// Separation — 群れの押し合いと壁からの押し出し（純粋）。敵は足元の円（Disc）で見る。
// 一辺が一番大きい円の直径の格子（SpatialGrid）へ円を 1 回振り分け、届く近さの円とだけ、重なった分の半分ずつ押し離す（全員どうしを比べない）。
// プレイヤーの体からは重なった分を全部離し、最後に壁と立てた物の箱から押し出す。
mod Separation {
    use fge::{CollisionShape3d, CollisionWorld3d, Hash01, Num, SpatialGrid, Vec3}

    /// 足元の円。id = 押す向きを決める番号（同じ点に重なった時）。
    pub type alias Disc = { id = Int32, x = Float64, z = Float64, radius = Float64 }

    /// 押し離した後の足元（discs と同じ並び）。
    /// open = 開いたマス（Collider.openCellsOf。開いたマスの円は箱を引かずに壁を飛ばす）。
    // WhyNot: 迷路のマスで近所を引かない — 1 部屋に群れが詰まると、1 体が隣の 9 マスの何百体と比べる（詰まるほど二乗で重くなる）。
    // WhyNot: 内側のループでレコードの欄を読まない — 欄を引くたびに名前で探すので、半径と番号は Vector へ 1 回写してから回す。
    pub def separate(m: Maze.Maze, world: CollisionWorld3d.CollisionWorld3d, open: Vector[Bool], p: PlayerBody.PlayerBody, discs: List[Disc]): List[(Float64, Float64)] =
        let radii = discs |> List.map(d -> d#radius) |> List.toVector;
        let ids = discs |> List.map(d -> d#id) |> List.toVector;
        let maxRadius = Vector.foldLeft(Float64.max, 0.0, radii);
        let grid = SpatialGrid.buildBy(2.0 * maxRadius, discs, d -> (d#x, d#z));
        discs |> List.map(d -> walled(m, world, open, apart(grid, radii, ids, maxRadius, p, d)))

    /// 円 d を、周りの円とプレイヤーの体から押し離した円。
    def apart(grid: SpatialGrid.SpatialGrid, radii: Vector[Float64], ids: Vector[Int32], maxRadius: Float64, p: PlayerBody.PlayerBody, d: Disc): Disc =
        let self = d#id;
        let x = d#x;
        let z = d#z;
        let radius = d#radius;
        let (px, pz) = SpatialGrid.foldNearIndex(grid, x, z, radius + maxRadius, (0.0, 0.0), (acc, index, otherX, otherZ) -> {
            let other = Vector.get(index, ids);
            if (other == self) acc
            else {
                let (dx, dz) = awayFrom(self, other, x - otherX, z - otherZ, radius + Vector.get(index, radii), 0.5);
                let (ax, az) = acc;
                (ax + dx, az + dz)
            }
        });
        let (bx, bz) = awayFrom(self, -1, x - p#x, z - p#z, radius + p#radius, 1.0);
        { x = x + px + bx, z = z + pz + bz | d }

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
