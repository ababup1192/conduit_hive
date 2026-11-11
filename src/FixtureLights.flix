// FixtureLights — 色の光を出す物（look の fixtures）のうち、毎コマ動く光（純粋）: 警告の回転灯（光る灯と回る 2 本のスポット）と、壊れて明滅する蛍光灯。
// 物の取り付け（腕・灯具の枠）と、動かない物（非常口の灯り・制御盤・タンク・消火栓）の形と光は modeling/stage.py がステージに組んでベイクする。
// 置き場所はマス（列・行）の、付ける壁の真ん中から内へ寄せた点（stage.py の fixtures.py と同じ決め方）。
// WhyNot: 回転灯と蛍光灯をベイクしない — 回る光と明滅は lightmap に焼けない。
// WhyNot: スポットを回転灯ごとに出さない — engine が 1 つの場面で計算するスポットは 2 本まで。目に近い 1 つの回転灯の 2 本の筋だけにする。
mod FixtureLights {
    use fge::{Color, Hash01, Mat4, Num, Scene3d, Sort, Vec3}
    use LookDoc.FixtureKind

    /// 毎コマ光る物 1 つ: 区画の文字・種類・光る点・光る箱の大きさ・色・番号（明滅をずらす）。
    pub type alias Light = { zone = Char, kind = FixtureKind, at = Vec3.Vec3, size = Vec3.Vec3, color = Color, index = Int32 }

    /// 回転灯の灯の高さと、壁から内へ出す長さ（m）・光る箱の大きさ。蛍光灯は天井から下げる長さと壁から内へ寄せる長さ（m）・管の長さと太さ。
    // WhyNot: Doc へ出さない — 物の形の値で、stage.py の fixtures.py と同じ数でないと光が取り付けから外れる。
    def beaconHeight(): Float64 = 2.5
    def beaconOut(): Float64 = 0.24
    def flickerDrop(): Float64 = 0.14
    def flickerOut(): Float64 = 1.0

    /// 壁の向き（'n' = 北 = +z・'e' = 東 = +x・'s'・'w'）の、マスの真ん中から壁へ向く向き（x・z）。
    def dirOf(side: Char): (Float64, Float64) = match side {
        case 'n' => (0.0, 1.0)
        case 's' => (0.0, -1.0)
        case 'e' => (1.0, 0.0)
        case _   => (-1.0, 0.0)
    }

    /// look の fixtures のうち回転灯と蛍光灯の、光る点（区画の外のマスに置いた物は置かない）。
    pub def lightsOf(look: LookDoc.Rec, maze: Maze.Maze): List[Light] =
        look#fixtures |> List.zipWithIndex |> List.filterMap(e -> {
            let (i, f) = e;
            let cell = { col = f#x, row = f#y };
            Maze.zoneAt(maze, Maze.centerOf(maze, cell) |> fst, Maze.centerOf(maze, cell) |> snd) |> Option.flatMap(zid -> {
                let (cx, cz) = Maze.centerOf(maze, cell);
                let (dx, dz) = dirOf(f#side);
                let wall = (out: Float64) -> (cx + dx * (maze#cellSize / 2.0 - out), cz + dz * (maze#cellSize / 2.0 - out));
                let along = if (dx == 0.0) Vec3.v3(1.2, 0.05, 0.08) else Vec3.v3(0.08, 0.05, 1.2);
                match f#kind {
                    case FixtureKind.Beacon  =>
                        let (x, z) = wall(beaconOut());
                        Some({ zone = zid, kind = f#kind, at = Vec3.v3(x, beaconHeight(), z), size = Vec3.v3(0.26, 0.24, 0.26), color = f#color, index = i })
                    case FixtureKind.Flicker =>
                        let (x, z) = wall(flickerOut());
                        Some({ zone = zid, kind = f#kind, at = Vec3.v3(x, Maze.heightAt(maze, cell) - flickerDrop(), z), size = along, color = f#color, index = i })
                    case _ => None
                }
            })
        })

    /// 蛍光灯 l の時刻 t の明るさ（0 か 1 の間。ほとんど点いていて、時々ちらついて消える）。
    def flickerAt(fl: LookDoc.FlickerLight, t: Float64, l: Light): Float64 =
        let step = Num.floorInt(t * Float64.max(0.1, fl#rate));
        let off = Hash01.at(step, 70 + l#index) < Num.clamp01(fl#dark);
        let buzz = 0.85 + 0.15 * Hash01.at(step, 90 + l#index);
        if (off) 0.08 else buzz

    /// 物の点光源（回転灯の灯・蛍光灯）。
    pub def pointLightsOf(look: LookDoc.Rec, t: Float64, lights: List[Light]): List[Scene3d.PointLight] =
        lights |> List.map(l -> match l#kind {
            case FixtureKind.Flicker => { position = l#at, color = l#color, intensity = look#flicker#intensity * flickerAt(look#flicker, t, l), range = look#flicker#range }
            case _                   => { position = l#at, color = l#color, intensity = look#beacon#intensity, range = look#beacon#range }
        })

    /// 目 eye に一番近い回転灯の、反対向きに回る 2 本の筋（少し下を向く）。
    pub def beamsOf(look: LookDoc.Rec, t: Float64, eye: Vec3.Vec3, lights: List[Light]): List[Scene3d.SpotLight] =
        let b = look#beacon;
        let near = lights |> List.filter(l -> l#kind == FixtureKind.Beacon) |> Sort.sortStableBy(l -> Vec3.length(Vec3.sub(l#at, eye))) |> List.head;
        near |> Option.toList |> List.flatMap(l -> List.range(0, 2) |> List.map(k -> {
            let angle = b#spin * t + Int32.toFloat64(k) * Num.pi();
            let target = Vec3.add(l#at, Vec3.v3(Num.cos(angle), -0.3, Num.sin(angle)));
            { color = l#color, intensity = b#beamIntensity, range = b#beamRange, innerFovY = Some(b#beamFov * 0.4) | Scene3d.spotLight(l#at, target, b#beamFov) }
        }))

    /// 光る箱（回転灯の灯と蛍光灯の管。蛍光灯は明滅に合わせて光る）。
    pub def instancesOf(look: LookDoc.Rec, t: Float64, lights: List[Light]): List[Scene3d.Instance3d] =
        lights |> List.map(l -> {
            let k = match l#kind {
                case FixtureKind.Flicker => 6.0 * flickerAt(look#flicker, t, l)
                case _                   => 5.0
            };
            Scene3d.meshInstance(BoxMesh.of(l#color, { center = l#at, size = l#size } :: Nil), Mat4.identity()) |> Scene3d.withName("fixture")
                |> Scene3d.withMaterial(MazeMesh.glowMaterial("conduit_fixture", l#color, k))
        })
}
