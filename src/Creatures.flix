// Creatures — 敵の体（Blender で作った骨つきの glb）の読み込みと、クリップの長さ・当たり判定の形・今の姿勢（読み込みのほかは純粋）。
// 何をしているか（追う・振る・倒れる）は Horde が決め、ここはその時刻の形を作るだけ。
//
// glb の座標: 前が +Z・原点が足元の真ん中・m。どのクリップも場所の上で動く（移動は Horde が付ける）。
// クリップは idle・walk（ループ）・attack・hit・die（1 回。最後のコマで止まる）。
//
// ── 姿勢の共有 ──
// 骨つきの姿勢を 1 体ずつ作ると 1 体あたり約 45 µs かかる（plans/bench-horde.md）。同じ型・同じクリップの敵は時刻を丸めて 1 つの姿勢を共有する:
//   ループのクリップ … 敵ごとの組（0..7）でクリップの長さの 1/8 ずつずらした時刻（同じ組は同じ姿勢）
//   1 回のクリップ  … 始めてからの秒を 1/30 秒に丸める（同じ頃に始めた敵は同じ姿勢）
// クリップを切り替えた直後の blendSeconds の間だけは、前のクリップと今のクリップを混ぜた姿勢を 1 体ずつ作る（Pose3d.blend）。
mod Creatures {
    use fge::{AnimationClip3d, Gltf, ImageData, LoadProgress, Log, Mat4, Model3d, Num, Pose3d, Scene3d, Skin3d, Vec3}

    /// 敵の型。
    pub enum Kind with Eq, Order, ToString {
        case Melee
        case Ranged
    }

    /// クリップ。
    pub enum Clip with Eq, Order, ToString {
        case Idle
        case Walk
        case Attack
        case Hit
        case Die
    }

    /// 全部の型（読み込みの並び）。
    def all(): List[Kind] = Kind.Melee :: Kind.Ranged :: Nil

    def clips(): List[Clip] = Clip.Idle :: Clip.Walk :: Clip.Attack :: Clip.Hit :: Clip.Die :: Nil

    /// 型の名前（glb のファイル名・Doc の欄の名前）。
    def keyOf(k: Kind): String = match k {
        case Kind.Melee  => "melee"
        case Kind.Ranged => "ranged"
    }

    /// glb の中のクリップの名前。
    def clipName(c: Clip): String = match c {
        case Clip.Idle   => "idle"
        case Clip.Walk   => "walk"
        case Clip.Attack => "attack"
        case Clip.Hit    => "hit"
        case Clip.Die    => "die"
    }

    /// ループするクリップか。
    def isLooping(c: Clip): Bool = c == Clip.Idle or c == Clip.Walk

    /// 型 1 つの体。
    pub type alias Body = { model = Model3d.Model3d, skin = Skin3d.Skin3d, clips = Map[Clip, AnimationClip3d.AnimationClip3d] }

    /// 型ごとの体（読めなかった型は無い。その型の敵は描かないが、動きと当たり判定は残る）。
    pub type alias Bodies = Map[Kind, Body]

    def pathOf(k: Kind): String = "assets/models/creature_${keyOf(k)}.glb"

    /// 全部の型の glb を絵つきで読む。読めない型は理由を 1 行出して置かない。
    pub def load(): Bodies \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        all()
            |> LoadProgress.mapWithProgress("reading creatures...", k -> (k, Fs.FileRead.readBytes(pathOf(k)) |> Result.mapErr(e -> "${pathOf(k)}: 読めない（${e}）")))
            |> LoadProgress.parMapWithProgress("decoding creatures...", raw -> decode(dec, raw))
            |> List.filterMap(r -> match r {
                case Ok(pair) => Some(pair)
                case Err(why) => Log.warnThen("[creatures] ${why}", None)
            })
            |> List.toMap

    def decode(dec: ImageData.ImageDecoder, raw: (Kind, Result[String, Vector[Int8]])): Result[String, (Kind, Body)] \ IO =
        let (k, bytes) = raw;
        bytes
            |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, Gltf.noTextureLimits(), b) |> Result.mapErr(why -> "${pathOf(k)}: ${why}"))
            |> Result.flatMap(rigOf(pathOf(k)))
            |> Result.map(rig -> (k, rig))

    /// 読んだ glb から体を組む（骨か 5 つのクリップのどれかが無ければ Err）。
    def rigOf(path: String, model: Model3d.Model3d): Result[String, Body] =
        let found = clips() |> List.map(c -> (c, Map.get(clipName(c), model#clips)));
        let missing = found |> List.filter(e -> Option.isEmpty(snd(e))) |> List.map(e -> clipName(fst(e)));
        forM (
            skin <- model#skin |> Option.toOk("${path}: 骨が無い");
            _ <- if (List.isEmpty(missing)) Ok(()) else Err("${path}: クリップ ${List.join(", ", missing)} が無い")
        ) yield { model = model, skin = skin, clips = found |> List.filterMap(e -> snd(e) |> Option.map(clip -> (fst(e), clip))) |> List.toMap }

    // ── クリップの長さ ──

    /// glb が読めない時のクリップの長さ（秒。Blender で作った長さと同じ）。
    def fallbackSeconds(k: Kind, c: Clip): Float64 = match (k, c) {
        case (_, Clip.Idle)           => 2.0
        case (Kind.Melee, Clip.Walk)  => 0.6
        case (Kind.Ranged, Clip.Walk) => 1.0
        case (Kind.Melee, Clip.Attack)  => 0.9
        case (Kind.Ranged, Clip.Attack) => 1.0
        case (_, Clip.Hit)            => 0.25
        case (Kind.Melee, Clip.Die)   => 1.2
        case (Kind.Ranged, Clip.Die)  => 1.4
    }

    /// 型ごと・クリップごとの長さ（秒）。読めた体はクリップの長さ・読めなかった型は fallbackSeconds。
    pub type alias Timing = Map[(Kind, Clip), Float64]

    pub def timingOf(rigs: Bodies): Timing =
        all() |> List.flatMap(k -> clips() |> List.map(c -> {
            let fromRig = Map.get(k, rigs) |> Option.flatMap(r -> Map.get(c, r#clips)) |> Option.map(AnimationClip3d.duration);
            ((k, c), fromRig |> Option.getWithDefault(fallbackSeconds(k, c)))
        })) |> List.toMap

    /// クリップの長さ（秒）。
    pub def secondsOf(timing: Timing, k: Kind, c: Clip): Float64 =
        Map.get((k, c), timing) |> Option.getWithDefault(fallbackSeconds(k, c))

    // ── 当たり判定の形（idle の構えの体に合わせた、原点からの相対の値） ──

    /// 体のカプセルと頭の球。feet = カプセルの下の端・mouth = projectile を吐く点（ranged だけ意味がある）。
    /// WhyNot: 体を斜めのカプセルにしない — engine の Ray3d.hitCapsule は縦のカプセルだけを見る。傾き（高さ 1.25 m で 0.25 m）は真ん中の z に寄せる。
    pub type alias Hitbox = { feet = Vec3.Vec3, height = Float64, radius = Float64, head = Vec3.Vec3, headRadius = Float64, mouth = Vec3.Vec3 }

    pub def hitboxOf(k: Kind): Hitbox = match k {
        case Kind.Melee  => { feet = Vec3.v3(0.0, 0.10, 0.125), height = 1.75, radius = 0.25,
                              head = Vec3.v3(0.0, 1.88, 0.52), headRadius = 0.11, mouth = Vec3.v3(0.0, 1.6, 0.5) }
        case Kind.Ranged => { feet = Vec3.v3(0.0, 0.10, 0.025), height = 1.6, radius = 0.30,
                              head = Vec3.v3(0.0, 1.62, 0.25), headRadius = 0.13, mouth = Vec3.v3(0.0, 1.29, 0.53) }
    }

    /// 押し合いの半径（足元の円。体のカプセルより少し広く取り、腕を振る間合いを残す）。
    pub def footprintOf(k: Kind): Float64 = match k {
        case Kind.Melee  => 0.4
        case Kind.Ranged => 0.45
    }

    /// 足元 (x, z)・向き yaw（ラジアン。0 が +Z）に立てた体の world の行列。
    pub def worldOf(x: Float64, z: Float64, yaw: Float64): Mat4.Mat4 = Mat4.mul(Mat4.translate(Vec3.v3(x, 0.0, z)), Mat4.rotateY(yaw))

    // ── 流しているクリップ ──

    /// クリップ 1 本: どのクリップを、いつ始めたか（ループのクリップは始めた時刻を見ない）。
    pub type alias Track = { clip = Clip, start = Float64 }

    /// 今のクリップと、混ぜている途中の前のクリップ（switchedAt = 切り替えた時刻）。
    pub type alias Anim = { now = Track, before = Option[Track], switchedAt = Float64 }

    /// 湧いた時の walk（湧いてすぐ歩き出すので idle から混ぜない）。
    pub def walkAnim(): Anim = { now = { clip = Clip.Walk, start = 0.0 }, before = None, switchedAt = -1000.0 }

    /// 時刻 t に track へ替える（同じ track なら何もしない）。
    pub def play(track: Track, t: Float64, a: Anim): Anim =
        if (track#clip == a#now#clip and track#start == a#now#start) a else { now = track, before = Some(a#now), switchedAt = t }

    // ── 姿勢 ──

    /// 姿勢を共有する鍵。Loop = 型・クリップ・ずらしの組・Once = 型・クリップ・1/30 秒に丸めた始めてからのコマ。
    enum PoseKey with Eq, Order {
        case Loop(Kind, Clip, Int32)
        case Once(Kind, Clip, Int32)
    }

    /// 時刻を共有する組の数。
    def groups(): Int32 = 8

    def framesPerSecond(): Float64 = 30.0

    /// 1 回のクリップは始めてからの秒をクリップの長さで頭打ちにする（最後のコマで止まった死体どうしが同じ鍵になる）。
    def poseKeyOf(timing: Timing, k: Kind, group: Int32, t: Float64, track: Track): PoseKey =
        if (isLooping(track#clip)) PoseKey.Loop(k, track#clip, Int32.modulo(group, groups()))
        else {
            let elapsed = Num.clamp(0.0, secondsOf(timing, k, track#clip), t - track#start);
            PoseKey.Once(k, track#clip, Num.floorInt(elapsed * framesPerSecond()))
        }

    /// 時刻 t に 2 体が同じ姿勢を共有するか（混ぜている途中の体は共有しない）。
    pub def sharesPose(timing: Timing, blendSeconds: Float64, t: Float64, a: Posed, b: Posed): Bool =
        Option.isEmpty(blendOf(blendSeconds, t, a#anim)) and Option.isEmpty(blendOf(blendSeconds, t, b#anim)) and
            poseKeyOf(timing, a#kind, a#group, t, a#anim#now) == poseKeyOf(timing, b#kind, b#group, t, b#anim#now)

    /// 鍵の局所の姿勢（時刻 t のコマ）。クリップが無ければ休みの姿勢。
    def localOf(rig: Body, t: Float64, key: PoseKey): Vector[Skin3d.JointPose] =
        let at = (c: Clip, time: Float64, looping: Bool) -> sampledOr(rig, c, time, looping);
        match key {
            case PoseKey.Loop(_, c, g) =>
                let length = Map.get(c, rig#clips) |> Option.map(AnimationClip3d.duration) |> Option.getWithDefault(1.0);
                at(c, t + Int32.toFloat64(g) * length / Int32.toFloat64(groups()), true)
            case PoseKey.Once(_, c, f) => at(c, Int32.toFloat64(f) / framesPerSecond(), false)
        }

    /// 描く敵 1 体: 型・ずらしの組・クリップ・体の world の行列・発光の倍率（1 で glb のまま）。
    pub type alias Posed = { kind = Kind, group = Int32, anim = Anim, world = Mat4.Mat4, glow = Float64 }

    /// このコマに作った物: 置いた物と、作った姿勢の数（共有した物は 1 つと数える）。
    pub type alias Drawn = { instances = List[Scene3d.Instance3d], poses = Int32 }

    /// 混ぜている途中か（混ぜる割合 0..1 を返す）。
    def blendOf(blendSeconds: Float64, t: Float64, a: Anim): Option[(Track, Float64)] =
        a#before |> Option.filter(_ -> blendSeconds > 0.0 and t - a#switchedAt < blendSeconds)
            |> Option.map(b -> (b, Num.clamp01((t - a#switchedAt) / blendSeconds)))

    /// 時刻 t の敵の置いた物（体が読めていない型は描かない）。
    pub def drawnOf(models: Bodies, timing: Timing, blendSeconds: Float64, t: Float64, posed: List[Posed]): Drawn =
        let steady = posed |> List.filter(b -> Option.isEmpty(blendOf(blendSeconds, t, b#anim)))
            |> List.map(b -> poseKeyOf(timing, b#kind, b#group, t, b#anim#now)) |> List.toSet;
        let shared = steady |> Set.toList |> List.filterMap(key -> bodyOfKey(models, key) |> Option.map(body -> (key, Pose3d.compute(body#skin, localOf(body, t, key)))))
            |> List.toMap;
        let instances = posed |> List.flatMap(b -> Map.get(b#kind, models) |> Option.toList |> List.flatMap(body -> {
            let pose = poseOf(body, timing, shared, blendSeconds, t, b);
            Model3d.partInstances(b#world, body#model) |> List.map(i -> glowing(b#glow, Scene3d.withPose(pose, i)))
        }));
        let blended = posed |> List.count(b -> Option.nonEmpty(blendOf(blendSeconds, t, b#anim)));
        { instances = instances, poses = Map.size(shared) + blended }

    /// 置いた物の材質の発光を k 倍にする（1 なら何もしない・材質の無い物もそのまま）。
    def glowing(k: Float64, i: Scene3d.Instance3d): Scene3d.Instance3d =
        if (k == 1.0) i
        else Scene3d.instanceFieldsOf(i)#material
            |> Option.map(m -> Scene3d.withMaterial(Scene3d.withEmissionIntensity(Scene3d.materialFieldsOf(m)#emissionIntensity * k, m), i))
            |> Option.getWithDefault(i)

    def kindOfKey(key: PoseKey): Kind = match key {
        case PoseKey.Loop(k, _, _) => k
        case PoseKey.Once(k, _, _) => k
    }

    def bodyOfKey(models: Bodies, key: PoseKey): Option[Body] = Map.get(kindOfKey(key), models)

    /// クリップ c の時刻 time の局所の姿勢（クリップが無ければ休みの姿勢）。
    // WhyNot: Option.getWithDefault(Skin3d.restPose(..)) にしない — 既定の値は引数なので、クリップがある時も毎回休みの姿勢を作る。
    def sampledOr(rig: Body, c: Clip, time: Float64, looping: Bool): Vector[Skin3d.JointPose] = match Map.get(c, rig#clips) {
        case Some(clip) => AnimationClip3d.sample(rig#skin, clip, time, looping)
        case None       => Skin3d.restPose(rig#skin)
    }

    /// 共有の姿勢から鍵 key の姿勢（無ければその場で作る）。
    // WhyNot: Option.getWithDefault(Pose3d.compute(..)) にしない — 既定の値は引数なので、共有の姿勢がある敵の分も毎コマ姿勢を作り直す。
    def sharedOr(body: Body, shared: Map[PoseKey, Pose3d.Pose3d], t: Float64, key: PoseKey): Pose3d.Pose3d = match Map.get(key, shared) {
        case Some(pose) => pose
        case None       => Pose3d.compute(body#skin, localOf(body, t, key))
    }

    /// 1 体の姿勢: 混ぜている途中なら 2 つのクリップを混ぜて作り、ほかは共有の姿勢。
    def poseOf(body: Body, timing: Timing, shared: Map[PoseKey, Pose3d.Pose3d], blendSeconds: Float64, t: Float64, b: Posed): Pose3d.Pose3d =
        let nowKey = poseKeyOf(timing, b#kind, b#group, t, b#anim#now);
        match blendOf(blendSeconds, t, b#anim) {
            case Some((before, w)) =>
                Pose3d.compute(body#skin, Pose3d.blend(localOf(body, t, poseKeyOf(timing, b#kind, b#group, t, before)), localOf(body, t, nowKey), w))
            case None => sharedOr(body, shared, t, nowKey)
        }
}
