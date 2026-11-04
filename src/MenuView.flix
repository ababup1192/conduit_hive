// MenuView — 3D の場面の上に重ねる画面のメニュー（純粋）: タイトル（名前・一言・始め方・操作の一覧）・ポーズ（続ける・タイトルへ）・
// クリア（かかった時間・倒した数）。背景はどれも StageView の 3D の場面（タイトルとクリアはゆっくり見回す迷路・ポーズは止まった遊びの場面）。
// 押せる物の当たりは絵と同じ木に ZStack.hit で積む（Controls.tapAt が同じ木から選ぶ）。
mod MenuView {

    use fge::{App, Color, Num, Render, TextDraw, Vec2, ZStack}
    use ZOrder.Layer

    /// タイトルの値: 文言・時刻（始め方の文言の明滅）。
    pub type alias TitleIn = { text = UiTextDoc.Rec, t = Float64 }

    /// ポーズの値: 文言・選んでいる項目。
    pub type alias PauseIn = { text = UiTextDoc.Rec, selected = World.PauseItem }

    /// クリアの値: 文言・記録・時刻（戻り方の文言の明滅）。
    pub type alias ClearIn = { text = UiTextDoc.Rec, tally = World.Tally, t = Float64 }

    /// 重ねるメニュー。Hidden = 遊んでいる間（HUD だけ）。
    pub enum Menu {
        case Hidden
        case Title(TitleIn)
        case Pause(PauseIn)
        case Clear(ClearIn)
    }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def width(): Float64 = World.width()
    def height(): Float64 = World.height()

    /// メニューの木（Layer.Menu に積む）。
    pub def tree(ctx: App.ViewCtx, theme: ThemeDoc.Doc, m: Menu): ZStack.Tree[Layer, World.Press] =
        let th = ThemeDoc.rec(theme);
        match m {
            case Menu.Hidden   => ZStack.leaf(Nil)
            case Menu.Title(v) => ZStack.of(ZStack.leaf(titleOf(ctx, th#accent, th#bg, v)) :: ZStack.hit(World.Press.Start, wholeScreen()) :: Nil)
            case Menu.Pause(v) => pauseOf(ctx, th#accent, th#bg, v)
            case Menu.Clear(v) => ZStack.of(ZStack.leaf(clearOf(ctx, th#accent, th#bg, v)) :: ZStack.hit(World.Press.ToTitle, wholeScreen()) :: Nil)
        }

    def wholeScreen(): { position = Vec2.Vec2, size = Vec2.Vec2 } = { position = Vec2.zero(), size = p(width(), height()) }

    // ── 部品 ──

    /// 頂点ごとに色と濃さを持つ多角形を、画面の座標のまま置く。
    def gradAt(vertices: List[(Vec2.Vec2, Color, Float64)], z: Int32): Render.PlacedItem =
        { at = Vec2.zero(), item = Render.gradPolygon(vertices |> List.map(v -> { let (at, c, a) = v; { pos = at, color = c, alpha = a } }), z) }

    /// 横いっぱいの帯: 真ん中が濃く左右の端へ消える（上下 top..bottom）。
    def band(c: Color, alpha: Float64, top: Float64, bottom: Float64, z: Int32): List[Render.PlacedItem] =
        let mid = width() / 2.0;
        gradAt((p(0.0, top), c, 0.0) :: (p(mid, top), c, alpha) :: (p(mid, bottom), c, alpha) :: (p(0.0, bottom), c, 0.0) :: Nil, z)
            :: gradAt((p(mid, top), c, alpha) :: (p(width(), top), c, 0.0) :: (p(width(), bottom), c, 0.0) :: (p(mid, bottom), c, alpha) :: Nil, z)
            :: Nil

    /// 真ん中が明るく左右へ消える細い線（帯の縁）。
    def rule(c: Color, y: Float64, halfWidth: Float64, z: Int32): List[Render.PlacedItem] =
        let mid = width() / 2.0;
        gradAt((p(mid - halfWidth, y), c, 0.0) :: (p(mid, y - 0.6), c, 0.9) :: (p(mid + halfWidth, y), c, 0.0) :: (p(mid, y + 0.6), c, 0.9) :: Nil, z) :: Nil

    /// 画面全体を沈める幕（上が浅く下が深い）。
    def veil(bg: Color, alpha: Float64): Render.PlacedItem =
        { at = Vec2.zero(), item = Render.vgrad(p(width(), height()), { top = bg, bottom = Color.darken(bg, 0.6) }, 0) |> Render.fade(alpha) }

    /// 影を 1 px 下に敷いた 1 行の字（真ん中を center に）。
    def lettering(ctx: App.ViewCtx, text: String, size: Float64, color: Color, shade: Color, center: Vec2.Vec2, z: Int32): List[Render.PlacedItem] =
        TextDraw.centeredAt({ text = text, atlas = ctx#atlas, size = size, color = shade, z = z, center = p(center#x, center#y + Float64.max(1.0, size / 14.0)) })
            :: TextDraw.centeredAt({ text = text, atlas = ctx#atlas, size = size, color = color, z = z + 1, center = center }) :: Nil

    /// 左の端を x にそろえた 1 行の字。
    def leftText(ctx: App.ViewCtx, text: String, size: Float64, color: Color, x: Float64, y: Float64, z: Int32): Render.PlacedItem =
        TextDraw.centered({ text = text, atlas = ctx#atlas, size = size, color = color, z = z, centerX = x + TextDraw.width(text, ctx#atlas, size) / 2.0, y = y })

    /// 右の端を x にそろえた 1 行の字。
    def rightText(ctx: App.ViewCtx, text: String, size: Float64, color: Color, x: Float64, y: Float64, z: Int32): Render.PlacedItem =
        TextDraw.centered({ text = text, atlas = ctx#atlas, size = size, color = color, z = z, centerX = x - TextDraw.width(text, ctx#atlas, size) / 2.0, y = y })

    /// 0..1 をゆっくり行き来する明滅（周期 2 秒）。
    def pulse(t: Float64): Float64 = 0.5 + 0.5 * Num.sin(t * Num.pi())

    /// 角の丸い縦のグラデの板に差し色の細い縁。
    def plate(size: Vec2.Vec2, ink: Color, bg: Color, edge: Float64, z: Int32): Render.Item =
        Render.vgrad(size, { top = Color.lighten(bg, 0.1), bottom = Color.darken(bg, 0.45) }, z)
            |> Render.fade(0.88) |> Render.rounded(5.0) |> Render.outlineA({ color = ink, alpha = edge, width = 1.0 })

    /// 板と、その上の縁の差し色の細い光（真ん中が明るく両端へ消える）。
    def card(at: Vec2.Vec2, size: Vec2.Vec2, ink: Color, bg: Color, edge: Float64, z: Int32): List[Render.PlacedItem] =
        let (l, r, y) = (at#x + 6.0, at#x + size#x - 6.0, at#y + 0.5);
        let mid = (l + r) / 2.0;
        { at = at, item = plate(size, ink, bg, edge, z) }
            :: gradAt((p(l, y), ink, 0.0) :: (p(mid, y - 0.5), ink, 0.85) :: (p(r, y), ink, 0.0) :: (p(mid, y + 0.7), ink, 0.85) :: Nil, z + 1)
            :: Nil

    // ── タイトル ──

    /// 名前の帯（上下に差し色の細い線）・一言・明滅する始め方・下の操作の一覧の板。
    def titleOf(ctx: App.ViewCtx, ink: Color, bg: Color, v: TitleIn): List[Render.PlacedItem] =
        let tx = v#text;
        let mid = width() / 2.0;
        let grey = Color.mix(ink, Color.rgb(0.85, 0.88, 0.9), 0.65);
        let rows = tx#controls;
        let rowH = 10.0;
        let panel = p(230.0, 14.0 + rowH * Int32.toFloat64(List.length(rows)));
        let panelAt = p(mid - panel#x / 2.0, height() - 14.0 - panel#y);
        let controlRows = rows |> List.zipWithIndex |> List.flatMap(e -> {
            let (i, c) = e;
            let y = panelAt#y + 7.0 + rowH * Int32.toFloat64(i);
            rightText(ctx, c#key, 8.0, ink, mid - 8.0, y, 3) :: leftText(ctx, c#action, 8.0, grey, mid + 8.0, y, 3) :: Nil
        });
        let divider = gradAt((p(mid - 0.5, panelAt#y + 6.0), ink, 0.5) :: (p(mid + 0.5, panelAt#y + 6.0), ink, 0.5)
                                 :: (p(mid + 0.5, panelAt#y + panel#y - 6.0), ink, 0.1) :: (p(mid - 0.5, panelAt#y + panel#y - 6.0), ink, 0.1) :: Nil, 3);
        List.flatten(
            (veil(bg, 0.35) :: Nil)
                :: band(Color.darken(bg, 0.3), 0.82, 48.0, 116.0, 1)
                :: rule(ink, 48.0, 170.0, 2) :: rule(ink, 116.0, 170.0, 2)
                :: lettering(ctx, tx#gameTitle, 34.0, ink, Color.darken(bg, 0.5), p(mid, 76.0), 3)
                :: lettering(ctx, tx#tagline, 8.0, grey, Color.darken(bg, 0.5), p(mid, 103.0), 3)
                :: Render.fadeAll(0.45 + 0.55 * pulse(v#t), lettering(ctx, tx#startHint, 11.0, Color.lighten(ink, 0.25), Color.darken(bg, 0.6), p(mid, 140.0), 3))
                :: card(panelAt, panel, ink, bg, 0.35, 2) :: (divider :: controlRows) :: Nil)

    // ── ポーズ ──

    /// 遊びの場面を沈める幕と真ん中の板（見出し・続ける・タイトルへ）。選んでいる項目は明るい板と差し色の縁と左右の矢じり。
    def pauseOf(ctx: App.ViewCtx, ink: Color, bg: Color, v: PauseIn): ZStack.Tree[Layer, World.Press] =
        let mid = width() / 2.0;
        let panel = p(170.0, 104.0);
        let at = p(mid - panel#x / 2.0, (height() - panel#y) / 2.0);
        let button = p(124.0, 20.0);
        let items = (World.PauseItem.Resume, World.Press.Resume, v#text#resume, at#y + 46.0)
            :: (World.PauseItem.ToTitle, World.Press.ToTitle, v#text#toTitle, at#y + 72.0) :: Nil;
        let buttons = items |> List.map(e -> {
            let (item, press, label, y) = e;
            let picked = item == v#selected;
            let bAt = p(mid - button#x / 2.0, y);
            let center = p(mid, y + button#y / 2.0);
            let arrows = if (picked) chevrons(ink, center, button#x / 2.0 + 7.0) else Nil;
            let face = { at = bAt, item = plate(button, ink, if (picked) Color.lighten(bg, 0.14) else bg, if (picked) 0.9 else 0.3, 2) };
            ZStack.of(ZStack.leaf(face :: TextDraw.centeredAt({ text = label, atlas = ctx#atlas, size = 11.0, color = if (picked) Color.lighten(ink, 0.2) else Color.mix(ink, bg, 0.35), z = 4, center = center }) :: arrows)
                      :: ZStack.hit(press, { position = bAt, size = button }) :: Nil)
        });
        let frame = veil(bg, 0.62) :: card(at, panel, ink, bg, 0.5, 1)
            ::: rule(ink, at#y + 34.0, 60.0, 2) ::: lettering(ctx, v#text#pauseTitle, 16.0, ink, Color.darken(bg, 0.5), p(mid, at#y + 20.0), 3);
        ZStack.of(ZStack.leaf(frame) :: buttons)

    /// 項目の左右の小さな矢じり（真ん中 center から half だけ外）。
    def chevrons(ink: Color, center: Vec2.Vec2, half: Float64): List[Render.PlacedItem] =
        let tri = (x: Float64, dir: Float64) ->
            gradAt((p(x, center#y - 4.0), ink, 0.9) :: (p(x + dir * 5.0, center#y), ink, 0.4) :: (p(x, center#y + 4.0), ink, 0.9) :: Nil, 4);
        tri(center#x - half - 5.0, 1.0) :: tri(center#x + half + 5.0, -1.0) :: Nil

    // ── クリア ──

    /// 見出しの帯・かかった時間と倒した数の 2 つのメニュー・明滅する戻り方。
    def clearOf(ctx: App.ViewCtx, ink: Color, bg: Color, v: ClearIn): List[Render.PlacedItem] =
        let tx = v#text;
        let mid = width() / 2.0;
        let grey = Color.mix(ink, Color.rgb(0.85, 0.88, 0.9), 0.65);
        let cardSize = p(110.0, 50.0);
        let stat = (label: String, value: String, cx: Float64) -> {
            let at = p(cx - cardSize#x / 2.0, 132.0);
            card(at, cardSize, ink, bg, 0.4, 2)
                ::: TextDraw.centeredAt({ text = label, atlas = ctx#atlas, size = 8.0, color = grey, z = 3, center = p(cx, at#y + 12.0) })
                :: lettering(ctx, value, 20.0, ink, Color.darken(bg, 0.5), p(cx, at#y + 32.0), 3)
        };
        List.flatten(
            (veil(bg, 0.45) :: Nil)
                :: band(Color.darken(bg, 0.3), 0.82, 62.0, 116.0, 1)
                :: rule(ink, 62.0, 160.0, 2) :: rule(ink, 116.0, 160.0, 2)
                :: lettering(ctx, tx#clearTitle, 28.0, ink, Color.darken(bg, 0.5), p(mid, 89.0), 3)
                :: stat(tx#clearTime, clockText(v#tally#seconds), mid - 64.0)
                :: stat(tx#clearKills, Int32.toString(v#tally#kills), mid + 64.0)
                :: Render.fadeAll(0.45 + 0.55 * pulse(v#t), lettering(ctx, tx#clearBack, 10.0, Color.lighten(ink, 0.25), Color.darken(bg, 0.6), p(mid, 218.0), 3))
                :: Nil)

    /// 秒を「分:秒」の字に（秒は 2 桁）。
    def clockText(seconds: Float64): String =
        let total = Int32.max(0, Num.floorInt(seconds));
        let s = Int32.modulo(total, 60);
        "${total / 60}:${if (s < 10) "0" else ""}${s}"
}
