// Particles3dDoc — conduit_hive.particles3d.json（3D の粒: 武器ごとのマズルフラッシュ・当たった所の火花と煙・撃った瞬間の灯り・敵の体液・
// 弾けた時の体液と衝撃の輪・projectile の光・ranged の溜めの光・連射銃の曳光弾）の宣言ドキュメント層。
// engine の fx.json（2D の FxDoc）とは別の物。出し方・動かし方・消し方はコード（Particles3d）で、ここは数と色だけ。
// 長さは m・角度は度・時間は秒・速さは 1 秒あたり。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod Particles3dDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    /// 粒の出し方 1 種類。count = 1 回に出す数。
    pub type alias Burst = {
        count = Int32,
        // 寿命（秒）。粒ごとに寿命 × (1 − lifeJitter) から寿命までに散らす。
        life = Float64,
        lifeJitter = Float64,
        // 飛び出す速さ（m/秒。粒ごとに半分からこの値まで）・向きの広がり（度。出す向きから外れる角の最大）。
        speed = Float64,
        spread = Float64,
        // 大きさ（m）・寿命の終わりの大きさの倍率（1 未満で縮み・1 を超えて広がる）・横の長さの倍率（1 で丸・2 で横に 2 倍）・下へ引く強さ（m/秒²。負で上る）。
        size = Float64,
        grow = Float64,
        aspect = Float64,
        gravity = Float64,
        // 色（光を当てずにこの色で光る）と、その明るさの線形の倍率（1 を超えるとブルームが掛かる）。
        color = Color,
        intensity = Float64
    }

    /// 撃った瞬間だけ点ける灯り（ステージとビューモデルの両方の場面に 1 本ずつ）。
    pub type alias Flash = { color = Color, intensity = Float64, range = Float64, life = Float64 }

    /// ranged が吐く projectile の見え方: 頭の光る粒の大きさ（m）・色・明るさの線形の倍率と、粒に付ける点光源の強さと届く距離、
    /// 進む向きの後ろへ伸びる光る尾（長さと芯の太さ m・芯の色・にじむ外側の太さ（芯の何倍）と濃さ・外側がゆらめく速さ（1 秒の回数））。
    pub type alias Glow = { size = Float64, color = Color, intensity = Float64, lightIntensity = Float64, lightRange = Float64,
                            length = Float64, width = Float64, core = Color, glowWidth = Float64, glowAlpha = Float64, wobble = Float64 }

    /// 武器ごとのマズルフラッシュ（JSON では muzzle が拳銃・muzzleShotgun・muzzleRifle）。
    pub type alias Muzzles = { pistol = Burst, shotgun = Burst, rifle = Burst }

    /// ranged の溜めの光: 口に出す光る玉の大きさ（m。溜め切った時）・色・明るさの線形の倍率。
    pub type alias Charge = { size = Float64, color = Color, intensity = Float64 }

    /// 武器 1 つの曳光弾: 何発に 1 発か（0 で出さない）・1 回に出す本数（散弾の粒の当たった所へ前から）・飛ぶ速さ（m/秒）・光る芯の長さと太さ（m）・色・
    /// 明るさの線形の倍率・濃さ（0..1）・同時に飛ぶ数の上限・にじむ外側の太さ（芯の何倍か）と濃さ（0..1。0 で外側を描かない）。
    pub type alias Tracer = { every = Int32, count = Int32, speed = Float64, length = Float64, width = Float64, color = Color, intensity = Float64,
                              alpha = Float64, limit = Int32, glowWidth = Float64, glowAlpha = Float64 }

    /// 武器ごとの曳光弾（JSON では tracer が連射銃・tracerPistol・tracerShotgun）。
    pub type alias Tracers = { pistol = Tracer, shotgun = Tracer, rifle = Tracer }

    /// 武器 w の曳光弾。
    pub def tracerOf(r: Rec, w: WeaponsDoc.Weapon): Tracer = match w {
        case WeaponsDoc.Weapon.Pistol  => r#tracers#pistol
        case WeaponsDoc.Weapon.Shotgun => r#tracers#shotgun
        case WeaponsDoc.Weapon.Rifle   => r#tracers#rifle
    }

    /// 爆発の火の玉の塊（形で描く）: puff = 塊 1 つずつの出し方（color = 真ん中の殻の橙）・hot = 中心の白に近い色・cool = 外の殻の冷めた暗い赤。
    pub type alias Fireball = { puff = Burst, hot = Color, cool = Color }

    /// 手榴弾の爆発（JSON は conduit_hive.blastfx.json）: 真ん中の一瞬の光・床を走る衝撃の輪・上る煙・飛び散る火花と破片・
    /// 膨らんで崩れる火の玉の塊・床の焦げ跡（scorch の intensity = 焦げの中の残り火の明るさ）。
    pub type alias Blast = { flash = Burst, ring = Burst, smoke = Burst, debris = Burst, fireball = Fireball, scorch = Burst }

    /// limit = 同時に出ている粒の上限（越えたら古い物から消す）・muzzleFlicker = マズルフラッシュの形が次の形へ替わるまでの秒（0 で替えない）。
    /// muzzleSmoke = 撃った後に銃口からうっすら上る煙。
    pub type alias Rec = { version = Int32, muzzle = Muzzles, muzzleFlicker = Float64, muzzleSmoke = Burst, spark = Burst, smoke = Burst, light = Flash, ichor = Burst, gore = Burst,
                           ring = Burst, spit = Glow, charge = Charge, tracers = Tracers, blast = Blast, limit = Int32 }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.particles3d.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/conduit_hive.particles3d.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  muzzle = { pistol  = { count = 0, life = 0.05, lifeJitter = 0.3, speed = 0.2, spread = 5.0, size = 0.1, grow = 1.4, aspect = 1.0, gravity = 0.0, color = hx("#fff2cc"), intensity = 4.0 },
                             shotgun = { count = 0, life = 0.065, lifeJitter = 0.3, speed = 0.3, spread = 6.0, size = 0.17, grow = 1.5, aspect = 1.3, gravity = 0.0, color = hx("#ffeec0"), intensity = 4.5 },
                             rifle   = { count = 0, life = 0.04, lifeJitter = 0.3, speed = 0.2, spread = 4.0, size = 0.085, grow = 1.3, aspect = 1.0, gravity = 0.0, color = hx("#fff4d6"), intensity = 4.0 } },
                  spark  = { count = 22, life = 0.4, lifeJitter = 0.5, speed = 7.5, spread = 75.0, size = 0.08, grow = 0.5, aspect = 1.0, gravity = 9.8, color = hx("#ffc070"), intensity = 6.0 },
                  smoke  = { count = 3, life = 0.7, lifeJitter = 0.4, speed = 0.6, spread = 50.0, size = 0.16, grow = 2.2, aspect = 1.0, gravity = -1.2, color = hx("#4a4f57"), intensity = 0.6 },
                  light  = { color = hx("#ffc890"), intensity = 1.8, range = 6.5, life = 0.07 },
                  ichor  = { count = 7, life = 0.55, lifeJitter = 0.5, speed = 4.5, spread = 55.0, size = 0.035, grow = 0.5, aspect = 1.0, gravity = 9.8, color = hx("#ff7a2a"), intensity = 2.0 },
                  gore   = { count = 12, life = 0.8, lifeJitter = 0.5, speed = 7.0, spread = 180.0, size = 0.03, grow = 0.5, aspect = 1.0, gravity = 9.8, color = hx("#ff6a20"), intensity = 2.2 },
                  ring   = { count = 1, life = 0.15, lifeJitter = 0.0, speed = 0.0, spread = 0.0, size = 0.3, grow = 5.0, aspect = 1.0, gravity = 0.0, color = hx("#d8602a"), intensity = 0.9 },
                  spit   = { size = 0.14, color = hx("#ffb040"), intensity = 6.0, lightIntensity = 1.0, lightRange = 4.0,
                             length = 0.9, width = 0.06, core = hx("#fff0a0"), glowWidth = 3.5, glowAlpha = 0.3, wobble = 14.0 },
                  muzzleSmoke = { count = 3, life = 0.6, lifeJitter = 0.4, speed = 0.35, spread = 40.0, size = 0.05, grow = 3.0, aspect = 1.0, gravity = -0.6, color = hx("#5a5d62"), intensity = 0.35 },
                  charge = { size = 0.42, color = hx("#ff8a3c"), intensity = 5.0 },
                  tracers = { pistol  = { every = 1, count = 1, speed = 90.0, length = 2.5, width = 0.02, color = hx("#ffc070"), intensity = 3.0, alpha = 0.9, limit = 4, glowWidth = 4.0, glowAlpha = 0.25 },
                              shotgun = { every = 1, count = 5, speed = 80.0, length = 1.4, width = 0.012, color = hx("#ffa850"), intensity = 3.0, alpha = 0.85, limit = 12, glowWidth = 4.0, glowAlpha = 0.2 },
                              rifle   = { every = 1, count = 1, speed = 110.0, length = 3.5, width = 0.022, color = hx("#ffb060"), intensity = 3.0, alpha = 0.9, limit = 8, glowWidth = 4.0, glowAlpha = 0.25 } },
                  muzzleFlicker = 0.016,
                  blast = { flash  = { count = 5, life = 0.1, lifeJitter = 0.4, speed = 1.5, spread = 180.0, size = 0.7, grow = 1.6, aspect = 1.0, gravity = 0.0, color = hx("#ffe2b0"), intensity = 2.0 },
                            ring   = { count = 1, life = 0.42, lifeJitter = 0.0, speed = 0.0, spread = 0.0, size = 0.6, grow = 11.0, aspect = 1.0, gravity = 0.0, color = hx("#ff9a50"), intensity = 1.6 },
                            smoke  = { count = 30, life = 2.6, lifeJitter = 0.4, speed = 1.6, spread = 75.0, size = 0.8, grow = 3.4, aspect = 1.0, gravity = -0.9, color = hx("#6e6862"), intensity = 1.0 },
                            debris = { count = 50, life = 0.7, lifeJitter = 0.5, speed = 12.0, spread = 80.0, size = 0.07, grow = 0.5, aspect = 1.0, gravity = 9.8, color = hx("#ffb060"), intensity = 3.0 },
                            fireball = { puff = { count = 9, life = 0.75, lifeJitter = 0.35, speed = 4.5, spread = 75.0, size = 0.9, grow = 1.35, aspect = 1.0, gravity = -4.0, color = hx("#ff7a26"), intensity = 2.2 },
                                         hot = hx("#fff0c8"), cool = hx("#6e1a0c") },
                            scorch = { count = 1, life = 8.0, lifeJitter = 0.0, speed = 0.0, spread = 0.0, size = 2.2, grow = 1.0, aspect = 1.0, gravity = 0.0, color = hx("#0d0a09"), intensity = 1.0 } },
                  limit = 320 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    /// 敵の側の粒（体液・弾けた時の体液と輪・projectile の光・溜めの光）の Doc。形は同じで、path() と一緒に読む。
    pub def creaturePath(): String = "assets/conduit_hive.creaturefx.json"

    /// 爆発（手榴弾の中心の光・輪・煙・破片・火の玉の塊・焦げ跡）の Doc。粒の形は同じで、path() と一緒に読む。
    pub def blastPath(): String = "assets/conduit_hive.blastfx.json"

    /// 武器の粒の Doc（p）と敵の粒の Doc（creaturePath）と爆発の粒の Doc（blastPath）を 1 つの値に読む（読めない物はその欄だけ既定）。
    // WhyNot: 1 つの JSON に戻さない — 17 の塊が Studio の 17 枚のタブになり、武器の手触りと敵の見え方と爆発の見え方を直す時が違う。
    pub def load(p: String): Doc \ Fs.FileRead = fromRoot(Map.union(rootOf(p), Map.union(rootOf(creaturePath()), rootOf(blastPath()))))

    def rootOf(p: String): Map[String, Json] \ Fs.FileRead =
        DocJson.readJson(p) |> Result.toOption |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    def objectOf(key: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    /// 粒の出し方 1 種類（無い欄はその欄だけ既定）。
    def burstOr(fallback: Burst, key: String, root: Map[String, Json]): Burst =
        let o = objectOf(key, root);
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { count = JsonCodec.intOr("count", fallback#count, o), life = f("life", fallback#life), lifeJitter = f("lifeJitter", fallback#lifeJitter),
          speed = f("speed", fallback#speed), spread = f("spread", fallback#spread), size = f("size", fallback#size),
          grow = f("grow", fallback#grow), aspect = f("aspect", fallback#aspect),
          gravity = f("gravity", fallback#gravity), color = colorOr(fallback#color, "color", o), intensity = f("intensity", fallback#intensity) }

    /// 火の玉の塊（出し方の欄は burstOr と同じ・hot と cool の色だけ足す）。
    def fireballOr(fallback: Fireball, key: String, root: Map[String, Json]): Fireball =
        let o = objectOf(key, root);
        { puff = burstOr(fallback#puff, key, root), hot = colorOr(fallback#hot, "hot", o), cool = colorOr(fallback#cool, "cool", o) }

    def flashOr(fallback: Flash, key: String, root: Map[String, Json]): Flash =
        let o = objectOf(key, root);
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { color = colorOr(fallback#color, "color", o), intensity = f("intensity", fallback#intensity),
          range = f("range", fallback#range), life = f("life", fallback#life) }

    def glowOr(fallback: Glow, key: String, root: Map[String, Json]): Glow =
        let o = objectOf(key, root);
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { size = f("size", fallback#size), color = colorOr(fallback#color, "color", o), intensity = f("intensity", fallback#intensity),
          lightIntensity = f("lightIntensity", fallback#lightIntensity), lightRange = f("lightRange", fallback#lightRange),
          length = f("length", fallback#length), width = f("width", fallback#width), core = colorOr(fallback#core, "core", o),
          glowWidth = f("glowWidth", fallback#glowWidth), glowAlpha = f("glowAlpha", fallback#glowAlpha), wobble = f("wobble", fallback#wobble) }

    def chargeOr(fallback: Charge, key: String, root: Map[String, Json]): Charge =
        let o = objectOf(key, root);
        { size = JsonCodec.floatOr("size", fallback#size, o), color = colorOr(fallback#color, "color", o), intensity = JsonCodec.floatOr("intensity", fallback#intensity, o) }

    def tracerOr(fallback: Tracer, key: String, root: Map[String, Json]): Tracer =
        let o = objectOf(key, root);
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { every = JsonCodec.intOr("every", fallback#every, o), count = JsonCodec.intOr("count", fallback#count, o), speed = f("speed", fallback#speed),
          length = f("length", fallback#length), width = f("width", fallback#width), color = colorOr(fallback#color, "color", o),
          intensity = f("intensity", fallback#intensity), alpha = f("alpha", fallback#alpha), limit = JsonCodec.intOr("limit", fallback#limit, o),
          glowWidth = f("glowWidth", fallback#glowWidth), glowAlpha = f("glowAlpha", fallback#glowAlpha) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  muzzle = { pistol = burstOr(d#muzzle#pistol, "muzzle", root), shotgun = burstOr(d#muzzle#shotgun, "muzzleShotgun", root),
                             rifle = burstOr(d#muzzle#rifle, "muzzleRifle", root) },
                  spark = burstOr(d#spark, "spark", root), smoke = burstOr(d#smoke, "smoke", root), light = flashOr(d#light, "light", root),
                  ichor = burstOr(d#ichor, "ichor", root), gore = burstOr(d#gore, "gore", root), ring = burstOr(d#ring, "ring", root),
                  muzzleFlicker = JsonCodec.floatOr("muzzleFlicker", d#muzzleFlicker, root), muzzleSmoke = burstOr(d#muzzleSmoke, "muzzleSmoke", root),
                  spit = glowOr(d#spit, "spit", root), charge = chargeOr(d#charge, "charge", root),
                  tracers = { pistol = tracerOr(d#tracers#pistol, "tracerPistol", root), shotgun = tracerOr(d#tracers#shotgun, "tracerShotgun", root),
                              rifle = tracerOr(d#tracers#rifle, "tracer", root) },
                  blast = { flash = burstOr(d#blast#flash, "blastFlash", root), ring = burstOr(d#blast#ring, "blastRing", root),
                            smoke = burstOr(d#blast#smoke, "blastSmoke", root), debris = burstOr(d#blast#debris, "blastDebris", root),
                            fireball = fireballOr(d#blast#fireball, "blastFireball", root), scorch = burstOr(d#blast#scorch, "blastScorch", root) },
                  limit = JsonCodec.intOr("limit", d#limit, root) })
}
