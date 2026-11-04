// JSON 橋渡しのテスト（1 Doc につき最大 3 本まで。同型の重複は書かない）。
mod TestDocs {
    use fge::{GameEngine, LogCapture}

    @Test
    def testMazeBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(MazeDoc.fromJson("{ broken")))

    /// 印の種類の綴りが引けない行は置かず、1 行知らせる（start の行は残る）。
    @Test
    def testMazeDropsAnUnknownMarkKind(): Unit \ {Assert, IO} =
        let (doc, lines) = LogCapture.capture(() ->
            MazeDoc.fromJson("{\"rows\":[\"###\",\"#A#\",\"###\"],\"marks\":[{\"kind\":\"start\",\"x\":1,\"y\":1},{\"kind\":\"spawnn\",\"x\":1,\"y\":1}]}"));
        Assert.assertEq(expected = (Some(1), 1), (doc |> Option.map(d -> List.length(MazeDoc.rec(d)#marks)), List.length(lines)))

    /// zones の行の無い区画の高さは wallHeight（1 欄だけ上書きした値が入る）。
    @Test
    def testMazeWallHeightFillsMissingZones(): Unit \ Assert =
        Assert.assertEq(expected = Some(Some(7.0)),
            MazeDoc.fromJson("{\"wallHeight\":7.0,\"rows\":[\"###\",\"#A#\",\"###\"]}")
                |> Option.map(d -> Maze.build(10.0, d)#zones |> Map.get('A') |> Option.map(z -> z#height)))

    @Test
    def testWalkOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((9.0, WalkDoc.rec(WalkDoc.defaults())#walkSpeed)),
            WalkDoc.fromJson("{\"version\":1, \"runSpeed\": 9.0}") |> Option.map(d -> (WalkDoc.rec(d)#runSpeed, WalkDoc.rec(d)#walkSpeed)))

    @Test
    def testLookOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some(30.0), LookDoc.fromJson("{\"fogFar\": 30.0}") |> Option.map(d -> LookDoc.rec(d)#fogFar))

    @Test
    def testLookBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(LookDoc.fromJson("{oops")))

    @Test
    def testKeysBrokenFallsBack(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(KeysDoc.fromJson("{oops")))

    /// 書き間違い("Sinistra")はその 1 個だけ落ちる。全部知らない名前で空になった操作(sprint)だけ既定へ落ちる。
    @Test
    def testKeysDropsUnknownNameAndEmptyActionFallsBack(): Unit \ Assert =
        Assert.assertEq(
            expected = Some((GameEngine.Key.Q :: Nil, KeysDoc.rec(KeysDoc.defaults())#sprint)),
            KeysDoc.fromJson("{\"left\": [\"Q\", \"Sinistra\"], \"sprint\": [\"Hop\"]}")
                |> Option.map(d -> (KeysDoc.rec(d)#left, KeysDoc.rec(d)#sprint)))

    @Test
    def testSampleBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(SampleDoc.fromJson("{ broken")))
}
