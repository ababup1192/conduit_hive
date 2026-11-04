// View — World から「(置き場所, 見せたい物) のリスト」と、その前に描く Pass の計画への投影（純粋）。
//
// ── 画面の層（奥から手前へ）──
// 場面（Layer.Scene）: 一人称の迷路と手前の腕と銃（StageView。Pass の中で 3D の場面とブルームを組み、後処理の面 1 枚で画面へ）。
// 終了の確認の窓（Layer.Prompt）: 場面のどれよりも手前に出る。押せる物の当たりは絵と同じ木に ZStack.hit で積む。
// HUD（照準・体力・弾の数・被弾の赤み・F3 の診断の行）は App.withHudView に繋ぐ hudFrame（view の絵のどれよりも手前）。
mod View {

    use fge::{App, Bezier, Camera3d, Color, FrameDiagnostics, Frustum, Mat4, Num, Render, Scene3d, SortingLayer, TextDraw, Vec2, Vec3, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値。部品は World でなくこれを読む（lint/rules.flix の view-no-world）。
    pub type alias In = {
        stage = StageView.In,
        theme = ThemeDoc.Doc,
        askingQuit = Bool,
        quitPrompt = String
    }

    /// HUD を描くのに要る値。
    pub type alias Hud = {
        theme = ThemeDoc.Doc,
        askingQuit = Bool,
        // マウスをキャプチャしているか（照準を明るくする）・F3 の診断の行を出すか。
        looking = Bool,
        showsDiagnostics = Bool,
        // 構えている武器の残りの弾（無限なら None）。
        ammo = Option[Int32],
        // 体力の残りの割合（0..1）・被弾の赤みの強さ（0..1）・倒れてからやり直すまでの進み（0..1。倒れていなければ 0）。
        health = Float64,
        hurt = Float64,
        down = Float64
    }

    /// 描く元と World から描くのに要る値だけを写す（View の中で World を読むのは入口の frame・passPlan・hudFrame とここだけ）。
    pub def inputOf(res: Res.Res, w: World.World): In =
        { stage = stageIn(res, w), theme = res#theme, askingQuit = World.isAskingQuit(w), quitPrompt = SampleDoc.rec(res#sample)#quitPrompt }

    /// HUD の入口（Game の App.withHudView と描き出しが呼ぶ）。
    pub def hudFrame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        let d = EnemiesDoc.rec(res#enemies);
        let t = World.seconds(w);
        let health = World.healthOf(w);
        hud(ctx, { theme = res#theme, askingQuit = World.isAskingQuit(w), looking = World.isLooking(w),
                   showsDiagnostics = World.showsDiagnostics(w), ammo = Arsenal.ammoOf(res#weapons, World.arsenalOf(w)),
                   health = Health.fraction(d, health), hurt = Health.flash(d, t, health), down = Health.downProgress(d, t, health) })

    /// 一人称の場面の値: 照準のカメラ・今いる区画から見える区画の絵・その区画の敵と projectile・粒・手前の腕と銃・撃った瞬間の灯り。
    pub def stageIn(res: Res.Res, w: World.World): StageView.In =
        let body = World.walkerOf(w);
        let t = World.seconds(w);
        let camera = World.cameraOf(res, w);
        let a = World.arsenalOf(w);
        let particles = World.particlesOf(w);
        let drawn = Maze.visibleFrom(res#maze, body#x, body#z);
        let motion = { phase = Walker.stridePhase(WalkDoc.rec(res#walk), body), sway = World.swayOf(w) };
        let hands = handsIn(res, a, particles, motion, t);
        let horde = World.hordeOf(w);
        let seen = (x: Float64, y: Float64, z: Float64, radius: Float64) ->
            Maze.zoneAt(res#maze, x, z) |> Option.exists(id -> Set.memberOf(id, drawn)) and
            Frustum.intersectsSphere(Camera3d.frustum(camera, World.width() / World.height()), Vec3.v3(x, y, z), radius);
        let shots = horde#projectiles |> List.filter(p -> seen(p#at#x, p#at#y, p#at#z, 1.0));
        { t = t, camera = camera, look = LookDoc.rec(res#look),
          zones = drawn |> Set.toList |> List.filterMap(id -> Map.get(id, res#art)),
          billboards = List.append(
              shots |> List.filterMap(p -> Particles3d.spitBillboard(res#particles, Particles3d.textureName(), Res.particleRegion(res, Particles3d.Kind.Spark), p#at)),
              Particles3d.billboards(res#particles, Particles3d.textureName(), Res.particleRegion(res), Particles3d.Space.World, Mat4.identity(), t, particles)),
          flash = hands |> Option.toList |> List.flatMap(h -> flashLights(res, a, t, StageView.fromEye(camera, fst(h)))),
          creatures = creaturesIn(res, t, horde#enemies |> List.filter(e -> seen(e#x, 1.0, e#z, creatureReach()))),
          creatureTextures = res#creatures |> Map.valuesOf |> List.flatMap(r -> r#model#textures),
          glows = shots |> List.map(p -> Particles3d.spitLight(res#particles, p#at)),
          hands = hands |> Option.map(snd) }

    /// 敵を囲む球の半径（足元から 1 m の高さが真ん中。振り下ろした腕の先まで）。
    def creatureReach(): Float64 = 1.7

    /// 敵の置いた物（同じクリップの姿勢は共有する。Creatures.drawnOf）。
    def creaturesIn(res: Res.Res, t: Float64, enemies: List[Horde.Enemy]): List[Scene3d.Instance3d] =
        let bodies = enemies |> List.map(e -> { kind = e#kind, group = e#id, anim = e#anim, world = Horde.worldOf(e) });
        Creatures.drawnOf(res#creatures, EnemiesDoc.rec(res#enemies)#blendSeconds, t, bodies)#instances

    /// 手前の腕と銃: 今の銃口（目の座標）と、場面に入れる物。構えている武器の glb が読めていなければ None。
    def handsIn(res: Res.Res, a: Arsenal.Arsenal, particles: List[Particles3d.Particle], motion: Arms.Motion, t: Float64): Option[(Vec3.Vec3, StageView.Hands)] =
        let hd = HandsDoc.rec(res#hands);
        Map.get(a#current, res#rigs) |> Option.map(rig -> {
            let pose = Arms.poseOf(rig, Arms.playingAt(hd, Arms.clipLength(rig, "fire"), t, a));
            let place = Arms.placeOf(hd, motion);
            let frame = Arms.muzzleFrame(rig, pose, place);
            let muzzle = Mat4.apply(frame, Vec3.zero());
            (muzzle, { instances = Arms.instancesOf(rig, pose, place), textures = rig#model#textures,
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

    pub def frame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        frameOf(ctx, inputOf(res, w))

    /// 本編の描き物（描き出しも同じ物を呼ぶ）。
    def frameOf(ctx: App.ViewCtx, w: In): List[Render.PlacedItem] =
        SortingLayer.compose(ctx, layers(ctx, w))

    /// 本編より先に描く Pass の計画（Main の App.withPassPlan と描き出しが呼ぶ）。
    pub def passPlan(res: Res.Res, w: World.World): Render.PassPlan = StageView.passPlan(stageIn(res, w))

    /// 層ごとの木（絵と押せる物の当たり）。Controls.tapAt も同じ木から押した物を選ぶ。
    pub def layers(ctx: App.ViewCtx, w: In): List[(Layer, ZStack.Tree[Layer, World.Press])] =
        (Layer.Scene, StageView.frameTree()) :: (Layer.Prompt, quitPrompt(ctx, w)) :: Nil

    // ── HUD（App.withHudView） ──

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    /// 照準（真ん中）・左下の体力・右下の弾の数・被弾の赤み（画面の縁）・F3 の診断の行（左上）。照準はキャプチャしていない間は薄くする（撃てないことを見せる）。
    /// 終了の確認の窓が出ている間は出さない（窓の文言を読ませる）。
    def hud(ctx: App.ViewCtx, w: Hud): List[Render.PlacedItem] =
        let theme = ThemeDoc.rec(w#theme);
        let alpha = if (w#looking) 1.0 else 0.35;
        let panels = List.append(crosshair(theme#accent, theme#bg), List.append(healthPanel(ctx, theme#accent, theme#bg, w#health), ammoPanel(ctx, theme#accent, theme#bg, w#ammo)));
        let marks = if (w#askingQuit) Nil else List.append(hurtEdges(w#hurt, w#down), Render.fadeAll(alpha, panels));
        let rows = if (w#showsDiagnostics) ctx#diagnostics |> Option.map(FrameDiagnostics.summaryLines) |> Option.getWithDefault(Nil) else Nil;
        let lines = rows |> List.zipWithIndex |> List.map(e -> {
            let (i, line) = e;
            let size = 8.0;
            TextDraw.centered({ text = line, atlas = ctx#atlas, size = size, color = theme#accent, z = 4,
                                centerX = 4.0 + TextDraw.width(line, ctx#atlas, size) / 2.0, y = 4.0 + Int32.toFloat64(i) * (size + 2.0) })
        });
        List.append(marks, lines)

    /// 頂点ごとに色と濃さを持つ多角形を、画面の座標のまま置く。
    def gradAt(vertices: List[(Vec2.Vec2, Color, Float64)], z: Int32): Render.PlacedItem =
        { at = Vec2.zero(), item = Render.gradPolygon(vertices |> List.map(v -> { let (at, c, a) = v; { pos = at, color = c, alpha = a } }), z) }

    /// 照準: 真ん中を空けて 4 方向へ先細りに伸びる針（根元が濃く先へ薄れる）と、真ん中の小さな菱形。
    /// どれも 1 px 太い暗い影を下に敷き、明るい壁の前でも読める。
    def crosshair(ink: Color, shade: Color): List[Render.PlacedItem] =
        let c = p(World.width() / 2.0, World.height() / 2.0);
        let dirs = (1.0, 0.0) :: (-1.0, 0.0) :: (0.0, 1.0) :: (0.0, -1.0) :: Nil;
        let needle = (grow: Float64, color: Color, alphaIn: Float64, alphaOut: Float64, z: Int32, dir: (Float64, Float64)) -> {
            let (dx, dy) = dir;
            let (gap, len) = (3.0 - grow, 5.0 + grow * 2.0);
            let (wIn, wOut) = (0.8 + grow, 0.25 + grow);
            let at = (along: Float64, side: Float64) -> p(c#x + dx * along - dy * side, c#y + dy * along + dx * side);
            gradAt((at(gap, 0.0 - wIn), color, alphaIn) :: (at(gap + len, 0.0 - wOut), color, alphaOut)
                       :: (at(gap + len, wOut), color, alphaOut) :: (at(gap, wIn), color, alphaIn) :: Nil, z)
        };
        let diamond = (r: Float64, color: Color, a: Float64, z: Int32) ->
            gradAt((p(c#x, c#y - r), color, a) :: (p(c#x + r, c#y), color, a) :: (p(c#x, c#y + r), color, a) :: (p(c#x - r, c#y), color, a) :: Nil, z);
        List.flatten(
            (dirs |> List.map(needle(0.7, shade, 0.7, 0.2, 0)))
                :: (dirs |> List.map(needle(0.0, ink, 1.0, 0.35, 1)))
                :: (diamond(1.6, shade, 0.7, 0) :: diamond(0.9, ink, 1.0, 1) :: Nil) :: Nil)

    /// 右下の弾の数の板: 角の丸い縦のグラデの板に差し色の細い縁、中に弾の数（無限は ∞ の線）。
    def ammoPanel(ctx: App.ViewCtx, ink: Color, bg: Color, ammo: Option[Int32]): List[Render.PlacedItem] =
        let size = p(44.0, 22.0);
        let at = p(World.width() - 10.0 - size#x, World.height() - 10.0 - size#y);
        let center = p(at#x + size#x / 2.0, at#y + size#y / 2.0);
        let panel = Render.vgrad(size, { top = Color.lighten(bg, 0.08), bottom = Color.darken(bg, 0.4) }, 0)
            |> Render.fade(0.8) |> Render.rounded(4.0) |> Render.outlineA({ color = ink, alpha = 0.45, width = 1.0 });
        let count = match ammo {
            case Some(n) => TextDraw.centeredAt({ text = Int32.toString(n), atlas = ctx#atlas, size = 14.0, color = ink, z = 2, center = center }) :: Nil
            case None    => infinity(center, ink)
        };
        { at = at, item = panel } :: count

    /// 傷の色（暖かい赤。クリーチャーの発光と同じ側の色）。
    def wound(): Color = Color.rgb(0.66, 0.07, 0.04)

    /// 左下の体力の板: 角の丸い縦のグラデの板に差し色の細い縁、中に残りの割合の帯（左が濃く右へ明るむ・減ると傷の色へ寄る）と数。
    def healthPanel(ctx: App.ViewCtx, ink: Color, bg: Color, health: Float64): List[Render.PlacedItem] =
        let size = p(92.0, 22.0);
        let at = p(10.0, World.height() - 10.0 - size#y);
        let panel = Render.vgrad(size, { top = Color.lighten(bg, 0.08), bottom = Color.darken(bg, 0.4) }, 0)
            |> Render.fade(0.8) |> Render.rounded(4.0) |> Render.outlineA({ color = ink, alpha = 0.45, width = 1.0 });
        let left = at#x + 6.0;
        let right = at#x + size#x - 30.0;
        let (top, bottom) = (at#y + 7.0, at#y + size#y - 7.0);
        let tone = Color.mix(wound(), ink, Num.clamp01(health * 1.6 - 0.3));
        let end = left + (right - left) * Num.clamp01(health);
        let track = gradAt((p(left, top), Color.darken(bg, 0.6), 0.9) :: (p(right, top), Color.darken(bg, 0.6), 0.9)
                               :: (p(right, bottom), Color.darken(bg, 0.3), 0.9) :: (p(left, bottom), Color.darken(bg, 0.3), 0.9) :: Nil, 1);
        let fill = gradAt((p(left, top), Color.darken(tone, 0.35), 1.0) :: (p(end, top), Color.lighten(tone, 0.15), 1.0)
                              :: (p(end, bottom), tone, 1.0) :: (p(left, bottom), Color.darken(tone, 0.5), 1.0) :: Nil, 2);
        let count = TextDraw.centeredAt({ text = Int32.toString(Num.roundInt(health * 100.0)), atlas = ctx#atlas, size = 12.0, color = tone, z = 2,
                                         center = p(at#x + size#x - 15.0, at#y + size#y / 2.0) });
        { at = at, item = panel } :: track :: (if (health > 0.0) fill :: Nil else Nil) ::: count :: Nil

    /// 被弾の赤み: 画面の 4 辺から内へ消える台形の帯（縁が濃い）。倒れている間は進みに合わせて画面全体を暗い赤へ沈める。
    def hurtEdges(hurt: Float64, down: Float64): List[Render.PlacedItem] =
        let (wd, ht) = (World.width(), World.height());
        let inset = 20.0 + 26.0 * hurt;
        let a = Num.clamp01(hurt) * 0.55;
        let red = wound();
        let band = (o1: Vec2.Vec2, o2: Vec2.Vec2, i2: Vec2.Vec2, i1: Vec2.Vec2) ->
            gradAt((o1, red, a) :: (o2, red, a) :: (i2, red, 0.0) :: (i1, red, 0.0) :: Nil, 0);
        let (tl, tr, br, bl) = (p(0.0, 0.0), p(wd, 0.0), p(wd, ht), p(0.0, ht));
        let (itl, itr, ibr, ibl) = (p(inset, inset), p(wd - inset, inset), p(wd - inset, ht - inset), p(inset, ht - inset));
        let edges = if (a <= 0.0) Nil else band(tl, tr, itr, itl) :: band(tr, br, ibr, itr) :: band(br, bl, ibl, ibr) :: band(bl, tl, itl, ibl) :: Nil;
        let veil = if (down <= 0.0) Nil
            else { at = Vec2.zero(), item = Render.vgrad({ x = wd, y = ht }, { top = Color.darken(red, 0.7), bottom = Color.darken(red, 0.9) }, 0) |> Render.fade(Num.clamp01(down) * 0.85) } :: Nil;
        List.append(edges, veil)

    /// ∞ の線（横に寝た 8 の字。字の無いフォントでも出る）。
    def infinity(center: Vec2.Vec2, ink: Color): List[Render.PlacedItem] =
        let points = List.range(0, 41) |> List.map(i -> {
            let t = Int32.toFloat64(i) * Num.tau() / 40.0;
            let k = 1.0 + Num.sin(t) * Num.sin(t);
            p(center#x + 9.0 * Num.cos(t) / k, center#y + 9.0 * Num.sin(t) * Num.cos(t) / k)
        });
        Bezier.polyline(points, { width = 1.6 }, ink, 2)

    // ── 終了の確認の窓（Layer.Prompt） ──

    /// Esc か閉じるボタンで出る確認。場面を薄く沈める幕・窓・文言（文言は sample.kind.json の quitPrompt）。
    /// 窓の中を押すと QuitYes・外を押すと QuitNo（blocking が奥の当たりを塞ぐ）。
    def quitPrompt(ctx: App.ViewCtx, w: In): ZStack.Tree[Layer, World.Press] =
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
