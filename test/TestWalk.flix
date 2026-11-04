// 歩く規則: 速さは Doc から・壁の当たりを抜けない。
mod TestWalk {
    use TestSupport.{clockOf, eastRoom, resWith}

    def ahead(sprint: Bool): Walker.Drive = { forward = 1.0, sprint = sprint | Walker.idle() }

    /// 1/60 秒を 60 コマ（1 秒）前へ歩くと、Doc の walkSpeed だけ進む（start は x = 6 m の東向き・東の壁は x = 16 m で届かない）。
    @Test
    def testWalksAtTheDocSpeed(): Unit \ Assert =
        let res = resWith(eastRoom());
        let walk = WalkDoc.rec(res#walk);
        let start = World.walkerOf(World.initial(res));
        let after = Walker.simulate(res#collision, walk, ahead(false), clockOf(1.0 / 60.0), 60, start);
        Assert.assertTrue(Float64.abs(after#x - (start#x + walk#walkSpeed)) < 0.01)

    /// 東の壁（x = 16 m）へ 3 秒走り続けても、体の真ん中は壁から半径より内に入らず、壁に食い込まない（食い込みは 1 mm 未満）。
    @Test
    def testRunningIntoAWallStopsAtTheRadius(): Unit \ Assert =
        let res = resWith(eastRoom());
        let walk = WalkDoc.rec(res#walk);
        let after = Walker.simulate(res#collision, walk, ahead(true), clockOf(1.0 / 60.0), 180, World.walkerOf(World.initial(res)));
        Assert.assertEq(expected = (true, true, true),
            (after#x <= 16.0 - walk#radius + 0.001, after#x > 16.0 - walk#radius - 0.05, Walker.overlapDepth(res#collision, walk, after) < 0.001))

    /// 北を向いて 2 秒歩いても、幅 1 マスの部屋の北の壁（z = 8 m）で止まる。
    @Test
    def testSideWallStopsTheBody(): Unit \ Assert =
        let res = resWith(eastRoom());
        let walk = WalkDoc.rec(res#walk);
        let facingNorth = { yaw = 0.0 | World.walkerOf(World.initial(res)) };
        let after = Walker.simulate(res#collision, walk, ahead(false), clockOf(1.0 / 60.0), 120, facingNorth);
        Assert.assertTrue(after#z <= 8.0 - walk#radius + 0.001)
}
