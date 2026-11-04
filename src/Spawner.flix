// Spawner — 迷路の spawn の印と spawns.json の群れの種類から、部屋ごとの湧く予定を作る（純粋）。
// 印は群れの種類の名前だけを持ち、数・間隔・型は SpawnsDoc が正。名前が引けない印は 1 行知らせて置かない。
// 部屋に入った時刻から、印ごとに melee を先・ranged を後に、interval 秒ずつ空けて 1 体ずつ出す。プレイヤーに近すぎる印（SpawnsDoc の minDistance）の群れは、
// その部屋で一番遠い印から出す（数は保つ）。立つ所は印のマスの真ん中から scatter の幅で散らす。
mod Spawner {
    use fge::{Hash01, Log}
    use Creatures.Kind

    /// spawn の点 1 つ: 区画・印のマスの真ん中・群れの種類。
    pub type alias Point = { zone = Char, x = Float64, z = Float64, group = SpawnsDoc.Group }

    /// 湧く予定の 1 体: 時刻・型・立つ所・湧いた部屋。
    pub type alias Pending = { at = Float64, kind = Kind, x = Float64, z = Float64, home = Char }

    /// 迷路の spawn の印を、群れの種類の名前で引いた点の列（引けない名前・床でないマスの印は置かない）。
    pub def pointsOf(m: Maze.Maze, doc: SpawnsDoc.Doc): List[Point] =
        let groups = SpawnsDoc.rec(doc)#groups;
        m#marks |> List.filter(mk -> mk#kind == MazeDoc.MarkKind.Spawn) |> List.filterMap(mk -> {
            let cell = { col = mk#col, row = mk#row };
            let zone = Map.get(Maze.charAt(m, cell), m#zones) |> Option.map(z -> z#id);
            match (Map.get(mk#name, groups), zone) {
                case (None, _) => Log.warnThen("[spawn] 印 (${mk#col}, ${mk#row}) の群れ '${mk#name}' は spawns.json に無いので置かない", None)
                case (_, None) => Log.warnThen("[spawn] 印 (${mk#col}, ${mk#row}) は床のマスに無いので置かない", None)
                case (Some(g), Some(id)) =>
                    let (x, z) = Maze.centerOf(m, cell);
                    Some({ zone = id, x = x, z = z, group = g })
            }
        })

    /// 区画 zone の点から、時刻 t に始まる湧く予定（湧く順）。プレイヤー（away の x・z）から minDistance より近い点の群れは、
    /// その区画で一番遠い点から湧かせる（入った瞬間に目の前に湧かせず、湧く数は保つ。全部の点が近くても一番遠い点から湧く）。
    pub def scheduleOf(points: List[Point], zone: Char, t: Float64, away: { x = Float64, z = Float64, minDistance = Float64 }): List[Pending] =
        let distance2 = (p: Point) -> { let (dx, dz) = (p#x - away#x, p#z - away#z); dx * dx + dz * dz };
        let here = points |> List.filter(p -> p#zone == zone) |> List.zipWithIndex;
        let farthest = here |> List.foldLeft((best, e) -> {
            let p = snd(e);
            if (best |> Option.forAll(b -> distance2(p) > distance2(b))) Some(p) else best
        }, None);
        let placed = (p: Point) ->
            if (distance2(p) >= away#minDistance * away#minDistance) p
            else farthest |> Option.map(f -> { x = f#x, z = f#z | p }) |> Option.getWithDefault(p);
        here |> List.flatMap(e -> {
            let (pointIndex, mark) = e;
            let p = placed(mark);
            let g = p#group;
            let kinds = List.append(List.repeat(Int32.max(0, g#melee), Kind.Melee), List.repeat(Int32.max(0, g#ranged), Kind.Ranged));
            kinds |> List.zipWithIndex |> List.map(k -> {
                let (i, kind) = k;
                let seed = pointIndex * 64 + i;
                { at = t + Int32.toFloat64(i) * Float64.max(0.0, g#interval), kind = kind, home = zone,
                  x = p#x + (Hash01.at(seed, 71) - 0.5) * g#scatter, z = p#z + (Hash01.at(seed, 72) - 0.5) * g#scatter }
            })
        })
}
