// 拾う規則（Pickups・Arsenal・Health と World.step）: 印から置く・満タンなら拾わない・武器が加わり持ち替わる・
// 弾倉で弾が増えて上限で止まる・弾が 0 の時の空撃ちと自動の持ち替え・拾った物は消える。
mod TestPickups {
    use fge::LogCapture
    use Events.Event
    use Pickups.Kind
    use TestSupport.{arsenalIn, clockAt, eventsIn, mazeOf, resWith}
    use WeaponsDoc.Weapon

    // ── 迷路と道具 ──

    def pickupMark(name: String, col: Int32): MazeDoc.Mark = { kind = MazeDoc.MarkKind.Pickup, name = name, col = col, row = 1, yaw = 0.0 }

    /// 東西に長い 5 マスの通路（x 4〜24 m・z 4〜8 m。区画の行は無いので部屋は無い）。start は西の端（x 6 m・z 6 m）で東を向く。
    /// 回復（小）を x 10 m・散弾銃を x 14 m・散弾銃の弾倉を x 18 m に置き、extra の印を足す。
    def laneWith(extra: List[MazeDoc.Mark]): MazeDoc.Doc =
        let base = MazeDoc.rec(mazeOf("#######" :: "#AAAAA#" :: "#######" :: Nil, 1, 1, 90.0));
        MazeDoc.Doc.Doc({ marks = List.flatten(base#marks :: (pickupMark("health_small", 2) :: pickupMark("weapon_shotgun", 3) :: pickupMark("ammo_shotgun", 4) :: Nil) :: extra :: Nil) | base })

    def res(): Res.Res = resWith(laneWith(Nil))

    def weapons(): WeaponsDoc.Doc = WeaponsDoc.defaults()

    def shotgun(): WeaponsDoc.Stats = WeaponsDoc.statsOf(Weapon.Shotgun, weapons())

    def player(): PlayerDoc.Rec = PlayerDoc.rec(PlayerDoc.defaults())

    def vm(): FpViewmodelDoc.Rec = FpViewmodelDoc.rec(FpViewmodelDoc.defaults())

    /// Doc の種類の名前の量。
    def amountOf(name: String): Option[Int32] = Map.get(name, PickupsDoc.rec(PickupsDoc.defaults())#amounts)

    def rules(): Pickups.Rules = { t = 1.0, weapons = weapons(), viewmodel = vm(), player = player() }

    /// 置いた物のうち種類 k の物。
    def pointOf(k: Kind): Option[Pickups.Point] = res()#pickupPoints |> List.find(p -> p#kind == k)

    /// 通路の x（z 6 m）に立って、時刻 t（刻み 0.05 秒）に 1 コマ進めた World。
    def standAt(r: Res.Res, x: Float64, t: Float64, w: World.World): World.World =
        World.step(r, World.walking(Walker.idle()), { play = clockAt(t, 0.05) | World.placeWalker(r, { x = x, z = 6.0 }, 90.0, 0.0, w) })

    // ── 印から置く ──

    /// 散弾銃の印は x 14 m・z 6 m（列 3 のマスの真ん中）に、Doc の weapon_shotgun の量で置く。
    @Test
    def testMarkPlacesTheDocAmount(): Unit \ Assert =
        Assert.assertEq(expected = amountOf("weapon_shotgun") |> Option.map(n -> (14.0, 6.0, n)),
            pointOf(Kind.WeaponShotgun) |> Option.map(p -> (p#x, p#z, p#amount)))

    /// pickups.json に無い名前の印は 1 行知らせて置かない（ほかの 3 つは残る）。
    @Test
    def testUnknownPickupNameIsReportedAndDropped(): Unit \ {Assert, IO} =
        let (r, lines) = LogCapture.capture(() -> resWith(laneWith(pickupMark("medkit", 5) :: Nil)));
        Assert.assertEq(expected = (1, 3), (List.length(lines), List.length(r#pickupPoints)))

    // ── 回復 ──

    /// 10 減った体力に回復（小）を拾うと、体力の最大で止まる（25 足しても最大を超えない）。
    @Test
    def testHealthTopsUpToTheMax(): Unit \ Assert =
        let hurt = Health.hurt(0.0, 10.0, Health.full(player()));
        let carry = { arsenal = Arsenal.initial(weapons()), health = hurt };
        Assert.assertEq(expected = Some(player()#health),
            pointOf(Kind.HealthSmall) |> Option.flatMap(p -> Pickups.take(rules(), p, carry)) |> Option.map(c -> c#health#points))

    /// 体力が満タンの時は回復の上に立っても拾わない（置いたまま）。
    @Test
    def testFullHealthLeavesTheKit(): Unit \ Assert =
        let r = res();
        Assert.assertEq(expected = Some(Set.empty()), World.sessionOf(standAt(r, 10.0, 0.05, World.initial(r))) |> Option.map(World.takenOf))

    // ── 武器 ──

    /// 散弾銃の上に立つと、持っている武器に加わってその場で持ち替え、弾は始めの弾に Doc の量を足した数になる。
    @Test
    def testWeaponPickupArmsAndSwitches(): Unit \ Assert =
        let r = res();
        Assert.assertEq(expected = amountOf("weapon_shotgun") |> Option.map(n -> (Weapon.Shotgun, true, Some(shotgun()#ammo + n))),
            arsenalIn(standAt(r, 14.0, 0.05, World.initial(r))) |> Option.map(a -> (a#current, Set.memberOf(Weapon.Shotgun, a#owned), Arsenal.ammoOf(weapons(), a))))

    /// 武器を拾ったコマに起きた事: 拾った・持ち替えた の順。
    @Test
    def testWeaponPickupReportsPickedAndSwitched(): Unit \ Assert =
        let r = res();
        Assert.assertEq(expected = Some(Event.PickedUp(Kind.WeaponShotgun) :: Event.Switched(Weapon.Shotgun) :: Nil),
            eventsIn(standAt(r, 14.0, 0.05, World.initial(r))))

    /// 拾った物は消える: 同じ所に立ったままの次のコマには何も起きない。
    @Test
    def testTakenPickupIsGone(): Unit \ Assert =
        let r = res();
        let once = standAt(r, 14.0, 0.05, World.initial(r));
        Assert.assertEq(expected = Some(Nil), eventsIn(standAt(r, 14.0, 0.1, once)))

    /// もう持っていて弾が上限の武器は拾わない。
    @Test
    def testOwnedWeaponWithFullAmmoIsLeft(): Unit \ Assert =
        let full = { owned = Set#{Weapon.Pistol, Weapon.Shotgun}, ammo = Map#{Weapon.Pistol => 0, Weapon.Shotgun => shotgun()#maxAmmo, Weapon.Rifle => 0}
                     | Arsenal.initial(weapons()) };
        Assert.assertEq(expected = true, Option.isEmpty(Arsenal.arm(weapons(), vm(), 0.0, Weapon.Shotgun, 12, full)))

    // ── 弾倉 ──

    /// 上限の 3 発手前で弾倉（8 発）を拾うと、上限で止まる。
    @Test
    def testAmmoStopsAtTheMax(): Unit \ Assert =
        let nearlyFull = { ammo = Map#{Weapon.Pistol => 0, Weapon.Shotgun => shotgun()#maxAmmo - 3, Weapon.Rifle => 0} | Arsenal.initial(weapons()) };
        Assert.assertEq(expected = Some(Some(shotgun()#maxAmmo)),
            Arsenal.addAmmo(weapons(), Weapon.Shotgun, 8, nearlyFull) |> Option.map(a -> Map.get(Weapon.Shotgun, a#ammo)))

    /// 弾が上限の時は弾倉を拾わない。
    @Test
    def testFullAmmoLeavesTheBox(): Unit \ Assert =
        let full = { ammo = Map#{Weapon.Pistol => 0, Weapon.Shotgun => shotgun()#maxAmmo, Weapon.Rifle => 0} | Arsenal.initial(weapons()) };
        Assert.assertEq(expected = true, Option.isEmpty(Arsenal.addAmmo(weapons(), Weapon.Shotgun, 8, full)))

    /// 持っていない武器の弾倉も拾え、後で武器を拾えばその弾も使える（弾倉 8 ＋ 散弾銃の量）。
    @Test
    def testAmmoBeforeTheWeaponIsKept(): Unit \ Assert =
        let r = res();
        let boxed = standAt(r, 18.0, 0.05, World.initial(r));
        Assert.assertEq(expected = forM (box <- amountOf("ammo_shotgun"); gun <- amountOf("weapon_shotgun")) yield Some(shotgun()#ammo + box + gun),
            arsenalIn(standAt(r, 14.0, 0.1, boxed)) |> Option.map(a -> Arsenal.ammoOf(weapons(), a)))

    // ── 弾が 0 の時 ──

    /// 散弾銃だけを持ち、弾が 0 の Doc（拳銃は持っていない）。
    def emptyShotgunOnly(): WeaponsDoc.Doc =
        let d = WeaponsDoc.rec(weapons());
        WeaponsDoc.Doc.Doc({ pistol = { owned = false | d#pistol }, shotgun = { owned = true, ammo = 0 | d#shotgun } | d })

    /// 拳銃と、弾が 0 の散弾銃を持つ Doc。
    def emptyShotgunAndPistol(): WeaponsDoc.Doc =
        let d = WeaponsDoc.rec(weapons());
        WeaponsDoc.Doc.Doc({ shotgun = { owned = true, ammo = 0 | d#shotgun } | d })

    /// 弾が 0 の散弾銃に持ち替えてから引き金を引くと、撃たずに空撃ちし、弾のある拳銃へ自動で持ち替える。
    @Test
    def testDryFireSwitchesToALoadedWeapon(): Unit \ Assert =
        let r = { weapons = emptyShotgunAndPistol() | res() };
        let pull = { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) };
        let drawn = World.step(r, { choice = Arsenal.Choice.Slot(Weapon.Shotgun) | World.walking(Walker.idle()) }, { play = clockAt(0.05, 0.05) | World.initial(r) });
        let pulled = World.step(r, pull, { play = clockAt(0.1 + vm()#drawSeconds, 0.05) | drawn });
        Assert.assertEq(expected = Some(Event.DryFire(Weapon.Shotgun) :: Event.Switched(Weapon.Pistol) :: Nil), eventsIn(pulled))

    /// ほかに弾のある武器が無ければ、空撃ちは持ち替えずに散弾銃の間隔だけ待つ（押し続けても空撃ちは間隔ごと）。
    @Test
    def testDryFireWithoutAnotherWeaponOnlyWaits(): Unit \ Assert =
        let a = Arsenal.dryFire(emptyShotgunOnly(), vm(), 1.0, Arsenal.initial(emptyShotgunOnly()));
        Assert.assertEq(expected = (Weapon.Shotgun, 1.0 + shotgun()#interval), (a#current, a#readyAt))

    /// 弾が 0 の時に鳴らす音は空撃ちと持ち替えの 2 つ（撃った音は鳴らさない）。
    @Test
    def testDryFireSoundsClickAndSwitch(): Unit \ Assert =
        let r = { weapons = emptyShotgunAndPistol() | res() };
        let pull = { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) };
        let drawn = World.step(r, { choice = Arsenal.Choice.Slot(Weapon.Shotgun) | World.walking(Walker.idle()) }, { play = clockAt(0.05, 0.05) | World.initial(r) });
        Assert.assertEq(expected = "dryfire" :: "switch" :: Nil, Sounds.events(World.step(r, pull, { play = clockAt(0.1 + vm()#drawSeconds, 0.05) | drawn })))
}
