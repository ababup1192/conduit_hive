// Preload3d — 遊びの途中で初めて出る物（蹴りの脚・持ち替える銃・手榴弾・肉片・爆発・曳光弾・落とした物・敵の種類）の一覧を
// App.withPreload3d へ渡し、形と絵と材質のプログラムを起動の時に GPU へ上げさせる（純粋）。
// WhyNot: 初めて出るコマに任せない — 1024² の絵の mip 作りと材質のプログラムの組み立てがそのコマに乗り、submit が 40 ms 跳ねる。
mod Preload3d {
    use fge::{App, Mat4, Model3d, Scene3d, Texture3d}

    /// app に先に上げる物を宣言する。resOf = World から描く元を引く関数。
    // WhyNot: key に束の中身を混ぜない — 束を作り直すのは Doc の読み直しの時だけで、その世代は engine が key に足す。
    pub def withPreload(resOf: w -> Res.Res, app: App.App[w, ef]): App.App[w, ef] =
        App.withPreload3d({ key = _ -> "first-appearance", instances = w -> instancesOf(resOf(w)), textures = w -> texturesOf(resOf(w)) }, app)

    /// 先に上げる物。
    // WhyNot: 骨つきの物の姿勢を外さない — 外すと骨の無い版のプログラムだけが組まれ、本当に描く版が初めて出るコマへ残る。
    def instancesOf(res: Res.Res): List[Scene3d.Instance3d] =
        List.flatten(creatures(res#creatures, res#timing) :: viewmodels(res#viewmodels) :: Boot.instancesAt(res#bootArt, 0.3) :: pickups(res#pickupArt)
            :: gibs(res#gibArt) :: blast(res#blastArt) :: tracer(res#tracerArt) :: grenade(res#grenadeModel) :: Nil)

    /// 先に上げる物の材質が読む絵。
    def texturesOf(res: Res.Res): List[Texture3d.Texture3d] =
        List.flatten((res#creatures |> Map.valuesOf |> List.flatMap(b -> b#model#textures)) :: (res#viewmodels |> Map.valuesOf |> List.flatMap(v -> v#model#textures))
            :: res#bootArt#textures :: res#pickupArt#textures :: res#gibArt#textures
            :: (res#grenadeModel |> Option.toList |> List.flatMap(m -> m#textures)) :: Nil)

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
