// 始まりの登録簿（Starts.all を App.startOrBug / App.buildStart で引く）と、引数との橋渡し。
mod TestStarts {
    use fge::{App, HeadlessLoad, Resources, Vec2}

    def app(): App.App[Resources.With[Res.Res, World.World], {}] \ Fs.FileRead + IO = Game.app(HeadlessLoad.handle(Controls.loadDocs))

    /// at は体を x・z に置く（start の部屋 A の中の点）。
    @Test
    def testAtPlacesTheBody(): Unit \ Assert + Fs.FileRead + IO =
        let started = App.startOrBug(app(), "at", Map#{"x" => "14", "z" => "22", "yaw" => "90"});
        Assert.assertEq(expected = Some((14.0, 22.0)), Resources.read((_, w) -> TestSupport.walkerIn(w) |> Option.map(b -> (b#x, b#z)), started))

    /// 数でない座標は組まずに理由を返す。
    @Test
    def testAtRefusesANonNumber(): Unit \ Assert + Fs.FileRead + IO =
        Assert.assertEq(expected = Err("始まり 'at': x は数（'left'）"),
            App.buildStart(app(), Vec2.zero(), "at", Map#{"x" => "left"}) |> Result.map(Resources.read((_, w) -> TestSupport.walkerIn(w) |> Option.map(b -> b#x))))

    /// ギャラリーの場面は全部、実機と同じ App から shot:<名前> の始まりで組める。
    @Test
    def testEveryShotBuildsFromTheApp(): Unit \ Assert + Fs.FileRead + IO =
        let a = app();
        Assert.assertEq(expected = Nil,
            Shots.names() |> List.filter(name -> Result.isErr(App.buildStart(a, Vec2.zero(), App.shotStartName(name), Map.empty()))))

    /// 起動の既定（先頭の title）はタイトルの画面。
    @Test
    def testTitleStartsOnTheTitleScreen(): Unit \ Assert + Fs.FileRead + IO =
        Assert.assertEq(expected = true, Resources.read((_, w) -> World.isOnTitle(w), App.startOrBug(app(), "title", Map.empty())))
}
