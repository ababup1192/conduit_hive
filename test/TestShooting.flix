// 撃つ規則: 弾の当たり（壁で止まる・的の柱に当たる）・連射の間隔・弾の数・持ち替え・粒の寿命・腕と銃の glb の銃口。
mod TestShooting {
    use fge::{Gltf, Mat4, Pose3d, Skin3d, Vec3}
    use TestSupport.{arsenalIn, cameraIn, clockOf, mazeOf, particlesIn, resWith}
    use WeaponsDoc.Weapon

    // ── 迷路 ──

    /// 西の部屋 A（x 4〜24 m・z 4〜16 m）と、壁 1 マスを挟んだ東の通路 B（x 28〜32 m）。
    /// 最後の部屋は A で、的の柱は A の真ん中のマス（列 3・行 2）から 2 マス西の列 1・行 2（真ん中 x = 6 m・z = 10 m）。
    /// start は A の東の端（列 5・行 2 = x 22 m・z 10 m）で西を向く。
    def twoRooms(): MazeDoc.Doc =
        mazeOf("#########" :: "#AAAAA#B#" :: "#AAAAA#B#" :: "#AAAAA#B#" :: "#########" :: Nil, 5, 2, 270.0)

    def weapons(): WeaponsDoc.Doc = WeaponsDoc.defaults()

    def pistol(): WeaponsDoc.Stats = WeaponsDoc.statsOf(Weapon.Pistol, weapons())

    def vm(): FpViewmodelDoc.Rec = FpViewmodelDoc.rec(FpViewmodelDoc.defaults())

    /// 散弾銃と連射銃も始めから持っている Doc。
    def armed(): WeaponsDoc.Doc =
        let d = WeaponsDoc.rec(weapons());
        WeaponsDoc.Doc.Doc({ shotgun = { owned = true | d#shotgun }, rifle = { owned = true | d#rifle } | d })

    def struckOf(hits: List[Hitscan.Impact]): List[Hitscan.Struck] = hits |> List.map(h -> h#struck)

    // ── 弾の当たり ──

    /// start から西を向いて撃つと、間の床の上を飛んで的の柱（番号 0）に当たる。当たる点は柱の東の面（x = 6 + 0.5 m）。
    @Test
    def testShotHitsThePillar(): Unit \ Assert =
        let res = resWith(twoRooms());
        let hits = cameraIn(res, World.initial(res)) |> Option.map(c -> Hitscan.fire(res#hitTargets, c, pistol(), 0));
        Assert.assertEq(expected = Some((Hitscan.Struck.Prop(0) :: Nil, true)),
            hits |> Option.map(hs -> (struckOf(hs), hs |> List.forAll(h -> Float64.abs(h#point#x - 6.5) < 0.001))))

    /// 東の通路 B（x = 30 m）から西を向いて撃つと、A との間の壁の東の面（x = 28 m）で止まり、壁の向こうの柱には当たらない。
    @Test
    def testWallStopsTheShot(): Unit \ Assert =
        let res = resWith(twoRooms());
        let w = World.placeWalker(res, { x = 30.0, z = 10.0 }, 270.0, 0.0, World.initial(res));
        let hits = cameraIn(res, w) |> Option.map(c -> Hitscan.fire(res#hitTargets, c, pistol(), 0));
        Assert.assertEq(expected = Some((Hitscan.Struck.Wall :: Nil, true)),
            hits |> Option.map(hs -> (struckOf(hs), hs |> List.forAll(h -> Float64.abs(h#point#x - 28.0) < 0.001))))

    /// 散弾は Doc の粒の数だけレイを飛ばす（間の広い部屋なら全部どこかに当たる）。
    @Test
    def testShotgunFiresEveryPellet(): Unit \ Assert =
        let res = resWith(twoRooms());
        let shotgun = WeaponsDoc.statsOf(Weapon.Shotgun, weapons());
        Assert.assertEq(expected = Some(shotgun#pellets),
            cameraIn(res, World.initial(res)) |> Option.map(c -> List.length(Hitscan.fire(res#hitTargets, c, shotgun, 0))))

    // ── 連射の間隔と弾の数 ──

    /// 撃ってから間隔の半分では撃てず、間隔が過ぎると撃てる（拳銃の interval は Doc の値）。
    @Test
    def testPistolWaitsForTheInterval(): Unit \ Assert =
        let interval = pistol()#interval;
        let fired = Arsenal.fire(weapons(), 0.0, 1.0 / 60.0, Arsenal.initial(weapons()));
        Assert.assertEq(expected = (false, true),
            (Arsenal.canFire(weapons(), interval * 0.5, fired), Arsenal.canFire(weapons(), interval, fired)))

    /// 拳銃の弾は無限（撃っても数が出ない）・連射銃は 1 回撃つと Doc の始めの弾から 1 つ減る。
    @Test
    def testAmmoCountsDownExceptForThePistol(): Unit \ Assert =
        let a = Arsenal.initial(armed());
        let rifle = Arsenal.equip(vm(), 0.0, Arsenal.Choice.Slot(Weapon.Rifle), a);
        let start = WeaponsDoc.statsOf(Weapon.Rifle, armed())#ammo;
        Assert.assertEq(expected = (None, Some(start - 1)),
            (Arsenal.ammoOf(armed(), Arsenal.fire(armed(), 0.0, 1.0 / 60.0, a)), Arsenal.ammoOf(armed(), Arsenal.fire(armed(), 1.0, 1.0 / 60.0, rifle))))

    /// 弾が 0 の武器は、間隔が過ぎても撃てない。
    @Test
    def testEmptyWeaponCannotFire(): Unit \ Assert =
        let a = Arsenal.equip(vm(), 0.0, Arsenal.Choice.Slot(Weapon.Shotgun), Arsenal.initial(armed()));
        Assert.assertEq(expected = false, Arsenal.canFire(armed(), 100.0, { ammo = Map.insert(Weapon.Shotgun, 0, a#ammo) | a }))

    /// 連射銃は押している間撃ち続け、拳銃は押したコマだけ撃つ。
    @Test
    def testOnlyAutomaticWeaponsFireWhileHeld(): Unit \ Assert =
        let holding = { pressed = false, held = true };
        Assert.assertEq(expected = (false, true),
            (Arsenal.wantsToFire(pistol(), holding), Arsenal.wantsToFire(WeaponsDoc.statsOf(Weapon.Rifle, weapons()), holding)))

    // ── 持ち替え ──

    /// 持っていない武器（始めの散弾銃）へは替わらない（拳銃のまま）。
    @Test
    def testSwitchingNeedsTheWeapon(): Unit \ Assert =
        Assert.assertEq(expected = Weapon.Pistol, Arsenal.equip(vm(), 0.0, Arsenal.Choice.Slot(Weapon.Shotgun), Arsenal.initial(weapons()))#current)

    /// 持っていれば替わり、持ち替えの間（drawSeconds の半分）は撃てず、drawSeconds で撃てる。
    @Test
    def testSwitchingTakesTheDrawTime(): Unit \ Assert =
        let switched = Arsenal.equip(vm(), 0.0, Arsenal.Choice.Slot(Weapon.Shotgun), Arsenal.initial(armed()));
        Assert.assertEq(expected = (Weapon.Shotgun, false, true),
            (switched#current, Arsenal.canFire(armed(), vm()#drawSeconds * 0.5, switched), Arsenal.canFire(armed(), vm()#drawSeconds, switched)))

    /// ホイールの次・前は持っている武器の並びを回る（拳銃 → 散弾銃・拳銃の前は連射銃）。
    @Test
    def testWheelCyclesThroughOwnedWeapons(): Unit \ Assert =
        let a = Arsenal.initial(armed());
        Assert.assertEq(expected = (Weapon.Shotgun, Weapon.Rifle),
            (Arsenal.equip(vm(), 0.0, Arsenal.Choice.Next, a)#current, Arsenal.equip(vm(), 0.0, Arsenal.Choice.Previous, a)#current))

    // ── 撃った 1 コマ ──

    /// 引き金を引いた 1 コマで 1 回撃ち、銃口にマズルフラッシュの粒・柱に火花の粒が Doc の数だけ出る（拳銃は 1 粒）。
    @Test
    def testFiringStepEmitsFlashAndSparks(): Unit \ Assert =
        let res = resWith(twoRooms());
        let pdoc = Particles3dDoc.rec(res#particles);
        let input = { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) };
        let after = World.step(res, input, { play = clockOf(1.0 / 60.0) | World.initial(res) });
        Assert.assertEq(expected = Some((1, pdoc#muzzle#count + pdoc#spark#count)),
            forM (a <- arsenalIn(after); ps <- particlesIn(after)) yield (a#shots, List.length(ps)))

    // ── 粒の寿命 ──

    /// 火花は寿命の一番短い粒（life × (1 − lifeJitter)）の手前まで全部見えていて、life で全部消える。
    @Test
    def testSparksLiveForTheDocLife(): Unit \ Assert =
        let doc = Particles3dDoc.defaults();
        let spark = Particles3dDoc.rec(doc)#spark;
        let ps = Particles3d.emit(doc, Particles3d.Kind.Spark, Particles3d.Space.World, Vec3.zero(), Vec3.v3(0.0, 1.0, 0.0), 0.0, 0);
        let shortest = spark#life * (1.0 - spark#lifeJitter);
        Assert.assertEq(expected = (spark#count, 0),
            (List.length(Particles3d.step(shortest * 0.99, ps)), List.length(Particles3d.step(spark#life, ps))))

    // ── 腕と銃の glb ──

    /// 拳銃の glb の銃口: 休みの姿勢の gun のジョイントの行列 × MUZZLE の局所の行列の原点が、Blender で置いた MUZZLE の点
    /// （engine の座標で (0.038, −0.043, 0.399) m）に 2 mm の内で重なる。
    @Test
    def testPistolMuzzleSitsAtTheBlenderPoint(): Unit \ {Assert, Fs.FileRead} =
        let path = FpViewmodel.pathOf(Weapon.Pistol);
        let rig = Gltf.load(path) |> Result.flatMap(FpViewmodel.viewmodelOf(path));
        let muzzle = rig |> Result.map(r -> FpViewmodel.muzzleAt(r, Pose3d.compute(r#skin, Skin3d.restPose(r#skin)), Mat4.identity()));
        Assert.assertEq(expected = Ok(true),
            muzzle |> Result.map(m -> Vec3.length(Vec3.sub(m, Vec3.v3(0.038, -0.043, 0.399))) < 0.002))
}
