// Res — 描く元の束: Doc と、Doc から作る物（迷路の形・見える区画の組・当たり判定・灰色の箱の絵）。読むだけで、Doc の読み直しの時だけ替わる。
// 遊びの状態は World が持ち、App の w は Resources.With[Res, World] の組（Game）。
// Res は World を使わない（使う向きは World → Res だけ。lint/rules.flix の module-cycle）。
mod Res {
    use fge::CollisionWorld3d

    /// 起動時と描き出しが同じ形で読む Doc の束（Controls.loadDocs）。
    pub type alias Docs = {
        sample = SampleDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        maze = MazeDoc.Doc
    }

    /// 描く元の束。
    pub type alias Res = {
        sample = SampleDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        mazeDoc = MazeDoc.Doc,
        // 迷路の形と見える区画の組（見える距離は霧のかかり切る距離）。
        maze = Maze.Maze,
        collision = CollisionWorld3d.CollisionWorld3d,
        // 区画ごとの灰色の箱の絵と灯り。
        art = Map[Char, MazeMesh.ZoneArt]
    }

    /// Doc の束から描く元を組む。
    pub def build(docs: Docs): Res =
        withStage(docs#maze, docs#look,
            { sample = docs#sample, keys = docs#keys, theme = docs#theme, walk = docs#walk, look = docs#look, mazeDoc = docs#maze,
              maze = Maze.build(0.0, MazeDoc.defaults()), collision = CollisionWorld3d.empty(), art = Map.empty() })

    /// 迷路と見た目から、形・当たり判定・絵を作り直す。
    /// WhyNot: 位置や時刻の更新ではここを通らない（作り直すのは迷路か見た目の Doc を読み直した時だけ）。
    def withStage(mazeDoc: MazeDoc.Doc, look: LookDoc.Doc, res: Res): Res =
        let maze = Maze.build(LookDoc.rec(look)#fogFar, mazeDoc);
        { mazeDoc = mazeDoc, look = look, maze = maze, collision = Collider.worldOf(maze), art = MazeMesh.build(LookDoc.rec(look), maze) | res }

    // ── Doc の差し替え（保存即反映。Controls.docTable の reload） ──

    pub def withSample(sample: SampleDoc.Doc, res: Res): Res = { sample = sample | res }

    pub def withKeys(keys: KeysDoc.Doc, res: Res): Res = { keys = keys | res }

    pub def withTheme(theme: ThemeDoc.Doc, res: Res): Res = { theme = theme | res }

    pub def withWalk(walk: WalkDoc.Doc, res: Res): Res = { walk = walk | res }

    pub def withLook(look: LookDoc.Doc, res: Res): Res = withStage(res#mazeDoc, look, res)

    pub def withMaze(mazeDoc: MazeDoc.Doc, res: Res): Res = withStage(mazeDoc, res#look, res)
}
