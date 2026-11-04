// HordeScene — 測り（make bench-horde）だけが使う、仮の敵の群れとパイプの仮置き（純粋）。普段の遊びからは呼ばない。
//
// 敵は最後の部屋に散らばって立ち、プレイヤーへまっすぐ歩いて寄るだけ（追う・押し合いは段 2 の仕事）。
// 姿勢の作り方を 3 つの軸で切り替えて比べる:
//   Each   … 毎コマ全員の姿勢をクリップから作る
//   Shared … 歩きの時刻を groups 通りに丸め、同じ組の敵は 1 つの姿勢を共有する
//   throttle … 遠い敵と背中側の敵は 3 コマに 1 回だけ姿勢を作り直し、間は前の姿勢を使う
// パイプは区画ごとに細長い箱を pipes 個まで、壁ぎわの天井近くに 3 段で並べる（区画ごとに 1 つの形へまとめるか、ばらばらか）。
mod HordeScene {
    use fge::{AnimationClip3d, Color, Hash01, Mat4, Model3d, Num, Pose3d, Scene3d, Skin3d, Vec3}

    /// 姿勢の作り方。
    pub enum PoseMode with Eq, ToString {
        case Each
        case Shared
    }

    /// 体の部品の置き方。Split = glb の材質ごとの部品（guard は 12）・Merged = 部品を 1 つの形にまとめた物（1 体 1 材質の見込み）。
    pub enum Parts with Eq, ToString {
        case Split
        case Merged
    }

    /// パイプの箱の形の持ち方。PerZone = 区画ごとに 1 つの形へまとめる・Loose = 箱ごとに置く。
    pub enum PipeMesh with Eq, ToString {
        case PerZone
        case Loose
    }

    /// 測る組 1 つ。groups = Shared の時の時刻の通り数・pipes = 1 区画あたりの箱の数（0 で無し）。
    pub type alias Config = {
        label = String,
        enemies = Int32,
        pose = PoseMode,
        groups = Int32,
        throttle = Bool,
        parts = Parts,
        pipes = Int32,
        pipeMesh = PipeMesh
    }

    /// 仮の敵の体（骨つきの glb と歩きのクリップ）。
    pub type alias Body = { model = Model3d.Model3d, skin = Skin3d.Skin3d, clip = AnimationClip3d.AnimationClip3d }

    /// 敵 1 体: 足元・向き（ラジアン）・歩きの時刻のずれ（秒）・今の姿勢。
    pub type alias Enemy = { x = Float64, z = Float64, yaw = Float64, phase = Float64, pose = Pose3d.Pose3d }

    /// 群れ: 敵・今のコマに作った姿勢の数・コマの番号・歩きの時刻（秒）。
    pub type alias Horde = { enemies = List[Enemy], computed = Int32, frame = Int32, t = Float64 }

    /// 見ている人: 足元と向き（ラジアン。0 が北 = +z・90 度が東 = +x）。
    pub type alias Viewer = { x = Float64, z = Float64, yaw = Float64 }

    /// 歩く速さ（m/秒）と、プレイヤーの手前で止まる距離（m）。
    def walkSpeed(): Float64 = 1.4
    def stopDistance(): Float64 = 2.5

    /// 遠い敵の境目（m）。これより遠いか背中側なら間引く。
    def farDistance(): Float64 = 12.0

    /// 間引く敵が姿勢を作り直す間隔（コマ）。
    def throttleEvery(): Int32 = 3

    // ── 置く ──

    /// 最後の部屋の床のマスへ count 体を散らして置く。プレイヤーから 6 m より近いマスには置かない。
    pub def spawnHorde(cfg: Config, body: Body, m: Maze.Maze, zone: Char, viewer: Viewer): Horde =
        let cells = Map.get(zone, m#zones) |> Option.map(z -> z#cells) |> Option.getWithDefault(Nil)
            |> List.filter(c -> { let (cx, cz) = Maze.centerOf(m, c); distance(cx - viewer#x, cz - viewer#z) > 6.0 });
        let n = List.length(cells);
        let duration = Float64.max(0.001, AnimationClip3d.duration(body#clip));
        let enemies = if (n == 0) Nil else List.range(0, cfg#enemies) |> List.filterMap(i ->
            List.drop(Hash01.indexOf({ index = i, channel = 1 }, n), cells) |> List.head |> Option.map(cell -> {
                let (cx, cz) = Maze.centerOf(m, cell);
                let x = cx + (Hash01.at(i, 2) - 0.5) * m#cellSize * 0.8;
                let z = cz + (Hash01.at(i, 3) - 0.5) * m#cellSize * 0.8;
                let phase = phaseOf(cfg, duration, i);
                { x = x, z = z, yaw = facing(viewer, x, z), phase = phase, pose = poseAt(body, phase) }
            }));
        { enemies = enemies, computed = List.length(enemies), frame = 0, t = 0.0 }

    /// 歩きの時刻のずれ。Shared は groups 通りに丸める（同じ組は同じ時刻）。
    def phaseOf(cfg: Config, duration: Float64, i: Int32): Float64 = match cfg#pose {
        case PoseMode.Each   => Hash01.at(i, 4) * duration
        case PoseMode.Shared => Int32.toFloat64(Int32.modulo(i, Int32.max(1, cfg#groups))) * duration / Int32.toFloat64(Int32.max(1, cfg#groups))
    }

    def distance(dx: Float64, dz: Float64): Float64 = Num.sqrt(dx * dx + dz * dz)

    /// 敵の足元から見ている人へ向く角。
    def facing(viewer: Viewer, x: Float64, z: Float64): Float64 = Num.atan2(viewer#x - x, viewer#z - z)

    /// 歩きのクリップの t 秒目の姿勢（night_apartment の People.poseAt と同じ素朴な形）。
    def poseAt(body: Body, t: Float64): Pose3d.Pose3d =
        Pose3d.compute(body#skin, AnimationClip3d.sample(body#skin, body#clip, t, true))

    // ── 1 コマ進める ──

    /// dt 秒進める: 全員がプレイヤーへ歩き、姿勢を作る（作り方は cfg）。
    pub def step(cfg: Config, body: Body, viewer: Viewer, dt: Float64, h: Horde): Horde =
        let t = h#t + dt;
        let moved = h#enemies |> List.map(e -> walk(viewer, dt, e));
        let due = moved |> List.zipWithIndex |> List.map(p -> { let (i, e) = p; (isDue(cfg, viewer, h#frame, i, e), e) });
        let shared = sharedPoses(cfg, body, t, due);
        let posed = due |> List.map(p -> { let (d, e) = p; if (d) { pose = poseOf(cfg, body, shared, t, e) | e } else e });
        let made = match cfg#pose {
            case PoseMode.Shared => Map.size(shared)
            case PoseMode.Each   => due |> List.count(fst)
        };
        { enemies = posed, computed = made, frame = h#frame + 1, t = t }

    def walk(viewer: Viewer, dt: Float64, e: Enemy): Enemy =
        let dx = viewer#x - e#x;
        let dz = viewer#z - e#z;
        let d = distance(dx, dz);
        let stride = Float64.min(walkSpeed() * dt, Float64.max(0.0, d - stopDistance()));
        if (d < 0.001) e
        else { x = e#x + dx / d * stride, z = e#z + dz / d * stride, yaw = facing(viewer, e#x, e#z) | e }

    /// このコマに姿勢を作り直すか。間引かない時・近くて前にいる時はいつも。間引く時は 3 コマに 1 回（敵ごとにずらす）。
    def isDue(cfg: Config, viewer: Viewer, frame: Int32, index: Int32, e: Enemy): Bool =
        let dx = e#x - viewer#x;
        let dz = e#z - viewer#z;
        let ahead = dx * Num.sin(viewer#yaw) + dz * Num.cos(viewer#yaw);
        let isNearFront = distance(dx, dz) <= farDistance() and ahead >= 0.0;
        not cfg#throttle or isNearFront or Int32.modulo(frame + index, throttleEvery()) == 0

    /// Shared の時、今のコマに作り直す敵がいる時刻の組だけ姿勢を作る（鍵は組の番号）。
    def sharedPoses(cfg: Config, body: Body, t: Float64, due: List[(Bool, Enemy)]): Map[Int32, Pose3d.Pose3d] =
        if (cfg#pose != PoseMode.Shared) Map.empty()
        else due |> List.filter(fst) |> List.map(p -> groupOf(cfg, body, snd(p))) |> List.toSet |> Set.toList
            |> List.map(g -> (g, poseAt(body, t + groupPhase(cfg, body, g)))) |> List.toMap

    def groups(cfg: Config): Int32 = Int32.max(1, cfg#groups)

    def groupPhase(cfg: Config, body: Body, g: Int32): Float64 =
        Int32.toFloat64(g) * AnimationClip3d.duration(body#clip) / Int32.toFloat64(groups(cfg))

    /// 敵の時刻のずれから組の番号へ（spawn の phaseOf の逆）。
    def groupOf(cfg: Config, body: Body, e: Enemy): Int32 =
        let duration = Float64.max(0.001, AnimationClip3d.duration(body#clip));
        Int32.modulo(Float64.round(e#phase / duration * Int32.toFloat64(groups(cfg))) |> Float64.tryToInt32 |> Option.getWithDefault(0), groups(cfg))

    def poseOf(cfg: Config, body: Body, shared: Map[Int32, Pose3d.Pose3d], t: Float64, e: Enemy): Pose3d.Pose3d = match cfg#pose {
        case PoseMode.Shared => Map.get(groupOf(cfg, body, e), shared) |> Option.getWithDefault(e#pose)
        case PoseMode.Each   => poseAt(body, t + e#phase)
    }

    // ── 描く物 ──

    /// 敵の置いた物（姿勢つき）。
    pub def instances(cfg: Config, body: Body, h: Horde): List[Scene3d.Instance3d] =
        h#enemies |> List.flatMap(e -> {
            let world = Mat4.mul(Mat4.translate(Vec3.v3(e#x, 0.0, e#z)), Mat4.rotateY(e#yaw));
            partsOf(cfg, body, world) |> List.map(Scene3d.withPose(e#pose))
        })

    def partsOf(cfg: Config, body: Body, world: Mat4.Mat4): List[Scene3d.Instance3d] = match cfg#parts {
        case Parts.Split  => Model3d.partInstances(world, body#model)
        case Parts.Merged => Scene3d.meshInstance(body#model#mesh, world) :: Nil
    }

    // ── パイプの仮置き ──

    /// 区画ごとのパイプの箱の置いた物（pipes が 0 なら空）。
    pub def pipeArt(cfg: Config, m: Maze.Maze): Map[Char, List[Scene3d.Instance3d]] =
        let unit = BoxMesh.unit(steel());
        if (cfg#pipes <= 0) Map.empty()
        else m#zones |> Map.map(zone -> {
            let boxes = pipeBoxes(cfg#pipes, m, zone);
            match cfg#pipeMesh {
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
