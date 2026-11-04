// E2e — e2e/<名前>.flow の語彙（App.withFlow の表と指紋）と、画面なしで流す入口。
// flow の書き方は engine の engine_world/src/Flow.flix 冒頭。名前の一覧は流すたびに e2e/vocab.json へ書き出す。
//   make flow FLOW=e2e/walk.flow   画面なしで最後まで流す
mod E2e {
    use fge::{App, Flow, HeadlessLoad, InputMap, Resources}
    use fge::GameEngine.Key

    /// make flow（bin/fge flow run|check）が流す入口。
    pub def play(): Unit \ IO = App.Headless.exitWith(playJob(App.Headless.requestFromProcess()))

    def playJob(req: App.Headless.Request): Int32 \ IO =
        run { Flow.Cli.mainOf(Game.app(HeadlessLoad.handle(Controls.loadDocs)), App.Headless.envOf(req)) } with Fs.FileRead.runWithIO with Fs.FileWrite.runWithIO

    /// 語彙 e2e/vocab.json だけを書く入口（bin/headless-run が jar を作った時に流す・make flow-vocab）。
    pub def vocab(): Unit \ IO = App.Headless.exitWith(vocabJob(App.Headless.requestFromProcess()))

    def vocabJob(req: App.Headless.Request): Int32 \ IO =
        run { Flow.Cli.vocabMainOf(Game.app(HeadlessLoad.handle(Controls.loadDocs)), App.Headless.envOf(req)) } with Fs.FileRead.runWithIO with Fs.FileWrite.runWithIO

    /// 常駐（App.Headless.serveJobs）が /run で流す E2e の入口の束。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("E2e", "play", req -> playJob(req)) ::
        App.Headless.job("E2e", "vocab", req -> vocabJob(req)) :: Nil

    /// 役の名前 → キー（表の先頭のキーを押す。player.keys.json の既定と同じ）。
    def roles(): InputMap.Table[String] =
        (Key.W, "forward") :: (Key.S, "back") :: (Key.A, "left") :: (Key.D, "right") ::
        (Key.Left, "turnLeft") :: (Key.Right, "turnRight") :: (Key.LeftShift, "sprint") ::
        (Key.Enter, "confirm") :: (Key.Escape, "cancel") :: Nil

    /// flow の表: 役と問い。
    pub def table(): Flow.Table[Resources.With[Res.Res, World.World]] =
        { roles = _ -> roles(),
          probes =
              { name = "x", doc = "足元の x（m）", read = Flow.Probe.Num(Resources.read((_, w) -> playing(w, s -> World.walkerOf(s)#x))) } ::
              { name = "z", doc = "足元の z（m）", read = Flow.Probe.Num(Resources.read((_, w) -> playing(w, s -> World.walkerOf(s)#z))) } ::
              { name = "zone", doc = "今いる区画の文字（壁の中は -）", read = Flow.Probe.Text(Resources.read((res, w) -> zoneName(res, w))) } ::
              { name = "quit", doc = "終了の確認（Playing・Asking・Confirmed）", read = Flow.Probe.Text(Resources.read((_, w) -> "${w#quit}")) } ::
              { name = "screen", doc = "画面（Title・Play・Paused・Clear）", read = Flow.Probe.Text(Resources.read((_, w) -> screenName(w))) } ::
              { name = "weapon", doc = "構えている武器（Pistol・Shotgun・Rifle）", read = Flow.Probe.Text(Resources.read((_, w) -> World.sessionOf(w) |> Option.map(s -> "${World.arsenalOf(s)#current}") |> Option.getWithDefault("-"))) } ::
              { name = "shots", doc = "撃った回数の合計", read = Flow.Probe.Num(Resources.read((_, w) -> playing(w, s -> Int32.toFloat64(World.arsenalOf(s)#shots)))) } ::
              { name = "health", doc = "プレイヤーの体力", read = Flow.Probe.Num(Resources.read((_, w) -> playing(w, s -> World.healthOf(s)#points))) } ::
              { name = "enemies", doc = "倒れていない敵の数", read = Flow.Probe.Num(Resources.read((_, w) -> playing(w, s -> Int32.toFloat64(Horde.aliveCount(World.hordeOf(s)))))) } :: Nil
          | Flow.emptyTable() }

    /// 画面の名前（ポーズは Paused）。
    def screenName(w: World.World): String = match w#screen {
        case World.Screen.Title    => "Title"
        case World.Screen.Play(_)  => if (World.isPaused(w)) "Paused" else "Play"
        case World.Screen.Clear(_) => "Clear"
    }

    /// 遊んでいる場面の数（ほかの画面では 0）。
    def playing(w: World.World, f: World.Session -> Float64): Float64 = World.sessionOf(w) |> Option.map(f) |> Option.getWithDefault(0.0)

    def zoneName(res: Res.Res, w: World.World): String =
        World.zoneOf(res, w) |> Option.map(c -> "${c}") |> Option.getWithDefault("-")

    /// 指紋の元（記録の再生が比べる）: 進行に効く欄だけ。
    pub def fingerprint(res: Res.Res, w: World.World): String =
        let at = World.sessionOf(w) |> Option.map(s -> { let b = World.walkerOf(s); "${b#x},${b#z}" }) |> Option.getWithDefault("-");
        let shots = World.sessionOf(w) |> Option.map(s -> World.arsenalOf(s)#shots) |> Option.getWithDefault(0);
        "screen=${screenName(w)}|at=${at}|zone=${zoneName(res, w)}|quit=${w#quit}|shots=${shots}"
}
