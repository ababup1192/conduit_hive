// FpViewmodelDoc — conduit_hive.viewmodel.json（画面の手前に重ねる腕と銃 = ビューモデルの見え方と手触り）の宣言ドキュメント層。
// 画角・写す奥行き・歩く揺れ・見回しの遅れ・持ち替えの長さ・反動の戻り・光の倍率。光の色と向きはステージの look と灯りに合わせ、霧は掛けない。
// 長さは m・角度は度・時間は秒。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod FpViewmodelDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // ビューモデルだけの縦の画角（度）。ステージの画角を変えても腕の見え方は変わらない。
        fovY = Float64,
        // 写す奥行きの範囲（m）。near を小さくして銃口の手前が欠けないようにする。
        near = Float64,
        far = Float64,
        // 歩く時の揺れ: 左右と上下の幅（m。2 歩で左右に 1 往復・1 歩で上下に 1 往復。頭の上下と同じ拍）。
        bobSide = Float64,
        bobLift = Float64,
        // 見回した時の遅れ: 回した角に掛ける割合・遅れの上限（度）・遅れが戻る速さ（秒。小さいほど早く付いてくる）。
        swayScale = Float64,
        swayMax = Float64,
        swayFollow = Float64,
        // 持ち替えの長さ（秒。この間は撃てない・draw のクリップをこの長さに伸び縮みさせる）。
        drawSeconds = Float64,
        // 反動で跳ね上がった照準が戻るまでの長さ（秒）。
        recoilRecover = Float64,
        // 腕と銃に当てる光の倍率（線形）: ステージの環境光と hemisphere・ステージの灯りの写し。
        // 腕と銃は目の真ん前にあり、灯りをステージと同じ強さで受けると壁より明るく白っぽく見えるので、ここで沈める。
        ambientScale = Float64,
        lampScale = Float64
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.viewmodel.json"

    /// コード側の既定値（assets/conduit_hive.viewmodel.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, fovY = 55.0, near = 0.01, far = 4.0, bobSide = 0.012, bobLift = 0.008,
                  swayScale = 0.6, swayMax = 4.0, swayFollow = 0.12, drawSeconds = 0.35, recoilRecover = 0.18,
                  ambientScale = 0.55, lampScale = 0.3 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  fovY = f("fovY", d#fovY), near = f("near", d#near), far = f("far", d#far),
                  bobSide = f("bobSide", d#bobSide), bobLift = f("bobLift", d#bobLift),
                  swayScale = f("swayScale", d#swayScale), swayMax = f("swayMax", d#swayMax), swayFollow = f("swayFollow", d#swayFollow),
                  drawSeconds = f("drawSeconds", d#drawSeconds), recoilRecover = f("recoilRecover", d#recoilRecover),
                  ambientScale = f("ambientScale", d#ambientScale), lampScale = f("lampScale", d#lampScale) })
}
