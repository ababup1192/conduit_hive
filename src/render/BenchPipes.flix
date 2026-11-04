// BenchPipes — 測り（make bench-horde）だけが使う、パイプの仮置き（純粋）。普段の遊びからは呼ばない。
// 区画ごとに細長い箱を pipes 個まで、壁ぎわの天井近くに 3 段で並べる（区画ごとに 1 つの形へまとめるか、ばらばらか）。
// 本物のパイプ（Blender で区画ごとに組む）は段 4 の仕事で、ここは draw call と三角形の量だけをそれらしくする。
mod BenchPipes {
    use fge::{Color, Mat4, Scene3d, Vec3}

    /// パイプの箱の形の持ち方。PerZone = 区画ごとに 1 つの形へまとめる・Loose = 箱ごとに置く。
    pub enum PipeMesh with Eq, ToString {
        case PerZone
        case Loose
    }

    /// 区画ごとのパイプの箱の置いた物（pipes が 0 なら空）。
    pub def artOf(pipes: Int32, mesh: PipeMesh, m: Maze.Maze): Map[Char, List[Scene3d.Instance3d]] =
        let unit = BoxMesh.unit(steel());
        if (pipes <= 0) Map.empty()
        else m#zones |> Map.map(zone -> {
            let boxes = pipeBoxes(pipes, m, zone);
            match mesh {
                case PipeMesh.PerZone => if (List.isEmpty(boxes)) Nil else Scene3d.meshInstance(BoxMesh.of(steel(), boxes), Mat4.identity()) :: Nil
                case PipeMesh.Loose   => boxes |> List.map(b -> Scene3d.meshInstance(unit, Mat4.mul(Mat4.translate(b#center), Mat4.scale(b#size))))
            }
        })

    /// 1 区画の箱: 壁に接するマスの辺ごとに、天井近くへ 3 段。多ければ count 個まで。
    def pipeBoxes(count: Int32, m: Maze.Maze, zone: Maze.Zone): List[BoxMesh.Box] =
        let half = m#cellSize / 2.0;
        let thick = 0.28;
        let sides = (1, 0) :: (-1, 0) :: (0, 1) :: (0, -1) :: Nil;
        zone#cells |> List.flatMap(cell -> sides |> List.filter(s -> { let (dc, dr) = s; not Maze.isFloor(m, { col = cell#col + dc, row = cell#row + dr }) })
                                                  |> List.map(s -> (cell, s)))
            |> List.flatMap(edge -> List.range(0, 3) |> List.map(tier -> {
                let (cell, (dc, dr)) = edge;
                let (cx, cz) = Maze.centerOf(m, cell);
                // 行が増えると z は減る（Maze.cornerOf の向き）。
                let (nx, nz) = (Int32.toFloat64(dc), Int32.toFloat64(-dr));
                let inset = half - 0.25 - Int32.toFloat64(tier) * 0.05;
                let y = zone#height - 0.6 - Int32.toFloat64(tier) * 0.45;
                let along = if (dc != 0) Vec3.v3(thick, thick, m#cellSize) else Vec3.v3(m#cellSize, thick, thick);
                { center = Vec3.v3(cx + nx * inset, y, cz + nz * inset), size = along }
            }))
            |> List.take(count)

    def steel(): Color = Color.rgb(0.32, 0.34, 0.37)
}
