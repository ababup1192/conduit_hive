// VideoRender — 遊んでいる様子の紹介の動画（mp4・音つき）を、画面なしで書く。
// 実行: make video → debug/video/play.mp4（GPU で塗れた時は ffmpeg へ生の画素を直に流して mp4 を書く。音は audio.f64 に書いて同じ ffmpeg で束ねる。
//       SoftRaster に落ちた時はコマを debug/video/play/f0000.png … に書き、make が mp4 へ束ねる）
//
// 手順は e2e/video.flow（e2e と同じ flow の実行器）で、1 フレームずつ World を進める。歩いて撃つのは `start tour` の自動の操縦（Pilot）。
// 撮るのは mark in_<名前> から out_<名前> までの区間だけで、並んだ順につなぐ。手順は 60 fps で流し、VIDEO_FPS ごとに間引いて描く。
// 音は撮るフレームごとに鳴った音の名前と鳴り続ける音（App.withAudio・withSustained と同じ Sounds）を、project.json の sounds の wav で、遊ぶ時と同じミキサー（Res の mixer）を通して混ぜる（AudioMixdown）。
// wav を差し替えれば同じ口で撮り直せる。
//
// 環境変数: VIDEO_FPS（既定 60。60 を割り切る数）・VIDEO_FLOW（手順。既定 e2e/video.flow）・VIDEO_OUT（debug/video/<名前>。既定 play）・
//           VIDEO_SCALE（design 480×270 の何倍で塗るか。既定 4 = 1920×1080）・VIDEO_X264（GPU の道で mp4 を書く ffmpeg の旗）・
//           VIDEO_HORDE（立てると最後の部屋の真ん中で群れに囲まれて撃ち続ける動画。数は同時に生きている敵の上限。手順は start を書かない物）・
//           FGE_GPU / FGE_VIDEO_PAINT / FFMPEG（VideoOut.settingsOf）
mod VideoRender {
    use fge::{
        App, AudioMixdown, DocJson, Flow, FontAtlas, HeadlessFont, HeadlessLoad, HeadlessRender, JsonCodec,
        PxSpriteAtlas, Render, Resources, VideoOut
    }

    import java.io.{BufferedOutputStream, DataOutputStream, File, FileOutputStream}
    import java.nio.file.{Files, Paths}

    /// App の w（描く元と World の組）。
    type alias AppState = Resources.With[Res.Res, World.World]

    /// 撮る手順と、コマを書く所（debug/video/<名前>）と、design の何倍で塗るか。
    type alias Take = { flow = String, outDir = String, scale = Int32 }

    def takeOf(env: Map[String, String]): Take =
        let pick = (key, fallback) -> Map.get(key, env) |> Option.map(String.trim) |> Option.filter(v -> not String.isEmpty(v)) |> Option.getWithDefault(fallback);
        { flow = pick("VIDEO_FLOW", "e2e/video.flow"), outDir = "debug/video/${pick("VIDEO_OUT", "play")}",
          scale = Int32.fromString(pick("VIDEO_SCALE", "4")) |> Option.filter(n -> n > 0 and n <= 8) |> Option.getWithDefault(4) }

    /// 手順を流す速さ（e2e/video.flow の fps と同じ）。
    def playFps(): Int32 = 60

    pub def frames(): Unit \ IO = App.Headless.exitWith(framesJob(App.Headless.requestFromProcess()))

    /// 常駐（App.Headless.serveJobs）が /run で流す入口の束。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("VideoRender", "frames", req -> framesJob(req)) :: Nil

    def framesJob(req: App.Headless.Request): Int32 \ IO =
        let env = App.Headless.envOf(req);
        // WhyNot: 字のアトラス（AWT）を先に作らない — AWT の後では GL の文脈が作れない（VideoOut.settingsOf の doc）。
        let settings = VideoOut.settingsOf(env);
        let fps = Map.get("VIDEO_FPS", env) |> Option.flatMap(Int32.fromString)
            |> Option.filter(n -> n > 0 and Int32.modulo(playFps(), n) == 0) |> Option.getWithDefault(60);
        let docs = run { HeadlessLoad.handle(Controls.loadDocs) } with Fs.FileRead.runWithIO;
        let app = Game.app(docs);
        let fresh = match hordeOf(env) {
            case Some(maxAlive) => hordeStart(maxAlive, docs)
            case None           => Ok(run { App.freshWorld(app, SceneRender.design()) } with Fs.FileRead.runWithIO)
        };
        let take = takeOf(env);
        discard (new File(take#outDir)).mkdirs();
        match fresh |> Result.flatMap(w -> playFlow(app, w, take#flow, Files.readString(Paths.get(take#flow)))) {
            case Err(why) =>
                println("[video] ${why}");
                1
            case Ok(outcome) => writeOutcome(settings, env, fps, take, outcome)
        }

    // ── 群れの動画（VIDEO_HORDE） ──

    /// VIDEO_HORDE = 同時に生きている敵の上限（立っていなければ普段の動画）。
    def hordeOf(env: Map[String, String]): Option[Int32] =
        Map.get("VIDEO_HORDE", env) |> Option.flatMap(v -> Int32.fromString(String.trim(v))) |> Option.filter(n -> n > 0)

    /// 群れの動画の始まり: 群れの重さの測り（HordeBench.endlessScene）と同じ描く元と World（最後の部屋の真ん中で自動の操縦が撃ち続け、
    /// wave が上限まで湧き続け、敵の威力は 0）に、振り向きだけ人の手に寄せた物。
    // WhyNot: App.freshWorld を通さない — Doc を全部ファイルから読み直すので、群れの描く元が普段の物へ戻る。
    //   flow も start を書かない（start は freshWorld で組み直す）。
    def hordeStart(maxAlive: Int32, docs: Res.Docs): Result[String, AppState] =
        HordeBench.endlessScene(maxAlive, Res.build(standOff(HordeBench.harmlessDocs(docs))))
            |> Result.map(rs -> { let (res, w) = rs; Resources.of(humanAim(res), w) })

    /// 敵が押し出されるプレイヤーの体の円を半径 1.8 m に広げ、melee はその縁で足を止めて振り、飛びかからない。
    // WhyNot: 遊びの距離（体 0.35 m・1.2 m で止まり 4.5 m から飛びかかる）のままにしない — 後ろの数百体に押されて前の列が目の中まで入り、
    //   画面が体の内側だけになる（群れも撃つ所も見えない）。止まる距離だけ広げても、押し合いで前の列は押し込まれる。
    def standOff(docs: Res.Docs): Res.Docs =
        let r = EnemiesDoc.rec(docs#enemies);
        let walk = WalkDoc.rec(docs#walk);
        { enemies = EnemiesDoc.Doc.Doc({ melee = { attackRange = 2.6, stopDistance = 2.4, lungeRange = 0.0 | r#melee } | r }),
          walk = WalkDoc.Doc.Doc({ radius = 1.8 | walk }) | docs }

    /// 振り向きの速さと狙いへ寄る勢いを、測りの組（900 度/秒・0.04 秒）から人の手の速さへ戻す。
    // WhyNot: 測りの組の速さのままにしない — 的から的へ一瞬で向きが跳ね、絵が切り替わって見える。
    def humanAim(res: Res.Res): Res.Res =
        let t = TourDoc.rec(res#tour);
        res |> Res.withTour(TourDoc.Doc.Doc({ turnRate = 320.0, lookEase = 0.12, turnSmooth = 0.08, fireCone = 4.0 | t }))

    /// 撮ったコマの間の群れ: 生きている敵の最大・平均・最小と、倒した数（撮り始めから撮り終わりまで）。
    def hordeSummary(worlds: List[AppState]): String =
        let alive = worlds |> List.map(Resources.read((_, w) -> Horde.aliveCount(HordeBench.hordeIn(w))));
        let kills = worlds |> List.map(Resources.read((_, w) -> HordeBench.killsIn(w)));
        let n = Int32.max(1, List.length(alive));
        let killed = Option.getWithDefault(0, List.last(kills)) - Option.getWithDefault(0, List.head(kills));
        "[video] 群れ: 生きている敵 最大 ${List.maximum(alive) |> Option.getWithDefault(0)}・平均 ${List.sum(alive) / n}・" +
        "最小 ${List.minimum(alive) |> Option.getWithDefault(0)}・撮った間に倒した数 ${killed}"

    /// 手順（flow の文）を読んで、まっさらな World から流す。読めない・途中で止まった時は、その訳の 1 行。
    def playFlow(app: App.App[AppState, {}], fresh: AppState, flowPath: String, text: String): Result[String, Flow.Outcome[AppState]] \ IO =
        Flow.Parse.parseText(Flow.vocabOf(app, fresh), flowPath, text)
            |> Result.mapErr(problems -> "手順を読めない\n" + Flow.Parse.problemsText(problems))
            |> Result.flatMap(script -> {
                let played = run {
                    Flow.play(app, { design = SceneRender.design(), limit = 100000 }, script, { world = fresh, state = App.freshStepState() })
                } with Fs.FileRead.runWithIO;
                played |> Result.mapErr(failure -> "手順が ${failure#at#number} 行目で止まった: ${failure#why}（${failure#at#text}）/ ${failure#seen}")
            })

    def writeOutcome(settings: VideoOut.Settings, env: Map[String, String], fps: Int32, take: Take, outcome: Flow.Outcome[AppState]): Int32 \ IO =
        match segmentsOf(outcome#marks) {
            case Err(why) =>
                println("[video] ${take#flow} の mark: ${why}");
                1
            case Ok(segments) =>
                let shown = segments |> List.flatMap(seg -> outcome#frames |> List.drop(fst(seg)) |> List.take(snd(seg) - fst(seg)));
                let stride = playFps() / fps;
                let painted = shown |> List.zipWithIndex |> List.filter(p -> Int32.modulo(fst(p), stride) == 0)
                    |> List.map(p -> snd(p)#step#after);
                println("[video] ${List.length(outcome#frames)} フレームを流し、${List.length(segments)} 区間・${List.length(painted)} コマを撮る（${Int32.toString(List.length(painted) / fps)} 秒・${Int32.toString(fps)} fps）");
                if (Option.nonEmpty(hordeOf(env))) println(hordeSummary(painted)) else ();
                let audio = "${take#outDir}/audio.f64";
                writeAudio(audio, shown |> List.map(p -> p#step));
                writeVideo(settings, encoderOf(env, fps, take, audio), fps, take, painted);
                0
        }

    /// mark の in_<名前> / out_<名前> の組を、始まりのフレームの順に (始まり, 終わり) で並べる。
    /// 対の無い mark・終わりが始まりより前の組は Err（黙って区間を落とすと動画が短くなったことに気付けない）。
    def segmentsOf(marks: Map[String, Int32]): Result[String, List[(Int32, Int32)]] =
        let names = Map.keysOf(marks) |> Set.toList;
        let ins = names |> List.filterMap(n -> String.stripPrefix(substr = "in_", n));
        let outs = names |> List.filterMap(n -> String.stripPrefix(substr = "out_", n));
        let inSet = List.toSet(ins);
        let outSet = List.toSet(outs);
        let lonely = List.append(ins |> List.filter(n -> not Set.memberOf(n, outSet)) |> List.map(n -> "in_${n}"),
                                 outs |> List.filter(n -> not Set.memberOf(n, inSet)) |> List.map(n -> "out_${n}"));
        let pairs = ins |> List.map(n -> (Map.getWithDefault("in_${n}", 0, marks), Map.getWithDefault("out_${n}", 0, marks)));
        let backwards = pairs |> List.filter(p -> snd(p) <= fst(p));
        if (not List.isEmpty(lonely)) Err("対の無い印 ${List.join(", ", lonely)}")
        else if (List.isEmpty(pairs)) Err("in_<名前> と out_<名前> の組が 1 つも無い")
        else if (not List.isEmpty(backwards)) Err("終わりが始まりより前の組がある")
        else Ok(List.sortBy(fst, pairs))

    /// GPU の道で debug/video/<名前>.mp4 を直に書く ffmpeg の旗（VIDEO_X264 は Makefile と同じ字を受ける）。音（audio）を 2 本目の入力に足す。
    def encoderOf(env: Map[String, String], fps: Int32, take: Take, audio: String): VideoOut.Encoder =
        let x264 = Map.getWithDefault("VIDEO_X264", "-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p", env);
        let flags = String.splitOn({ substr = " " }, x264) |> List.filter(part -> not String.isEmpty(part));
        { rate = Int32.toString(fps), inputs = audioInput(audio),
          outputs = List.append(flags, "-c:a" :: "aac" :: "-b:a" :: "192k" :: "-shortest" :: "-movflags" :: "+faststart" :: "${take#outDir}.mp4" :: Nil) }

    // ── 音 ──

    /// 音の速さ（assets/sfx の wav と同じ 44.1 kHz）。
    def sampleRate(): Int32 = 44100

    /// ffmpeg に渡す音の入力（左右交互の 64bit 浮動小数・ビッグエンディアン）。
    def audioInput(path: String): List[String] =
        "-f" :: "f64be" :: "-ar" :: Int32.toString(sampleRate()) :: "-ac" :: "2" :: "-i" :: path :: Nil

    /// 撮るフレーム（手順の 60 fps のまま）に鳴った音と鳴り続ける音を混ぜて書く。
    /// WhyNot: 時刻表を別に作って ffmpeg の adelay で重ねない — 実機と同じ名前の列（App.withAudio の trace）とミキサーの規則で混ぜる方が、絵と音がずれない。
    def writeAudio(path: String, steps: List[App.TraceStep[AppState]]): Unit \ IO =
        let entries = soundFiles();
        let sounds = entries |> List.map(e -> { let (name, file, _) = e; (name, AudioMixdown.loadWavStereo(sampleRate(), file)) }) |> List.toMap;
        let loops = entries |> List.filterMap(e -> {
            let (name, file, looping) = e;
            if (looping) AudioMixdown.loadLoopStart(sampleRate(), file) |> Option.map(at -> (name, at)) else None
        }) |> List.toMap;
        let frames = steps |> List.map(st -> { plays = st#sounds, sustained = st#sustained, mixer = Resources.read((r, _) -> r#mixer, st#after) });
        let mixed = AudioMixdown.mixdownStereo(sampleRate(), Int32.toFloat64(playFps()), sounds, loops, frames);
        let out = new DataOutputStream(new BufferedOutputStream(new FileOutputStream(path)));
        let n = Int32.min(Vector.length(mixed#left), Vector.length(mixed#right));
        Vector.forEach(i -> { out.writeDouble(Vector.get(i, mixed#left)); out.writeDouble(Vector.get(i, mixed#right)) }, Vector.range(0, n));
        out.close();
        println("[video] 音: ${path}（${Int32.toString(n / sampleRate())} 秒・いちばん大きな振れ幅 ${Float64.toString(AudioMixdown.peakOf(mixed#left))}）")

    /// project.json の sounds（名前・ファイル・鳴り続けるか）。
    def soundFiles(): List[(String, String, Bool)] \ IO =
        let rows = run { DocJson.readJson("project.json") } with Fs.FileRead.runWithIO;
        rows |> Result.toOption |> Option.flatMap(JsonCodec.expectObject)
             |> Option.flatMap(root -> Map.get("sounds", root))
             |> Option.flatMap(JsonCodec.decodeList(j -> JsonCodec.expectObject(j) |> Option.map(obj ->
                    (JsonCodec.stringOr("name", "", obj), JsonCodec.stringOr("path", "", obj), JsonCodec.boolOr("looping", false, obj)))))
             |> Option.getWithDefault(Nil)

    // ── 絵 ──

    def writeVideo(settings: VideoOut.Settings, encoder: VideoOut.Encoder, fps: Int32, take: Take, worlds: List[AppState]): Unit \ IO =
        let first = match List.head(worlds) {
            case Some(w) => w
            case None    => bug!("[video] 撮るコマが無い")
        };
        let res = Resources.read((r, _) -> r, first);
        let atlas = HeadlessFont.buildUiAtlas(SceneRender.ttf(), SceneRender.ttf());
        let soft = { design = SceneRender.design(), scale = take#scale, background = LookDoc.rec(res#look)#fogColor,
                     fontTtf = SceneRender.ttf(), fontAtlas = atlas, outDir = take#outDir,
                     frameW = Float64.round(SceneRender.design()#x) |> Float64.tryToInt32 |> Option.getWithDefault(480) |> (w -> w * take#scale),
                     frameH = Float64.round(SceneRender.design()#y) |> Float64.tryToInt32 |> Option.getWithDefault(270) |> (h -> h * take#scale)
                     | HeadlessRender.defaults() };
        let painter = VideoOut.writeFramesWithPasses(settings,
            { outDir = take#outDir, fps = fps, soft = soft, softFonts = _ -> atlas, extraFonts = Map.empty(),
              images = PxSpriteAtlas.asImages({ texture = Particles3d.textureName(), baked = res#particleTexture } :: Nil), scene = sceneOf,
              wanted = _ -> true, bakeSurfaces = false, encoders = encoder :: Nil },
            _ -> Resources.read((r, w) -> View.passPlan(r, w)), worlds);
        println("[video] コマ: ${take#outDir}（${painter}）")

    /// 1 コマの本編と HUD（GPU では GL の字のアトラスで組む）。
    def sceneOf(fonts: String -> FontAtlas): AppState -> List[Render.PlacedItem] =
        Resources.read((r, w) -> {
            let ctx = App.viewCtxOf(fonts("default"), SceneRender.design());
            App.composeScene(None, 1.0, SceneRender.design(), { world = View.frame(ctx, r, w), hud = View.hudFrame(ctx, r, w) })
        })
}
