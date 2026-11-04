// SpawnsDoc — conduit_hive.spawns.json（区画ごとの wave・同時に生きている数の上限・湧く間隔と距離）の宣言ドキュメント層。
// 迷路の Doc の spawn の印は湧く所だけを持ち、何がいつ何体湧くかはここが正。
// どの印から湧かせるか・いつ次の wave へ進むか・上限で待たせる規則はコード（Spawner・Horde）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod SpawnsDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// wave 1 つ: 入ると始まる区画（部屋か通路の文字）・melee と ranged の数・湧く印の区画（None = zone と同じ）・
    /// 前の wave が始まってからこの秒が過ぎたら始まる（最初の wave は区画に入ってから）・
    /// その区画の残り（生きている数 + 湧くのを待っている数）がこの数以下になったら始まる（最初の wave には効かない）。
    pub type alias Wave = { zone = Char, melee = Int32, ranged = Int32, source = Option[Char], after = Float64, whenLeft = Int32 }

    /// minDistance = プレイヤーからこの距離（m）より近い印からは湧かせない・maxAlive = 同時に生きている敵の上限（倒れた体は数えない）・
    /// spawnInterval = 1 体湧いてから次が湧くまで（秒。全部の区画で共有）・scatter = 印のマスの中で散らす幅（m）・waves = wave の並び（区画ごとに並びの順）。
    pub type alias Rec = { version = Int32, minDistance = Float64, maxAlive = Int32, spawnInterval = Float64, scatter = Float64, waves = List[Wave] }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.spawns.json"

    def wave(zone: Char, melee: Int32, ranged: Int32): Wave = { zone = zone, melee = melee, ranged = ranged, source = None, after = 20.0, whenLeft = 4 }

    /// コード側の既定値（区画ごとの wave の並びは JSON が正なので、既定は最後の部屋 H の 2 wave だけ）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 2, minDistance = 14.0, maxAlive = 50, spawnInterval = 0.15, scatter = 2.4,
                  waves = wave('H', 20, 4) :: wave('H', 24, 6) :: Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// 区画の文字（1 文字の文字列だけ）。
    def charOf(text: String): Option[Char] = if (String.length(text) == 1) String.charAt(0, text) |> Some else None

    /// wave 1 つ（zone が 1 文字でなければ捨てる。ほかの無い欄はその欄だけ既定）。
    def waveOf(obj: Map[String, Json]): Option[Wave] =
        charOf(JsonCodec.stringOr("zone", "", obj)) |> Option.map(zone ->
            { zone = zone, melee = JsonCodec.intOr("melee", 0, obj), ranged = JsonCodec.intOr("ranged", 0, obj),
              source = charOf(JsonCodec.stringOr("from", "", obj)), after = JsonCodec.floatOr("after", 0.0, obj),
              whenLeft = JsonCodec.intOr("whenLeft", 0, obj) })

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let waves = Map.get("waves", root)
            |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
            |> Option.map(rows -> rows |> List.filterMap(waveOf))
            |> Option.getWithDefault(d#waves);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), minDistance = JsonCodec.floatOr("minDistance", d#minDistance, root),
                  maxAlive = JsonCodec.intOr("maxAlive", d#maxAlive, root), spawnInterval = JsonCodec.floatOr("spawnInterval", d#spawnInterval, root),
                  scatter = JsonCodec.floatOr("scatter", d#scatter, root), waves = waves })
}
