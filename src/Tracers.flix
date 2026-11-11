// Tracers — 曳光弾（純粋）: 撃った瞬間に銃口の近くから当たった所まで、光る細い線（tracer）が速さ speed で飛ぶ。武器ごとに値が違い、散弾は細く短い線を何本か出す。
// 線は 1 つの細い箱の形（Res が 1 回だけ作る）を、頭と尻の間に伸ばして置く。光る芯と、同じ線を太く薄くしたにじむ外側の 2 本を重ねる。
// 頭が当たった所に着き、尻が追いついたら消える。値は Particles3dDoc の tracers。同時に飛ぶ数は撃った武器の limit で止め、越えたら古い物から消す。
mod Tracers {
    use fge::{Color, Mat4, Mesh3d, Num, Scene3d, ShaderDoc, Vec3}
    use fge::ShaderDoc.{Field, Shade, Out}
    use WeaponsDoc.Weapon

    /// 曳光弾 1 本: 出た点・着く点（ステージの座標）・撃った時刻・撃った武器。
    pub type alias Tracer = { origin = Vec3.Vec3, target = Vec3.Vec3, born = Float64, weapon = Weapon }

    /// 線の形（長さ 1・太さ 1 の +Z へ伸びる箱）と、武器ごとの自分で光る半透明の材質（芯とにじむ外側）。
    /// spit = ranged の projectile の光る尾の材質（芯と外側。形は曳光弾と同じ箱）。
    pub type alias Art = { mesh = Mesh3d.Mesh3d, materials = Map[Weapon, { core = Scene3d.Material3d, glow = Scene3d.Material3d }],
                           spit = { core = Scene3d.Material3d, glow = Scene3d.Material3d } }

    /// 撃った回（何回目か）に曳光弾を出すか（その武器の every 発に 1 発。every が 0 なら出さない）。
    pub def isDue(doc: Particles3dDoc.Tracer, shot: Int32): Bool =
        doc#every > 0 and doc#count > 0 and Int32.modulo(shot, doc#every) == 0

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

    def docOf(docs: Particles3dDoc.Tracers, tr: Tracer): Particles3dDoc.Tracer = match tr#weapon {
        case Weapon.Pistol  => docs#pistol
        case Weapon.Shotgun => docs#shotgun
        case Weapon.Rifle   => docs#rifle
    }

    /// 時刻 t に消えた曳光弾を落とす。
    pub def step(docs: Particles3dDoc.Tracers, t: Float64, list: List[Tracer]): List[Tracer] =
        list |> List.filter(tr -> t < tr#born or Option.nonEmpty(spanAt(docOf(docs, tr), t, tr)))

    /// 線の形と、武器ごとの材質（芯 = tracer の色と明るさと濃さ・外側 = 同じ色で glowAlpha の濃さ。Doc を読み直した時に作り直す）。
    pub def artOf(docs: Particles3dDoc.Tracers, spit: Particles3dDoc.Glow): Art =
        // 8 角の筒で、尻（z = 0）を頭（z = 1）の 3 割の太さにすぼめる（先が太く尾へ細る光。真正面から見ても角張った四角に見えない）。
        let ring = (z: Float64, r: Float64) -> List.range(0, 8) |> List.map(k -> {
            let a = Int32.toFloat64(k) * Num.tau() / 8.0;
            Vec3.v3(r * Num.cos(a), r * Num.sin(a), z)
        }) |> List.toVector;
        let (tail, head) = (ring(0.0, 0.15), ring(1.0, 0.5));
        let quad = (p: Vec3.Vec3, q: Vec3.Vec3, r: Vec3.Vec3, s: Vec3.Vec3) -> { points = p :: q :: r :: s :: Nil, color = Color.rgb(1.0, 1.0, 1.0) };
        let side = (k: Int32) -> { let k2 = Int32.modulo(k + 1, 8); quad(Vector.get(k, tail), Vector.get(k, head), Vector.get(k2, head), Vector.get(k2, tail)) };
        let mesh = Mesh3d.fromPolygons(List.range(0, 8) |> List.map(side));
        let pair = (name: String, doc: Particles3dDoc.Tracer) ->
            { core = glowingMaterial("conduit_tracer_${name}", doc#color, doc#intensity, doc#alpha),
              glow = glowingMaterial("conduit_tracer_${name}_glow", doc#color, doc#intensity, doc#glowAlpha) };
        { mesh = mesh, materials = Map#{ Weapon.Pistol => pair("pistol", docs#pistol), Weapon.Shotgun => pair("shotgun", docs#shotgun),
                                         Weapon.Rifle => pair("rifle", docs#rifle) },
          spit = { core = glowingMaterial("conduit_spit", spit#core, spit#intensity, 0.95), glow = glowingMaterial("conduit_spit_glow", spit#color, spit#intensity, spit#glowAlpha) } }

    /// 色 c で自分で光る半透明の材質（濃さ alpha）。
    def glowingMaterial(name: String, c: Color, intensity: Float64, alpha: Float64): Scene3d.Material3d =
        let spec = { name = name, cycleRate = 0.0, bindings = Nil,
                     out = Out.Fill({ shade = Shade.Solid(c), alpha = Field.Const(Num.clamp01(alpha)) }) };
        Scene3d.material(spec) |> Scene3d.withEmission(Shade.Solid(c)) |> Scene3d.withEmissionIntensity(intensity)
            |> Scene3d.withAlphaBlend(true) |> Scene3d.withDoubleSided(true)

    /// +Z を向き d（長さ 1）へ向ける回転（x・y は d と直角な 2 本）。
    def facing(d: Vec3.Vec3): Mat4.Mat4 =
        let helper = if (Float64.abs(d#y) < 0.9) Vec3.v3(0.0, 1.0, 0.0) else Vec3.v3(1.0, 0.0, 0.0);
        let u = Vec3.normalized(Vec3.cross(helper, d));
        let v = Vec3.cross(d, u);
        Mat4.ofLinearRows(Vec3.v3(u#x, v#x, d#x), Vec3.v3(u#y, v#y, d#y), Vec3.v3(u#z, v#z, d#z))

    /// 時刻 t の曳光弾の頭の点（ステージの座標。頭に光る玉を重ねて、遠くでも飛んでいる物に見せる）と、その武器の値。
    pub def headsOf(docs: Particles3dDoc.Tracers, t: Float64, list: List[Tracer]): List[(Vec3.Vec3, Particles3dDoc.Tracer)] =
        list |> List.filterMap(tr -> { let doc = docOf(docs, tr); spanAt(doc, t, tr) |> Option.map(span ->
            (Vec3.add(tr#origin, Vec3.mul(Vec3.normalized(Vec3.sub(tr#target, tr#origin)), snd(span))), doc)) })

    /// 時刻 t の曳光弾の置いた物（尻から頭まで伸ばした芯と、その外側のにじみ）。
    pub def instancesOf(docs: Particles3dDoc.Tracers, art: Art, t: Float64, list: List[Tracer]): List[Scene3d.Instance3d] =
        list |> List.flatMap(tr -> {
            let doc = docOf(docs, tr);
            let found = (spanAt(doc, t, tr), Map.get(tr#weapon, art#materials));
            match found {
                case (Some((tail, head)), Some(m)) =>
                    let d = Vec3.normalized(Vec3.sub(tr#target, tr#origin));
                    let start = Vec3.add(tr#origin, Vec3.mul(d, tail));
                    let line = (width: Float64, material: Scene3d.Material3d) ->
                        Scene3d.meshInstance(art#mesh, Mat4.mul(Mat4.translate(start), Mat4.mul(facing(d), Mat4.scale(Vec3.v3(width, width, head - tail)))))
                            |> Scene3d.withMaterial(material) |> Scene3d.withName("tracer");
                    let halo = if (doc#glowAlpha > 0.0) line(doc#width * Float64.max(1.0, doc#glowWidth), m#glow) :: Nil else Nil;
                    line(doc#width, m#core) :: halo
                case _ => Nil
            }
        })

    /// ranged の projectile の光る尾（頭から進む向きの後ろへ length 伸びる芯と、ゆらめくにじむ外側）。
    // WhyNot: 丸い玉のビルボードだけにしない — 単色の丸は飛ぶ向きが読めず、玩具の玉に見える。
    pub def spitInstancesOf(g: Particles3dDoc.Glow, art: Art, t: Float64, shots: List[Projectiles.Projectile]): List[Scene3d.Instance3d] =
        shots |> List.flatMap(p -> {
            let speed = Vec3.length(p#velocity);
            if (speed < 0.001) Nil
            else {
                let d = Vec3.mul(p#velocity, 1.0 / speed);
                let length = Float64.min(g#length, speed * Float64.max(0.0, t - p#born) + 0.05);
                let start = Vec3.sub(p#at, Vec3.mul(d, length));
                let line = (width: Float64, material: Scene3d.Material3d) ->
                    Scene3d.meshInstance(art#mesh, Mat4.mul(Mat4.translate(start), Mat4.mul(facing(d), Mat4.scale(Vec3.v3(width, width, length)))))
                        |> Scene3d.withMaterial(material) |> Scene3d.withName("spit");
                let wobble = 1.0 + 0.25 * Num.sin(t * g#wobble * Num.tau() + Int32.toFloat64(p#id) * 1.7);
                line(g#width, art#spit#core) :: line(g#width * Float64.max(1.0, g#glowWidth) * wobble, art#spit#glow) :: Nil
            }
        })
}
