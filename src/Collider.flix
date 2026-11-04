// Collider — 迷路のマス目から作る当たり判定の箱の集まり（純粋）。
// 壁は、床のマスに辺か角で接する壁のマスを、行ごとに続いている所をまとめた縦長の箱。床は迷路全体の下に敷く 1 枚の板。
// 天井はマスごとの板（弾を止めるだけ。体は天井に届かない）。
// 体を箱の中で動かす規則は engine の CharacterBody3d。弾の当たりは Hitscan が同じ箱を的にする。
mod Collider {
    use fge::{CollisionShape3d, CollisionWorld3d, Ray3d, Vec3}

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
    pub def wallBoxes(m: Maze.Maze): List[CollisionShape3d.Box3d] =
        let top = Maze.maxHeight(m) + headroom();
        List.range(0, m#rows) |> List.flatMap(row -> wallRunsOf(m, row) |> List.map(span -> {
            let (c0, c1) = span;
            let (x0, z0) = Maze.cornerOf(m, { col = c0, row = row });
            let width = Int32.toFloat64(c1 - c0 + 1) * m#cellSize;
            CollisionShape3d.box3d(Vec3.v3(x0 + width / 2.0, top / 2.0, z0 + m#cellSize / 2.0), Vec3.v3(width / 2.0, top / 2.0, m#cellSize / 2.0))
        }))

    /// 迷路全体の下に敷く床の板（上の面が y = 0）。
    pub def floorBox(m: Maze.Maze): CollisionShape3d.Box3d =
        let w = Int32.toFloat64(m#cols) * m#cellSize;
        let d = Int32.toFloat64(m#rows) * m#cellSize;
        CollisionShape3d.box3d(Vec3.v3(w / 2.0, 0.0 - slab() / 2.0, d / 2.0), Vec3.v3(w / 2.0, slab() / 2.0, d / 2.0))

    /// 床のマスごとの天井の板（下の面がその区画の高さ）。
    pub def ceilingBoxes(m: Maze.Maze): List[CollisionShape3d.Box3d] =
        let half = m#cellSize / 2.0;
        m#zones |> Map.valuesOf |> List.flatMap(zone -> zone#cells |> List.map(cell -> {
            let (cx, cz) = Maze.centerOf(m, cell);
            CollisionShape3d.box3d(Vec3.v3(cx, zone#height + slab() / 2.0, cz), Vec3.v3(half, slab() / 2.0, half))
        }))

    /// 迷路の当たり判定の集まり（格子の 1 マスは迷路の 1 マスと同じ幅）。props = 床に立てた物（撃つ的の柱など）。
    pub def worldOf(m: Maze.Maze, props: List[CollisionShape3d.Box3d]): CollisionWorld3d.CollisionWorld3d =
        CollisionWorld3d.build(m#cellSize, List.append(wallBoxes(m), floorBox(m) :: props))

    /// マスごとに、そのマスと周りの 8 マスが床で、立てた物も掛からないか（並びは Maze の grid と同じ）。
    /// 開いたマスの中の体（半径がマスの幅より小さい）は、どの壁と立てた物の箱にも触れない。
    pub def openCellsOf(m: Maze.Maze, props: List[CollisionShape3d.Box3d]): Vector[Bool] =
        Vector.range(0, m#cols * m#rows) |> Vector.map(i -> {
            let cell = { col = Int32.modulo(i, m#cols), row = i / m#cols };
            let floors = List.range(-1, 2) |> List.forAll(dr -> List.range(-1, 2) |> List.forAll(dc ->
                Map.memberOf(Maze.charAt(m, { col = cell#col + dc, row = cell#row + dr }), m#zones)));
            let (cx, cz) = Maze.centerOf(m, cell);
            let reach = m#cellSize * 1.5;
            let clearOfProps = props |> List.forAll(b ->
                Float64.abs(b#center#x - cx) >= reach + b#half#x or Float64.abs(b#center#z - cz) >= reach + b#half#z);
            floors and clearOfProps
        })

    /// 点 x・z のマスが開いているか（openCellsOf。迷路の外は閉じている）。
    pub def isOpenAt(m: Maze.Maze, open: Vector[Bool], x: Float64, z: Float64): Bool =
        let cell = Maze.cellAt(m, x, z);
        cell#col >= 0 and cell#col < m#cols and cell#row >= 0 and cell#row < m#rows and Vector.get(cell#row * m#cols + cell#col, open)

    /// origin から destination まで、箱に遮られずに線が引けるか（敵の見通し・自動の操縦が狙える敵を選ぶ）。
    pub def isLineClear(world: CollisionWorld3d.CollisionWorld3d, origin: Vec3.Vec3, destination: Vec3.Vec3): Bool =
        let toward = Vec3.sub(destination, origin);
        let length = Vec3.length(toward);
        let ray = Ray3d.ray3d(origin, toward);
        let middle = Vec3.add(origin, Vec3.mul(toward, 0.5));
        CollisionWorld3d.boxesNear(world, middle, length * 0.5 + 0.5)
            |> List.forAll(b -> Option.isEmpty(Ray3d.hitBox(ray, length, b)))

    /// origin から target へ進む間に当たる箱の、一番近い当たり（projectile が弾ける所・手榴弾が跳ねる所）。
    pub def firstHit(world: CollisionWorld3d.CollisionWorld3d, origin: Vec3.Vec3, target: Vec3.Vec3): Option[Ray3d.RayHit] =
        let toward = Vec3.sub(target, origin);
        let length = Vec3.length(toward);
        let ray = Ray3d.ray3d(origin, toward);
        CollisionWorld3d.boxesNear(world, origin, length + 0.5)
            |> List.filterMap(b -> Ray3d.hitBox(ray, length, b))
            |> List.foldLeft((best, h) -> match best {
                case Some(b) if b#distance <= h#distance => best
                case _ => Some(h)
            }, None)
}
