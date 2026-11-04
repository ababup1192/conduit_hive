// JuiceDoc — conduit_hive.juice.json（撃った・倒した時の手応え: camera shake・撃った時のカメラの跳ね・hit marker と kill marker・
// 倒した敵が吹っ飛ぶ強さ・弾ける（gib）条件と肉片の飛び方・hit stop）の宣言ドキュメント層。
// 吹っ飛ぶ・弾ける・揺らす規則はコード（Knockback・Gibs・CameraShake・World）で、ここは調整する数だけ。
// 長さは m・角度は度・時間は秒・速さは 1 秒あたり。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod JuiceDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    /// 武器ごとの値（拳銃・散弾銃・連射銃）。
    pub type alias PerWeapon = { pistol = Float64, shotgun = Float64, rifle = Float64 }

    /// camera shake（JSON では武器ごとの強さも shake の塊の pistol・shotgun・rifle）: 出来事ごとの強さ（0..1。足して 1 で止める）・強さ 1 の揺れの角（度）・揺れの速さ（回/秒）・強さが半分に減るまで（秒）。
    pub type alias Shake = { fire = PerWeapon, kill = Float64, gib = Float64, hurt = Float64, maxDeg = Float64, frequency = Float64, halfLife = Float64 }

    /// 撃った時のカメラの跳ね: 目が後ろへ下がる距離（m）と、戻るまで（秒）。JSON では kick の 1 つの塊（武器の欄と recover）。
    pub type alias Kick = { back = PerWeapon, recover = Float64 }

    /// 照準の印: 当てた印と倒した印を出す長さ・大きさ（design px）・倒した印の色。
    pub type alias Marker = { hitSeconds = Float64, killSeconds = Float64, hitSize = Float64, killSize = Float64, killColor = Color }

    /// 倒した敵が吹っ飛ぶ: 武器ごとの横の速さ（m/秒。JSON では fling の塊の pistol・shotgun・rifle）・近い時に強める距離と倍率（0 m で倍率・距離の端で 1 倍）・上への速さ・
    /// 下へ引く強さ・床を滑る時の減り方（m/秒²）・横に回る速さ（度/秒）・飛んでいる間に後ろへ反る角（度）。
    pub type alias Fling = { speed = PerWeapon, closeRange = Float64, closeBoost = Float64, lift = Float64, gravity = Float64,
                             friction = Float64, spin = Float64, tilt = Float64 }

    /// 弾ける（gib。JSON では条件と数の gib・飛び方の gibPieces・光の gibLight の 3 つの塊）: 条件 3 つ（散弾銃の近距離・頭への強い一撃・余剰ダメージ）とそれぞれの確率、肉片の数と飛び方、弾けた瞬間の光。
    pub type alias Gib = {
        shotgunRange = Float64,
        shotgunChance = Float64,
        // 1 発で頭に受けた威力がこの値以上。
        headDamage = Float64,
        headChance = Float64,
        // 倒れた時に体力を超えた分がこの値以上。
        overkill = Float64,
        overkillChance = Float64,
        countMin = Int32,
        countMax = Int32,
        // 肉片の大きさの倍率（glb の大きさに掛ける）と、発光の筋の明るさの倍率（glb の強さに掛ける）。
        scale = Float64,
        glow = Float64,
        // 飛び出す速さ（撃たれた向きへの速さと、まわりへ散る速さ）・上への速さ・回る速さ（度/秒）。
        speed = Float64,
        scatter = Float64,
        lift = Float64,
        spin = Float64,
        gravity = Float64,
        // 床で跳ねた時に残る縦の速さの割合と、横の速さの割合。
        bounce = Float64,
        friction = Float64,
        // 残る長さと、その終わりに縮んで消える長さ。
        life = Float64,
        fade = Float64,
        // 同時に残す肉片の上限（越えたら古い物から消す）。
        limit = Int32,
        // 弾けた瞬間の点光源（強さ・届く距離・長さ・同時に点ける数）。
        lightColor = Color,
        lightIntensity = Float64,
        lightRange = Float64,
        lightSeconds = Float64,
        lights = Int32
    }

    /// hit stop: 1 コマにこの数以上倒した時と、群れの最後の 1 体を倒した時に、遊びの時計を止めて遅く流す（秒は実時間）。
    pub type alias HitStop = { multiKill = Int32, freeze = Float64, slow = Float64, slowScale = Float64, ramp = Float64,
                               lastFreeze = Float64, lastSlow = Float64 }

    pub type alias Rec = { version = Int32, shake = Shake, kick = Kick, marker = Marker, fling = Fling, gib = Gib, hitStop = HitStop }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.juice.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// 武器 w の値。
    pub def ofWeapon(w: WeaponsDoc.Weapon, p: PerWeapon): Float64 = match w {
        case WeaponsDoc.Weapon.Pistol  => p#pistol
        case WeaponsDoc.Weapon.Shotgun => p#shotgun
        case WeaponsDoc.Weapon.Rifle   => p#rifle
    }

    /// コード側の既定値（assets/conduit_hive.juice.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  shake = { fire = { pistol = 0.22, shotgun = 0.6, rifle = 0.12 }, kill = 0.18, gib = 0.45, hurt = 0.35,
                            maxDeg = 1.6, frequency = 17.0, halfLife = 0.08 },
                  kick = { back = { pistol = 0.025, shotgun = 0.07, rifle = 0.012 }, recover = 0.14 },
                  marker = { hitSeconds = 0.16, killSeconds = 0.42, hitSize = 6.0, killSize = 9.0, killColor = hx("#ff7a2a") },
                  fling = { speed = { pistol = 2.4, shotgun = 4.2, rifle = 1.8 }, closeRange = 5.0, closeBoost = 2.2, lift = 3.2,
                            gravity = 14.0, friction = 9.0, spin = 140.0, tilt = 28.0 },
                  gib = { shotgunRange = 4.5, shotgunChance = 0.8, headDamage = 45.0, headChance = 0.35, overkill = 90.0, overkillChance = 0.6,
                          countMin = 8, countMax = 12, scale = 1.5, glow = 4.0, speed = 5.5, scatter = 3.5, lift = 5.5, spin = 720.0, gravity = 14.0,
                          bounce = 0.35, friction = 0.55, life = 3.5, fade = 0.5, limit = 36,
                          lightColor = hx("#ff8a3c"), lightIntensity = 2.0, lightRange = 4.0, lightSeconds = 0.12, lights = 2 },
                  hitStop = { multiKill = 3, freeze = 0.045, slow = 0.1, slowScale = 0.3, ramp = 0.08, lastFreeze = 0.09, lastSlow = 0.3 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(key: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    def perWeaponOr(d: PerWeapon, o: Map[String, Json]): PerWeapon =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { pistol = f("pistol", d#pistol), shotgun = f("shotgun", d#shotgun), rifle = f("rifle", d#rifle) }

    def shakeOr(d: Shake, o: Map[String, Json]): Shake =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { fire = perWeaponOr(d#fire, o), kill = f("kill", d#kill), gib = f("gib", d#gib), hurt = f("hurt", d#hurt),
          maxDeg = f("maxDeg", d#maxDeg), frequency = f("frequency", d#frequency), halfLife = f("halfLife", d#halfLife) }

    def kickOr(d: Kick, o: Map[String, Json]): Kick =
        { back = perWeaponOr(d#back, o), recover = JsonCodec.floatOr("recover", d#recover, o) }

    def markerOr(d: Marker, o: Map[String, Json]): Marker =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { hitSeconds = f("hitSeconds", d#hitSeconds), killSeconds = f("killSeconds", d#killSeconds), hitSize = f("hitSize", d#hitSize),
          killSize = f("killSize", d#killSize), killColor = colorOr(d#killColor, "killColor", o) }

    def flingOr(d: Fling, o: Map[String, Json]): Fling =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { speed = perWeaponOr(d#speed, o), closeRange = f("closeRange", d#closeRange), closeBoost = f("closeBoost", d#closeBoost),
          lift = f("lift", d#lift), gravity = f("gravity", d#gravity), friction = f("friction", d#friction), spin = f("spin", d#spin), tilt = f("tilt", d#tilt) }

    def gibOr(d: Gib, o: Map[String, Json]): Gib =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        let i = (k, v) -> JsonCodec.intOr(k, v, o);
        { shotgunRange = f("shotgunRange", d#shotgunRange), shotgunChance = f("shotgunChance", d#shotgunChance),
          headDamage = f("headDamage", d#headDamage), headChance = f("headChance", d#headChance),
          overkill = f("overkill", d#overkill), overkillChance = f("overkillChance", d#overkillChance),
          countMin = i("countMin", d#countMin), countMax = i("countMax", d#countMax), scale = f("scale", d#scale), glow = f("glow", d#glow), speed = f("speed", d#speed), scatter = f("scatter", d#scatter),
          lift = f("lift", d#lift), spin = f("spin", d#spin), gravity = f("gravity", d#gravity), bounce = f("bounce", d#bounce),
          friction = f("friction", d#friction), life = f("life", d#life), fade = f("fade", d#fade), limit = i("limit", d#limit),
          lightColor = colorOr(d#lightColor, "lightColor", o), lightIntensity = f("lightIntensity", d#lightIntensity),
          lightRange = f("lightRange", d#lightRange), lightSeconds = f("lightSeconds", d#lightSeconds), lights = i("lights", d#lights) }

    def hitStopOr(d: HitStop, o: Map[String, Json]): HitStop =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { multiKill = JsonCodec.intOr("multiKill", d#multiKill, o), freeze = f("freeze", d#freeze), slow = f("slow", d#slow),
          slowScale = f("slowScale", d#slowScale), ramp = f("ramp", d#ramp), lastFreeze = f("lastFreeze", d#lastFreeze), lastSlow = f("lastSlow", d#lastSlow) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  shake = shakeOr(d#shake, objectOf("shake", root)), kick = kickOr(d#kick, objectOf("kick", root)),
                  marker = markerOr(d#marker, objectOf("marker", root)), fling = flingOr(d#fling, objectOf("fling", root)),
                  gib = gibOr(d#gib, List.foldLeft((acc, k) -> Map.union(acc, objectOf(k, root)), Map.empty(), "gib" :: "gibPieces" :: "gibLight" :: Nil)), hitStop = hitStopOr(d#hitStop, objectOf("hitStop", root)) })
}
