// PostView — 画面の後処理（ブルーム・トーンマップ・ビネット・フィルムの粒・FXAA）の Pass の並びと、本編の面（純粋）。
// 場面の中身は呼ぶ側（StageView）が渡す。場面から bloomB までは 1 を超える明るさを持つ Pass。面の Spec は Res が持つ PostSpecs。
mod PostView {

    use fge::{Color, Render, RenderTarget, ShaderDoc, Vec2}
    use PostSpecs.{scenePass, brightPass, bloomPassA, bloomPassB, postPass}

    def wd(): Float64 = World.width()
    def ht(): Float64 = World.height()
    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    /// 後処理の Pass の並び: 場面（窓の画素の HDR）→ 明るい所 → ぼかし 2 回 → 本編の面を窓の画素の Rgba8Unorm へ。t = 粒の時刻。
    pub def chain(look: LookDoc.Rec, post: PostSpecs.Specs, scene: List[Render.PlacedItem], t: Float64): Render.PassPlan =
        let black = RenderTarget.LoadOp.Clear(Color.rgb(0.0, 0.0, 0.0));
        let passes =
            { name = scenePass(), clear = RenderTarget.LoadOp.Clear(look#fogColor), items = scene }
                :: { name = brightPass(), clear = black, items = fullFill(post#bright, 0.0) :: Nil }
                :: { name = bloomPassA(), clear = black, items = fullFill(post#blurA, 0.0) :: Nil }
                :: { name = bloomPassB(), clear = black, items = fullFill(post#blurB, 0.0) :: Nil }
                :: { name = postPass(), clear = black, items = fullFill(post#main, t) :: Nil }
                :: Nil;
        let at = s -> RenderTarget.withHdr({ scale = s | RenderTarget.defaultDescriptor() });
        { targets = Map#{ scenePass() => RenderTarget.withMsaa(look#msaaSamples, RenderTarget.withHdr(RenderTarget.windowDescriptor())),
                          brightPass() => at(look#bloomScale),
                          bloomPassA() => at(look#bloomScale * 0.5),
                          bloomPassB() => at(look#bloomScale * 0.5),
                          postPass() => RenderTarget.windowDescriptor() }
          | Render.passPlan(passes) }

    /// 画面へ置く面: post の Pass を FXAA でならして写す。
    pub def fxaaFill(post: PostSpecs.Specs): Render.PlacedItem = fullFill(post#fxaa, 0.0)

    def fullFill(spec: ShaderDoc.Spec, t: Float64): Render.PlacedItem =
        Render.shaderFill(spec, { position = Vec2.zero(), size = p(wd(), ht()) }, t, 0)
}
