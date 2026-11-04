// BlastFx — 手榴弾の爆発の、形で描く部分（純粋）: 膨らんで崩れる火の玉の塊・床を走る衝撃の輪・床の焦げ跡。
// どれも Particles3d の粒（Kind.Blast の Fireball・Ring・Scorch）の出た時刻・点・速さから、今の大きさ・明るさ・濃さを計算して置く。
// 中心の光・煙・火花と破片はビルボードのまま（Particles3d.billboards）。値は Particles3dDoc の blast。
//
// 火の玉の塊は、でこぼこの球を 3 枚の殻に重ねる（内から中心の白・橙・冷めた赤）。殻は半透明なので、
// 真ん中ほど重なる殻が多く明るく、ふちほど外の殻だけが残って暗い赤になる。時間とともに中心から先に消え、外の殻が膨らみながら上へ崩れる。
mod BlastFx {
    use fge::{Color, Hash01, Log, Mat4, Mesh3d, Num, Scene3d, ShaderDoc, Vec3}
    use fge::ShaderDoc.{Field, Shade, Out, BinOp, UnOp}
    use Particles3d.{Kind, BlastPart}

    /// 形と材質: 火の玉の塊の球（でこぼこの違う数種）・衝撃の輪・焦げ跡と残り火の斑点と、どれにも使う 1 つの材質と、殻と輪の色。
    pub type alias Art = { puffs = Vector[Mesh3d.Mesh3d], ring = Mesh3d.Mesh3d, scorch = Mesh3d.Mesh3d, embers = Mesh3d.Mesh3d,
                           fire = Scene3d.Material3d, hot = Color, warm = Color, cool = Color, wave = Color }

    // ── 形 ──

    def puffVariants(): Int32 = 4

    /// 頂点の並びを 1 つの形にする（法線・頂点の色つき）。組めなければ空の形にして 1 行知らせる。
    def meshOf(name: String, points: List[(Vec3.Vec3, Vec3.Vec3, (Float64, Float64, Float64))], tris: List[Int32]): Mesh3d.Mesh3d =
        let flat3 = (p: Vec3.Vec3) -> p#x :: p#y :: p#z :: Nil;
        match Mesh3d.fromArrays({ positions = points |> List.flatMap(p -> { let (at, _, _) = p; flat3(at) }) |> List.toVector,
                                  normals = points |> List.flatMap(p -> { let (_, n, _) = p; flat3(n) }) |> List.toVector,
                                  colors = points |> List.flatMap(p -> { let (_, _, (r, g, b)) = p; r :: g :: b :: Nil }) |> List.toVector,
                                  indices = List.toVector(tris), skin = None }) {
            case Ok(mesh) => mesh
            case Err(e)   => Log.warnThen("[blast] ${name} の形を組めない: ${e}", Mesh3d.fromPolygons(Nil))
        }

    /// 緯度 lat × 経度 lon の格子の三角（極は経度の数だけ重なった点のまま）。
    def gridTris(rows: Int32, lon: Int32): List[Int32] =
        List.range(0, rows) |> List.flatMap(i -> List.range(0, lon) |> List.flatMap(j -> {
            let a = i * lon + j;
            let b = i * lon + Int32.modulo(j + 1, lon);
            let c = (i + 1) * lon + j;
            let d = (i + 1) * lon + Int32.modulo(j + 1, lon);
            a :: c :: b :: b :: c :: d :: Nil
        }))

    /// 向き d の上の、種 seed の 3 つの波の和（-1..1 ほど）。球のでこぼこと、面の明るさのむらに使う。
    def waves(seed: Int32, d: Vec3.Vec3): Float64 =
        List.range(0, 3) |> List.foldLeft((acc, k) -> {
            let key = seed * 7 + k;
            let axis = Vec3.normalized(Vec3.v3(Hash01.at(key, 1) - 0.5, Hash01.at(key, 2) - 0.5, Hash01.at(key, 3) - 0.5));
            let freq = 2.5 + 3.5 * Hash01.at(key, 4);
            acc + Num.sin(freq * Vec3.dot(axis, d) + Num.tau() * Hash01.at(key, 5)) / Int32.toFloat64(k + 1)
        }, 0.0) / 1.8

    /// でこぼこの球（半径 1 ほど）。頂点の色の赤 = 面の明るさと濃さのむら（0.5..1。殻のふちがちぎれて見える）。
    def puffMesh(seed: Int32): Mesh3d.Mesh3d =
        let (lat, lon) = (9, 14);
        let points = List.range(0, lat + 1) |> List.flatMap(i -> List.range(0, lon) |> List.map(j -> {
            let theta = Num.pi() * Int32.toFloat64(i) / Int32.toFloat64(lat);
            let phi = Num.tau() * Int32.toFloat64(j) / Int32.toFloat64(lon);
            let d = Vec3.v3(Num.sin(theta) * Num.cos(phi), Num.cos(theta), Num.sin(theta) * Num.sin(phi));
            let r = 1.0 + 0.2 * waves(seed, d);
            let m = 0.5 + 0.5 * Num.clamp01(0.5 + 0.7 * waves(seed + 50, d));
            (Vec3.mul(d, r), d, (m, m, m))
        }));
        meshOf("火の玉の塊", points, gridTris(lat, lon))

    /// 床に寝かせた輪（半径 1 で外のふち）。頂点の色の赤 = 明るさ（外のふちの少し内が一番明るく、内へ消える）。
    def ringMesh(): Mesh3d.Mesh3d =
        let segs = 48;
        let rows = (0.62, 0.0) :: (0.9, 1.0) :: (1.0, 0.25) :: Nil;
        let points = rows |> List.flatMap(row -> List.range(0, segs) |> List.map(j -> {
            let (r, glow) = row;
            let a = Num.tau() * Int32.toFloat64(j) / Int32.toFloat64(segs);
            (Vec3.v3(r * Num.cos(a), 0.0, r * Num.sin(a)), Vec3.v3(0.0, 1.0, 0.0), (glow, glow, glow))
        }));
        meshOf("衝撃の輪", points, gridTris(List.length(rows) - 1, segs))

    /// 床に寝かせた焦げ跡（半径 1 ほど・ふちはちぎれる）。頂点の色の赤 = 濃さ（真ん中が濃くふちで 0）。
    def scorchMesh(): Mesh3d.Mesh3d =
        let segs = 40;
        let rows = 0.0 :: 0.35 :: 0.7 :: 1.0 :: Nil;
        let points = rows |> List.zipWithIndex |> List.flatMap(row -> List.range(0, segs) |> List.map(j -> {
            let (i, u) = row;
            let a = Num.tau() * Int32.toFloat64(j) / Int32.toFloat64(segs);
            let ragged = if (i == 3) 0.75 + 0.45 * Hash01.at(j, 61) else 1.0;
            let r = u * ragged;
            let dark = if (i == 3) 0.0 else 1.0 - 0.25 * u;
            (Vec3.v3(r * Num.cos(a), 0.0, r * Num.sin(a)), Vec3.v3(0.0, 1.0, 0.0), (dark, dark, dark))
        }));
        meshOf("焦げ跡", points, gridTris(List.length(rows) - 1, segs))

    /// 焦げ跡の中に散らばる残り火の小さな斑（焦げ跡の半径 1 に対して内の 0.65 まで）。頂点の色の赤 = 明るさ（斑の真ん中で 1・ふちで 0）。
    def embersMesh(): Mesh3d.Mesh3d =
        let (count, segs) = (9, 8);
        let spots = List.range(0, count) |> List.map(i -> {
            let a = Num.tau() * Hash01.at(i, 64);
            let d = 0.15 + 0.5 * Hash01.at(i, 65);
            (d * Num.cos(a), d * Num.sin(a), 0.04 + 0.06 * Hash01.at(i, 66))
        });
        let points = spots |> List.flatMap(spot -> {
            let (cx, cz, r) = spot;
            (Vec3.v3(cx, 0.0, cz), Vec3.v3(0.0, 1.0, 0.0), (1.0, 1.0, 1.0)) :: (List.range(0, segs) |> List.map(j -> {
                let a = Num.tau() * Int32.toFloat64(j) / Int32.toFloat64(segs);
                (Vec3.v3(cx + r * Num.cos(a), 0.0, cz + r * Num.sin(a)), Vec3.v3(0.0, 1.0, 0.0), (0.0, 0.0, 0.0))
            }))
        });
        let tris = List.range(0, count) |> List.flatMap(i -> {
            let base = i * (segs + 1);
            List.range(0, segs) |> List.flatMap(j -> base :: base + 1 + j :: base + 1 + Int32.modulo(j + 1, segs) :: Nil)
        });
        meshOf("残り火", points, tris)

    // ── 材質 ──

    def vc(chan: ShaderDoc.TexChan): Field = Field.VertexColor({ chan = chan })

    def by(chan: ShaderDoc.TexChan, param: String): Field = Field.Bin({ op = BinOp.Mul, a = vc(chan), b = Field.Param({ name = param }) })

    /// 頂点の色の赤 × 置いた物ごとの色（"r"・"g"・"b"）で自分で光る色。
    // WhyNot: 殻・輪・焦げ跡ごとに色を定数で書いた材質を分けない — GL は emission の中身ごとにプログラムを作り、初めての爆発のコマで 5 本の組み立てが重なって 180 ms 止まった。
    def tintedGlow(): Shade = Shade.Rgb({ r = by(ShaderDoc.TexChan.R, "r"), g = by(ShaderDoc.TexChan.R, "g"), b = by(ShaderDoc.TexChan.R, "b") })

    /// 頂点の色の赤 × 置いた物ごとの値で光り、濃さも頂点の色の赤 × "a" で決める半透明の材質（地の色は黒で、光を受けない）。
    def fireMaterial(): Scene3d.Material3d =
        let alpha = Field.Un({ op = UnOp.Sat, of = by(ShaderDoc.TexChan.R, "a") });
        let spec = { name = "conduit_blast", cycleRate = 0.0, bindings = Nil, out = Out.Fill({ shade = Shade.Solid(Color.rgb(0.0, 0.0, 0.0)), alpha = alpha }) };
        Scene3d.material(spec) |> Scene3d.withEmission(tintedGlow()) |> Scene3d.withAlphaBlend(true) |> Scene3d.withDoubleSided(true)

    /// 形と材質を組む（読み込みと粒の Doc を読み直した時だけ）。
    pub def artOf(b: Particles3dDoc.Blast): Art =
        let fb = b#fireball;
        { puffs = List.range(0, puffVariants()) |> List.map(i -> puffMesh(17 + i * 13)) |> List.toVector,
          ring = ringMesh(), scorch = scorchMesh(), embers = embersMesh(), fire = fireMaterial(),
          hot = fb#hot, warm = fb#puff#color, cool = fb#cool, wave = b#ring#color }

    // ── 置く ──

    def smooth(lo: Float64, hi: Float64, x: Float64): Float64 =
        let u = Num.clamp01((x - lo) / Float64.max(0.0001, hi - lo));
        u * u * (3.0 - 2.0 * u)

    def easeOut(u: Float64): Float64 = { let v = 1.0 - Num.clamp01(u); 1.0 - v * v * v }

    /// 置いた物ごとの光る色 c・濃さ・明るさを付ける。
    def lit(m: Scene3d.Material3d, c: Color, alpha: Float64, intensity: Float64, mesh: Mesh3d.Mesh3d, world: Mat4.Mat4): Scene3d.Instance3d =
        let mat = m |> Scene3d.withParams(Map#{ "a" => Num.clamp(0.0, 2.0, alpha), "r" => c#r, "g" => c#g, "b" => c#b })
                    |> Scene3d.withEmissionIntensity(Float64.max(0.0, intensity));
        Scene3d.meshInstance(mesh, world) |> Scene3d.withMaterial(mat) |> Scene3d.withName("blast")

    /// パーティクルごとの散らし（パーティクルは番号を持たないので、出た速さから引く。同じパーティクルは毎コマ同じ値）。
    def keyOf(p: Particles3d.Particle): Int32 = Num.roundInt(p#velocity#x * 977.0) * 31 + Num.roundInt(p#velocity#z * 613.0) + Num.roundInt(p#velocity#y * 389.0)

    /// 爆発が床から離れすぎていないか（宙で弾けた時は床に輪も焦げも描かない）。
    def nearFloor(p: Particles3d.Particle): Bool = p#origin#y < 1.2

    /// 火の玉の塊 1 つ: 出た向きへ飛び出してすぐ止まり（空気に押し戻される）、上へ昇る。大きさは最初の 2 割で膨らみ切り、
    /// 後半は横に広がって縦に潰れる。殻は中心から先に消える。内の殻ほど目の側へ少し寄せる。
    // WhyNot: 3 枚の殻を同じ点に置かない — 半透明を描く順は形の境界の真ん中の遠さで決まり、でこぼこの球では殻ごとに真ん中がずれて、
    // 外の冷めた殻が中心の上に描かれるコマが出る（火の玉が暗い赤い風船に見える）。
    def puffOf(fb: Particles3dDoc.Fireball, art: Art, eye: Vec3.Vec3, age: Float64, p: Particles3d.Particle): List[Scene3d.Instance3d] =
        let b = fb#puff;
        let k = age / Float64.max(0.0001, p#life);
        let key = keyOf(p);
        let travel = 0.25 * easeOut(age / 0.3);
        let at = Vec3.add(p#origin, Vec3.v3(p#velocity#x * travel, p#velocity#y * travel - 0.5 * b#gravity * age * age, p#velocity#z * travel));
        let r = b#size * (0.3 + 0.7 * easeOut(k / 0.22)) * (1.0 + (b#grow - 1.0) * k);
        let slump = smooth(0.45, 1.0, k);
        let size = Vec3.v3(r * (1.0 + 0.25 * slump), r * (1.0 - 0.35 * slump), r * (1.0 + 0.25 * slump));
        let turn = Mat4.mul(Mat4.rotateY(Num.tau() * Hash01.at(key, 71) + 0.6 * age), Mat4.rotateX(Num.pi() * Hash01.at(key, 72)));
        let mesh = Vector.nth(Int32.modulo(Int32.abs(key), puffVariants()), art#puffs) |> Option.getWithDefault(Mesh3d.fromPolygons(Nil));
        let toEye = Vec3.normalized(Vec3.sub(eye, at));
        let place = (k0: Float64) -> Mat4.mul(Mat4.translate(Vec3.add(at, Vec3.mul(toEye, r * 0.5 * (1.0 - k0)))), Mat4.mul(Mat4.scale(Vec3.mul(size, k0)), turn));
        let i = b#intensity;
        lit(art#fire, art#cool, 0.75 * (1.0 - smooth(0.5, 1.0, k)), i * 0.55 * (1.0 - k), mesh, place(1.0))
            :: lit(art#fire, art#warm, 0.95 * (1.0 - smooth(0.25, 0.8, k)), i * (1.0 - 0.6 * k), mesh, place(0.8))
            :: lit(art#fire, art#hot, 1.2 * (1.0 - smooth(0.06, 0.45, k)), i * 1.5 * (1.0 - smooth(0.0, 0.5, k)), mesh, place(0.55))
            :: Nil

    /// 床を走る衝撃の輪: すぐ広がり切って薄れる。
    def ringOf(b: Particles3dDoc.Burst, art: Art, age: Float64, p: Particles3d.Particle): List[Scene3d.Instance3d] =
        let k = age / Float64.max(0.0001, p#life);
        let r = b#size * (1.0 + (b#grow - 1.0) * easeOut(k));
        let fade = (1.0 - k) * (1.0 - k);
        let world = Mat4.mul(Mat4.translate(Vec3.v3(p#origin#x, floorLift() * 2.0, p#origin#z)), Mat4.scale(Vec3.v3(r, 1.0, r)));
        if (nearFloor(p)) lit(art#fire, art#wave, 0.85 * fade, b#intensity * fade, art#ring, world) :: Nil else Nil

    /// 床の焦げ跡（光を受けない焦げの色）: すぐに出て、寿命の終わりに薄れて消える。中の残り火の斑点（火の玉の橙）は寿命の最初の 15% で消える。
    def scorchOf(fb: Particles3dDoc.Fireball, b: Particles3dDoc.Burst, art: Art, age: Float64, p: Particles3d.Particle): List[Scene3d.Instance3d] =
        let k = age / Float64.max(0.0001, p#life);
        let yaw = Num.tau() * Hash01.at(keyOf(p), 73);
        let at = (lift: Float64) -> Mat4.mul(Mat4.translate(Vec3.v3(p#origin#x, lift, p#origin#z)), Mat4.mul(Mat4.rotateY(yaw), Mat4.scale(Vec3.v3(b#size, 1.0, b#size))));
        let glow = 1.0 - smooth(0.0, 0.15, k);
        let embers = if (glow <= 0.0) Nil else lit(art#fire, fb#puff#color, glow, b#intensity * glow, art#embers, at(floorLift() * 1.5)) :: Nil;
        if (nearFloor(p)) lit(art#fire, b#color, 0.85 * (1.0 - smooth(0.7, 1.0, k)), 1.0, art#scorch, at(floorLift())) :: embers else Nil

    /// 床から浮かせる高さ（m）。
    // WhyNot: 床と同じ高さに置かない — 深度が床と取り合って、焦げ跡が縞に欠ける。
    def floorLift(): Float64 = 0.012

    /// 時刻 t の爆発の形（火の玉の塊・衝撃の輪・焦げ跡）の置いた物。eye = 描くカメラの目の位置。
    pub def instancesOf(doc: Particles3dDoc.Doc, art: Art, eye: Vec3.Vec3, t: Float64, ps: List[Particles3d.Particle]): List[Scene3d.Instance3d] =
        let b = Particles3dDoc.rec(doc)#blast;
        ps |> List.flatMap(p -> {
            let age = t - p#born;
            if (age < 0.0 or age >= p#life) Nil
            else match p#kind {
                case Kind.Blast(BlastPart.Fireball) => puffOf(b#fireball, art, eye, age, p)
                case Kind.Blast(BlastPart.Ring)     => ringOf(b#ring, art, age, p)
                case Kind.Blast(BlastPart.Scorch)   => scorchOf(b#fireball, b#scorch, art, age, p)
                case _                              => Nil
            }
        })
}
