// PostSpecs — 画面の後処理（ブルーム・トーンマップ・ビネット・フィルムの粒・FXAA）の面の Spec（純粋）。見た目の Doc から 1 回だけ組み、Res が持つ。
// Pass の並びと面の置き方は PostView。
// WhyNot: 毎コマ PostView で組み直さない — 描き手は名前の同じ Spec を中身の木で比べ直すので、組み直すたびに 5 本の木を丸ごと比べる。
mod PostSpecs {

    use fge::{PostProcess, ShaderDoc}
    use fge::ShaderDoc.{BinOp, Field, Shade, Out, TexChan}

    /// 後処理の面の Spec の組。
    pub type alias Specs = { bright = ShaderDoc.Spec, blurA = ShaderDoc.Spec, blurB = ShaderDoc.Spec, main = ShaderDoc.Spec, fxaa = ShaderDoc.Spec }

    pub def scenePass(): String = "scene"
    pub def brightPass(): String = "bright"
    pub def bloomPassA(): String = "bloomA"
    pub def bloomPassB(): String = "bloomB"

    /// トーンマップ済みの本編の Pass の名前（画面へ写す前の最後の段）。
    /// WhyNot: 縮めた Pass や design の大きさにしない — FXAA は 1 テクセル = 1 画素を前提に縁を探す。
    pub def postPass(): String = "post"

    /// 見た目の Doc から後処理の面を組む。
    pub def build(look: LookDoc.Rec): Specs =
        { bright = brightSpec(look), blurA = blurOf(brightPass(), look#bloomRadius, look#bloomTaps),
          blurB = blurOf(bloomPassA(), look#bloomRadius * 0.5, look#bloomTaps), main = mainSpec(look), fxaa = PostProcess.fxaaSpec(postPass()) }

    def wd(): Float64 = Design.width()
    def ht(): Float64 = Design.height()

    def k(v: Float64): Field = Field.Const(v)
    def add(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Add, a = a, b = b })
    def sub(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Sub, a = a, b = b })
    def mul(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Mul, a = a, b = b })
    def linear(f: Field): Field = Field.Sampler({ filter = ShaderDoc.FilterMode.Linear, of = f })
    def aspect(): Float64 = wd() / ht()

    /// 場面とブルームを足し、ビネットを掛けてトーンマップし、粒で仕上げる。
    def mainSpec(look: LookDoc.Rec): ShaderDoc.Spec =
        let sharp = chan -> Field.Tex({ name = scenePass(), chan = chan });
        let bloom = chan -> linear(Field.Tex({ name = bloomPassB(), chan = chan }));
        let vig = sub(k(1.0), mul(k(look#vignette),
            Field.Smoothstep({ lo = 0.35, hi = 1.05, of = Field.RadialAspect({ cx = 0.5, cy = 0.5, aspect = aspect() }) })));
        let base = chan -> mul(add(sharp(chan), mul(k(look#bloomStrength), bloom(chan))), Field.Ref("vig"));
        let hdr = { name = "conduit_post", cycleRate = 0.0,
                    bindings = ("vig", vig) :: ("r0", base(TexChan.R)) :: ("g0", base(TexChan.G)) :: ("b0", base(TexChan.B)) :: Nil,
                    out = Out.Fill({ shade = Shade.Rgb({ r = Field.Ref("r0"), g = Field.Ref("g0"), b = Field.Ref("b0") }), alpha = k(1.0) }) };
        PostProcess.tonemappedWith(PostProcess.Tonemap.AcesFitted, look#exposure, look#whitePoint, grainOf(look), hdr)

    /// トーンマップの後の 0..1 の色に足すフィルムの粒（1 秒に 24 回選び直す升目ごとの乱数・暗い所ほど見える）。
    def grainOf(look: LookDoc.Rec): (Field, Field, Field) -> Shade =
        (r, g, b) -> {
            let grain = mul(sub(Field.Hash1({ scale = 360.0, seed = 7, bucket = Some(Field.Un({ op = ShaderDoc.UnOp.Floor, of = Field.Time({ scale = 24.0, offset = k(0.0) }) })) }), k(0.5)),
                            k(look#grain * 2.0));
            Shade.Rgb({ r = add(r, grain), g = add(g, grain), b = add(b, grain) })
        }

    /// 場面の明るい所だけを残す（しきいは HDR の目盛り。1 を超える所が光る所）。
    def brightSpec(look: LookDoc.Rec): ShaderDoc.Spec =
        let read = chan -> linear(Field.Tex({ name = scenePass(), chan = chan }));
        let luma = PostProcess.luma709(read(TexChan.R), read(TexChan.G), read(TexChan.B));
        let over = Field.Smoothstep({ lo = look#bloomThreshold, hi = look#bloomThreshold + Float64.max(0.01, look#bloomKnee), of = luma });
        let chan = c -> mul(read(c), Field.Ref("over"));
        { name = "conduit_bright", cycleRate = 0.0, bindings = ("over", over) :: Nil,
          out = Out.Fill({ shade = Shade.Rgb({ r = chan(TexChan.R), g = chan(TexChan.G), b = chan(TexChan.B) }), alpha = k(1.0) }) }

    /// 前の Pass を Linear で読んでぼかし、そのまま写す面（ブルームの 2 段で共用）。
    def blurOf(src: String, radius: Float64, taps: Int32): ShaderDoc.Spec =
        let b = chan -> linear(Field.TexBlur({ name = src, chan = chan, radius = { x = radius / aspect(), y = radius },
                                               taps = ShaderDoc.blurTaps(taps), amount = k(1.0) }));
        { name = "conduit_blur_${src}", cycleRate = 0.0, bindings = Nil,
          out = Out.Fill({ shade = Shade.Rgb({ r = b(TexChan.R), g = b(TexChan.G), b = b(TexChan.B) }), alpha = k(1.0) }) }
}
