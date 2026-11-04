// SceneRender — ゲーム画面を画面なしで PNG に生成する（スナップショット比較用）。
// 実行: make render-all → gallery/*.png
//       make render SHOT=corridor → debug/corridor.png（1 枚だけ）
// 3D の場面と後処理の Pass は SoftRaster が CPU で塗る（実機の GPU と同じ式。MSAA は掛からない）。
mod SceneRender {
    use fge::{App, Color, FontAtlas, HeadlessFont, HeadlessRender, Render, Vec2}

    import java.io.File

    def design(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    def ttf(): String = "assets/Xolonium-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): HeadlessRender.RenderConfig =
        { design = design(), scale = 2, background = bg,
          fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 960, frameH = 540 | HeadlessRender.defaults() }

    /// 描く元（実機の起動と同じ Controls.loadDocs から組む）。
    def loadRes(): Res.Res \ IO =
        Res.build(run { Controls.loadDocs() } with Fs.FileRead.runWithIO)

    pub def all(): Unit \ IO = App.Headless.exitWith(allJob(App.Headless.requestFromProcess()))

    def allJob(_req: App.Headless.Request): Int32 \ IO =
        discard allShots();
        0

    /// 常駐（App.Headless.serveJobs）が /run で流す入口の束。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("SceneRender", "one", req -> oneJob(req)) ::
        App.Headless.job("SceneRender", "all", req -> allJob(req)) :: Nil

    /// 全部の場面を gallery/ へ生成し、PNG のパス列を返す（走行中のゲームへの POST /render もこれを呼ぶ）。
    pub def allShots(): List[String] \ IO = shotsInto("gallery", _ -> true)

    /// SHOT で指した場面だけを debug/ へ生成する（スナップショットを汚さない）。
    pub def one(): Unit \ IO = App.Headless.exitWith(oneJob(App.Headless.requestFromProcess()))

    def oneJob(req: App.Headless.Request): Int32 \ IO =
        let wanted = Map.getWithDefault("SHOT", "", App.Headless.envOf(req)) |> String.splitOn(substr = " ")
            |> List.map(String.trim) |> List.filter(n -> not String.isEmpty(n));
        let known = List.toSet(Shots.names());
        let unknown = wanted |> List.filter(n -> not Set.memberOf(n, known));
        if (List.isEmpty(wanted) or not List.isEmpty(unknown)) {
            println("[render] 描けない名前です: ${List.join(" ", unknown)}");
            println("[render] SHOT=<場面> に使えるのは: ${List.join(" ", Shots.names())}");
            1
        } else {
            let picked = List.toSet(wanted);
            discard shotsInto("debug", n -> Set.memberOf(n, picked));
            0
        }

    def shotsInto(outDir: String, keep: String -> Bool): List[String] \ IO =
        discard (new File(outDir)).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let res = loadRes();
        let cfg = cfgOf(outDir, atlas, LookDoc.rec(res#look)#fogColor);
        let ctx = App.viewCtxOf(atlas, design());
        Shots.names() |> List.filter(keep) |> List.filterMap(name ->
            Shots.worldOf(name, res) |> Option.map(w -> {
                let path = shoot(cfg, ctx, res, w, name);
                App.Headless.writeShotRecord(outDir, name, Some(E2e.fingerprint(res, w)));
                path
            }))

    /// 1 場面を Pass つきで PNG に生成する。
    def shoot(cfg: HeadlessRender.RenderConfig, ctx: App.ViewCtx, res: Res.Res, w: World.World, name: String): String \ IO =
        let noTextures = _ -> None;
        let prepared = Render.passSpecsOf(noTextures, View.passPlan(res, w));
        prepared#issues |> List.forEach(i -> println("[render] Pass の計画: ${i}"));
        let items = View.frame(ctx, res, w);
        let surfaces = Render.shaderSurfaces(items);
        let (drawables, polygons) = Render.drawWith(noTextures, Render.withoutShaders(items));
        HeadlessRender.renderPngWithPasses(cfg, prepared#specs, drawables, polygons, surfaces, name);
        let path = "${cfg#outDir}/${name}.png";
        println("rendered: ${path}");
        path
}
