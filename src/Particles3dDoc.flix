// Particles3dDoc — conduit_hive.particles3d.json（3D の粒: マズルフラッシュ・当たった所の火花・撃った瞬間の灯り）の宣言ドキュメント層。
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
        // 大きさ（m。消える前に半分まで縮む）・下へ引く強さ（m/秒²）。
        size = Float64,
        gravity = Float64,
        // 色（光を当てずにこの色で光る）と、その明るさの線形の倍率（1 を超えるとブルームが掛かる）。
        color = Color,
        intensity = Float64
    }

    /// 撃った瞬間だけ点ける灯り（ステージとビューモデルの両方の場面に 1 本ずつ）。
    pub type alias Flash = { color = Color, intensity = Float64, range = Float64, life = Float64 }

    pub type alias Rec = { version = Int32, muzzle = Burst, spark = Burst, light = Flash }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.particles3d.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/conduit_hive.particles3d.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  muzzle = { count = 4, life = 0.06, lifeJitter = 0.3, speed = 0.6, spread = 25.0, size = 0.07, gravity = 0.0, color = hx("#ffd9a0"), intensity = 6.0 },
                  spark  = { count = 10, life = 0.35, lifeJitter = 0.5, speed = 6.0, spread = 70.0, size = 0.09, gravity = 9.8, color = hx("#ffc070"), intensity = 3.0 },
                  light  = { color = hx("#ffc890"), intensity = 4.0, range = 6.0, life = 0.05 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

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
          gravity = f("gravity", fallback#gravity), color = colorOr(fallback#color, "color", o), intensity = f("intensity", fallback#intensity) }

    def flashOr(fallback: Flash, key: String, root: Map[String, Json]): Flash =
        let o = objectOf(key, root);
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { color = colorOr(fallback#color, "color", o), intensity = f("intensity", fallback#intensity),
          range = f("range", fallback#range), life = f("life", fallback#life) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  muzzle = burstOr(d#muzzle, "muzzle", root), spark = burstOr(d#spark, "spark", root), light = flashOr(d#light, "light", root) })
}
