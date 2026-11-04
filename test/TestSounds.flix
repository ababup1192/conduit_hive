// 音（Sounds）: 起きた事 → 音の名前・変化が回る・同じ種類をコマに重ねすぎない・mixer の cooldown・唸りの距離・ポーズの環境音・薬莢の遅れ。
mod TestSounds {
    use fge::{AudioMixer, AudioMixerDoc}
    use Creatures.Kind
    use Events.Event
    use TestSupport.{clockAt, eastRoom, eventsIn, resWith}

    // ── 道具 ──

    def res(): Res.Res = resWith(eastRoom())

    def sounds(): SoundsDoc.Rec = SoundsDoc.rec(res()#sounds)

    /// 遊ぶ時と同じ音の通り道（conduit_hive.mixer.json に sounds の levels を足した物）。
    def mixer(): AudioMixer.Mixer \ Fs.FileRead = Res.withMixer(AudioMixerDoc.load(AudioMixer.defaults(), Controls.mixerPath()), res())#mixer

    def idle(): World.Input = World.walking(Walker.idle())

    def pulling(): World.Input = { trigger = { pressed = true, held = true } | idle() }

    def at(t: Float64, w: World.World): World.World = { play = clockAt(t, 0.05) | w }

    /// 体（start は x 6 m・z 6 m で東向き）から東へ dx m の所に melee を 1 体置いた World の場面。
    def withMeleeAhead(dx: Float64): Option[World.Session] =
        let r = res();
        World.initial(r) |> World.mapHorde(h -> Horde.spawnNow(r, { kind = Kind.Melee, x = 6.0 + dx, z = 6.0, yaw = 0.0, home = 'A' } :: Nil, h)) |> World.sessionOf

    // ── 起きた事 → 音の名前 ──

    /// 出来事ごとの音の頭: 武器ごとの銃声・薬莢・先台・拾う物の種類・持ち替えた先の武器・最後の部屋の扉だけ重い扉・wave の警報。
    @Test
    def testEventsMapToSoundFamilies(): Unit \ Assert =
        let of = Sounds.familyOf('H');
        Assert.assertEq(expected = "shot_rifle" :: "shell" :: "shotgun_pump" :: "pickup_ammo" :: "shotgun_pump" :: "door" :: "door_heavy" :: "alarm" :: "enemy_hit" :: Nil,
            of(Event.Fired(WeaponsDoc.Weapon.Rifle)) :: of(Event.ShellLanded(WeaponsDoc.Weapon.Pistol)) :: of(Event.Pumped)
                :: of(Event.PickedUp(Pickups.Kind.AmmoRifle)) :: of(Event.Switched(WeaponsDoc.Weapon.Shotgun)) :: of(Event.RoomTriggered('A'))
                :: of(Event.RoomTriggered('H')) :: of(Event.WaveStarted('H', 0)) :: of(Event.EnemyHit(Kind.Ranged, Hitscan.Part.Head)) :: Nil)

    /// 変化は 1 番から順に回り、変化の数で 1 番へ戻る（数は Doc の variants）。変化の無い頭はそのままの名前。
    @Test
    def testVariantsRotateAndWrap(): Unit \ Assert =
        let n = Map.getWithDefault("shot_rifle", 0, sounds()#variants);
        Assert.assertEq(expected = ("shot_rifle_1", "shot_rifle_2", "shot_rifle_1", "alarm"),
            (Sounds.variantOf(sounds(), "shot_rifle", 0), Sounds.variantOf(sounds(), "shot_rifle", 1), Sounds.variantOf(sounds(), "shot_rifle", n),
             Sounds.variantOf(sounds(), "alarm", 5)))

    /// 撃った音は撃った回数の順に変化を回す: 続けて 2 回撃つと 1 番・2 番。
    @Test
    def testConsecutiveShotsUseTheNextVariant(): Unit \ Assert =
        let r = res();
        let first = World.step(r, pulling(), at(0.05, World.initial(r)));
        let start2 = at(1.05, first);
        let second = World.step(r, pulling(), start2);
        Assert.assertEq(expected = (true, true),
            (List.memberOf("shot_pistol_1", Sounds.events(r, at(0.05, World.initial(r)), first)), List.memberOf("shot_pistol_2", Sounds.events(r, start2, second))))

    // ── 重ねすぎない ──

    /// 同じ種類の音はコマに maxPerFamily まで（並びの前から残し、ほかの種類は数えない）。
    @Test
    def testSameFamilyIsLimitedPerFrame(): Unit \ Assert =
        let picks = ("enemy_hit", "enemy_hit_1") :: ("enemy_hit", "enemy_hit_2") :: ("enemy_hit", "enemy_hit_3") :: ("shell", "shell_1") :: Nil;
        Assert.assertEq(expected = "enemy_hit_1" :: "enemy_hit_2" :: "shell_1" :: Nil, Sounds.limitPerFamily(2, picks))

    /// mixer の cooldown: 叫びが鳴ってから cooldown の半分の秒の内にもう一度来ても鳴らさない（秒は conduit_hive.mixer.json）。
    @Test
    def testCooldownDropsARepeatWithinTheDocSeconds(): Unit \ {Assert, Fs.FileRead} =
        let m = mixer();
        let (first, state) = AudioMixer.step(m, _ -> 3.0, 0.016, "enemy_scream_1" :: Nil, Nil, AudioMixer.initial());
        let (again, _) = AudioMixer.step(m, _ -> 3.0, AudioMixer.cooldownOf(m, "enemy_scream_1") * 0.5, "enemy_scream_1" :: Nil, Nil, state);
        Assert.assertEq(expected = ("enemy_scream_1" :: Nil, Nil), (first, again))

    /// 連射銃の音は音ごとの量（levels）で子のバスへ流れ、そのバスの音量は親の gun のバス × 量（数は Doc）。
    @Test
    def testRifleLevelScalesItsBus(): Unit \ {Assert, Fs.FileRead} =
        let m = mixer();
        Assert.assertEq(expected = ("gun.shot_rifle", AudioMixer.getBus(m, "gun")#volume * Map.getWithDefault("shot_rifle", 1.0, sounds()#levels)),
            (AudioMixer.busOf(m, "shot_rifle_2"), AudioMixer.getBus(m, AudioMixer.busOf(m, "shot_rifle_2"))#volume))

    // ── 鳴り続ける音 ──

    /// 唸りの量は growlNear までは 1・growlFar で 0（距離は Doc）。
    @Test
    def testGrowlLevelFallsToZeroAtFar(): Unit \ Assert =
        Assert.assertEq(expected = (1.0, 0.0), (Sounds.growlLevel(sounds(), sounds()#growlNear), Sounds.growlLevel(sounds(), sounds()#growlFar)))

    /// growlNear の内の敵は唸りの量そのまま（growlVolume）・growlFar の外の敵は唸らない（距離は Doc。2 m と growlFar + 1 m）。
    @Test
    def testNearEnemyGrowlsAndFarEnemyIsSilent(): Unit \ Assert =
        let loudest = dx -> withMeleeAhead(dx) |> Option.map(s -> Sounds.growlsOf(res(), s) |> List.head |> Option.map(g -> g#volume));
        Assert.assertEq(expected = (Some(Some(sounds()#growlVolume)), Some(None)), (loudest(2.0), loudest(sounds()#growlFar + 1.0)))

    /// 機械のうなりの量: 遊んでいる間は通路の既定（迷路に区画の行が無い = 全部通路）・ポーズの間は 0（鳴らし続けたまま黙らせる）。
    @Test
    def testPauseSilencesAmbience(): Unit \ Assert =
        let machineOf = w -> Sounds.sustained(res(), w) |> List.head |> Option.map(x -> (x#name, x#volume));
        Assert.assertEq(expected = (Some(("amb_machine", sounds()#corridor#machine)), Some(("amb_machine", 0.0))),
            (machineOf(World.initial(res())), machineOf(World.pause(World.initial(res())))))

    /// タイトルの画面でも部屋の環境音を小さく流す（無音の画面を出さない。量は部屋の既定 × menuAmbience）。
    @Test
    def testTitleKeepsAQuietAmbience(): Unit \ Assert =
        Assert.assertEq(expected = Some(("amb_machine", sounds()#room#machine * sounds()#menuAmbience)),
            Sounds.sustained(res(), World.title()) |> List.head |> Option.map(x -> (x#name, x#volume)))

    // ── 遅れて起きる事 ──

    /// 拳銃を撃ってから shellDelay を過ぎた最初のコマ（0.05 秒の刻みの次のコマ）に薬莢が落ちる（秒は Doc）。
    @Test
    def testShellLandsAfterTheDocDelay(): Unit \ Assert =
        let r = res();
        let fired = World.step(r, pulling(), at(0.05, World.initial(r)));
        let landed = World.step(r, idle(), at(0.1 + sounds()#shellDelay#pistol, fired));
        Assert.assertEq(expected = Some(Event.ShellLanded(WeaponsDoc.Weapon.Pistol) :: Nil), eventsIn(landed))
}
