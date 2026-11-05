// GpuWarmup — 遊びの途中で初めて出る物（蹴りの脚・持ち替える銃・手榴弾・肉片・爆発・曳光弾・落とした物・敵の 2 種類）を、
// 視錐台の外へ置いて、形と絵と材質のプログラムを GPU へ先に上げさせる（純粋）。
// engine は視錐台の外の物を描かないが、形と絵を上げ、材質のプログラムを組む（間引くのは描く直前）。
// 起動の直後は全部を置き、その後は材質のプログラム 1 つにつき 1 つだけを置き続ける。
// WhyNot: 初めて出るコマに任せない — 1024² の絵の mip 作りと材質のプログラムの組み立てがそのコマに乗り、submit が 40 ms 跳ねる。
// WhyNot: 起動の直後のコマだけ置かない — 材質のプログラムの置き場は、使わない物を数の上限（今使っている数の 2 倍・16 以上）で追い出すので、
//   先に組んだ物がしばらく出ないと消え、初めて出るコマでまた組む（形と絵は置き場の上限を超えない限り残る）。
// WhyNot: 全部を置き続けない — 間引く物も 1 つごとに材質の鍵と置き場を引くので、70 個ほどで 1 コマの submit が 0.3 ms 増える。
mod GpuWarmup {
    use fge::{Mat4, Mesh3d, Model3d, Scene3d, Texture3d, Vec3}

    /// 先に上げる物。all = 起動の直後に置く全部・keep = その後も置き続ける物（材質のプログラム 1 つにつき 1 つ）・
    /// textures = 材質が読む絵（場面の textures に足す）。
    pub type alias Warmup = { all = List[Scene3d.Instance3d], keep = List[Scene3d.Instance3d], textures = List[Texture3d.Texture3d] }

    /// 何も置かない（Res を組み始める時の仮の値）。
    pub def empty(): Warmup = { all = Nil, keep = Nil, textures = Nil }

    /// 起動からこの秒数の間は全部を置く（遊びの時計。Pass の場面は 1 コマ遅れて描かれるので 1 コマより長く取る）。
    def seconds(): Float64 = 0.25

    /// 時刻 t に置く物。
    pub def at(w: Warmup, t: Float64): List[Scene3d.Instance3d] = if (t < seconds()) w#all else w#keep

    /// 先に上げる物（どれも視錐台の外の遠い下へ動かした物）。res は形の束を持つ物（Res.Res を渡す）。
    // WhyNot: Res.Res を名指しで受けない — Res がこの値を持つので、名指しすると Res と互いに使い合う。
    pub def of(res: { creatures = Creatures.Bodies, timing = Creatures.Timing, viewmodels = FpViewmodel.Viewmodels, pickupArt = PickupModels.Art,
                      gibArt = Gibs.Art, blastArt = BlastFx.Art, tracerArt = Tracers.Art, grenadeModel = Option[Model3d.Model3d], bootArt = Boot.Art | r }): Warmup =
        let skinned = List.append(creatures(res#creatures, res#timing), viewmodels(res#viewmodels));
        let plain = List.flatten(Boot.instancesAt(res#bootArt, 0.3) :: pickups(res#pickupArt) :: gibs(res#gibArt) :: blast(res#blastArt)
            :: tracer(res#tracerArt) :: grenade(res#grenadeModel) :: Nil);
        { all = List.append(skinned, plain) |> List.map(parked),
          keep = plain |> List.filterMap(i -> programKeyOf(i) |> Option.map(k -> (k, i))) |> List.toMap |> Map.valuesOf |> List.map(parked),
          textures = List.flatten((res#viewmodels |> Map.valuesOf |> List.flatMap(v -> v#model#textures)) :: res#bootArt#textures :: Nil) }

    /// 材質のプログラムを分ける物（GLSL の中身の鍵・uv の有無・法線マップ・半透明・両面・cutout）。材質の無い物は None。
    // WhyNot: 骨つきの物を置き続ける物に入れない — 姿勢を外して置くので骨の無い版のプログラムになり、本当に描く版を残さない。
    def programKeyOf(i: Scene3d.Instance3d): Option[(Int64, Bool, Bool, Bool, Bool, Bool)] =
        let f = Scene3d.instanceFieldsOf(i);
        f#material |> Option.map(m -> {
            let mf = Scene3d.materialFieldsOf(m);
            (force mf#shaderHash, Option.nonEmpty(Mesh3d.uvs(f#mesh)), Option.nonEmpty(mf#normalMap), mf#blend, mf#doubleSided, mf#cutout)
        })

    /// 置いた物 i を、形と材質はそのままに、どのカメラの視錐台にも入らない遠い下へ動かし、姿勢を外した物。
    // WhyNot: 骨つきの物に姿勢を付けたまま置かない — engine は姿勢で形が境界の外へ出うる物を間引かないので、見えない所で毎コマ描く。
    //   姿勢を外すと骨つきの版の材質のプログラムは先に組まれないが、敵と構えている銃は始めから画面にいて、そこで組まれる。
    def parked(i: Scene3d.Instance3d): Scene3d.Instance3d =
        let f = Scene3d.instanceFieldsOf(i);
        let moved = Scene3d.meshInstance(f#mesh, Mat4.mul(Mat4.translate(Vec3.v3(0.0, -100000.0, 0.0)), f#world)) |> Scene3d.withName("warmup");
        f#material |> Option.map(m -> Scene3d.withMaterial(m, moved)) |> Option.getWithDefault(moved)

    /// 敵の型ごとに 1 体。
    def creatures(bodies: Creatures.Bodies, timing: Creatures.Timing): List[Scene3d.Instance3d] =
        let posed = bodies |> Map.keysOf |> Set.toList
            |> List.map(k -> { kind = k, group = 0, anim = Creatures.walkAnim(), world = Mat4.identity(), glow = 1.0 });
        Creatures.drawnOf(bodies, timing, 0.0, 0.0, posed)#instances

    /// 持ち替えられる銃の全部の腕と銃（撃つクリップの頭の姿勢）。
    def viewmodels(rigs: FpViewmodel.Viewmodels): List[Scene3d.Instance3d] =
        rigs |> Map.valuesOf |> List.flatMap(rig -> {
            let pose = FpViewmodel.poseOf(rig, { clip = "fire", elapsed = 0.0, stretchTo = None, looping = false });
            FpViewmodel.instancesOf(rig, pose, Mat4.identity())
        })

    /// 拾う物の種類ごとに 1 つ（倒れた敵が落とす物を含む）。
    def pickups(art: PickupModels.Art): List[Scene3d.Instance3d] =
        art#bodies |> Map.keysOf |> Set.toList
            |> List.flatMap(k -> PickupModels.instancesAt(art, k, { x = 0.0, z = 0.0, y = 0.0, yaw = 0.0, scale = 1.0 }))

    /// 肉片の形ごとに 1 つ。
    def gibs(art: Gibs.Art): List[Scene3d.Instance3d] =
        art#shapes |> Map.valuesOf |> List.map(shape -> {
            let placed = Scene3d.meshInstance(shape#mesh, Mat4.identity());
            shape#material |> Option.map(m -> Scene3d.withMaterial(m, placed)) |> Option.getWithDefault(placed)
        })

    /// 爆発の火の玉の塊の全部の形と、衝撃の輪・焦げ跡・残り火（どれも火の材質）。
    def blast(art: BlastFx.Art): List[Scene3d.Instance3d] =
        List.append(Vector.toList(art#puffs), art#ring :: art#scorch :: art#embers :: Nil)
            |> List.map(mesh -> Scene3d.meshInstance(mesh, Mat4.identity()) |> Scene3d.withMaterial(art#fire))

    def tracer(art: Tracers.Art): List[Scene3d.Instance3d] =
        (Scene3d.meshInstance(art#mesh, Mat4.identity()) |> Scene3d.withMaterial(art#material)) :: Nil

    def grenade(model: Option[Model3d.Model3d]): List[Scene3d.Instance3d] =
        model |> Option.toList |> List.flatMap(Model3d.partInstances(Mat4.identity()))
}
