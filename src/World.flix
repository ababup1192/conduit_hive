// World — 遊びの状態そのものと、次の状態を作る規則（すべて純粋）。
// Doc と迷路（形・当たり判定・絵）は Res が持ち、World は持たない（読む口は res を受ける）。
//
// ── 画面 ──
// Title（迷路をゆっくり見回す背景にゲームの名前と操作）→ Play（一人称で迷路を歩き、撃つ）→ Clear（かかった時間と倒した数）→ Title。
// Play の値は Session に持ち、読む口は Session を受ける（sessionOf で場面を選んでから読む）。Esc のポーズは Session の pause。
// 画面を足す時は Screen に case を足し、step と View の入口を match で分ける。
//
// ── 拾う ──
// 迷路の pickup の印に置いた物（Res の pickupPoints）に足元が近づくと拾う（Pickups.collect。満タン・上限なら拾わない）。
// 拾った物の番号は taken に残り、やり直しても戻らない。拾った時の知らせは notice（文言は View が UiTextDoc から作る）。
//
// ── 弾が尽きた時 ──
// 弾の尽きた武器で引き金を引くと空撃ち（撃てない・間隔だけ空く）になり、弾のある武器へ自動で持ち替える（Arsenal.dryFire）。
//
// ── クリア ──
// 最後の部屋の wave を全部始め、その wave の敵が全部倒れたらクリア（Event.Cleared）。clearSeconds の後に Clear の画面へ移る。
//
// ── 起きた事 ──
// 1 コマに起きた事（撃った・当たった・倒れた・被弾…）は Session の events にそのコマの分だけ持つ。音（Sounds）はそれを写すだけ。
// 撃った後に遅れて起きる事（薬莢が落ちる・先台を引く）は pending に時刻つきで控え、その時刻を迎えたコマの events へ出す。
//
// ── 撃つ ──
// 引き金を引いて撃てる時（Arsenal.canFire）、照準（反動で跳ね上がった分を含む）からのレイを敵と的の列へ当て（Hitscan）、
// 壁に当たった所に火花と煙・敵に当たった所に体液の飛沫・銃口に武器ごとのマズルフラッシュの粒を出す（Particles3d）。弾は飛ばない
// （連射銃の曳光弾は当たった所まで飛ぶ絵だけ。Tracers）。撃つと描くカメラが揺れ（CameraShake）、照準に当てた印と倒した印が出る（marks）。
//
// ── 倒す ──
// 倒れた敵は撃たれた向きへ吹っ飛ぶか、条件に当たれば弾けて肉片と体液と衝撃の輪と短い光になる（Horde.applyDamage・Gibs）。
// 1 コマに multiKill 体以上倒した時と、群れの最後の 1 体（生きている敵も湧くのを待つ敵もいない）を倒した時は hit stop
// （遊びの時計を止めて遅く流す。paceOf が Clock.withSlow で宣言し、App が時計に掛ける）。
//
// ── 囲まれた時の技 ──
// Shift で走る間はスタミナが減り、走り切ると息切れして resumeAt まで戻るまで走れない。Space で押している向き（無ければ後ろ）へ緊急回避
// （跳ぶ間の初めは攻撃が当たらない i-frame・壁は Walker の moveAndSlide が止める）。F で前の扇の敵を蹴って押し返す（Horde.kick）。
// G で手榴弾を投げ、信管が尽きると爆発して半径の内の敵を吹っ飛ばし・弾けさせ、近ければ自分も傷を受ける（Grenades・Horde.blast）。
// 値は MovesDoc と GrenadeDoc。スタミナが足りずに技を使えなかった時は StaminaOut（音で知らせる）。
//
// ── 敵と体力 ──
// 部屋（区画の種類が Room）に入ると、その入口を checkpoint に控え、まだ入っていない区画なら wave を始める（Horde.enter。通路も wave を持てる）。
// 群れは毎コマ Horde.step で進み、プレイヤーが受けた傷は Health に足す。体力が 0 で倒れ、respawnSeconds の後に checkpoint から
// やり直す（敵と projectile と落とした物を消し、wave の進みを checkpoint に控えた「終えた区画」だけに戻す。ほかの区画はもう一度入ると最初の wave から）。
// 倒れた敵は時々弾や回復を落とす（Pickups.dropsOf）。紹介の動画の自動の操縦の間だけ、最後の部屋の wave を TourDoc の finalWaves までにする。
mod World {

    use fge::{Camera3d, Clock, Hash01, Num, TimeScale, Vec3}
    use Events.Event

    /// このフレームの入力: 歩き方（Walker.Drive）・引き金・持ち替え・このコマに押した技（緊急回避・蹴り・手榴弾）。
    pub type alias Input = { drive = Walker.Drive, trigger = Arsenal.Trigger, choice = Arsenal.Choice, moves = Moves.Press }

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
        case Start     // タイトルの画面（Enter と同じ）
        case Resume    // ポーズの「続ける」
        case ToTitle   // ポーズの「タイトルへ」・クリアの画面
    }

    /// ポーズの項目（上から）。
    pub enum PauseItem with Eq, ToString {
        case Resume
        case ToTitle
    }

    /// Esc のポーズ。Paused は選んでいる項目を持つ（遊びの時計は止まる）。
    pub enum Pause with Eq, ToString {
        case Running
        case Paused(PauseItem)
    }

    /// 拾った時の知らせ: 種類・量・拾った時刻。
    pub type alias Notice = { kind = Pickups.Kind, amount = Int32, at = Float64 }

    /// 照準の印: 最後に敵へ当てた時刻と、最後に倒した時刻（遊びの時計の秒）。
    pub type alias Marks = { hitAt = Float64, killAt = Float64 }

    /// hit stop: 合図の時刻（遊びの時計）と、群れの最後の 1 体を倒した時か（長く止める）。
    pub type alias HitStop = { at = Clock.Time[PlayClock.Play], last = Bool }

    /// クリアの記録: かかった時間（秒）・倒した数・最後に立っていた所と向き（ラジアン。結果の画面の背景がそこから見回す）・クリアした時刻。
    pub type alias Tally = { seconds = Float64, kills = Int32, x = Float64, z = Float64, yaw = Float64, endedAt = Float64 }

    /// やり直す所: 部屋に入った時の足元と向き（度）と、その部屋と、その時の武器と弾・持っていた手榴弾の数・倒した数・拾った物の番号・終えた区画の wave の進みの写し
    /// （倒れてやり直すと、部屋の群れと一緒にこれらもその時へ戻る）。
    pub type alias Checkpoint = { x = Float64, z = Float64, yawDeg = Float64, zone = Option[Char], arsenal = Arsenal.Arsenal, grenades = Int32, kills = Int32,
                                  taken = Set[Int32], waves = Map[Char, Spawner.Progress] }

    /// 歩いている間の中身: 体・マウスの視点・F3 の診断を出すか・武器・見回しの遅れ（度。ビューモデルの揺れ）・3D の粒・
    /// 敵の群れ・体力・やり直す所・最後にいた区画（壁の中の None は数えない）・このコマに起きた事・
    /// ポーズ・拾った物の番号・倒れた敵が落とした物・拾った時の知らせ・倒した数・始めた時刻・クリアした時刻・
    /// 紹介の動画の自動の操縦（`start tour` の時だけ Some。キーとマウスの代わりに歩いて撃ち、体力と弾を TourDoc の下限より下げない）・
    /// 後の時刻に起きる事（時刻と起きる事。撃った後の薬莢と先台）・連射銃の曳光弾・弾けた肉片・描くカメラの揺れ・照準の印・hit stop・
    /// 囲まれた時の技（スタミナ・緊急回避・蹴り）・手榴弾（持っている数・飛んでいる物・爆発）。
    pub type alias SessionRec = {
        walker = Walker.Walker,
        look = Look,
        diagnosticsView = DiagnosticsView,
        arsenal = Arsenal.Arsenal,
        sway = { x = Float64, y = Float64 },
        particles = List[Particles3d.Particle],
        horde = Horde.Horde,
        health = Health.Health,
        checkpoint = Checkpoint,
        lastZone = Option[Char],
        events = List[Event],
        pause = Pause,
        taken = Set[Int32],
        drops = List[Pickups.Drop],
        notice = Option[Notice],
        kills = Int32,
        startedAt = Float64,
        clearedAt = Option[Float64],
        pilot = Option[Pilot.State],
        pending = List[{ at = Float64, event = Event }],
        tracers = List[Tracers.Tracer],
        gibs = Gibs.State,
        shake = CameraShake.Shake,
        marks = Marks,
        hitStop = HitStop,
        moves = Moves.Moves,
        grenades = Grenades.State
    }

    /// 歩いている間の中身。作るのは World の中だけ。読む口は Session を受ける関数・書く口は mapSession。
    enum SessionOf(SessionRec)

    pub type alias Session = SessionOf

    /// どの画面か。その画面だけが持つ値を payload に持つ。
    pub enum Screen {
        case Title
        case Play(Session)
        case Clear(Tally)
    }

    /// 遊びの状態。play = 遊びの時計（歩く・頭の上下・タイトルの見回しがこれを見る。終了の確認とポーズの間は止まる）。
    /// events = このコマに起きた画面をまたぐ事（遊び始めた・ポーズ・項目・タイトルへ・クリアの画面へ）。Controls.step の頭で空にする。
    pub type alias World = {
        play = Clock.Clock[PlayClock.Play],
        screen = Screen,
        quit = Quit,
        events = List[Event]
    }

    // ── 盤の寸法（design 480×270。project.json と同じ値） ──

    pub def width(): Float64 = 480.0
    pub def height(): Float64 = 270.0

    pub def spritePath(): String = "assets/conduit_hive.sprite.json"

    /// 歩き始める体（迷路の start の印に立ち、足元を床に合わせる）。
    pub def startWalker(res: Res.Res): Walker.Walker =
        let s = res#maze#start;
        Walker.settle(res#collision, WalkDoc.rec(res#walk), Walker.standing(s#x, 0.0, s#z, s#yaw))

    /// 時刻 t に遊び始める中身（やり直す所は迷路の start の印）。
    def freshSession(res: Res.Res, t: Float64): SessionRec =
        let s = res#maze#start;
        let grenades = Grenades.initial(GrenadeDoc.rec(res#grenade));
        { walker = startWalker(res), look = Look.Released, diagnosticsView = DiagnosticsView.Hidden,
          arsenal = Arsenal.initial(res#weapons), sway = { x = 0.0, y = 0.0 }, particles = Nil,
          horde = Horde.empty(), health = Health.full(PlayerDoc.rec(res#player)),
          checkpoint = { x = s#x, z = s#z, yawDeg = s#yaw, zone = None, arsenal = Arsenal.initial(res#weapons), grenades = grenades#carried, kills = 0, taken = Set.empty(), waves = Map.empty() },
          lastZone = None, events = Nil,
          pause = Pause.Running, taken = Set.empty(), drops = Nil, notice = None, kills = 0, startedAt = t, clearedAt = None, pilot = None, pending = Nil,
          tracers = Nil, gibs = Gibs.empty(), shake = CameraShake.none(), marks = noMarks(), hitStop = { at = Clock.never(), last = false },
          moves = Moves.initial(MovesDoc.rec(res#moves)), grenades = grenades }

    def noMarks(): Marks = { hitAt = -1000.0, killAt = -1000.0 }

    /// 遊びから始める状態（迷路の start の印に立ち、始めた時刻は 0 秒）。
    pub def initial(res: Res.Res): World =
        { play = Clock.start(), quit = Quit.Playing, screen = Screen.Play(SessionOf.SessionOf(freshSession(res, 0.0))), events = Nil }

    /// タイトルの画面から始める状態（起動の既定）。
    pub def title(): World = { play = Clock.start(), quit = Quit.Playing, screen = Screen.Title, events = Nil }

    /// 今の時計のまま、迷路の start の印から遊び直す（始めた時刻は今。タイトルにいた時間をかかった時間に足さない）。
    pub def restart(res: Res.Res, w: World): World =
        { screen = Screen.Play(SessionOf.SessionOf(freshSession(res, seconds(w)))), quit = Quit.Playing | w }

    /// 遊んでいる場面に自動の操縦を付ける（紹介の動画の `start tour`）。
    pub def withPilot(w: World): World = mapSession(s -> { pilot = Some(Pilot.start()), look = Look.Captured | s }, w)

    /// 自動の操縦が狙っている敵の番号（付いていない・狙っていなければ None。測りが様子を書く）。
    pub def pilotTargetOf(w: World): Option[Int32] = sessionOf(w) |> Option.flatMap(s -> rec(s)#pilot) |> Option.flatMap(p -> p#target)

    /// 自動の操縦が向かっている点の名前（付いていない・歩き終えたら空）。
    pub def pilotPoint(res: Res.Res, w: World): String =
        sessionOf(w) |> Option.flatMap(s -> rec(s)#pilot) |> Option.map(Pilot.pointName(TourDoc.rec(res#tour))) |> Option.getWithDefault("")

    /// このコマに起きた画面をまたぐ事。
    pub def screenEventsOf(w: World): List[Event] = w#events

    /// コマの頭: 前のコマの画面をまたぐ事を消す（Controls.step が最初に呼ぶ）。
    pub def beginFrame(w: World): World = { events = Nil | w }

    def withEvent(e: Event, w: World): World = { events = List.append(w#events, e :: Nil) | w }

    def rec(s: Session): SessionRec = match s { case SessionOf.SessionOf(r) => r }

    /// 遊んでいる場面の中身（ほかの画面なら None）。
    pub def sessionOf(w: World): Option[Session] = match w#screen {
        case Screen.Play(s) => Some(s)
        case _              => None
    }

    def mapSession(f: SessionRec -> SessionRec, w: World): World = match w#screen {
        case Screen.Play(s) => { screen = Screen.Play(SessionOf.SessionOf(f(rec(s)))) | w }
        case _              => w
    }

    // ── 画面を移る ──

    /// タイトルから遊び始める（マウスをキャプチャして視点を回す）。タイトルでなければ何もしない。
    pub def startPlay(res: Res.Res, w: World): World = match w#screen {
        case Screen.Title => withEvent(Event.Started, { screen = Screen.Play(SessionOf.SessionOf({ look = Look.Captured | freshSession(res, seconds(w)) })) | w })
        case _            => w
    }

    /// タイトルへ戻る（ポーズの「タイトルへ」・クリアの画面）。
    pub def toTitle(w: World): World = withEvent(Event.ToTitle, { screen = Screen.Title | w })

    /// タイトルの画面か。
    pub def isOnTitle(w: World): Bool = match w#screen {
        case Screen.Title => true
        case _            => false
    }

    /// クリアの記録（クリアの画面でなければ None）。
    pub def tallyOf(w: World): Option[Tally] = match w#screen {
        case Screen.Clear(t) => Some(t)
        case _               => None
    }

    // ── ポーズ ──

    /// ポーズしているか（遊んでいる場面の時だけ）。
    pub def isPaused(w: World): Bool = sessionOf(w) |> Option.exists(s -> rec(s)#pause != Pause.Running)

    /// 遊んでいる場面のポーズ。
    pub def pauseOf(s: Session): Pause = rec(s)#pause

    /// Esc: ポーズする（キャプチャは放し、「続ける」を選んだ所から）。
    /// 遊んでいて、ポーズしていなければ何もしない。
    pub def pause(w: World): World =
        if (Option.isEmpty(sessionOf(w)) or isPaused(w)) w
        else withEvent(Event.Paused, mapSession(s -> { pause = Pause.Paused(PauseItem.Resume), look = Look.Released | s }, w))

    /// ポーズを解いて遊びへ戻る（マウスをキャプチャし直す）。ポーズしていなければ何もしない。
    pub def resume(w: World): World =
        if (not isPaused(w)) w
        else withEvent(Event.Resumed, mapSession(s -> { pause = Pause.Running, look = Look.Captured | s }, w))

    /// ポーズの項目を上下に動かす（項目は 2 つなので、どちらへ動かしても入れ替わる）。
    pub def movePauseSelection(w: World): World =
        if (not isPaused(w)) w else withEvent(Event.MenuMoved, mapSession(s -> { pause = otherItem(s#pause) | s }, w))

    def otherItem(p: Pause): Pause = match p {
        case Pause.Paused(PauseItem.Resume)  => Pause.Paused(PauseItem.ToTitle)
        case Pause.Paused(PauseItem.ToTitle) => Pause.Paused(PauseItem.Resume)
        case Pause.Running                   => Pause.Running
    }

    /// ポーズで選んでいる項目を決める（続ける・タイトルへ）。ポーズしていなければ何もしない。
    pub def choosePause(w: World): World =
        let chosen = sessionOf(w) |> Option.map(s -> rec(s)#pause);
        if (chosen == Some(Pause.Paused(PauseItem.Resume))) resume(withEvent(Event.MenuChosen, w))
        else if (chosen == Some(Pause.Paused(PauseItem.ToTitle))) toTitle(withEvent(Event.MenuChosen, w))
        else w

    // ── 遊んでいる場面を読む（Session を受ける） ──

    /// 今の体。
    pub def walkerOf(s: Session): Walker.Walker = rec(s)#walker

    /// 今の武器の状態。
    pub def arsenalOf(s: Session): Arsenal.Arsenal = rec(s)#arsenal

    /// 今の 3D の粒。
    pub def particlesOf(s: Session): List[Particles3d.Particle] = rec(s)#particles

    /// 飛んでいる曳光弾。
    pub def tracersOf(s: Session): List[Tracers.Tracer] = rec(s)#tracers

    /// 弾けた肉片と、最近弾けた所。
    pub def gibsOf(s: Session): Gibs.State = rec(s)#gibs

    /// 照準の印の時刻。
    pub def marksOf(s: Session): Marks = rec(s)#marks

    /// 今の見回しの遅れ（度）。
    pub def swayOf(s: Session): { x = Float64, y = Float64 } = rec(s)#sway

    /// 今の敵の群れ。
    pub def hordeOf(s: Session): Horde.Horde = rec(s)#horde

    /// 今の体力。
    pub def healthOf(s: Session): Health.Health = rec(s)#health

    /// やり直す所。
    pub def checkpointOf(s: Session): Checkpoint = rec(s)#checkpoint

    /// このコマに起きた事。
    pub def eventsOf(s: Session): List[Event] = rec(s)#events

    /// 拾った物の番号。
    pub def takenOf(s: Session): Set[Int32] = rec(s)#taken

    /// 倒れた敵が落とした、まだ拾っていない物。
    pub def dropsOf(s: Session): List[Pickups.Drop] = rec(s)#drops

    /// 最後に拾った時の知らせ（まだ拾っていなければ None）。
    pub def noticeOf(s: Session): Option[Notice] = rec(s)#notice

    /// 倒した数。
    pub def killsOf(s: Session): Int32 = rec(s)#kills

    /// 時刻 t の描くカメラ（照準のカメラに、揺れと撃った時に目が後ろへ下がる跳ねを足す）。
    pub def cameraOf(res: Res.Res, t: Float64, s: Session): Camera3d.Camera3d = viewOf(res, t, rec(s))

    /// 時刻 t の照準のカメラ（撃つレイと同じ物。揺れも跳ねも無し）。
    pub def aimCameraOf(res: Res.Res, t: Float64, s: Session): Camera3d.Camera3d = aimOf(res, t, rec(s))

    /// F3 の診断を出しているか。
    pub def showsDiagnosticsIn(s: Session): Bool = rec(s)#diagnosticsView == DiagnosticsView.Shown

    /// 今の技の状態（スタミナ・緊急回避・蹴り）。
    pub def movesOf(s: Session): Moves.Moves = rec(s)#moves

    /// 今の手榴弾（持っている数・飛んでいる物・爆発）。
    pub def grenadesOf(s: Session): Grenades.State = rec(s)#grenades

    /// 体を x・z に置き直す（描き出しの場面・始まり）。向きと見下ろす角は度。足元は床に合わせる。
    pub def placeWalker(res: Res.Res, at: { x = Float64, z = Float64 }, yawDeg: Float64, pitchDeg: Float64, w: World): World =
        let placed = Walker.settle(res#collision, WalkDoc.rec(res#walk), Walker.standing(at#x, 0.0, at#z, yawDeg));
        mapSession(s -> { walker = { pitch = pitchDeg * Num.pi() / 180.0 | placed } | s }, w)

    /// 今いる区画（遊んでいない・壁の中・迷路の外は None）。
    pub def zoneOf(res: Res.Res, w: World): Option[Char] =
        sessionOf(w) |> Option.flatMap(s -> { let b = walkerOf(s); Maze.zoneAt(res#maze, b#x, b#z) })

    /// 遊びの時計の今（秒）。
    pub def seconds(w: World): Float64 = Clock.secondsOf(Clock.nowOf(w#play))

    /// 遊びの時計の進み方: 終了の確認の窓が出ている間とポーズの間は止める（App.addClock が毎フレーム 1 回だけ進める）。
    /// 遊んでいる間は、最後の hit stop の合図から JuiceDoc の hitStop の形で止めて遅く流す。
    pub def paceOf(res: Res.Res, w: World): Clock.Pace[PlayClock.Play, PlayClock.Halt] =
        let pace = Clock.paceOf(
            if (w#quit == Quit.Asking) Clock.Run.Paused(PlayClock.Halt.AskingQuit)
            else if (isPaused(w)) Clock.Run.Paused(PlayClock.Halt.Paused)
            else Clock.Run.Running);
        sessionOf(w) |> Option.map(s -> Clock.withSlow(rec(s)#hitStop#at, hitStopPlan(JuiceDoc.rec(res#juice)#hitStop, rec(s)#hitStop#last), pace))
            |> Option.getWithDefault(pace)

    /// hit stop の形（last = 群れの最後の 1 体）: freeze 秒止め、slow 秒を slowScale 倍で流し、ramp 秒で等速へ戻す（秒は実時間）。
    def hitStopPlan(h: JuiceDoc.HitStop, last: Bool): TimeScale.Plan =
        TimeScale.freezeThenSlow({ freeze = if (last) h#lastFreeze else h#freeze, freezeScale = 0.0,
                                   slow = if (last) h#lastSlow else h#slow, slowScale = h#slowScale, ramp = h#ramp })

    /// 入力から次の状態を作る（秒は遊びの時計がこのコマに進んだ分）。終了の確認の窓・ポーズの間は歩かず撃たない（起きた事も無い）。
    /// クリアしてから clearSeconds が過ぎたコマに、クリアの画面へ移る。
    pub def step(res: Res.Res, input: Input, w: World): World = match w#screen {
        case Screen.Play(s) if w#quit != Quit.Playing or rec(s)#pause != Pause.Running => mapSession(r -> { events = Nil | r }, w)
        case Screen.Play(s) =>
            let r = if (Option.isEmpty(rec(s)#pilot)) res else { wavePlans = res#tourWavePlans | res };
            let (command, pilot) = pilotInput(r, w#play, input, rec(s));
            let next = guarded(r, { pilot = pilot | stepSession(r, command, w#play, rec(s)) });
            if (isClearDue(res, w#play, next)) withEvent(Event.ClearShown, { screen = Screen.Clear(tallyAt(w#play, next)) | w })
            else { screen = Screen.Play(SessionOf.SessionOf(next)) | w }
        case _ => w
    }

    /// 自動の操縦が付いていれば、その入力と次の状態（付いていなければ手の入力のまま）。
    def pilotInput(res: Res.Res, clock: Clock.Clock[PlayClock.Play], input: Input, s: SessionRec): (Input, Option[Pilot.State]) =
        let at = { t = Clock.secondsOf(Clock.nowOf(clock)), dt = Num.clamp(0.0, 0.05, Clock.dtOf(clock)),
                   walker = s#walker, arsenal = s#arsenal, horde = s#horde, moves = s#moves, grenades = s#grenades };
        s#pilot |> Option.map(p -> { let (command, next) = Pilot.drive(res, at, p); (command, Some(next)) })
                |> Option.getWithDefault((input, None))

    /// 自動の操縦の間だけ、体力を TourDoc の下限より下げず、弾が下限を切ったら上限まで足し、手榴弾を下限より減らさない。
    def guarded(res: Res.Res, s: SessionRec): SessionRec =
        let tour = TourDoc.rec(res#tour);
        if (Option.isEmpty(s#pilot)) s
        else { health = Health.atLeast(tour#minHealth, s#health), arsenal = Arsenal.refilledBelow(res#weapons, tour#minAmmo, s#arsenal),
               grenades = Grenades.atLeast(tour#minGrenades, s#grenades) | s }

    /// クリアしてから clearSeconds が過ぎたか。
    def isClearDue(res: Res.Res, clock: Clock.Clock[PlayClock.Play], s: SessionRec): Bool =
        s#clearedAt |> Option.exists(at -> Clock.secondsOf(Clock.nowOf(clock)) - at >= PlayerDoc.rec(res#player)#clearSeconds)

    /// 今のクリアの記録（かかった時間はクリアした時刻まで）。
    def tallyAt(clock: Clock.Clock[PlayClock.Play], s: SessionRec): Tally =
        let endAt = s#clearedAt |> Option.getWithDefault(Clock.secondsOf(Clock.nowOf(clock)));
        { seconds = endAt - s#startedAt, kills = s#kills, x = s#walker#x, z = s#walker#z, yaw = s#walker#yaw, endedAt = endAt }

    /// 歩くだけの入力（引き金は引かず・持ち替えず・技も使わない）。
    pub def walking(d: Walker.Drive): Input = { drive = d, trigger = Arsenal.released(), choice = Arsenal.Choice.Keep, moves = Moves.none() }

    /// 1 コマ: 倒れている間はやり直す時刻を待つだけ。ほかは 技を押す（回避・蹴り）→ 歩く（か跳ぶ）とスタミナ → 見回しの遅れ → 持ち替え → 部屋に入る → 拾う →
    /// 撃つ（か空撃ち）→ 手榴弾を投げる・飛ばす・爆発 → 群れ → 傷と粒 → 倒した数とクリア。
    def stepSession(res: Res.Res, input: Input, clock: Clock.Clock[PlayClock.Play], s0: SessionRec): SessionRec =
        let t = Clock.secondsOf(Clock.nowOf(clock));
        let (due, later) = List.partition(p -> p#at <= t, s0#pending);
        let s = { events = due |> List.map(p -> p#event), pending = later | s0 };
        let dt = Num.clamp(0.0, 0.05, Clock.dtOf(clock));
        let pd = PlayerDoc.rec(res#player);
        if (Health.isRespawnDue(pd, t, s#health)) respawn(res, s)
        else if (Health.isDown(s#health)) { particles = Particles3d.step(t, s#particles), gibs = Gibs.step(JuiceDoc.rec(res#juice)#gib, lineOfSightIn(res), t, dt, s#gibs),
                                              tracers = Tracers.step(Particles3dDoc.rec(res#particles)#tracer, t, s#tracers) | s }
        else {
            let vm = FpViewmodelDoc.rec(res#viewmodel);
            let equipped = Arsenal.equip(vm, t, input#choice, s#arsenal);
            let braced = s |> pressDodge(res, t, dt, input) |> pressKick(res, t, input);
            let stepped = walked(res, clock, t, dt, input#drive, braced);
            let moved = { sway = swayAfter(vm, input#drive, dt, s#sway), arsenal = equipped, particles = Particles3d.step(t, stepped#particles),
                          gibs = Gibs.step(JuiceDoc.rec(res#juice)#gib, lineOfSightIn(res), t, dt, s#gibs),
                          tracers = Tracers.step(Particles3dDoc.rec(res#particles)#tracer, t, s#tracers),
                          drops = Pickups.keepDrops(t, PickupsDoc.rec(res#pickups)#dropLimit, stepped#drops),
                          events = List.append(stepped#events, switched(s#arsenal, equipped)) | stepped };
            let picked = pickUp(res, t, enterZone(res, t, moved));
            let a = picked#arsenal;
            let wants = Arsenal.wantsToFire(Arsenal.statsOf(res#weapons, a), input#trigger);
            let fired =
                if (wants and Arsenal.canFire(res#weapons, t, a)) shoot(res, t, dt, picked)
                else if (wants and Arsenal.isReady(t, a) and Arsenal.isEmpty(res#weapons, a)) dryFire(res, t, picked)
                else picked;
            let thrown = if (Moves.isPressed(Moves.Move.Grenade, input#moves)) toss(res, t, fired) else fired;
            hitStopped(res, clock, tally(res, t, stepHorde(res, t, dt, flyGrenades(res, clock, t, dt, thrown))))
        }

    // ── 技（緊急回避・蹴り）とスタミナ ──

    /// 回避を押した: 押している向き（無ければ後ろ）へ跳び始める。スタミナが足りなければ StaminaOut。
    def pressDodge(res: Res.Res, t: Float64, dt: Float64, input: Input, s: SessionRec): SessionRec =
        if (not Moves.isPressed(Moves.Move.Dodge, input#moves)) s
        else {
            let yaw = s#walker#yaw;
            let heading = Moves.dodgeHeading(yaw, Walker.headingOf(yaw, input#drive));
            match Moves.dodge(MovesDoc.rec(res#moves)#dodge, t, dt, heading, s#moves) {
                case Ok(m)                     => { moves = m, events = List.append(s#events, Event.Dodged :: Nil) | s }
                case Err(Moves.Refusal.Tired)  => { events = List.append(s#events, Event.StaminaOut :: Nil) | s }
                case Err(Moves.Refusal.Busy)   => s
            }
        }

    /// 蹴りを押した: 前の扇の敵を押し返す（kickWith）。スタミナが足りなければ StaminaOut。
    def pressKick(res: Res.Res, t: Float64, input: Input, s: SessionRec): SessionRec =
        if (not Moves.isPressed(Moves.Move.Kick, input#moves)) s
        else match Moves.kick(MovesDoc.rec(res#moves)#kick, t, s#moves) {
            case Ok(m)                    => kickWith(res, t, { moves = m | s })
            case Err(Moves.Refusal.Tired) => { events = List.append(s#events, Event.StaminaOut :: Nil) | s }
            case Err(Moves.Refusal.Busy)  => s
        }

    /// 時刻 t に蹴る: 扇の内の敵を押し返して傷を付け、当たった敵の胸に体液・足元に埃を出し、描くカメラを揺らす。倒れた敵は物を落とす。
    // WhyNot: 足の先に衝撃の輪を出さない — 1 m 余りの目の前で広がる輪は画面の下で切れた太い弧になり、何の形か読めない。
    def kickWith(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let kd = MovesDoc.rec(res#moves)#kick;
        let b = s#walker;
        let k = { t = t, x = b#x, z = b#z, yaw = b#yaw, doc = kd };
        let targets = s#horde#enemies |> List.filter(Horde.isInKick(k));
        let damaged = Horde.kick(res, k, s#horde);
        let seed = Num.floorInt(t * 60.0) * 8;
        let splashes = targets |> List.flatMap(e -> List.append(
            Particles3d.emit(res#particles, Particles3d.Kind.Ichor, Particles3d.Space.World, Vec3.v3(e#x, 1.0, e#z), Vec3.v3(e#x - b#x, 0.4, e#z - b#z), t, seed + e#id * 2),
            Particles3d.emit(res#particles, Particles3d.Kind.Smoke, Particles3d.Space.World, Vec3.v3(e#x, 0.15, e#z), Vec3.v3(e#x - b#x, 1.0, e#z - b#z), t, seed + e#id * 2 + 1)));
        let jd = JuiceDoc.rec(res#juice);
        { horde = damaged#horde, drops = List.append(s#drops, Pickups.dropsOf(res#pickups, t, fallenOf(res, damaged#fallen))),
          particles = Particles3d.added(res#particles, splashes, s#particles),
          shake = CameraShake.add(jd#shake, t, kd#shake + jd#shake#kill * Int32.toFloat64(List.length(damaged#fallen)), s#shake),
          marks = { killAt = if (List.isEmpty(damaged#fallen)) s#marks#killAt else t | s#marks },
          events = List.flatten(s#events :: (Event.Kicked(List.length(targets)) :: Nil) :: damaged#events :: Nil) | s }

    /// 倒れた敵が物を落とす所（足元の区画。壁ぎわで区画の外なら湧いた部屋）。
    def fallenOf(res: Res.Res, fallen: List[Horde.Enemy]): List[Pickups.Fallen] =
        fallen |> List.map(e -> { id = e#id, x = e#x, z = e#z, zone = Maze.zoneAt(res#maze, e#x, e#z) |> Option.getWithDefault(e#home) })

    /// 歩く（か跳ぶ）とスタミナ: 跳んでいるコマは回避の速さで動かし、ほかは歩く。走るのは押していて、歩いていて、息切れしていない時だけで、
    /// 走る間はスタミナが減り、走り切ったコマに StaminaOut。
    def walked(res: Res.Res, clock: Clock.Clock[PlayClock.Play], t: Float64, dt: Float64, d: Walker.Drive, s: SessionRec): SessionRec =
        let md = MovesDoc.rec(res#moves);
        let walk = WalkDoc.rec(res#walk);
        match Moves.dashOf(md#dodge, t, dt, s#moves) {
            case Some(v) => { walker = Walker.dash(res#collision, walk, d, v, clock, s#walker), moves = Moves.breathe(md#stamina, t, dt, false, s#moves) | s }
            case None    =>
                let sprinting = d#sprint and (d#forward != 0.0 or d#strafe != 0.0) and Moves.canSprint(s#moves);
                let breathed = Moves.breathe(md#stamina, t, dt, sprinting, s#moves);
                let spent = sprinting and not Moves.canSprint(breathed);
                { walker = Walker.step(res#collision, walk, { sprint = sprinting | d }, clock, s#walker), moves = breathed,
                  events = if (spent) List.append(s#events, Event.StaminaOut :: Nil) else s#events | s }
        }

    // ── 手榴弾 ──

    /// 手榴弾を投げる: 目の少し前（壁に近ければ目）から照準の向きへ。持っていない・間がまだなら何もしない。
    def toss(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let aim = aimOf(res, t, s);
        let forward = Camera3d.forward(aim);
        let ahead = Vec3.add(aim#eye, Vec3.add(Vec3.mul(forward, 0.45), Vec3.add(Vec3.mul(Camera3d.right(aim), 0.15), Vec3.mul(Camera3d.up(aim), -0.12))));
        let release = if (Collider.isLineClear(res#collision, aim#eye, ahead)) ahead else aim#eye;
        match Grenades.toss(GrenadeDoc.rec(res#grenade), t, release, forward, s#grenades) {
            case Some(g) => { grenades = g, events = List.append(s#events, Event.GrenadeThrown :: Nil) | s }
            case None    => s
        }

    /// 点 x・z の上の天井の高さ（壁の中と迷路の外は一番高い天井）。
    def ceilingAt(res: Res.Res, x: Float64, z: Float64): Float64 =
        let h = Maze.heightAt(res#maze, Maze.cellAt(res#maze, x, z));
        if (h > 0.0) h else Maze.maxHeight(res#maze)

    /// 飛んでいる手榴弾を 1 コマ進め、強く跳ねた数だけ GrenadeBounced、信管が尽きた物を爆発させる。
    def flyGrenades(res: Res.Res, clock: Clock.Clock[PlayClock.Play], t: Float64, dt: Float64, s: SessionRec): SessionRec =
        let room = { collision = res#collision, ceilingAt = (x, z) -> ceilingAt(res, x, z) };
        let flight = Grenades.step(GrenadeDoc.rec(res#grenade), room, t, dt, s#grenades);
        let bounced = { grenades = flight#state, events = List.append(s#events, List.repeat(flight#bounces, Event.GrenadeBounced)) | s };
        flight#blasts |> List.foldLeft((acc, b) -> { hitStop = { at = Clock.nowOf(clock), last = false } | explode(res, t, b, acc) }, bounced)

    /// 時刻 t に手榴弾が点 b で爆発した: 半径の内の敵を倒す・吹っ飛ばす・弾けさせ（Horde.blast）、中心の光・輪・煙・破片・火の玉の塊・焦げ跡の粒を出し、
    /// 近ければ自分も傷を受け（壁越しは受けない）、描くカメラを揺らす。倒れた敵は物を落とす。
    def explode(res: Res.Res, t: Float64, b: Grenades.Blast, s: SessionRec): SessionRec =
        let gd = GrenadeDoc.rec(res#grenade);
        let damaged = Horde.blast(res, { t = t, point = b#point, doc = gd#blast, seed = b#id }, s#horde);
        let burst = burstOf(res, t, b#point, b#id, damaged#burst, s#gibs);
        let up = Vec3.v3(0.0, 1.0, 0.0);
        let lift = (h: Float64) -> Vec3.add(b#point, Vec3.v3(0.0, h, 0.0));
        let seed = b#id * 64 + 7000;
        let part = (p: Particles3d.BlastPart, h: Float64, k: Int32) -> Particles3d.emit(res#particles, Particles3d.Kind.Blast(p), Particles3d.Space.World, lift(h), up, t, seed + k);
        let fireball = List.flatten(part(Particles3d.BlastPart.Flash, 0.45, 0) :: part(Particles3d.BlastPart.Ring, 0.0, 1)
                                    :: part(Particles3d.BlastPart.Smoke, 0.4, 2) :: part(Particles3d.BlastPart.Debris, 0.25, 3)
                                    :: part(Particles3d.BlastPart.Fireball, 0.5, 4) :: part(Particles3d.BlastPart.Scorch, 0.0, 5) :: Nil);
        let chest = Vec3.v3(s#walker#x, s#walker#feet + 1.0, s#walker#z);
        let away = Vec3.length(Vec3.sub(chest, lift(0.3)));
        let selfHit = if (Collider.isLineClear(res#collision, lift(0.3), chest)) Grenades.selfDamageAt(gd#blast, away) else 0.0;
        let jd = JuiceDoc.rec(res#juice);
        let shaken = CameraShake.add(jd#shake, t, gd#shake + jd#shake#gib * Int32.toFloat64(List.length(damaged#burst)), s#shake);
        let blown = { horde = damaged#horde, gibs = burst#gibs, shake = shaken,
                      drops = List.append(s#drops, Pickups.dropsOf(res#pickups, t, fallenOf(res, damaged#fallen))),
                      particles = Particles3d.added(res#particles, List.append(fireball, burst#particles), s#particles),
                      marks = { killAt = if (List.isEmpty(damaged#fallen)) s#marks#killAt else t | s#marks },
                      events = List.flatten(s#events :: (Event.Exploded :: Nil) :: damaged#events :: Nil) | s };
        hurtPlayer(res, t, selfHit, blown)

    /// プレイヤーが時刻 t に傷 amount を受ける（緊急回避の i-frame の間は受けない）: 体力・被弾と倒れた事・描くカメラの揺れ。
    def hurtPlayer(res: Res.Res, t: Float64, amount: Float64, s: SessionRec): SessionRec =
        let dealt = if (Moves.isInvulnerable(MovesDoc.rec(res#moves)#dodge, t, s#moves)) 0.0 else amount;
        let health = Health.hurt(t, dealt, s#health);
        let hurts = dealt > 0.0 and not Health.isDown(s#health);
        let hurtEvents = if (hurts) Event.PlayerHurt(dealt) :: Nil else Nil;
        let downEvents = if (Health.isDown(health) and not Health.isDown(s#health)) Event.PlayerDown :: Nil else Nil;
        let jd = JuiceDoc.rec(res#juice);
        { health = health, shake = if (hurts) CameraShake.add(jd#shake, t, jd#shake#hurt, s#shake) else s#shake,
          events = List.flatten(s#events :: hurtEvents :: downEvents :: Nil) | s }

    /// 線の見通し（壁と立てた物の箱に遮られないか）。肉片と倒れた体が壁を抜けないかを見る。
    def lineOfSightIn(res: Res.Res): (Vec3.Vec3, Vec3.Vec3) -> Bool = (a, b) -> Collider.isLineClear(res#collision, a, b)

    /// このコマに倒した数が multiKill 以上か、群れの最後の 1 体（生きている敵も湧くのを待つ敵もいない）を倒したら、今の時刻に hit stop の合図を置く。
    def hitStopped(res: Res.Res, clock: Clock.Clock[PlayClock.Play], s: SessionRec): SessionRec =
        let downs = s#events |> List.count(e -> match e {
            case Event.EnemyDown(_, _) => true
            case _                     => false
        });
        let last = downs > 0 and Horde.aliveCount(s#horde) == 0 and Horde.queuedCount(s#horde) == 0;
        if (last or downs >= Int32.max(1, JuiceDoc.rec(res#juice)#hitStop#multiKill)) { hitStop = { at = Clock.nowOf(clock), last = last } | s }
        else s

    /// 持ち替えた事（替えた先が今と違えば 1 つ）。
    def switched(before: Arsenal.Arsenal, after: Arsenal.Arsenal): List[Event] =
        if (after#current != before#current) Event.Switched(after#current) :: Nil else Nil

    /// 足元の近くの置いた物と落とした物を拾い、拾った物の番号・知らせ・起きた事を足す。
    def pickUp(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let rules = { t = t, weapons = res#weapons, viewmodel = FpViewmodelDoc.rec(res#viewmodel), player = PlayerDoc.rec(res#player), grenade = GrenadeDoc.rec(res#grenade) };
        let radius = PickupsDoc.rec(res#pickups)#radius;
        let feet = { x = s#walker#x, z = s#walker#z };
        let got = Pickups.collect(rules, radius, feet, res#pickupPoints, s#taken, { arsenal = s#arsenal, health = s#health, grenades = s#grenades });
        let dropped = if (List.isEmpty(s#drops)) { carry = got#carry, drops = Nil, picked = Nil } else Pickups.collectDrops(rules, radius, feet, s#drops, got#carry);
        let picked = List.append(got#picked, dropped#picked);
        if (List.isEmpty(picked)) s
        else {
            let events = picked |> List.map(p -> Event.PickedUp(p#kind));
            { arsenal = dropped#carry#arsenal, health = dropped#carry#health, grenades = dropped#carry#grenades, taken = got#taken, drops = dropped#drops,
              notice = List.last(picked) |> Option.map(p -> { kind = p#kind, amount = p#amount, at = t }),
              events = List.flatten(s#events :: events :: switched(s#arsenal, dropped#carry#arsenal) :: Nil) | s }
        }

    /// 弾の尽きた武器で引き金を引いた: 空撃ちして、弾のある武器があれば持ち替える。
    def dryFire(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let after = Arsenal.dryFire(res#weapons, FpViewmodelDoc.rec(res#viewmodel), t, s#arsenal);
        { arsenal = after, events = List.flatten(s#events :: (Event.DryFire(s#arsenal#current) :: Nil) :: switched(s#arsenal, after) :: Nil) | s }

    /// 倒した数を数え、最後の部屋を空にした最初のコマにクリアの時刻を控える。
    def tally(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let downs = s#events |> List.count(e -> match e {
            case Event.EnemyDown(_, _) => true
            case _                  => false
        });
        let cleared = Option.isEmpty(s#clearedAt) and isFinalRoomClear(res, s#horde);
        { kills = s#kills + downs, clearedAt = if (cleared) Some(t) else s#clearedAt,
          events = if (cleared) List.append(s#events, Event.Cleared :: Nil) else s#events | s }

    /// 最後の部屋の wave を全部始め、その wave の敵が残っていないか（まだ入っていなければ偽）。
    def isFinalRoomClear(res: Res.Res, h: Horde.Horde): Bool = Horde.isFinished(res, res#maze#finalZone, h)

    /// 区画に入った: 前にいた区画と違えば、まだ入っていない区画の wave を始める（通路は wave を持つ時だけ）。部屋なら、やり直す所をその入口に控える
    /// （控えた部屋と同じなら書き換えない。控えるのは入る前の、終えた区画の wave の進み）。
    /// WhyNot: 壁ぎわで体の真ん中が壁のマスへ入った None を「区画を出た」と数えない — Some(A) → None → Some(A) で
    /// 部屋に入り直したことになり、戦いの最中の位置へやり直す所を書き換えてしまう。
    def enterZone(res: Res.Res, t: Float64, s: SessionRec): SessionRec =
        let b = s#walker;
        match Maze.zoneAt(res#maze, b#x, b#z) {
            case None => s
            case Some(id) if Some(id) == s#lastZone => s
            case Some(id) if not isRoom(res, id) =>
                { lastZone = Some(id), horde = if (Map.memberOf(id, res#wavePlans)) Horde.enter(id, t, s#horde) else s#horde | s }
            case Some(id) =>
                let fresh = not Horde.isTriggered(id, s#horde);
                let checkpoint = if (s#checkpoint#zone == Some(id)) s#checkpoint
                                 else { x = b#x, z = b#z, yawDeg = b#yaw * 180.0 / Num.pi(), zone = Some(id), arsenal = s#arsenal, grenades = s#grenades#carried, kills = s#kills, taken = s#taken,
                                        waves = Horde.finishedOf(res, s#horde) };
                { lastZone = Some(id), checkpoint = checkpoint, horde = Horde.enter(id, t, s#horde),
                  events = if (fresh) List.append(s#events, Event.RoomTriggered(id) :: Nil) else s#events | s }
        }

    def isRoom(res: Res.Res, id: Char): Bool =
        Map.get(id, res#maze#zones) |> Option.exists(z -> z#kind == MazeDoc.ZoneKind.Room)

    /// 敵が見るプレイヤーの体。
    def playerOf(res: Res.Res, s: SessionRec): PlayerBody.PlayerBody =
        let walk = WalkDoc.rec(res#walk);
        let b = s#walker;
        { x = b#x, feet = b#feet, z = b#z, eye = Walker.eyeOf(walk, b), yaw = b#yaw, radius = walk#radius, height = walk#height }

    /// 群れを 1 コマ進め、受けた傷を体力に足し、projectile が弾けた所に体液の飛沫を出す（散らし方の種は弾けた projectile の id）。
    def stepHorde(res: Res.Res, t: Float64, dt: Float64, s: SessionRec): SessionRec =
        let outcome = Horde.step(res, t, dt, playerOf(res, s), s#horde);
        let splashes = outcome#splashes |> List.flatMap(sp ->
            Particles3d.emit(res#particles, Particles3d.Kind.Ichor, Particles3d.Space.World, sp#point, sp#normal, t, sp#seed * 16));
        hurtPlayer(res, t, outcome#damage, { horde = outcome#horde, particles = Particles3d.added(res#particles, splashes, s#particles),
                                             events = List.append(s#events, outcome#events) | s })

    /// やり直す: やり直す所に立ち、体力を満たし、敵と落とした物を消して、wave の進みを部屋に入った時に終えていた区画だけへ戻す
    /// （次のコマに部屋へ入り直し、その部屋は最初の wave から湧く）。
    /// 武器と弾・倒した数・拾った物も部屋に入った時の写しへ戻す（湧き直す群れの分を二重に数えない・使った弾を取り戻せる）。
    def respawn(res: Res.Res, s: SessionRec): SessionRec =
        let c = s#checkpoint;
        let walker = Walker.settle(res#collision, WalkDoc.rec(res#walk), Walker.standing(c#x, 0.0, c#z, c#yawDeg));
        { walker = walker, health = Health.full(PlayerDoc.rec(res#player)), horde = Horde.restore(c#waves, s#horde),
          arsenal = c#arsenal, kills = c#kills, taken = c#taken, drops = Nil, notice = None,
          particles = Nil, lastZone = None, events = Event.Respawned :: Nil, pending = Nil, tracers = Nil, gibs = Gibs.empty(), shake = CameraShake.none(),
          marks = noMarks(), moves = Moves.initial(MovesDoc.rec(res#moves)),
          grenades = { carried = c#grenades | Grenades.initial(GrenadeDoc.rec(res#grenade)) } | s }

    /// 見回しの遅れ: このコマに回した角を足し、上限で切り、swayFollow 秒ほどで 0 へ戻す。
    def swayAfter(vm: FpViewmodelDoc.Rec, d: Walker.Drive, dt: Float64, sway: { x = Float64, y = Float64 }): { x = Float64, y = Float64 } =
        let keep = Float64.exp(0.0 - dt / Float64.max(0.001, vm#swayFollow));
        let clampMax = v -> Num.clamp(0.0 - vm#swayMax, vm#swayMax, v);
        { x = clampMax(sway#x + d#turnDeg + d#turnRate * dt) * keep, y = clampMax(sway#y + d#lookDeg) * keep }

    /// 時刻 t に構えている武器で 1 回撃つ: 照準から粒を飛ばし、敵に当たれば傷を付け、当たった所に火花と煙か体液・銃口にマズルフラッシュを出す。
    /// 連射銃は曳光弾を飛ばし、描くカメラを揺らし、照準の印の時刻を置く。倒れた敵のうち弾けた敵は肉片と体液と衝撃の輪になる。
    def shoot(res: Res.Res, t: Float64, dt: Float64, s: SessionRec): SessionRec =
        let a = s#arsenal;
        let stats = Arsenal.statsOf(res#weapons, a);
        let aim = aimOf(res, t, s);
        let impacts = Hitscan.fire(List.append(Horde.targetsOf(s#horde), res#hitTargets), aim, stats, a#shots);
        let pdoc = Particles3dDoc.rec(res#particles);
        // WhyNot: 粒の真ん中を当たった点・銃口の点に置かない — 面を向いたビルボードの半分が壁や銃身に埋まる。粒の半分の大きさだけ手前へ出す。
        let sparks = impacts |> List.zipWithIndex |> List.flatMap(e -> {
            let (i, hit) = e;
            let lifted = Vec3.add(hit#point, Vec3.mul(hit#normal, pdoc#spark#size * 0.5));
            let seed = a#shots * 64 + i;
            if (isEnemy(hit#struck)) Particles3d.emit(res#particles, Particles3d.Kind.Ichor, Particles3d.Space.World, lifted, hit#normal, t, seed)
            else List.append(Particles3d.emit(res#particles, Particles3d.Kind.Spark, Particles3d.Space.World, lifted, hit#normal, t, seed),
                             Particles3d.emit(res#particles, Particles3d.Kind.Smoke, Particles3d.Space.World, lifted, hit#normal, t, seed + 32))
        });
        let ahead = Particles3d.muzzleOf(res#particles, a#current)#size * 0.5;
        let flash = Particles3d.emit(res#particles, Particles3d.Kind.Muzzle(a#current), Particles3d.Space.Muzzle, Vec3.v3(0.0, 0.0, ahead), Vec3.v3(0.0, 0.0, 1.0), t, a#shots);
        let damaged = Horde.applyDamage(res, { t = t, damage = stats#damage, weapon = a#current, origin = aim#eye, index = a#shots }, impacts, s#horde);
        let burst = burstOf(res, t, aim#eye, a#shots, damaged#burst, s#gibs);
        let sd = SoundsDoc.rec(res#sounds);
        let ricochet = if (List.exists(hit -> not isEnemy(hit#struck), impacts) and Hash01.at(a#shots, 71) < sd#ricochetChance) Event.Ricochet :: Nil else Nil;
        let jd = JuiceDoc.rec(res#juice);
        let shaken = s#shake |> CameraShake.add(jd#shake, t, JuiceDoc.ofWeapon(a#current, jd#shake#fire)
            + jd#shake#kill * Int32.toFloat64(List.length(damaged#fallen)) + jd#shake#gib * Int32.toFloat64(List.length(damaged#burst)));
        let tracers = if (Tracers.isDue(pdoc#tracer, a#current, a#shots)) Tracers.add(pdoc#tracer, tracerOf(aim, stats#range, impacts, t), s#tracers) else s#tracers;
        { arsenal = Arsenal.fire(res#weapons, t, dt, a), horde = damaged#horde,
          drops = List.append(s#drops, Pickups.dropsOf(res#pickups, t, fallenOf(res, damaged#fallen))),
          particles = Particles3d.added(res#particles, List.flatten(flash :: sparks :: burst#particles :: Nil), s#particles),
          gibs = burst#gibs, shake = shaken, tracers = tracers, marks = marksAfter(t, impacts, damaged#fallen, s#marks),
          pending = List.append(s#pending, afterShot(sd, t, a#current)),
          events = List.flatten(s#events :: (Event.Fired(a#current) :: Nil) :: ricochet :: damaged#events :: Nil) | s }

    /// 照準の印: 敵に当てたら当てた時刻・倒したら倒した時刻を置く。
    def marksAfter(t: Float64, impacts: List[Hitscan.Impact], fallen: List[Horde.Enemy], m: Marks): Marks =
        { hitAt = if (List.exists(hit -> isEnemy(hit#struck), impacts)) t else m#hitAt, killAt = if (List.isEmpty(fallen)) m#killAt else t }

    /// 弾けた敵ごとに、肉片（体の真ん中から撃たれた向きへ）・体液・衝撃の輪を出す（種は敵の番号と撃った回数）。
    def burstOf(res: Res.Res, t: Float64, eye: Vec3.Vec3, shot: Int32, burst: List[Horde.Enemy], g: Gibs.State): { gibs = Gibs.State, particles = List[Particles3d.Particle] } =
        let gd = JuiceDoc.rec(res#juice)#gib;
        burst |> List.foldLeft((acc, e) -> {
            let away = Knockback.awayFrom(eye#x, eye#z, e#x, e#z);
            let center = Vec3.v3(e#x, 1.1, e#z);
            let seed = e#id * 13 + shot;
            let dir = Vec3.v3(away#dx, 0.35, away#dz);
            let gore = Particles3d.emit(res#particles, Particles3d.Kind.Gore, Particles3d.Space.World, center, dir, t, seed * 16);
            let ring = Particles3d.emit(res#particles, Particles3d.Kind.Ring, Particles3d.Space.World, center, Vec3.v3(0.0, 1.0, 0.0), t, seed * 16 + 1);
            { gibs = Gibs.burst(gd, res#gibArt, t, seed, center, away#dx, away#dz, acc#gibs), particles = List.flatten(gore :: ring :: acc#particles :: Nil) }
        }, { gibs = g, particles = Nil })

    /// 曳光弾 1 本: 銃口のあたり（目から前へ 0.8 m・右へ 0.12 m・下へ 0.13 m）から、最初に当たった所（当たらなければ照準の先の届く距離）まで。
    // WhyNot: 銃口の点を腕と銃の glb から取らない — 銃口は描く側の物で World は知らない。曳光弾は 1 コマに 2 m 余り進むので数 cm の違いは見えない。
    pub def tracerOf(aim: Camera3d.Camera3d, range: Float64, impacts: List[Hitscan.Impact], t: Float64): Tracers.Tracer =
        let forward = Camera3d.forward(aim);
        let start = Vec3.add(aim#eye, Vec3.add(Vec3.mul(forward, 0.8), Vec3.add(Vec3.mul(Camera3d.right(aim), 0.12), Vec3.mul(Camera3d.up(aim), -0.13))));
        let target = List.head(impacts) |> Option.map(hit -> hit#point) |> Option.getWithDefault(Vec3.add(aim#eye, Vec3.mul(forward, range)));
        { origin = start, target = target, born = t }

    /// 撃った後に遅れて起きる事: 薬莢が床に落ちる（武器ごとの秒の後）・散弾銃は先台を引く。
    def afterShot(sd: SoundsDoc.Rec, t: Float64, w: WeaponsDoc.Weapon): List[{ at = Float64, event = Event }] = match w {
        case WeaponsDoc.Weapon.Pistol  => { at = t + sd#shellDelay#pistol, event = Event.ShellLanded(w) } :: Nil
        case WeaponsDoc.Weapon.Rifle   => { at = t + sd#shellDelay#rifle, event = Event.ShellLanded(w) } :: Nil
        case WeaponsDoc.Weapon.Shotgun =>
            { at = t + sd#pumpDelay, event = Event.Pumped } :: { at = t + sd#shellDelay#shotgun, event = Event.ShellLanded(w) } :: Nil
    }

    def isEnemy(struck: Hitscan.Struck): Bool = match struck {
        case Hitscan.Struck.Enemy(_, _) => true
        case _                          => false
    }

    /// 時刻 t の描くカメラ: 照準のカメラに揺れの角を足し、撃った時の跳ねで目を後ろへ下げる。
    def viewOf(res: Res.Res, t: Float64, s: SessionRec): Camera3d.Camera3d =
        let aim = aimOf(res, t, s);
        let jd = JuiceDoc.rec(res#juice);
        let (yaw, pitch) = CameraShake.offsetAt(jd#shake, t, s#shake);
        let back = s#arsenal#last |> Option.map(shot -> CameraShake.kickAt(jd#kick, shot#weapon, t, shot#at)) |> Option.getWithDefault(0.0);
        let dd = MovesDoc.rec(res#moves)#dodge;
        let widen = dd#fovKick * Moves.dodgeSwell(dd, t, s#moves) * Num.pi() / 180.0;
        { eye = CameraShake.pulledBack(aim#eye, Camera3d.forward(aim), back), yaw = aim#yaw + yaw, pitch = aim#pitch + pitch, fovY = aim#fovY + widen | aim }

    /// 時刻 t の照準のカメラ: 目の位置・向きに、反動で跳ね上がった角を足し、緊急回避の間は目を沈める（撃つレイと、描くカメラの元）。
    def aimOf(res: Res.Res, t: Float64, s: SessionRec): Camera3d.Camera3d =
        let walk = WalkDoc.rec(res#walk);
        let punch = Arsenal.punchAt(res#weapons, FpViewmodelDoc.rec(res#viewmodel), t, s#arsenal);
        let dd = MovesDoc.rec(res#moves)#dodge;
        let dip = Vec3.v3(0.0, 0.0 - dd#dip * Moves.dodgeSwell(dd, t, s#moves), 0.0);
        { eye = Vec3.add(Walker.eyeOf(walk, s#walker), dip), yaw = s#walker#yaw, pitch = s#walker#pitch - punch * Num.pi() / 180.0,
          fovY = walk#fovY * Num.pi() / 180.0, near = 0.05, far = LookDoc.rec(res#look)#fogFar }

    /// 撃った後の見た目の物: 3D の粒・肉片・曳光弾・照準の印（描き出しの場面が組む）。
    pub type alias Effects = { particles = List[Particles3d.Particle], gibs = Gibs.State, tracers = List[Tracers.Tracer], marks = Marks }

    /// 撃った後の見た目の物を読み替える（描き出しの場面が、少し前に弾けた・撃った見た目を置く）。
    pub def mapEffects(f: Effects -> Effects, w: World): World = mapSession(s -> {
        let e = f({ particles = s#particles, gibs = s#gibs, tracers = s#tracers, marks = s#marks });
        { particles = e#particles, gibs = e#gibs, tracers = e#tracers, marks = e#marks | s }
    }, w)

    /// 技の状態を読み替える（描き出しの場面が少し前に跳んだ所を置く）。
    pub def mapMoves(f: Moves.Moves -> Moves.Moves, w: World): World = mapSession(s -> { moves = f(s#moves) | s }, w)

    /// 手榴弾の状態を読み替える（テストが持っている数を決める）。
    pub def mapGrenades(f: Grenades.State -> Grenades.State, w: World): World = mapSession(s -> { grenades = f(s#grenades) | s }, w)

    /// 時刻 at に蹴った World（描き出しの場面。蹴った時刻を前へずらす）。
    pub def kickAt(res: Res.Res, at: Float64, w: World): World = mapSession(s -> kickWith(res, at, { moves = { kickAt = at | s#moves } | s }), w)

    /// 時刻 at に点 point で手榴弾が爆発した World（描き出しの場面・テスト）。
    pub def detonate(res: Res.Res, point: Vec3.Vec3, at: Float64, w: World): World =
        mapSession(s -> explode(res, at, { id = s#grenades#nextId, point = point }, s), w)

    /// 武器の状態を読み替える（描き出しの場面が構える武器を替える）。
    pub def mapArsenal(f: Arsenal.Arsenal -> Arsenal.Arsenal, w: World): World = mapSession(s -> { arsenal = f(s#arsenal) | s }, w)

    /// 敵の群れを差し替える（描き出しの場面・測り・テストが敵を並べる）。
    pub def withHorde(h: Horde.Horde, w: World): World = mapSession(s -> { horde = h | s }, w)

    /// 群れを読み替える（描き出しの場面が今の群れの何体かを倒しておく）。
    pub def mapHorde(f: Horde.Horde -> Horde.Horde, w: World): World = mapSession(s -> { horde = f(s#horde) | s }, w)

    /// 部屋に入った扱いにする（最後にいた区画を今の区画にそろえ、次のコマに部屋へ入ったと数えない）。描き出しの場面と測りが使う。
    pub def settleZone(res: Res.Res, w: World): World = mapSession(s -> { lastZone = zoneOf(res, w) | s }, w)

    // ── マウスの視点・診断 ──

    /// マウスを窓にキャプチャして視点を回しているか（App.withMouseCapture がこれを見て当てる）。
    pub def isLooking(w: World): Bool = sessionOf(w) |> Option.exists(s -> rec(s)#look == Look.Captured)

    /// キャプチャを始める・放す。終了の確認の窓・ポーズの間はキャプチャしない（窓の中を押せない）。
    pub def setLooking(on: Bool, w: World): World =
        mapSession(s -> { look = if (on and w#quit == Quit.Playing and s#pause == Pause.Running) Look.Captured else Look.Released | s }, w)

    /// F3 の診断の表示を切り替える。
    pub def toggleDiagnostics(w: World): World =
        mapSession(s -> { diagnosticsView = if (s#diagnosticsView == DiagnosticsView.Shown) DiagnosticsView.Hidden else DiagnosticsView.Shown | s }, w)

    // ── 終了の確認 ──

    /// 閉じるボタン・タイトルの Esc: 確認の窓を出す（キャプチャは放す）。
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
