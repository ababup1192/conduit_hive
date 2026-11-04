// Controls — キーとマウスを World.Input へ写し、World.step で 1 歩進める（純粋）。
// どのキーがどの操作かは KeysDoc（player.keys.json）が決める。マウスは窓を押すと窓にキャプチャし（App.withMouseCapture）、
// 動いた量（frame#mouseDelta）で視点を回す。Esc で放し、放している時の Esc で終了の確認を出す。
// キャプチャしている間は左ボタンが引き金・数字キーの 1〜3 とホイールが持ち替え（FPS の慣習の固定のキー）。
// Doc の読み込み（loadDocs）と、保存即反映（watchFile）・F1 一括リロードの読み直しもここに置く。
mod Controls {

    use fge::{App, DocTable, GameEngine, LoadProgress, Resources, SortingLayer, Vec2}

    /// マウスの動いた量（design px）を、このコマに回す角（度。yaw, pitch）へ。キャプチャしていない・窓にフォーカスが無い時は回さない。
    /// 上下は invertY で逆にする（pitch は正で下を向く）。
    def lookOf(walk: WalkDoc.Rec, looking: Bool, focused: Bool, delta: Vec2.Vec2): (Float64, Float64) =
        if (not looking or not focused) (0.0, 0.0)
        else (delta#x * walk#mouseSensitivity, delta#y * walk#mouseSensitivity * (if (walk#invertY) -1.0 else 1.0))

    /// このフレームのキーとマウスを World.Input へ（逆向きが同時なら打ち消して 0）。
    /// キーは向きを変える速さ（turnSpeed 度/秒）・マウスはこのコマの角（mouseSensitivity × px）で渡す。
    /// aiming = 前のコマからキャプチャしていて窓にフォーカスがある（キャプチャを始めたクリックでは撃たない）。
    def inputOf(frame: App.Frame, res: Res.Res, aiming: Bool, w: World.World): World.Input =
        let k = KeysDoc.rec(res#keys);
        let walk = WalkDoc.rec(res#walk);
        let held = ks -> List.exists(key -> App.isDown(key, frame), ks);
        let axis = (neg, pos) -> (if (held(pos)) 1.0 else 0.0) - (if (held(neg)) 1.0 else 0.0);
        let (mdx, mdy) = lookOf(walk, World.isLooking(w), frame#windowFocused, frame#mouseDelta);
        let left = GameEngine.MouseButton.Left;
        { drive = { forward = axis(k#back, k#forward), strafe = axis(k#left, k#right),
                    turnDeg = mdx, lookDeg = mdy,
                    turnRate = axis(k#turnLeft, k#turnRight) * walk#turnSpeed, sprint = held(k#sprint) },
          trigger = if (aiming) { pressed = Set.memberOf(left, frame#mouseClickedButtons), held = Set.memberOf(left, frame#mouseButtons) }
                    else Arsenal.released(),
          choice = if (aiming) choiceOf(frame) else Arsenal.Choice.Keep }

    /// 持ち替えの指示: 数字キーの 1・2・3 が武器の並び・ホイールを上へ回すと前・下へ回すと次。
    def choiceOf(frame: App.Frame): Arsenal.Choice =
        let slots = (GameEngine.Key.Digit1, WeaponsDoc.Weapon.Pistol) :: (GameEngine.Key.Digit2, WeaponsDoc.Weapon.Shotgun)
                        :: (GameEngine.Key.Digit3, WeaponsDoc.Weapon.Rifle) :: Nil;
        let slot = slots |> List.find(e -> App.justPressed(fst(e), frame)) |> Option.map(e -> Arsenal.Choice.Slot(snd(e)));
        let wheel = if (frame#wheel > 0.0) Arsenal.Choice.Previous else if (frame#wheel < 0.0) Arsenal.Choice.Next else Arsenal.Choice.Keep;
        slot |> Option.getWithDefault(wheel)

    /// 毎フレームのシステム。終了の確認の窓が出ている間は Enter で終わる・Esc で戻る（マウスは tapAt）。
    /// 遊んでいる間は、窓を押すとマウスをキャプチャし、Esc でキャプチャを放す。放している時の Esc で終了の確認を出す。
    /// Esc・Enter・F3（診断の表示）は OS とゲームの慣習に合わせた固定のキー（割り当ての Doc には載せない）。
    pub def step(frame: App.Frame, res: Res.Res, w: World.World): World.World =
        let pressed = key -> App.justPressed(key, frame);
        let w1 =
            if (World.isAskingQuit(w))
                (if (pressed(GameEngine.Key.Enter)) World.answerQuit(true, w)
                 else if (pressed(GameEngine.Key.Escape)) World.answerQuit(false, w)
                 else if (frame#mouseClicked) tapAt(res, frame#cursor, w)
                 else w)
            else if (pressed(GameEngine.Key.Escape) and World.isLooking(w)) World.setLooking(false, w)
            else if (pressed(GameEngine.Key.Escape)) World.askQuit(w)
            else if (frame#mouseClicked and not World.isLooking(w)) World.setLooking(true, w)
            else w;
        let w2 = if (pressed(GameEngine.Key.F3)) World.toggleDiagnostics(w1) else w1;
        let aiming = World.isLooking(w) and World.isLooking(w2) and frame#windowFocused;
        World.step(res, inputOf(frame, res, aiming, w2), w2)

    /// 終了の確認の窓が出ている時に cursor を押した。押した物は絵と同じ木（View.layers）から描く順の手前で選ぶ。
    pub def tapAt(res: Res.Res, cursor: Vec2.Vec2, w: World.World): World.World =
        let ctx = App.pickCtx({ x = World.width(), y = World.height() });
        match SortingLayer.pickFrom(cursor, View.layers(ctx, View.inputOf(res, w))) {
            case Some(World.Press.QuitYes) => World.answerQuit(true, w)
            case Some(World.Press.QuitNo)  => World.answerQuit(false, w)
            case None                      => w
        }

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と描き出しが同じ形で読む Doc の束と腕と銃・敵の glb。区切りごとに進み具合を知らせる
    /// （実機は起動画面が進む・描き出しとテストと flow は HeadlessLoad.handle で絵を解く）。
    pub def loadDocs(): Res.Docs \ Fs.FileRead + IO + LoadProgress =
        LoadProgress.report("reading docs...", 0, 0);
        { sample = SampleDoc.load(SampleDoc.path()), keys = KeysDoc.load(KeysDoc.path()), theme = ThemeDoc.load(ThemeDoc.path()),
          walk = WalkDoc.load(WalkDoc.path()), look = LookDoc.load(LookDoc.path()), maze = MazeDoc.load(MazeDoc.path()),
          weapons = WeaponsDoc.load(WeaponsDoc.path()), hands = HandsDoc.load(HandsDoc.path()),
          particles = Particles3dDoc.load(Particles3dDoc.path()), enemies = EnemiesDoc.load(EnemiesDoc.path()),
          spawns = SpawnsDoc.load(SpawnsDoc.path()), rigs = Arms.load(), creatures = Creatures.load() }

    def reloadSample(res: Res.Res): Res.Res \ Fs.FileRead = Res.withSample(SampleDoc.load(SampleDoc.path()), res)

    def reloadKeys(res: Res.Res): Res.Res \ Fs.FileRead = Res.withKeys(KeysDoc.load(KeysDoc.path()), res)

    def reloadTheme(res: Res.Res): Res.Res \ Fs.FileRead = Res.withTheme(ThemeDoc.load(ThemeDoc.path()), res)

    def reloadWeapons(res: Res.Res): Res.Res \ Fs.FileRead = Res.withWeapons(WeaponsDoc.load(WeaponsDoc.path()), res)

    def reloadHands(res: Res.Res): Res.Res \ Fs.FileRead = Res.withHands(HandsDoc.load(HandsDoc.path()), res)

    def reloadParticles(res: Res.Res): Res.Res \ Fs.FileRead = Res.withParticles(Particles3dDoc.load(Particles3dDoc.path()), res)

    def reloadEnemies(res: Res.Res): Res.Res \ Fs.FileRead = Res.withEnemies(EnemiesDoc.load(EnemiesDoc.path()), res)

    def reloadSpawns(res: Res.Res): Res.Res \ Fs.FileRead = Res.withSpawns(SpawnsDoc.load(SpawnsDoc.path()), res)

    def reloadWalk(res: Res.Res): Res.Res \ Fs.FileRead = Res.withWalk(WalkDoc.load(WalkDoc.path()), res)

    def reloadLook(res: Res.Res): Res.Res \ Fs.FileRead = Res.withLook(LookDoc.load(LookDoc.path()), res)

    def reloadMaze(res: Res.Res): Res.Res \ Fs.FileRead = Res.withMaze(MazeDoc.load(MazeDoc.path()), res)

    /// Doc の一覧表(DocTable)。watchFile(保存即反映)・F1 の一括リロード・Studio へ名乗る「表示中」の 3 つは、どれもこの 1 枚から導出する。
    /// docId は project.json の editor.resources[] の id と同じ物。
    /// 迷路を読み直したら、体を新しい start の印に立たせ直す（古い迷路の座標のままだと壁の中に残る）。
    pub def docTable(): List[DocTable.Entry[Resources.With[Res.Res, World.World]]] =
        let unchanged = (_, w) -> w;
        Resources.reloadRow("sample", SampleDoc.path(), reloadSample, unchanged)
            :: Resources.reloadRow("keys", KeysDoc.path(), reloadKeys, unchanged)
            :: Resources.reloadRow("theme", ThemeDoc.path(), reloadTheme, unchanged)
            :: Resources.reloadRow("weapons", WeaponsDoc.path(), reloadWeapons, unchanged)
            :: Resources.reloadRow("hands", HandsDoc.path(), reloadHands, unchanged)
            :: Resources.reloadRow("particles3d", Particles3dDoc.path(), reloadParticles, unchanged)
            :: Resources.reloadRow("enemies", EnemiesDoc.path(), reloadEnemies, unchanged)
            :: Resources.reloadRow("spawns", SpawnsDoc.path(), reloadSpawns, unchanged)
            :: Resources.reloadRow("walk", WalkDoc.path(), reloadWalk, unchanged)
            :: Resources.reloadRow("look", LookDoc.path(), reloadLook, unchanged)
            :: Resources.reloadRow("maze", MazeDoc.path(), reloadMaze, (res, w) -> { play = w#play | World.initial(res) })
            :: Nil
}
