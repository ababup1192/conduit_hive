// 始まりの登録簿（Starts.all を App.startOrBug / App.buildStart で引く）と、引数との橋渡し。
mod TestStarts {
    use fge::{App, Resources, Vec2}

    def app(): App.App[Resources.With[Res.Res, World.World], {}] \ Fs.FileRead = Game.app(Controls.loadDocs())

    /// at は体を x・z に置く（start の部屋 A の中の点）。
    @Test
    def testAtPlacesTheBody(): Unit \ Assert + Fs.FileRead =
        let started = App.startOrBug(app(), "at", Map#{"x" => "14", "z" => "22", "yaw" => "90"});
        Assert.assertEq(expected = (14.0, 22.0), Resources.read((_, w) -> (World.walkerOf(w)#x, World.walkerOf(w)#z), started))

    /// 数でない座標は組まずに理由を返す。
    @Test
    def testAtRefusesANonNumber(): Unit \ Assert + Fs.FileRead =
        Assert.assertEq(expected = Err("始まり 'at': x は数（'left'）"),
            App.buildStart(app(), Vec2.zero(), "at", Map#{"x" => "left"}) |> Result.map(Resources.read((_, w) -> World.walkerOf(w)#x)))

    /// ギャラリーの場面は全部、実機と同じ App から shot:<名前> の始まりで組める。
    @Test
    def testEveryShotBuildsFromTheApp(): Unit \ Assert + Fs.FileRead =
        let a = app();
        Assert.assertEq(expected = Nil,
            Shots.names() |> List.filter(name -> Result.isErr(App.buildStart(a, Vec2.zero(), App.shotStartName(name), Map.empty()))))
}
