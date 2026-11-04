// 紹介の動画の自動の操縦（Pilot・World.withPilot）: 向きをなめらかに変える・正面の敵を撃つ・道筋の点へ歩く・倒れない。
mod TestPilot {
    use fge::Num
    use Creatures.Kind
    use TestSupport.{clockAt, eastRoom, healthIn, resWith}

    /// 東西に長い部屋（x 4〜16 m・z 4〜8 m。start は x 6 m・z 6 m で東向き）と、x 14 m・z 6 m の 1 点だけの道筋。
    def tourRes(): Res.Res =
        let base = resWith(eastRoom());
        let tour = TourDoc.rec(TourDoc.defaults());
        { tour = TourDoc.Doc.Doc({ points = { name = "east", x = 14.0, z = 6.0, wait = 10.0, sprint = false, weapon = None, lookYaw = None, clear = false } :: Nil | tour }),
          player = PlayerDoc.Doc.Doc({ health = 5.0 | PlayerDoc.rec(base#player) }) | base }

    def started(r: Res.Res): World.World = World.withPilot(World.initial(r))

    def withMelee(r: Res.Res, x: Float64, z: Float64, w: World.World): World.World =
        World.mapHorde(Horde.spawnNow(r, { kind = Kind.Melee, x = x, z = z, yaw = Num.pi() * 1.5, home = 'A' } :: Nil), w)

    /// 1 コマ（1/60 秒）の自動の操縦の入力。
    def commandIn(r: Res.Res, w: World.World): Option[Pilot.Command] =
        World.sessionOf(w) |> Option.map(s ->
            fst(Pilot.drive(r, { t = 1.0, dt = 1.0 / 60.0, walker = World.walkerOf(s), arsenal = World.arsenalOf(s), horde = World.hordeOf(s),
                                 moves = World.movesOf(s), grenades = World.grenadesOf(s) }, Pilot.start())))

    /// 真後ろの敵へも、1 コマに turnRate の 1/60 より大きくは回さない。
    @Test
    def testTurnsNoFasterThanTheTurnRate(): Unit \ Assert =
        let r = tourRes();
        let turn = commandIn(r, withMelee(r, 4.6, 6.0, started(r))) |> Option.map(c -> Float64.abs(c#drive#turnDeg));
        Assert.assertTrue(turn |> Option.exists(d -> d > 0.0 and d <= 220.0 / 60.0))

    /// 正面の敵には引き金を引く。
    @Test
    def testFiresAtAnEnemyAhead(): Unit \ Assert =
        let r = tourRes();
        let pulled = commandIn(r, withMelee(r, 12.0, 6.0, started(r))) |> Option.map(c -> c#trigger#held);
        Assert.assertEq(expected = Some(true), pulled)

    /// 敵がいなければ道筋の点（東）へ歩く。
    @Test
    def testWalksTowardThePoint(): Unit \ Assert =
        let r = tourRes();
        let forward = commandIn(r, started(r)) |> Option.map(c -> c#drive#forward);
        Assert.assertEq(expected = Some(1.0), forward)

    /// 体力より強い 1 撃を受けても倒れない。
    @Test
    def testHealthStaysAtTheFloor(): Unit \ Assert =
        let r = tourRes();
        let hit = EnemiesDoc.rec(EnemiesDoc.defaults())#melee#hitTime;
        let w0 = withMelee(r, 7.0, 6.0, started(r));
        let swung = World.step(r, World.walking(Walker.idle()), { play = clockAt(0.125, 0.125) | w0 });
        let after = World.step(r, World.walking(Walker.idle()), { play = clockAt(0.125 + hit, 0.05) | swung });
        Assert.assertEq(expected = Some(false), healthIn(after) |> Option.map(Health.isDown))

    /// crowdRange の内に crowdCount 体いれば蹴る（初めは蹴りから。3 体は start の x 6 m・z 6 m から 1.2 m 前後）。
    @Test
    def testKicksWhenCrowded(): Unit \ Assert =
        let r = tourRes();
        let w = started(r) |> withMelee(r, 7.2, 6.0) |> withMelee(r, 7.0, 6.6) |> withMelee(r, 7.0, 5.4);
        Assert.assertEq(expected = Some(true), commandIn(r, w) |> Option.map(c -> Moves.isPressed(Moves.Move.Kick, c#moves)))

    /// 正面 9 m 先に clusterCount 体の塊がいれば手榴弾を投げる（塊は x 15 m のまわり 1 m の内）。
    @Test
    def testThrowsAtAPackAhead(): Unit \ Assert =
        let r = tourRes();
        let w = started(r) |> withMelee(r, 15.0, 6.0) |> withMelee(r, 15.0, 5.2) |> withMelee(r, 15.0, 6.8) |> withMelee(r, 14.4, 6.0);
        Assert.assertEq(expected = Some(true), commandIn(r, w) |> Option.map(c -> Moves.isPressed(Moves.Move.Grenade, c#moves)))
}
