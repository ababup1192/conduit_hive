// HordeBench — 群れの重さの測りの入口（make bench-horde）。普段の遊び（Main・Game.app）とは別の入口で、窓ありの GL で数秒回して数を書き出す。
//
// 立つのは最後の部屋の真ん中（東を向く）。本物のクリーチャー（Creatures）を部屋に散らして置き、本物の規則（World.step → Horde.step）で
// 追わせ・押し合わせ・振らせ・吐かせる。プレイヤーは動かず撃たない。測る間に倒れないよう、敵の威力だけを 0 にした Doc で回す。
// 測る組は環境変数で決める（BENCH_LABEL・BENCH_ENEMIES・BENCH_PIPES・BENCH_PIPE_MESH=zone|loose・BENCH_WARMUP・BENCH_FRAMES）。
// 数は 2 つの道で取る:
//   窓の前の CPU だけの測り … 規則の 1 コマ（World.step）と、描く物の木を組む（View.passPlan。敵の姿勢を作るのもここ）を nanoTime で 1 コマずつ
//   窓の測り             … 1 コマの間隔（frame#realNow の差）と FrameDiagnostics（GL へ送る・swap・GPU・3D の数）
// 結果は debug/bench/horde-<label>.txt に書く（App.addOutput）。
mod HordeBench {
    use fge::{App, Clock, FrameDiagnostics, Hash01, HeadlessLoad, Log, LwjglLayer, Num, Render, Scene3d}

    import java.io.File
    import java.lang.System

    /// 測る組。pipes = 1 区画あたりのパイプの箱の数（0 で無し）。
    type alias Config = { label = String, enemies = Int32, pipes = Int32, pipeMesh = BenchPipes.PipeMesh }

    /// 測る間に変わらない物。
    type alias Kit = {
        res = Res.Res,
        cfg = Config,
        pipes = Map[Char, List[Scene3d.Instance3d]],
        start = World.World,
        warmup = Int32,
        frames = Int32,
        out = String,
        // 窓の前の CPU だけの測りの行。
        micro = List[String]
    }

    /// 窓の 1 コマの記録。intervalNs = 前のコマからの間隔・diag = 前のコマを描いた時の診断。
    type alias Sample = { intervalNs = Int64, diag = FrameDiagnostics.Diagnostics }

    /// 測りの状態。game = 遊びの状態・lastAt = 前のコマの実時間（秒。まだ無ければ負）。
    type alias State = { game = World.World, frame = Int32, lastAt = Float64, samples = List[Sample] }

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

    def configOf(env: Map[String, String]): Config =
        let text = (name, fallback) -> Map.getWithDefault(name, fallback, env);
        { label = text("BENCH_LABEL", "bench"), enemies = numOr(env, "BENCH_ENEMIES", 50), pipes = numOr(env, "BENCH_PIPES", 120),
          pipeMesh = if (text("BENCH_PIPE_MESH", "zone") == "loose") BenchPipes.PipeMesh.Loose else BenchPipes.PipeMesh.PerZone }

    /// 敵の威力だけを 0 にした Doc（測る間にプレイヤーが倒れて群れが消えないように）。
    def harmless(d: EnemiesDoc.Doc): EnemiesDoc.Doc =
        let r = EnemiesDoc.rec(d);
        EnemiesDoc.Doc.Doc({ melee = { damage = 0.0 | r#melee }, projectile = { damage = 0.0 | r#projectile } | r })

    def loadKit(env: Map[String, String]): Result[String, Kit] \ IO =
        let cfg = configOf(env);
        let docs = run { HeadlessLoad.handle(Controls.loadDocs) } with Fs.FileRead.runWithIO;
        let res = Res.build({ enemies = harmless(docs#enemies) | docs });
        let zone = res#maze#finalZone;
        Maze.middleCellOf(res#maze, zone) |> Option.toOk("最後の部屋 ${zone} が迷路に無い") |> Result.map(cell -> {
            let (x, z) = Maze.centerOf(res#maze, cell);
            let placed = World.settleZone(res, World.placeWalker(res, { x = x, z = z }, 90.0, -4.0, World.initial(res)));
            let start = World.withHorde(Horde.spawnNow(res, crowdOf(res, cfg#enemies, x, z), Horde.empty()), placed);
            { res = res, cfg = cfg, pipes = BenchPipes.artOf(cfg#pipes, cfg#pipeMesh, res#maze), start = start,
              warmup = numOr(env, "BENCH_WARMUP", 120), frames = numOr(env, "BENCH_FRAMES", 360),
              out = "${outDir()}/horde-${cfg#label}.txt", micro = Nil }
        })

    /// 最後の部屋の床のマスへ count 体を散らす（5 体に 1 体が ranged）。プレイヤーから 6 m より近いマスには置かない。
    def crowdOf(res: Res.Res, count: Int32, px: Float64, pz: Float64): List[{ kind = Creatures.Kind, x = Float64, z = Float64, yaw = Float64, home = Char }] =
        let m = res#maze;
        let cells = Map.get(m#finalZone, m#zones) |> Option.map(z -> z#cells) |> Option.getWithDefault(Nil)
            |> List.filter(c -> { let (cx, cz) = Maze.centerOf(m, c); Num.sqrt((cx - px) * (cx - px) + (cz - pz) * (cz - pz)) > 6.0 });
        let n = List.length(cells);
        if (n == 0) Nil else List.range(0, count) |> List.filterMap(i ->
            List.drop(Hash01.indexOf({ index = i, channel = 1 }, n), cells) |> List.head |> Option.map(cell -> {
                let (cx, cz) = Maze.centerOf(m, cell);
                let x = cx + (Hash01.at(i, 2) - 0.5) * m#cellSize * 0.8;
                let z = cz + (Hash01.at(i, 3) - 0.5) * m#cellSize * 0.8;
                { kind = if (Int32.modulo(i, 5) == 3) Creatures.Kind.Ranged else Creatures.Kind.Melee, x = x, z = z,
                  yaw = Num.atan2(px - x, pz - z), home = m#finalZone }
            }))

    def initial(kit: Kit): State = { game = kit#start, frame = 0, lastAt = -1.0, samples = Nil }

    // ── App ──

    def app(kit: Kit): App.App[State, {}] =
        App.game({ init = initial(kit), update = (frame, s) -> step(kit, frame, s),
                   view = (ctx, s) -> View.frame(ctx, kit#res, s#game), reloads = Nil })
            |> App.addClock({ clockOf = s -> s#game#play, withClock = (c, s) -> { game = { play = c | s#game } | s }, paceOf = s -> World.paceOf(s#game) })
            |> App.withPassPlan(s -> passPlan(kit, s))
            |> App.withHudView((ctx, s) -> View.hudFrame(ctx, kit#res, s#game))
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
        let sample = if (measuring) frame#diagnostics |> Option.map(d -> { intervalNs = nanosOf(now - s#lastAt), diag = d }) else None;
        { game = World.step(kit#res, World.walking(Walker.idle()), s#game), frame = s#frame + 1, lastAt = now, samples = List.append(Option.toList(sample), s#samples) | s }

    def nanosOf(seconds: Float64): Int64 = Float64.round(seconds * 1.0e9) |> Float64.tryToInt64 |> Option.getWithDefault(0i64)

    /// 本編の Pass の計画に、見える区画のパイプを足す。
    def passPlan(kit: Kit, s: State): Render.PassPlan =
        let base = View.stageIn(kit#res, s#game);
        let b = World.walkerOf(s#game);
        let pipes = Maze.visibleFrom(kit#res#maze, b#x, b#z) |> Set.toList |> List.flatMap(id -> Map.getWithDefault(id, Nil, kit#pipes));
        StageView.passPlan({ zones = { instances = pipes, lights = Nil } :: base#zones | base })

    // ── 窓の前の CPU だけの測り ──

    /// 規則の 1 コマ（時計を進めて World.step。App.traceFrame で実機と同じ道）と描く物の木を組む（passPlan）の 1 コマあたりの時間と、
    /// 作った姿勢の数。120 コマ慣らしてから 240 コマ測る。
    def microbench(kit: Kit): List[String] \ IO =
        let a = app(kit);
        let warmed = microLoop(kit, a, 120, { state = initial(kit), stepState = App.freshStepState(), rows = Nil, passes = 0, poses = 0 });
        let measured = microLoop(kit, a, 240, { rows = Nil, poses = 0 | warmed });
        let rows = measured#rows;
        let msOf = (f: ((Int64, Int64)) -> Int64) -> rows |> List.map(r -> ms(f(r)));
        "cpu_step_ms   ${spread(msOf(fst))}" :: "cpu_plan_ms   ${spread(msOf(snd))}  (passes ${Int32.toString(measured#passes)})" ::
        "poses_frame   ${fmt(Int32.toFloat64(measured#poses) / 240.0)}  (全員を描いた時。共有した姿勢は 1 と数える)" :: Nil

    /// 測りの途中: 状態・コマごとの (規則, 木) の時間・組んだ Pass の数の合計（木を組んだ結果を使う所）・作った姿勢の数の合計。
    type alias Micro = { state = State, stepState = App.StepState, rows = List[(Int64, Int64)], passes = Int32, poses = Int32 }

    /// 今の時刻（ナノ秒）。n を受けるのは、n を作る計算を時刻を取る前に済ませるため。
    // WhyNot: let で受けた値をそのまま後で使わない — コンパイラが純粋な let を使う所まで下げ、測る区間の外へ出してしまう。
    def stampAfter(n: Int32): Int64 \ IO = if (n < 0) 0i64 else System.nanoTime()

    def posesOf(kit: Kit, w: World.World): Int32 =
        let bodies = World.hordeOf(w)#enemies |> List.map(e -> { kind = e#kind, group = e#id, anim = e#anim, world = Horde.worldOf(e) });
        Creatures.drawnOf(kit#res#creatures, EnemiesDoc.rec(kit#res#enemies)#blendSeconds, World.seconds(w), bodies)#poses

    def microLoop(kit: Kit, a: App.App[State, {}], left: Int32, acc: Micro): Micro \ IO =
        if (left <= 0) acc
        else {
            let t0 = System.nanoTime();
            let (traced, stepState) = App.traceFrame(a, { dt = 1.0 / 60.0 | App.emptyFrame() }, acc#stepState, acc#state);
            let next = traced#after;
            let t1 = stampAfter(Horde.aliveCount(World.hordeOf(next#game)));
            let passes = List.length(passPlan(kit, next)#passes);
            let t2 = stampAfter(passes);
            microLoop(kit, a, left - 1, { state = next, stepState = stepState, rows = (t1 - t0, t2 - t1) :: acc#rows,
                                          passes = acc#passes + passes, poses = acc#poses + posesOf(kit, next#game) })
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
        let lines =
            "label ${cfg#label}" ::
            "config enemies=${cfg#enemies} pipes=${cfg#pipes} pipeMesh=${cfg#pipeMesh} alive_at_end=${Horde.aliveCount(World.hordeOf(s#game))}" ::
            "frames ${List.length(xs)}" ::
            "interval_ms   ${spread(xs |> List.map(x -> ms(x#intervalNs)))}" ::
            "work_ms       ${spread(xs |> List.map(x -> ms(x#intervalNs - x#diag#swapNs)))}" ::
            "submit_ms     ${spread(xs |> List.map(x -> ms(x#diag#submitNs)))}" ::
            "swap_ms       ${spread(xs |> List.map(x -> ms(x#diag#swapNs)))}" ::
            "gpu_ms        ${spread(gpu)}" ::
            "gpu_passes    ${passAverages(xs)}" ::
            "scene3d       instances=${medianInt(counts |> List.map(c -> c#instances))} drawn=${medianInt(counts |> List.map(c -> c#drawn))} drawCalls=${medianInt(counts |> List.map(c -> c#drawCalls))}" ::
            kit#micro;
        List.join("\n", lines) + "\n"

    def writeReport(kit: Kit, s: State): Unit \ Fs.FileWrite =
        match Fs.FileWrite.write({ str = report(kit, s) }, kit#out) {
            case Ok(_)  => ()
            case Err(e) => Log.warnThen("[bench] ${kit#out} を書けない: ${e}", ())
        }
}
