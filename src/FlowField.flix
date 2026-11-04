// FlowField — プレイヤーのマスまでの歩数の地図（純粋）。数コマに 1 回だけ塗り、全部の敵が同じ地図を読んで進む。
// 敵は自分のマスの隣（8 方向。斜めは両脇が床の時だけ）のうち、歩数が一番小さいマスへ向かう。
// WhyNot: 敵ごとに engine の Steering.chase を呼ばない — 呼ぶたびに地図を塗り直すので、50 体で 50 回の探索になる。
mod FlowField {
    use fge::GridSearch

    /// 地図: goal = 塗った時のプレイヤーのマス（None はまだ塗っていない）・steps = マス (列, 行) → goal までの歩数。
    pub type alias FlowField = { goal = Option[Maze.Cell], steps = Map[(Int32, Int32), Int32] }

    /// まだ塗っていない地図。
    pub def empty(): FlowField = { goal = None, steps = Map.empty() }

    /// 塗る歩数の上限（迷路の端から端まで届く数）。
    def maxSteps(): Int32 = 200

    /// goal のマスから床のマスだけを通って塗った地図。
    pub def build(m: Maze.Maze, goal: Maze.Cell): FlowField =
        let canEnter = (p: (Int32, Int32)) -> { let (col, row) = p; Maze.isFloor(m, { col = col, row = row }) };
        { goal = Some(goal), steps = GridSearch.distances(canEnter, (goal#col, goal#row) :: Nil, maxSteps()) }

    /// マス cell から goal までの歩数（届かないマスは None）。
    pub def stepsAt(f: FlowField, cell: Maze.Cell): Option[Int32] = Map.get((cell#col, cell#row), f#steps)

    /// 隣のマスの向き（4 方向が先・斜めが後。同じ歩数なら前の物）。
    def around(): List[(Int32, Int32)] =
        (0, -1) :: (1, 0) :: (0, 1) :: (-1, 0) :: (1, -1) :: (1, 1) :: (-1, 1) :: (-1, -1) :: Nil

    /// 斜めへ進めるか（両脇のマスが床。壁の角を斜めに抜けない）。
    def isOpen(m: Maze.Maze, cell: Maze.Cell, d: (Int32, Int32)): Bool =
        let (dc, dr) = d;
        (dc == 0 or dr == 0) or (Maze.isFloor(m, { col = cell#col + dc | cell }) and Maze.isFloor(m, { row = cell#row + dr | cell }))

    /// cell から 1 歩下るマス（今より歩数が小さい隣のうち一番小さい物）。今のマスが goal か、塗った外なら None。
    pub def downhill(m: Maze.Maze, f: FlowField, cell: Maze.Cell): Option[Maze.Cell] =
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
