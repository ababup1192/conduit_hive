// UiTextDoc — conduit_hive.uitext.json（画面に出す文言）の宣言ドキュメント層。
// fail-open — 読めない・壊れているときは defaults() へ落とし、ゲームは必ず起動する。
mod UiTextDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        quitPrompt = String
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.uitext.json"

    /// コード側の既定値（assets/conduit_hive.uitext.json と同じ値から出発する）。
    pub def defaults(): Doc = Doc.Doc({ version = 1, quitPrompt = "Quit?  Enter: yes  /  Esc: no" })

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ落とす。
    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  quitPrompt = JsonCodec.stringOr("quitPrompt", d#quitPrompt, root) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)
}
