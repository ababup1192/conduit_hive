// LookDoc — conduit_hive.look.json（施設の色と光・霧・画面の仕上げ）の宣言ドキュメント層。
// 灰色の箱の面の色・光る筋・部屋の灯り・環境光・霧・トーンマップ・ブルーム・ビネット・粒の数だけを持つ。
// 面の組み方は MazeMesh・後処理の Pass の並べ方と式は PostView（コード）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod LookDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // 面の色: 壁（くすんだ鋼）・床（黒鉛）・天井。
        wallColor = Color,
        floorColor = Color,
        ceilingColor = Color,
        // 施設の光る筋（冷たいシアン）と、その明るさの線形の倍率（ブルームの効き）。
        stripColor = Color,
        stripIntensity = Float64,
        // 天井の灯り: 部屋の灯りの色・部屋と通路の強さ・灯具の間隔（マス）・届く距離の灯具の間隔に対する割合。
        roomLightColor = Color,
        roomLightIntensity = Float64,
        corridorLightIntensity = Float64,
        lampSpacing = Int32,
        roomLightReach = Float64,
        // どこにでも当たる光・上を向く面ほど明るくする量。
        ambient = Color,
        hemisphere = Float64,
        // 距離の霧（色・かかり始め・かかり切る距離 m）。かかり切る距離はカメラの写す奥行きの端と見える区画の距離も兼ねる。
        fogColor = Color,
        fogNear = Float64,
        fogFar = Float64,
        // トーンマップ: 露出（stop の数。1 増やすと 2 倍明るく）と白の点。
        exposure = Float64,
        whitePoint = Float64,
        // ブルーム: しきい（HDR の明るさ）・幅・強さ・ぼかしの半径・標本の数・Pass の倍率。
        bloomThreshold = Float64,
        bloomKnee = Float64,
        bloomStrength = Float64,
        bloomRadius = Float64,
        bloomTaps = Int32,
        bloomScale = Float64,
        // 場面の Pass の 1 画素の標本の数（MSAA。1 で掛けない）。
        msaaSamples = Int32,
        // 画面の仕上げ: ビネット・フィルムの粒。
        vignette = Float64,
        grain = Float64
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.look.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/conduit_hive.look.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, wallColor = hx("#5b636b"), floorColor = hx("#34383d"), ceilingColor = hx("#24272b"),
                  stripColor = hx("#5fe3f0"), stripIntensity = 6.0,
                  roomLightColor = hx("#cfe6ee"), roomLightIntensity = 2.2, corridorLightIntensity = 1.2, lampSpacing = 4, roomLightReach = 1.6,
                  ambient = hx("#2e3640"), hemisphere = 0.35,
                  fogColor = hx("#0b0e12"), fogNear = 10.0, fogFar = 56.0,
                  exposure = 0.0, whitePoint = 4.0,
                  bloomThreshold = 0.9, bloomKnee = 0.6, bloomStrength = 0.6, bloomRadius = 0.04, bloomTaps = 12, bloomScale = 0.5,
                  msaaSamples = 4, vignette = 0.35, grain = 0.015 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        let c = (key, fallback) -> colorOr(fallback, key, root);
        let i = (key, fallback) -> JsonCodec.intOr(key, fallback, root);
        Doc.Doc({ version = i("version", d#version),
                  wallColor = c("wallColor", d#wallColor), floorColor = c("floorColor", d#floorColor), ceilingColor = c("ceilingColor", d#ceilingColor),
                  stripColor = c("stripColor", d#stripColor), stripIntensity = f("stripIntensity", d#stripIntensity),
                  roomLightColor = c("roomLightColor", d#roomLightColor), roomLightIntensity = f("roomLightIntensity", d#roomLightIntensity),
                  corridorLightIntensity = f("corridorLightIntensity", d#corridorLightIntensity), lampSpacing = i("lampSpacing", d#lampSpacing),
                  roomLightReach = f("roomLightReach", d#roomLightReach),
                  ambient = c("ambient", d#ambient), hemisphere = f("hemisphere", d#hemisphere),
                  fogColor = c("fogColor", d#fogColor), fogNear = f("fogNear", d#fogNear), fogFar = f("fogFar", d#fogFar),
                  exposure = f("exposure", d#exposure), whitePoint = f("whitePoint", d#whitePoint),
                  bloomThreshold = f("bloomThreshold", d#bloomThreshold), bloomKnee = f("bloomKnee", d#bloomKnee),
                  bloomStrength = f("bloomStrength", d#bloomStrength), bloomRadius = f("bloomRadius", d#bloomRadius),
                  bloomTaps = i("bloomTaps", d#bloomTaps), bloomScale = f("bloomScale", d#bloomScale),
                  msaaSamples = i("msaaSamples", d#msaaSamples), vignette = f("vignette", d#vignette), grain = f("grain", d#grain) })
}
