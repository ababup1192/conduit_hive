// テストの共通の道具: 小さな迷路の Doc・その迷路の描く元（腕と銃の glb は無し）・刻み dt の遊びの時計・遊んでいる場面の値の取り出し。
mod TestSupport {
    use fge::{Camera3d, Clock}

    /// マス目の行と start の印（列・行・向き）から小さな迷路の Doc（区画の行は書かない = 全部通路・高さ 4 m・1 マス 4 m）。
    pub def mazeOf(rows: List[String], startCol: Int32, startRow: Int32, yaw: Float64): MazeDoc.Doc =
        MazeDoc.Doc.Doc({ version = 1, cellSize = 4.0, wallHeight = 4.0, finalZone = 'A', rows = rows, zones = Nil,
                          marks = { kind = MazeDoc.MarkKind.Start, name = "start", col = startCol, row = startRow, yaw = yaw } :: Nil })

    /// 既定の Doc に迷路だけを差し替えた描く元（腕と銃・敵の glb は無し。敵のクリップの長さは既定の長さ）。
    pub def resWith(maze: MazeDoc.Doc): Res.Res = Res.build(docsWith(maze))

    /// 既定の Doc に迷路だけを差し替えた Doc の束（Game.app に渡す）。
    pub def docsWith(maze: MazeDoc.Doc): Res.Docs =
        ({ uiText = UiTextDoc.defaults(), keys = KeysDoc.defaults(), theme = ThemeDoc.defaults(),
                    walk = WalkDoc.defaults(), look = LookDoc.defaults(), maze = maze,
                    weapons = WeaponsDoc.defaults(), viewmodel = FpViewmodelDoc.defaults(), particles = Particles3dDoc.defaults(),
                    player = PlayerDoc.defaults(), enemies = EnemiesDoc.defaults(), spawns = SpawnsDoc.defaults(), pickups = PickupsDoc.defaults(), tour = TourDoc.defaults(),
                    stage = None, viewmodels = Map.empty(), creatures = Map.empty(), pickupModels = Map.empty() })

    // ── 遊んでいる場面の値（ほかの画面なら None） ──

    pub def walkerIn(w: World.World): Option[Walker.Walker] = World.sessionOf(w) |> Option.map(World.walkerOf)

    pub def arsenalIn(w: World.World): Option[Arsenal.Arsenal] = World.sessionOf(w) |> Option.map(World.arsenalOf)

    pub def particlesIn(w: World.World): Option[List[Particles3d.Particle]] = World.sessionOf(w) |> Option.map(World.particlesOf)

    pub def hordeIn(w: World.World): Option[Horde.Horde] = World.sessionOf(w) |> Option.map(World.hordeOf)

    pub def healthIn(w: World.World): Option[Health.Health] = World.sessionOf(w) |> Option.map(World.healthOf)

    pub def checkpointIn(w: World.World): Option[World.Checkpoint] = World.sessionOf(w) |> Option.map(World.checkpointOf)

    pub def eventsIn(w: World.World): Option[List[Events.Event]] = World.sessionOf(w) |> Option.map(World.eventsOf)

    /// 今の照準のカメラ。
    pub def cameraIn(res: Res.Res, w: World.World): Option[Camera3d.Camera3d] = World.sessionOf(w) |> Option.map(World.cameraOf(res, World.seconds(w)))

    /// 刻みが dt 秒の遊びの時計（1 コマ進めた後）。
    pub def clockOf(dt: Float64): Clock.Clock[PlayClock.Play] =
        Clock.advance(Clock.paceOf(Clock.Run.Running), dt, Clock.start())

    /// 今が t 秒で、このコマの刻みが dt 秒の遊びの時計。
    pub def clockAt(t: Float64, dt: Float64): Clock.Clock[PlayClock.Play] =
        Clock.advance(Clock.paceOf(Clock.Run.Running), dt, Clock.advance(Clock.paceOf(Clock.Run.Running), t - dt, Clock.start()))

    /// 東西に長い 3 マスの部屋（壁の内側は x が 4〜16 m・z が 4〜8 m）。start は西の端のマス・東向き。
    pub def eastRoom(): MazeDoc.Doc = mazeOf("#####" :: "#AAA#" :: "#####" :: Nil, 1, 1, 90.0)
}
