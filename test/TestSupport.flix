// テストの共通の道具: 小さな迷路の Doc・その迷路の描く元（腕と銃の glb は無し）・刻み dt の遊びの時計。
mod TestSupport {
    use fge::Clock

    /// マス目の行と start の印（列・行・向き）から小さな迷路の Doc（区画の行は書かない = 全部通路・高さ 4 m・1 マス 4 m）。
    pub def mazeOf(rows: List[String], startCol: Int32, startRow: Int32, yaw: Float64): MazeDoc.Doc =
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'A', rows = rows, zones = Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = startCol, row = startRow, yaw = yaw } :: Nil })

    /// 既定の Doc に迷路だけを差し替えた描く元。
    pub def resWith(maze: MazeDoc.Doc): Res.Res =
        Res.build({ sample = SampleDoc.defaults(), keys = KeysDoc.defaults(), theme = ThemeDoc.defaults(),
                    walk = WalkDoc.defaults(), look = LookDoc.defaults(), maze = maze,
                    weapons = WeaponsDoc.defaults(), hands = HandsDoc.defaults(), particles = Particles3dDoc.defaults(), rigs = Map.empty() })

    /// 刻みが dt 秒の遊びの時計（1 コマ進めた後）。
    pub def clockOf(dt: Float64): Clock.Clock[PlayClock.Play] =
        Clock.advance(Clock.paceOf(Clock.Run.Running), dt, Clock.start())

    /// 東西に長い 3 マスの部屋（壁の内側は x が 4〜16 m・z が 4〜8 m）。start は西の端のマス・東向き。
    pub def eastRoom(): MazeDoc.Doc = mazeOf("#####" :: "#AAA#" :: "#####" :: Nil, 1, 1, 90.0)
}
