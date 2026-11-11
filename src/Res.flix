// Res — 描く元の束: Doc と、Doc から作る物（迷路の形・見える区画の組・当たり判定・弾の的・区画ごとの絵・粒の絵・曳光弾の形・spawn の点・拾う物）と、
// 読み込んだステージ・腕と銃・敵・拾う武器・肉片の glb。読むだけで、Doc の読み直しの時だけ替わる。
// 遊びの状態は World が持ち、App の w は Resources.With[Res, World] の組（Game）。
// Res は World を使わない（使う向きは World → Res だけ。lint/rules.flix の module-cycle）。
mod Res {
    use fge::{AudioMixer, CollisionShape3d, CollisionWorld3d, Model3d, Num, PxSpriteAtlas, Rect2, Scene3d, Texture3d}

    /// 起動時と描き出しが同じ形で読む Doc の束と、ステージ・腕と銃・敵・拾う武器の glb（Controls.loadDocs）。
    pub type alias Docs = {
        uiText = UiTextDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        maze = MazeDoc.Doc,
        weapons = WeaponsDoc.Doc,
        viewmodel = FpViewmodelDoc.Doc,
        particles = Particles3dDoc.Doc,
        juice = JuiceDoc.Doc,
        player = PlayerDoc.Doc,
        moves = MovesDoc.Doc,
        grenade = GrenadeDoc.Doc,
        enemies = EnemiesDoc.Doc,
        spawns = SpawnsDoc.Doc,
        pickups = PickupsDoc.Doc,
        tour = TourDoc.Doc,
        sounds = SoundsDoc.Doc,
        // 音の通り道（conduit_hive.mixer.json。音ごとの量は sounds の levels から Res が足す）。
        mixer = AudioMixer.Mixer,
        // ベイクしたステージ（読めなければ None・灰色の箱で描く）。
        stage = Option[StageModel.Stage],
        viewmodels = FpViewmodel.Viewmodels,
        creatures = Creatures.Bodies,
        pickupModels = PickupModels.Models,
        // 弾けた時の肉片（読めなければ None・肉片を出さない）と、投げた手榴弾（読めなければ None・見えないが飛んで爆発する）。
        gibs = Option[Model3d.Model3d],
        grenadeModel = Option[Model3d.Model3d],
        // 蹴りの間に手前へ出る脚（読めなければ None・蹴りは効くが脚は見えない）。
        bootModel = Option[Model3d.Model3d]
    }

    /// 描く元の束。
    pub type alias Res = {
        uiText = UiTextDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        // 画面の後処理の面（見た目の Doc から組む）。
        post = PostSpecs.Specs,
        mazeDoc = MazeDoc.Doc,
        weapons = WeaponsDoc.Doc,
        viewmodel = FpViewmodelDoc.Doc,
        particles = Particles3dDoc.Doc,
        juice = JuiceDoc.Doc,
        player = PlayerDoc.Doc,
        // 技（スタミナ・走る・緊急回避・蹴り）と手榴弾。
        moves = MovesDoc.Doc,
        grenade = GrenadeDoc.Doc,
        enemies = EnemiesDoc.Doc,
        spawns = SpawnsDoc.Doc,
        pickups = PickupsDoc.Doc,
        // 紹介の動画で自動の操縦が歩いて撃つ道筋。
        tour = TourDoc.Doc,
        // 音の鳴らし方と、音の通り道（mixerDoc = conduit_hive.mixer.json のまま・mixer = それに sounds の levels を足した物で、鳴らす時に通す）。
        sounds = SoundsDoc.Doc,
        mixerDoc = AudioMixer.Mixer,
        mixer = AudioMixer.Mixer,
        // ベイクしたステージ（読めなければ None）。迷路と見た目の Doc を読み直した時に、区画の絵をここから組み直す。
        stage = Option[StageModel.Stage],
        viewmodels = FpViewmodel.Viewmodels,
        // 敵の体と、そのクリップの長さ（glb が読めない型は既定の長さ）。
        creatures = Creatures.Bodies,
        timing = Creatures.Timing,
        // 毎コマ光る物（回転灯と明滅する蛍光灯。迷路か見た目の Doc を読み直した時に組み直す）。
        fixtureLights = List[FixtureLights.Light],
        // 迷路の spawn の印の点と、spawns.json の wave を区画ごとに並べた物（遊ぶ時と、紹介の動画の自動の操縦の時は最後の部屋の wave を TourDoc の finalWaves まで）。
        spawnPoints = List[Spawner.Point],
        wavePlans = Spawner.Plans,
        tourWavePlans = Spawner.Plans,
        // 迷路の pickup の印を pickups.json の量で引いた物と、拾う物の形（武器の glb を含む）。
        pickupPoints = List[Pickups.Point],
        pickupArt = PickupModels.Art,
        // 迷路の形と見える区画の組（見える距離は霧のかかり切る距離）。
        maze = Maze.Maze,
        collision = CollisionWorld3d.CollisionWorld3d,
        // 周りに壁も立てた物も無いマス（押し合いの後の壁の押し出しを飛ばす。Collider.openCellsOf）。
        openCells = Vector[Bool],
        // 撃つ的の柱の箱（当たり判定・弾の的・絵が同じ箱を使う）と、弾の的の列。
        props = List[CollisionShape3d.Box3d],
        hitTargets = Hitscan.Targets,
        // 区画ごとの絵と灯り（ベイクしたステージか灰色の箱）・的の柱の絵（最後の部屋が見える時に一人称の場面だけに描く）と、
        // 場面に渡すステージの絵（trim sheet と lightmap）。
        art = Map[Char, MazeMesh.ZoneArt],
        propArt = List[Scene3d.Instance3d],
        stageTextures = List[Texture3d.Texture3d],
        // 3D の粒のビルボードの絵（コードで塗った 1 枚。読み込みで 1 回だけ作る）。
        particleTexture = PxSpriteAtlas.Baked,
        // 弾けた時の肉片の形と、曳光弾の線の形と材質（粒の Doc を読み直した時に作り直す）。
        gibArt = Gibs.Art,
        tracerArt = Tracers.Art,
        // 爆発の形で描く部分（火の玉の塊・衝撃の輪・焦げ跡。粒の Doc を読み直した時に作り直す）。
        blastArt = BlastFx.Art,
        // 投げた手榴弾の glb（読めなければ None）と、蹴りの間に手前へ出る脚の形（boot.glb の腿と脛）。
        grenadeModel = Option[Model3d.Model3d],
        bootArt = Boot.Art,
        // 銃口の光の作り置きの形（読み込みで 1 回）。
        muzzleFlashArt = MuzzleFlash.Art
    }

    /// Doc の束から描く元を組む。
    pub def build(docs: Docs): Res =
        let stage = stageOf(docs#maze, docs#look, docs#stage);
        withPlans({ uiText = docs#uiText, keys = docs#keys, theme = docs#theme, walk = docs#walk, look = docs#look, post = PostSpecs.build(LookDoc.rec(docs#look)), mazeDoc = docs#maze,
          weapons = docs#weapons, viewmodel = docs#viewmodel, particles = docs#particles, juice = docs#juice, player = docs#player,
          moves = docs#moves, grenade = docs#grenade, enemies = docs#enemies,
          spawns = docs#spawns, pickups = docs#pickups, tour = docs#tour,
          sounds = docs#sounds, mixerDoc = docs#mixer, mixer = SoundsDoc.mixerOf(docs#mixer, docs#sounds), stage = docs#stage, viewmodels = FpViewmodel.withSurfaces(FpViewmodelDoc.rec(docs#viewmodel), docs#viewmodels), creatures = Creatures.withSkin(LookDoc.rec(docs#look), docs#creatures), timing = Creatures.timingOf(docs#creatures),
          spawnPoints = stage#spawnPoints, fixtureLights = stage#fixtureLights, wavePlans = Map.empty(), tourWavePlans = Map.empty(), pickupPoints = Pickups.pointsOf(stage#maze, docs#pickups),
          pickupArt = PickupModels.build(LookDoc.rec(docs#look), docs#pickups, docs#pickupModels), maze = stage#maze, collision = stage#collision, openCells = stage#openCells, props = stage#props, hitTargets = stage#hitTargets,
          art = stage#art, propArt = stage#propArt, stageTextures = stage#textures, particleTexture = Particles3d.textureOf(),
          gibArt = Gibs.artOf(docs#gibs), tracerArt = Tracers.artOf(Particles3dDoc.rec(docs#particles)#tracers, Particles3dDoc.rec(docs#particles)#spit), blastArt = BlastFx.artOf(Particles3dDoc.rec(docs#particles)#blast),
          grenadeModel = docs#grenadeModel, bootArt = Boot.build(docs#bootModel), muzzleFlashArt = MuzzleFlash.artOf() })


    /// 迷路と見た目から作る物。
    type alias Stage = {
        maze = Maze.Maze,
        collision = CollisionWorld3d.CollisionWorld3d,
        openCells = Vector[Bool],
        props = List[CollisionShape3d.Box3d],
        hitTargets = Hitscan.Targets,
        art = Map[Char, MazeMesh.ZoneArt],
        propArt = List[Scene3d.Instance3d],
        textures = List[Texture3d.Texture3d],
        spawnPoints = List[Spawner.Point],
        fixtureLights = List[FixtureLights.Light]
    }

    /// 迷路と見た目から、形・当たり判定・弾の的・絵・spawn の点を作る。
    /// WhyNot: 位置や時刻の更新ではここを通らない（作り直すのは迷路か見た目の Doc を読み直した時だけ）。
    def stageOf(mazeDoc: MazeDoc.Doc, look: LookDoc.Doc, baked: Option[StageModel.Stage]): Stage =
        let lk = LookDoc.rec(look);
        let maze = Maze.build(lk#fogFar, mazeDoc);
        let props = Props.pillarsOf(maze);
        let current = if (lk#bakedStage) baked |> Option.flatMap(StageModel.currentFor(mazeDoc)) else None;
        let hullSurface = current |> Option.flatMap(StageModel.hullSurfaceOf(lk));
        { maze = maze, collision = Collider.worldOf(maze, props), openCells = Collider.openCellsOf(maze, props), props = props, hitTargets = Hitscan.targetsOf(maze, props),
          art = artOf(lk, maze, current, hullSurface |> Option.map(Texture3d.name)), propArt = Props.artOf(lk, props),
          textures = List.append(current |> Option.map(s -> s#textures) |> Option.getWithDefault(Nil), Option.toList(hullSurface)), spawnPoints = Spawner.pointsOf(maze),
          fixtureLights = if (Option.isEmpty(current)) Nil else FixtureLights.lightsOf(lk, maze) }

    def tourPlansOf(maze: Maze.Maze, tour: TourDoc.Doc, plans: Spawner.Plans): Spawner.Plans =
        Spawner.limitWaves(maze#finalZone, TourDoc.rec(tour)#finalWaves, plans)

    /// spawn の点と、区画ごとの wave（迷路か spawns か tour の Doc を読み直した時に組み直す）。
    def withPlans(res: Res): Res =
        let plans = Spawner.plansOf(res#maze, res#spawnPoints, res#spawns);
        { wavePlans = plans, tourWavePlans = tourPlansOf(res#maze, res#tour, plans) | res }

    /// 区画ごとの絵: ベイクしたステージがあればその区画の形（灯りは場面に入れず、灯具の写しだけを持つ）と映り込みの景色・無ければ灰色の箱。
    /// hullSurface = 壁・床・天井の金属っぽさと粗さの絵の名前（StageModel.hullSurfaceOf）。
    def artOf(look: LookDoc.Rec, maze: Maze.Maze, baked: Option[StageModel.Stage], hullSurface: Option[String]): Map[Char, MazeMesh.ZoneArt] = match baked {
        case None        => MazeMesh.build(look, maze)
        case Some(stage) => maze#zones |> Map.map(zone ->
            { instances = StageModel.instancesOf(look, hullSurface, stage, zone#id), lights = Nil, lamps = zoneLamps(look, maze, zone),
              environment = StageModel.environmentOf(look, maze, stage, zone) })
    }

    /// ベイクしたステージの区画の灯具の灯り（手前の腕と銃へ写す）: 色と強さは look の zoneLights（ベイクした灯りと同じ）。
    def zoneLamps(look: LookDoc.Rec, maze: Maze.Maze, zone: Maze.Zone): List[Scene3d.PointLight] =
        let zl = LookDoc.zoneLightOf(look, zone#id);
        MazeMesh.lampLightsOf(look, maze, zone) |> List.map(l -> { color = zl#color, intensity = l#intensity * zl#intensity | l })

    /// 点 x・z の区画の映り込みの景色（区画の外・灰色の箱・使わない時は None）。ほかの区画との境目から look の envFade m の内では、
    /// 境目へ近づくほど映り込みを弱め、境目でちょうど 0 にする（区画をまたいで景色の絵を替える瞬間に、映り込みが一瞬で変わって見えないため）。
    // WhyNot: 2 つの区画の景色を混ぜない — engine の環境マップは場面に 1 枚で、2 枚を混ぜる口が無い。
    pub def environmentAt(res: Res, x: Float64, z: Float64): Option[Scene3d.EnvironmentMap] =
        let fade = LookDoc.rec(res#look)#envFade;
        let k = if (fade <= 0.0) 1.0 else { let u = Num.clamp01(boundaryDistance(res#maze, x, z) / fade); u * u * (3.0 - 2.0 * u) };
        Maze.zoneAt(res#maze, x, z) |> Option.flatMap(id -> Map.get(id, res#art)) |> Option.flatMap(a -> a#environment)
            |> Option.map(e -> Scene3d.withEnvironmentIntensity(Scene3d.environmentMapFieldsOf(e)#intensity * k, e))

    /// 点 x・z から、今のマスの 4 辺のうち向こうが別の区画の床の辺までの近い方の距離（m。そういう辺が無ければ十分遠い値）。
    def boundaryDistance(maze: Maze.Maze, x: Float64, z: Float64): Float64 =
        let cell = Maze.cellAt(maze, x, z);
        let here = Maze.charAt(maze, cell);
        let (x0, z0) = Maze.cornerOf(maze, cell);
        let cs = maze#cellSize;
        let sides = ({ col = cell#col, row = cell#row - 1 }, z0 + cs - z) :: ({ col = cell#col, row = cell#row + 1 }, z - z0)
            :: ({ col = cell#col + 1, row = cell#row }, x0 + cs - x) :: ({ col = cell#col - 1, row = cell#row }, x - x0) :: Nil;
        sides |> List.filter(e -> Maze.isFloor(maze, fst(e)) and Maze.charAt(maze, fst(e)) != here)
            |> List.map(snd) |> List.foldLeft(Float64.min, 1000.0)

    def withStage(mazeDoc: MazeDoc.Doc, look: LookDoc.Doc, res: Res): Res =
        let stage = stageOf(mazeDoc, look, res#stage);
        withPlans({ mazeDoc = mazeDoc, look = look, post = PostSpecs.build(LookDoc.rec(look)), maze = stage#maze, collision = stage#collision, openCells = stage#openCells, props = stage#props, hitTargets = stage#hitTargets,
          art = stage#art, propArt = stage#propArt, stageTextures = stage#textures, spawnPoints = stage#spawnPoints, fixtureLights = stage#fixtureLights, pickupPoints = Pickups.pointsOf(stage#maze, res#pickups),
          creatures = Creatures.withSkin(LookDoc.rec(look), res#creatures),
          pickupArt = PickupModels.build(LookDoc.rec(look), res#pickups, res#pickupArt#models) | res })

    /// 粒の種類の絵のコマ。
    pub def particleRegion(res: Res, kind: Particles3d.Kind): Option[Rect2.Rect2] = Particles3d.regionOf(res#particleTexture, kind)

    /// 粒の種類の絵の frame 番目のコマ（形の変わる種類だけ frame で替わる。Particles3d.frameRegionOf）。
    pub def particleFrame(res: Res, kind: Particles3d.Kind, frame: Int32): Option[Rect2.Rect2] = Particles3d.frameRegionOf(res#particleTexture, kind, frame)

    // ── Doc の差し替え（保存即反映。Controls.docTable の reload） ──

    pub def withUiText(uiText: UiTextDoc.Doc, res: Res): Res = { uiText = uiText | res }

    pub def withKeys(keys: KeysDoc.Doc, res: Res): Res = { keys = keys | res }

    pub def withTheme(theme: ThemeDoc.Doc, res: Res): Res = { theme = theme | res }

    pub def withWalk(walk: WalkDoc.Doc, res: Res): Res = { walk = walk | res }

    pub def withLook(look: LookDoc.Doc, res: Res): Res = withStage(res#mazeDoc, look, res)

    pub def withMaze(mazeDoc: MazeDoc.Doc, res: Res): Res = withStage(mazeDoc, res#look, res)

    pub def withWeapons(weapons: WeaponsDoc.Doc, res: Res): Res = { weapons = weapons | res }

    pub def withViewmodel(viewmodel: FpViewmodelDoc.Doc, res: Res): Res =
        { viewmodel = viewmodel, viewmodels = FpViewmodel.withSurfaces(FpViewmodelDoc.rec(viewmodel), res#viewmodels) | res }

    pub def withParticles(particles: Particles3dDoc.Doc, res: Res): Res =
        { particles = particles, tracerArt = Tracers.artOf(Particles3dDoc.rec(particles)#tracers, Particles3dDoc.rec(particles)#spit), blastArt = BlastFx.artOf(Particles3dDoc.rec(particles)#blast) | res }

    pub def withJuice(juice: JuiceDoc.Doc, res: Res): Res = { juice = juice | res }

    pub def withPlayer(player: PlayerDoc.Doc, res: Res): Res = { player = player | res }

    pub def withMoves(moves: MovesDoc.Doc, res: Res): Res = { moves = moves | res }

    pub def withGrenade(grenade: GrenadeDoc.Doc, res: Res): Res = { grenade = grenade | res }

    pub def withEnemies(enemies: EnemiesDoc.Doc, res: Res): Res = { enemies = enemies | res }

    pub def withSpawns(spawns: SpawnsDoc.Doc, res: Res): Res = withPlans({ spawns = spawns | res })

    pub def withTour(tour: TourDoc.Doc, res: Res): Res = withPlans({ tour = tour | res })

    pub def withSounds(sounds: SoundsDoc.Doc, res: Res): Res = { sounds = sounds, mixer = SoundsDoc.mixerOf(res#mixerDoc, sounds) | res }

    pub def withMixer(mixer: AudioMixer.Mixer, res: Res): Res = { mixerDoc = mixer, mixer = SoundsDoc.mixerOf(mixer, res#sounds) | res }

    pub def withPickups(pickups: PickupsDoc.Doc, res: Res): Res =
        { pickups = pickups, pickupPoints = Pickups.pointsOf(res#maze, pickups),
          pickupArt = PickupModels.build(LookDoc.rec(res#look), pickups, res#pickupArt#models) | res }
}
