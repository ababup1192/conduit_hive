// World — 遊びの状態そのものと、次の状態を作る規則（すべて純粋）。
// Doc と迷路（形・当たり判定・絵）は Res が持ち、World は持たない（読む口は res を受ける）。
//
// ── 場面 ──
// Play = 一人称で迷路を歩いている。表紙・クリアなどを足す時は Screen に case を足し、step と View を match で分ける。
mod World {

    use fge::{Clock, Num}

    /// このフレームの入力: 歩き方（Walker.Drive）。
    pub type alias Input = { drive = Walker.Drive }

    /// マウスの視点。Captured = マウスを窓にキャプチャして視点を回している。
    pub enum Look with Eq, ToString {
        case Captured
        case Released
    }

    /// F3 の診断の表示。
    pub enum DiagnosticsView with Eq, ToString {
        case Shown
        case Hidden
    }

    /// 終了の確認。Esc か窓の閉じるボタンで Asking（確認の窓を出し、歩けない）、
    /// はいで Confirmed（Game の App.quitWhen がこれを見て閉じる）、いいえで Playing へ戻る。
    pub enum Quit with Eq, ToString {
        case Playing
        case Asking
        case Confirmed
    }

    /// マウスで押せる物（View が描く木に ZStack.hit で積み、Controls が SortingLayer.pickFrom で引く）。
    pub enum Press with Eq, ToString {
        case QuitYes   // 終了の確認の窓の中（Enter と同じ）
        case QuitNo    // 窓の外（Esc と同じ）
    }

    /// 歩いている間の中身: 体・マウスの視点・F3 の診断を出すか。
    pub type alias SessionRec = {
        walker = Walker.Walker,
        look = Look,
        diagnosticsView = DiagnosticsView
    }

    /// 歩いている間の中身。作るのは World の中だけ。読む口は sessionOf・書く口は mapSession。
    enum SessionOf(SessionRec)

    pub type alias Session = SessionOf

    /// どの画面か。その画面だけが持つ値を payload に持つ。
    pub enum Screen {
        case Play(Session)
    }

    /// 遊びの状態。play = 遊びの時計（歩く・頭の上下がこれを見る。終了の確認の間は止まる）。
    pub type alias World = {
        play = Clock.Clock[PlayClock.Play],
        screen = Screen,
        quit = Quit
    }

    // ── 盤の寸法（design 480×270。project.json と同じ値） ──

    pub def width(): Float64 = 480.0
    pub def height(): Float64 = 270.0

    pub def spritePath(): String = "assets/conduit_hive.sprite.json"

    /// 歩き始める体（迷路の start の印に立ち、足元を床に合わせる）。
    def startWalker(res: Res.Res): Walker.Walker =
        let s = res#maze#start;
        Walker.settle(res#collision, WalkDoc.rec(res#walk), Walker.standing(s#x, 0.0, s#z, s#yaw))

    /// 遊びから始める状態。
    pub def initial(res: Res.Res): World =
        { play = Clock.start(), quit = Quit.Playing,
          screen = Screen.Play(SessionOf.SessionOf({ walker = startWalker(res), look = Look.Released, diagnosticsView = DiagnosticsView.Hidden })) }

    def rec(s: Session): SessionRec = match s { case SessionOf.SessionOf(r) => r }

    def sessionOf(w: World): SessionRec = match w#screen {
        case Screen.Play(s) => rec(s)
    }

    def mapSession(f: SessionRec -> SessionRec, w: World): World = match w#screen {
        case Screen.Play(s) => { screen = Screen.Play(SessionOf.SessionOf(f(rec(s)))) | w }
    }

    /// 今の体。
    pub def walkerOf(w: World): Walker.Walker = sessionOf(w)#walker

    /// 体を x・z に置き直す（描き出しの場面・始まり）。向きと見下ろす角は度。足元は床に合わせる。
    pub def placeWalker(res: Res.Res, at: { x = Float64, z = Float64 }, yawDeg: Float64, pitchDeg: Float64, w: World): World =
        let placed = Walker.settle(res#collision, WalkDoc.rec(res#walk), Walker.standing(at#x, 0.0, at#z, yawDeg));
        mapSession(s -> { walker = { pitch = pitchDeg * Num.pi() / 180.0 | placed } | s }, w)

    /// 今いる区画（壁の中・迷路の外は None）。
    pub def zoneOf(res: Res.Res, w: World): Option[Char] =
        let b = walkerOf(w);
        Maze.zoneAt(res#maze, b#x, b#z)

    /// 遊びの時計の今（秒）。
    pub def seconds(w: World): Float64 = Clock.secondsOf(Clock.nowOf(w#play))

    /// 遊びの時計の進み方: 終了の確認の窓が出ている間は止める（App.addClock が毎フレーム 1 回だけ進める）。
    pub def paceOf(w: World): Clock.Pace[PlayClock.Play, PlayClock.Halt] =
        Clock.paceOf(if (w#quit == Quit.Asking) Clock.Run.Paused(PlayClock.Halt.AskingQuit) else Clock.Run.Running)

    /// 入力から次の状態を作る（秒は遊びの時計がこのコマに進んだ分）。終了の確認の窓が出ている間は歩かない。
    pub def step(res: Res.Res, input: Input, w: World): World =
        if (w#quit != Quit.Playing) w
        else mapSession(s -> { walker = Walker.step(res#collision, WalkDoc.rec(res#walk), input#drive, w#play, s#walker) | s }, w)

    // ── マウスの視点・診断 ──

    /// マウスを窓にキャプチャして視点を回しているか（App.withMouseCapture がこれを見て当てる）。
    pub def isLooking(w: World): Bool = sessionOf(w)#look == Look.Captured

    /// キャプチャを始める・放す。終了の確認の窓が出ている間はキャプチャしない（窓の中を押せない）。
    pub def setLooking(on: Bool, w: World): World =
        mapSession(s -> { look = if (on and w#quit == Quit.Playing) Look.Captured else Look.Released | s }, w)

    /// F3 の診断の表示を切り替える。
    pub def toggleDiagnostics(w: World): World =
        mapSession(s -> { diagnosticsView = if (s#diagnosticsView == DiagnosticsView.Shown) DiagnosticsView.Hidden else DiagnosticsView.Shown | s }, w)

    /// F3 の診断を出しているか。
    pub def showsDiagnostics(w: World): Bool = sessionOf(w)#diagnosticsView == DiagnosticsView.Shown

    // ── 終了の確認 ──

    /// Esc・閉じるボタン: 遊んでいる間なら確認の窓を出す（キャプチャは放す）。
    pub def askQuit(w: World): World =
        if (w#quit == Quit.Playing) mapSession(s -> { look = Look.Released | s }, { quit = Quit.Asking | w }) else w

    /// 確認の窓への答え（yes なら終わる・no なら遊びへ戻る）。窓が出ていないときは何もしない。
    pub def answerQuit(yes: Bool, w: World): World =
        if (w#quit != Quit.Asking) w
        else if (yes) { quit = Quit.Confirmed | w }
        else { quit = Quit.Playing | w }

    pub def isAskingQuit(w: World): Bool = w#quit == Quit.Asking

    pub def isQuitting(w: World): Bool = w#quit == Quit.Confirmed
}
