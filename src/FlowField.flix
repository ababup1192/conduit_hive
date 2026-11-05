// FlowField — プレイヤーのマスまでの歩数の地図（純粋）。数コマに 1 回だけ塗り、全部の敵が同じ地図を読んで進む。
// 敵は自分のマスの隣（8 方向。斜めは両脇が床の時だけ）のうち、歩数が一番小さいマスへ向かう。
// WhyNot: 敵ごとに engine の Steering.chase を呼ばない — 呼ぶたびに地図を塗り直すので、50 体で 50 回の探索になる。
mod FlowField {
    use fge::GridSearch

    /// 地図: goal = 塗った時のプレイヤーのマス（None はまだ塗っていない）・cols × rows = 塗った迷路の大きさ・
    /// steps = マスの番号（行 × cols + 列）→ goal までの歩数（届かないマスは -1）・next = マスの番号 → 1 歩下るマスの番号（無ければ -1）。
    // WhyNot: 下るマスを敵ごとに毎コマ探さない — 地図は数コマに 1 回しか変わらないのに、群れの全員が隣の 8 マスを Map で引き直す。
    pub type alias FlowField = { goal = Option[Maze.Cell], cols = Int32, rows = Int32, steps = Vector[Int32], next = Vector[Int32] }

    /// まだ塗っていない地図。
    pub def empty(): FlowField = { goal = None, cols = 0, rows = 0, steps = Vector.empty(), next = Vector.empty() }

    /// 塗る歩数の上限（迷路の端から端まで届く数）。
    def maxSteps(): Int32 = 200

    /// goal のマスから床のマスだけを通って塗った地図（下るマスも塗る時に決める）。
    pub def build(m: Maze.Maze, goal: Maze.Cell): FlowField =
        let canEnter = (p: (Int32, Int32)) -> { let (col, row) = p; Maze.isFloor(m, { col = col, row = row }) };
        let distances = GridSearch.distances(canEnter, (goal#col, goal#row) :: Nil, maxSteps());
        let cells = Vector.range(0, m#cols * m#rows) |> Vector.map(i -> { col = Int32.remainder(i, m#cols), row = i / m#cols });
        let painted = { goal = Some(goal), cols = m#cols, rows = m#rows,
                        steps = cells |> Vector.map(c -> Map.getWithDefault((c#col, c#row), -1, distances)), next = Vector.empty() };
        { next = cells |> Vector.map(c -> searchDownhill(m, painted, c) |> Option.map(indexOf(painted)) |> Option.getWithDefault(-1)) | painted }

    /// マスの番号（迷路の外は None）。
    def indexAt(f: FlowField, cell: Maze.Cell): Option[Int32] =
        if (cell#col < 0 or cell#row < 0 or cell#col >= f#cols or cell#row >= f#rows) None else Some(indexOf(f, cell))

    def indexOf(f: FlowField, cell: Maze.Cell): Int32 = cell#row * f#cols + cell#col

    /// マス cell から goal までの歩数（届かないマスは None）。
    pub def stepsAt(f: FlowField, cell: Maze.Cell): Option[Int32] =
        indexAt(f, cell) |> Option.map(i -> Vector.get(i, f#steps)) |> Option.filter(s -> s >= 0)

    /// 隣のマスの向き（4 方向が先・斜めが後。同じ歩数なら前の物）。
    def around(): List[(Int32, Int32)] =
        (0, -1) :: (1, 0) :: (0, 1) :: (-1, 0) :: (1, -1) :: (1, 1) :: (-1, 1) :: (-1, -1) :: Nil

    /// 斜めへ進めるか（両脇のマスが床。壁の角を斜めに抜けない）。
    def isOpen(m: Maze.Maze, cell: Maze.Cell, d: (Int32, Int32)): Bool =
        let (dc, dr) = d;
        (dc == 0 or dr == 0) or (Maze.isFloor(m, { col = cell#col + dc | cell }) and Maze.isFloor(m, { row = cell#row + dr | cell }))

    /// cell から 1 歩下るマス（今より歩数が小さい隣のうち一番小さい物）。今のマスが goal か、塗った外なら None。
    pub def downhill(f: FlowField, cell: Maze.Cell): Option[Maze.Cell] =
        indexAt(f, cell) |> Option.map(i -> Vector.get(i, f#next)) |> Option.filter(j -> j >= 0)
            |> Option.map(j -> { col = Int32.remainder(j, f#cols), row = j / f#cols })

    /// 塗った歩数から、cell の下るマスを隣の 8 マスで探す。
    def searchDownhill(m: Maze.Maze, f: FlowField, cell: Maze.Cell): Option[Maze.Cell] =
        stepsAt(f, cell) |> Option.flatMap(here ->
            around()
                |> List.filter(d -> isOpen(m, cell, d))
                |> List.filterMap(d -> { let (dc, dr) = d; let next = { col = cell#col + dc, row = cell#row + dr }; stepsAt(f, next) |> Option.map(s -> (s, next)) })
                |> List.filter(e -> fst(e) < here)
                |> List.foldLeft((best, e) -> match best {
                    case Some((s, _)) if s <= fst(e) => best
                    case _ => Some(e)
                }, None)
                |> Option.map(snd))
}
