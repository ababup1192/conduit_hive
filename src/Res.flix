// Res — 描く元の束: Doc と、Doc から作る物（迷路の形・見える区画の組・当たり判定・弾の的・灰色の箱の絵・粒の絵・spawn の点）と、
// 読み込んだ腕と銃・敵の glb。読むだけで、Doc の読み直しの時だけ替わる。
// 遊びの状態は World が持ち、App の w は Resources.With[Res, World] の組（Game）。
// Res は World を使わない（使う向きは World → Res だけ。lint/rules.flix の module-cycle）。
mod Res {
    use fge::{CollisionShape3d, CollisionWorld3d, PxSpriteAtlas, Rect2}

    /// 起動時と描き出しが同じ形で読む Doc の束と、腕と銃・敵の glb（Controls.loadDocs）。
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
        player = PlayerDoc.Doc,
        enemies = EnemiesDoc.Doc,
        spawns = SpawnsDoc.Doc,
        viewmodels = FpViewmodel.Viewmodels,
        creatures = Creatures.Bodies
    }

    /// 描く元の束。
    pub type alias Res = {
        uiText = UiTextDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        mazeDoc = MazeDoc.Doc,
        weapons = WeaponsDoc.Doc,
        viewmodel = FpViewmodelDoc.Doc,
        particles = Particles3dDoc.Doc,
        player = PlayerDoc.Doc,
        enemies = EnemiesDoc.Doc,
        spawns = SpawnsDoc.Doc,
        viewmodels = FpViewmodel.Viewmodels,
        // 敵の体と、そのクリップの長さ（glb が読めない型は既定の長さ）。
        creatures = Creatures.Bodies,
        timing = Creatures.Timing,
        // 迷路の spawn の印を spawns.json の群れで引いた点。
        spawnPoints = List[Spawner.Point],
        // 迷路の形と見える区画の組（見える距離は霧のかかり切る距離）。
        maze = Maze.Maze,
        collision = CollisionWorld3d.CollisionWorld3d,
        // 撃つ的の柱の箱（当たり判定・弾の的・絵が同じ箱を使う）と、弾の的の列。
        props = List[CollisionShape3d.Box3d],
        hitTargets = Hitscan.Targets,
        // 区画ごとの灰色の箱の絵と灯り（的の柱は最後の部屋の絵に入る）。
        art = Map[Char, MazeMesh.ZoneArt],
        // 3D の粒のビルボードの絵（コードで塗った 1 枚。読み込みで 1 回だけ作る）。
        particleTexture = PxSpriteAtlas.Baked
    }

    /// Doc の束から描く元を組む。
    pub def build(docs: Docs): Res =
        let stage = stageOf(docs#maze, docs#look, docs#spawns);
        { uiText = docs#uiText, keys = docs#keys, theme = docs#theme, walk = docs#walk, look = docs#look, mazeDoc = docs#maze,
          weapons = docs#weapons, viewmodel = docs#viewmodel, particles = docs#particles, player = docs#player, enemies = docs#enemies,
          spawns = docs#spawns, viewmodels = docs#viewmodels, creatures = docs#creatures, timing = Creatures.timingOf(docs#creatures),
          spawnPoints = stage#spawnPoints, maze = stage#maze, collision = stage#collision, props = stage#props, hitTargets = stage#hitTargets,
          art = stage#art, particleTexture = Particles3d.textureOf() }

    /// 迷路と見た目と spawn の群れから作る物。
    type alias Stage = {
        maze = Maze.Maze,
        collision = CollisionWorld3d.CollisionWorld3d,
        props = List[CollisionShape3d.Box3d],
        hitTargets = Hitscan.Targets,
        art = Map[Char, MazeMesh.ZoneArt],
        spawnPoints = List[Spawner.Point]
    }

    /// 迷路と見た目から、形・当たり判定・弾の的・絵・spawn の点を作る。
    /// WhyNot: 位置や時刻の更新ではここを通らない（作り直すのは迷路か見た目の Doc を読み直した時だけ）。
    def stageOf(mazeDoc: MazeDoc.Doc, look: LookDoc.Doc, spawns: SpawnsDoc.Doc): Stage =
        let maze = Maze.build(LookDoc.rec(look)#fogFar, mazeDoc);
        let props = Props.pillarsOf(maze);
        let art = MazeMesh.build(LookDoc.rec(look), maze)
            |> Map.adjust(z -> { instances = List.append(z#instances, Props.artOf(LookDoc.rec(look), props)) | z }, maze#finalZone);
        { maze = maze, collision = Collider.worldOf(maze, props), props = props, hitTargets = Hitscan.targetsOf(maze, props), art = art,
          spawnPoints = Spawner.pointsOf(maze, spawns) }

    def withStage(mazeDoc: MazeDoc.Doc, look: LookDoc.Doc, res: Res): Res =
        let stage = stageOf(mazeDoc, look, res#spawns);
        { mazeDoc = mazeDoc, look = look, maze = stage#maze, collision = stage#collision, props = stage#props, hitTargets = stage#hitTargets,
          art = stage#art, spawnPoints = stage#spawnPoints | res }

    /// 粒の種類の絵のコマ。
    pub def particleRegion(res: Res, kind: Particles3d.Kind): Option[Rect2.Rect2] = Particles3d.regionOf(res#particleTexture, kind)

    // ── Doc の差し替え（保存即反映。Controls.docTable の reload） ──

    pub def withUiText(uiText: UiTextDoc.Doc, res: Res): Res = { uiText = uiText | res }

    pub def withKeys(keys: KeysDoc.Doc, res: Res): Res = { keys = keys | res }

    pub def withTheme(theme: ThemeDoc.Doc, res: Res): Res = { theme = theme | res }

    pub def withWalk(walk: WalkDoc.Doc, res: Res): Res = { walk = walk | res }

    pub def withLook(look: LookDoc.Doc, res: Res): Res = withStage(res#mazeDoc, look, res)

    pub def withMaze(mazeDoc: MazeDoc.Doc, res: Res): Res = withStage(mazeDoc, res#look, res)

    pub def withWeapons(weapons: WeaponsDoc.Doc, res: Res): Res = { weapons = weapons | res }

    pub def withViewmodel(viewmodel: FpViewmodelDoc.Doc, res: Res): Res = { viewmodel = viewmodel | res }

    pub def withParticles(particles: Particles3dDoc.Doc, res: Res): Res = { particles = particles | res }

    pub def withPlayer(player: PlayerDoc.Doc, res: Res): Res = { player = player | res }

    pub def withEnemies(enemies: EnemiesDoc.Doc, res: Res): Res = { enemies = enemies | res }

    pub def withSpawns(spawns: SpawnsDoc.Doc, res: Res): Res = { spawns = spawns, spawnPoints = Spawner.pointsOf(res#maze, spawns) | res }
}
