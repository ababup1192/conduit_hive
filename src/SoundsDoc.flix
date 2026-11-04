// SoundsDoc — conduit_hive.sounds.json（音の鳴らし方: 変化の数・音ごとの量・薬莢と跳弾・敵の唸りと叫び・部屋ごとの環境音の混ぜ方）の宣言ドキュメント層。
// どの出来事にどの音を当てるか・変化の選び方・距離から量を出す式はコード（Sounds）。バスとダッキングと cooldown は conduit_hive.mixer.json。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod SoundsDoc {
    use fge::{AudioMixer, DocJson, JsonCodec}
    use Util.Json.Json

    /// 環境音の 3 本のループ（amb_machine・amb_vent・amb_pipes）の量（0〜1）。
    pub type alias Ambience = { machine = Float64, vent = Float64, pipes = Float64 }

    /// 武器ごとの秒（撃ってから薬莢が床で鳴るまで）。
    pub type alias PerWeapon = { pistol = Float64, shotgun = Float64, rifle = Float64 }

    pub type alias Rec = {
        version = Int32,
        // 同じ種類（名前の末尾の _数字 を除いた頭）の音を 1 コマに鳴らす数の上限。
        maxPerFamily = Int32,
        // 撃ってから薬莢が床で鳴るまで（秒）・散弾銃を撃ってから先台を引くまで（秒）。
        shellDelay = PerWeapon,
        pumpDelay = Float64,
        // 弾が壁や柱に当たった 1 回が跳弾の音を鳴らす割合（0〜1）。
        ricochetChance = Float64,
        // 唸りを鳴らす近い敵の数（変化の数まで）・この距離までは量 1・この距離で 0（m）・量の倍率・高さのばらつき（1 からの差）。
        growlVoices = Int32,
        growlNear = Float64,
        growlFar = Float64,
        growlVolume = Float64,
        growlPitchSpread = Float64,
        // 攻撃を始めた敵が叫ぶ割合（0〜1）・叫びが聞こえる距離（m）。
        screamChance = Float64,
        screamRange = Float64,
        // 環境音の混ぜ方: 足元の周りのこの半径（m）の区画を混ぜて、戸口で急に替わらないようにする・部屋と通路の既定・区画ごとの上書き。
        ambienceRadius = Float64,
        // タイトルとクリアの画面で流す環境音の量（部屋の既定に掛ける倍率。無音の画面を出さない）。
        menuAmbience = Float64,
        room = Ambience,
        corridor = Ambience,
        zones = Map[Char, Ambience],
        // 変化の数（名前の頭 → 1..n の n。project.json の sounds の <頭>_<番号> と同じ数）。
        variants = Map[String, Int32],
        // 音ごとの量（名前の頭 → 倍率。素材の大きさの違いをそろえる。バスの音量に掛かる）。
        levels = Map[String, Float64]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.sounds.json"

    /// コード側の既定値（assets/conduit_hive.sounds.json と同じ値から出発する）。
    pub def defaults(): Doc = Doc.Doc({
        version = 1, maxPerFamily = 2,
        shellDelay = { pistol = 0.3, shotgun = 0.6, rifle = 0.25 }, pumpDelay = 0.3, ricochetChance = 0.3,
        growlVoices = 3, growlNear = 3.0, growlFar = 20.0, growlVolume = 0.8, growlPitchSpread = 0.08,
        screamChance = 0.4, screamRange = 18.0,
        ambienceRadius = 3.0, menuAmbience = 0.35,
        room = { machine = 0.8, vent = 0.4, pipes = 0.3 }, corridor = { machine = 0.3, vent = 0.8, pipes = 0.5 }, zones = Map.empty(),
        variants = Map#{ "shot_pistol" => 3, "shot_shotgun" => 2, "shot_rifle" => 4, "shell" => 3, "ricochet" => 3,
                         "enemy_growl" => 3, "enemy_scream" => 3, "enemy_swing" => 2, "enemy_hit" => 3, "enemy_down" => 2,
                         "spit_burst" => 2, "player_hurt" => 3, "step_metal" => 4 },
        levels = Map#{ "shot_rifle" => 0.5 }
    })

    /// 音ごとの量（levels）を足したミキサー: 量を持つ名前の頭ごとに、その頭が流れるバスの子のバス（名前 = 親.頭・音量 = 親 × 量）を足し、
    /// その頭の音を子へ流す。ダッキングは親を鳴らす側・下げられる側に書けば子にも効き、スナップショットの音量も子へ量を掛けて写す。
    /// WhyNot: 素材の wav の大きさを書き換えてそろえない — 量を Doc に置くと、保存したその場で聞き比べて直せる。
    pub def mixerOf(base: AudioMixer.Mixer, d: Doc): AudioMixer.Mixer =
        let children = rec(d)#levels |> Map.toList |> List.map(e -> {
            let (prefix, volume) = e;
            let parent = AudioMixer.busOf(base, prefix);
            { prefix = prefix, volume = volume, parent = parent, name = "${parent}.${prefix}" }
        });
        let childrenOf = bus -> children |> List.filter(c -> c#parent == bus) |> List.map(c -> c#name);
        let buses = children |> List.map(c -> {
            let p = AudioMixer.getBus(base, c#parent);
            { name = c#name, volume = p#volume * c#volume, lowpassGainHF = p#lowpassGainHF }
        });
        let routes = children |> List.map(c -> { bus = c#name, prefixes = c#prefix :: Nil });
        let ducks = base#ducks |> List.flatMap(duck -> {
            let by = List.append(duck#by, duck#by |> List.flatMap(childrenOf));
            (duck#bus :: childrenOf(duck#bus)) |> List.map(bus -> { bus = bus, by = by | duck })
        });
        let snapshots = base#snapshots |> List.map(snap -> {
            let scaled = snap#buses |> List.flatMap(o -> children |> List.filter(c -> c#parent == o#name)
                |> List.map(c -> { name = c#name, volume = o#volume |> Option.map(v -> v * c#volume), lowpassGainHF = o#lowpassGainHF }));
            { buses = List.append(snap#buses, scaled) | snap }
        });
        // WhyNot: 子の routes を後ろに置かない — 親と同じ長さの頭は先に並んだ方が勝つ（AudioMixer.busOf）。
        { buses = List.append(base#buses, buses), routes = List.append(routes, base#routes), ducks = ducks, snapshots = snapshots | base }

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// 区画の文字（1 文字の鍵だけ）。
    def charOf(text: String): Option[Char] = if (String.length(text) == 1) String.charAt(0, text) |> Some else None

    def ambienceOf(fallback: Ambience, o: Map[String, Json]): Ambience =
        { machine = JsonCodec.floatOr("machine", fallback#machine, o), vent = JsonCodec.floatOr("vent", fallback#vent, o),
          pipes = JsonCodec.floatOr("pipes", fallback#pipes, o) }

    /// 名前 → 中身の一覧（中身の読めない行だけ落とす。欄が無ければ None）。
    def catalogOf(key: String, row: Json -> Option[a], root: Map[String, Json]): Option[List[(String, a)]] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(o -> o |> Map.toList |> List.filterMap(e -> { let (name, v) = e; row(v) |> Option.map(x -> (name, x)) }))

    /// 入れ子のオブジェクトの欄（無い・オブジェクトでなければ fallback）。
    def objectOr(key: String, fallback: a, root: Map[String, Json], read: Map[String, Json] -> a): a =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.map(read) |> Option.getWithDefault(fallback)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (k, v) -> JsonCodec.floatOr(k, v, root);
        let shell = objectOr("shellDelay", d#shellDelay, root, o ->
            { pistol = JsonCodec.floatOr("pistol", d#shellDelay#pistol, o), shotgun = JsonCodec.floatOr("shotgun", d#shellDelay#shotgun, o),
              rifle = JsonCodec.floatOr("rifle", d#shellDelay#rifle, o) });
        let zones = catalogOf("zones", v -> JsonCodec.expectObject(v) |> Option.map(ambienceOf(d#corridor)), root)
            |> Option.map(rows -> rows |> List.filterMap(e -> { let (k, a) = e; charOf(k) |> Option.map(c -> (c, a)) }) |> List.toMap)
            |> Option.getWithDefault(d#zones);
        let variants = catalogOf("variants", v -> JsonCodec.expectObject(v) |> Option.map(o -> JsonCodec.intOr("count", 1, o)), root)
            |> Option.map(List.toMap) |> Option.getWithDefault(d#variants);
        let levels = catalogOf("levels", v -> JsonCodec.expectObject(v) |> Option.map(o -> JsonCodec.floatOr("volume", 1.0, o)), root)
            |> Option.map(List.toMap) |> Option.getWithDefault(d#levels);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), maxPerFamily = JsonCodec.intOr("maxPerFamily", d#maxPerFamily, root),
                  shellDelay = shell, pumpDelay = f("pumpDelay", d#pumpDelay), ricochetChance = f("ricochetChance", d#ricochetChance),
                  growlVoices = JsonCodec.intOr("growlVoices", d#growlVoices, root), growlNear = f("growlNear", d#growlNear), growlFar = f("growlFar", d#growlFar),
                  growlVolume = f("growlVolume", d#growlVolume), growlPitchSpread = f("growlPitchSpread", d#growlPitchSpread),
                  screamChance = f("screamChance", d#screamChance), screamRange = f("screamRange", d#screamRange),
                  ambienceRadius = f("ambienceRadius", d#ambienceRadius), menuAmbience = f("menuAmbience", d#menuAmbience),
                  room = objectOr("room", d#room, root, ambienceOf(d#room)), corridor = objectOr("corridor", d#corridor, root, ambienceOf(d#corridor)),
                  zones = zones, variants = variants, levels = levels })
}
