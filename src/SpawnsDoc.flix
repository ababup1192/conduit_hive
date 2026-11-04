// SpawnsDoc — conduit_hive.spawns.json（spawn の群れの種類ごとの湧く数・間隔・型）の宣言ドキュメント層。
// 迷路の Doc の spawn の印は群れの種類の名前だけを持ち、数と型はここが正（印の名前がここで引けなければ、その印は置かない）。
// 部屋に入った時にどの印から湧かせるか・どこに立たせるかはコード（Spawner）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod SpawnsDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 群れの種類 1 つ: 1 つの印から湧く melee と ranged の数・1 体ごとの間隔（秒）・印のマスの中で散らす幅（m）。
    pub type alias Group = { melee = Int32, ranged = Int32, interval = Float64, scatter = Float64 }

    /// minDistance = 部屋に入った時、プレイヤーからこの距離（m）より近い印からは湧かせない。
    pub type alias Rec = { version = Int32, minDistance = Float64, groups = Map[String, Group] }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.spawns.json"

    def group(melee: Int32, ranged: Int32, interval: Float64): Group = { melee = melee, ranged = ranged, interval = interval, scatter = 2.4 }

    /// コード側の既定値（assets/conduit_hive.spawns.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, minDistance = 10.0,
                  groups = Map#{ "pack" => group(3, 0, 0.5), "mixed" => group(3, 1, 0.5), "hive" => group(5, 1, 0.35) } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// 群れの種類 1 つ（無い欄はその欄だけ既定の pack の値）。
    def groupOf(fallback: Group, element: Json): Option[Group] =
        JsonCodec.expectObject(element) |> Option.map(o ->
            { melee = JsonCodec.intOr("melee", fallback#melee, o), ranged = JsonCodec.intOr("ranged", fallback#ranged, o),
              interval = JsonCodec.floatOr("interval", fallback#interval, o), scatter = JsonCodec.floatOr("scatter", fallback#scatter, o) })

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let fallback = Map.get("pack", d#groups) |> Option.getWithDefault(group(0, 0, 1.0));
        let groups = Map.get("groups", root) |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(o -> o |> Map.toList |> List.filterMap(e -> { let (name, v) = e; groupOf(fallback, v) |> Option.map(g -> (name, g)) }) |> List.toMap)
            |> Option.getWithDefault(d#groups);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), minDistance = JsonCodec.floatOr("minDistance", d#minDistance, root), groups = groups })
}
