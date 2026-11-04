// Particles3d — 3D の粒の emitter（純粋）: 出す（emit）・動かす（positionAt）・消す（step）と、描く Billboard3d へ写す（billboards）。
// 粒は出した時刻・始まりの点・速さだけを持ち、今の位置は時刻から計算する（コマの長さで軌跡が変わらない）。
// 置き場は 2 つ: World = ステージの座標（火花・煙・体液・輪）・Muzzle = 銃口の局所の座標（マズルフラッシュ。+Z が銃身の向き。銃が動いても銃口に付いて動く）。
// 粒の列は新しい物が前で、上限（Doc の limit）を越えたら古い物から消す（added）。
// 絵はコードで塗った 1 枚（textureOf。真ん中ほど明るいなめらかな濃淡の型）を光を当てずに色で塗る。値は Particles3dDoc。
mod Particles3d {
    use fge::{Color, Hash01, Mat4, Num, PxSpriteAtlas, Rect2, Scene3d, Texture3d, Vec2, Vec3}

    /// 粒の種類（Doc の欄と、描くコマを決める）。Muzzle は武器ごとの形・Smoke は壁の煙・Gore は弾けた時の体液・Ring は弾けた時の衝撃の輪。
    pub enum Kind with Eq, ToString {
        case Muzzle(WeaponsDoc.Weapon)
        case Spark
        case Smoke
        case Ichor
        case Gore
        case Ring
    }

    /// 粒の置き場。World = ステージの座標・Muzzle = 銃口の局所の座標（原点が銃口・+Z が銃身の向き）。
    pub enum Space with Eq, ToString {
        case World
        case Muzzle
    }

    /// 粒 1 つ。born = 出した時刻（遊びの時計の秒）・life = 寿命（秒）。
    pub type alias Particle = { kind = Kind, space = Space, origin = Vec3.Vec3, velocity = Vec3.Vec3, born = Float64, life = Float64 }

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    /// ビルボードの真ん中（粒の位置を絵の真ん中に合わせる）。
    def center(): Vec2.Vec2 = { x = 0.5, y = 0.5 }

    /// 種類の出し方。
    def burstOf(doc: Particles3dDoc.Doc, kind: Kind): Particles3dDoc.Burst = match kind {
        case Kind.Muzzle(WeaponsDoc.Weapon.Pistol)  => Particles3dDoc.rec(doc)#muzzle#pistol
        case Kind.Muzzle(WeaponsDoc.Weapon.Shotgun) => Particles3dDoc.rec(doc)#muzzle#shotgun
        case Kind.Muzzle(WeaponsDoc.Weapon.Rifle)   => Particles3dDoc.rec(doc)#muzzle#rifle
        case Kind.Spark  => Particles3dDoc.rec(doc)#spark
        case Kind.Smoke  => Particles3dDoc.rec(doc)#smoke
        case Kind.Ichor  => Particles3dDoc.rec(doc)#ichor
        case Kind.Gore   => Particles3dDoc.rec(doc)#gore
        case Kind.Ring   => Particles3dDoc.rec(doc)#ring
    }

    /// 武器 w のマズルフラッシュの出し方。
    pub def muzzleOf(doc: Particles3dDoc.Doc, w: WeaponsDoc.Weapon): Particles3dDoc.Burst = burstOf(doc, Kind.Muzzle(w))

    /// dir と直角な 2 本の向き（長さ 1）。
    def basisOf(dir: Vec3.Vec3): (Vec3.Vec3, Vec3.Vec3) =
        let helper = if (Float64.abs(dir#y) < 0.9) Vec3.v3(0.0, 1.0, 0.0) else Vec3.v3(1.0, 0.0, 0.0);
        let u = Vec3.normalized(Vec3.cross(helper, dir));
        (u, Vec3.cross(dir, u))

    /// 時刻 t に、点 at から向き dir（長さは問わない）のまわりへ粒を出す。seed が同じなら同じ粒が出る。
    pub def emit(doc: Particles3dDoc.Doc, kind: Kind, space: Space, at: Vec3.Vec3, dir: Vec3.Vec3, t: Float64, seed: Int32): List[Particle] =
        let b = burstOf(doc, kind);
        let d = Vec3.normalized(dir);
        let (u, v) = basisOf(d);
        let cone = rad(Num.clamp(0.0, 180.0, b#spread));
        List.range(0, Int32.max(0, b#count)) |> List.map(i -> {
            let key = seed * 97 + i;
            let tilt = cone * Hash01.at(key, 51);
            let around = Num.tau() * Hash01.at(key, 52);
            let side = Vec3.add(Vec3.mul(u, Num.cos(around)), Vec3.mul(v, Num.sin(around)));
            let heading = Vec3.add(Vec3.mul(d, Num.cos(tilt)), Vec3.mul(side, Num.sin(tilt)));
            let speed = b#speed * (0.5 + 0.5 * Hash01.at(key, 53));
            let life = b#life * (1.0 - Num.clamp01(b#lifeJitter) * Hash01.at(key, 54));
            { kind = kind, space = space, origin = at, velocity = Vec3.mul(heading, speed), born = t, life = life }
        })

    /// 寿命の進み k（0..1）の粒の色: 衝撃の輪だけは広がるにつれて暗くし、終わりには地の暗さへ沈める（ほかは glowOf のまま）。
    // WhyNot: 輪を同じ明るさのまま広げない — 寿命の終わりに 1 m を超える明るい輪が画面の真ん中に残り、UI の部品に見える。
    def fadedOf(b: Particles3dDoc.Burst, kind: Kind, k: Float64): Color =
        if (kind == Kind.Ring) brightened(b#color, b#intensity * (1.0 - Num.clamp01(k)) * (1.0 - Num.clamp01(k))) else glowOf(b)

    /// 粒の色に明るさの倍率を掛けた色（描き手は色を線形の量へ戻すので、戻した後で intensity 倍になる画面の値で渡す）。
    def glowOf(b: Particles3dDoc.Burst): Color = brightened(b#color, b#intensity)

    def brightened(c: Color, intensity: Float64): Color =
        let k = Float64.max(0.0, intensity);
        let lift = v -> Texture3d.linearToSrgb(Texture3d.srgbToLinear(v) * k);
        Color.rgb(lift(c#r), lift(c#g), lift(c#b))

    /// projectile の光る玉（点 at が玉の真ん中・光を当てない）。region = 粒の絵のコマ（無ければ描かない）。
    pub def spitBillboard(doc: Particles3dDoc.Doc, texture: String, area: Option[Rect2.Rect2], at: Vec3.Vec3): Option[Scene3d.Billboard3d] =
        let g = Particles3dDoc.rec(doc)#spit;
        area |> Option.map(rect ->
            Scene3d.billboard(texture, rect, at, { x = g#size, y = g#size })
                |> Scene3d.withAnchor(center()) |> Scene3d.withBillboardTint(brightened(g#color, g#intensity)) |> Scene3d.unlit)

    /// 曳光弾の頭の光る玉（点 at が玉の真ん中・大きさは線の太さの 4 倍）。region = 粒の絵のコマ（無ければ描かない）。
    pub def tracerHead(doc: Particles3dDoc.Doc, texture: String, area: Option[Rect2.Rect2], at: Vec3.Vec3): Option[Scene3d.Billboard3d] =
        let tr = Particles3dDoc.rec(doc)#tracer;
        area |> Option.map(rect ->
            Scene3d.billboard(texture, rect, at, { x = tr#width * 4.0, y = tr#width * 4.0 })
                |> Scene3d.withAnchor(center()) |> Scene3d.withBillboardTint(brightened(tr#color, tr#intensity)) |> Scene3d.unlit)

    /// projectile の玉に付ける点光源。
    pub def spitLight(doc: Particles3dDoc.Doc, at: Vec3.Vec3): Scene3d.PointLight =
        let g = Particles3dDoc.rec(doc)#spit;
        { position = at, color = g#color, intensity = g#lightIntensity, range = g#lightRange }

    /// 時刻 t にまだ見えているか（出した時刻から寿命の間）。
    def isAlive(t: Float64, p: Particle): Bool = t >= p#born and t - p#born < p#life

    /// 時刻 t に消えた粒を落とす。
    pub def step(t: Float64, ps: List[Particle]): List[Particle] = ps |> List.filter(isAlive(t))

    /// 新しい粒 fresh を前に足し、上限（Doc の limit）を越えたら古い物から消す（粒の列は新しい物が前）。
    pub def added(doc: Particles3dDoc.Doc, fresh: List[Particle], ps: List[Particle]): List[Particle] =
        List.take(Int32.max(0, Particles3dDoc.rec(doc)#limit), List.append(fresh, ps))

    /// ranged の溜めの口の光（点 at が玉の真ん中・k = 溜めの進み 0..1 で大きくなる）。region = 粒の絵のコマ（無ければ描かない）。
    pub def chargeBillboard(doc: Particles3dDoc.Doc, texture: String, area: Option[Rect2.Rect2], at: Vec3.Vec3, k: Float64): Option[Scene3d.Billboard3d] =
        let c = Particles3dDoc.rec(doc)#charge;
        let size = c#size * (0.25 + 0.75 * Num.clamp01(k));
        area |> Option.map(rect ->
            Scene3d.billboard(texture, rect, at, { x = size, y = size })
                |> Scene3d.withAnchor(center()) |> Scene3d.withBillboardTint(brightened(c#color, c#intensity * (0.4 + 0.6 * Num.clamp01(k)))) |> Scene3d.unlit)

    /// 時刻 t の位置（置き場の座標。下へ引く強さは種類の Doc の値）。
    def positionAt(doc: Particles3dDoc.Doc, t: Float64, p: Particle): Vec3.Vec3 =
        let age = Float64.max(0.0, t - p#born);
        let fall = 0.5 * burstOf(doc, p#kind)#gravity * age * age;
        Vec3.add(p#origin, Vec3.v3(p#velocity#x * age, p#velocity#y * age - fall, p#velocity#z * age))

    /// 置き場 space の生きている粒の Billboard3d。base = 置き場の座標 → 描く場面の座標の行列（Muzzle なら今の銃口の行列・World なら単位行列）。
    /// regionOf = 種類 → アトラスのコマ（無ければその粒は描かない）。大きさは寿命の終わりに grow 倍へ変わり、横は aspect 倍。
    pub def billboards(doc: Particles3dDoc.Doc, texture: String, regionOf: Kind -> Option[Rect2.Rect2],
                       space: Space, base: Mat4.Mat4, t: Float64, ps: List[Particle]): List[Scene3d.Billboard3d] =
        ps |> List.filter(p -> p#space == space and isAlive(t, p)) |> List.filterMap(p ->
            regionOf(p#kind) |> Option.map(rect -> {
                let b = burstOf(doc, p#kind);
                let size = b#size * (1.0 + (b#grow - 1.0) * Num.clamp01((t - p#born) / Float64.max(0.0001, p#life)));
                Scene3d.billboard(texture, rect, Mat4.apply(base, positionAt(doc, t, p)), { x = size * b#aspect, y = size })
                    |> Scene3d.withAnchor(center()) |> Scene3d.withBillboardTint(fadedOf(b, p#kind, (t - p#born) / Float64.max(0.0001, p#life))) |> Scene3d.unlit
            }))

    // ── 粒の絵 ──

    /// 粒の絵の 1 辺（px）。マズルフラッシュは目の前 0.4 m で画面の 90 px ほどになるので、引き伸ばして画素が見えない大きさにする。
    def muzzleSide(): Int32 = 128
    // WhyNot: 右の列のコマを 32 px にしない — 弾けた時の輪は 1 m を超えて広がり、32 px では縁の画素の段が見える。
    def sparkSide(): Int32 = 64

    /// 右の列の小さなコマ（火花・輪・煙）の左上の y。
    def ringTop(): Int32 = sparkSide()
    def smokeTop(): Int32 = sparkSide() * 2

    /// 粒の絵を GPU に登録する名前と、上げ直すかを決める鍵（絵はコードで決まるので、塗り方を替えたら版を上げる）。
    pub def textureName(): String = "particles3d"
    pub def textureKey(): String = "particles3d:v5"

    /// 種類のコマ（textureOf の中の矩形）。
    pub def regionOf(t: PxSpriteAtlas.Baked, kind: Kind): Option[Rect2.Rect2] = match kind {
        case Kind.Muzzle(_) => PxSpriteAtlas.regionOf(t, "muzzle", "a")
        case Kind.Smoke     => PxSpriteAtlas.regionOf(t, "smoke", "a")
        case Kind.Ring      => PxSpriteAtlas.regionOf(t, "ring", "a")
        case _              => PxSpriteAtlas.regionOf(t, "spark", "a")
    }

    /// 粒の絵 1 枚（左にマズルフラッシュ・右の列に上から火花・輪・煙）。色は白から灰の濃淡だけで、粒の色は描く時に掛ける。
    /// 型の外は透明（ビルボードは α が半分未満の画素を捨てる）。読み込みで 1 回だけ作る。
    pub def textureOf(): PxSpriteAtlas.Baked =
        let side = muzzleSide() + sparkSide();
        let pixels = Vector.range(0, side * side) |> Vector.map(i -> {
            let (x, y) = (Int32.modulo(i, side), i / side);
            if (x < muzzleSide() and y < muzzleSide()) muzzlePixel(x, y)
            else if (x >= muzzleSide() and y < ringTop()) sparkPixel(x - muzzleSide(), y)
            else if (x >= muzzleSide() and y < smokeTop()) ringPixel(x - muzzleSide(), y - ringTop())
            else if (x >= muzzleSide() and y < smokeTop() + sparkSide()) smokePixel(x - muzzleSide(), y - smokeTop())
            else 0
        });
        { side = side, pixels = pixels,
          regions = Map#{ ("muzzle", "a") => { x = 0, y = 0, w = muzzleSide(), h = muzzleSide() },
                          ("spark", "a") => { x = muzzleSide(), y = 0, w = sparkSide(), h = sparkSide() },
                          ("ring", "a") => { x = muzzleSide(), y = ringTop(), w = sparkSide(), h = sparkSide() },
                          ("smoke", "a") => { x = muzzleSide(), y = smokeTop(), w = sparkSide(), h = sparkSide() } } }

    /// 画素の真ん中の、型の中の座標（-1〜1）。
    def unitOf(n: Int32, x: Int32, y: Int32): (Float64, Float64) =
        let c = Int32.toFloat64(n) / 2.0;
        ((Int32.toFloat64(x) + 0.5 - c) / c, (Int32.toFloat64(y) + 0.5 - c) / c)

    /// 明るさ k（0〜1）の灰の不透明な画素。
    def greyOf(k: Float64): Int32 =
        let v = Num.roundInt(255.0 * Num.clamp01(k));
        Int32.bitwiseOr(Int32.bitwiseOr(-16777216, Int32.leftShift(v, 16)), Int32.bitwiseOr(Int32.leftShift(v, 8), v))

    /// マズルフラッシュ: 真ん中の丸から長短 3 本ずつの光の筋が先細りに出る星。真ん中が白く、外へ向かって暗くなる。
    def muzzlePixel(x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(muzzleSide(), x, y);
        let d = Num.sqrt(u * u + v * v);
        let a = Num.atan2(v, u);
        let inRay = List.range(0, 6) |> List.exists(k -> {
            let length = if (Int32.modulo(k, 2) == 0) 1.0 else 0.68;
            let da = a - (Int32.toFloat64(k) * Num.pi() / 3.0 + Num.pi() / 2.0);
            let across = Float64.abs(Num.sin(da)) * d;
            Num.cos(da) > 0.0 and d <= length and across <= 0.16 * (1.0 - d / length)
        });
        let falloff = 1.0 - Num.clamp01(d);
        if (d <= 0.34 or inRay) greyOf(0.08 + 0.92 * falloff * falloff) else 0

    /// 火花: 丸。真ん中が白く、縁へ向かって暗くなる。
    def sparkPixel(x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(sparkSide(), x, y);
        let d = Num.sqrt(u * u + v * v);
        if (d <= 1.0) greyOf(1.0 - 0.85 * d) else 0

    /// 衝撃の輪: 細い輪。輪の真ん中の線が明るく、内と外の縁へ暗くなる。
    def ringPixel(x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(sparkSide(), x, y);
        let d = Num.sqrt(u * u + v * v);
        let off = Float64.abs(d - 0.9) / 0.05;
        if (off <= 1.0) greyOf(1.0 - 0.6 * off) else 0

    /// 煙: 縁がちぎれた丸い塊（4 px の升ごとの濃淡で縁を削り、真ん中ほど明るい）。
    def smokePixel(x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(sparkSide(), x, y);
        let d = Num.sqrt(u * u + v * v);
        let n = Hash01.at((x / 4) * 131 + y / 4, 91);
        if (d <= 0.62 + 0.38 * n) greyOf(0.55 + 0.45 * n * (1.0 - d)) else 0
}
