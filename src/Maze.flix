// Maze — 迷路の Doc（MazeDoc）から作る、引くための形（純粋）: マス目・区画・区画の隣り合い・見える区画の組（PVS）・歩き始める所。
//
// 座標は engine の Scene3d と同じ（X 東・Y 上・Z 北）。マス目の上の行が北で、列 col・行 row のマスは
// x が [col × 幅, (col + 1) × 幅)・z が [(行の数 − 1 − row) × 幅, (行の数 − row) × 幅)。床の上面は y = 0。
//
// 見える区画の組（今いる区画から描く区画）は 2 つの和:
//   1. 隣り合いを 2 段たどった区画（同じ区画・境目のマスでつながる隣・その隣）
//   2. 見通し: その区画のマスの真ん中から、見える距離の内のほかの区画のマスの真ん中へ、壁のマスを通らずに線が引ける区画
//      （区画に分けた真っすぐ長い通路で、3 段より先の奥が欠けないため）
mod Maze {
    use fge::Num

    /// マス（列・行。左上が 0, 0）。
    pub type alias Cell = { col = Int32, row = Int32 }

    /// 区画: 文字・名前・種類・天井の高さ（m）・マスの並び（上の行から）。
    pub type alias Zone = { id = Char, name = String, kind = MazeDoc.ZoneKind, height = Float64, cells = List[Cell] }

    /// 歩き始める所: 足元の x・z と向き（度）。
    pub type alias Start = { x = Float64, z = Float64, yaw = Float64 }

    pub type alias Maze = {
        cols = Int32,
        rows = Int32,
        cellSize = Float64,
        // 行の順に並べたマスの文字（cols × rows）。
        grid = Vector[Char],
        zones = Map[Char, Zone],
        neighbors = Map[Char, Set[Char]],
        visible = Map[Char, Set[Char]],
        start = Start,
        finalZone = Char,
        marks = List[MazeDoc.Mark]
    }

    /// Doc から組む。viewDistance = 見える距離（m。霧の先と同じ）。
    pub def build(viewDistance: Float64, doc: MazeDoc.Doc): Maze =
        let d = MazeDoc.rec(doc);
        let cols = d#rows |> List.map(String.length) |> List.foldLeft(Int32.max, 0);
        let rowCount = List.length(d#rows);
        let grid = d#rows |> List.flatMap(r -> List.append(String.toList(r), List.repeat(cols - String.length(r), MazeDoc.wallChar()))) |> List.toVector;
        let shape = { cols = cols, rows = rowCount, cellSize = Float64.max(0.5, d#cellSize), grid = grid };
        let floors = floorCells(shape);
        let zones = zonesOf(d, floors);
        let neighbors = neighborsOf(shape, floors);
        let reach = viewDistance / shape#cellSize;
        let visible = Map.keysOf(zones) |> Set.toList |> List.map(id -> (id, visibleSet(shape, floors, neighbors, reach, id, zones))) |> List.toMap;
        { cols = cols, rows = rowCount, cellSize = shape#cellSize, grid = grid, zones = zones, neighbors = neighbors, visible = visible,
          start = startOf(shape, d#marks, floors), finalZone = d#finalZone, marks = d#marks }

    /// マス目の形だけ（組む途中で使う）。
    type alias Shape = { cols = Int32, rows = Int32, cellSize = Float64, grid = Vector[Char] }

    def charIn(s: Shape, cell: Cell): Char =
        if (cell#col < 0 or cell#row < 0 or cell#col >= s#cols or cell#row >= s#rows) MazeDoc.wallChar()
        else Vector.get(cell#row * s#cols + cell#col, s#grid)

    /// 床の文字か（壁の文字と空白のほかは全部床）。
    def isFloorChar(c: Char): Bool = c != MazeDoc.wallChar() and c != ' '

    /// マスの文字（マス目の外は壁）。
    pub def charAt(m: Maze, cell: Cell): Char = charIn({ cols = m#cols, rows = m#rows, cellSize = m#cellSize, grid = m#grid }, cell)

    /// マスが床か。
    pub def isFloor(m: Maze, cell: Cell): Bool = isFloorChar(charAt(m, cell))

    /// 床のマスと、その区画の文字（上の行から）。
    def floorCells(s: Shape): List[(Cell, Char)] =
        List.range(0, s#rows) |> List.flatMap(row -> List.range(0, s#cols) |> List.filterMap(col -> {
            let cell = { col = col, row = row };
            let c = charIn(s, cell);
            if (isFloorChar(c)) Some((cell, c)) else None
        }))

    /// 区画の表。zones の行が無い文字は、名前なし・通路・既定の高さ。
    def zonesOf(d: MazeDoc.Rec, floors: List[(Cell, Char)]): Map[Char, Zone] =
        let specs = d#zones |> List.map(z -> (z#id, z)) |> List.toMap;
        let cellsById = floors |> List.foldRight((e, acc) -> Map.insertWith((x, y) -> List.append(x, y), snd(e), fst(e) :: Nil, acc), Map.empty());
        cellsById |> Map.mapWithKey((id, cells) -> {
            let spec = Map.get(id, specs) |> Option.getWithDefault({ id = id, name = "", kind = MazeDoc.ZoneKind.Corridor, height = d#wallHeight });
            { id = id, name = spec#name, kind = spec#kind, height = spec#height, cells = cells }
        })

    /// 区画の隣り合い（違う区画の床のマスが辺で接していれば隣）。
    def neighborsOf(s: Shape, floors: List[(Cell, Char)]): Map[Char, Set[Char]] =
        floors |> List.foldLeft((acc, e) -> {
            let (cell, id) = e;
            ({ col = cell#col + 1 | cell } :: { row = cell#row + 1 | cell } :: Nil)
                |> List.map(n -> charIn(s, n))
                |> List.filter(c -> isFloorChar(c) and c != id)
                |> List.foldLeft((m, other) -> m |> Map.insertWith(Set.union, id, Set#{other}) |> Map.insertWith(Set.union, other, Set#{id}), acc)
        }, Map.empty())

    /// 区画 id から見える区画の組。
    def visibleSet(s: Shape, floors: List[(Cell, Char)], neighbors: Map[Char, Set[Char]], reach: Float64, id: Char, zones: Map[Char, Zone]): Set[Char] =
        let near = (z: Char) -> Map.getWithDefault(z, Set.empty(), neighbors);
        let twoSteps = Set.foldLeft((acc, n) -> Set.union(acc, near(n)), Set.insert(id, near(id)), near(id));
        let own = Map.get(id, zones) |> Option.map(z -> z#cells) |> Option.getWithDefault(Nil);
        own |> List.foldLeft((acc, a) ->
            floors |> List.foldLeft((seen, e) -> {
                let (b, other) = e;
                if (Set.memberOf(other, seen) or not isInSight(s, reach, a, b)) seen else Set.insert(other, seen)
            }, acc), twoSteps)

    /// マス a の真ん中から b の真ん中へ、距離 reach マスの内で、壁のマスを通らずに線が引けるか（1/4 マスごとに見る）。
    def isInSight(s: Shape, reach: Float64, a: Cell, b: Cell): Bool =
        let dx = Int32.toFloat64(b#col - a#col);
        let dy = Int32.toFloat64(b#row - a#row);
        let dist = Num.sqrt(dx * dx + dy * dy);
        if (dist > reach) false
        else {
            let n = Int32.max(1, Num.floorInt(dist * 4.0) + 1);
            List.range(1, n) |> List.forAll(i -> {
                let t = Int32.toFloat64(i) / Int32.toFloat64(n);
                let cell = { col = Num.floorInt(Int32.toFloat64(a#col) + 0.5 + dx * t), row = Num.floorInt(Int32.toFloat64(a#row) + 0.5 + dy * t) };
                isFloorChar(charIn(s, cell))
            })
        }

    /// 歩き始める所: 最初の start の印のマスの真ん中。印が無ければ最初の床のマス。
    def startOf(s: Shape, marks: List[MazeDoc.Mark], floors: List[(Cell, Char)]): Start =
        let fromMark = marks |> List.find(mk -> mk#kind == MazeDoc.MarkKind.Start)
            |> Option.map(mk -> ({ col = mk#col, row = mk#row }, mk#yaw));
        let fallback = floors |> List.head |> Option.map(e -> (fst(e), 0.0)) |> Option.getWithDefault(({ col = 0, row = 0 }, 0.0));
        let (cell, yaw) = Option.getWithDefault(fallback, fromMark);
        let (x, z) = centerIn(s, cell);
        { x = x, z = z, yaw = yaw }

    def centerIn(s: Shape, cell: Cell): (Float64, Float64) =
        ((Int32.toFloat64(cell#col) + 0.5) * s#cellSize, (Int32.toFloat64(s#rows - cell#row) - 0.5) * s#cellSize)

    // ── 座標と区画を引く ──

    /// マスの真ん中の x・z。
    pub def centerOf(m: Maze, cell: Cell): (Float64, Float64) =
        centerIn({ cols = m#cols, rows = m#rows, cellSize = m#cellSize, grid = m#grid }, cell)

    /// マスの x の西の端と z の南の端（m）。
    pub def cornerOf(m: Maze, cell: Cell): (Float64, Float64) =
        (Int32.toFloat64(cell#col) * m#cellSize, Int32.toFloat64(m#rows - 1 - cell#row) * m#cellSize)

    /// 点 x・z のあるマス。
    def cellAt(m: Maze, x: Float64, z: Float64): Cell =
        { col = Num.floorInt(x / m#cellSize), row = m#rows - 1 - Num.floorInt(z / m#cellSize) }

    /// 点 x・z のある区画（壁のマス・マス目の外は None）。
    pub def zoneAt(m: Maze, x: Float64, z: Float64): Option[Char] =
        let c = charAt(m, cellAt(m, x, z));
        if (isFloorChar(c)) Some(c) else None

    /// 点 x・z から描く区画。床の上でなければ全部の区画。
    /// WhyNot: 床の外で空の組にしない — 当たり判定の縁で体の真ん中が壁のマスへ入った瞬間に、画面が全部消える。
    pub def visibleFrom(m: Maze, x: Float64, z: Float64): Set[Char] =
        zoneAt(m, x, z) |> Option.flatMap(id -> Map.get(id, m#visible)) |> Option.getWithDefault(Map.keysOf(m#zones))

    /// 区画 id から見える区画の組（無い区画は空）。
    pub def visibleOf(m: Maze, id: Char): Set[Char] = Map.getWithDefault(id, Set.empty(), m#visible)

    /// 区画 id の隣の区画（無い区画は空）。
    pub def neighborsOfZone(m: Maze, id: Char): Set[Char] = Map.getWithDefault(id, Set.empty(), m#neighbors)

    /// 区画の高さの一番高い値（m。区画が無ければ 0）。
    pub def maxHeight(m: Maze): Float64 = m#zones |> Map.valuesOf |> List.map(z -> z#height) |> List.foldLeft(Float64.max, 0.0)

    /// マス cell の区画の高さ（床でなければ 0）。
    pub def heightAt(m: Maze, cell: Cell): Float64 =
        Map.get(charAt(m, cell), m#zones) |> Option.map(z -> z#height) |> Option.getWithDefault(0.0)
}
