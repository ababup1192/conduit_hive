// World — 遊びの状態そのものと、次の状態を作る規則（すべて純粋）。
// Doc と迷路（形・当たり判定・絵）は Res が持ち、World は持たない（読む口は res を受ける）。
//
// ── 場面 ──
// Play = 一人称で迷路を歩き、撃つ。表紙・クリアなどを足す時は Screen に case を足し、step と View を match で分ける。
//
// ── 撃つ ──
// 引き金を引いて撃てる時（Arsenal.canFire）、照準（反動で跳ね上がった分を含む）からのレイを的の列へ当て（Hitscan）、
// 当たった所に火花・銃口にマズルフラッシュの粒を出す（Particles3d）。弾は飛ばない。
mod World {

    use fge::{Camera3d, Clock, Num, Vec3}

    /// このフレームの入力: 歩き方（Walker.Drive）・引き金・持ち替え。
    pub type alias Input = { drive = Walker.Drive, trigger = Arsenal.Trigger, choice = Arsenal.Choice }

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

    /// 歩いている間の中身: 体・マウスの視点・F3 の診断を出すか・武器・見回しの遅れ（度。ビューモデルの揺れ）・3D の粒。
    pub type alias SessionRec = {
        walker = Walker.Walker,
        look = Look,
        diagnosticsView = DiagnosticsView,
        arsenal = Arsenal.Arsenal,
        sway = { x = Float64, y = Float64 },
        particles = List[Particles3d.Particle]
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
          screen = Screen.Play(SessionOf.SessionOf({ walker = startWalker(res), look = Look.Released, diagnosticsView = DiagnosticsView.Hidden,
                                                     arsenal = Arsenal.initial(res#weapons), sway = { x = 0.0, y = 0.0 }, particles = Nil })) }

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

    /// 入力から次の状態を作る（秒は遊びの時計がこのコマに進んだ分）。終了の確認の窓が出ている間は歩かず撃たない。
    pub def step(res: Res.Res, input: Input, w: World): World =
        if (w#quit != Quit.Playing) w
        else mapSession(stepSession(res, input, w#play), w)

    /// 歩くだけの入力（引き金は引かず・持ち替えない）。
    pub def walking(d: Walker.Drive): Input = { drive = d, trigger = Arsenal.released(), choice = Arsenal.Choice.Keep }

    /// 1 コマ: 歩く → 見回しの遅れ → 持ち替え → 撃つ → 消えた粒を落とす。
    def stepSession(res: Res.Res, input: Input, clock: Clock.Clock[PlayClock.Play], s: SessionRec): SessionRec =
        let t = Clock.secondsOf(Clock.nowOf(clock));
        let dt = Num.clamp(0.0, 0.05, Clock.dtOf(clock));
        let vm = HandsDoc.rec(res#hands);
        let equipped = Arsenal.equip(vm, t, input#choice, s#arsenal);
        let moved = { walker = Walker.step(res#collision, WalkDoc.rec(res#walk), input#drive, clock, s#walker),
                      sway = swayAfter(vm, input#drive, dt, s#sway), arsenal = equipped, particles = Particles3d.step(t, s#particles) | s };
        let wants = Arsenal.wantsToFire(Arsenal.statsOf(res#weapons, equipped), input#trigger);
        if (wants and Arsenal.canFire(res#weapons, t, equipped)) shoot(res, t, moved) else moved

    /// 見回しの遅れ: このコマに回した角を足し、上限で切り、swayFollow 秒ほどで 0 へ戻す。
    def swayAfter(vm: HandsDoc.Rec, d: Walker.Drive, dt: Float64, sway: { x = Float64, y = Float64 }): { x = Float64, y = Float64 } =
        let keep = Float64.exp(0.0 - dt / Float64.max(0.001, vm#swayFollow));
        let clampMax = v -> Num.clamp(0.0 - vm#swayMax, vm#swayMax, v);
        { x = clampMax(sway#x + d#turnDeg + d#turnRate * dt) * keep, y = clampMax(sway#y + d#lookDeg) * keep }

    /// 時刻 t に構えている武器で 1 回撃つ: 照準から粒を飛ばし、当たった所に火花・銃口にマズルフラッシュを出す。
    def shoot(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let a = s#arsenal;
        let impacts = Hitscan.fire(res#hitTargets, aimOf(res, t, s), Arsenal.statsOf(res#weapons, a), a#shots);
        let pdoc = Particles3dDoc.rec(res#particles);
        // WhyNot: 粒の真ん中を当たった点・銃口の点に置かない — 面を向いたビルボードの半分が壁や銃身に埋まる。粒の半分の大きさだけ手前へ出す。
        let sparks = impacts |> List.zipWithIndex |> List.flatMap(e -> {
            let (i, hit) = e;
            let lifted = Vec3.add(hit#point, Vec3.mul(hit#normal, pdoc#spark#size * 0.5));
            Particles3d.emit(res#particles, Particles3d.Kind.Spark, Particles3d.Space.World, lifted, hit#normal, t, a#shots * 64 + i)
        });
        let ahead = pdoc#muzzle#size * 0.5;
        let flash = Particles3d.emit(res#particles, Particles3d.Kind.Muzzle, Particles3d.Space.Muzzle, Vec3.v3(0.0, 0.0, ahead), Vec3.v3(0.0, 0.0, 1.0), t, a#shots);
        { arsenal = Arsenal.fire(res#weapons, t, a), particles = List.append(flash, List.append(sparks, s#particles)) | s }

    /// 時刻 t の照準のカメラ: 目の位置・向きに、反動で跳ね上がった角を足す（撃つレイと描く場面が同じ物を使う）。
    def aimOf(res: Res.Res, t: Float64, s: SessionRec): Camera3d.Camera3d =
        let walk = WalkDoc.rec(res#walk);
        let punch = Arsenal.punchAt(res#weapons, HandsDoc.rec(res#hands), t, s#arsenal);
        { eye = Walker.eyeOf(walk, s#walker), yaw = s#walker#yaw, pitch = s#walker#pitch - punch * Num.pi() / 180.0,
          fovY = walk#fovY * Num.pi() / 180.0, near = 0.05, far = LookDoc.rec(res#look)#fogFar }

    /// 今の照準のカメラ。
    pub def cameraOf(res: Res.Res, w: World): Camera3d.Camera3d = aimOf(res, seconds(w), sessionOf(w))

    /// 今の武器の状態。
    pub def arsenalOf(w: World): Arsenal.Arsenal = sessionOf(w)#arsenal

    /// 今の 3D の粒。
    pub def particlesOf(w: World): List[Particles3d.Particle] = sessionOf(w)#particles

    /// 今の見回しの遅れ（度）。
    pub def swayOf(w: World): { x = Float64, y = Float64 } = sessionOf(w)#sway

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
