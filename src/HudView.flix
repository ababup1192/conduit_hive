// HudView — 遊んでいる間の HUD（App.withHudView。view の絵のどれよりも手前）: 照準・左下の体力・右下の武器の並びと弾の数・
// 拾った時の知らせ（照準の下）・被弾の赤み・F3 の診断の行（純粋）。値は View が World から組んだ Hud を受ける。
mod HudView {

    use fge::{App, Bezier, Color, FrameDiagnostics, Num, Render, TextDraw, Vec2}
    use WeaponsDoc.Weapon

    /// 武器の並びの 1 つ: 武器・持っているか・構えているか。
    pub type alias Slot = { weapon = Weapon, owned = Bool, current = Bool }

    /// 拾った時の知らせ: 文言と、出してからの進み（0..1。1 で消える）。
    pub type alias Notice = { text = String, age = Float64 }

    /// HUD を描くのに要る値。
    pub type alias Hud = {
        theme = ThemeDoc.Doc,
        askingQuit = Bool,
        // マウスをキャプチャしているか（照準を明るくする）・F3 の診断の行を出すか。
        looking = Bool,
        showsDiagnostics = Bool,
        // 構えている武器の残りの弾（無限なら None）・武器の並び（1〜3 キーの順）。
        ammo = Option[Int32],
        slots = List[Slot],
        // 体力の残りの割合（0..1）・被弾の赤みの強さ（0..1）・倒れてからやり直すまでの進み（0..1。倒れていなければ 0）。
        health = Float64,
        hurt = Float64,
        down = Float64,
        notice = Option[Notice]
    }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    def width(): Float64 = World.width()
    def height(): Float64 = World.height()

    /// 照準（真ん中）・左下の体力・右下の武器の並びと弾の数・知らせ・被弾の赤み（画面の縁）・F3 の診断の行（左上）。
    /// 照準はキャプチャしていない間は薄くする（撃てないことを見せる）。終了の確認の窓が出ている間は出さない（窓の文言を読ませる）。
    pub def draw(ctx: App.ViewCtx, w: Hud): List[Render.PlacedItem] =
        let theme = ThemeDoc.rec(w#theme);
        let alpha = if (w#looking) 1.0 else 0.35;
        let panels = List.flatten(crosshair(theme#accent, theme#bg) :: healthPanel(ctx, theme#accent, theme#bg, w#health)
                                  :: ammoPanel(ctx, theme#accent, theme#bg, w#ammo) :: slotRow(ctx, theme#accent, theme#bg, w#slots) :: Nil);
        let toast = w#notice |> Option.map(noticeOf(ctx, theme#accent, theme#bg)) |> Option.getWithDefault(Nil);
        let marks = if (w#askingQuit) Nil else List.flatten(hurtEdges(w#hurt, w#down) :: Render.fadeAll(alpha, panels) :: toast :: Nil);
        let rows = if (w#showsDiagnostics) ctx#diagnostics |> Option.map(FrameDiagnostics.summaryLines) |> Option.getWithDefault(Nil) else Nil;
        let lines = rows |> List.zipWithIndex |> List.map(e -> {
            let (i, line) = e;
            let size = 8.0;
            TextDraw.centered({ text = line, atlas = ctx#atlas, size = size, color = theme#accent, z = 4,
                                centerX = 4.0 + TextDraw.width(line, ctx#atlas, size) / 2.0, y = 4.0 + Int32.toFloat64(i) * (size + 2.0) })
        });
        List.append(marks, lines)

    /// 頂点ごとに色と濃さを持つ多角形を、画面の座標のまま置く。
    def gradAt(vertices: List[(Vec2.Vec2, Color, Float64)], z: Int32): Render.PlacedItem =
        { at = Vec2.zero(), item = Render.gradPolygon(vertices |> List.map(v -> { let (at, c, a) = v; { pos = at, color = c, alpha = a } }), z) }

    /// 角の丸い縦のグラデの板に差し色の細い縁（体力・弾・武器の板の地）。
    def plate(size: Vec2.Vec2, ink: Color, bg: Color, edge: Float64): Render.Item =
        Render.vgrad(size, { top = Color.lighten(bg, 0.08), bottom = Color.darken(bg, 0.4) }, 0)
            |> Render.fade(0.8) |> Render.rounded(4.0) |> Render.outlineA({ color = ink, alpha = edge, width = 1.0 })

    /// 照準: 真ん中を空けて 4 方向へ先細りに伸びる針（根元が濃く先へ薄れる）と、真ん中の小さな菱形。
    /// どれも 1 px 太い暗い影を下に敷き、明るい壁の前でも読める。
    def crosshair(ink: Color, shade: Color): List[Render.PlacedItem] =
        let c = p(width() / 2.0, height() / 2.0);
        let dirs = (1.0, 0.0) :: (-1.0, 0.0) :: (0.0, 1.0) :: (0.0, -1.0) :: Nil;
        let needle = (grow: Float64, color: Color, alphaIn: Float64, alphaOut: Float64, z: Int32, dir: (Float64, Float64)) -> {
            let (dx, dy) = dir;
            let (gap, len) = (3.0 - grow, 5.0 + grow * 2.0);
            let (wIn, wOut) = (0.8 + grow, 0.25 + grow);
            let at = (along: Float64, side: Float64) -> p(c#x + dx * along - dy * side, c#y + dy * along + dx * side);
            gradAt((at(gap, 0.0 - wIn), color, alphaIn) :: (at(gap + len, 0.0 - wOut), color, alphaOut)
                       :: (at(gap + len, wOut), color, alphaOut) :: (at(gap, wIn), color, alphaIn) :: Nil, z)
        };
        let diamond = (r: Float64, color: Color, a: Float64, z: Int32) ->
            gradAt((p(c#x, c#y - r), color, a) :: (p(c#x + r, c#y), color, a) :: (p(c#x, c#y + r), color, a) :: (p(c#x - r, c#y), color, a) :: Nil, z);
        List.flatten(
            (dirs |> List.map(needle(0.7, shade, 0.7, 0.2, 0)))
                :: (dirs |> List.map(needle(0.0, ink, 1.0, 0.35, 1)))
                :: (diamond(1.6, shade, 0.7, 0) :: diamond(0.9, ink, 1.0, 1) :: Nil) :: Nil)

    /// 右下の弾の数の板の大きさと左上。
    def ammoSize(): Vec2.Vec2 = p(44.0, 22.0)
    def ammoAt(): Vec2.Vec2 = p(width() - 10.0 - ammoSize()#x, height() - 10.0 - ammoSize()#y)

    /// 右下の弾の数の板: 中に弾の数（無限は ∞ の線）。
    def ammoPanel(ctx: App.ViewCtx, ink: Color, bg: Color, ammo: Option[Int32]): List[Render.PlacedItem] =
        let at = ammoAt();
        let center = p(at#x + ammoSize()#x / 2.0, at#y + ammoSize()#y / 2.0);
        let low = ammo |> Option.exists(n -> n <= 0);
        let tone = if (low) bloodColor() else ink;
        let count = match ammo {
            case Some(n) => TextDraw.centeredAt({ text = Int32.toString(n), atlas = ctx#atlas, size = 14.0, color = tone, z = 2, center = center }) :: Nil
            case None    => infinity(center, ink)
        };
        { at = at, item = plate(ammoSize(), tone, bg, 0.45) } :: count

    // ── 武器の並び ──

    /// 武器の並びの板 1 つの大きさと間。
    def slotSize(): Vec2.Vec2 = p(30.0, 18.0)
    def slotGap(): Float64 = 4.0

    /// 弾の数の板の上に、1〜3 キーの順で武器の板を右へそろえて並べる。構えている武器は明るい板と差し色の縁と下の帯・
    /// 持っていない武器は薄い空の板（番号だけ）。
    def slotRow(ctx: App.ViewCtx, ink: Color, bg: Color, slots: List[Slot]): List[Render.PlacedItem] =
        let n = Int32.toFloat64(List.length(slots));
        let left = width() - 10.0 - (n * slotSize()#x + (n - 1.0) * slotGap());
        let top = ammoAt()#y - 5.0 - slotSize()#y;
        slots |> List.zipWithIndex |> List.flatMap(e -> {
            let (i, slot) = e;
            slotTile(ctx, ink, bg, i + 1, p(left + Int32.toFloat64(i) * (slotSize()#x + slotGap()), top), slot)
        })

    def slotTile(ctx: App.ViewCtx, ink: Color, bg: Color, number: Int32, at: Vec2.Vec2, slot: Slot): List[Render.PlacedItem] =
        let size = slotSize();
        let (edge, iconAlpha, plateAlpha) = if (slot#current) (0.95, 1.0, 1.0) else if (slot#owned) (0.4, 0.7, 0.85) else (0.18, 0.18, 0.45);
        let base = if (slot#current) Color.lighten(bg, 0.12) else bg;
        let label = TextDraw.centeredAt({ text = Int32.toString(number), atlas = ctx#atlas, size = 6.0, color = ink, z = 3,
                                         center = p(at#x + 4.5, at#y + 4.5) });
        let underline = if (slot#current)
            gradAt((p(at#x + 4.0, at#y + size#y + 1.5), ink, 0.2) :: (p(at#x + size#x / 2.0, at#y + size#y + 1.5), ink, 1.0)
                       :: (p(at#x + size#x - 4.0, at#y + size#y + 1.5), ink, 0.2) :: (p(at#x + size#x / 2.0, at#y + size#y + 2.6), ink, 0.6) :: Nil, 3) :: Nil
            else Nil;
        let tile = { at = at, item = plate(size, ink, base, edge) |> Render.fade(plateAlpha) };
        List.flatten((tile :: Nil) :: Render.fadeAll(if (slot#owned) 1.0 else 0.45, label :: Nil)
                     :: weaponIcon(slot#weapon, p(at#x + 3.0, at#y + 3.0), p(size#x - 6.0, size#y - 6.0), ink, bg, iconAlpha) :: underline :: Nil)

    /// 武器の横からの影絵（箱 box の中の 0..1 の座標で書いた多角形）。上が明るく下が暗い差し色で、濃さは alpha。
    // WhyNot: Render.fadeAll で薄めない — 頂点ごとに濃さを持つ多角形には効かない。
    def weaponIcon(w: Weapon, at: Vec2.Vec2, box: Vec2.Vec2, ink: Color, bg: Color, alpha: Float64): List[Render.PlacedItem] =
        let q = (u: Float64, v: Float64) -> p(at#x + u * box#x, at#y + v * box#y);
        let poly = (pts: List[(Float64, Float64)]) -> {
            let (vMin, vMax) = pts |> List.foldLeft((acc, pt) -> (Float64.min(fst(acc), snd(pt)), Float64.max(snd(acc), snd(pt))), (1.0, 0.0));
            gradAt(pts |> List.map(pt -> {
                let (u, v) = pt;
                let k = (v - vMin) / Float64.max(0.01, vMax - vMin);
                (q(u, v), Color.mix(Color.lighten(ink, 0.25), Color.mix(ink, bg, 0.45), k), alpha)
            }), 2)
        };
        let shapes = match w {
            case Weapon.Pistol  =>
                ((0.22, 0.3) :: (0.86, 0.3) :: (0.86, 0.5) :: (0.22, 0.5) :: Nil)
                    :: ((0.26, 0.5) :: (0.46, 0.5) :: (0.42, 0.95) :: (0.2, 0.95) :: Nil) :: Nil
            case Weapon.Shotgun =>
                ((0.22, 0.32) :: (1.0, 0.32) :: (1.0, 0.46) :: (0.22, 0.46) :: Nil)
                    :: ((0.5, 0.46) :: (0.74, 0.46) :: (0.74, 0.62) :: (0.5, 0.62) :: Nil)
                    :: ((0.0, 0.4) :: (0.24, 0.32) :: (0.3, 0.56) :: (0.02, 0.78) :: Nil) :: Nil
            case Weapon.Rifle   =>
                ((0.14, 0.28) :: (0.84, 0.28) :: (0.84, 0.52) :: (0.14, 0.52) :: Nil)
                    :: ((0.84, 0.34) :: (1.0, 0.34) :: (1.0, 0.44) :: (0.84, 0.44) :: Nil)
                    :: ((0.48, 0.52) :: (0.6, 0.52) :: (0.66, 0.95) :: (0.53, 0.95) :: Nil)
                    :: ((0.0, 0.3) :: (0.16, 0.3) :: (0.16, 0.62) :: (0.0, 0.72) :: Nil) :: Nil
        };
        shapes |> List.map(poly)

    // ── 体力 ──

    /// 傷の色（暖かい赤。クリーチャーの発光と同じ側の色）。
    def bloodColor(): Color = Color.rgb(0.66, 0.07, 0.04)

    /// 左下の体力の板: 中に残りの割合の帯（左が濃く右へ明るむ・減ると傷の色へ寄る）と数。
    def healthPanel(ctx: App.ViewCtx, ink: Color, bg: Color, health: Float64): List[Render.PlacedItem] =
        let size = p(92.0, 22.0);
        let at = p(10.0, height() - 10.0 - size#y);
        let left = at#x + 6.0;
        let right = at#x + size#x - 30.0;
        let (top, bottom) = (at#y + 7.0, at#y + size#y - 7.0);
        let tone = Color.mix(bloodColor(), ink, Num.clamp01(health * 1.6 - 0.3));
        let end = left + (right - left) * Num.clamp01(health);
        let track = gradAt((p(left, top), Color.darken(bg, 0.6), 0.9) :: (p(right, top), Color.darken(bg, 0.6), 0.9)
                               :: (p(right, bottom), Color.darken(bg, 0.3), 0.9) :: (p(left, bottom), Color.darken(bg, 0.3), 0.9) :: Nil, 1);
        let fill = gradAt((p(left, top), Color.darken(tone, 0.35), 1.0) :: (p(end, top), Color.lighten(tone, 0.15), 1.0)
                              :: (p(end, bottom), tone, 1.0) :: (p(left, bottom), Color.darken(tone, 0.5), 1.0) :: Nil, 2);
        let count = TextDraw.centeredAt({ text = Int32.toString(Num.roundInt(health * 100.0)), atlas = ctx#atlas, size = 12.0, color = tone, z = 2,
                                         center = p(at#x + size#x - 15.0, at#y + size#y / 2.0) });
        { at = at, item = plate(size, ink, bg, 0.45) } :: track :: (if (health > 0.0) fill :: Nil else Nil) ::: count :: Nil

    /// 被弾の赤み: 画面の 4 辺から内へ消える台形の帯（縁が濃い）。倒れている間は進みに合わせて画面全体を暗い赤へ沈める。
    def hurtEdges(hurt: Float64, down: Float64): List[Render.PlacedItem] =
        let (wd, ht) = (width(), height());
        let inset = 20.0 + 26.0 * hurt;
        let a = Num.clamp01(hurt) * 0.55;
        let red = bloodColor();
        let band = (o1: Vec2.Vec2, o2: Vec2.Vec2, i2: Vec2.Vec2, i1: Vec2.Vec2) ->
            gradAt((o1, red, a) :: (o2, red, a) :: (i2, red, 0.0) :: (i1, red, 0.0) :: Nil, 0);
        let (tl, tr, br, bl) = (p(0.0, 0.0), p(wd, 0.0), p(wd, ht), p(0.0, ht));
        let (itl, itr, ibr, ibl) = (p(inset, inset), p(wd - inset, inset), p(wd - inset, ht - inset), p(inset, ht - inset));
        let edges = if (a <= 0.0) Nil else band(tl, tr, itr, itl) :: band(tr, br, ibr, itr) :: band(br, bl, ibl, ibr) :: band(bl, tl, itl, ibl) :: Nil;
        let veil = if (down <= 0.0) Nil
            else { at = Vec2.zero(), item = Render.vgrad({ x = wd, y = ht }, { top = Color.darken(red, 0.7), bottom = Color.darken(red, 0.9) }, 0) |> Render.fade(Num.clamp01(down) * 0.85) } :: Nil;
        List.append(edges, veil)

    /// ∞ の線（横に寝た 8 の字。字の無いフォントでも出る）。
    def infinity(center: Vec2.Vec2, ink: Color): List[Render.PlacedItem] =
        let points = List.range(0, 41) |> List.map(i -> {
            let t = Int32.toFloat64(i) * Num.tau() / 40.0;
            let k = 1.0 + Num.sin(t) * Num.sin(t);
            p(center#x + 9.0 * Num.cos(t) / k, center#y + 9.0 * Num.sin(t) * Num.cos(t) / k)
        });
        Bezier.polyline(points, { width = 1.6 }, ink, 2)

    // ── 拾った時の知らせ ──

    /// 照準の下の角の丸いメニューに文言。出た瞬間に少し下から浮き上がり、終わりの 3 割で薄れて消える。
    def noticeOf(ctx: App.ViewCtx, ink: Color, bg: Color, n: Notice): List[Render.PlacedItem] =
        let size = 10.0;
        let rise = Num.clamp01(n#age * 6.0);
        let alpha = Num.clamp01((1.0 - n#age) / 0.3);
        let textW = TextDraw.width(n#text, ctx#atlas, size);
        let box = p(textW + 18.0, 16.0);
        let center = p(width() / 2.0, height() / 2.0 + 30.0 - 4.0 * rise);
        let at = p(center#x - box#x / 2.0, center#y - box#y / 2.0);
        Render.fadeAll(alpha * (0.4 + 0.6 * rise),
            { at = at, item = plate(box, ink, bg, 0.6) }
                :: TextDraw.centeredAt({ text = n#text, atlas = ctx#atlas, size = size, color = Color.lighten(ink, 0.2), z = 2, center = center }) :: Nil)
}
