// 画面の流れ（World と Controls）: タイトル → 遊ぶ → クリア → タイトル・Esc のポーズ・クリアの判定・倒した数。
mod TestFlow {
    use fge::{App, Clock, Num}
    use fge::GameEngine.Key
    use Creatures.Kind
    use Events.Event
    use TestSupport.{clockAt, eventsIn, resWith, walkerIn}

    // ── 迷路と道具 ──

    /// 部屋 A（x 4〜16 m）・通路 a（x 16〜20 m の上の行）・最後の部屋 B（x 20〜32 m）。行 1 の z は 8〜12 m・行 2 は 4〜8 m。
    /// start は A の西の端（x 6 m・z 10 m）で東を向く。spawn の印は無い（B は入った時から空）。
    def twoRooms(): MazeDoc.Doc =
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'B',
                          rows = "#########" :: "#AAAaBBB#" :: "#AAA#BBB#" :: "#########" :: Nil,
                          zones = { id = 'A', name = "west", kind = MazeDoc.ZoneKind.Room, height = 4.0 }
                                  :: { id = 'B', name = "east", kind = MazeDoc.ZoneKind.Room, height = 4.0 } :: Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = 1, row = 1, yaw = 90.0 } :: Nil })

    def res(): Res.Res = resWith(twoRooms())

    def player(): PlayerDoc.Rec = PlayerDoc.rec(PlayerDoc.defaults())

    def pressing(k: Key): App.Frame = { justPressed = Set#{k}, down = Set#{k} | App.emptyFrame() }

    def idle(): World.Input = World.walking(Walker.idle())

    def at(t: Float64, w: World.World): World.World = { play = clockAt(t, 0.05) | w }

    /// 最後の部屋 B の真ん中（x 26 m・z 10 m）に立たせた World。
    def inFinalRoom(w: World.World): World.World = World.placeWalker(res(), { x = 26.0, z = 10.0 }, 90.0, 0.0, w)

    // ── タイトル ──

    /// タイトルで Enter を押すと遊び始め、マウスをキャプチャする。
    @Test
    def testEnterOnTitleStartsPlaying(): Unit \ Assert =
        let started = Controls.step(pressing(Key.Enter), res(), World.title());
        Assert.assertEq(expected = (true, true), (Option.nonEmpty(World.sessionOf(started)), World.isLooking(started)))

    /// タイトルの画面を押しても遊び始める。
    @Test
    def testClickOnTitleStartsPlaying(): Unit \ Assert =
        let clicked = { mouseClicked = true, cursor = { x = 20.0, y = 20.0 } | App.emptyFrame() };
        Assert.assertEq(expected = false, World.isOnTitle(Controls.step(clicked, res(), World.title())))

    // ── ポーズ ──

    /// ポーズの間は前へ押しても歩かない。
    @Test
    def testPauseHoldsTheBody(): Unit \ Assert =
        let paused = World.pause(World.initial(res()));
        let after = World.step(res(), World.walking({ forward = 1.0 | Walker.idle() }), at(0.05, paused));
        Assert.assertEq(expected = walkerIn(paused) |> Option.map(b -> b#x), walkerIn(after) |> Option.map(b -> b#x))

    /// ポーズで Esc を押すと遊びへ戻り、マウスをキャプチャし直す。
    @Test
    def testEscapeInPauseResumes(): Unit \ Assert =
        let resumed = Controls.step(pressing(Key.Escape), res(), World.pause(World.initial(res())));
        Assert.assertEq(expected = (false, true), (World.isPaused(resumed), World.isLooking(resumed)))

    /// ポーズで下へ 1 つ動かして Enter を押すと、タイトルへ戻る。
    @Test
    def testPauseMenuGoesToTitle(): Unit \ Assert =
        let picked = Controls.step(pressing(Key.S), res(), World.pause(World.initial(res())));
        Assert.assertEq(expected = true, World.isOnTitle(Controls.step(pressing(Key.Enter), res(), picked)))

    // ── クリア ──

    /// 空の最後の部屋に入ったコマに、部屋が湧き始めて（湧く物は無い）すぐにクリアになる。
    @Test
    def testEnteringAnEmptyFinalRoomClears(): Unit \ Assert =
        Assert.assertEq(expected = Some(Event.RoomTriggered('B') :: Event.Cleared :: Nil),
            eventsIn(World.step(res(), idle(), at(0.05, inFinalRoom(World.initial(res()))))))

    /// 最後の部屋で湧いた敵が 1 体でも立っている間はクリアにならない。
    @Test
    def testLivingFinalRoomEnemyHoldsTheClear(): Unit \ Assert =
        let guarded = World.mapHorde(Horde.spawnNow(res(), { kind = Kind.Melee, x = 30.0, z = 6.0, yaw = 0.0, home = 'B' } :: Nil), inFinalRoom(World.initial(res())));
        Assert.assertEq(expected = Some(Event.RoomTriggered('B') :: Nil), eventsIn(World.step(res(), idle(), at(0.05, guarded))))

    /// クリアしてから clearSeconds 経ったコマにクリアの画面へ移り、かかった時間はクリアした時刻（始めは 0 秒）。
    @Test
    def testClearScreenFollowsAfterClearSeconds(): Unit \ Assert =
        let cleared = World.step(res(), idle(), at(0.05, inFinalRoom(World.initial(res()))));
        let shown = World.step(res(), idle(), at(0.05 + player()#clearSeconds, cleared));
        Assert.assertEq(expected = Some((0.05, 0)), World.tallyOf(shown) |> Option.map(t -> (t#seconds, t#kills)))

    /// クリアの画面で Enter を押すとタイトルへ戻る。
    @Test
    def testEnterOnClearGoesToTitle(): Unit \ Assert =
        let cleared = World.step(res(), idle(), at(0.05, inFinalRoom(World.initial(res()))));
        let shown = World.step(res(), idle(), at(0.05 + player()#clearSeconds, cleared));
        Assert.assertEq(expected = true, World.isOnTitle(Controls.step(pressing(Key.Enter), res(), shown)))

    /// タイトル → Enter で遊ぶ → 最後の部屋を空にする → clearSeconds の後にクリアの画面 → Enter でタイトル、の順に移る。
    @Test
    def testTitleToPlayToClearToTitle(): Unit \ Assert =
        let started = Controls.step(pressing(Key.Enter), res(), at(1.0, World.title()));
        let cleared = World.step(res(), idle(), at(1.05, inFinalRoom(started)));
        let shown = World.step(res(), idle(), at(1.05 + player()#clearSeconds, cleared));
        let back = Controls.step(pressing(Key.Enter), res(), shown);
        Assert.assertEq(expected = (true, true, true, true),
            (Option.nonEmpty(World.sessionOf(started)), Option.nonEmpty(World.sessionOf(cleared)), Option.nonEmpty(World.tallyOf(shown)), World.isOnTitle(back)))

    // ── 倒した数 ──

    /// 体力が拳銃の威力と同じ melee を 1 発で倒すと、倒した数が 1 になる。
    @Test
    def testShotDownEnemyCounts(): Unit \ Assert =
        let pistol = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Pistol, WeaponsDoc.defaults());
        let e = EnemiesDoc.rec(EnemiesDoc.defaults());
        let r = { enemies = EnemiesDoc.Doc.Doc({ melee = { health = pistol#damage | e#melee } | e }) | res() };
        let aimed = World.mapHorde(Horde.spawnNow(r, { kind = Kind.Melee, x = 12.0, z = 10.0, yaw = Num.pi() * 1.5, home = 'A' } :: Nil), World.initial(r));
        let shot = World.step(r, { trigger = { pressed = true, held = true } | idle() }, at(0.05, aimed));
        Assert.assertEq(expected = Some(1), World.sessionOf(shot) |> Option.map(World.killsOf))

    // ── 時計 ──

    /// ポーズの間は遊びの時計が進まない（1 秒進めても 0 秒のまま）。
    @Test
    def testPauseStopsThePlayClock(): Unit \ Assert =
        let paused = World.pause(World.initial(res()));
        Assert.assertEq(expected = 0.0, Clock.secondsOf(Clock.nowOf(Clock.advance(World.paceOf(res(), paused), 1.0, paused#play))))

    /// 今の時計が 5 秒の所から遊び直すと、かかった時間はそこから数える（クリアの時間にタイトルにいた 5 秒を足さない）。
    @Test
    def testRestartCountsTimeFromNow(): Unit \ Assert =
        let restarted = World.restart(res(), at(5.0, World.title()));
        let cleared = World.step(res(), idle(), at(5.05, inFinalRoom(restarted)));
        let shown = World.step(res(), idle(), at(5.05 + player()#clearSeconds, cleared));
        Assert.assertEq(expected = Some(true), World.tallyOf(shown) |> Option.map(t -> Float64.abs(t#seconds - 0.05) < 0.001))

    // ── 画面をまたぐ事と音 ──

    /// タイトルで Enter を押したコマに起きた事は「遊び始めた」で、決める音と、最初の部屋に入った扉の音が鳴る。
    @Test
    def testStartingReportsStartedAndSounds(): Unit \ Assert =
        let started = Controls.step(pressing(Key.Enter), res(), World.title());
        Assert.assertEq(expected = (Event.Started :: Nil, "ui_choose" :: "door" :: Nil), (World.screenEventsOf(started), Sounds.events(res(), World.title(), started)))

    /// ポーズで矢印の下を押すと項目が動き（動かす音）、Enter で「タイトルへ」を決める: 決めた・タイトルへ の順。
    @Test
    def testPauseMenuEventsByArrowKeys(): Unit \ Assert =
        let paused = Controls.step(pressing(Key.Escape), res(), World.setLooking(true, World.initial(res())));
        let moved = Controls.step(pressing(Key.Down), res(), paused);
        let chosen = Controls.step(pressing(Key.Enter), res(), moved);
        Assert.assertEq(expected = (Event.Paused :: Nil, "ui_move" :: Nil, Event.MenuChosen :: Event.ToTitle :: Nil, true),
            (World.screenEventsOf(paused), Sounds.events(res(), paused, moved), World.screenEventsOf(chosen), World.isOnTitle(chosen)))

    /// 前のコマの画面をまたぐ事は、次のコマには残らない。
    @Test
    def testScreenEventsLastOneFrame(): Unit \ Assert =
        let started = Controls.step(pressing(Key.Enter), res(), World.title());
        Assert.assertEq(expected = Nil, World.screenEventsOf(Controls.step(App.emptyFrame(), res(), started)))

    /// クリアの画面へ移ったコマに「クリアの画面へ」が起きる。
    @Test
    def testClearScreenReportsClearShown(): Unit \ Assert =
        let cleared = World.step(res(), idle(), at(0.05, inFinalRoom(World.initial(res()))));
        Assert.assertEq(expected = Event.ClearShown :: Nil, World.screenEventsOf(World.step(res(), idle(), at(0.05 + player()#clearSeconds, cleared))))

    /// 鳴り続ける音の倍率: 遊んでいる間は 1・ポーズの間とタイトルでは 0。
    @Test
    def testSustainedSoundIsSilentWhilePaused(): Unit \ Assert =
        Assert.assertEq(expected = (1.0, 0.0, 0.0),
            (Sounds.sustainedScale(World.initial(res())), Sounds.sustainedScale(World.pause(World.initial(res()))), Sounds.sustainedScale(World.title())))
}
