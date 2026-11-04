// PickupModels — 拾う物の形（読み込みのほかは純粋）: 武器は Blender の glb（原点は床の上の真ん中・長い向きは Z・骨なし）、
// 回復と弾倉は鋼の箱の組み合わせに発光の筋（施設の光る筋と同じ冷たい色）。どの物の下にも、光る縁の台座を床に敷く。
// 形は読み込みで 1 回だけ組み、置くたびに world の行列だけを替える（instancesAt）。浮き方と回り方は Pickups。
mod PickupModels {
    use fge::{Color, Gltf, LoadProgress, Log, Mat4, Mesh3d, Model3d, Num, Scene3d, ShaderDoc, Texture3d, Vec3}
    use fge::ShaderDoc.{Field, Shade, Out}
    use WeaponsDoc.Weapon
    use Pickups.Kind

    /// 武器の拾う物の glb（読めなかった武器は無い）。
    pub type alias Models = Map[Weapon, Model3d.Model3d]

    /// 形 1 つ（原点のまわりの形と、光る物なら材質）。
    type alias Shape = { mesh = Mesh3d.Mesh3d, material = Option[Scene3d.Material3d], name = String }

    /// 拾う物の形の束: 種類ごとの浮く形・床に敷く台座・武器の glb・glb の絵。
    pub type alias Art = { bodies = Map[Kind, List[Shape]], pad = List[Shape], models = Models, textures = List[Texture3d.Texture3d] }

    /// 武器 w の拾う物の glb のパス。
    def pathOf(w: Weapon): String = "assets/models/pickup_${WeaponsDoc.keyOf(w)}.glb"

    /// 拾える武器（拳銃は始めから持つので拾う物の形が無い）。
    def weapons(): List[Weapon] = Weapon.Shotgun :: Weapon.Rifle :: Nil

    /// 武器の glb を絵つきで読む。読めない武器は理由を 1 行出して置かない（その武器の拾う物は台座だけになる）。
    pub def load(): Models \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        weapons()
            |> LoadProgress.mapWithProgress("reading pickups...", w -> (w, Fs.FileRead.readBytes(pathOf(w)) |> Result.mapErr(e -> "${pathOf(w)}: 読めない（${e}）")))
            |> LoadProgress.parMapWithProgress("decoding pickups...", raw -> {
                let (w, bytes) = raw;
                bytes |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, Gltf.noTextureLimits(), b) |> Result.mapErr(why -> "${pathOf(w)}: ${why}"))
                      |> Result.map(model -> (w, model))
            })
            |> List.filterMap(r -> match r {
                case Ok(pair) => Some(pair)
                case Err(why) => Log.warnThen("[pickup] ${why}", None)
            })
            |> List.toMap

    // ── 形を組む ──

    def box(cx: Float64, cy: Float64, cz: Float64, sx: Float64, sy: Float64, sz: Float64): BoxMesh.Box =
        { center = Vec3.v3(cx, cy, cz), size = Vec3.v3(sx, sy, sz) }

    def solid(name: String, c: Color, boxes: List[BoxMesh.Box]): Shape = { mesh = BoxMesh.of(c, boxes), material = None, name = name }

    def glowing(look: LookDoc.Rec, glow: Float64, name: String, boxes: List[BoxMesh.Box]): Shape =
        { mesh = BoxMesh.of(look#stripColor, boxes), material = Some(MazeMesh.glowMaterial("conduit_${name}", look#stripColor, glow)), name = name }

    /// 回復: 明るい鋼のケース（胴・一回り小さい蓋・取っ手）と、両の長い面の光る十字。k = 大きさの倍率。
    def medkit(look: LookDoc.Rec, glow: Float64, k: Float64): List[Shape] =
        let (w, h, d) = (0.44 * k, 0.26 * k, 0.30 * k);
        let pale = Color.lighten(look#wallColor, 0.32);
        let cross = (zFace: Float64) ->
            box(0.0, h * 0.5, zFace, 0.05 * k, 0.17 * k, 0.012) :: box(0.0, h * 0.5, zFace, 0.17 * k, 0.05 * k, 0.012) :: Nil;
        solid("pickup:case", pale, box(0.0, h * 0.5, 0.0, w, h, d) :: Nil)
            :: solid("pickup:lid", Color.lighten(pale, 0.12), box(0.0, h + 0.02 * k, 0.0, w * 0.9, 0.04 * k, d * 0.88) :: box(0.0, h + 0.06 * k, 0.0, w * 0.36, 0.035 * k, 0.045 * k) :: Nil)
            :: glowing(look, glow, "pickup:cross", List.append(cross(d * 0.5 + 0.006), cross(0.0 - d * 0.5 - 0.006)))
            :: Nil

    /// 散弾銃の弾倉: 暗い鋼の箱に光る帯、上に薬莢を 5 本並べる（明るい鋼の胴と暗い頭）。
    def shells(look: LookDoc.Rec, glow: Float64): List[Shape] =
        let dark = Color.darken(look#wallColor, 0.25);
        let xs = List.range(0, 5) |> List.map(i -> (Int32.toFloat64(i) - 2.0) * 0.072);
        solid("pickup:crate", dark, box(0.0, 0.1, 0.0, 0.42, 0.2, 0.28) :: Nil)
            :: solid("pickup:shell", Color.lighten(look#wallColor, 0.25), xs |> List.map(x -> box(x, 0.26, 0.0, 0.05, 0.12, 0.05)))
            :: solid("pickup:shell-cap", Color.darken(look#wallColor, 0.45), xs |> List.map(x -> box(x, 0.215, 0.0, 0.056, 0.03, 0.056)))
            :: glowing(look, glow, "pickup:crate-band", box(0.0, 0.12, 0.146, 0.38, 0.03, 0.012) :: box(0.0, 0.12, -0.146, 0.38, 0.03, 0.012) :: Nil)
            :: Nil

    /// 連射銃の弾倉: 暗い鋼の箱に、弾倉を 2 本立て、弾倉の横に光る筋。
    def magazines(look: LookDoc.Rec, glow: Float64): List[Shape] =
        let dark = Color.darken(look#wallColor, 0.25);
        solid("pickup:crate", dark, box(0.0, 0.08, 0.0, 0.42, 0.16, 0.28) :: Nil)
            :: solid("pickup:magazine", Color.lighten(look#wallColor, 0.1), box(-0.09, 0.27, 0.0, 0.08, 0.22, 0.15) :: box(0.09, 0.27, 0.0, 0.08, 0.22, 0.15) :: Nil)
            :: glowing(look, glow, "pickup:magazine-band", box(-0.09, 0.3, 0.081, 0.06, 0.12, 0.012) :: box(0.09, 0.3, 0.081, 0.06, 0.12, 0.012) :: box(0.0, 0.1, -0.146, 0.38, 0.03, 0.012) :: Nil)
            :: Nil

    /// 半透明で自分で光る材質（頂点の色に光る色を足し、alpha の濃さで重ねる）。
    def beamMaterial(name: String, c: Color, intensity: Float64, alpha: Float64): Scene3d.Material3d =
        let vc = chan -> Field.VertexColor({ chan = chan });
        let spec = { name = name, cycleRate = 0.0, bindings = Nil,
                     out = Out.Fill({ shade = Shade.Rgb({ r = vc(ShaderDoc.TexChan.R), g = vc(ShaderDoc.TexChan.G), b = vc(ShaderDoc.TexChan.B) }), alpha = Field.Const(alpha) }) };
        Scene3d.material(spec) |> Scene3d.withEmission(Shade.Solid(c)) |> Scene3d.withEmissionIntensity(intensity) |> Scene3d.withAlphaBlend(true)

    /// 台座から上へ立つ淡い光の柱: 下ほど濃く上へ消える 4 段の半透明の箱（暗がりで拾う物の後ろに明るい地を作り、形を背景から分ける）。
    def beamOf(look: LookDoc.Rec, glow: Float64): List[Shape] =
        let (side, step) = (0.62, 0.45);
        (0.22 :: 0.13 :: 0.07 :: 0.03 :: Nil) |> List.zipWithIndex |> List.map(e -> {
            let (i, alpha) = e;
            let y = 0.04 + step * (Int32.toFloat64(i) + 0.5);
            { mesh = BoxMesh.of(look#stripColor, box(0.0, y, 0.0, side, step, side) :: Nil),
              material = Some(beamMaterial("conduit_pickup_beam${i}", look#stripColor, glow * 0.35, alpha)), name = "pickup:beam" }
        })

    /// 床に敷く台座: 低い黒鉛の板と、その縁の光る四角の枠と、上へ立つ光の柱。
    def padOf(look: LookDoc.Rec, glow: Float64): List[Shape] =
        let (half, rim, y) = (0.55, 0.035, 0.036);
        solid("pickup:pad", Color.darken(look#floorColor, 0.2), box(0.0, 0.015, 0.0, half * 2.0, 0.03, half * 2.0) :: Nil)
            :: glowing(look, glow * 0.6, "pickup:pad-rim",
                   box(0.0, y, half - 0.06, half * 2.0 - 0.12, 0.012, rim) :: box(0.0, y, 0.06 - half, half * 2.0 - 0.12, 0.012, rim)
                       :: box(half - 0.06, y, 0.0, rim, 0.012, half * 2.0 - 0.12) :: box(0.06 - half, y, 0.0, rim, 0.012, half * 2.0 - 0.12) :: Nil)
            :: beamOf(look, glow)

    /// 形の束を組む（読み込みと見た目の Doc を読み直した時だけ）。
    pub def build(look: LookDoc.Rec, doc: PickupsDoc.Doc, models: Models): Art =
        let glow = PickupsDoc.rec(doc)#glow;
        { bodies = Map#{ Kind.HealthSmall => medkit(look, glow, 1.0), Kind.HealthLarge => medkit(look, glow, 1.35),
                         Kind.AmmoShotgun => shells(look, glow), Kind.AmmoRifle => magazines(look, glow) },
          pad = padOf(look, glow), models = models |> Map.map(glowingModel(look, glow)), textures = models |> Map.valuesOf |> List.flatMap(m -> m#textures) }

    /// 武器の glb の、自分で光らない材質に施設の光る筋の色をうっすら足す（暗がりで黒い影にならない）。光る筋の材質はそのまま。
    def glowingModel(look: LookDoc.Rec, glow: Float64, m: Model3d.Model3d): Model3d.Model3d =
        let tint = (mat: Scene3d.Material3d) ->
            if (Option.nonEmpty(Scene3d.materialFieldsOf(mat)#emission)) mat
            else mat |> Scene3d.withEmission(Shade.Solid(Color.mix(look#wallColor, look#stripColor, 0.5))) |> Scene3d.withEmissionIntensity(glow * 0.12);
        { parts = m#parts |> List.map(p -> { material = p#material |> Option.map(tint) | p }) | m }

    // ── 置く ──

    def place(world: Mat4.Mat4, s: Shape): Scene3d.Instance3d =
        let i = Scene3d.meshInstance(s#mesh, world) |> Scene3d.withName(s#name);
        s#material |> Option.map(m -> Scene3d.withMaterial(m, i)) |> Option.getWithDefault(i)

    /// 置き方: 床の点 x・z・物の高さ y・向き yaw（ラジアン）・物の大きさの倍率（台座は替えない）。
    pub type alias Placement = { x = Float64, z = Float64, y = Float64, yaw = Float64, scale = Float64 }

    /// 種類 kind の拾う物を置いた物: 台座は床に・物は高さ y で yaw だけ回し、scale 倍にして。
    /// 武器の glb は床に寝かせた向き（横の形が上を向く）で作ってあるので、Z のまわりに 90 度起こして横の形を横から見せる。
    pub def instancesAt(art: Art, kind: Kind, at: Placement): List[Scene3d.Instance3d] =
        let floor = Mat4.translate(Vec3.v3(at#x, 0.0, at#z));
        let k = Float64.max(0.05, at#scale);
        let body = Mat4.mul(Mat4.translate(Vec3.v3(at#x, at#y, at#z)), Mat4.mul(Mat4.rotateY(at#yaw), Mat4.scale(Vec3.v3(k, k, k))));
        let pad = art#pad |> List.map(place(floor));
        let shaped = Map.getWithDefault(kind, Nil, art#bodies) |> List.map(place(body));
        let upright = Mat4.mul(body, Mat4.rotateZ(Num.pi() * 0.5));
        let modeled = weaponOf(kind) |> Option.flatMap(w -> Map.get(w, art#models)) |> Option.map(Model3d.partInstances(upright)) |> Option.getWithDefault(Nil);
        List.flatten(pad :: shaped :: modeled :: Nil)

    /// glb で描く種類の武器（ほかは None）。
    def weaponOf(kind: Kind): Option[Weapon] = match Pickups.gainOf(kind) {
        case Pickups.Gain.Arm(w) => Some(w)
        case _                   => None
    }
}
