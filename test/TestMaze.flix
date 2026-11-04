// 迷路の Doc → マス目・区画・隣り合い・見える区画の組（Maze.build）。
mod TestMaze {
    use TestSupport.mazeOf

    // ========================================================================
    // マス目と区画
    // ========================================================================

    /// 1 行の通路 A A b C: 区画ごとのマスの数と、マス目の大きさ。
    @Test
    def testZonesCountTheirCells(): Unit \ Assert =
        let m = Maze.build(100.0, mazeOf("######" :: "#AAbC#" :: "######" :: Nil, 1, 1, 0.0));
        Assert.assertEq(expected = (6, 3, Map#{'A' => 2, 'C' => 1, 'b' => 1}),
            (m#cols, m#rows, m#zones |> Map.map(z -> List.length(z#cells))))

    /// start の印のマス（列 1・行 1）の真ん中に立つ: x = 1.5 × 4・z = (3 − 1 − 0.5) × 4（上の行が北）。
    @Test
    def testStartIsAtTheMarkedCell(): Unit \ Assert =
        let m = Maze.build(100.0, mazeOf("######" :: "#AAbC#" :: "######" :: Nil, 1, 1, 90.0));
        Assert.assertEq(expected = (6.0, 6.0, 90.0, Some('A')), (m#start#x, m#start#z, m#start#yaw, Maze.zoneAt(m, m#start#x, m#start#z)))

    /// 違う区画のマスが辺で接していれば隣（b は A と C の両方の隣・A と C は隣ではない）。
    @Test
    def testNeighborsShareAnEdge(): Unit \ Assert =
        let m = Maze.build(100.0, mazeOf("######" :: "#AAbC#" :: "######" :: Nil, 1, 1, 0.0));
        Assert.assertEq(expected = (Set#{'b'}, Set#{'A', 'C'}, Set#{'b'}),
            (Maze.neighborsOfZone(m, 'A'), Maze.neighborsOfZone(m, 'b'), Maze.neighborsOfZone(m, 'C')))

    /// 本物の迷路の Doc: zones の行の区画が全部マス目にあり、最後の部屋は部屋。
    @Test
    def testRealMazeHasEveryZoneOfTheDoc(): Unit \ {Assert, Fs.FileRead} =
        let doc = MazeDoc.load(MazeDoc.path());
        let m = Maze.build(LookDoc.rec(LookDoc.defaults())#fogFar, doc);
        Assert.assertEq(expected = (List.length(MazeDoc.rec(doc)#zones), Some(MazeDoc.ZoneKind.Room)),
            (Map.size(m#zones), Map.get(MazeDoc.rec(doc)#finalZone, m#zones) |> Option.map(z -> z#kind)))

    // ========================================================================
    // 見える区画の組
    // ========================================================================

    /// 1 マスずつの区画が真っすぐ 7 つ並んだ通路: 見通しの内なら、隣を 2 段たどった先（d・e・f・G）も見える。
    @Test
    def testStraightCorridorSeesPastTwoSteps(): Unit \ Assert =
        let m = Maze.build(100.0, mazeOf("#########" :: "#AbcdefG#" :: "#########" :: Nil, 1, 1, 0.0));
        Assert.assertEq(expected = Set#{'A', 'b', 'c', 'd', 'e', 'f', 'G'}, Maze.visibleOf(m, 'A'))

    /// 見える距離 8 m（2 マス）の内しか見通さない: 同じ通路で、2 段たどった c までになる。
    @Test
    def testSightStopsAtTheViewDistance(): Unit \ Assert =
        let m = Maze.build(8.0, mazeOf("#########" :: "#AbcdefG#" :: "#########" :: Nil, 1, 1, 0.0));
        Assert.assertEq(expected = Set#{'A', 'b', 'c'}, Maze.visibleOf(m, 'A'))

    ///   #######
    ///   #Abc###     A から曲がり角の先（3 段目の d・その先の e F G）は、
    ///   ###d###     壁の角に遮られて見えない。
    ///   ###eFG#
    ///   #######
    @Test
    def testCornerBlocksSight(): Unit \ Assert =
        let m = Maze.build(100.0, mazeOf("#######" :: "#Abc###" :: "###d###" :: "###eFG#" :: "#######" :: Nil, 1, 1, 0.0));
        Assert.assertEq(expected = Set#{'A', 'b', 'c'}, Maze.visibleOf(m, 'A'))

    /// 本物の迷路の東の長い通路: 南の角 k から、3 段先の n（霧の内の真っすぐ先）は見え、西の端の G は見えない。
    @Test
    def testRealEastCorridorSeesItsFarEnd(): Unit \ {Assert, Fs.FileRead} =
        let m = Maze.build(LookDoc.rec(LookDoc.defaults())#fogFar, MazeDoc.load(MazeDoc.path()));
        Assert.assertEq(expected = (true, false), (Set.memberOf('n', Maze.visibleOf(m, 'k')), Set.memberOf('G', Maze.visibleOf(m, 'k'))))

    /// 床の外（壁のマス）に立つ時は、全部の区画を描く。
    @Test
    def testOffTheFloorDrawsEveryZone(): Unit \ Assert =
        let m = Maze.build(100.0, mazeOf("######" :: "#AAbC#" :: "######" :: Nil, 1, 1, 0.0));
        Assert.assertEq(expected = Set#{'A', 'b', 'C'}, Maze.visibleFrom(m, 2.0, 2.0))
}
