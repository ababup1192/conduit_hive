// 囲まれた時の技の規則: スタミナの減りと戻り・息切れの間は走れない・緊急回避の距離と時間と i-frame と壁・蹴りの扇と押し返し・
// 手榴弾の放物線と跳ねと信管・爆発の範囲と傷・自分への傷・持てる数の上限と拾う・技と手榴弾の Doc の橋渡し。
mod TestMoves {
    use fge::{Num, Vec3}
    use Creatures.Kind
    use TestSupport.{eastRoom, healthIn, mazeOf, resWith, simulate, walkerIn}

    // ── 迷路と道具 ──

    /// 東西に長い部屋 A（x 4〜24 m・z 4〜16 m）。start は東の端（x 22 m・z 10 m）で西を向く。
    def room(): MazeDoc.Doc = mazeOf("#######" :: "#AAAAA#" :: "#AAAAA#" :: "#AAAAA#" :: "#######" :: Nil, 5, 2, 270.0)

    def moves(): MovesDoc.Rec = MovesDoc.rec(MovesDoc.defaults())

    def stamina(): MovesDoc.Stamina = moves()#stamina

    def grenade(): GrenadeDoc.Rec = GrenadeDoc.rec(GrenadeDoc.defaults())

    def walk(): WalkDoc.Rec = WalkDoc.rec(WalkDoc.defaults())

    def player(): PlayerDoc.Rec = PlayerDoc.rec(PlayerDoc.defaults())

    def dt(): Float64 = 1.0 / 60.0

    def west(): Float64 = Num.pi() * 1.5

    def idle(): World.Input = World.walking(Walker.idle())

    def pressing(drive: Walker.Drive, press: Moves.Press): World.Input = { moves = press | World.walking(drive) }

    def dodgeKey(): Moves.Press = Set#{Moves.Move.Dodge}

    /// melee の体力を health にした描く元（爆発の傷を体力の残りで読む）。
    def toughRes(health: Float64): Res.Res =
        let base = resWith(room());
        let d = EnemiesDoc.rec(base#enemies);
        Res.withEnemies(EnemiesDoc.Doc.Doc({ melee = { health = health | d#melee } | d }), base)

    /// melee を x・z に 1 体ずつ（番号は並びの順）。
    def meleesAt(r: Res.Res, at: List[(Float64, Float64)]): Horde.Horde =
        Horde.spawnNow(r, at |> List.map(p -> { kind = Kind.Melee, x = fst(p), z = snd(p), yaw = Num.pi() * 0.5, home = 'A' }), Horde.empty())

    def healthOf(id: Int32, h: Horde.Horde): Option[Float64] = Horde.enemyOf(id, h) |> Option.map(e -> e#health)

    /// 部屋の天井（4 m）の下の飛ぶ周り。
    def roomOf(r: Res.Res): Grenades.Room = { collision = r#collision, ceilingAt = (_, _) -> 4.0 }

    /// 時刻 0 に点 at から速さ velocity で飛び始めた 1 つだけの手榴弾。
    def flying(at: Vec3.Vec3, velocity: Vec3.Vec3): Grenades.State =
        { flying = { id = 0, at = at, velocity = velocity, born = 0.0, angle = 0.0, spin = 0.0, heading = 0.0 } :: Nil | Grenades.initial(grenade()) }

    def onlyOf(s: Grenades.State): Option[Grenades.Grenade] = List.head(s#flying)

    // ── スタミナ ──

    /// 満タンから 1 秒走ると sprintPerSecond だけ減る。
    @Test
    def testSprintDrainsStamina(): Unit \ Assert =
        Assert.assertEq(expected = stamina()#max - stamina()#sprintPerSecond, Stamina.sprinted(stamina(), 1.0, 1.0, Stamina.full(stamina()))#points)

    /// 最後に使ってから regenDelay の間は戻らず、過ぎたら 1 秒で regenPerSecond 戻る（残り 10 から）。並びは（間の内, 過ぎた後）。
    @Test
    def testStaminaRestsOnlyAfterTheDelay(): Unit \ Assert =
        let used = { points = 10.0, usedAt = 0.0, exhausted = false };
        Assert.assertEq(expected = (10.0, 10.0 + stamina()#regenPerSecond),
            (Stamina.rested(stamina(), stamina()#regenDelay * 0.5, 1.0, used)#points, Stamina.rested(stamina(), stamina()#regenDelay, 1.0, used)#points))

    /// 0 まで走り切ると息切れし、resumeAt に届くまで息切れのまま。並びは（走り切った, resumeAt の 1 手前まで戻った, resumeAt まで戻った）。
    @Test
    def testExhaustionLastsUntilResume(): Unit \ Assert =
        let out = Stamina.sprinted(stamina(), 0.0, stamina()#max / stamina()#sprintPerSecond, Stamina.full(stamina()));
        let after = (seconds: Float64) -> Stamina.rested(stamina(), stamina()#regenDelay, seconds, out)#exhausted;
        Assert.assertEq(expected = (true, true, false),
            (out#exhausted, after((stamina()#resumeAt - 1.0) / stamina()#regenPerSecond), after(stamina()#resumeAt / stamina()#regenPerSecond)))

    /// 息切れの間は Shift を押していても歩く速さで進む（1 秒前へ。始めは x 6 m の東向き・東の壁は x 16 m）。
    @Test
    def testExhaustedCannotSprint(): Unit \ Assert =
        let r = resWith(eastRoom());
        let tired = World.mapMoves(m -> { stamina = { points = 0.0, usedAt = 0.0, exhausted = true } | m }, World.initial(r));
        let ran = simulate(r, World.walking({ forward = 1.0, sprint = true | Walker.idle() }), World.walking({ forward = 1.0, sprint = true | Walker.idle() }), dt(), 60, tired);
        Assert.assertTrue(walkerIn(ran) |> Option.exists(b -> Float64.abs(b#x - (6.0 + walk()#walkSpeed)) < 0.01))

    // ── 緊急回避 ──

    /// 前へ回避すると seconds の内に distance だけ跳ぶ（始めは x 6 m の東向き。seconds を越えて 30 コマ進めても距離は増えない）。
    @Test
    def testDodgeCoversItsDistance(): Unit \ Assert =
        let r = resWith(eastRoom());
        let after = simulate(r, pressing({ forward = 1.0 | Walker.idle() }, dodgeKey()), idle(), dt(), 30, World.initial(r));
        Assert.assertTrue(walkerIn(after) |> Option.exists(b -> Float64.abs(b#x - (6.0 + moves()#dodge#distance)) < 0.01))

    /// 跳んでいるのは跳び始めから seconds の間だけ。並びは（終わりの 0.01 秒前, 終わり）。
    @Test
    def testDodgeLastsItsSeconds(): Unit \ Assert =
        let d = moves()#dodge;
        let m = { dodge = Some({ at = 0.0, dx = 1.0, dz = 0.0 }) | Moves.initial(moves()) };
        Assert.assertEq(expected = (true, false), (Moves.isDodging(d, d#seconds - 0.01, m), Moves.isDodging(d, d#seconds, m)))

    /// 何も押さずに回避すると後ろ（西の壁 x 4 m の方）へ跳び、壁で止まって食い込まない。並びは（体の真ん中が壁から半径の内に来ない, 食い込みが 1 mm 未満）。
    @Test
    def testDodgeStopsAtTheWall(): Unit \ Assert =
        let r = resWith(eastRoom());
        let after = simulate(r, pressing(Walker.idle(), dodgeKey()), idle(), dt(), 30, World.initial(r));
        Assert.assertEq(expected = Some((true, true)),
            walkerIn(after) |> Option.map(b -> (b#x >= 4.0 + walk()#radius - 0.001, Walker.overlapDepth(r#collision, walk(), b) < 0.001)))

    /// i-frame の間は攻撃が当たらない: 回避を押したコマに start の印（x 6 m・z 6 m）の床で手榴弾が爆発しても体力は減らず
    /// （1 コマで跳ぶのは 0.5 m 足らずで selfRadius の内）、押していなければ減る。並びは（回避した, 回避していない）の体力が最大のままか。
    @Test
    def testIframeIgnoresDamage(): Unit \ Assert =
        let r = resWith(eastRoom());
        let blast = (w: World.World) -> World.detonate(r, Vec3.v3(6.0, 0.06, 6.0), World.seconds(w), w);
        let dodged = blast(simulate(r, pressing(Walker.idle(), dodgeKey()), idle(), dt(), 1, World.initial(r)));
        let stood = blast(simulate(r, idle(), idle(), dt(), 1, World.initial(r)));
        Assert.assertEq(expected = (Some(true), Some(false)),
            (healthIn(dodged) |> Option.map(h -> h#points == player()#health), healthIn(stood) |> Option.map(h -> h#points == player()#health)))

    /// スタミナが cost より少なければ跳べない（Tired）。
    @Test
    def testDodgeNeedsStamina(): Unit \ Assert =
        let low = { stamina = { points = moves()#dodge#cost - 1.0, usedAt = 0.0, exhausted = false } | Moves.initial(moves()) };
        Assert.assertEq(expected = Err(Moves.Refusal.Tired) |> Result.map(_ -> ()), Moves.dodge(moves()#dodge, 1.0, dt(), (1.0, 0.0), low) |> Result.map(_ -> ()))

    // ── 蹴り ──

    /// 東の端（x 22 m）で西を向いて蹴る。
    def kickAt(t: Float64): Horde.Kick = { t = t, x = 22.0, z = 10.0, yaw = west(), doc = moves()#kick }

    /// 前（西）1.5 m の敵は傷を受け、後ろ（東）1.5 m の敵は受けない（体力 1000）。並びは（前, 後ろ）の体力。
    @Test
    def testKickHitsOnlyTheFan(): Unit \ Assert =
        let r = toughRes(1000.0);
        let kicked = Horde.kick(r, kickAt(0.0), meleesAt(r, (20.5, 10.0) :: (23.5, 10.0) :: Nil))#horde;
        Assert.assertEq(expected = (Some(1000.0 - moves()#kick#damage), Some(1000.0)), (healthOf(0, kicked), healthOf(1, kicked)))

    /// 蹴られた敵は 0.3 秒で push × pushDecay の半分より遠くへ押し返される（前 1.5 m の敵・体力 1000）。
    @Test
    def testKickPushesBack(): Unit \ Assert =
        let r = toughRes(1000.0);
        let k = moves()#kick;
        let kicked = Horde.kick(r, kickAt(0.0), meleesAt(r, (20.5, 10.0) :: Nil))#horde;
        let body = { x = 22.0, feet = 0.0, z = 10.0, eye = Vec3.v3(22.0, walk()#eyeHeight, 10.0), yaw = west(), radius = walk()#radius, height = walk()#height };
        let after = Horde.simulate(r, 0.0, 0.05, 6, body, kicked)#horde;
        Assert.assertTrue(Horde.enemyOf(0, after) |> Option.exists(e -> e#x < 20.5 - k#push * k#pushDecay * 0.5))

    /// 傷が kick の damage 以下しか残っていない敵は蹴りで倒れる。
    @Test
    def testKickFellsAWeakEnemy(): Unit \ Assert =
        let r = toughRes(moves()#kick#damage);
        Assert.assertEq(expected = 1, List.length(Horde.kick(r, kickAt(0.0), meleesAt(r, (20.5, 10.0) :: Nil))#fallen))

    // ── 手榴弾の飛び方 ──

    /// 何にも当たらない間は放物線（x 8 m・高さ 2 m から東へ speed・上へ lift で 10 コマ）。
    @Test
    def testGrenadeFollowsAParabola(): Unit \ Assert =
        let r = resWith(room());
        let g = grenade();
        let t = 10.0 * dt();
        let after = Grenades.simulate(g, roomOf(r), 0.0, dt(), 10, flying(Vec3.v3(8.0, 2.0, 10.0), Vec3.v3(g#throwing#speed, g#throwing#lift, 0.0)));
        let expected = Vec3.v3(8.0 + g#throwing#speed * t, 2.0 + g#throwing#lift * t - 0.5 * g#flight#gravity * t * t, 10.0);
        Assert.assertTrue(onlyOf(after) |> Option.exists(x -> Vec3.length(Vec3.sub(x#at, expected)) < 0.001))

    /// 高さ 1 m から落とすと床で跳ね上がる（0.42 秒後に上へ向かい、床より上にいる）。
    @Test
    def testGrenadeBouncesOffTheFloor(): Unit \ Assert =
        let r = resWith(room());
        let after = Grenades.simulate(grenade(), roomOf(r), 0.0, dt(), 25, flying(Vec3.v3(12.0, 1.0, 10.0), Vec3.zero()));
        Assert.assertEq(expected = Some((true, true)), onlyOf(after) |> Option.map(x -> (x#velocity#y > 0.0, x#at#y > grenade()#flight#radius)))

    /// 西の壁（x 4 m）へ投げると跳ね返り、壁を抜けない（x 6 m から西へ speed で 15 コマ）。並びは（東へ向かう, 壁より内）。
    @Test
    def testGrenadeBouncesOffAWall(): Unit \ Assert =
        let r = resWith(room());
        let after = Grenades.simulate(grenade(), roomOf(r), 0.0, dt(), 15, flying(Vec3.v3(6.0, 1.5, 10.0), Vec3.v3(0.0 - grenade()#throwing#speed, 0.0, 0.0)));
        Assert.assertEq(expected = Some((true, true)), onlyOf(after) |> Option.map(x -> (x#velocity#x > 0.0, x#at#x >= 4.0)))

    /// 信管が尽きたコマに爆発して列から外れる。並びは（fuse の 1 コマ前の爆発の数, fuse のコマの爆発の数）。
    @Test
    def testGrenadeExplodesAtTheFuse(): Unit \ Assert =
        let r = resWith(room());
        let s = flying(Vec3.v3(12.0, 0.06, 10.0), Vec3.zero());
        let fuse = grenade()#flight#fuse;
        Assert.assertEq(expected = (0, 1),
            (List.length(Grenades.step(grenade(), roomOf(r), fuse - dt(), dt(), s)#blasts), List.length(Grenades.step(grenade(), roomOf(r), fuse, dt(), s)#blasts)))

    // ── 爆発 ──

    def blastAt(x: Float64): Horde.Blast = { t = 0.0, point = Vec3.v3(x, 0.06, 10.0), doc = grenade()#blast, seed = 0 }

    /// 半径の半分の敵は真ん中と縁の傷の間の半分の傷を受け、半径の外の敵は受けない（体力 1000・爆発は x 14 m）。並びは（半分の所, 外）の体力。
    @Test
    def testBlastDamageFallsOffToTheEdge(): Unit \ Assert =
        let r = toughRes(1000.0);
        let b = grenade()#blast;
        let hit = Horde.blast(r, blastAt(14.0), meleesAt(r, (14.0 - b#radius * 0.5, 10.0) :: (14.0 + b#radius + 1.0, 10.0) :: Nil))#horde;
        Assert.assertTrue(
            healthOf(0, hit) |> Option.exists(h -> Float64.abs(h - (1000.0 - (b#damage + b#edgeDamage) * 0.5)) < 0.001) and healthOf(1, hit) == Some(1000.0))

    /// 倒した敵のうち gibRadius の内は弾け、外は吹っ飛ぶ（体力 1・爆発は x 14 m）。並びは（弾けた数, 倒れた数）。
    @Test
    def testBlastBurstsOnlyCloseEnemies(): Unit \ Assert =
        let r = toughRes(1.0);
        let b = grenade()#blast;
        let hit = Horde.blast(r, blastAt(14.0), meleesAt(r, (14.0 - b#gibRadius * 0.5, 10.0) :: (14.0 + (b#gibRadius + b#radius) * 0.5, 10.0) :: Nil));
        Assert.assertEq(expected = (1, 2), (List.length(hit#burst), List.length(hit#fallen)))

    /// 自分の傷は真ん中で selfDamage・selfRadius で 0。
    @Test
    def testSelfDamageFallsToZeroAtTheRadius(): Unit \ Assert =
        let b = grenade()#blast;
        Assert.assertEq(expected = (b#selfDamage, 0.0), (Grenades.selfDamageAt(b, 0.0), Grenades.selfDamageAt(b, b#selfRadius)))

    /// 足元の爆発では自分も傷を受け、selfRadius より遠い爆発では受けない（start は x 6 m・東の壁は x 16 m）。並びは（足元, 遠く）の体力が最大のままか。
    @Test
    def testOwnBlastHurtsOnlyWhenClose(): Unit \ Assert =
        let r = resWith(eastRoom());
        let w = World.initial(r);
        let near = World.detonate(r, Vec3.v3(6.0, 0.06, 6.0), 0.0, w);
        let far = World.detonate(r, Vec3.v3(6.0 + grenade()#blast#selfRadius + 1.5, 0.06, 6.0), 0.0, w);
        Assert.assertEq(expected = (Some(false), Some(true)),
            (healthIn(near) |> Option.map(h -> h#points == player()#health), healthIn(far) |> Option.map(h -> h#points == player()#health)))

    // ── 持てる数と拾う ──

    /// 上限まで持っていれば足せず、0 から上限より多く足すと上限で止まる。並びは（上限から, 0 から max + 5）。
    @Test
    def testCarryStopsAtTheMax(): Unit \ Assert =
        let g = grenade();
        let full = { carried = g#carry#max | Grenades.initial(g) };
        let empty = { carried = 0 | Grenades.initial(g) };
        Assert.assertEq(expected = (None, Some(g#carry#max)),
            (Grenades.add(g, 1, full) |> Option.map(s -> s#carried), Grenades.add(g, g#carry#max + 5, empty) |> Option.map(s -> s#carried)))

    /// 手榴弾を持っていなければ投げられない。
    @Test
    def testCannotThrowWithoutGrenades(): Unit \ Assert =
        let empty = { carried = 0 | Grenades.initial(grenade()) };
        Assert.assertEq(expected = None, Grenades.toss(grenade(), 1.0, Vec3.zero(), Vec3.v3(1.0, 0.0, 0.0), empty) |> Option.map(s -> s#carried))

    /// 通路の手榴弾の印（x 10 m）の上に立つと拾い、持っている数が pickups.json の量だけ増える（max で止まる）。
    @Test
    def testGrenadePickupAddsToTheCarry(): Unit \ Assert =
        let base = MazeDoc.rec(mazeOf("#######" :: "#AAAAA#" :: "#######" :: Nil, 1, 1, 90.0));
        let lane = MazeDoc.Doc.Doc({ marks = { kind = MazeDoc.MarkKind.Pickup, name = "grenade", col = 2, row = 1, yaw = 0.0 } :: base#marks | base });
        let r = resWith(lane);
        let g = grenade();
        let start = { carried = 0 | Grenades.initial(g) };
        let amount = Map.getWithDefault("grenade", 0, PickupsDoc.rec(r#pickups)#amounts);
        let w = World.placeWalker(r, { x = 10.0, z = 6.0 }, 90.0, 0.0, World.initial(r));
        let picked = simulate(r, idle(), idle(), dt(), 1, w |> mapGrenades(start));
        Assert.assertEq(expected = Some(Int32.min(g#carry#max, amount)), World.sessionOf(picked) |> Option.map(s -> World.grenadesOf(s)#carried))

    def mapGrenades(s: Grenades.State, w: World.World): World.World = World.mapGrenades(_ -> s, w)

    // ── Doc の橋渡し ──

    @Test
    def testMovesBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(MovesDoc.fromJson("{ broken")))

    /// dodge の 1 欄だけを上書きすると、ほかの欄は既定のまま。
    @Test
    def testMovesOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((2.5, moves()#dodge#seconds)),
            MovesDoc.fromJson("{\"dodge\": {\"distance\": 2.5}}") |> Option.map(d -> (MovesDoc.rec(d)#dodge#distance, MovesDoc.rec(d)#dodge#seconds)))

    @Test
    def testGrenadeBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(GrenadeDoc.fromJson("{ broken")))

    /// JSON の throw の塊の 1 欄だけを上書きすると、ほかの欄は既定のまま。
    @Test
    def testGrenadeOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((20.0, grenade()#throwing#lift)),
            GrenadeDoc.fromJson("{\"throw\": {\"speed\": 20.0}}") |> Option.map(d -> (GrenadeDoc.rec(d)#throwing#speed, GrenadeDoc.rec(d)#throwing#lift)))
}
