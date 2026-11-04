// MazeDoc — maze.stage.json（迷路のマス目）の宣言ドキュメント層。
// マス目は文字の行の並び: `#` が壁・ほかの 1 文字が床で、その文字が区画（部屋と通路の塊）の名前。
// 区画の高さと種類は zones の行・スタート・spawn 点・ピックアップの置き場は marks の行（種類の名前だけを持つ）。
// 区画のつながりと見える区画の組・当たり判定・絵はコード（Maze・Collider・MazeMesh）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod MazeDoc {
    use fge::{DocJson, JsonCodec, Log}
    use Util.Json.Json

    /// 区画の種類。Room = 部屋（灯りを吊る）・Corridor = 通路。
    pub enum ZoneKind with Eq, ToString {
        case Room
        case Corridor
    }

    /// 区画の行: マス目の文字・人が読む名前・種類・天井の高さ（m）。
    pub type alias ZoneSpec = { id = Char, name = String, kind = ZoneKind, height = Float64 }

    /// 印の種類。Start = 歩き始める所・Spawn = 敵が湧く所・Pickup = 拾う物の置き場（name が種類の名前）。
    pub enum MarkKind with Eq, ToString {
        case Start
        case Spawn
        case Pickup
    }

    /// マスの印: 種類・種類の名前・列（左が 0）・行（上が 0）・向き（度。0 が上の行の向き・90 が右）。
    pub type alias Mark = { kind = MarkKind, name = String, col = Int32, row = Int32, yaw = Float64 }

    pub type alias Rec = {
        version = Int32,
        // 1 マスの幅（m）。
        cellSize = Float64,
        // zones に行の無い区画の天井の高さ（m）。
        wallHeight = Float64,
        // 最後の部屋の文字。
        finalZone = Char,
        rows = List[String],
        zones = List[ZoneSpec],
        marks = List[Mark]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/maze.stage.json"

    /// 壁の文字。
    pub def wallChar(): Char = '#'

    /// コード側の既定: 1 部屋だけの小さな迷路（Doc が読めない時に歩ける所を残す）。
    /// 読めた Doc に zones・marks の欄が無ければ、その欄は空（既定の部屋の行は既定のマス目にだけ合う）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'A',
                  rows = "#####" :: "#AAA#" :: "#AAA#" :: "#AAA#" :: "#####" :: Nil,
                  zones = { id = 'A', name = "fallback", kind = ZoneKind.Room, height = 4.0 } :: Nil,
                  marks = { kind = MarkKind.Start, name = "start", col = 2, row = 2, yaw = 0.0 } :: Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def firstChar(s: String): Option[Char] = String.toList(s) |> List.head

    def listOf(key: String, decode: Json -> Option[a], root: Map[String, Json]): Option[List[a]] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.decodeList(decode))

    def zoneKindOf(s: String): Option[ZoneKind] = match s {
        case "room"     => Some(ZoneKind.Room)
        case "corridor" => Some(ZoneKind.Corridor)
        case _          => None
    }

    def markKindOf(s: String): Option[MarkKind] = match s {
        case "start"  => Some(MarkKind.Start)
        case "spawn"  => Some(MarkKind.Spawn)
        case "pickup" => Some(MarkKind.Pickup)
        case _        => None
    }

    /// 区画の行（文字が無い行は捨てる・種類の綴り違いは通路）。
    def zoneOf(wallHeight: Float64, element: Json): Option[ZoneSpec] =
        JsonCodec.expectObject(element) |> Option.flatMap(o ->
            Map.get("id", o) |> Option.flatMap(JsonCodec.expectString) |> Option.flatMap(firstChar) |> Option.map(id ->
                { id = id, name = JsonCodec.stringOr("name", "", o),
                  kind = zoneKindOf(JsonCodec.stringOr("kind", "", o)) |> Option.getWithDefault(ZoneKind.Corridor),
                  height = JsonCodec.floatOr("height", wallHeight, o) }))

    /// 印の行。種類の綴りが引けない行は 1 行知らせて置かない。
    def markOf(element: Json): Option[Mark] =
        JsonCodec.expectObject(element) |> Option.flatMap(o -> {
            let kindName = JsonCodec.stringOr("kind", "", o);
            match markKindOf(kindName) {
                case None => Log.warnThen("[maze] 印の種類 '${kindName}' は引けないので置かない（start・spawn・pickup）", None)
                case Some(kind) =>
                    Some({ kind = kind, name = JsonCodec.stringOr("name", "", o),
                           col = JsonCodec.intOr("x", 0, o), row = JsonCodec.intOr("y", 0, o), yaw = JsonCodec.floatOr("yaw", 0.0, o) })
            }
        })

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let wallHeight = JsonCodec.floatOr("wallHeight", d#wallHeight, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  cellSize = JsonCodec.floatOr("cellSize", d#cellSize, root),
                  wallHeight = wallHeight,
                  finalZone = firstChar(JsonCodec.stringOr("finalZone", "", root)) |> Option.getWithDefault(d#finalZone),
                  rows = listOf("rows", JsonCodec.expectString, root) |> Option.filter(rs -> not List.isEmpty(rs)) |> Option.getWithDefault(d#rows),
                  zones = listOf("zones", e -> Some(zoneOf(wallHeight, e)), root) |> Option.map(List.flatMap(Option.toList)) |> Option.getWithDefault(Nil),
                  marks = listOf("marks", e -> Some(markOf(e)), root) |> Option.map(List.flatMap(Option.toList)) |> Option.getWithDefault(Nil) })
}
