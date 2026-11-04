// Tracers — 連射銃の曳光弾（純粋）: 撃った瞬間に銃口の近くから当たった所まで、光る細い線（tracer）が速さ speed で飛ぶ。
// 線は 1 つの細い箱の形（Res が 1 回だけ作る）を、頭と尻の間に伸ばして置く。頭が当たった所に着き、尻が追いついたら消える。
// 値は Particles3dDoc の tracer。同時に飛ぶ数は limit で止め、越えたら古い物から消す。
mod Tracers {
    use fge::{Mat4, Mesh3d, Num, Scene3d, ShaderDoc, Vec3}
    use fge::ShaderDoc.{Field, Shade, Out}

    /// 曳光弾 1 本: 出た点・着く点（ステージの座標）・撃った時刻。
    pub type alias Tracer = { origin = Vec3.Vec3, target = Vec3.Vec3, born = Float64 }

    /// 線の形（長さ 1・太さ 1 の +Z へ伸びる箱）と、自分で光る半透明の材質。
    pub type alias Art = { mesh = Mesh3d.Mesh3d, material = Scene3d.Material3d }

    /// 撃った回（何回目か）に曳光弾を出すか（連射銃の every 発に 1 発）。
    pub def isDue(doc: Particles3dDoc.Tracer, w: WeaponsDoc.Weapon, shot: Int32): Bool =
        w == WeaponsDoc.Weapon.Rifle and doc#every > 0 and Int32.modulo(shot, doc#every) == 0

    /// 曳光弾を足す（新しい物が前・上限を越えたら古い物から消す）。
    pub def add(doc: Particles3dDoc.Tracer, tr: Tracer, list: List[Tracer]): List[Tracer] =
        List.take(Int32.max(0, doc#limit), tr :: list)

    def lengthOf(tr: Tracer): Float64 = Vec3.length(Vec3.sub(tr#target, tr#origin))

    /// 時刻 t の線の尻と頭（出た点からの m）。まだ見える間だけ。
    def spanAt(doc: Particles3dDoc.Tracer, t: Float64, tr: Tracer): Option[(Float64, Float64)] =
        let d = lengthOf(tr);
        let flown = (t - tr#born) * doc#speed;
        let head = Float64.min(d, flown);
        let tail = Num.clamp(0.0, d, flown - doc#length);
        if (t < tr#born or head <= tail) None else Some((tail, head))

    /// 時刻 t に消えた曳光弾を落とす。
    pub def step(doc: Particles3dDoc.Tracer, t: Float64, list: List[Tracer]): List[Tracer] =
        list |> List.filter(tr -> t < tr#born or Option.nonEmpty(spanAt(doc, t, tr)))

    /// 線の形と材質（tracer の色と明るさと濃さ。Doc を読み直した時に作り直す）。
    pub def artOf(doc: Particles3dDoc.Tracer): Art =
        let corners = (z: Float64) -> (Vec3.v3(-0.5, -0.5, z), Vec3.v3(0.5, -0.5, z), Vec3.v3(0.5, 0.5, z), Vec3.v3(-0.5, 0.5, z));
        let (a0, b0, c0, d0) = corners(0.0);
        let (a1, b1, c1, d1) = corners(1.0);
        let quad = (p: Vec3.Vec3, q: Vec3.Vec3, r: Vec3.Vec3, s: Vec3.Vec3) -> { points = p :: q :: r :: s :: Nil, color = doc#color };
        let mesh = Mesh3d.fromPolygons(quad(a0, a1, b1, b0) :: quad(b0, b1, c1, c0) :: quad(c0, c1, d1, d0) :: quad(d0, d1, a1, a0) :: Nil);
        let vc = chan -> Field.VertexColor({ chan = chan });
        let spec = { name = "conduit_tracer", cycleRate = 0.0, bindings = Nil,
                     out = Out.Fill({ shade = Shade.Rgb({ r = vc(ShaderDoc.TexChan.R), g = vc(ShaderDoc.TexChan.G), b = vc(ShaderDoc.TexChan.B) }),
                                      alpha = Field.Const(Num.clamp01(doc#alpha)) }) };
        { mesh = mesh,
          material = Scene3d.material(spec) |> Scene3d.withEmission(Shade.Solid(doc#color)) |> Scene3d.withEmissionIntensity(doc#intensity)
                         |> Scene3d.withAlphaBlend(true) |> Scene3d.withDoubleSided(true) }

    /// +Z を向き d（長さ 1）へ向ける回転（x・y は d と直角な 2 本）。
    def facing(d: Vec3.Vec3): Mat4.Mat4 =
        let helper = if (Float64.abs(d#y) < 0.9) Vec3.v3(0.0, 1.0, 0.0) else Vec3.v3(1.0, 0.0, 0.0);
        let u = Vec3.normalized(Vec3.cross(helper, d));
        let v = Vec3.cross(d, u);
        Mat4.ofLinearRows(Vec3.v3(u#x, v#x, d#x), Vec3.v3(u#y, v#y, d#y), Vec3.v3(u#z, v#z, d#z))

    /// 時刻 t の曳光弾の頭の点（ステージの座標。頭に光る玉を重ねて、遠くでも飛んでいる物に見せる）。
    pub def headsOf(doc: Particles3dDoc.Tracer, t: Float64, list: List[Tracer]): List[Vec3.Vec3] =
        list |> List.filterMap(tr -> spanAt(doc, t, tr) |> Option.map(span ->
            Vec3.add(tr#origin, Vec3.mul(Vec3.normalized(Vec3.sub(tr#target, tr#origin)), snd(span)))))

    /// 時刻 t の曳光弾の置いた物（尻から頭まで伸ばした線）。
    pub def instancesOf(doc: Particles3dDoc.Tracer, art: Art, t: Float64, list: List[Tracer]): List[Scene3d.Instance3d] =
        list |> List.filterMap(tr -> spanAt(doc, t, tr) |> Option.map(span -> {
            let (tail, head) = span;
            let d = Vec3.normalized(Vec3.sub(tr#target, tr#origin));
            let start = Vec3.add(tr#origin, Vec3.mul(d, tail));
            let world = Mat4.mul(Mat4.translate(start), Mat4.mul(facing(d), Mat4.scale(Vec3.v3(doc#width, doc#width, head - tail))));
            Scene3d.meshInstance(art#mesh, world) |> Scene3d.withMaterial(art#material) |> Scene3d.withName("tracer")
        }))
}
