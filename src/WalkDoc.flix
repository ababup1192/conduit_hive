// WalkDoc — conduit_hive.walk.json（歩く手触りの数値）の宣言ドキュメント層。
// 歩き方の規則（当たり判定・段差）はコード（Walker・Collider）で、ここは調整する数だけ。歩き始める所は迷路の Doc の start の印。
// 長さはメートル・角度は度・速さは 1 秒あたり。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod WalkDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // 歩く速さ・走る速さ（m/秒）。
        walkSpeed = Float64,
        runSpeed = Float64,
        // キーで向きを変える速さ（度/秒）・マウスの 1 px で向きを変える角（度）・マウスの上下を逆にするか・見上げ見下ろしの上限（度）。
        turnSpeed = Float64,
        mouseSensitivity = Float64,
        invertY = Bool,
        pitchLimit = Float64,
        // 目の高さ・体の半径・体の高さ・そのまま上がれる段の高さ（m）。
        eyeHeight = Float64,
        radius = Float64,
        height = Float64,
        stepHeight = Float64,
        // 落ちる速さの増え方（m/秒²）。
        gravity = Float64,
        // 歩く時の頭の上下（m）と、1 歩の長さ（m）。走る時の 1 歩の長さ。
        bobHeight = Float64,
        stride = Float64,
        runStride = Float64,
        // 縦の画角（度）。
        fovY = Float64
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.walk.json"

    /// コード側の既定値（assets/conduit_hive.walk.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, walkSpeed = 4.5, runSpeed = 7.5, turnSpeed = 120.0, mouseSensitivity = 0.15, invertY = false, pitchLimit = 80.0,
                  eyeHeight = 1.65, radius = 0.35, height = 1.8, stepHeight = 0.35, gravity = 9.8,
                  bobHeight = 0.03, stride = 1.6, runStride = 2.2, fovY = 70.0 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  walkSpeed = f("walkSpeed", d#walkSpeed), runSpeed = f("runSpeed", d#runSpeed),
                  turnSpeed = f("turnSpeed", d#turnSpeed), mouseSensitivity = f("mouseSensitivity", d#mouseSensitivity),
                  invertY = JsonCodec.boolOr("invertY", d#invertY, root),
                  pitchLimit = f("pitchLimit", d#pitchLimit), eyeHeight = f("eyeHeight", d#eyeHeight),
                  radius = f("radius", d#radius), height = f("height", d#height), stepHeight = f("stepHeight", d#stepHeight),
                  gravity = f("gravity", d#gravity), bobHeight = f("bobHeight", d#bobHeight),
                  stride = f("stride", d#stride), runStride = f("runStride", d#runStride), fovY = f("fovY", d#fovY) })
}
