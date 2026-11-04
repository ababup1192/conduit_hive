// View — World から「(置き場所, 見せたい物) のリスト」と、その前に描く Pass の計画への投影（純粋）。
//
// ── 画面の層（奥から手前へ）──
// 場面（Layer.Scene）: 一人称の迷路（StageView。Pass の中で 3D の場面とブルームを組み、後処理の面 1 枚で画面へ）。
// 印（Layer.Hud）: マウスをキャプチャしている間の照準の点・F3 の診断の行。
// 終了の確認の窓（Layer.Prompt）: 場面のどれよりも手前に出る。押せる物の当たりは絵と同じ木に ZStack.hit で積む。
mod View {

    use fge::{App, Color, FrameDiagnostics, RawDraw, Render, SortingLayer, TextDraw, Vec2, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値。部品は World でなくこれを読む（lint/rules.flix の view-no-world）。
    pub type alias In = {
        stage = StageView.In,
        theme = ThemeDoc.Doc,
        askingQuit = Bool,
        quitPrompt = String,
        // マウスをキャプチャしているか（画面の真ん中に照準の点を出す）・F3 の診断の行を出すか。
        looking = Bool,
        showsDiagnostics = Bool
    }

    /// 描く元と World から描くのに要る値だけを写す（View の中で World を読むのは入口の frame・passPlan とここだけ）。
    pub def inputOf(res: Res.Res, w: World.World): In =
        { stage = stageIn(res, w), theme = res#theme, askingQuit = World.isAskingQuit(w), quitPrompt = SampleDoc.rec(res#sample)#quitPrompt,
          looking = World.isLooking(w), showsDiagnostics = World.showsDiagnostics(w) }

    /// 一人称の場面の値: 目と、今いる区画から見える区画の絵。
    def stageIn(res: Res.Res, w: World.World): StageView.In =
        let walk = WalkDoc.rec(res#walk);
        let body = World.walkerOf(w);
        let drawn = Maze.visibleFrom(res#maze, body#x, body#z);
        { t = World.seconds(w), eye = Walker.eyeOf(walk, body), yaw = body#yaw, pitch = body#pitch, fovY = walk#fovY,
          look = LookDoc.rec(res#look),
          zones = drawn |> Set.toList |> List.filterMap(id -> Map.get(id, res#art)) }

    pub def frame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        frameOf(ctx, inputOf(res, w))

    /// 本編の描き物（描き出しも同じ物を呼ぶ）。
    def frameOf(ctx: App.ViewCtx, w: In): List[Render.PlacedItem] =
        SortingLayer.compose(ctx, layers(ctx, w))

    /// 本編より先に描く Pass の計画（Main の App.withPassPlan と描き出しが呼ぶ）。
    pub def passPlan(res: Res.Res, w: World.World): Render.PassPlan = StageView.passPlan(stageIn(res, w))

    /// 層ごとの木（絵と押せる物の当たり）。Controls.tapAt も同じ木から押した物を選ぶ。
    pub def layers(ctx: App.ViewCtx, w: In): List[(Layer, ZStack.Tree[Layer, World.Press])] =
        (Layer.Scene, StageView.frameTree()) :: (Layer.Hud, ZStack.leaf(hud(ctx, w))) :: (Layer.Prompt, quitPrompt(ctx, w)) :: Nil

    // ── 画面の上の小さな印（Layer.Hud） ──

    /// マウスをキャプチャしている間だけ画面の真ん中に照準の点と、F3 の診断の行（左上）。
    def hud(ctx: App.ViewCtx, w: In): List[Render.PlacedItem] =
        let theme = ThemeDoc.rec(w#theme);
        let center = { x = World.width() / 2.0, y = World.height() / 2.0 };
        let dot = if (w#looking and not w#askingQuit)
                      RawDraw.circleAt(center, 1.6, Color.darken(theme#bg, 0.3), 0) :: RawDraw.circleAt(center, 1.0, theme#accent, 1) :: Nil
                  else Nil;
        let rows = if (w#showsDiagnostics) ctx#diagnostics |> Option.map(FrameDiagnostics.summaryLines) |> Option.getWithDefault(Nil) else Nil;
        let lines = rows |> List.zipWithIndex |> List.map(e -> {
            let (i, line) = e;
            let size = 8.0;
            TextDraw.centered({ text = line, atlas = ctx#atlas, size = size, color = theme#accent, z = 2,
                                centerX = 4.0 + TextDraw.width(line, ctx#atlas, size) / 2.0, y = 4.0 + Int32.toFloat64(i) * (size + 2.0) })
        });
        List.append(dot, lines)

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
                { at = Vec2.zero(), item = RawDraw.box({ x = World.width(), y = World.height() }, theme#bg, 0) |> Render.fade(0.6) }
                    :: { at = at, item = RawDraw.box(size, Color.darken(theme#bg, 0.2), 1) }
                    :: TextDraw.centeredAt({ text = w#quitPrompt, atlas = ctx#atlas, size = 16.0, color = theme#accent, z = 2,
                                             center = { x = World.width() / 2.0, y = World.height() / 2.0 } })
                    :: Nil;
            ZStack.blocking(Some(World.Press.QuitNo),
                ZStack.of(ZStack.leaf(window) :: ZStack.hit(World.Press.QuitYes, { position = at, size = size }) :: Nil))
        }
}
