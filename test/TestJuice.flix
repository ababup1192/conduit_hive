// 撃った・倒した時の手応えの規則: 弾ける条件（Gibs.bursts）・吹っ飛ぶ向きと強さと壁（Knockback・Horde）・粒と肉片と曳光弾の上限・
// melee の飛びかかりの当たり・ranged の溜めの時間・hit stop（World.paceOf）・手応えの Doc の橋渡し。
mod TestJuice {
    use fge::{Clock, Num, Vec3}
    use Creatures.Kind
    use TestSupport.{clockAt, mazeOf, resWith}

    // ── 迷路と道具 ──

    /// 東西に長い部屋 A（x 4〜24 m・z 4〜16 m）。start は東の端（x 22 m・z 10 m）で西を向く。
    def room(): MazeDoc.Doc = mazeOf("#######" :: "#AAAAA#" :: "#AAAAA#" :: "#AAAAA#" :: "#######" :: Nil, 5, 2, 270.0)

    def res(): Res.Res = resWith(room())

    def enemies(): EnemiesDoc.Rec = EnemiesDoc.rec(EnemiesDoc.defaults())

    def juice(): JuiceDoc.Rec = JuiceDoc.rec(JuiceDoc.defaults())

    def gib(): JuiceDoc.Gib = juice()#gib

    def east(): Float64 = Num.pi() * 0.5

    def west(): Float64 = Num.pi() * 1.5

    /// 足元 (x, z) に立つプレイヤー（体の寸法は歩く Doc の既定）。
    def playerAt(x: Float64, z: Float64): PlayerBody.PlayerBody =
        let walk = WalkDoc.rec(WalkDoc.defaults());
        { x = x, feet = 0.0, z = z, eye = Vec3.v3(x, walk#eyeHeight, z), yaw = west(), radius = walk#radius, height = walk#height }

    /// 型 k の 1 体（番号 0）を x・z に、向き yaw で立たせた群れ。
    def oneAt(k: Kind, x: Float64, z: Float64, yaw: Float64): Horde.Horde =
        Horde.spawnNow(res(), { kind = k, x = x, z = z, yaw = yaw, home = 'A' } :: Nil, Horde.empty())

    /// 時刻 0 に、点 (fromX, 1.6, 10) から武器 w の威力 damage の弾を、番号 0 の敵の体に 1 粒当てた群れ。
    def shotFrom(w: WeaponsDoc.Weapon, fromX: Float64, damage: Float64, h: Horde.Horde): Horde.Horde =
        Horde.applyDamage(res(), { t = 0.0, damage = damage, weapon = w, origin = Vec3.v3(fromX, 1.6, 10.0), index = 0 },
            { struck = Hitscan.Struck.Enemy(0, Hitscan.Part.Body), point = Vec3.zero(), normal = Vec3.zero() } :: Nil, h)#horde

    /// 刻み 0.05 秒で frames コマ進めた群れ（プレイヤーは東の端）。
    def after(frames: Int32, h: Horde.Horde): Horde.Outcome = Horde.simulate(res(), 0.0, 0.05, frames, playerAt(22.0, 10.0), h)

    def xOf(h: Horde.Horde): Option[Float64] = Horde.enemyOf(0, h) |> Option.map(e -> e#x)

    def cause(w: WeaponsDoc.Weapon, distance: Float64, head: Float64, overkill: Float64): Gibs.Cause =
        { weapon = w, distance = distance, headDamage = head, overkill = overkill }

    // ── 弾ける条件 ──

    /// 散弾銃で shotgunRange ちょうどの近さなら、確率の内（roll 0）で弾ける。
    @Test
    def testShotgunAtCloseRangeBursts(): Unit \ Assert =
        Assert.assertEq(expected = true, Gibs.bursts(gib(), cause(WeaponsDoc.Weapon.Shotgun, gib()#shotgunRange, 0.0, 0.0), 0.0))

    /// 散弾銃でも shotgunRange より遠ければ、ほかの条件が無い限り弾けない。
    @Test
    def testShotgunBeyondRangeDoesNotBurst(): Unit \ Assert =
        Assert.assertEq(expected = false, Gibs.bursts(gib(), cause(WeaponsDoc.Weapon.Shotgun, gib()#shotgunRange + 1.0, 0.0, 0.0), 0.0))

    /// 頭に headDamage の威力なら弾け、1 だけ弱いと弾けない（拳銃・遠く・余剰なし）。
    @Test
    def testStrongHeadShotBursts(): Unit \ Assert =
        Assert.assertEq(expected = (true, false),
            (Gibs.bursts(gib(), cause(WeaponsDoc.Weapon.Pistol, 30.0, gib()#headDamage, 0.0), 0.0),
             Gibs.bursts(gib(), cause(WeaponsDoc.Weapon.Pistol, 30.0, gib()#headDamage - 1.0, 0.0), 0.0)))

    /// 体力を overkill 以上超える一撃なら弾ける（連射銃・遠く・体）。
    @Test
    def testOverkillBursts(): Unit \ Assert =
        Assert.assertEq(expected = true, Gibs.bursts(gib(), cause(WeaponsDoc.Weapon.Rifle, 30.0, 0.0, gib()#overkill), 0.0))

    /// 条件に当たっても、roll が確率を超えると弾けない（3 つの条件の確率のどれより上の 1 に近い roll）。
    @Test
    def testRollAboveTheChanceDoesNotBurst(): Unit \ Assert =
        Assert.assertEq(expected = false, Gibs.bursts(gib(), cause(WeaponsDoc.Weapon.Shotgun, 0.0, gib()#headDamage, gib()#overkill), 0.999))

    /// 弾けた敵は群れから消える（散弾銃を 1 m から・体力を overkill 超える威力。番号 0 と撃った回 0 の roll は確率の内）。
    @Test
    def testBurstEnemyLeavesTheHorde(): Unit \ Assert =
        Assert.assertEq(expected = 0,
            List.length(shotFrom(WeaponsDoc.Weapon.Shotgun, 13.0, enemies()#melee#health + gib()#overkill, oneAt(Kind.Melee, 12.0, 10.0, east()))#enemies))

    // ── 吹っ飛ぶ ──

    /// 東（x 22 m）から拳銃でちょうど倒すと、体は撃たれた向き（西）へ飛ぶ（0.5 秒後に x が 12 m より小さい）。
    @Test
    def testFallenBodyFliesAwayFromTheShooter(): Unit \ Assert =
        let fallen = shotFrom(WeaponsDoc.Weapon.Pistol, 22.0, enemies()#melee#health, oneAt(Kind.Melee, 12.0, 10.0, east()));
        Assert.assertEq(expected = Some(true), xOf(after(10, fallen)#horde) |> Option.map(x -> x < 12.0))

    /// 飛び出す横の速さは武器ごとの値 × 近さの倍率: 散弾銃を 0 m は closeBoost 倍・拳銃を closeRange の遠さは 1 倍。
    @Test
    def testFlingIsStrongerForACloseShotgun(): Unit \ Assert =
        let fl = juice()#fling;
        let away = (d: Float64) -> { dx = 1.0, dz = 0.0, distance = d };
        Assert.assertEq(expected = (fl#speed#shotgun * fl#closeBoost, fl#speed#pistol),
            (Knockback.launch(fl, WeaponsDoc.Weapon.Shotgun, away(0.0), 0.0)#speed0, Knockback.launch(fl, WeaponsDoc.Weapon.Pistol, away(fl#closeRange), 0.0)#speed0))

    /// 西の壁（x 4 m）の 1.5 m 手前の敵を 2.5 m 東から拳銃で倒すと、壁が無ければ 3 m ほど飛ぶが、壁の手前で止まる（2 秒後に x が 4 m より大きい）。
    @Test
    def testFlungBodyStopsAtTheWall(): Unit \ Assert =
        let fallen = shotFrom(WeaponsDoc.Weapon.Pistol, 8.0, enemies()#melee#health, oneAt(Kind.Melee, 5.5, 10.0, east()));
        Assert.assertEq(expected = Some(true), xOf(after(40, fallen)#horde) |> Option.map(x -> x > 4.0))

    /// 生き残った敵は撃たれた向き（西）へ押される（0.25 秒後に x が 12 m より小さい）。
    @Test
    def testSurvivorIsPushedAway(): Unit \ Assert =
        let hurt = shotFrom(WeaponsDoc.Weapon.Pistol, 22.0, 10.0, oneAt(Kind.Melee, 12.0, 10.0, west()));
        Assert.assertEq(expected = Some(true), xOf(Horde.simulate(res(), 0.0, 0.05, 5, playerAt(22.0, 10.0), hurt)#horde) |> Option.map(x -> x < 12.0))

    /// 弾けた体（群れから消える）と、吹っ飛んで滑っている体は、生きている数（maxAlive の数え）に入らない。
    /// 並びは（滑っている体を残した 0.25 秒後の数, 弾けた直後の数）。
    @Test
    def testBurstAndFlungBodiesAreNotAlive(): Unit \ Assert =
        let flung = shotFrom(WeaponsDoc.Weapon.Pistol, 22.0, enemies()#melee#health, oneAt(Kind.Melee, 12.0, 10.0, east()));
        let burst = shotFrom(WeaponsDoc.Weapon.Shotgun, 13.0, enemies()#melee#health + gib()#overkill, oneAt(Kind.Melee, 12.0, 10.0, east()));
        Assert.assertEq(expected = (0, 0), (Horde.aliveCount(after(5, flung)#horde), Horde.aliveCount(burst)))

    // ── 上限 ──

    /// 粒は上限（Doc の limit）を越えると古い物から消える: 上限を火花 1 回の数にして、時刻 0 の火花の上へ時刻 1 の火花を足すと、時刻 1 の火花だけが残る。
    @Test
    def testParticlesDropTheOldestPastTheLimit(): Unit \ Assert =
        let base = Particles3dDoc.rec(Particles3dDoc.defaults());
        let doc = Particles3dDoc.Doc.Doc({ limit = base#spark#count | base });
        let old = Particles3d.emit(doc, Particles3d.Kind.Spark, Particles3d.Space.World, Vec3.zero(), Vec3.v3(0.0, 1.0, 0.0), 0.0, 1);
        let fresh = Particles3d.emit(doc, Particles3d.Kind.Spark, Particles3d.Space.World, Vec3.zero(), Vec3.v3(0.0, 1.0, 0.0), 1.0, 2);
        let kept = Particles3d.added(doc, fresh, old);
        Assert.assertEq(expected = (base#spark#count, Some(1.0)), (List.length(kept), List.last(kept) |> Option.map(p -> p#born)))

    /// 肉片は上限を越えると古い物から消える: 1 回に 4 つ・上限 4 で 2 回弾けると、2 回目の 4 つだけが残る。
    @Test
    def testGibsDropTheOldestPastTheLimit(): Unit \ Assert =
        let g = { countMin = 4, countMax = 4, limit = 4 | gib() };
        let art = Gibs.artOf(None);
        let twice = Gibs.empty() |> Gibs.burst(g, art, 0.0, 1, Vec3.v3(0.0, 1.0, 0.0), 1.0, 0.0) |> Gibs.burst(g, art, 1.0, 2, Vec3.v3(0.0, 1.0, 0.0), 1.0, 0.0);
        Assert.assertEq(expected = (4, Some(1.0)), (List.length(twice#pieces), List.last(twice#pieces) |> Option.map(p -> p#born)))

    /// 曳光弾は上限を越えると古い物から消える: 上限 2 に 3 本足すと、新しい 2 本。
    @Test
    def testTracersDropTheOldestPastTheLimit(): Unit \ Assert =
        let doc = { limit = 2 | Particles3dDoc.rec(Particles3dDoc.defaults())#tracer };
        let tr = (t: Float64) -> { origin = Vec3.zero(), target = Vec3.v3(0.0, 0.0, 10.0), born = t };
        let kept = Nil |> Tracers.add(doc, tr(0.0)) |> Tracers.add(doc, tr(1.0)) |> Tracers.add(doc, tr(2.0));
        Assert.assertEq(expected = (2, Some(2.0), Some(1.0)), (List.length(kept), List.head(kept) |> Option.map(x -> x#born), List.last(kept) |> Option.map(x -> x#born)))

    /// 曳光弾は尻が着く点に追いつくと消える: 10 m 先へ撃って (10 + length) ÷ speed 秒の後は残らない。
    @Test
    def testTracerVanishesAfterReachingTheTarget(): Unit \ Assert =
        let doc = Particles3dDoc.rec(Particles3dDoc.defaults())#tracer;
        let tr = { origin = Vec3.zero(), target = Vec3.v3(0.0, 0.0, 10.0), born = 0.0 };
        Assert.assertEq(expected = 0, List.length(Tracers.step(doc, (10.0 + doc#length) / doc#speed, tr :: Nil)))

    // ── 飛びかかり・溜め ──

    /// lungeRange の内（4 m 先）の melee は 1 コマ目に飛びかかる。
    @Test
    def testMeleeLungesInsideTheLungeRange(): Unit \ Assert =
        Assert.assertEq(expected = Some(Horde.Act.Lunge(0.05)), Horde.enemyOf(0, after(1, oneAt(Kind.Melee, 18.0, 10.0, east()))#horde) |> Option.map(e -> e#act))

    /// 4 m 先から飛びかかると、歩くだけなら届かない 1.2 秒の内に振り下ろしが当たる（歩けば 2.5 m に 0.83 秒 + hitTime 0.5 秒）。
    @Test
    def testLungeLandsTheSwing(): Unit \ Assert =
        Assert.assertEq(expected = enemies()#melee#damage, after(24, oneAt(Kind.Melee, 18.0, 10.0, east()))#damage)

    /// ranged は溜め（chargeSeconds）と attack の hitTime を合わせた時刻までは吐かず、その 2 コマ後には吐いている（並びは（前, 後））。
    @Test
    def testRangedSpitsOnlyAfterTheCharge(): Unit \ Assert =
        let r = enemies()#ranged;
        let frames = Num.floorInt((r#chargeSeconds + r#hitTime) / 0.05);
        let spat = (n: Int32) -> List.memberOf(Events.Event.Spit, after(n, oneAt(Kind.Ranged, 10.0, 10.0, east()))#events);
        Assert.assertEq(expected = (false, true), (spat(frames), spat(frames + 2)))

    // ── hit stop ──

    /// 部屋 A で拳銃 1 発で倒せる melee を 1 発で倒すコマ: 群れの最後の 1 体なら、次の 1/60 秒は遊びの時計が止まる。
    /// もう 1 体が生き残っていれば（1 体しか倒していない）止まらず 1/60 秒進む。並びは（最後の 1 体, 生き残りあり）の進んだ秒。
    @Test
    def testHitStopFreezesOnTheLastKill(): Unit \ Assert =
        let pistol = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Pistol, WeaponsDoc.defaults());
        let r = { enemies = EnemiesDoc.Doc.Doc({ melee = { health = pistol#damage | enemies()#melee } | enemies() }) | res() };
        let melee = (x: Float64, z: Float64) -> { kind = Kind.Melee, x = x, z = z, yaw = east(), home = 'A' };
        let fire = (spawns: List[{ kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }]) -> {
            let w = World.mapHorde(Horde.spawnNow(r, spawns), World.initial(r));
            let shot = World.step(r, { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) }, { play = clockAt(0.05, 0.05) | w });
            Clock.secondsOf(Clock.nowOf(Clock.advance(World.paceOf(r, shot), 1.0 / 60.0, shot#play))) - 0.05
        };
        let rounded = (v: Float64) -> Num.roundInt(v * 6000.0);
        Assert.assertEq(expected = (0, 100), (rounded(fire(melee(12.0, 10.0) :: Nil)), rounded(fire(melee(12.0, 10.0) :: melee(8.0, 14.0) :: Nil))))

    // ── Doc の橋渡し ──

    @Test
    def testJuiceBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(JuiceDoc.fromJson("{ broken")))

    /// 塊の欄の 1 つだけを上書きすると、同じ塊のほかの欄は既定のまま（弾けた瞬間の光は gibLight の塊から gib へ入る）。
    @Test
    def testJuiceOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((2.0, gib()#shotgunRange, 9.0, juice()#shake#fire#shotgun)),
            JuiceDoc.fromJson("{\"gib\": {\"countMin\": 2}, \"gibLight\": {\"lightRange\": 9.0}}")
                |> Option.map(x -> { let g = JuiceDoc.rec(x)#gib; (Int32.toFloat64(g#countMin), g#shotgunRange, g#lightRange, JuiceDoc.rec(x)#shake#fire#shotgun) }))
}
