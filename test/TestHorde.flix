// 敵の規則: 当たり判定（体・頭・壁の向こう）・ダメージと倒れる・spawn（印 → spawns の数）・押し合い・距離の地図で近づく・
// melee の当たる時刻と扇・ranged の見通し・projectile・プレイヤーが倒れてやり直す。
mod TestHorde {
    use fge::{Camera3d, LogCapture, Num, Vec3}
    use Creatures.Kind
    use TestSupport.{clockAt, mazeOf, resWith}

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
    def playerAt(x: Float64, z: Float64): Horde.Player =
        { x = x, feet = 0.0, z = z, eye = Vec3.v3(x, walk()#eyeHeight, z), radius = walk()#radius, height = walk()#height }

    /// 型 k の 1 体（番号 0）を x・z に、向き yaw（ラジアン）で立たせた群れ。
    def oneAt(r: Res.Res, k: Kind, x: Float64, z: Float64, yaw: Float64): Horde.Horde =
        Horde.spawnNow(r, { kind = k, x = x, z = z, yaw = yaw, home = 'A' } :: Nil, Horde.empty())

    /// 目 (x, y, 10) から西をまっすぐ見るカメラ。
    def westCamera(x: Float64, y: Float64): Camera3d.Camera3d =
        { eye = Vec3.v3(x, y, 10.0), yaw = west(), pitch = 0.0, fovY = 1.0, near = 0.05, far = 60.0 }

    def struckOf(h: Horde.Horde, camera: Camera3d.Camera3d): List[Hitscan.Struck] =
        Hitscan.fire(List.append(Horde.targetsOf(h), res()#hitTargets), camera, pistol(), 0) |> List.map(i -> i#struck)

    def impactOn(part: Hitscan.Part): List[Hitscan.Impact] =
        { struck = Hitscan.Struck.Enemy(0, part), point = Vec3.zero(), normal = Vec3.zero() } :: Nil

    def actOf(h: Horde.Horde): Option[(Float64, Horde.Act)] = Horde.enemyOf(0, h) |> Option.map(e -> (e#health, e#act))

    // ── 当たり判定 ──

    /// x = 12 m で東を向く melee を西向きに撃つ: 頭の高さ（1.88 m。glb の頭の球の真ん中）は頭・腰の高さ（1 m）は体に当たる。
    /// 東の通路 B（x = 30 m）から撃つと、間の壁（x = 28 m）で止まり敵には当たらない。
    @Test
    def testShotsHitHeadBodyAndStopAtWalls(): Unit \ Assert =
        let h = oneAt(res(), Kind.Melee, 12.0, 10.0, east());
        Assert.assertEq(expected = (Hitscan.Struck.Enemy(0, Hitscan.Part.Head) :: Nil, Hitscan.Struck.Enemy(0, Hitscan.Part.Body) :: Nil, Hitscan.Struck.Wall :: Nil),
            (struckOf(h, westCamera(22.0, 1.88)), struckOf(h, westCamera(22.0, 1.0)), struckOf(h, westCamera(30.0, 1.0))))

    /// 倒れた敵は弾の的にならない（倒れる途中の体を撃っても後ろの的の柱に当たる）。
    @Test
    def testFallenEnemiesAreNotTargets(): Unit \ Assert =
        let fallen = Horde.wound(res(), 0.0, doc()#melee#health, impactOn(Hitscan.Part.Body), oneAt(res(), Kind.Melee, 12.0, 10.0, east()));
        Assert.assertEq(expected = Hitscan.Struck.Prop(0) :: Nil, struckOf(fallen, westCamera(22.0, 1.0)))

    /// 4 m 先に詰まった 5 体（前に 3 体・その間の後ろに 2 体）へ散弾銃を 1 回: 粒が群れに散り、2 体以上が倒れる（残るのは 3 体以下）。
    @Test
    def testShotgunFellsSeveralOfACloseCrowd(): Unit \ Assert =
        let at = (x: Float64, z: Float64) -> { kind = Kind.Melee, x = x, z = z, yaw = east(), home = 'A' };
        let crowd = Horde.spawnNow(res(), at(18.0, 9.2) :: at(18.0, 10.0) :: at(18.0, 10.8) :: at(17.2, 9.6) :: at(17.2, 10.4) :: Nil, Horde.empty());
        let shotgun = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Shotgun, WeaponsDoc.defaults());
        let impacts = Hitscan.fire(List.append(Horde.targetsOf(crowd), res()#hitTargets), westCamera(22.0, 1.4), shotgun, 0);
        Assert.assertEq(expected = true, Horde.aliveCount(Horde.wound(res(), 0.0, shotgun#damage, impacts, crowd)) <= 3)

    // ── ダメージと倒れる ──

    /// 体に拳銃 1 発: 体力が威力だけ減ってよろける。頭なら威力 × headMultiplier で、体力ちょうどの威力なら倒れる。
    @Test
    def testBodyShotStaggersAndHeadShotDoublesDamage(): Unit \ Assert =
        let h = oneAt(res(), Kind.Melee, 12.0, 10.0, east());
        let body = Horde.wound(res(), 1.0, pistol()#damage, impactOn(Hitscan.Part.Body), h);
        let head = Horde.wound(res(), 1.0, doc()#melee#health / doc()#headMultiplier, impactOn(Hitscan.Part.Head), h);
        Assert.assertEq(expected = (Some((doc()#melee#health - pistol()#damage, Horde.Act.Hurt(1.0))), Some((0.0, Horde.Act.Dying(1.0)))),
            (actOf(body), actOf(head)))

    /// 振り下ろしている途中の melee は撃たれてもよろけない（振りは止まらない）。
    @Test
    def testAttackIsNotInterruptedByAHit(): Unit \ Assert =
        let swinging = Horde.step(res(), 0.1, 0.1, playerAt(13.0, 10.0), oneAt(res(), Kind.Melee, 12.0, 10.0, east()))#horde;
        Assert.assertEq(expected = Some((doc()#melee#health - pistol()#damage, Horde.Act.Attack(0.1))),
            actOf(Horde.wound(res(), 0.2, pistol()#damage, impactOn(Hitscan.Part.Body), swinging)))

    /// 倒れた敵は corpseSeconds の間は残り、過ぎたコマに消える。
    @Test
    def testCorpseStaysForTheDocTime(): Unit \ Assert =
        let fallen = Horde.wound(res(), 0.0, doc()#melee#health, impactOn(Hitscan.Part.Body), oneAt(res(), Kind.Melee, 12.0, 10.0, east()));
        let far = playerAt(22.0, 10.0);
        Assert.assertEq(expected = (1, 0),
            (List.length(Horde.step(res(), doc()#corpseSeconds * 0.5, 0.1, far, fallen)#horde#enemies),
             List.length(Horde.step(res(), doc()#corpseSeconds, 0.1, far, fallen)#horde#enemies)))

    // ── spawn ──

    /// 部屋 A（x 4〜24 m・z 4〜12 m）だけの迷路。start は西の端（x 6 m・z 10 m）で東を向く。marks に spawn の印を足す。
    def roomMaze(spawns: List[MazeDoc.Mark]): MazeDoc.Doc =
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'A',
                          rows = "#######" :: "#AAAAA#" :: "#AAAAA#" :: "#######" :: Nil,
                          zones = { id = 'A', name = "room", kind = MazeDoc.ZoneKind.Room, height = 4.0 } :: Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = 1, row = 1, yaw = 90.0 } :: spawns })

    def spawnMark(name: String, col: Int32, row: Int32): MazeDoc.Mark = { kind = MazeDoc.MarkKind.Spawn, name = name, col = col, row = row, yaw = 0.0 }

    /// spawns.json の既定の pack の群れ。
    def pack(): Option[SpawnsDoc.Group] = Map.get("pack", SpawnsDoc.rec(SpawnsDoc.defaults())#groups)

    /// pack の印 2 つと、spawns.json に無い名前の印 1 つ: 無い名前は 1 行知らせて置かず、部屋に入ると pack 2 つ分が湧く予定になる。
    /// もう一度入っても足さない。予定の時刻を過ぎた（60 秒後の）コマには全部出ている。
    @Test
    def testEnteringARoomSpawnsTheMarkedGroupsOnce(): Unit \ {Assert, IO} =
        let (r, lines) = LogCapture.capture(() -> resWith(roomMaze(spawnMark("pack", 4, 1) :: spawnMark("pack", 5, 2) :: spawnMark("nope", 3, 2) :: Nil)));
        let entered = Horde.enter(r, 'A', 0.0, Horde.empty());
        let twice = Horde.enter(r, 'A', 1.0, entered);
        let later = Horde.step(r, 60.0, 0.1, playerAt(6.0, 10.0), twice)#horde;
        Assert.assertEq(expected = pack() |> Option.map(g -> (1, 2 * (g#melee + g#ranged), 2 * (g#melee + g#ranged), 2 * (g#melee + g#ranged))),
            Some((List.length(lines), List.length(entered#pending), List.length(twice#pending), Horde.aliveCount(later))))

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

    /// プレイヤーの 1 m 手前の melee: 1 コマ目に振り始め、始めてから hitTime の手前のコマまではダメージ 0・hitTime のコマに Doc の威力
    /// （刻みは hitTime の 1/4。始めたコマから 4 コマ目が hitTime）。
    @Test
    def testMeleeHitsAtTheDocTime(): Unit \ Assert =
        let dt = doc()#melee#hitTime / 4.0;
        let h = oneAt(res(), Kind.Melee, 13.0, 10.0, east());
        Assert.assertEq(expected = (0.0, doc()#melee#damage),
            (Horde.simulate(res(), 0.0, dt, 4, playerAt(14.0, 10.0), h)#damage, Horde.simulate(res(), 0.0, dt, 5, playerAt(14.0, 10.0), h)#damage))

    /// 振り下ろしの扇: 北を向く melee の 1 m 前は内・1 m 後ろは外・前でも reach と体の半径より 0.2 m 遠ければ外。
    @Test
    def testMeleeSwingCoversTheFrontArc(): Unit \ Assert =
        let m = doc()#melee;
        Assert.assertEq(expected = Some((true, false, false)),
            Horde.enemyOf(0, oneAt(res(), Kind.Melee, 10.0, 10.0, 0.0)) |> Option.map(e ->
                (Horde.isInSwing(m, e, playerAt(10.0, 11.0)), Horde.isInSwing(m, e, playerAt(10.0, 9.0)),
                 Horde.isInSwing(m, e, playerAt(10.0, 10.0 + m#reach + walk()#radius + 0.2)))))

    // ── ranged ──

    /// ranged は見通しがある時だけ吐き始める: 同じ部屋（12 m 先）なら 1 コマ目に attack・間に壁がある通路 B（16 m 先）なら追うまま。
    @Test
    def testRangedAttacksOnlyWithLineOfSight(): Unit \ Assert =
        let actAfter = (player: Horde.Player) -> Horde.step(res(), 0.1, 0.1, player, oneAt(res(), Kind.Ranged, 10.0, 10.0, east()))#horde |> actOf;
        Assert.assertEq(expected = (Some(Horde.Act.Attack(0.1)), Some(Horde.Act.Chase)),
            (actAfter(playerAt(22.0, 10.0)) |> Option.map(snd), actAfter(playerAt(30.0, 10.0)) |> Option.map(snd)))

    /// 西の壁（x = 4 m）の 1 m 手前から西へ飛ぶ projectile は壁で弾けて消え（ダメージ 0）、プレイヤーへ飛ぶ物は当たって Doc の威力。
    @Test
    def testProjectileBurstsOnWallsAndHurtsThePlayer(): Unit \ Assert =
        let speed = doc()#projectile#speed;
        let atWall = Horde.simulate(res(), 0.0, 0.05, 4, playerAt(22.0, 10.0), Horde.launch(Vec3.v3(5.0, 1.5, 14.0), Vec3.v3(0.0 - speed, 0.0, 0.0), 0.0, Horde.empty()));
        let atPlayer = Horde.simulate(res(), 0.0, 0.05, 20, playerAt(22.0, 10.0), Horde.launch(Vec3.v3(18.0, 1.5, 10.0), Vec3.v3(speed, 0.0, 0.0), 0.0, Horde.empty()));
        Assert.assertEq(expected = ((0, 1, 0.0), (0, doc()#projectile#damage)),
            ((List.length(atWall#horde#projectiles), List.length(atWall#splashes), atWall#damage),
             (List.length(atPlayer#horde#projectiles), atPlayer#damage)))

    // ── 倒れてやり直す ──

    /// 体力 5 の Doc で、部屋 A に入ったコマに 1 m 前の melee が振り始め、hitTime のコマの 1 撃（威力 10）で倒れる。
    /// respawnSeconds の後のコマに、入った所（start の x 6 m・z 10 m）で体力を満たして立ち、敵は消えている。次のコマに部屋へ入り直して pack が湧き直す。
    @Test
    def testDeathRespawnsAtTheRoomEntranceAndRearmsTheRoom(): Unit \ Assert =
        let base = resWith(roomMaze(spawnMark("pack", 5, 2) :: Nil));
        let r = { enemies = EnemiesDoc.Doc.Doc({ playerHealth = 5.0 | doc() }) | base };
        let idle = World.walking(Walker.idle());
        let hit = doc()#melee#hitTime;
        let w0 = World.withHorde(oneAt(r, Kind.Melee, 7.0, 10.0, west()), World.initial(r));
        let swung = World.step(r, idle, { play = clockAt(0.125, 0.125) | w0 });
        let down = World.step(r, idle, { play = clockAt(0.125 + hit, 0.05) | swung });
        let back = World.step(r, idle, { play = clockAt(0.125 + hit + doc()#respawnSeconds, 0.05) | down });
        let again = World.step(r, idle, { play = clockAt(0.175 + hit + doc()#respawnSeconds, 0.05) | back });
        Assert.assertEq(expected = pack() |> Option.map(g -> (true, 5.0, 0, (6.0, 10.0), g#melee + g#ranged)),
            Some((Health.isDown(World.healthOf(down)), World.healthOf(back)#points, Horde.aliveCount(World.hordeOf(back)),
                  (World.walkerOf(back)#x, World.walkerOf(back)#z), Horde.aliveCount(World.hordeOf(again)) + List.length(World.hordeOf(again)#pending))))
}
