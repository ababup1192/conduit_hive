// Separation — 群れの押し合いと壁からの押し出し（純粋）。敵は足元の円（Disc）で見る。
// マス → そのマスにいる円の Map を 1 回作り、同じマスと隣のマスの円とだけ、重なった分の半分ずつ押し離す（全員どうしを比べない）。
// プレイヤーの体からは重なった分を全部離し、最後に壁と立てた物の箱から押し出す。
mod Separation {
    use fge::{CollisionShape3d, CollisionWorld3d, Hash01, Num, Vec3}

    /// 足元の円。id = 押す向きを決める番号（同じ点に重なった時）。
    pub type alias Disc = { id = Int32, x = Float64, z = Float64, radius = Float64 }

    /// 押し離した後の足元（discs と同じ並び）。
    pub def separate(m: Maze.Maze, world: CollisionWorld3d.CollisionWorld3d, p: PlayerBody.PlayerBody, discs: List[Disc]): List[(Float64, Float64)] =
        let byCell = discs |> List.foldLeft((acc, d) -> Map.insertWith((a, b) -> List.append(b, a), cellKey(m, d), d :: Nil, acc), Map.empty());
        discs |> List.map(d -> walled(world, apart(m, p, byCell, d)))

    def cellKey(m: Maze.Maze, d: Disc): (Int32, Int32) =
        let c = Maze.cellAt(m, d#x, d#z);
        (c#col, c#row)

    def apart(m: Maze.Maze, p: PlayerBody.PlayerBody, byCell: Map[(Int32, Int32), List[Disc]], d: Disc): Disc =
        let (col, row) = cellKey(m, d);
        let others = List.range(-1, 2) |> List.flatMap(dr -> List.range(-1, 2) |> List.flatMap(dc -> Map.getWithDefault((col + dc, row + dr), Nil, byCell)))
            |> List.filter(o -> o#id != d#id);
        let (px, pz) = others |> List.foldLeft((acc, o) -> {
            let (ax, az) = awayFrom(d#id, o#id, d#x - o#x, d#z - o#z, d#radius + o#radius, 0.5);
            (fst(acc) + ax, snd(acc) + az)
        }, (0.0, 0.0));
        let (bx, bz) = awayFrom(d#id, -1, d#x - p#x, d#z - p#z, d#radius + p#radius, 1.0);
        { x = d#x + px + bx, z = d#z + pz + bz | d }

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
    def walled(world: CollisionWorld3d.CollisionWorld3d, d: Disc): (Float64, Float64) =
        let center = Vec3.v3(d#x, 1.0, d#z);
        let moved = CollisionWorld3d.boxesNear(world, center, d#radius + 0.1) |> List.foldLeft((at, b) ->
            CollisionShape3d.pushOutHorizontal(b, at, d#radius) |> Option.map(Vec3.add(at)) |> Option.getWithDefault(at), center);
        (moved#x, moved#z)
}
