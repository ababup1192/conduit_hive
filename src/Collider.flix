// Collider — 迷路のマス目から作る当たり判定の箱の集まり（純粋）。
// 壁は、床のマスに辺か角で接する壁のマスを、行ごとに続いている所をまとめた縦長の箱。床は迷路全体の下に敷く 1 枚の板。
// 体を箱の中で動かす規則は engine の CharacterBody3d。
mod Collider {
    use fge::{CollisionShape3d, CollisionWorld3d, Vec3}

    /// 床の板の厚さ（m）。
    def slab(): Float64 = 1.0

    /// 壁の箱の上の端を、一番高い天井よりどれだけ上にするか（m）。
    def headroom(): Float64 = 2.0

    /// 床のマスに辺か角で接する壁のマスか。
    def isBorderWall(m: Maze.Maze, cell: Maze.Cell): Bool =
        not Maze.isFloor(m, cell) and
            List.range(-1, 2) |> List.exists(dr -> List.range(-1, 2) |> List.exists(dc -> Maze.isFloor(m, { col = cell#col + dc, row = cell#row + dr })))

    /// 行 row の、床に接する壁のマスが続く所（始まりの列, 終わりの列）。
    def wallRunsOf(m: Maze.Maze, row: Int32): List[(Int32, Int32)] =
        List.range(0, m#cols) |> List.foldLeft((acc, col) -> {
            let wall = isBorderWall(m, { col = col, row = row });
            match acc {
                case (start, last) :: rest if wall and last == col - 1 => (start, col) :: rest
                case _ if wall => (col, col) :: acc
                case _ => acc
            }
        }, Nil) |> List.reverse

    /// 壁の箱の列（上の行から・行の中は西から）。
    def wallBoxes(m: Maze.Maze): List[CollisionShape3d.Box3d] =
        let top = Maze.maxHeight(m) + headroom();
        List.range(0, m#rows) |> List.flatMap(row -> wallRunsOf(m, row) |> List.map(span -> {
            let (c0, c1) = span;
            let (x0, z0) = Maze.cornerOf(m, { col = c0, row = row });
            let width = Int32.toFloat64(c1 - c0 + 1) * m#cellSize;
            CollisionShape3d.box3d(Vec3.v3(x0 + width / 2.0, top / 2.0, z0 + m#cellSize / 2.0), Vec3.v3(width / 2.0, top / 2.0, m#cellSize / 2.0))
        }))

    /// 迷路全体の下に敷く床の板（上の面が y = 0）。
    def floorBox(m: Maze.Maze): CollisionShape3d.Box3d =
        let w = Int32.toFloat64(m#cols) * m#cellSize;
        let d = Int32.toFloat64(m#rows) * m#cellSize;
        CollisionShape3d.box3d(Vec3.v3(w / 2.0, 0.0 - slab() / 2.0, d / 2.0), Vec3.v3(w / 2.0, slab() / 2.0, d / 2.0))

    /// 迷路の当たり判定の集まり（格子の 1 マスは迷路の 1 マスと同じ幅）。
    pub def worldOf(m: Maze.Maze): CollisionWorld3d.CollisionWorld3d =
        CollisionWorld3d.build(m#cellSize, List.append(wallBoxes(m), floorBox(m) :: Nil))
}
