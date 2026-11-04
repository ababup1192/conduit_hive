// 遊びの規則: 終了の確認・マウスのキャプチャ・層の並び・始まりの区画。画面の移り変わりとポーズは TestFlow。
mod TestRules {
    use fge::{App, SortingLayer}
    use fge::GameEngine.Key
    use TestSupport.{eastRoom, resWith, walkerIn}

    def res(): Res.Res = resWith(eastRoom())

    def w0(): World.World = World.initial(res())

    def pressing(k: Key): App.Frame = { justPressed = Set#{k}, down = Set#{k} | App.emptyFrame() }

    /// Esc で確認の窓が出る（まだ終わらない）。
    @Test
    def testQuitAskedIsNotQuitting(): Unit \ Assert =
        let asked = World.askQuit(w0());
        Assert.assertEq(expected = (true, false), (World.isAskingQuit(asked), World.isQuitting(asked)))

    /// 確認の窓でいいえを選ぶと遊びへ戻る。
    @Test
    def testQuitAnsweredNoReturnsToPlay(): Unit \ Assert =
        Assert.assertEq(expected = false, World.isAskingQuit(World.answerQuit(false, World.askQuit(w0()))))

    @Test
    def testQuitConfirmedOnlyAfterYes(): Unit \ Assert =
        Assert.assertEq(expected = true, World.isQuitting(World.answerQuit(true, World.askQuit(w0()))))

    /// 窓を押すとマウスをキャプチャする。
    @Test
    def testClickCapturesTheMouse(): Unit \ Assert =
        Assert.assertEq(expected = true, World.isLooking(Controls.step({ mouseClicked = true | App.emptyFrame() }, res(), w0())))

    /// 遊んでいる間の Esc はポーズしてキャプチャを放す（終了の確認は出さない）。
    @Test
    def testEscapeWhilePlayingPauses(): Unit \ Assert =
        let captured = Controls.step({ mouseClicked = true | App.emptyFrame() }, res(), w0());
        let paused = Controls.step(pressing(Key.Escape), res(), captured);
        Assert.assertEq(expected = (true, false, false), (World.isPaused(paused), World.isLooking(paused), World.isAskingQuit(paused)))

    /// タイトルの Esc で終了の確認を出す。
    @Test
    def testEscapeOnTitleAsksQuit(): Unit \ Assert =
        Assert.assertEq(expected = true, World.isAskingQuit(Controls.step(pressing(Key.Escape), res(), World.title())))

    /// 終了の確認の窓が出ている間は、前へ押しても歩かない。
    @Test
    def testBodyStaysWhileAskingQuit(): Unit \ Assert =
        let asked = World.askQuit(w0());
        let after = World.step(res(), World.walking({ forward = 1.0 | Walker.idle() }), asked);
        Assert.assertEq(expected = walkerIn(asked) |> Option.map(b -> b#x), walkerIn(after) |> Option.map(b -> b#x))

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
