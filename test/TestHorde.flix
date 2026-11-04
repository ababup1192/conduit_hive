// 敵の規則（Horde・Creatures の口を直に）: 当たり判定（体・頭・壁の向こう）・ダメージと倒れる・よろけの間隔・spawn（印 → spawns の数）・
// 押し合い・距離の地図で近づく・melee の当たる時刻と扇・ranged の見通しと吐く上限・projectile・姿勢の共有の鍵。
mod TestHorde {
    use fge::{Camera3d, LogCapture, Mat4, Num, Vec3}
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
        { x = x, feet = 0.0, z = z, eye = Vec3.v3(x, walk()#eyeHeight, z), radius = walk()#radius, height = walk()#height }

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

    def damaged(t: Float64, amount: Float64, part: Hitscan.Part, h: Horde.Horde): Horde.Horde = Horde.applyDamage(res(), t, amount, impactOn(part), h)#horde

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
        Assert.assertEq(expected = true, Horde.aliveCount(Horde.applyDamage(res(), 0.0, shotgun#damage, impacts, crowd)#horde) <= 3)

    // ── ダメージと倒れる ──

    /// 体に拳銃 1 発: 体力が威力だけ減る。
    @Test
    def testBodyShotTakesTheWeaponDamage(): Unit \ Assert =
        Assert.assertEq(expected = Some(doc()#melee#health - pistol()#damage), healthOf(damaged(1.0, pistol()#damage, Hitscan.Part.Body, meleeAt12())))

    /// 体に拳銃 1 発: 追っている途中ならよろける。
    @Test
    def testBodyShotStaggers(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Hurt(1.0)), actOf(damaged(1.0, pistol()#damage, Hitscan.Part.Body, meleeAt12())))

    /// 頭は威力 × headMultiplier: 体力 ÷ 倍率の威力の弾 1 粒で倒れる。
    @Test
    def testHeadShotMultipliesTheDamage(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Dying(1.0)),
            actOf(damaged(1.0, doc()#melee#health / doc()#headMultiplier, Hitscan.Part.Head, meleeAt12())))

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

    // ── spawn ──

    /// 部屋 A（x 4〜24 m・z 4〜12 m）だけの迷路。start は西の端（x 6 m・z 10 m）で東を向く。marks に spawn の印を足す。
    def roomMaze(spawns: List[MazeDoc.Mark]): MazeDoc.Doc =
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'A',
                          rows = "#######" :: "#AAAAA#" :: "#AAAAA#" :: "#######" :: Nil,
                          zones = { id = 'A', name = "room", kind = MazeDoc.ZoneKind.Room, height = 4.0 } :: Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = 1, row = 1, yaw = 90.0 } :: spawns })

    def spawnMark(name: String, col: Int32, row: Int32): MazeDoc.Mark = { kind = MazeDoc.MarkKind.Spawn, name = name, col = col, row = row, yaw = 0.0 }

    /// spawns.json の既定の pack の群れの数。
    def packSize(): Option[Int32] = Map.get("pack", SpawnsDoc.rec(SpawnsDoc.defaults())#groups) |> Option.map(g -> g#melee + g#ranged)

    def packRes(): Res.Res = resWith(roomMaze(spawnMark("pack", 4, 1) :: spawnMark("pack", 5, 2) :: Nil))

    /// spawns.json に無い名前の印は 1 行知らせて置かない（pack の印 1 つだけが残る）。
    @Test
    def testUnknownSpawnNameIsReportedAndDropped(): Unit \ {Assert, IO} =
        let (r, lines) = LogCapture.capture(() -> resWith(roomMaze(spawnMark("pack", 4, 1) :: spawnMark("nope", 3, 2) :: Nil)));
        Assert.assertEq(expected = (1, 1), (List.length(lines), List.length(r#spawnPoints)))

    /// pack の印 2 つの部屋に入ると、pack 2 つ分が湧く予定になる。
    @Test
    def testEnteringARoomSchedulesTheMarkedGroups(): Unit \ Assert =
        Assert.assertEq(expected = packSize() |> Option.map(n -> 2 * n), Some(List.length(Horde.enter(packRes(), 'A', 0.0, Horde.empty())#pending)))

    /// もう一度入っても予定を足さない（1 部屋 1 回だけ）。
    @Test
    def testEnteringTwiceSpawnsOnce(): Unit \ Assert =
        let twice = Horde.enter(packRes(), 'A', 1.0, Horde.enter(packRes(), 'A', 0.0, Horde.empty()));
        Assert.assertEq(expected = packSize() |> Option.map(n -> 2 * n), Some(List.length(twice#pending)))

    /// 予定の時刻を過ぎた（60 秒後の）コマには全部出ている。
    @Test
    def testScheduledEnemiesAppearByTheirTime(): Unit \ Assert =
        let entered = Horde.enter(packRes(), 'A', 0.0, Horde.empty());
        Assert.assertEq(expected = packSize() |> Option.map(n -> 2 * n), Some(Horde.aliveCount(Horde.step(packRes(), 60.0, 0.1, playerAt(6.0, 10.0), entered)#horde)))

    // ── 押し合い ──

    /// 同じ点に立った melee 2 体は、1 コマで押し合いの半径の和まで離れる。
    @Test
    def testTwoEnemiesOnOnePointArePushedApart(): Unit \ Assert =
        let both = Horde.spawnNow(res(), { kind = Kind.Melee, x = 12.0, z = 10.0, yaw = 0.0, home = 'A' } :: { kind = Kind.Melee, x = 12.0, z = 10.0, yaw = 0.0, home = 'A' } :: Nil, Horde.empty());
        let after = Horde.step(res(), 0.1, 1.0 / 60.0, playerAt(22.0, 10.0), both)#horde;
        let gap = forM (a <- Horde.enemyOf(0, after); b <- Horde.enemyOf(1, after)) yield Num.sqrt((a#x - b#x) * (a#x - b#x) + (a#z - b#z) * (a#z - b#z));
        Assert.assertEq(expected = Some(true), gap |> Option.map(g -> g >= Creatures.footprintOf(Kind.Melee) * 2.0 - 0.001))

    // ── 距離の地図で近づく ──

    /// U の字の迷路: 西の脚の下（x 6 m・z 6 m）の melee は、間の壁を回って東の脚の下（x 14 m・z 6 m）のプレイヤーへ着く
    /// （壁を回る道は 20 m ほど・melee の速さ 3 m/秒で 7 秒ほど。9 秒進めて、地図の上でプレイヤーのマスか隣にいる）。
    @Test
    def testMeleeWalksAroundTheWallByTheField(): Unit \ Assert =
        let r = resWith(mazeOf("#####" :: "#AAA#" :: "#A#A#" :: "#A#A#" :: "#####" :: Nil, 3, 3, 0.0));
        let o = Horde.simulate(r, 0.0, 0.05, 180, playerAt(14.0, 6.0), oneAt(r, Kind.Melee, 6.0, 6.0, 0.0));
        Assert.assertEq(expected = Some(true),
            Horde.enemyOf(0, o#horde) |> Option.flatMap(e -> FlowField.stepsAt(o#horde#field, Maze.cellAt(r#maze, e#x, e#z))) |> Option.map(s -> s <= 1))

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

    /// 同じ部屋（12 m 先）で見通しがあれば 1 コマ目に吐き始める。
    @Test
    def testRangedAttacksWithLineOfSight(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Attack(0.1, false)), rangedActAfterOneFrame(playerAt(22.0, 10.0)))

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
        { kind = k, group = 0, anim = { now = { clip = Creatures.Clip.Die, start = start }, before = None, switchedAt = -1000.0 }, world = Mat4.identity() }

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
