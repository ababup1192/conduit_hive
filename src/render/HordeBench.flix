// HordeBench — 段 0.5 の測りの入口（make bench-horde）。普段の遊び（Main・Game.app）とは別の入口で、窓ありの GL で数秒回して数を書き出す。
//
// 立つのは最後の部屋の真ん中（東を向く）。敵は部屋に散って立ち、プレイヤーへ歩いて寄る（HordeScene）。
// 測る組は環境変数で決める（BENCH_LABEL・BENCH_ENEMIES・BENCH_POSE=each|shared・BENCH_GROUPS・BENCH_THROTTLE=1・
// BENCH_PARTS=split|merged・BENCH_PIPES・BENCH_PIPE_MESH=zone|loose・BENCH_WARMUP・BENCH_FRAMES）。
// 数は 2 つの道で取る:
//   窓の前の CPU だけの測り … 姿勢を作る（HordeScene.step）と、描く物の木を組む（passPlan）を nanoTime で 1 コマずつ
//   窓の測り             … 1 コマの間隔（frame#realNow の差）と FrameDiagnostics（GL へ送る・swap・GPU・3D の数）
// 結果は debug/bench/horde-<label>.txt に書く（App.addOutput）。
mod HordeBench {
    use fge::{AnimationClip3d, App, Clock, FrameDiagnostics, Gltf, HeadlessLoad, Log, LwjglLayer, Model3d, Render, Scene3d}

    import java.io.File
    import java.lang.System

    /// 測る間に変わらない物。
    type alias Kit = {
        res = Res.Res,
        cfg = HordeScene.Config,
        body = HordeScene.Body,
        pipes = Map[Char, List[Scene3d.Instance3d]],
        viewer = HordeScene.Viewer,
        start = World.World,
        warmup = Int32,
        frames = Int32,
        out = String,
        // 窓の前の CPU だけの測りの行。
        micro = List[String]
    }

    /// 窓の 1 コマの記録。intervalNs = 前のコマからの間隔・diag = 前のコマを描いた時の診断・computed = 前のコマに作った姿勢の数。
    type alias Sample = { intervalNs = Int64, diag = FrameDiagnostics.Diagnostics, computed = Int32 }

    /// 測りの状態。lastAt = 前のコマの実時間（秒。まだ無ければ負）。
    type alias State = { world = World.World, horde = HordeScene.Horde, frame = Int32, lastAt = Float64, samples = List[Sample] }

    def guardPath(): String = "assets/bench/guard.glb"

    def outDir(): String = "debug/bench"

    pub def main(): Unit \ IO =
        if (LwjglLayer.ensureMainThread()) ()
        else {
            let env = App.Headless.envOf(App.Headless.requestFromProcess());
            match loadKit(env) {
                case Err(e)  => Log.warn("[bench] 始められない: ${e}")
                case Ok(kit) => launch({ micro = microbench(kit) | kit })
            }
        }

    def launch(kit: Kit): Unit \ IO =
        discard (new File(outDir())).mkdirs();
        run {
            App.loadAndLaunch(() -> app(kit))
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO

    // ── 組と読み込み ──

    def numOr(env: Map[String, String], name: String, fallback: Int32): Int32 =
        Map.get(name, env) |> Option.flatMap(Int32.fromString) |> Option.getWithDefault(fallback)

    def configOf(env: Map[String, String]): HordeScene.Config =
        let text = (name, fallback) -> Map.getWithDefault(name, fallback, env);
        { label = text("BENCH_LABEL", "bench"),
          enemies = numOr(env, "BENCH_ENEMIES", 50),
          pose = if (text("BENCH_POSE", "each") == "shared") HordeScene.PoseMode.Shared else HordeScene.PoseMode.Each,
          groups = numOr(env, "BENCH_GROUPS", 8),
          throttle = text("BENCH_THROTTLE", "0") == "1",
          parts = if (text("BENCH_PARTS", "split") == "merged") HordeScene.Parts.Merged else HordeScene.Parts.Split,
          pipes = numOr(env, "BENCH_PIPES", 0),
          pipeMesh = if (text("BENCH_PIPE_MESH", "zone") == "loose") HordeScene.PipeMesh.Loose else HordeScene.PipeMesh.PerZone }

    def bodyOf(model: Model3d.Model3d): Result[String, HordeScene.Body] =
        forM (
            skin <- model#skin |> Option.toOk("${guardPath()} に骨が無い");
            clip <- Map.get("walk", model#clips) |> Option.toOk("${guardPath()} に walk のクリップが無い")
        ) yield { model = model, skin = skin, clip = clip }

    def loadKit(env: Map[String, String]): Result[String, Kit] \ IO =
        let cfg = configOf(env);
        let (docs, model) = run { (HeadlessLoad.handle(Controls.loadDocs), Gltf.load(guardPath())) } with Fs.FileRead.runWithIO;
        let res = Res.build(docs);
        let zone = MazeDoc.rec(res#mazeDoc)#finalZone;
        let center = Maze.middleCellOf(res#maze, zone) |> Option.toOk("最後の部屋 ${zone} が迷路に無い");
        forM (
            m <- model;
            body <- bodyOf(m);
            cell <- center
        ) yield {
            let (x, z) = Maze.centerOf(res#maze, cell);
            let start = World.placeWalker(res, { x = x, z = z }, 90.0, -4.0, World.initial(res));
            let walker = World.walkerOf(start);
            let viewer = { x = walker#x, z = walker#z, yaw = walker#yaw };
            { res = res, cfg = cfg, body = body, pipes = HordeScene.pipeArt(cfg, res#maze), viewer = viewer, start = start,
              warmup = numOr(env, "BENCH_WARMUP", 120), frames = numOr(env, "BENCH_FRAMES", 360),
              out = "${outDir()}/horde-${cfg#label}.txt", micro = Nil }
        }

    def initial(kit: Kit): State =
        { world = kit#start, horde = HordeScene.spawnHorde(kit#cfg, kit#body, kit#res#maze, MazeDoc.rec(kit#res#mazeDoc)#finalZone, kit#viewer),
          frame = 0, lastAt = -1.0, samples = Nil }

    // ── App ──

    def app(kit: Kit): App.App[State, {}] =
        App.game({ init = initial(kit), update = (frame, s) -> step(kit, frame, s),
                   view = (ctx, s) -> View.frame(ctx, kit#res, s#world), reloads = Nil })
            |> App.withPassPlan(s -> passPlan(kit, s))
            |> App.withSpriteAtlases(_ -> { texture = Particles3d.textureName(), key = Particles3d.textureKey(), baked = kit#res#particleTexture } :: Nil)
            |> App.withDiagnostics
            |> App.addOutput({ keyOf = s -> if (isDone(kit, s)) kit#cfg#label else "", write = s -> writeReport(kit, s), onJump = App.OnJump.Skip })
            |> App.quitWhen((_, s) -> s#frame >= kit#warmup + kit#frames + 4)

    def isDone(kit: Kit, s: State): Bool = s#frame > kit#warmup + kit#frames

    /// 1 コマ: 前のコマの間隔と診断を記録し、群れを進める。
    // WhyNot: 系で frame#diagnostics を読む（ゲームの系ではしない）— この入口は測るだけで、記録の再生（make flow）に載らない。
    def step(kit: Kit, frame: App.Frame, s: State): State =
        let now = Clock.secondsOf(frame#realNow);
        let measuring = s#frame > kit#warmup and s#frame <= kit#warmup + kit#frames and s#lastAt >= 0.0;
        let sample = if (measuring) frame#diagnostics |> Option.map(d -> { intervalNs = nanosOf(now - s#lastAt), diag = d, computed = s#horde#computed }) else None;
        { horde = HordeScene.step(kit#cfg, kit#body, kit#viewer, frame#dt, s#horde), frame = s#frame + 1, lastAt = now,
          samples = List.append(Option.toList(sample), s#samples) | s }

    def nanosOf(seconds: Float64): Int64 = Float64.round(seconds * 1.0e9) |> Float64.tryToInt64 |> Option.getWithDefault(0i64)

    /// 本編の Pass の計画に、敵と見える区画のパイプを足す。
    def passPlan(kit: Kit, s: State): Render.PassPlan =
        let base = View.stageIn(kit#res, s#world);
        let pipes = Maze.visibleFrom(kit#res#maze, kit#viewer#x, kit#viewer#z) |> Set.toList
            |> List.flatMap(id -> Map.getWithDefault(id, Nil, kit#pipes));
        let extra = { instances = List.append(HordeScene.instances(kit#cfg, kit#body, s#horde), pipes), lights = Nil };
        StageView.passPlan({ zones = extra :: base#zones | base })

    // ── 窓の前の CPU だけの測り ──

    /// 姿勢を作る（step）と描く物の木を組む（passPlan）の 1 コマあたりの時間。120 コマ慣らしてから 240 コマ測る。
    def microbench(kit: Kit): List[String] \ IO =
        let warmed = microLoop(kit, 120, { state = initial(kit), rows = Nil, passes = 0 });
        let measured = microLoop(kit, 240, { rows = Nil | warmed });
        let rows = measured#rows;
        let msOf = (f: ((Int64, Int64)) -> Int64) -> rows |> List.map(r -> ms(f(r)));
        "cpu_pose_ms   ${spread(msOf(fst))}" :: "cpu_plan_ms   ${spread(msOf(snd))}  (passes ${Int32.toString(measured#passes)})" :: Nil

    /// 測りの途中: 状態・コマごとの (姿勢, 木) の時間・組んだ Pass の数の合計（木を組んだ結果を使う所）。
    type alias Micro = { state = State, rows = List[(Int64, Int64)], passes = Int32 }

    /// 今の時刻（ナノ秒）。n を受けるのは、n を作る計算を時刻を取る前に済ませるため。
    // WhyNot: let で受けた値をそのまま後で使わない — コンパイラが純粋な let を使う所まで下げ、測る区間の外へ出してしまう。
    def stampAfter(n: Int32): Int64 \ IO = if (n < 0) 0i64 else System.nanoTime()

    def microLoop(kit: Kit, left: Int32, acc: Micro): Micro \ IO =
        if (left <= 0) acc
        else {
            let t0 = System.nanoTime();
            let horde = HordeScene.step(kit#cfg, kit#body, kit#viewer, 1.0 / 60.0, acc#state#horde);
            let t1 = stampAfter(horde#computed);
            let next = { horde = horde | acc#state };
            let passes = List.length(passPlan(kit, next)#passes);
            let t2 = stampAfter(passes);
            microLoop(kit, left - 1, { state = next, rows = (t1 - t0, t2 - t1) :: acc#rows, passes = acc#passes + passes })
        }

    // ── 書き出し ──

    def ms(ns: Int64): Float64 = Int64.toFloat64(ns) / 1.0e6

    def at(p: Int32, sorted: List[Float64]): Float64 =
        List.drop((List.length(sorted) - 1) * p / 100, sorted) |> List.head |> Option.getWithDefault(0.0)

    def fmt(v: Float64): String = Float64.toString(Float64.round(v * 1000.0) / 1000.0)

    /// 中央値・95 パーセンタイル・最大（ミリ秒）。
    def spread(xs: List[Float64]): String =
        let sorted = List.sort(xs);
        "median ${fmt(at(50, sorted))}  p95 ${fmt(at(95, sorted))}  max ${fmt(at(100, sorted))}"

    def medianInt(xs: List[Int32]): Int32 = List.drop(List.length(xs) / 2, List.sort(xs)) |> List.head |> Option.getWithDefault(0)

    /// 描き先ごとの GPU の時間の平均（ミリ秒）。
    def passAverages(samples: List[Sample]): String =
        let all = samples |> List.flatMap(x -> x#diag#gpuPasses);
        let n = Int32.max(1, List.length(samples));
        all |> List.foldLeft((acc, p) -> Map.insertWith((a, b) -> a + b, fst(p), snd(p), acc), Map.empty()) |> Map.toList
            |> List.map(e -> { let (name, total) = e; "${name}=${fmt(ms(total) / Int32.toFloat64(n))}" })
            |> List.join(" ")

    def report(kit: Kit, s: State): String =
        let xs = s#samples;
        let cfg = kit#cfg;
        let counts = xs |> List.map(x -> x#diag#scene3dCounts);
        let gpu = xs |> List.filterMap(x -> x#diag#gpuNs) |> List.map(ms);
        let duration = AnimationClip3d.duration(kit#body#clip);
        let lines =
            "label ${cfg#label}" ::
            "config enemies=${cfg#enemies} pose=${cfg#pose} groups=${cfg#groups} throttle=${cfg#throttle} parts=${cfg#parts} pipes=${cfg#pipes} pipeMesh=${cfg#pipeMesh} walkClip=${fmt(duration)}s" ::
            "frames ${List.length(xs)}" ::
            "interval_ms   ${spread(xs |> List.map(x -> ms(x#intervalNs)))}" ::
            "work_ms       ${spread(xs |> List.map(x -> ms(x#intervalNs - x#diag#swapNs)))}" ::
            "submit_ms     ${spread(xs |> List.map(x -> ms(x#diag#submitNs)))}" ::
            "swap_ms       ${spread(xs |> List.map(x -> ms(x#diag#swapNs)))}" ::
            "gpu_ms        ${spread(gpu)}" ::
            "gpu_passes    ${passAverages(xs)}" ::
            "scene3d       instances=${medianInt(counts |> List.map(c -> c#instances))} drawn=${medianInt(counts |> List.map(c -> c#drawn))} drawCalls=${medianInt(counts |> List.map(c -> c#drawCalls))}" ::
            "poses_frame   ${fmt(Int32.toFloat64(xs |> List.map(x -> x#computed) |> List.foldLeft((a, b) -> a + b, 0)) / Int32.toFloat64(Int32.max(1, List.length(xs))))}" ::
            kit#micro;
        List.join("\n", lines) + "\n"

    def writeReport(kit: Kit, s: State): Unit \ Fs.FileWrite =
        match Fs.FileWrite.write({ str = report(kit, s) }, kit#out) {
            case Ok(_)  => ()
            case Err(e) => Log.warnThen("[bench] ${kit#out} を書けない: ${e}", ())
        }
}
