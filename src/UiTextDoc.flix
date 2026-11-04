// UiTextDoc — conduit_hive.uitext.json（画面に出す文言）の宣言ドキュメント層。
// 字は Xolonium（ラテン文字だけ）で描くので、文言は英字で書く。拾った時の知らせの {n} は拾った量に置き換わる。
// fail-open — 読めない・壊れているときは defaults() へ落とし、ゲームは必ず起動する。
mod UiTextDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 操作の一覧の 1 行: キー・何をするか。
    pub type alias Control = { key = String, action = String }

    pub type alias Rec = {
        version = Int32,
        quitPrompt = String,
        // タイトル: ゲームの名前・一言・始め方・操作の一覧。
        gameTitle = String,
        tagline = String,
        startHint = String,
        controls = List[Control],
        // ポーズ: 見出し・続ける・タイトルへ。
        pauseTitle = String,
        resume = String,
        toTitle = String,
        // クリア: 見出し・かかった時間・倒した数・戻り方。
        clearTitle = String,
        clearTime = String,
        clearKills = String,
        clearBack = String,
        // 拾った時の知らせ（{n} は量）。
        noticeHealth = String,
        noticeShells = String,
        noticeRounds = String,
        noticeShotgun = String,
        noticeRifle = String,
        noticeGrenade = String
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.uitext.json"

    /// コード側の既定値（assets/conduit_hive.uitext.json と同じ値から出発する）。
    pub def defaults(): Doc = Doc.Doc({
        version = 1, quitPrompt = "Quit?  Enter: yes  /  Esc: no",
        gameTitle = "CONDUIT HIVE", tagline = "PURGE THE HIVE AT THE END OF THE CONDUITS", startHint = "CLICK  OR  ENTER  TO  START",
        controls = { key = "W A S D", action = "MOVE" } :: { key = "SHIFT", action = "SPRINT" } :: { key = "MOUSE", action = "LOOK" }
                   :: { key = "LEFT BUTTON", action = "FIRE" } :: { key = "1 2 3  /  WHEEL", action = "SWITCH WEAPON" }
                   :: { key = "SPACE", action = "DODGE" } :: { key = "F", action = "KICK" } :: { key = "G", action = "GRENADE" } :: { key = "ESC", action = "PAUSE" } :: Nil,
        pauseTitle = "PAUSED", resume = "RESUME", toTitle = "TITLE",
        clearTitle = "HIVE PURGED", clearTime = "TIME", clearKills = "KILLS", clearBack = "CLICK  OR  ENTER  FOR  TITLE",
        noticeHealth = "+{n}  HEALTH", noticeShells = "+{n}  SHELLS", noticeRounds = "+{n}  ROUNDS",
        noticeShotgun = "SHOTGUN", noticeRifle = "RIFLE", noticeGrenade = "+{n}  GRENADE" })

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ落とす。
    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    /// 操作の一覧の 1 行（key の無い行は捨てる）。
    def controlOf(element: Json): Option[Control] =
        JsonCodec.expectObject(element) |> Option.flatMap(o ->
            Map.get("key", o) |> Option.flatMap(JsonCodec.expectString) |> Option.map(key -> { key = key, action = JsonCodec.stringOr("action", "", o) }))

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let s = (k, v) -> JsonCodec.stringOr(k, v, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), quitPrompt = s("quitPrompt", d#quitPrompt),
                  gameTitle = s("gameTitle", d#gameTitle), tagline = s("tagline", d#tagline), startHint = s("startHint", d#startHint),
                  controls = Map.get("controls", root) |> Option.flatMap(JsonCodec.decodeList(e -> Some(controlOf(e))))
                      |> Option.map(List.flatMap(Option.toList)) |> Option.getWithDefault(d#controls),
                  pauseTitle = s("pauseTitle", d#pauseTitle), resume = s("resume", d#resume), toTitle = s("toTitle", d#toTitle),
                  clearTitle = s("clearTitle", d#clearTitle), clearTime = s("clearTime", d#clearTime), clearKills = s("clearKills", d#clearKills),
                  clearBack = s("clearBack", d#clearBack),
                  noticeHealth = s("noticeHealth", d#noticeHealth), noticeShells = s("noticeShells", d#noticeShells),
                  noticeRounds = s("noticeRounds", d#noticeRounds), noticeShotgun = s("noticeShotgun", d#noticeShotgun),
                  noticeRifle = s("noticeRifle", d#noticeRifle), noticeGrenade = s("noticeGrenade", d#noticeGrenade) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)
}
