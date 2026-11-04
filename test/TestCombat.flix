// 遊びの 1 コマを通した戦いの規則（World.step・Game.app）: 倒れてやり直す・部屋の入り直し・起きた事と音・連射の間隔。
mod TestCombat {
    use fge::{App, GameEngine, Num, Resources}
    use Creatures.Kind
    use TestSupport.{checkpointIn, clockAt, docsWith, eventsIn, healthIn, hordeIn, resWith, walkerIn}

    // ── 迷路と道具 ──

    /// 部屋 A（x 4〜16 m）・通路 a（x 16〜20 m の上の行）・部屋 B（x 20〜32 m）。行 1 の z は 8〜12 m・行 2 は 4〜8 m。
    /// start は A の西の端（x 6 m・z 10 m）で東を向く。B には spawn の印が 1 つ（列 7・行 2）。
    def twoRoomMaze(): MazeDoc.Doc =
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'B',
                          rows = "#########" :: "#AAAaBBB#" :: "#AAA#BBB#" :: "#########" :: Nil,
                          zones = { id = 'A', name = "west", kind = MazeDoc.ZoneKind.Room, height = 4.0 }
                                  :: { id = 'B', name = "east", kind = MazeDoc.ZoneKind.Room, height = 4.0 }
                                  :: { id = 'a', name = "A-B", kind = MazeDoc.ZoneKind.Corridor, height = 4.0 } :: Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = 1, row = 1, yaw = 90.0 }
                                  :: { kind = MazeDoc.MarkKind.Spawn, name = "spawn", col = 7, row = 2, yaw = 0.0 } :: Nil })

    def enemies(): EnemiesDoc.Rec = EnemiesDoc.rec(EnemiesDoc.defaults())

    def player(): PlayerDoc.Rec = PlayerDoc.rec(PlayerDoc.defaults())

    /// 体力 5 の描く元（melee の 1 撃で倒れる）。部屋 B に入るとすぐ melee 3 体の wave が 1 つ始まる。
    /// 部屋が 12 m 四方と狭いので、近い印からも湧かせる（minDistance 0）。
    def fragileRes(): Res.Res =
        let base = resWith(twoRoomMaze());
        let bWave = { zone = 'B', melee = 3, ranged = 0, source = None, after = 0.0, whenLeft = 0 };
        Res.withSpawns(SpawnsDoc.Doc.Doc({ minDistance = 0.0, waves = bWave :: Nil | SpawnsDoc.rec(base#spawns) }),
                       { player = PlayerDoc.Doc.Doc({ health = 5.0 | player() }) | base })

    def idle(): World.Input = World.walking(Walker.idle())

    def at(t: Float64, dt: Float64, w: World.World): World.World = { play = clockAt(t, dt) | w }

    /// 群れに melee を 1 体（足元 x・z・向き yaw・湧いた部屋 home）足す。
    def withMelee(r: Res.Res, x: Float64, z: Float64, yaw: Float64, home: Char, w: World.World): World.World =
        World.mapHorde(Horde.spawnNow(r, { kind = Kind.Melee, x = x, z = z, yaw = yaw, home = home } :: Nil), w)

    /// 倒れてやり直すまで: 部屋 A に入ったコマに 1 m 前（x 7 m）の melee が振り始め、hitTime のコマの 1 撃で倒れ、
    /// respawnSeconds の後のコマにやり直し、その次のコマに部屋 A へ入り直す。並びは（倒れたコマ, やり直したコマ, 入り直したコマ）。
    def deathRun(): (World.World, World.World, World.World) =
        let r = fragileRes();
        let hit = enemies()#melee#hitTime;
        let w0 = withMelee(r, 7.0, 10.0, Num.pi() * 1.5, 'A', World.initial(r));
        let swung = World.step(r, idle(), at(0.125, 0.125, w0));
        let down = World.step(r, idle(), at(0.125 + hit, 0.05, swung));
        let back = World.step(r, idle(), at(0.125 + hit + player()#respawnSeconds, 0.05, down));
        let again = World.step(r, idle(), at(0.175 + hit + player()#respawnSeconds, 0.05, back));
        (down, back, again)

    // ── 倒れてやり直す ──

    /// 体力より強い 1 撃で倒れる。
    @Test
    def testLethalHitDownsThePlayer(): Unit \ Assert =
        let (down, _, _) = deathRun();
        Assert.assertEq(expected = Some(true), healthIn(down) |> Option.map(Health.isDown))

    /// respawnSeconds の後に体力を満たして立つ。
    @Test
    def testRespawnRefillsHealth(): Unit \ Assert =
        let (_, back, _) = deathRun();
        Assert.assertEq(expected = Some(5.0), healthIn(back) |> Option.map(h -> h#points))

    /// やり直す所は最後に入った部屋の入口（start の x 6 m・z 10 m）。
    @Test
    def testRespawnStandsAtTheRoomEntrance(): Unit \ Assert =
        let (_, back, _) = deathRun();
        Assert.assertEq(expected = Some((6.0, 10.0)), walkerIn(back) |> Option.map(b -> (b#x, b#z)))

    /// やり直したコマには敵がいない。
    @Test
    def testRespawnClearsTheEnemies(): Unit \ Assert =
        let (_, back, _) = deathRun();
        Assert.assertEq(expected = Some(0), hordeIn(back) |> Option.map(Horde.aliveCount))

    /// やり直した次のコマに部屋 A へ入り直し、A がもう一度湧かせられる部屋に戻っている（湧かせ終えた印が付き直す）。
    @Test
    def testRespawnRearmsTheRoom(): Unit \ Assert =
        let (_, back, again) = deathRun();
        Assert.assertEq(expected = (Some(false), Some(true)),
            (hordeIn(back) |> Option.map(Horde.isTriggered('A')), hordeIn(again) |> Option.map(Horde.isTriggered('A'))))

    /// 部屋 A で湧いた敵が残ったまま部屋 B へ移り、B で倒れると、やり直した時に A も B ももう一度湧かせられる部屋に戻る。
    @Test
    def testDeathRearmsOtherRoomsWithSurvivors(): Unit \ Assert =
        let r = fragileRes();
        let hit = enemies()#melee#hitTime;
        let inA = World.step(r, idle(), at(0.05, 0.05, World.initial(r)));
        let inB = World.step(r, idle(), at(0.1, 0.05, World.placeWalker(r, { x = 22.0, z = 10.0 }, 90.0, 0.0, withMelee(r, 9.0, 10.0, 0.0, 'A', inA))));
        let swung = World.step(r, idle(), at(0.15, 0.05, withMelee(r, 23.0, 10.0, Num.pi() * 1.5, 'B', inB)));
        let down = World.step(r, idle(), at(0.15 + hit, 0.05, swung));
        let back = World.step(r, idle(), at(0.15 + hit + player()#respawnSeconds, 0.05, down));
        Assert.assertEq(expected = Some((false, false)), hordeIn(back) |> Option.map(h -> (Horde.isTriggered('A', h), Horde.isTriggered('B', h))))

    /// 部屋 A（wave 無し）を終えて部屋 B に入り、B の wave を 1 つ始めた所で倒れると、やり直した時に B は最初の wave の前に戻り、
    /// 入る前に終えていた A は終えたまま（並びは 倒れたコマの B の wave の数・やり直したコマの B の wave の数・A に入ったままか）。
    @Test
    def testRespawnRestartsTheRoomWaves(): Unit \ Assert =
        let r = fragileRes();
        let hit = enemies()#melee#hitTime;
        let inA = World.step(r, idle(), at(0.05, 0.05, World.initial(r)));
        let inB = World.step(r, idle(), at(0.1, 0.05, World.placeWalker(r, { x = 22.0, z = 10.0 }, 90.0, 0.0, inA)));
        let swung = World.step(r, idle(), at(0.15, 0.05, withMelee(r, 23.0, 10.0, Num.pi() * 1.5, 'B', inB)));
        let down = World.step(r, idle(), at(0.15 + hit, 0.05, swung));
        let back = World.step(r, idle(), at(0.15 + hit + player()#respawnSeconds, 0.05, down));
        Assert.assertEq(expected = (Some(1), Some((0, true))),
            (hordeIn(down) |> Option.map(Horde.wavesStarted('B')), hordeIn(back) |> Option.map(h -> (Horde.wavesStarted('B', h), Horde.isTriggered('A', h)))))

    // ── 部屋の入り直し ──

    /// 部屋 A → 通路 a → 部屋 A と戻っても、やり直す所は最初に A へ入った所（x 6 m）のまま（同じ部屋なら書き換えない）。
    @Test
    def testReenteringTheSameRoomKeepsTheCheckpoint(): Unit \ Assert =
        let r = resWith(twoRoomMaze());
        let inA = World.step(r, idle(), at(0.05, 0.05, World.initial(r)));
        let inCorridor = World.step(r, idle(), at(0.1, 0.05, World.placeWalker(r, { x = 18.0, z = 10.0 }, 90.0, 0.0, inA)));
        let backInA = World.step(r, idle(), at(0.15, 0.05, World.placeWalker(r, { x = 14.0, z = 6.0 }, 270.0, 0.0, inCorridor)));
        Assert.assertEq(expected = Some(6.0), checkpointIn(backInA) |> Option.map(c -> c#x))

    /// 部屋 B に入るとやり直す所は B の入口（入ったコマの足元 x 22 m）に替わる。
    @Test
    def testEnteringANewRoomMovesTheCheckpoint(): Unit \ Assert =
        let r = resWith(twoRoomMaze());
        let inA = World.step(r, idle(), at(0.05, 0.05, World.initial(r)));
        let inB = World.step(r, idle(), at(0.1, 0.05, World.placeWalker(r, { x = 22.0, z = 10.0 }, 90.0, 0.0, inA)));
        Assert.assertEq(expected = Some((22.0, Some('B'))), checkpointIn(inB) |> Option.map(c -> (c#x, c#zone)))

    // ── 起きた事と音 ──

    /// 部屋 A に入ったコマに、体力が拳銃の威力と同じ melee を 1 発で倒す: 部屋が湧き始めた・撃った・体に当たった・倒れた、の順に起きる。
    @Test
    def testLethalShotReportsFiredHitAndDown(): Unit \ Assert =
        let pistol = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Pistol, WeaponsDoc.defaults());
        let base = resWith(twoRoomMaze());
        let r = { enemies = EnemiesDoc.Doc.Doc({ melee = { health = pistol#damage | enemies()#melee } | enemies() }) | base };
        let aimed = withMelee(r, 12.0, 10.0, Num.pi() * 1.5, 'A', World.initial(r));
        let shot = World.step(r, { trigger = { pressed = true, held = true } | idle() }, at(0.05, 0.05, aimed));
        Assert.assertEq(expected = Some(Events.Event.RoomTriggered('A') :: Events.Event.Fired(WeaponsDoc.Weapon.Pistol)
                                        :: Events.Event.EnemyHit(Kind.Melee, Hitscan.Part.Body) :: Events.Event.EnemyDown(Kind.Melee, Events.Death.Fell) :: Nil),
            eventsIn(shot))

    /// 部屋に入ったコマに撃つと、扉の音と、拳銃の 1 つ目の変化の音が鳴る（最初の 1 発は撃った回数 0 番）。
    @Test
    def testFiringSoundsTheShot(): Unit \ Assert =
        let r = resWith(twoRoomMaze());
        let start = at(0.05, 0.05, World.initial(r));
        let shot = World.step(r, { trigger = { pressed = true, held = true } | idle() }, start);
        Assert.assertEq(expected = "door" :: Sounds.variantOf(SoundsDoc.rec(r#sounds), "shot_pistol", 0) :: Nil, Sounds.events(r, start, shot))

    // ── 連射の間隔 ──

    /// 連射銃だけを持つ Doc で、窓にキャプチャして左ボタンを 60 Hz で 1 秒押し続けると、間隔 0.1 秒どおり 10 発撃つ
    /// （撃てる時刻から数えるので、間隔がコマの長さで割り切れなくても遅れない）。
    @Test
    def testRifleFiresAtTheDocRateAt60Hz(): Unit \ Assert =
        let w = WeaponsDoc.rec(WeaponsDoc.defaults());
        let docs = { weapons = WeaponsDoc.Doc.Doc({ pistol = { owned = false | w#pistol }, rifle = { owned = true, ammo = w#rifle#maxAmmo | w#rifle } | w }) | docsWith(twoRoomMaze()) };
        let res = Res.build(docs);
        let held = { dt = 1.0 / 60.0, windowFocused = true, mouseButtons = Set#{GameEngine.MouseButton.Left} | App.emptyFrame() };
        let traced = App.trace(Game.app(docs), List.repeat(60, held), Resources.of(res, World.setLooking(true, World.initial(res))));
        Assert.assertEq(expected = Some(Some(10)),
            List.last(traced) |> Option.map(s -> Resources.read((_, wd) -> TestSupport.arsenalIn(wd) |> Option.map(a -> a#shots), s#after)))

    // ── やり直すと部屋に入った時へ戻る ──

    /// 部屋 A に入ったコマに、前（x 7 m）の melee を拳銃の 1 発で倒し（倒した数 1・撃った数 1）、後ろ（x 5 m）の melee の振り下ろしで倒れる。
    /// やり直すと、倒した数と撃った数は部屋に入った時の 0 へ戻る（湧き直す群れを二重に数えない）。並びは（倒れたコマ, やり直したコマ）の（倒した数, 撃った数）。
    @Test
    def testRespawnRestoresKillsAndAmmoOfTheRoomEntry(): Unit \ Assert =
        let pistol = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Pistol, WeaponsDoc.defaults());
        let base = fragileRes();
        let r = { enemies = EnemiesDoc.Doc.Doc({ melee = { health = pistol#damage | enemies()#melee } | enemies() }) | base };
        let hit = enemies()#melee#hitTime;
        let w0 = withMelee(r, 5.0, 10.0, Num.pi() * 0.5, 'A', withMelee(r, 7.0, 10.0, Num.pi() * 1.5, 'A', World.initial(r)));
        let shot = World.step(r, { trigger = { pressed = true, held = true } | idle() }, at(0.05, 0.05, w0));
        let down = World.step(r, idle(), at(0.05 + hit, 0.05, shot));
        let back = World.step(r, idle(), at(0.1 + hit + player()#respawnSeconds, 0.05, down));
        let tally = (w: World.World) -> World.sessionOf(w) |> Option.map(s -> (World.killsOf(s), World.arsenalOf(s)#shots));
        Assert.assertEq(expected = (Some((1, 1)), Some((0, 0))), (tally(down), tally(back)))

    // ── 弾が尽きるまで押し続ける ──

    /// 連射銃（弾 2 発）と拳銃を持ち、連射銃を構えて 60 Hz で 1 秒押し続けると、2 発撃った後に空撃ちして拳銃へ替わり、
    /// 押したままの拳銃では撃たない（拳銃は押すたびに 1 回）。並びは（撃った数の合計, 構えている武器）。
    @Test
    def testHeldRifleRunsDryThenSwitchesWithoutFiringThePistol(): Unit \ Assert =
        let w = WeaponsDoc.rec(WeaponsDoc.defaults());
        let docs = { weapons = WeaponsDoc.Doc.Doc({ rifle = { owned = true, ammo = 2 | w#rifle } | w }) | docsWith(twoRoomMaze()) };
        let res = Res.build(docs);
        let held = { dt = 1.0 / 60.0, windowFocused = true, mouseButtons = Set#{GameEngine.MouseButton.Left} | App.emptyFrame() };
        let start = World.step(res, { choice = Arsenal.Choice.Slot(WeaponsDoc.Weapon.Rifle) | idle() }, World.setLooking(true, World.initial(res)));
        let traced = App.trace(Game.app(docs), List.repeat(60, held), Resources.of(res, start));
        Assert.assertEq(expected = Some(Some((2, WeaponsDoc.Weapon.Pistol))),
            List.last(traced) |> Option.map(s -> Resources.read((_, wd) -> TestSupport.arsenalIn(wd) |> Option.map(a -> (a#shots, a#current)), s#after)))
}
