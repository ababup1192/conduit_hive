// KeysDoc — player.keys.json（キー割り当て）の宣言ドキュメント層。
// 「どのキーがどの操作か」だけを外に出す — 歩き方はコード（Controls / Walker）のまま。
// 1 つの操作に複数キーを並べられる。fail-open — 読めない・壊れているときは defaults() へ落とす。
// 操作の欄が空・全部知らない名前のときも、その操作だけ既定へ落とす（書き間違いで操作不能を作らない）。
mod KeysDoc {
    use fge::{DocJson, InputMap, JsonCodec}
    use fge::GameEngine.Key
    use Util.Json.Json

    /// 操作ごとのキーの列。
    pub type alias Rec = {
        version = Int32,
        forward = List[Key],      // 前へ歩く
        back = List[Key],         // 後ろへ歩く
        left = List[Key],         // 左へ横歩き
        right = List[Key],        // 右へ横歩き
        turnLeft = List[Key],     // 左を向く（マウスを使わない時）
        turnRight = List[Key],    // 右を向く（マウスを使わない時）
        sprint = List[Key],       // 押している間は走る（スタミナが減る）
        dodge = List[Key],        // 緊急回避（押している向きへ・押していなければ後ろへ跳ぶ）
        kick = List[Key],         // 前の敵を蹴って押し返す
        grenade = List[Key]       // 手榴弾を投げる
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/player.keys.json"

    /// コード側の既定（assets/player.keys.json と同じ割り当てから出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  forward = Key.W :: Key.Up :: Nil, back = Key.S :: Key.Down :: Nil,
                  left = Key.A :: Nil, right = Key.D :: Nil,
                  turnLeft = Key.Left :: Nil, turnRight = Key.Right :: Nil,
                  sprint = Key.LeftShift :: Nil, dodge = Key.Space :: Nil, kick = Key.F :: Key.V :: Nil, grenade = Key.G :: Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let k = (field, fallback) -> keysOr(field, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  forward = k("forward", d#forward), back = k("back", d#back), left = k("left", d#left), right = k("right", d#right),
                  turnLeft = k("turnLeft", d#turnLeft), turnRight = k("turnRight", d#turnRight), sprint = k("sprint", d#sprint),
                  dodge = k("dodge", d#dodge), kick = k("kick", d#kick), grenade = k("grenade", d#grenade) })

    /// 欄の文字列列 → キーの列。知らない名前はその 1 個だけ捨て、列ごと空になる形だけ既定へ落とす。
    def keysOr(field: String, fallback: List[Key], root: Map[String, Json]): List[Key] =
        Map.get(field, root)
            |> Option.flatMap(element -> JsonCodec.decodeList(JsonCodec.expectString, element))
            |> Option.map(InputMap.keysOf)
            |> Option.flatMap(keys -> if (List.isEmpty(keys)) None else Some(keys))
            |> Option.getWithDefault(fallback)
}
