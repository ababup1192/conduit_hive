// FpViewmodelDoc — conduit_hive.viewmodel.json（画面の手前に重ねる腕と銃 = ビューモデルの見え方と手触り）の宣言ドキュメント層。
// 画角・写す奥行き・歩く揺れ・見回しの遅れ・持ち替えの長さ・反動の戻り・光の倍率・面ごとの金属っぽさと粗さ。光の色と向きはステージの look と灯りに合わせ、霧は掛けない。
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
        lampScale = Float64,
        // 映り込みの景色の明るさの倍率（線形。look の envIntensity に掛ける）。灯りを lampScale で沈めた分、鋼の面の明暗は映り込みが作る。
        envScale = Float64,
        // 腕と銃の面ごとの金属っぽさと粗さ（glb の材質の名前の末尾 vm_<武器>_<面> で引く）。pbr が偽なら付けない（拡散の光だけの今までの絵）。
        // steel = 銃身・スライド・照準（磨いた鋼）・steelDark = 底板・手袋の甲の板・銃床の先（焼けた鋼）・graphite = 枠・握り・用心金（樹脂）・
        // glove = 手袋と袖の布・bore = 銃口の中。光る筋は付けない。
        pbr = Bool,
        steel = LookDoc.Surface,
        steelDark = LookDoc.Surface,
        graphite = LookDoc.Surface,
        glove = LookDoc.Surface,
        bore = LookDoc.Surface
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.viewmodel.json"

    /// コード側の既定値（assets/conduit_hive.viewmodel.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, fovY = 55.0, near = 0.01, far = 4.0, bobSide = 0.012, bobLift = 0.008,
                  swayScale = 0.6, swayMax = 4.0, swayFollow = 0.12, drawSeconds = 0.35, recoilRecover = 0.18,
                  ambientScale = 0.55, lampScale = 0.3, envScale = 3.0, pbr = true,
                  steel = { metallic = 0.75, roughness = 0.3 }, steelDark = { metallic = 0.7, roughness = 0.4 },
                  graphite = { metallic = 0.0, roughness = 0.62 }, glove = { metallic = 0.0, roughness = 0.95 }, bore = { metallic = 0.5, roughness = 0.7 } })

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
                  ambientScale = f("ambientScale", d#ambientScale), lampScale = f("lampScale", d#lampScale), envScale = f("envScale", d#envScale),
                  pbr = JsonCodec.boolOr("pbr", d#pbr, root),
                  steel = LookDoc.surfaceOr(d#steel, "steel", root), steelDark = LookDoc.surfaceOr(d#steelDark, "steelDark", root),
                  graphite = LookDoc.surfaceOr(d#graphite, "graphite", root), glove = LookDoc.surfaceOr(d#glove, "glove", root),
                  bore = LookDoc.surfaceOr(d#bore, "bore", root) })

    /// glb の材質の名前（vm_<武器>_<面>）の面の値（pbr が偽か、Doc に無い面なら None）。
    pub def surfaceOf(vm: Rec, material: String): Option[LookDoc.Surface] =
        if (not vm#pbr) None
        else (("_steel", vm#steel) :: ("_steel_dark", vm#steelDark) :: ("_graphite", vm#graphite) :: ("_glove", vm#glove) :: ("_bore", vm#bore) :: Nil)
            |> List.find(e -> String.endsWith(suffix = fst(e), material))
            |> Option.map(snd)
}
