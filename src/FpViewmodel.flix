// FpViewmodel — 画面の手前に重ねる腕と銃（ビューモデル。Blender で作った骨つきの glb）の読み込みと、今の姿勢・置き方・銃口（読み込みのほかは純粋）。
// 描くのは StageView（値を受けて場面を組むだけ）。
//
// glb の座標はビューモデルの場面のカメラ（原点・yaw 0・pitch 0）に合わせて作ってある（+Z が前・+X が右・-Y が下・m）。
// 置き方は単位行列に、歩く揺れ（bob）と見回しの遅れ（sway）だけを掛ける。
// クリップは idle（ループ）・draw（持ち替え。drawSeconds に伸び縮み）・fire（撃った瞬間から 1 回）・reload（長物だけ・まだ使わない）。
// 銃口は MUZZLE の点（gun のジョイントの子）: 今の姿勢の gun のジョイントの行列 × MUZZLE の局所の行列。原点が銃口・局所の +Z が銃身の向き。
mod FpViewmodel {
    use fge::{AnimationClip3d, Gltf, ImageData, LoadProgress, Log, Mat4, Model3d, Num, Pose3d, Scene3d, Skin3d, Vec3}
    use WeaponsDoc.Weapon

    /// 武器 1 つの腕と銃。gunJoint = 銃のジョイントの番号・muzzleLocal = gun から見た MUZZLE の点の行列。
    pub type alias Viewmodel = { model = Model3d.Model3d, skin = Skin3d.Skin3d, gunJoint = Int32, muzzleLocal = Mat4.Mat4 }

    /// 武器ごとの腕と銃（読めなかった武器は無い）。
    pub type alias Viewmodels = Map[Weapon, Viewmodel]

    /// 武器 w の glb のパス。
    pub def pathOf(w: Weapon): String = "assets/models/viewmodel_${WeaponsDoc.keyOf(w)}.glb"

    /// 全部の武器の glb を絵つきで読む。読めない武器は理由を 1 行出して置かない（その武器を構えても腕は描かない）。
    pub def load(): Viewmodels \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        WeaponsDoc.all()
            |> LoadProgress.mapWithProgress("reading viewmodels...", w -> (w, Fs.FileRead.readBytes(pathOf(w)) |> Result.mapErr(e -> "${pathOf(w)}: 読めない（${e}）")))
            |> LoadProgress.parMapWithProgress("decoding viewmodels...", raw -> decode(dec, raw))
            |> List.filterMap(r -> match r {
                case Ok(pair) => Some(pair)
                case Err(why) => Log.warnThen("[arms] ${why}", None)
            })
            |> List.toMap

    def decode(dec: ImageData.ImageDecoder, raw: (Weapon, Result[String, Vector[Int8]])): Result[String, (Weapon, Viewmodel)] \ IO =
        let (w, bytes) = raw;
        bytes
            |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, Gltf.noTextureLimits(), b) |> Result.mapErr(why -> "${pathOf(w)}: ${why}"))
            |> Result.flatMap(viewmodelOf(pathOf(w)))
            |> Result.map(rig -> (w, rig))

    /// 読んだ glb から腕と銃を組む（骨・gun のジョイント・MUZZLE の点が無ければ Err）。
    pub def viewmodelOf(path: String, model: Model3d.Model3d): Result[String, Viewmodel] =
        forM (
            skin <- model#skin |> Option.toOk("${path}: 骨が無い");
            gun <- Skin3d.jointIndex(skin, "gun") |> Option.toOk("${path}: gun のジョイントが無い");
            muzzle <- Model3d.findNode("MUZZLE", model) |> Option.toOk("${path}: MUZZLE の点が無い")
        ) yield { model = model, skin = skin, gunJoint = gun, muzzleLocal = muzzle#local }

    /// 部品の材質に、glb の材質の名前の面の金属っぽさと粗さ（Doc）を付ける。Doc に無い面と pbr が偽の時は拡散の光だけの材質に戻す（何度掛けても同じ）。
    // WhyNot: glb の metallicFactor を Gltf.loadTexturedPbrUsing で読まない — 値を Doc で保存即反映に調整したい。glb の値は Blender で見る時のためだけ。
    pub def withSurfaces(vm: FpViewmodelDoc.Rec, rigs: Viewmodels): Viewmodels =
        rigs |> Map.map(rig -> { model = { parts = rig#model#parts |> List.map(surfacedPart(vm)) | rig#model } | rig })

    def surfacedPart(vm: FpViewmodelDoc.Rec, part: Model3d.ModelPart): Model3d.ModelPart =
        let surface = part#gltfMaterial |> Option.flatMap(g -> FpViewmodelDoc.surfaceOf(vm, g#name));
        { material = part#material |> Option.map(m -> surfaced(surface, m)) | part }

    def surfaced(surface: Option[LookDoc.Surface], m: Scene3d.Material3d): Scene3d.Material3d = match surface {
        case Some(s) => Scene3d.withMetallicRoughness(s#metallic, s#roughness, m)
        case None    => Scene3d.withoutMetallicRoughness(m)
    }

    // ── 今のクリップ ──

    /// 今流すクリップ: 名前・始まりからの秒・伸び縮みさせる長さ（None ならクリップのまま）・ループするか。
    pub type alias Playing = { clip = String, elapsed = Float64, stretchTo = Option[Float64], looping = Bool }

    /// 時刻 t に流すクリップ: 持ち替えの最中は draw・構えている武器で撃ってから fire の長さの間は fire・ほかは idle。
    /// fireLength = 構えている武器の fire のクリップの長さ（秒）。
    pub def playingAt(vm: FpViewmodelDoc.Rec, fireLength: Float64, t: Float64, a: Arsenal.Arsenal): Playing =
        let firing = a#last |> Option.filter(s -> s#weapon == a#current and t - s#at < fireLength);
        match (a#hands, firing) {
            case (Arsenal.Hands.Drawing(s), _) if Arsenal.isDrawing(vm, t, a) =>
                { clip = "draw", elapsed = t - s, stretchTo = Some(vm#drawSeconds), looping = false }
            case (_, Some(shot)) => { clip = "fire", elapsed = t - shot#at, stretchTo = None, looping = false }
            case _               => { clip = "idle", elapsed = t, stretchTo = None, looping = true }
        }

    /// クリップ name の長さ（秒。無ければ 0）。
    pub def clipLength(rig: Viewmodel, name: String): Float64 =
        Map.get(name, rig#model#clips) |> Option.map(AnimationClip3d.duration) |> Option.getWithDefault(0.0)

    /// 流しているクリップの今の姿勢（クリップが無ければ休みの姿勢）。
    pub def poseOf(rig: Viewmodel, p: Playing): Pose3d.Pose3d =
        let local = Map.get(p#clip, rig#model#clips) |> Option.map(clip -> {
            let length = AnimationClip3d.duration(clip);
            let at = p#stretchTo |> Option.map(target -> p#elapsed * length / Float64.max(0.001, target)) |> Option.getWithDefault(p#elapsed);
            AnimationClip3d.sample(rig#skin, clip, at, p#looping)
        }) |> Option.getWithDefault(Skin3d.restPose(rig#skin));
        Pose3d.compute(rig#skin, local)

    // ── 置き方と銃口 ──

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    /// 揺れの今の値: 歩いた距離の 1 歩の位相（Walker.stridePhase）と、見回しの遅れ（度。x = 横・y = 縦）。
    pub type alias Motion = { phase = Float64, sway = { x = Float64, y = Float64 } }

    /// 腕と銃を置く行列（ビューモデルの場面の座標）: 歩く揺れで動かし、見回しの遅れの分だけ反対へ回す。
    pub def placeOf(vm: FpViewmodelDoc.Rec, m: Motion): Mat4.Mat4 =
        let s = Num.sin(m#phase);
        let bob = Vec3.v3(vm#bobSide * s, 0.0 - vm#bobLift * Float64.abs(s), 0.0);
        Mat4.mul(Mat4.translate(bob),
                 Mat4.mul(Mat4.rotateY(rad(0.0 - m#sway#x * vm#swayScale)), Mat4.rotateX(rad(0.0 - m#sway#y * vm#swayScale))))

    /// 今の銃口の行列（銃口の局所 → ビューモデルの場面の座標。原点が銃口・+Z が銃身の向き）。
    pub def muzzleFrame(rig: Viewmodel, pose: Pose3d.Pose3d, place: Mat4.Mat4): Mat4.Mat4 =
        Mat4.mul(place, Mat4.mul(Pose3d.jointTransform(pose, rig#gunJoint), rig#muzzleLocal))

    /// 今の銃口の点（ビューモデルの場面の座標）。
    pub def muzzleAt(rig: Viewmodel, pose: Pose3d.Pose3d, place: Mat4.Mat4): Vec3.Vec3 =
        Mat4.apply(muzzleFrame(rig, pose, place), Vec3.zero())

    /// 腕と銃の置いた物（部品ごと・今の姿勢で曲げる）。
    pub def instancesOf(rig: Viewmodel, pose: Pose3d.Pose3d, place: Mat4.Mat4): List[Scene3d.Instance3d] =
        Model3d.partInstances(place, rig#model) |> List.map(Scene3d.withPose(pose))
}
