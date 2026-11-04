// JSON 橋渡しのテスト（1 Doc につき最大 3 本まで。同型の重複は書かない）。
mod TestDocs {
    use fge::{GameEngine, LogCapture}

    @Test
    def testMazeBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(MazeDoc.fromJson("{ broken")))

    /// 印の種類の綴りが引けない行は置かず、1 行知らせる（start の行は残る）。
    @Test
    def testMazeDropsAnUnknownMarkKind(): Unit \ {Assert, IO} =
        let (doc, lines) = LogCapture.capture(() ->
            MazeDoc.fromJson("{\"rows\":[\"###\",\"#A#\",\"###\"],\"marks\":[{\"kind\":\"start\",\"x\":1,\"y\":1},{\"kind\":\"spawnn\",\"x\":1,\"y\":1}]}"));
        Assert.assertEq(expected = (Some(1), 1), (doc |> Option.map(d -> List.length(MazeDoc.rec(d)#marks)), List.length(lines)))

    /// zones の行の無い区画の高さは wallHeight（1 欄だけ上書きした値が入る）。
    @Test
    def testMazeWallHeightFillsMissingZones(): Unit \ Assert =
        Assert.assertEq(expected = Some(Some(7.0)),
            MazeDoc.fromJson("{\"wallHeight\":7.0,\"rows\":[\"###\",\"#A#\",\"###\"]}")
                |> Option.map(d -> Maze.build(10.0, d)#zones |> Map.get('A') |> Option.map(z -> z#height)))

    @Test
    def testWalkOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((9.0, WalkDoc.rec(WalkDoc.defaults())#walkSpeed)),
            WalkDoc.fromJson("{\"version\":1, \"runSpeed\": 9.0}") |> Option.map(d -> (WalkDoc.rec(d)#runSpeed, WalkDoc.rec(d)#walkSpeed)))

    @Test
    def testLookOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some(30.0), LookDoc.fromJson("{\"fogFar\": 30.0}") |> Option.map(d -> LookDoc.rec(d)#fogFar))

    @Test
    def testLookBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(LookDoc.fromJson("{oops")))

    @Test
    def testKeysBrokenFallsBack(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(KeysDoc.fromJson("{oops")))

    /// 書き間違い("Sinistra")はその 1 個だけ落ちる。全部知らない名前で空になった操作(sprint)だけ既定へ落ちる。
    @Test
    def testKeysDropsUnknownNameAndEmptyActionFallsBack(): Unit \ Assert =
        Assert.assertEq(
            expected = Some((GameEngine.Key.Q :: Nil, KeysDoc.rec(KeysDoc.defaults())#sprint)),
            KeysDoc.fromJson("{\"left\": [\"Q\", \"Sinistra\"], \"sprint\": [\"Hop\"]}")
                |> Option.map(d -> (KeysDoc.rec(d)#left, KeysDoc.rec(d)#sprint)))

    @Test
    def testUiTextBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(UiTextDoc.fromJson("{ broken")))

    @Test
    def testWeaponsBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(WeaponsDoc.fromJson("{ broken")))

    /// 武器の欄の 1 つだけを上書きすると、その武器のほかの欄とほかの武器は既定のまま。
    @Test
    def testWeaponsOverrideOneField(): Unit \ Assert =
        let d = WeaponsDoc.rec(WeaponsDoc.defaults());
        Assert.assertEq(expected = Some((0.5, d#shotgun#damage, d#rifle#interval)),
            WeaponsDoc.fromJson("{\"shotgun\": {\"interval\": 0.5}}")
                |> Option.map(x -> (WeaponsDoc.rec(x)#shotgun#interval, WeaponsDoc.rec(x)#shotgun#damage, WeaponsDoc.rec(x)#rifle#interval)))

    @Test
    def testViewmodelOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((40.0, FpViewmodelDoc.rec(FpViewmodelDoc.defaults())#near)),
            FpViewmodelDoc.fromJson("{\"fovY\": 40.0}") |> Option.map(d -> (FpViewmodelDoc.rec(d)#fovY, FpViewmodelDoc.rec(d)#near)))

    /// 粒の欄の 1 つだけを上書きすると、同じ粒のほかの欄は既定のまま。
    @Test
    def testParticlesOverrideOneField(): Unit \ Assert =
        let d = Particles3dDoc.rec(Particles3dDoc.defaults());
        Assert.assertEq(expected = Some((3, d#spark#life)),
            Particles3dDoc.fromJson("{\"spark\": {\"count\": 3}}") |> Option.map(x -> (Particles3dDoc.rec(x)#spark#count, Particles3dDoc.rec(x)#spark#life)))

    @Test
    def testEnemiesBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(EnemiesDoc.fromJson("{ broken")))

    /// 型の欄の 1 つだけを上書きすると、同じ型のほかの欄とほかの型は既定のまま。
    @Test
    def testEnemiesOverrideOneField(): Unit \ Assert =
        let d = EnemiesDoc.rec(EnemiesDoc.defaults());
        Assert.assertEq(expected = Some((5.0, d#melee#health, d#ranged#speed)),
            EnemiesDoc.fromJson("{\"melee\": {\"speed\": 5.0}}")
                |> Option.map(x -> (EnemiesDoc.rec(x)#melee#speed, EnemiesDoc.rec(x)#melee#health, EnemiesDoc.rec(x)#ranged#speed)))

    /// wave は書いた行だけになり（既定の wave は混ざらない）、区画が 1 文字でない行は捨て、書かない欄は 0 と None。
    @Test
    def testSpawnsWavesFollowTheRows(): Unit \ Assert =
        Assert.assertEq(expected = Some((1, Some(('B', 7, 0, Some('A'), 0.0, 0)))),
            SpawnsDoc.fromJson("{\"waves\": [{\"zone\": \"B\", \"from\": \"A\", \"melee\": 7}, {\"zone\": \"BB\", \"melee\": 3}]}")
                |> Option.map(x -> SpawnsDoc.rec(x)#waves)
                |> Option.map(waves -> (List.length(waves), List.head(waves) |> Option.map(w -> (w#zone, w#melee, w#ranged, w#source, w#after, w#whenLeft)))))

    @Test
    def testPlayerBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(PlayerDoc.fromJson("{ broken")))

    /// 欄の 1 つだけを上書きすると、ほかの欄は既定のまま。
    @Test
    def testPlayerOverridesOneField(): Unit \ Assert =
        Assert.assertEq(expected = Some((80.0, PlayerDoc.rec(PlayerDoc.defaults())#respawnSeconds)),
            PlayerDoc.fromJson("{\"health\": 80.0}") |> Option.map(d -> (PlayerDoc.rec(d)#health, PlayerDoc.rec(d)#respawnSeconds)))

    @Test
    def testPickupsBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(PickupsDoc.fromJson("{ broken")))

    /// 拾う距離だけを上書きすると、ほかの欄と量は既定のまま。
    @Test
    def testPickupsOverrideOneField(): Unit \ Assert =
        let d = PickupsDoc.rec(PickupsDoc.defaults());
        Assert.assertEq(expected = Some((2.0, d#hover, d#amounts)),
            PickupsDoc.fromJson("{\"radius\": 2.0}") |> Option.map(x -> (PickupsDoc.rec(x)#radius, PickupsDoc.rec(x)#hover, PickupsDoc.rec(x)#amounts)))

    /// items と dropItems の行の数に追随する（items は量のない行を捨てる・dropItems は 1 行なら 1 つで、書かない量は 0）。
    @Test
    def testPickupsItemsFollowTheRows(): Unit \ Assert =
        Assert.assertEq(expected = Some((Map#{"health_small" => 10, "ammo_rifle" => 30}, Map#{"ammo_rifle" => (2.0, 0)})),
            PickupsDoc.fromJson("{\"items\": {\"health_small\": {\"amount\": 10}, \"ammo_rifle\": {\"amount\": 30}, \"weapon_rifle\": {}}, \"dropItems\": {\"ammo_rifle\": {\"weight\": 2.0}}}")
                |> Option.map(x -> (PickupsDoc.rec(x)#amounts, PickupsDoc.rec(x)#dropItems |> Map.map(i -> (i#weight, i#amount)))))

    /// 操作の一覧は行の数に追随する（key の無い行は捨てる）。
    @Test
    def testUiTextControlsFollowTheRows(): Unit \ Assert =
        let controls = UiTextDoc.fromJson("{\"controls\": [{\"key\": \"F\", \"action\": \"USE\"}, {\"action\": \"NOTHING\"}]}") |> Option.map(x -> UiTextDoc.rec(x)#controls);
        Assert.assertEq(expected = Some((1, Some(("F", "USE")))),
            controls |> Option.map(cs -> (List.length(cs), List.head(cs) |> Option.map(c -> (c#key, c#action)))))

    @Test
    def testTourBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(TourDoc.fromJson("{ broken")))

    /// 点の weapon の auto は、敵との距離で選ぶ（None）。
    @Test
    def testTourAutoWeaponIsNone(): Unit \ Assert =
        let text = "{\"points\": [{\"x\": 1.0, \"z\": 2.0, \"weapon\": \"auto\"}]}";
        Assert.assertEq(expected = Some(None), TourDoc.fromJson(text) |> Option.flatMap(d -> List.head(TourDoc.rec(d)#points)) |> Option.map(p -> p#weapon))

    @Test
    def testSoundsBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true, Option.isEmpty(SoundsDoc.fromJson("{ broken")))

    /// 跳弾の割合だけを上書きすると、ほかの欄と音ごとの量は既定のまま。
    @Test
    def testSoundsOverrideOneField(): Unit \ Assert =
        let d = SoundsDoc.rec(SoundsDoc.defaults());
        Assert.assertEq(expected = Some((0.9, d#pumpDelay, d#levels)),
            SoundsDoc.fromJson("{\"ricochetChance\": 0.9}") |> Option.map(x -> (SoundsDoc.rec(x)#ricochetChance, SoundsDoc.rec(x)#pumpDelay, SoundsDoc.rec(x)#levels)))

    /// variants と zones の行に追随する（zones は 1 文字の鍵だけ・書かない量は通路の既定）。
    @Test
    def testSoundsCatalogsFollowTheRows(): Unit \ Assert =
        let d = SoundsDoc.rec(SoundsDoc.defaults());
        Assert.assertEq(expected = Some((Map#{"shell" => 2}, Map#{'B' => (0.5, d#corridor#vent, d#corridor#pipes)})),
            SoundsDoc.fromJson("{\"variants\": {\"shell\": {\"count\": 2}}, \"zones\": {\"B\": {\"machine\": 0.5}, \"BB\": {}}}")
                |> Option.map(x -> (SoundsDoc.rec(x)#variants, SoundsDoc.rec(x)#zones |> Map.map(z -> (z#machine, z#vent, z#pipes)))))
}
