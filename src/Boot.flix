// Boot — 蹴りの間だけ画面の下から前へ出る脚（腿と、脛から下の装甲ブーツ）の形と置き方（読み込みのほかは純粋）。
// 形は assets/models/boot.glb（modeling/boot.py。骨なし・ノードは leg_thigh と leg_shin・どちらも原点が関節で脚は -Y へ下り・つま先は +Z）。
// 腕と銃と同じ手前の場面（目の座標: 右が +X・上が +Y・前が +Z）に入れる。脚が出るのは Moves.kickProgress の間（MovesDoc の kick の seconds）。
mod Boot {
    use fge::{Gltf, LoadProgress, Log, Mat4, Model3d, Num, Scene3d, Texture3d, Vec3}

    /// 脚の形: 腿の部品・脛から下の部品・glb の絵（読めなければ部品が無く、脚は出ない）。
    pub type alias Art = { thigh = List[Model3d.ModelPart], shin = List[Model3d.ModelPart], textures = List[Texture3d.Texture3d] }

    def path(): String = "assets/models/boot.glb"

    /// 腿の長さ（m。glb の leg_thigh の原点から膝まで。modeling/boot.py の THIGH と同じ）。
    def thighLength(): Float64 = 0.44

    /// glb を絵つきで読む（読めなければ理由を 1 行出して None。蹴りは効くが脚は見えない）。
    pub def load(): Option[Model3d.Model3d] \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        LoadProgress.report("reading boot...", 0, 0);
        match Fs.FileRead.readBytes(path()) |> Result.mapErr(e -> "読めない（${e}）")
                |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, Gltf.noTextureLimits(), b)) {
            case Ok(m)    => Some(m)
            case Err(why) => Log.warnThen("[boot] ${path()}: ${why}", None)
        }

    /// 光る筋の emissive の倍率。
    // WhyNot: glb の強さ（銃と同じ 4）のままにしない — 脚の筋は目の 0.5 m 前に太く写り、ブルームで白く飛んで施設の青い光に見えない。
    def glow(): Float64 = 1.5

    /// glb から腿と脛の部品を分けて持つ（読み込みで 1 回）。
    pub def build(model: Option[Model3d.Model3d]): Art =
        let dimmed = (part: Model3d.ModelPart) -> { material = part#material |> Option.map(Scene3d.withEmissionIntensity(glow())) | part };
        let partsOf = (name: String) -> model |> Option.flatMap(m -> Model3d.findNode(name, m) |> Option.map(n -> Model3d.partsOfNode(n, m) |> List.map(dimmed))) |> Option.getWithDefault(Nil);
        { thigh = partsOf("leg_thigh"), shin = partsOf("leg_shin"), textures = model |> Option.toList |> List.flatMap(m -> m#textures) }

    /// 蹴りの姿勢: swing = 腿を前へ振り上げた角（ラジアン。0 で真下）・bend = 膝の曲げ（ラジアン。0 で伸び切る）・push = 腰が前へ出る量（m）。
    type alias Pose = { swing = Float64, bend = Float64, push = Float64 }

    /// 姿勢の節（蹴りの進み k と姿勢）: 膝を抱え上げ → 足裏で前へ突き出し → 少し留め → 膝を曲げて下ろす。
    // WhyNot: Doc へ出さない — 脚の動きの形で、数を 1 つ動かすと他の節とつながらなくなる。長さは MovesDoc の kick の seconds で伸び縮みする。
    def keys(): List[(Float64, Pose)] =
        (0.0,  { swing = 0.6,  bend = 1.2,  push = 0.0 })
            :: (0.11, { swing = 2.1,  bend = 2.3,  push = 0.0 })
            :: (0.27, { swing = 1.8,  bend = 0.1,  push = 0.12 })
            :: (0.42, { swing = 1.75, bend = 0.06, push = 0.1 })
            :: (0.62, { swing = 2.0,  bend = 1.9,  push = 0.02 })
            :: (1.0,  { swing = 0.5,  bend = 1.4,  push = -0.05 })
            :: Nil

    def ease(u: Float64): Float64 = u * u * (3.0 - 2.0 * u)

    def mixPose(a: Pose, b: Pose, u: Float64): Pose =
        let m = (x: Float64, y: Float64) -> x + (y - x) * u;
        { swing = m(a#swing, b#swing), bend = m(a#bend, b#bend), push = m(a#push, b#push) }

    def rest(): Pose = { swing = 0.0, bend = 0.0, push = 0.0 }

    /// 進み k の姿勢（隣り合う節の間をなめらかにつなぐ・最後の節より後は最後の姿勢）。
    def poseAt(k: Float64): Pose =
        let ks = keys();
        let last = List.last(ks) |> Option.map(snd) |> Option.getWithDefault(rest());
        List.zip(ks, List.drop(1, ks)) |> List.find(p -> k <= fst(snd(p))) |> Option.map(p -> {
            let ((k0, a), (k1, b)) = p;
            mixPose(a, b, ease(Num.clamp01((k - k0) / Float64.max(0.0001, k1 - k0))))
        }) |> Option.getWithDefault(last)

    /// 股関節の置き場（目の座標）: 左の脚を目より下・少し後ろに置き、内へ向ける。
    // WhyNot: 本当の腰の高さ（目の 0.7 m 下）に置かない — 縦の画角 55 度では伸ばした足が画面の下の外に残り、蹴ったのが見えない。
    def hip(push: Float64): Mat4.Mat4 = Mat4.mul(Mat4.translate(Vec3.v3(-0.42, -0.44, 0.0 + push)), Mat4.rotateY(0.15))

    def placed(world: Mat4.Mat4, parts: List[Model3d.ModelPart]): List[Scene3d.Instance3d] =
        parts |> List.map(part -> {
            let i = Scene3d.meshInstance(part#mesh, world) |> Scene3d.withName("boot");
            part#material |> Option.map(m -> Scene3d.withMaterial(m, i)) |> Option.getWithDefault(i)
        })

    /// 蹴りの進み k（0..1）の脚の置いた物: 腿を前へ振り上げ、膝から先を伸ばして靴底で前を突き、膝を曲げて画面の下へ引く。
    /// eyeToWorld = 目の座標から置く先の座標への行列（目の座標のままなら単位行列）。
    pub def instancesAt(eyeToWorld: Mat4.Mat4, art: Art, k: Float64): List[Scene3d.Instance3d] =
        let p = poseAt(Num.clamp01(k));
        let thigh = Mat4.mul(eyeToWorld, Mat4.mul(hip(p#push), Mat4.rotateX(0.0 - p#swing)));
        let shin = Mat4.mul(thigh, Mat4.mul(Mat4.translate(Vec3.v3(0.0, 0.0 - thighLength(), 0.0)), Mat4.rotateX(p#bend)));
        List.append(placed(thigh, art#thigh), placed(shin, art#shin))
}
