// 敵の規則（Horde・Creatures の口を直に）: 当たり判定（体・頭・壁の向こう）・ダメージと倒れる・よろけの間隔・
// wave・同時に生きている数の上限・湧く所・押し合い・距離の地図で近づく・melee の当たる時刻と扇・ranged の見通しと吐く上限・projectile・姿勢の共有の鍵。
mod TestHorde {
    use fge::{Camera3d, FlowField, Hash01, LogCapture, Mat4, Num, Vec3}
    use Creatures.Kind
    use TestSupport.{mazeOf, resWith}

    // ── 迷路と道具 ──

    /// 西の部屋 A（x 4〜24 m・z 4〜16 m）と、壁 1 マスを挟んだ東の通路 B（x 28〜32 m）。
    /// 的の柱は A の列 1・行 2（真ん中 x = 6 m・z = 10 m）。start は A の東の端（x 22 m・z 10 m）で西を向く。
    def twoRooms(): MazeDoc.Doc =
        mazeOf("#########" :: "#AAAAA#B#" :: "#AAAAA#B#" :: "#AAAAA#B#" :: "#########" :: Nil, 5, 2, 270.0)

    def res(): Res.Res = resWith(twoRooms())

    def doc(): EnemiesDoc.Rec = EnemiesDoc.rec(EnemiesDoc.defaults())

    def walk(): WalkDoc.Rec = WalkDoc.rec(WalkDoc.defaults())

    def pistol(): WeaponsDoc.Stats = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Pistol, WeaponsDoc.defaults())

    def east(): Float64 = Num.pi() * 0.5

    def west(): Float64 = Num.pi() * 1.5

    /// 足元 (x, z) に立つプレイヤー（体の寸法は歩く Doc の既定）。
    def playerAt(x: Float64, z: Float64): PlayerBody.PlayerBody =
        { x = x, feet = 0.0, z = z, eye = Vec3.v3(x, walk()#eyeHeight, z), yaw = east(), radius = walk()#radius, height = walk()#height }

    /// 型 k の 1 体（番号 0）を x・z に、向き yaw（ラジアン）で立たせた群れ。
    def oneAt(r: Res.Res, k: Kind, x: Float64, z: Float64, yaw: Float64): Horde.Horde =
        Horde.spawnNow(r, { kind = k, x = x, z = z, yaw = yaw, home = 'A' } :: Nil, Horde.empty())

    /// x = 12 m で東を向く melee 1 体。
    def meleeAt12(): Horde.Horde = oneAt(res(), Kind.Melee, 12.0, 10.0, east())

    /// 目 (x, y, 10) から西をまっすぐ見るカメラ。
    def westCamera(x: Float64, y: Float64): Camera3d.Camera3d =
        { eye = Vec3.v3(x, y, 10.0), yaw = west(), pitch = 0.0, fovY = 1.0, near = 0.05, far = 60.0 }

    def struckOf(h: Horde.Horde, camera: Camera3d.Camera3d): List[Hitscan.Struck] =
        Hitscan.fire(List.append(Horde.targetsOf(h), res()#hitTargets), camera, pistol(), 0) |> List.map(i -> i#struck)

    def impactOn(part: Hitscan.Part): List[Hitscan.Impact] =
        { struck = Hitscan.Struck.Enemy(0, part), point = Vec3.zero(), normal = Vec3.zero() } :: Nil

    /// 時刻 t に、東の端の目（x = 22 m）から拳銃で 1 粒の威力 damage を撃った 1 回。
    def pistolShot(t: Float64, damage: Float64): Horde.Shot =
        { t = t, damage = damage, weapon = WeaponsDoc.Weapon.Pistol, origin = Vec3.v3(22.0, walk()#eyeHeight, 10.0), index = 0 }

    def damaged(t: Float64, amount: Float64, part: Hitscan.Part, h: Horde.Horde): Horde.Horde = Horde.applyDamage(res(), pistolShot(t, amount), impactOn(part), h)#horde

    def actOf(h: Horde.Horde): Option[Horde.Act] = Horde.enemyOf(0, h) |> Option.map(e -> e#act)

    def healthOf(h: Horde.Horde): Option[Float64] = Horde.enemyOf(0, h) |> Option.map(e -> e#health)

    // ── 当たり判定 ──

    /// 頭の高さ（1.88 m。glb の頭の球の真ん中）で撃つと頭に当たる。
    @Test
    def testShotAtHeadHeightHitsTheHead(): Unit \ Assert =
        Assert.assertEq(expected = Hitscan.Struck.Enemy(0, Hitscan.Part.Head) :: Nil, struckOf(meleeAt12(), westCamera(22.0, 1.88)))

    /// 腰の高さ（1 m）で撃つと体に当たる。
    @Test
    def testShotAtWaistHeightHitsTheBody(): Unit \ Assert =
        Assert.assertEq(expected = Hitscan.Struck.Enemy(0, Hitscan.Part.Body) :: Nil, struckOf(meleeAt12(), westCamera(22.0, 1.0)))

    /// 東の通路 B（x = 30 m）から撃つと間の壁（x = 28 m）で止まり、壁の向こうの敵には当たらない。
    @Test
    def testWallStopsTheShotBeforeTheEnemy(): Unit \ Assert =
        Assert.assertEq(expected = Hitscan.Struck.Wall :: Nil, struckOf(meleeAt12(), westCamera(30.0, 1.0)))

    /// 倒れた敵は弾の的にならない（倒れる途中の体を撃っても後ろの的の柱に当たる）。
    @Test
    def testFallenEnemiesAreNotTargets(): Unit \ Assert =
        Assert.assertEq(expected = Hitscan.Struck.Prop(0) :: Nil, struckOf(damaged(0.0, doc()#melee#health, Hitscan.Part.Body, meleeAt12()), westCamera(22.0, 1.0)))

    /// 4 m 先に詰まった 5 体（前に 3 体・その間の後ろに 2 体）へ散弾銃を 1 回: 粒が群れに散り、2 体以上が倒れる（残るのは 3 体以下）。
    @Test
    def testShotgunFellsSeveralOfACloseCrowd(): Unit \ Assert =
        let at = (x: Float64, z: Float64) -> { kind = Kind.Melee, x = x, z = z, yaw = east(), home = 'A' };
        let crowd = Horde.spawnNow(res(), at(18.0, 9.2) :: at(18.0, 10.0) :: at(18.0, 10.8) :: at(17.2, 9.6) :: at(17.2, 10.4) :: Nil, Horde.empty());
        let shotgun = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Shotgun, WeaponsDoc.defaults());
        let impacts = Hitscan.fire(List.append(Horde.targetsOf(crowd), res()#hitTargets), westCamera(22.0, 1.4), shotgun, 0);
        let shot = { t = 0.0, damage = shotgun#damage, weapon = WeaponsDoc.Weapon.Shotgun, origin = Vec3.v3(22.0, 1.4, 10.0), index = 0 };
        Assert.assertEq(expected = true, Horde.aliveCount(Horde.applyDamage(res(), shot, impacts, crowd)#horde) <= 3)

    // ── ダメージと倒れる ──

    /// 体に拳銃 1 発: 体力が威力だけ減る。
    @Test
    def testBodyShotTakesTheWeaponDamage(): Unit \ Assert =
        Assert.assertEq(expected = Some(doc()#melee#health - pistol()#damage), healthOf(damaged(1.0, pistol()#damage, Hitscan.Part.Body, meleeAt12())))

    /// 体に拳銃 1 発: 追っている途中ならよろける。
    @Test
    def testBodyShotStaggers(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Hurt(1.0)), actOf(damaged(1.0, pistol()#damage, Hitscan.Part.Body, meleeAt12())))

    /// 頭は威力 × headMultiplier: 頭に威力 10 の弾 1 粒で、体力が 10 × 倍率だけ減る（倒れない・弾けない強さ）。
    @Test
    def testHeadShotMultipliesTheDamage(): Unit \ Assert =
        Assert.assertEq(expected = Some(doc()#melee#health - 10.0 * doc()#headMultiplier),
            healthOf(damaged(1.0, 10.0, Hitscan.Part.Head, meleeAt12())))

    /// よろけてから staggerCooldown の内にもう 1 発当たっても、よろけは始め直さない（連射で一歩も進めない、にならない）。
    @Test
    def testStaggerWaitsForTheCooldown(): Unit \ Assert =
        let once = damaged(1.0, 1.0, Hitscan.Part.Body, meleeAt12());
        Assert.assertEq(expected = Some(Horde.Act.Hurt(1.0)), actOf(damaged(1.0 + doc()#staggerCooldown * 0.5, 1.0, Hitscan.Part.Body, once)))

    /// 振り下ろしている途中の melee は撃たれてもよろけない（振りは止まらない）。
    @Test
    def testAttackIsNotInterruptedByAHit(): Unit \ Assert =
        let swinging = Horde.step(res(), 0.1, 0.1, playerAt(13.0, 10.0), meleeAt12())#horde;
        Assert.assertEq(expected = Some(Horde.Act.Attack(0.1, false)), actOf(damaged(0.2, pistol()#damage, Hitscan.Part.Body, swinging)))

    /// 倒れた敵は corpseSeconds の半分ではまだ残る。
    @Test
    def testCorpseStaysWithinTheDocTime(): Unit \ Assert =
        let fallen = damaged(0.0, doc()#melee#health, Hitscan.Part.Body, meleeAt12());
        Assert.assertEq(expected = 1, List.length(Horde.step(res(), doc()#corpseSeconds * 0.5, 0.1, playerAt(22.0, 10.0), fallen)#horde#enemies))

    /// 倒れた敵は corpseSeconds が過ぎたコマに消える。
    @Test
    def testCorpseIsGoneAfterTheDocTime(): Unit \ Assert =
        let fallen = damaged(0.0, doc()#melee#health, Hitscan.Part.Body, meleeAt12());
        Assert.assertEq(expected = 0, List.length(Horde.step(res(), doc()#corpseSeconds, 0.1, playerAt(22.0, 10.0), fallen)#horde#enemies))

    // ── spawn と wave ──

    /// 東西に長い部屋 A（x 4〜44 m・z 4〜12 m）だけの迷路。start は西の端（x 6 m・z 10 m）で東を向く。
    /// spawn の印は東の端の 2 マス（x 42 m・z 10 m と z 6 m）。
    def longRoom(): MazeDoc.Doc =
        let mark = (col: Int32, row: Int32) -> { kind = MazeDoc.MarkKind.Spawn, name = "spawn", col = col, row = row, yaw = 0.0 };
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'A',
                          rows = "############" :: "#AAAAAAAAAA#" :: "#AAAAAAAAAA#" :: "############" :: Nil,
                          zones = { id = 'A', name = "room", kind = MazeDoc.ZoneKind.Room, height = 4.0 } :: Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = 1, row = 1, yaw = 90.0 } :: mark(10, 1) :: mark(10, 2) :: Nil })

    def spawns(): SpawnsDoc.Rec = SpawnsDoc.rec(SpawnsDoc.defaults())

    /// 部屋 A の wave 1 つ（melee だけ）。
    def wave(melee: Int32, after: Float64, whenLeft: Int32): SpawnsDoc.Wave = { zone = 'A', melee = melee, ranged = 0, source = None, after = after, whenLeft = whenLeft }

    /// 長い部屋の迷路に、部屋 A の wave だけを書いた spawns の Doc の描く元。
    def wavesRes(waves: List[SpawnsDoc.Wave]): Res.Res =
        Res.withSpawns(SpawnsDoc.Doc.Doc({ waves = waves | spawns() }), resWith(longRoom()))

    /// 西の端（x 6 m・z 10 m）で東を向いて立つプレイヤー（印から 36 m）。
    def westEnd(): PlayerBody.PlayerBody = playerAt(6.0, 10.0)

    /// 時刻 0 に部屋 A に入り、刻み 0.1 秒で frames コマ進めた群れ。
    def runFor(r: Res.Res, frames: Int32): Horde.Horde = Horde.simulate(r, 0.0, 0.1, frames, westEnd(), Horde.enter('A', 0.0, Horde.empty()))#horde

    /// 時刻 t に、番号 ids の敵に体力より強い弾（60。melee と ranged の体力より強く、弾ける余剰ダメージより弱い）を 1 粒ずつ当てた群れ。
    def shotDown(r: Res.Res, t: Float64, ids: List[Int32], h: Horde.Horde): Horde.Horde =
        Horde.applyDamage(r, pistolShot(t, 60.0), ids |> List.map(id -> { struck = Hitscan.Struck.Enemy(id, Hitscan.Part.Body), point = Vec3.zero(), normal = Vec3.zero() }), h)#horde

    /// 上限より 10 体多い wave 1 つに入って 10 秒（上限まで湧くのは maxAlive × spawnInterval = 7.5 秒）。
    def capped(): (Res.Res, Horde.Horde) =
        let r = wavesRes(wave(spawns()#maxAlive + 10, 0.0, 0) :: Nil);
        (r, runFor(r, 100))

    /// 生きている数は maxAlive で止まり、残りは湧くのを待つ。
    @Test
    def testAliveNeverExceedsMaxAlive(): Unit \ Assert =
        let (_, h) = capped();
        Assert.assertEq(expected = (spawns()#maxAlive, 10), (Horde.aliveCount(h), Horde.queuedCount(h)))

    /// 上限の群れの 1 体を倒すと、spawnInterval の後に待っていた 1 体が湧いて上限に戻る（倒れた体は数えない）。
    @Test
    def testFellingOneLetsTheNextSpawn(): Unit \ Assert =
        let (r, h) = capped();
        let refilled = Horde.simulate(r, 10.0, 0.1, 2, westEnd(), shotDown(r, 10.0, 0 :: Nil, h))#horde;
        Assert.assertEq(expected = (spawns()#maxAlive, 9), (Horde.aliveCount(refilled), Horde.queuedCount(refilled)))

    /// 2 つ目の wave（after 5 秒）は、1 つ目の敵が残っていれば 5 秒が過ぎるまで始まらない（4 秒で 1 つ・6 秒で 2 つ）。
    @Test
    def testWavesStartInOrderByTime(): Unit \ Assert =
        let r = wavesRes(wave(2, 0.0, 0) :: wave(2, 5.0, 0) :: Nil);
        Assert.assertEq(expected = (1, 2), (Horde.wavesStarted('A', runFor(r, 40)), Horde.wavesStarted('A', runFor(r, 60))))

    /// 1 つ目の wave の 2 体を倒すと、残りが whenLeft（0）以下になり、after（100 秒）を待たずに 2 つ目が始まる。
    @Test
    def testNextWaveStartsWhenFewAreLeft(): Unit \ Assert =
        let r = wavesRes(wave(2, 0.0, 0) :: wave(2, 100.0, 0) :: Nil);
        let cleared = shotDown(r, 1.0, 0 :: 1 :: Nil, runFor(r, 10));
        Assert.assertEq(expected = 2, Horde.wavesStarted('A', Horde.simulate(r, 1.0, 0.1, 1, westEnd(), cleared)#horde))

    /// 部屋は最後の wave を倒すまで終わらない: 1 つ目を倒した所では終わらず、2 つ目が湧いて倒した所で終わる。
    @Test
    def testRoomFinishesOnlyAfterTheLastWave(): Unit \ Assert =
        let r = wavesRes(wave(1, 0.0, 0) :: wave(1, 0.0, 0) :: Nil);
        let first = shotDown(r, 1.0, 0 :: Nil, runFor(r, 10));
        let second = shotDown(r, 2.0, 1 :: Nil, Horde.simulate(r, 1.0, 0.1, 10, westEnd(), first)#horde);
        Assert.assertEq(expected = (false, true), (Horde.isFinished(r, 'A', first), Horde.isFinished(r, 'A', second)))

    /// wave を倒し切って corpseSeconds が過ぎると、敵の列は空に戻る（倒した数だけ列が伸び続けない）。
    @Test
    def testFallenWaveLeavesTheList(): Unit \ Assert =
        let r = wavesRes(wave(4, 0.0, 0) :: Nil);
        let fallen = shotDown(r, 1.0, 0 :: 1 :: 2 :: 3 :: Nil, runFor(r, 10));
        let later = Horde.step(r, 1.0 + doc()#corpseSeconds, 0.1, westEnd(), fallen)#horde;
        Assert.assertEq(expected = (0, 0), (List.length(later#enemies), Horde.queuedCount(later)))

    /// もう一度入っても wave を始め直さない（1 区画 1 回だけ）。
    @Test
    def testEnteringTwiceStartsOnce(): Unit \ Assert =
        let r = wavesRes(wave(2, 0.0, 0) :: Nil);
        Assert.assertEq(expected = 1, Horde.wavesStarted('A', Horde.simulate(r, 1.0, 0.1, 1, westEnd(), Horde.enter('A', 1.0, runFor(r, 10)))#horde))

    /// 区画に spawn の印が無い wave は 1 行知らせて捨てる（長い部屋の印は A にだけある）。
    @Test
    def testWaveWithoutMarksIsReportedAndDropped(): Unit \ {Assert, IO} =
        let r = resWith(longRoom());
        let doc = SpawnsDoc.Doc.Doc({ waves = wave(1, 0.0, 0) :: { source = Some('Z') | wave(1, 0.0, 0) } :: Nil | spawns() });
        let (plans, lines) = LogCapture.capture(() -> Spawner.plansOf(r#maze, r#spawnPoints, doc));
        Assert.assertEq(expected = (1, Some(1)), (List.length(lines), Map.get('A', plans) |> Option.map(List.length)))

    // ── 湧く所 ──

    /// x 6 m・z 10 m（西の印）と x 42 m・z 10 m（東の印）。
    def westAndEast(): List[Spawner.Point] = { zone = 'A', x = 6.0, z = 10.0 } :: { zone = 'A', x = 42.0, z = 10.0 } :: Nil

    def placing(): Spawner.Placing = { minDistance = spawns()#minDistance, scatter = spawns()#scatter }

    /// x・z に立ち、向き yaw で、壁に遮られない（どの点も見通せる）プレイヤーの見え方。
    def viewer(x: Float64, z: Float64, yaw: Float64): Spawner.Viewer = { x = x, z = z, yaw = yaw, lineOfSight = (_, _) -> true }

    /// 湧いた点が (x, z) の印のマスの中（散らす幅の半分の内）か。
    def isAround(x: Float64, z: Float64, at: Option[(Float64, Float64)]): Bool =
        at |> Option.exists(p -> Float64.abs(fst(p) - x) <= spawns()#scatter * 0.5 and Float64.abs(snd(p) - z) <= spawns()#scatter * 0.5)

    /// 西の印から 4 m（minDistance より近い）に立つと、近い西の印でなく遠い東の印から湧く（印を回す番号が西を指す 0 でも）。
    @Test
    def testSpawnSkipsMarksNearerThanMinDistance(): Unit \ Assert =
        Assert.assertEq(expected = true, isAround(42.0, 10.0, Spawner.placeOf(placing(), viewer(10.0, 10.0, west()), 'A', 0, westAndEast())))

    /// 真ん中（x 24 m）で東を向くと、どちらの印も 18 m 先だが、見えている東でなく背中側の西の印から湧く（印を回す番号が東を指す 1 でも）。
    @Test
    def testSpawnPrefersAMarkOutOfSight(): Unit \ Assert =
        Assert.assertEq(expected = true, isAround(6.0, 10.0, Spawner.placeOf(placing(), viewer(24.0, 10.0, east()), 'A', 1, westAndEast())))

    /// どちらの印も minDistance より近い所（x 20 m・z 10 m）からは、一番遠い西の印（13 m 先。東は 12 m）から湧く（部屋が空のままにならない）。
    @Test
    def testAllMarksTooCloseSpawnFromTheFarthest(): Unit \ Assert =
        let near = { zone = 'A', x = 7.0, z = 10.0 } :: { zone = 'A', x = 32.0, z = 10.0 } :: Nil;
        Assert.assertEq(expected = true, isAround(7.0, 10.0, Spawner.placeOf(placing(), viewer(20.0, 10.0, east()), 'A', 1, near)))

    // ── 押し合い ──

    /// 同じ点に立った melee 2 体は、1 コマで押し合いの半径の和まで離れる。
    @Test
    def testTwoEnemiesOnOnePointArePushedApart(): Unit \ Assert =
        let both = Horde.spawnNow(res(), { kind = Kind.Melee, x = 12.0, z = 10.0, yaw = 0.0, home = 'A' } :: { kind = Kind.Melee, x = 12.0, z = 10.0, yaw = 0.0, home = 'A' } :: Nil, Horde.empty());
        let after = Horde.step(res(), 0.1, 1.0 / 60.0, playerAt(22.0, 10.0), both)#horde;
        let gap = forM (a <- Horde.enemyOf(0, after); b <- Horde.enemyOf(1, after)) yield Num.sqrt((a#x - b#x) * (a#x - b#x) + (a#z - b#z) * (a#z - b#z));
        Assert.assertEq(expected = Some(true), gap |> Option.map(g -> g >= Creatures.footprintOf(Kind.Melee) * 2.0 - 0.001))

    /// 部屋 A に詰めた大小 120 体の押し合いは、全員どうしを比べて押した足元と 1e-9 m の内で同じ。
    @Test
    def testCrowdIsPushedLikeEveryPairCompared(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Float64.floor(pushGap(crowdInA()) * 1.0e9))

    /// 部屋 A の 120 体と、迷路から遠く離れた 1 体（升が広がる・迷路の外で壁の箱が無く壁に押されない）の押し合いも、全員どうしを比べた足元と 1e-9 m の内で同じ。
    @Test
    def testCrowdWithStragglerIsPushedLikeEveryPairCompared(): Unit \ Assert =
        let straggler = { id = 999, x = 200.0, z = 200.0, radius = 0.35 };
        Assert.assertEq(expected = 0.0, Float64.floor(pushGap(List.append(crowdInA(), straggler :: Nil)) * 1.0e9))

    /// 円が 0 個なら足元も 0 個。
    @Test
    def testNoDiscsGiveNoFeet(): Unit \ Assert =
        let r = res();
        Assert.assertEq(expected = Nil, Separation.separate(r#maze, r#collision, r#openCells, playerAt(14.0, 10.0), Nil))

    /// 部屋 A の床の内（x 8〜20 m・z 7〜13 m。壁の箱に届かない）に散らした大小 120 体。どの 2 体も 1e-4 m より離れている。
    def crowdInA(): List[Separation.Disc] =
        List.range(0, 120) |> List.map(i ->
            { id = i, x = 8.0 + 12.0 * Hash01.at(i, 11), z = 7.0 + 6.0 * Hash01.at(i, 12), radius = if (Int32.modulo(i, 3) == 0) 0.6 else 0.35 })

    /// (14, 10) に立つプレイヤーで discs を押し合わせた足元と、全員どうしを比べた足元の、一番大きい差（m）。
    def pushGap(discs: List[Separation.Disc]): Float64 =
        let r = res();
        let p = playerAt(14.0, 10.0);
        let got = Separation.separate(r#maze, r#collision, r#openCells, p, discs);
        let want = discs |> List.map(everyPairPushed(p, discs));
        List.zip(got, want) |> List.foldLeft((acc, gw) -> {
            let ((gx, gz), (wx, wz)) = gw;
            Float64.max(acc, Float64.max(Float64.abs(gx - wx), Float64.abs(gz - wz)))
        }, 0.0)

    /// d が、ほかの全員から重なった分の半分ずつ・プレイヤーから重なった分を全部押されて着く足元（壁は見ない・1e-4 m より近い組は無い前提）。
    def everyPairPushed(p: PlayerBody.PlayerBody, discs: List[Separation.Disc], d: Separation.Disc): (Float64, Float64) =
        let away = (ox: Float64, oz: Float64, reach: Float64, share: Float64) -> {
            let dist = Num.sqrt((d#x - ox) * (d#x - ox) + (d#z - oz) * (d#z - oz));
            if (dist >= reach) (0.0, 0.0) else ((d#x - ox) / dist * (reach - dist) * share, (d#z - oz) / dist * (reach - dist) * share)
        };
        let pushes = (p#x, p#z, d#radius + p#radius, 1.0) :: (discs |> List.filter(o -> o#id != d#id) |> List.map(o -> (o#x, o#z, d#radius + o#radius, 0.5)));
        pushes |> List.foldLeft((acc, o) -> {
            let (ox, oz, reach, share) = o;
            let (ax, az) = away(ox, oz, reach, share);
            (fst(acc) + ax, snd(acc) + az)
        }, (d#x, d#z))

    // ── 距離の地図で近づく ──

    /// 真ん中に柱のある輪の迷路（床は外周の 8 マス・柱は列 2・行 2）で、左上の (1, 1) へ塗った地図。
    def ringField(): FlowField.FlowField =
        Horde.paintField(resWith(mazeOf("#####" :: "#AAA#" :: "#A#A#" :: "#AAA#" :: "#####" :: Nil, 1, 1, 0.0))#maze, { col = 1, row = 1 })

    /// 地図の上で cell から下るマス（列, 行）。
    def downhillAt(f: FlowField.FlowField, col: Int32, row: Int32): Option[(Int32, Int32)] =
        FlowField.downhill(f, (col, row))

    /// goal のマスからは下らない。
    @Test
    def testFieldGoalHasNoDownhill(): Unit \ Assert =
        Assert.assertEq(expected = None, downhillAt(ringField(), 1, 1))

    /// 迷路の外のマスは歩数も下る先も無い。
    @Test
    def testFieldOutsideTheMazeIsUnpainted(): Unit \ Assert =
        Assert.assertEq(expected = (None, None), (FlowField.stepsAt(ringField(), (-1, 0)), downhillAt(ringField(), 9, 9)))

    /// 右下 (3, 3) は goal から 4 歩。上 (3, 2) と左 (2, 3) が同じ 3 歩なら、先に見る上へ下る。
    @Test
    def testFieldTiePrefersTheFirstStraightStep(): Unit \ Assert =
        Assert.assertEq(expected = (Some(4), Some((3, 2))), (FlowField.stepsAt(ringField(), (3, 3)), downhillAt(ringField(), 3, 3)))

    /// (3, 2) から斜め左上の (2, 1) は 1 歩だが、柱の角を斜めに抜けないので上の (3, 1) へ下る。
    @Test
    def testFieldDoesNotCutAWallCorner(): Unit \ Assert =
        Assert.assertEq(expected = Some((3, 1)), downhillAt(ringField(), 3, 2))

    /// 壁で切れた床 (3, 1) へは届かない（歩数も下る先も無い）。
    @Test
    def testFieldUnreachableFloorIsUnpainted(): Unit \ Assert =
        let f = Horde.paintField(resWith(mazeOf("#####" :: "#A#A#" :: "#####" :: Nil, 1, 1, 0.0))#maze, { col = 1, row = 1 });
        Assert.assertEq(expected = (None, None), (FlowField.stepsAt(f, (3, 1)), downhillAt(f, 3, 1)))

    /// U の字の迷路: 西の脚の下（x 6 m・z 6 m）の melee は、間の壁を回って東の脚の下（x 14 m・z 6 m）のプレイヤーへ着く
    /// （壁を回る道は 20 m ほど・melee の速さ 3 m/秒で 7 秒ほど。9 秒進めて、地図の上でプレイヤーのマスか隣にいる）。
    @Test
    def testMeleeWalksAroundTheWallByTheField(): Unit \ Assert =
        let r = resWith(mazeOf("#####" :: "#AAA#" :: "#A#A#" :: "#A#A#" :: "#####" :: Nil, 3, 3, 0.0));
        let o = Horde.simulate(r, 0.0, 0.05, 180, playerAt(14.0, 6.0), oneAt(r, Kind.Melee, 6.0, 6.0, 0.0));
        Assert.assertEq(expected = Some(true),
            Horde.enemyOf(0, o#horde) |> Option.flatMap(e -> { let cell = Maze.cellAt(r#maze, e#x, e#z); FlowField.stepsAt(o#horde#field, (cell#col, cell#row)) }) |> Option.map(s -> s <= 1))

    // ── melee の振り下ろし ──

    def meleeInFront(): Horde.Horde = oneAt(res(), Kind.Melee, 13.0, 10.0, east())

    /// プレイヤーの 1 m 手前の melee: 振り始めてから hitTime の手前のコマまではダメージ 0（刻みは hitTime の 1/4・4 コマ）。
    @Test
    def testMeleeDoesNotHitBeforeTheDocTime(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Horde.simulate(res(), 0.0, doc()#melee#hitTime / 4.0, 4, playerAt(14.0, 10.0), meleeInFront())#damage)

    /// 振り始めたコマから hitTime のコマに Doc の威力（5 コマ目）。
    @Test
    def testMeleeHitsAtTheDocTime(): Unit \ Assert =
        Assert.assertEq(expected = doc()#melee#damage, Horde.simulate(res(), 0.0, doc()#melee#hitTime / 4.0, 5, playerAt(14.0, 10.0), meleeInFront())#damage)

    /// 振り始めた次のコマが hitTime を一度に飛び越えても（時計は 0.6 秒進み、dt は 0.05 に切り詰められたコマ）、当たるのは 1 回だけ。
    @Test
    def testMeleeHitsOnceAcrossALongFrame(): Unit \ Assert =
        let p = playerAt(14.0, 10.0);
        let swinging = Horde.step(res(), 0.1, 0.05, p, meleeInFront())#horde;
        let first = Horde.step(res(), 0.7, 0.05, p, swinging);
        let second = Horde.step(res(), 0.75, 0.05, p, first#horde);
        Assert.assertEq(expected = doc()#melee#damage, first#damage + second#damage)

    def northMelee(): Option[Horde.Enemy] = Horde.enemyOf(0, oneAt(res(), Kind.Melee, 10.0, 10.0, 0.0))

    /// 北を向く melee の 1 m 前は扇の内。
    @Test
    def testMeleeSwingCoversTheFront(): Unit \ Assert =
        Assert.assertEq(expected = Some(true), northMelee() |> Option.map(e -> Horde.isInSwing(doc()#melee, e, playerAt(10.0, 11.0))))

    /// 北を向く melee の 1 m 後ろは扇の外。
    @Test
    def testMeleeSwingMissesBehind(): Unit \ Assert =
        Assert.assertEq(expected = Some(false), northMelee() |> Option.map(e -> Horde.isInSwing(doc()#melee, e, playerAt(10.0, 9.0))))

    /// 前でも reach と体の半径より 0.2 m 遠ければ扇の外。
    @Test
    def testMeleeSwingMissesBeyondTheReach(): Unit \ Assert =
        Assert.assertEq(expected = Some(false),
            northMelee() |> Option.map(e -> Horde.isInSwing(doc()#melee, e, playerAt(10.0, 10.0 + doc()#melee#reach + walk()#radius + 0.2))))

    // ── ranged ──

    def rangedActAfterOneFrame(player: PlayerBody.PlayerBody): Option[Horde.Act] =
        Horde.step(res(), 0.1, 0.1, player, oneAt(res(), Kind.Ranged, 10.0, 10.0, east()))#horde |> actOf

    /// 同じ部屋（12 m 先）で見通しがあれば 1 コマ目に吐く前の溜めを始める。
    @Test
    def testRangedChargesWithLineOfSight(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Charge(0.1)), rangedActAfterOneFrame(playerAt(22.0, 10.0)))

    /// 間に壁がある通路 B（20 m 先）なら吐き始めない（追うまま）。
    @Test
    def testRangedDoesNotAttackThroughWalls(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Chase), rangedActAfterOneFrame(playerAt(30.0, 10.0)))

    /// 吐き始めた後で飛んでいる数が上限（limit 1 の Doc）に届いたら、吐く時刻が来ても吐かない（飛んでいるのは止まった 1 本のまま）。
    @Test
    def testRangedDoesNotSpitPastTheLimit(): Unit \ Assert =
        let r = { enemies = EnemiesDoc.Doc.Doc({ projectile = { limit = 1 | doc()#projectile } | doc() }) | res() };
        let p = playerAt(22.0, 10.0);
        let started = Horde.step(r, 0.1, 0.1, p, oneAt(r, Kind.Ranged, 10.0, 10.0, east()))#horde;
        let full = Horde.launch(Vec3.v3(10.0, 1.5, 14.0), Vec3.zero(), 0.1, started);
        Assert.assertEq(expected = 1, List.length(Horde.simulate(r, 0.1, 0.1, 7, p, full)#horde#projectiles))

    /// 西の壁（x = 4 m）の 1 m 手前から西へ飛ぶ projectile は壁で弾けて消える（弾けた所が 1 つ・ダメージ 0）。
    @Test
    def testProjectileBurstsOnWalls(): Unit \ Assert =
        let speed = doc()#projectile#speed;
        let o = Horde.simulate(res(), 0.0, 0.05, 4, playerAt(22.0, 10.0), Horde.launch(Vec3.v3(5.0, 1.5, 14.0), Vec3.v3(0.0 - speed, 0.0, 0.0), 0.0, Horde.empty()));
        Assert.assertEq(expected = (0, 1, 0.0), (List.length(o#horde#projectiles), List.length(o#splashes), o#damage))

    /// プレイヤーへ飛ぶ projectile は当たって Doc の威力。
    @Test
    def testProjectileHurtsThePlayer(): Unit \ Assert =
        let speed = doc()#projectile#speed;
        let o = Horde.simulate(res(), 0.0, 0.05, 20, playerAt(22.0, 10.0), Horde.launch(Vec3.v3(18.0, 1.5, 10.0), Vec3.v3(speed, 0.0, 0.0), 0.0, Horde.empty()));
        Assert.assertEq(expected = doc()#projectile#damage, o#damage)

    // ── 姿勢の共有の鍵 ──

    /// die のクリップを時刻 start に始めた体（world は使わない）。
    def corpse(k: Kind, start: Float64): Creatures.Posed =
        { kind = k, group = 0, anim = { now = { clip = Creatures.Clip.Die, start = start }, before = None, switchedAt = -1000.0 }, world = Mat4.identity(), glow = 1.0 }

    /// die を過ぎた（最後のコマで止まった）2 体は、倒れた時刻が違っても同じ姿勢を共有する。
    @Test
    def testFinishedCorpsesShareOnePose(): Unit \ Assert =
        Assert.assertEq(expected = true,
            Creatures.sharesPose(Creatures.timingOf(Map.empty()), doc()#blendSeconds, 10.0, corpse(Kind.Melee, 0.0), corpse(Kind.Melee, 3.0)))

    /// 型の違う敵は同じ時刻でも姿勢を共有しない。
    @Test
    def testDifferentKindsDoNotSharePoses(): Unit \ Assert =
        Assert.assertEq(expected = false,
            Creatures.sharesPose(Creatures.timingOf(Map.empty()), doc()#blendSeconds, 10.0, corpse(Kind.Melee, 0.0), corpse(Kind.Ranged, 0.0)))
}
