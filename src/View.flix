// View — World から「(置き場所, 見せたい物) のリスト」と、その前に描く Pass の計画への投影（純粋）。
// 入口（inputOf・passPlan・hudFrame）で先に画面（World.Screen）を選び、画面ごとの部品へ値を渡す。
//
// ── 画面の層（奥から手前へ）──
// 場面（Layer.Scene）: 3D の迷路（StageView。Pass の中で 3D の場面とブルームを組み、後処理の面 1 枚で画面へ）。
//   遊んでいる間は一人称の迷路と手前の腕と銃・タイトルとクリアは迷路をゆっくり見回す背景。
// メニュー（Layer.Menu）: タイトル・ポーズ・クリア（MenuView）。
// 終了の確認の窓（Layer.Prompt）: どれよりも手前に出る。押せる物の当たりは絵と同じ木に ZStack.hit で積む。
// HUD（照準・体力・武器の並び・弾の数・拾った知らせ・被弾の赤み・F3 の診断の行）は App.withHudView に繋ぐ hudFrame（HudView）。
mod View {

    use fge::{App, Camera3d, Color, Frustum, Mat4, Num, Render, Scene3d, SortingLayer, TextDraw, Vec2, Vec3, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値。部品は World でなくこれを読む（lint/rules.flix の view-no-world）。
    pub type alias In = { stage = StageView.In, overlay = Overlay }

    /// 場面の上に重ねるメニューと確認の窓の値。
    pub type alias Overlay = {
        theme = ThemeDoc.Doc,
        menu = MenuView.Menu,
        askingQuit = Bool,
        quitPrompt = String
    }

    /// 描く元と World から描くのに要る値だけを写す（View の中で World を読むのは入口の frame・passPlan・hudFrame とここだけ）。
    /// 先に画面を選び、遊んでいる場面の部品は Session を受ける。
    pub def inputOf(res: Res.Res, w: World.World): In = { stage = stageOf(res, w), overlay = overlayOf(res, w) }

    /// 画面ごとの 3D の場面。
    def stageOf(res: Res.Res, w: World.World): StageView.In =
        let t = World.seconds(w);
        match w#screen {
            case World.Screen.Title    => showcaseIn(res, t, titleCamera(res, t))
            case World.Screen.Play(s)  => stageIn(res, t, s)
            case World.Screen.Clear(c) => showcaseIn(res, t, clearCamera(res, t, c))
        }

    /// 画面ごとのメニューと確認の窓。
    def overlayOf(res: Res.Res, w: World.World): Overlay =
        let t = World.seconds(w);
        let text = UiTextDoc.rec(res#uiText);
        let menu = match w#screen {
            case World.Screen.Title    => MenuView.Menu.Title({ text = text, t = t })
            case World.Screen.Play(s)  => pauseMenuOf(text, World.pauseOf(s))
            case World.Screen.Clear(c) => MenuView.Menu.Clear({ text = text, tally = c, t = t })
        };
        { theme = res#theme, menu = menu, askingQuit = World.isAskingQuit(w), quitPrompt = text#quitPrompt }

    /// ポーズのメニュー（ポーズしていなければ出さない）。
    def pauseMenuOf(text: UiTextDoc.Rec, p: World.Pause): MenuView.Menu = match p {
        case World.Pause.Running         => MenuView.Menu.Hidden
        case World.Pause.Paused(picked)  => MenuView.Menu.Pause({ text = text, selected = picked })
    }

    /// HUD の入口（Game の App.withHudView と描き出しが呼ぶ）。遊んでいる間だけ（ポーズの間はメニューを読ませるので出さない）。
    pub def hudFrame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        World.sessionOf(w) |> Option.filter(s -> World.pauseOf(s) == World.Pause.Running)
            |> Option.map(s -> HudView.draw(ctx, playHud(res, World.seconds(w), World.isAskingQuit(w), World.isLooking(w), s)))
            |> Option.getWithDefault(Nil)

    /// 遊んでいる場面の HUD の値。
    def playHud(res: Res.Res, t: Float64, askingQuit: Bool, looking: Bool, s: World.Session): HudView.Hud =
        let pd = PlayerDoc.rec(res#player);
        let health = World.healthOf(s);
        let a = World.arsenalOf(s);
        { theme = res#theme, askingQuit = askingQuit, looking = looking, showsDiagnostics = World.showsDiagnosticsIn(s),
          ammo = Arsenal.ammoOf(res#weapons, a),
          slots = WeaponsDoc.all() |> List.map(wp -> { weapon = wp, owned = Set.memberOf(wp, a#owned), current = wp == a#current }),
          health = Health.fraction(pd, health), hurt = Health.flash(pd, t, health), down = Health.downProgress(pd, t, health),
          notice = World.noticeOf(s) |> Option.flatMap(noticeIn(res, t)) }

    /// 拾った時の知らせ（出す長さを過ぎたら None）。文言は UiTextDoc の notice*（{n} は量）。
    def noticeIn(res: Res.Res, t: Float64, n: World.Notice): Option[HudView.Notice] =
        let age = (t - n#at) / Float64.max(0.05, PickupsDoc.rec(res#pickups)#noticeSeconds);
        if (age < 0.0 or age >= 1.0) None
        else Some({ text = noticeText(UiTextDoc.rec(res#uiText), n), age = age })

    def noticeText(tx: UiTextDoc.Rec, n: World.Notice): String =
        let template = match n#kind {
            case Pickups.Kind.HealthSmall   => tx#noticeHealth
            case Pickups.Kind.HealthLarge   => tx#noticeHealth
            case Pickups.Kind.AmmoShotgun   => tx#noticeShells
            case Pickups.Kind.AmmoRifle     => tx#noticeRounds
            case Pickups.Kind.WeaponShotgun => tx#noticeShotgun
            case Pickups.Kind.WeaponRifle   => tx#noticeRifle
        };
        String.replace(src = "{n}", dst = Int32.toString(n#amount), template)

    // ── 3D の場面 ──

    /// 一人称の場面の値（時刻 t）: 照準のカメラ・今いる区画から見える区画の絵・その区画の敵と projectile と拾う物・粒・手前の腕と銃・撃った瞬間の灯り。
    def stageIn(res: Res.Res, t: Float64, s: World.Session): StageView.In =
        let body = World.walkerOf(s);
        let camera = World.cameraOf(res, t, s);
        let a = World.arsenalOf(s);
        let particles = World.particlesOf(s);
        let drawn = Maze.visibleFrom(res#maze, body#x, body#z);
        let motion = { phase = Walker.stridePhase(WalkDoc.rec(res#walk), body), sway = World.swayOf(s) };
        let viewmodel = viewmodelIn(res, a, particles, motion, t);
        let horde = World.hordeOf(s);
        let frustum = Camera3d.frustum(camera, World.width() / World.height());
        let seen = (x: Float64, y: Float64, z: Float64, radius: Float64) ->
            Maze.zoneAt(res#maze, x, z) |> Option.exists(id -> Set.memberOf(id, drawn)) and Frustum.intersectsSphere(frustum, Vec3.v3(x, y, z), radius);
        let shots = horde#projectiles |> List.filter(p -> seen(p#at#x, p#at#y, p#at#z, 1.0));
        let items = pickupsIn(res, t, camera, drawn, World.takenOf(s));
        let props = if (Set.memberOf(res#maze#finalZone, drawn)) res#propArt else Nil;
        { t = t, camera = camera, look = LookDoc.rec(res#look),
          zones = drawn |> Set.toList |> List.filterMap(id -> Map.get(id, res#art)),
          billboards = List.append(
              shots |> List.filterMap(p -> Particles3d.spitBillboard(res#particles, Particles3d.textureName(), Res.particleRegion(res, Particles3d.Kind.Spark), p#at)),
              Particles3d.billboards(res#particles, Particles3d.textureName(), Res.particleRegion(res), Particles3d.Space.World, Mat4.identity(), t, particles)),
          flash = viewmodel |> Option.toList |> List.flatMap(h -> flashLights(res, a, t, StageView.fromEye(camera, fst(h)))),
          creatures = creaturesIn(res, t, horde#enemies |> List.filter(e -> seen(e#x, 1.0, e#z, creatureReach()))),
          pickups = List.append(items#instances, props),
          textures = List.flatten(res#stageTextures :: (res#creatures |> Map.valuesOf |> List.flatMap(b -> b#model#textures)) :: res#pickupArt#textures :: Nil),
          glows = List.append(shots |> List.map(p -> Particles3d.spitLight(res#particles, p#at)), items#lights),
          viewmodel = viewmodel |> Option.map(snd) }

    /// タイトルとクリアの背景: カメラから見える区画の迷路と拾う物だけ（敵・粒・腕と銃・的の柱は無し）。
    def showcaseIn(res: Res.Res, t: Float64, camera: Camera3d.Camera3d): StageView.In =
        let drawn = Maze.visibleFrom(res#maze, camera#eye#x, camera#eye#z);
        let items = pickupsIn(res, t, camera, drawn, Set.empty());
        { t = t, camera = camera, look = LookDoc.rec(res#look),
          zones = drawn |> Set.toList |> List.filterMap(id -> Map.get(id, res#art)),
          billboards = Nil, flash = Nil, creatures = Nil, pickups = items#instances, textures = List.append(res#stageTextures, res#pickupArt#textures),
          glows = items#lights, viewmodel = None }

    /// 見回しの速さ（度/秒）・目の傾き（度。負で少し見上げる）・タイトルの見回しの始めの向き（度。最後の部屋の長い向き）。
    // WhyNot: Doc へ出さない — 背景の演出の形で、遊びの手触りとして調整する値ではない。
    def showcaseTurn(): Float64 = 6.0
    def titleStartYaw(): Float64 = 250.0
    def showcasePitch(): Float64 = -4.0

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    /// 見回すカメラ: 足元 (x, z) の目の高さから、yaw（ラジアン）を向く。
    def showcaseCamera(res: Res.Res, x: Float64, z: Float64, yaw: Float64): Camera3d.Camera3d =
        let walk = WalkDoc.rec(res#walk);
        { eye = Vec3.v3(x, walk#eyeHeight + 0.5, z), yaw = yaw, pitch = rad(showcasePitch()),
          fovY = rad(walk#fovY), near = 0.05, far = LookDoc.rec(res#look)#fogFar }

    /// タイトルの背景: 最後の部屋の真ん中から 4 マス東から、時刻 t に合わせてゆっくり見回す（部屋が無ければ start の印）。
    def titleCamera(res: Res.Res, t: Float64): Camera3d.Camera3d =
        let (x, z) = Maze.middleCellOf(res#maze, res#maze#finalZone) |> Option.map(c -> Maze.centerOf(res#maze, { col = c#col + 4 | c }))
            |> Option.getWithDefault((res#maze#start#x, res#maze#start#z));
        showcaseCamera(res, x, z, rad(titleStartYaw() + showcaseTurn() * t))

    /// クリアの背景: 最後に立っていた所から、クリアした時の向きから時刻 t に合わせてゆっくり見回す。
    def clearCamera(res: Res.Res, t: Float64, c: World.Tally): Camera3d.Camera3d =
        showcaseCamera(res, c#x, c#z, c#yaw + rad(showcaseTurn() * (t - c#endedAt)))

    /// まだ拾っていない拾う物のうち、描く区画にある物: 視錐台に掛かる物の置いた物と、目に近い lights 個の弱い点光源。
    def pickupsIn(res: Res.Res, t: Float64, camera: Camera3d.Camera3d, drawn: Set[Char], taken: Set[Int32]): Pickup3d =
        let doc = PickupsDoc.rec(res#pickups);
        let look = LookDoc.rec(res#look);
        let frustum = Camera3d.frustum(camera, World.width() / World.height());
        let here = res#pickupPoints |> List.filter(p -> Set.memberOf(p#zone, drawn) and not Set.memberOf(p#id, taken));
        let shown = here |> List.filter(p -> Frustum.intersectsSphere(frustum, Vec3.v3(p#x, doc#hover, p#z), 0.9));
        let distance = (p: Pickups.Point) -> { let (dx, dz) = (p#x - camera#eye#x, p#z - camera#eye#z); dx * dx + dz * dz };
        let lit = here |> List.sortBy(p -> (distance(p), p#id)) |> List.take(doc#lights);
        { instances = shown |> List.flatMap(p ->
              PickupModels.instancesAt(res#pickupArt, p#kind, { x = p#x, z = p#z, y = Pickups.hoverAt(res#pickups, t, p), yaw = Pickups.spinAt(res#pickups, t, p), scale = doc#scale })),
          lights = lit |> List.map(p -> { position = Vec3.v3(p#x, doc#hover, p#z), color = look#stripColor, intensity = doc#lightIntensity, range = doc#lightRange }) }

    /// 描く区画の拾う物: 置いた物・点光源。
    type alias Pickup3d = { instances = List[Scene3d.Instance3d], lights = List[Scene3d.PointLight] }

    /// 敵を囲む球の半径（足元から 1 m の高さが真ん中。振り下ろした腕の先まで）。
    // WhyNot: Doc へ出さない — 調整する値ではなく glb の形（背丈約 2 m・爪の先が前へ約 1.14 m）から決まる大きさ。
    def creatureReach(): Float64 = 1.7

    /// 敵の置いた物（同じクリップの姿勢は共有する。Creatures.drawnOf）。
    def creaturesIn(res: Res.Res, t: Float64, enemies: List[Horde.Enemy]): List[Scene3d.Instance3d] =
        let posed = enemies |> List.map(e -> { kind = e#kind, group = e#id, anim = e#anim, world = Horde.worldOf(e) });
        Creatures.drawnOf(res#creatures, res#timing, EnemiesDoc.rec(res#enemies)#blendSeconds, t, posed)#instances

    /// 手前の腕と銃: 今の銃口（目の座標）と、場面に入れる物。構えている武器の glb が読めていなければ None。
    def viewmodelIn(res: Res.Res, a: Arsenal.Arsenal, particles: List[Particles3d.Particle], motion: FpViewmodel.Motion, t: Float64): Option[(Vec3.Vec3, StageView.Viewmodel)] =
        let hd = FpViewmodelDoc.rec(res#viewmodel);
        Map.get(a#current, res#viewmodels) |> Option.map(model -> {
            let pose = FpViewmodel.poseOf(model, FpViewmodel.playingAt(hd, FpViewmodel.clipLength(model, "fire"), t, a));
            let place = FpViewmodel.placeOf(hd, motion);
            let frame = FpViewmodel.muzzleFrame(model, pose, place);
            let muzzle = Mat4.apply(frame, Vec3.zero());
            (muzzle, { instances = FpViewmodel.instancesOf(model, pose, place), textures = model#model#textures,
                       billboards = Particles3d.billboards(res#particles, Particles3d.textureName(), Res.particleRegion(res), Particles3d.Space.Muzzle, frame, t, particles),
                       flash = flashLights(res, a, t, muzzle), fovY = hd#fovY, near = hd#near, far = hd#far,
                       ambientScale = hd#ambientScale, lampScale = hd#lampScale })
        })

    /// 撃った瞬間の灯り（点 at に 1 本。最後に撃ってから light の life の間だけ）。
    def flashLights(res: Res.Res, a: Arsenal.Arsenal, t: Float64, at: Vec3.Vec3): List[Scene3d.PointLight] =
        let lit = Particles3dDoc.rec(res#particles)#light;
        a#last |> Option.filter(s -> { let age = t - s#at; age >= 0.0 and age < lit#life })
            |> Option.map(_ -> { position = at, color = lit#color, intensity = lit#intensity, range = lit#range })
            |> Option.toList

    /// 本編の描き物（App の view と描き出しが呼ぶ）: 後処理の面と、その上のメニューと確認の窓（3D の場面は Pass の計画が描く）。
    pub def frame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        SortingLayer.compose(ctx, (Layer.Scene, StageView.frameTree()) :: overlayLayers(ctx, overlayOf(res, w)))

    /// 本編より先に描く Pass の計画（Main の App.withPassPlan と描き出しが呼ぶ）。
    pub def passPlan(res: Res.Res, w: World.World): Render.PassPlan = StageView.passPlan(stageOf(res, w))

    /// 層ごとの木（絵と押せる物の当たり）。Controls.tapAt がこの木から押した物を選ぶ。
    pub def layers(ctx: App.ViewCtx, w: In): List[(Layer, ZStack.Tree[Layer, World.Press])] =
        (Layer.Scene, StageView.frameTree()) :: overlayLayers(ctx, w#overlay)

    /// メニューと確認の窓の層。
    def overlayLayers(ctx: App.ViewCtx, o: Overlay): List[(Layer, ZStack.Tree[Layer, World.Press])] =
        (Layer.Menu, MenuView.tree(ctx, o#theme, o#menu)) :: (Layer.Prompt, quitPrompt(ctx, o)) :: Nil

    // ── 終了の確認の窓（Layer.Prompt） ──

    /// 閉じるボタンかタイトルの Esc で出る確認。場面を薄く沈める幕・窓・文言（文言は conduit_hive.uitext.json の quitPrompt）。
    /// 窓の中を押すと QuitYes・外を押すと QuitNo（blocking が奥の当たりを塞ぐ）。
    def quitPrompt(ctx: App.ViewCtx, w: Overlay): ZStack.Tree[Layer, World.Press] =
        if (not w#askingQuit) ZStack.leaf(Nil)
        else {
            let theme = ThemeDoc.rec(w#theme);
            let size = { x = World.width() * 0.6, y = 48.0 };
            let at = { x = (World.width() - size#x) / 2.0, y = (World.height() - size#y) / 2.0 };
            let window =
                { at = Vec2.zero(), item = Render.vgrad({ x = World.width(), y = World.height() }, { top = theme#bg, bottom = Color.darken(theme#bg, 0.6) }, 0) |> Render.fade(0.6) }
                    :: { at = at, item = Render.vgrad(size, { top = Color.lighten(theme#bg, 0.06), bottom = Color.darken(theme#bg, 0.35) }, 1)
                                          |> Render.rounded(6.0) |> Render.outlineA({ color = theme#accent, alpha = 0.5, width = 1.0 }) }
                    :: TextDraw.centeredAt({ text = w#quitPrompt, atlas = ctx#atlas, size = 16.0, color = theme#accent, z = 2,
                                             center = { x = World.width() / 2.0, y = World.height() / 2.0 } })
                    :: Nil;
            ZStack.blocking(Some(World.Press.QuitNo),
                ZStack.of(ZStack.leaf(window) :: ZStack.hit(World.Press.QuitYes, { position = at, size = size }) :: Nil))
        }
}
