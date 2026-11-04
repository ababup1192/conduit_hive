// 遊びの規則: 終了の確認・マウスのキャプチャ・層の並び・始まりの区画。
mod TestRules {
    use fge::{App, SortingLayer}
    use fge::GameEngine.Key
    use TestSupport.{eastRoom, resWith}

    def res(): Res.Res = resWith(eastRoom())

    def w0(): World.World = World.initial(res())

    def pressing(k: Key): App.Frame = { justPressed = Set#{k}, down = Set#{k} | App.emptyFrame() }

    @Test
    def testQuitAskedThenNoReturnsToPlay(): Unit \ Assert =
        let asked = World.askQuit(w0());
        Assert.assertEq(expected = (true, false, false),
            (World.isAskingQuit(asked), World.isQuitting(asked), World.isAskingQuit(World.answerQuit(false, asked))))

    @Test
    def testQuitConfirmedOnlyAfterYes(): Unit \ Assert =
        Assert.assertEq(expected = true, World.isQuitting(World.answerQuit(true, World.askQuit(w0()))))

    /// 窓を押すとキャプチャ・キャプチャ中の Esc はキャプチャを放すだけ・放している時の Esc で終了の確認。
    @Test
    def testEscapeReleasesCaptureBeforeAskingQuit(): Unit \ Assert =
        let captured = Controls.step({ mouseClicked = true | App.emptyFrame() }, res(), w0());
        let released = Controls.step(pressing(Key.Escape), res(), captured);
        let asked = Controls.step(pressing(Key.Escape), res(), released);
        Assert.assertEq(expected = (true, false, false, true),
            (World.isLooking(captured), World.isLooking(released), World.isAskingQuit(released), World.isAskingQuit(asked)))

    /// 終了の確認の窓が出ている間は、前へ押しても歩かない。
    @Test
    def testBodyStaysWhileAskingQuit(): Unit \ Assert =
        let asked = World.askQuit(w0());
        let after = World.step(res(), World.walking({ forward = 1.0 | Walker.idle() }), asked);
        Assert.assertEq(expected = World.walkerOf(asked)#x, World.walkerOf(after)#x)

    @Test
    def testClickInsideQuitWindowQuits(): Unit \ Assert =
        let asked = World.askQuit(w0());
        Assert.assertEq(expected = true,
            World.isQuitting(Controls.tapAt(res(), { x = World.width() / 2.0, y = World.height() / 2.0 }, asked)))

    /// 本物の迷路の Doc: 始まりは start の印の区画（Doc の印の列・行のマスの文字）に立つ。
    @Test
    def testStartsInTheMarkedZone(): Unit \ {Assert, Fs.FileRead} =
        let doc = MazeDoc.load(MazeDoc.path());
        let r = resWith(doc);
        let mark = MazeDoc.rec(doc)#marks |> List.find(mk -> mk#kind == MazeDoc.MarkKind.Start);
        Assert.assertEq(expected = mark |> Option.map(mk -> Maze.charAt(r#maze, { col = mk#col, row = mk#row })), World.zoneOf(r, World.initial(r)))

    @Test
    def testLayersAreStackedBackToFront(): Unit \ Assert =
        Assert.assertEq(expected = true, SortingLayer.isStacked(ZOrder.layers()))
}
