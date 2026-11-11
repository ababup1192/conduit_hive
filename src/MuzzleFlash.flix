// MuzzleFlash — 撃った瞬間の銃口の光（純粋）: 白く強い芯の円盤と、放射状に開く細い光の筋の束を、目へ向いた面として銃口に置く。
// 筋の束は形を 3 つ作り置き、muzzleFlicker 秒ごとに替えながら少しずつ回す。芯も筋も自分で光る半透明で、明るさは寿命の終わりへ落ちる（ブルームでにじむ）。
// 値は Particles3dDoc の武器ごとの muzzle（size = 筋の長さ m・grow = 寿命の終わりの大きさの倍率・aspect = 横の倍率・life・color・intensity・count = 筋の本数の目安）。
// WhyNot: ビルボード（粒の絵）で描かない — ビルボードは α が半分未満の画素を捨てる切り抜きで、やわらかく重なる光にならず、平たい星の切り絵に見える。
mod MuzzleFlash {
    use fge::{Camera3d, Color, Hash01, Mat4, Mesh3d, Num, Scene3d, ShaderDoc, Vec3}
    use fge::ShaderDoc.{Field, Shade, Out}
    use WeaponsDoc.Weapon

    /// 作り置きの形: 筋の束 3 つ（長さ 1 の XY 面・+Z が目と反対）と芯の円盤（半径 1）。
    pub type alias Art = { rays = Vector[Mesh3d.Mesh3d], core = Mesh3d.Mesh3d }

    def variants(): Int32 = 3

    /// 芯の半径（筋の長さに対する割合）と、筋の付け根の太さ（筋の長さに対する割合）。
    // WhyNot: Doc へ出さない — 形の比で、大きさと明るさは muzzle の size・intensity で調整する。
    def coreRatio(): Float64 = 0.22
    def rayWidth(): Float64 = 0.05

    def white(): Color = Color.rgb(1.0, 1.0, 1.0)

    /// 形を作る（読み込みで 1 回）。筋は 1 束 16 本・長さは 0.35〜1 で散らす。
    pub def artOf(): Art =
        let tri = (a: Vec3.Vec3, b: Vec3.Vec3, c: Vec3.Vec3) -> { points = a :: b :: c :: Nil, color = white() };
        let bundle = (v: Int32) -> Mesh3d.fromPolygons(List.range(0, 16) |> List.map(k -> {
            let key = v * 53 + k;
            let angle = Int32.toFloat64(k) * Num.tau() / 16.0 + 0.3 * (Hash01.at(key, 71) - 0.5);
            let length = 0.35 + 0.65 * Hash01.at(key, 72);
            let w = rayWidth() * (0.6 + 0.8 * Hash01.at(key, 73));
            let (c, s) = (Num.cos(angle), Num.sin(angle));
            tri(Vec3.v3(0.0 - s * w, c * w, 0.0), Vec3.v3(s * w, 0.0 - c * w, 0.0), Vec3.v3(c * length, s * length, 0.0))
        }));
        let core = Mesh3d.fromPolygons(List.range(0, 12) |> List.map(k -> {
            let a0 = Int32.toFloat64(k) * Num.tau() / 12.0;
            let a1 = Int32.toFloat64(k + 1) * Num.tau() / 12.0;
            tri(Vec3.zero(), Vec3.v3(Num.cos(a0), Num.sin(a0), 0.0), Vec3.v3(Num.cos(a1), Num.sin(a1), 0.0))
        }));
        { rays = List.range(0, variants()) |> List.map(bundle) |> List.toVector, core = core }

    /// 色 c で自分で光る半透明・両面の材質。
    def glowing(name: String, c: Color, intensity: Float64, alpha: Float64): Scene3d.Material3d =
        let spec = { name = name, cycleRate = 0.0, bindings = Nil, out = Out.Fill({ shade = Shade.Solid(c), alpha = Field.Const(Num.clamp01(alpha)) }) };
        Scene3d.material(spec) |> Scene3d.withEmission(Shade.Solid(c)) |> Scene3d.withEmissionIntensity(intensity)
            |> Scene3d.withAlphaBlend(true) |> Scene3d.withDoubleSided(true)

    /// 時刻 t の銃口の光の置いた物（最後に撃ってから muzzle の life の間だけ）。muzzle = 銃口の点（ステージの座標）・camera = 照準のカメラ。
    pub def instancesOf(doc: Particles3dDoc.Doc, art: Art, camera: Camera3d.Camera3d, muzzle: Vec3.Vec3, t: Float64, a: Arsenal.Arsenal): List[Scene3d.Instance3d] =
        a#last |> Option.toList |> List.flatMap(shot -> {
            let b = Particles3d.muzzleOf(doc, shot#weapon);
            let age = t - shot#at;
            if (age < 0.0 or age >= b#life) Nil
            else {
                let k = age / Float64.max(0.0001, b#life);
                let fade = (1.0 - k) * (1.0 - k);
                let length = b#size * (1.0 + (b#grow - 1.0) * k);
                let flicker = Particles3dDoc.rec(doc)#muzzleFlicker;
                let step = if (flicker <= 0.0) 0 else Num.floorInt(age / flicker);
                let variant = Int32.modulo(a#shots + step, variants());
                let spin = Int32.toFloat64(a#shots) * 0.9 + Int32.toFloat64(step) * 0.12;
                let (r, u, f) = (Camera3d.right(camera), Camera3d.up(camera), Camera3d.forward(camera));
                let face = Mat4.ofLinearRows(Vec3.v3(r#x, u#x, f#x), Vec3.v3(r#y, u#y, f#y), Vec3.v3(r#z, u#z, f#z));
                let place = (sx: Float64, sy: Float64) -> Mat4.mul(Mat4.translate(muzzle), Mat4.mul(face, Mat4.mul(Mat4.rotateZ(spin), Mat4.scale(Vec3.v3(sx, sy, 1.0)))));
                let rays = Vector.nth(variant, art#rays) |> Option.toList |> List.map(mesh ->
                    Scene3d.meshInstance(mesh, place(length * b#aspect, length)) |> Scene3d.withName("muzzle-flash")
                        |> Scene3d.withMaterial(glowing("conduit_muzzle_rays", b#color, b#intensity * fade, 0.55)));
                let core = Scene3d.meshInstance(art#core, place(length * coreRatio() * b#aspect, length * coreRatio())) |> Scene3d.withName("muzzle-core")
                    |> Scene3d.withMaterial(glowing("conduit_muzzle_core", white(), b#intensity * 1.6 * fade, 0.9));
                core :: rays
            }
        })
}
