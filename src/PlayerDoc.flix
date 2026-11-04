// PlayerDoc — conduit_hive.player.json（プレイヤーの体力・被弾の赤み・倒れてからやり直すまで・クリアから結果の画面まで）の宣言ドキュメント層。
// 傷を足す・倒れる・やり直す規則はコード（Health・World）。時間は秒。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod PlayerDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // 体力の最大。
        health = Float64,
        // 被弾で画面の縁が赤くなる長さ・倒れてからやり直すまで。
        hurtSeconds = Float64,
        respawnSeconds = Float64,
        // 最後の部屋を空にしてから結果の画面へ移るまで（秒）。
        clearSeconds = Float64
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.player.json"

    /// コード側の既定値（assets/conduit_hive.player.json と同じ値から出発する）。
    pub def defaults(): Doc = Doc.Doc({ version = 1, health = 100.0, hurtSeconds = 0.6, respawnSeconds = 2.0, clearSeconds = 2.5 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (k, v) -> JsonCodec.floatOr(k, v, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), health = f("health", d#health),
                  hurtSeconds = f("hurtSeconds", d#hurtSeconds), respawnSeconds = f("respawnSeconds", d#respawnSeconds),
                  clearSeconds = f("clearSeconds", d#clearSeconds) })
}
