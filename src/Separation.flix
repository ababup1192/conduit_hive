// Separation — 群れの押し合いと壁からの押し出し（純粋）。敵は足元の円（Disc）で見る。
// 一辺が一番大きい円の直径の格子へ円を 1 回振り分け、同じ升と隣の升の円とだけ、重なった分の半分ずつ押し離す（全員どうしを比べない）。
// プレイヤーの体からは重なった分を全部離し、最後に壁と立てた物の箱から押し出す。
mod Separation {
    use fge::{CollisionShape3d, CollisionWorld3d, Hash01, Num, Vec3}

    /// 足元の円。id = 押す向きを決める番号（同じ点に重なった時）。
    pub type alias Disc = { id = Int32, x = Float64, z = Float64, radius = Float64 }

    /// 格子の円の欄（order・ids・xs・zs・radii）を 1 組にした物。
    type alias Columns[r: Region] = (Array[Int32, r], Array[Int32, r], Array[Float64, r], Array[Float64, r], Array[Float64, r])

    /// 円を振り分けた格子。order の starts[c] から starts[c + 1] の手前までが升 c の円の番号（discs の並び）。
    type alias Grid[r: Region] = { xs = Array[Float64, r], zs = Array[Float64, r], radii = Array[Float64, r], ids = Array[Int32, r],
                                   starts = Array[Int32, r], order = Array[Int32, r], cols = Int32, rows = Int32,
                                   minX = Float64, minZ = Float64, size = Float64 }

    /// 押し離した後の足元（discs と同じ並び）。
    /// open = 開いたマス（Collider.openCellsOf。開いたマスの円は箱を引かずに壁を飛ばす）。
    // WhyNot: 迷路のマスで近所を引かない — 1 部屋に群れが詰まると、1 体が隣の 9 マスの何百体と比べる（詰まるほど二乗で重くなる）。
    // WhyNot: 内側のループでレコードの欄を読まない — 欄を引くたびに名前で探すので、配列へ 1 回写してから回す。
    pub def separate(m: Maze.Maze, world: CollisionWorld3d.CollisionWorld3d, open: Vector[Bool], p: PlayerBody.PlayerBody, discs: List[Disc]): List[(Float64, Float64)] = region rc {
        let grid = gridOf(rc, discs);
        discs |> List.mapWithIndex((i, d) -> walled(m, world, open, apart(grid, p, i, d)))
    }

    /// 升の一辺: 一番大きい円の直径（重なる 2 つは必ず同じ升か隣の升）。升の数が円の数の 4 倍 + 1024 を超える広がりなら、超えない所まで広げる。
    // WhyNot: 直径だけで一辺を決めない — 遠くに 1 体はぐれると升の数が広さに比例して膨らみ、群れの数と関係なく大きな配列を毎コマ作る。
    def cellSizeOf(n: Int32, reach: Float64, width: Float64, depth: Float64): Float64 =
        let budget = Int32.toFloat64(4 * n + 1024);
        Float64.max(Float64.max(0.01, reach), Num.sqrt(width * depth / budget))

    def gridOf(rc: Region[r], discs: List[Disc]): Grid[r] \ r =
        let xs = discs |> List.map(d -> d#x) |> List.toArray(rc);
        let zs = discs |> List.map(d -> d#z) |> List.toArray(rc);
        let radii = discs |> List.map(d -> d#radius) |> List.toArray(rc);
        let ids = discs |> List.map(d -> d#id) |> List.toArray(rc);
        let n = Array.length(xs);
        let minX = if (n == 0) 0.0 else Array.foldLeft(Float64.min, Float64.maxValue(), xs);
        let minZ = if (n == 0) 0.0 else Array.foldLeft(Float64.min, Float64.maxValue(), zs);
        let width = if (n == 0) 0.0 else Array.foldLeft(Float64.max, Float64.minValue(), xs) - minX;
        let depth = if (n == 0) 0.0 else Array.foldLeft(Float64.max, Float64.minValue(), zs) - minZ;
        let size = cellSizeOf(n, 2.0 * Array.foldLeft(Float64.max, 0.0, radii), width, depth);
        let cols = Num.floorInt(width / size) + 1;
        let rows = Num.floorInt(depth / size) + 1;
        let starts = Array.repeat(rc, cols * rows + 1, 0);
        let order = Array.repeat(rc, Int32.max(1, n), 0);
        let grid = { xs = xs, zs = zs, radii = radii, ids = ids, starts = starts, order = order, cols = cols, rows = rows,
                     minX = minX, minZ = minZ, size = size };
        let cells = Array.repeat(rc, Int32.max(1, n), 0);
        Array.forEachWithIndex((i, x) -> {
            let c = cellOf(grid, colOf(grid, x), rowOf(grid, Array.get(i, zs)));
            Array.put(c, i, cells);
            Array.put(Array.get(c + 1, starts) + 1, c + 1, starts)
        }, xs);
        sumUp(starts, 1);
        let cursor = Array.copyOfRange(rc, 0, cols * rows, starts);
        Array.forEachWithIndex((i, _) -> {
            let c = Array.get(i, cells);
            Array.put(i, Array.get(c, cursor), order);
            Array.put(Array.get(c, cursor) + 1, c, cursor)
        }, xs);
        grid

    /// 数を頭から足し込んで、升ごとの始まりにする。
    def sumUp(starts: Array[Int32, r], c: Int32): Unit \ r =
        if (c >= Array.length(starts)) ()
        else {
            Array.put(Array.get(c, starts) + Array.get(c - 1, starts), c, starts);
            sumUp(starts, c + 1)
        }

    def colOf(g: Grid[r], x: Float64): Int32 = Num.clampInt(0, g#cols - 1, Num.floorInt((x - g#minX) / g#size))

    def rowOf(g: Grid[r], z: Float64): Int32 = Num.clampInt(0, g#rows - 1, Num.floorInt((z - g#minZ) / g#size))

    def cellOf(g: Grid[r], col: Int32, row: Int32): Int32 = row * g#cols + col

    def apart(g: Grid[r], p: PlayerBody.PlayerBody, i: Int32, d: Disc): Disc \ r =
        let me = (Array.get(i, g#ids), Array.get(i, g#xs), Array.get(i, g#zs), Array.get(i, g#radii));
        let (px, pz) = pushAround(g, (g#order, g#ids, g#xs, g#zs, g#radii), me, colOf(g, d#x), rowOf(g, d#z), 0, 0.0, 0.0);
        let (bx, bz) = awayFrom(d#id, -1, d#x - p#x, d#z - p#z, d#radius + p#radius, 1.0);
        { x = d#x + px + bx, z = d#z + pz + bz | d }

    /// 円 me（番号, x, z, 半径）が、自分の升と周りの 8 升（k = 0〜8）の円から受けるずれの合計。
    def pushAround(g: Grid[r], columns: Columns[r],
                   me: (Int32, Float64, Float64, Float64), col: Int32, row: Int32, k: Int32, ax: Float64, az: Float64): (Float64, Float64) \ r =
        if (k >= 9) (ax, az)
        else {
            let c = col + Int32.remainder(k, 3) - 1;
            let w = row + k / 3 - 1;
            let (bx, bz) = if (c < 0 or w < 0 or c >= g#cols or w >= g#rows) (0.0, 0.0)
                           else {
                               let cell = cellOf(g, c, w);
                               pushFrom(columns, me, Array.get(cell, g#starts), Array.get(cell + 1, g#starts), 0.0, 0.0)
                           };
            pushAround(g, columns, me, col, row, k + 1, ax + bx, az + bz)
        }

    /// order の k から end の手前までの円から、円 me が受けるずれの合計（同じ番号の円は飛ばす）。
    def pushFrom(columns: Columns[r],
                 me: (Int32, Float64, Float64, Float64), k: Int32, end: Int32, ax: Float64, az: Float64): (Float64, Float64) \ r =
        if (k >= end) (ax, az)
        else {
            let (order, ids, xs, zs, radii) = columns;
            let (self, x, z, radius) = me;
            let j = Array.get(k, order);
            let other = Array.get(j, ids);
            if (other == self) pushFrom(columns, me, k + 1, end, ax, az)
            else {
                let (dx, dz) = awayFrom(self, other, x - Array.get(j, xs), z - Array.get(j, zs), radius + Array.get(j, radii), 0.5);
                pushFrom(columns, me, k + 1, end, ax + dx, az + dz)
            }
        }

    /// 間 (dx, dz) が reach より近い時に離すずれ（重なった分 × share）。ちょうど同じ点なら番号から決まった向きへ。
    def awayFrom(self: Int32, other: Int32, dx: Float64, dz: Float64, reach: Float64, share: Float64): (Float64, Float64) =
        let d = Num.sqrt(dx * dx + dz * dz);
        if (d >= reach) (0.0, 0.0)
        else if (d < 0.0001) {
            let a = Hash01.at(Int32.min(self, other) * 977 + Int32.max(self, other), 73) * Num.tau() + (if (self < other) 0.0 else Num.pi());
            (Num.sin(a) * reach * share, Num.cos(a) * reach * share)
        }
        else ((dx / d) * (reach - d) * share, (dz / d) * (reach - d) * share)

    /// 壁と立てた物の箱から押し出す（足元の円を腰の高さの球で見る）。
    def walled(m: Maze.Maze, world: CollisionWorld3d.CollisionWorld3d, open: Vector[Bool], d: Disc): (Float64, Float64) =
        if (Collider.isOpenAt(m, open, d#x, d#z)) (d#x, d#z) else pushedOut(world, d)

    /// 壁と立てた物の箱から押し出した足元。
    def pushedOut(world: CollisionWorld3d.CollisionWorld3d, d: Disc): (Float64, Float64) =
        let center = Vec3.v3(d#x, 1.0, d#z);
        let moved = CollisionWorld3d.boxesNear(world, center, d#radius + 0.1) |> List.foldLeft((at, b) ->
            CollisionShape3d.pushOutHorizontal(b, at, d#radius) |> Option.map(Vec3.add(at)) |> Option.getWithDefault(at), center);
        (moved#x, moved#z)
}
