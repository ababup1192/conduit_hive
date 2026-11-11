// Particles3d — 3D の粒の emitter（純粋）: 出す（emit）・動かす（positionAt）・消す（step）と、描く Billboard3d へ写す（billboards）。
// 粒は出した時刻・始まりの点・速さだけを持ち、今の位置は時刻から計算する（コマの長さで軌跡が変わらない）。
// 置き場は 2 つ: World = ステージの座標（火花・煙・体液・輪）・Muzzle = 銃口の局所の座標（マズルフラッシュ。+Z が銃身の向き。銃が動いても銃口に付いて動く）。
// 粒の列は新しい物が前で、上限（Doc の limit）を越えたら古い物から消す（added）。
// 絵はコードで塗った 1 枚（textureOf。真ん中ほど明るいなめらかな濃淡の型）を光を当てずに色で塗る。値は Particles3dDoc。
mod Particles3d {
    use fge::{Color, Hash01, Mat4, Num, PxSpriteAtlas, Rect2, Scene3d, Texture3d, Vec2, Vec3}

    /// 粒の種類（Doc の欄と、描くコマを決める）。Muzzle は武器ごとの形・MuzzleSmoke は撃った後の銃口の薄い煙・Smoke は壁の煙・Gore は弾けた時の体液・Ring は弾けた時の衝撃の輪・
    /// Blast は手榴弾の爆発の粒（BlastPart の 4 つ）。
    pub enum Kind with Eq, ToString {
        case Muzzle(WeaponsDoc.Weapon)
        case MuzzleSmoke
        case Spark
        case Smoke
        case Ichor
        case Gore
        case Ring
        case Blast(BlastPart)
    }

    /// 爆発の部分: 真ん中の光・床を走る衝撃の輪・上る煙・飛び散る火花と破片・火の玉の塊・床の焦げ跡。
    /// Ring・Fireball・Scorch は形で描く（BlastFx。ビルボードのコマが無い）。
    pub enum BlastPart with Eq, ToString {
        case Flash
        case Ring
        case Smoke
        case Debris
        case Fireball
        case Scorch
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
        case Kind.MuzzleSmoke => Particles3dDoc.rec(doc)#muzzleSmoke
        case Kind.Spark  => Particles3dDoc.rec(doc)#spark
        case Kind.Smoke  => Particles3dDoc.rec(doc)#smoke
        case Kind.Ichor  => Particles3dDoc.rec(doc)#ichor
        case Kind.Gore   => Particles3dDoc.rec(doc)#gore
        case Kind.Ring   => Particles3dDoc.rec(doc)#ring
        case Kind.Blast(BlastPart.Flash)  => Particles3dDoc.rec(doc)#blast#flash
        case Kind.Blast(BlastPart.Ring)   => Particles3dDoc.rec(doc)#blast#ring
        case Kind.Blast(BlastPart.Smoke)  => Particles3dDoc.rec(doc)#blast#smoke
        case Kind.Blast(BlastPart.Debris) => Particles3dDoc.rec(doc)#blast#debris
        case Kind.Blast(BlastPart.Fireball) => Particles3dDoc.rec(doc)#blast#fireball#puff
        case Kind.Blast(BlastPart.Scorch) => Particles3dDoc.rec(doc)#blast#scorch
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
    pub def tracerHead(tr: Particles3dDoc.Tracer, texture: String, area: Option[Rect2.Rect2], at: Vec3.Vec3): Option[Scene3d.Billboard3d] =
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

    /// 粒 p の時刻 t の形の番号: マズルフラッシュは粒ごとにずらした番号から、Doc の muzzleFlicker 秒ごとに次の形へ替わる（ほかの種類は 0）。
    def frameAt(doc: Particles3dDoc.Doc, t: Float64, p: Particle): Int32 = match p#kind {
        case Kind.Muzzle(_) =>
            let flicker = Particles3dDoc.rec(doc)#muzzleFlicker;
            let start = Num.floorInt(Hash01.at(Num.floorInt(p#velocity#x * 7919.0 + p#velocity#y * 104729.0 + p#born * 997.0), 61) * Int32.toFloat64(muzzleFrames()));
            let steps = if (flicker <= 0.0) 0 else Num.floorInt(Float64.max(0.0, t - p#born) / flicker);
            Int32.modulo(start + steps, muzzleFrames())
        case Kind.Ichor => dropOf(p)
        case Kind.Gore  => dropOf(p)
        case _ => 0
    }

    /// 体液の粒の形の番号（粒ごとに散らす。寿命の間は替えない）。
    def dropOf(p: Particle): Int32 =
        Num.floorInt(Hash01.at(Num.floorInt(p#velocity#x * 7919.0 + p#velocity#z * 104729.0), 62) * 2.0)

    /// 置き場 space の生きている粒の Billboard3d。base = 置き場の座標 → 描く場面の座標の行列（Muzzle なら今の銃口の行列・World なら単位行列）。
    /// regionOf = 種類と形の番号 → アトラスのコマ（無ければその粒は描かない）。大きさは寿命の終わりに grow 倍へ変わり、横は aspect 倍。
    pub def billboards(doc: Particles3dDoc.Doc, texture: String, regionOf: (Kind, Int32) -> Option[Rect2.Rect2],
                       space: Space, base: Mat4.Mat4, t: Float64, ps: List[Particle]): List[Scene3d.Billboard3d] =
        ps |> List.filter(p -> p#space == space and isAlive(t, p)) |> List.filterMap(p ->
            regionOf(p#kind, frameAt(doc, t, p)) |> Option.map(rect -> {
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
    pub def textureKey(): String = "particles3d:v8"

    /// マズルフラッシュの形の数（左の列に縦に並ぶ。筋の長さと角をずらし、少しずつ回した形）。
    def muzzleFrames(): Int32 = 3

    def frameName(frame: Int32): String = match Int32.modulo(frame, muzzleFrames()) {
        case 0 => "a"
        case 1 => "b"
        case _ => "c"
    }

    /// 種類の frame 番目のコマ。マズルフラッシュは形の数・体液の粒は 2 つのコマがあり、ほかの種類は regionOf と同じ。
    pub def frameRegionOf(t: PxSpriteAtlas.Baked, kind: Kind, frame: Int32): Option[Rect2.Rect2] = match kind {
        case Kind.Muzzle(_) => PxSpriteAtlas.regionOf(t, "muzzle", frameName(frame))
        case Kind.Ichor     => PxSpriteAtlas.regionOf(t, "drop", if (frame == 0) "a" else "b")
        case Kind.Gore      => PxSpriteAtlas.regionOf(t, "drop", if (frame == 0) "a" else "b")
        case _              => regionOf(t, kind)
    }

    /// 種類のコマ（textureOf の中の矩形）。形で描く爆発の部分（BlastFx）はコマが無い（ビルボードにしない）。
    pub def regionOf(t: PxSpriteAtlas.Baked, kind: Kind): Option[Rect2.Rect2] = match kind {
        case Kind.Muzzle(_) => PxSpriteAtlas.regionOf(t, "muzzle", "a")
        case Kind.MuzzleSmoke => PxSpriteAtlas.regionOf(t, "smoke", "a")
        case Kind.Ichor     => PxSpriteAtlas.regionOf(t, "drop", "a")
        case Kind.Gore      => PxSpriteAtlas.regionOf(t, "drop", "a")
        case Kind.Smoke     => PxSpriteAtlas.regionOf(t, "smoke", "a")
        case Kind.Ring      => PxSpriteAtlas.regionOf(t, "ring", "a")
        case Kind.Blast(BlastPart.Smoke) => PxSpriteAtlas.regionOf(t, "smoke", "a")
        case Kind.Blast(BlastPart.Ring)     => None
        case Kind.Blast(BlastPart.Fireball) => None
        case Kind.Blast(BlastPart.Scorch)   => None
        case _              => PxSpriteAtlas.regionOf(t, "spark", "a")
    }

    /// 粒の絵 1 枚（左の列に上からマズルフラッシュの 3 つの形・右の列に上から火花・輪・煙・体液の粒の 2 つの形）。色は白から灰の濃淡だけで、粒の色は描く時に掛ける。
    /// 型の外は透明（ビルボードは α が半分未満の画素を捨てる）。読み込みで 1 回だけ作る。
    pub def textureOf(): PxSpriteAtlas.Baked =
        let side = muzzleSide() * muzzleFrames();
        let pixels = Vector.range(0, side * side) |> Vector.map(i -> {
            let (x, y) = (Int32.modulo(i, side), i / side);
            if (x < muzzleSide() and y < muzzleSide() * muzzleFrames()) streakMuzzlePixel(y / muzzleSide(), x, Int32.modulo(y, muzzleSide()))
            else if (x >= muzzleSide() and y < ringTop()) sparkPixel(x - muzzleSide(), y)
            else if (x >= muzzleSide() and y < smokeTop()) ringPixel(x - muzzleSide(), y - ringTop())
            else if (x >= muzzleSide() and y < smokeTop() + sparkSide()) smokePixel(x - muzzleSide(), y - smokeTop())
            else if (x >= muzzleSide() and y < dropTop() + sparkSide() * 2) dropPixel((y - dropTop()) / sparkSide(), x - muzzleSide(), Int32.modulo(y - dropTop(), sparkSide()))
            else 0
        });
        { side = side, pixels = pixels,
          regions = Map#{ ("muzzle", "a") => { x = 0, y = 0, w = muzzleSide(), h = muzzleSide() },
                          ("muzzle", "b") => { x = 0, y = muzzleSide(), w = muzzleSide(), h = muzzleSide() },
                          ("muzzle", "c") => { x = 0, y = muzzleSide() * 2, w = muzzleSide(), h = muzzleSide() },
                          ("spark", "a") => { x = muzzleSide(), y = 0, w = sparkSide(), h = sparkSide() },
                          ("ring", "a") => { x = muzzleSide(), y = ringTop(), w = sparkSide(), h = sparkSide() },
                          ("smoke", "a") => { x = muzzleSide(), y = smokeTop(), w = sparkSide(), h = sparkSide() },
                          ("drop", "a") => { x = muzzleSide(), y = dropTop(), w = sparkSide(), h = sparkSide() },
                          ("drop", "b") => { x = muzzleSide(), y = dropTop() + sparkSide(), w = sparkSide(), h = sparkSide() } } }

    /// 右の列の体液の粒の 2 つの形の左上の y（煙の下）。
    def dropTop(): Int32 = smokeTop() + sparkSide()

    /// 画素の真ん中の、型の中の座標（-1〜1）。
    def unitOf(n: Int32, x: Int32, y: Int32): (Float64, Float64) =
        let c = Int32.toFloat64(n) / 2.0;
        ((Int32.toFloat64(x) + 0.5 - c) / c, (Int32.toFloat64(y) + 0.5 - c) / c)

    /// 明るさ k（0〜1）の灰の不透明な画素。
    def greyOf(k: Float64): Int32 =
        let v = Num.roundInt(255.0 * Num.clamp01(k));
        Int32.bitwiseOr(Int32.bitwiseOr(-16777216, Int32.leftShift(v, 16)), Int32.bitwiseOr(Int32.leftShift(v, 8), v))

    /// マズルフラッシュ（frame 番目の形）: 小さな白い芯から、細い光の筋が 14 本放射状に開く（実写の銃口の光の写真のような、芯が強く筋が細い形）。
    /// 筋は 1 本ずつ長さと角をずらし、形ごとに全体を少し回す（数コマで形が変わり、少しずつ回って見える）。芯ほど明るく、筋の先へ暗くなる。
    // WhyNot: 太い 6 本の星にしない — 平たい切り絵の星に見えて漫画っぽい。筋を細く多くして、明るさはブルームでにじませる。
    def streakMuzzlePixel(frame: Int32, x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(muzzleSide(), x, y);
        let d = Num.sqrt(u * u + v * v);
        let a = Num.atan2(v, u);
        let turn = Int32.toFloat64(frame) * 0.21;
        let rays = 14;
        let ray = List.range(0, rays) |> List.foldLeft((best, k) -> {
            let key = frame * 31 + k;
            let length = 0.45 + 0.55 * Hash01.at(key, 63);
            let angle = Int32.toFloat64(k) * Num.tau() / Int32.toFloat64(rays) + turn + 0.18 * (Hash01.at(key, 64) - 0.5);
            let da = a - angle;
            let across = Float64.abs(Num.sin(da)) * d;
            let thick = 0.06 + 0.04 * Hash01.at(key, 65);
            let lit = Num.cos(da) > 0.0 and d <= length and across <= thick * (1.0 - d / length) + 0.012;
            if (lit) Float64.max(best, 1.0 - d / length) else best
        }, 0.0);
        let core = Num.clamp01(1.0 - d / 0.3);
        let k = Float64.max(core, ray * ray);
        if (k > 0.02) greyOf(0.2 + 0.8 * k) else 0

    /// 体液の粒（frame 番目の形）: 縁のちぎれた小さな滴。0 は少し細長い・1 は小さな欠片の 2 つ。
    def dropPixel(frame: Int32, x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(sparkSide(), x, y);
        let stretch = if (frame == 0) 1.6 else 1.0;
        let d = Num.sqrt(u * u * stretch * stretch + v * v);
        let n = valueNoise(10, 66 + frame, x, y);
        if (d <= 0.45 + 0.35 * n) greyOf(1.0 - 0.6 * d) else 0

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

    /// 格子 cell px ごとの値を、間でなめらかにつないだ濃淡（0..1）。
    def valueNoise(cell: Int32, salt: Int32, x: Int32, y: Int32): Float64 =
        let (gx, gy) = (x / cell, y / cell);
        let (fx, fy) = (Int32.toFloat64(Int32.modulo(x, cell)) / Int32.toFloat64(cell), Int32.toFloat64(Int32.modulo(y, cell)) / Int32.toFloat64(cell));
        let ease = (u: Float64) -> u * u * (3.0 - 2.0 * u);
        let at = (i: Int32, j: Int32) -> Hash01.at(i * 131 + j, salt);
        let top = Num.lerp(at(gx, gy), at(gx + 1, gy), ease(fx));
        let bottom = Num.lerp(at(gx, gy + 1), at(gx + 1, gy + 1), ease(fx));
        Num.lerp(top, bottom, ease(fy))

    /// 煙: 縁がふくらみでちぎれた丸い塊。中は大小 2 つのなめらかな濃淡で、真ん中ほど明るい。
    // WhyNot: 升ごとに値を変えるだけにしない — 爆発の煙は 2 m を超えて広がり、升の段がモザイクに見える。
    def smokePixel(x: Int32, y: Int32): Int32 =
        let (u, v) = unitOf(sparkSide(), x, y);
        let d = Num.sqrt(u * u + v * v);
        let n = 0.65 * valueNoise(16, 91, x, y) + 0.35 * valueNoise(6, 92, x, y);
        if (d <= 0.55 + 0.5 * n) greyOf(0.5 + 0.5 * n * (1.0 - 0.6 * d)) else 0
}
