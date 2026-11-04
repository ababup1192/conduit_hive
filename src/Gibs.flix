// Gibs — 敵が弾ける（gib）: 弾けるかの条件・肉片（assets/models/gibs.glb の GIB_0〜GIB_7）を撃たれた向きへ飛ばし、回しながら床で跳ねさせ、
// 少し残してから縮めて消す・弾けた瞬間の点光源（読み込みのほかは純粋）。値は JuiceDoc の gib。
// 肉片は 1 つの glb の部品（1 つ 1 draw call）なので、同時に残す数は limit で止め、越えたら古い物から消す。
// 壁を抜けないかは呼ぶ側が渡す線の見通し（Collider.isLineClear）で見る。
mod Gibs {
    use fge::{Gltf, Hash01, LoadProgress, Log, Mat4, Mesh3d, Model3d, Num, Scene3d, Texture3d, Vec3}

    /// 肉片 1 つ。part = GIB_<番号>・回る軸（長さ 1）と今の角（ラジアン）と回る速さ（ラジアン/秒）・born = 弾けた時刻・radius = 床に着く高さ。
    pub type alias Piece = { part = Int32, at = Vec3.Vec3, velocity = Vec3.Vec3, axis = Vec3.Vec3, angle = Float64, spin = Float64,
                             born = Float64, radius = Float64 }

    /// 弾けた所（点光源を点ける）。
    pub type alias Pop = { at = Float64, point = Vec3.Vec3 }

    /// 飛んでいる・残っている肉片と、最近弾けた所（どちらも新しい物が前）。
    pub type alias State = { pieces = List[Piece], pops = List[Pop] }

    /// 肉片 1 種類の形（glb の部品）と材質と床に着く高さ。
    type alias Shape = { mesh = Mesh3d.Mesh3d, material = Option[Scene3d.Material3d], radius = Float64 }

    /// 肉片の形の束（GIB_<番号> の順。読めなかった番号は無い）と、材質が読む絵。
    pub type alias Art = { shapes = Map[Int32, Shape], textures = List[Texture3d.Texture3d] }

    /// 弾けるかを決める値: 武器・撃った点からの距離・1 発で頭に受けた威力・倒れた時に体力を超えた分。
    pub type alias Cause = { weapon = WeaponsDoc.Weapon, distance = Float64, headDamage = Float64, overkill = Float64 }

    pub def empty(): State = { pieces = Nil, pops = Nil }

    def path(): String = "assets/models/gibs.glb"

    def parts(): Int32 = 8

    /// glb を絵つきで読む（読めなければ理由を 1 行出して None。弾けても肉片は出ず、体液と光だけになる）。
    pub def load(): Option[Model3d.Model3d] \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        LoadProgress.report("reading gibs...", 0, 0);
        match Fs.FileRead.readBytes(path()) |> Result.mapErr(e -> "読めない（${e}）")
                |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, Gltf.noTextureLimits(), b)) {
            case Ok(m)    => Some(m)
            case Err(why) => Log.warnThen("[gibs] ${path()}: ${why}", None)
        }

    /// 読んだ glb から肉片の形の束（ノード GIB_<番号> の部品 1 つ。原点が重心）。
    pub def artOf(model: Option[Model3d.Model3d]): Art = match model {
        case None    => { shapes = Map.empty(), textures = Nil }
        case Some(m) =>
            let shapes = List.range(0, parts()) |> List.filterMap(i ->
                Model3d.findNode("GIB_${i}", m) |> Option.flatMap(node -> List.head(Model3d.partsOfNode(node, m)))
                    |> Option.map(part -> {
                        let b = Mesh3d.bounds(part#mesh);
                        let half = Float64.min(b#max#y - b#min#y, Float64.min(b#max#x - b#min#x, b#max#z - b#min#z)) * 0.5;
                        (i, { mesh = part#mesh, material = part#material, radius = Float64.max(0.02, half) })
                    }));
            { shapes = List.toMap(shapes), textures = m#textures }
    }

    // ── 弾けるか ──

    /// 弾けるか: 散弾銃の近距離・頭への強い一撃・余剰ダメージのどれかの条件に当たり、その条件の確率に roll（0..1）が入る。
    pub def bursts(g: JuiceDoc.Gib, c: Cause, roll: Float64): Bool =
        (c#weapon == WeaponsDoc.Weapon.Shotgun and c#distance <= g#shotgunRange and roll < g#shotgunChance)
            or (c#headDamage >= g#headDamage and roll < g#headChance)
            or (c#overkill >= g#overkill and roll < g#overkillChance)

    // ── 飛ばす ──

    /// 肉片の種類の重み（GIB_0 から順。小さな肉片と骨の欠片を多めに、腕と光る管を少なめに）。
    // WhyNot: Doc へ出さない — glb の部品の並びと 1 対 1 で、部品を作り直す時に一緒に直す物。
    def weights(): List[Float64] = 1.0 :: 2.0 :: 2.0 :: 2.0 :: 1.0 :: 3.0 :: 2.0 :: 4.0 :: Nil

    /// 0..1 の u を重みで GIB の番号へ。
    def pickPart(u: Float64): Int32 =
        let total = List.foldLeft((a, b) -> a + b, 0.0, weights());
        let (picked, _) = weights() |> List.zipWithIndex |> List.foldLeft((acc, e) -> {
            let (found, left) = acc;
            let (i, w) = e;
            if (Option.nonEmpty(found)) acc else if (left < w) (Some(i), left) else (None, left - w)
        }, (None, u * total));
        picked |> Option.getWithDefault(parts() - 1)

    /// 長さ 1 のでたらめな向き（seed と k で決まる）。
    def unitOf(seed: Int32, k: Int32): Vec3.Vec3 =
        let y = Hash01.at(seed, k) * 2.0 - 1.0;
        let a = Hash01.at(seed, k + 1) * Num.tau();
        let r = Num.sqrt(Float64.max(0.0, 1.0 - y * y));
        Vec3.v3(r * Num.cos(a), y, r * Num.sin(a))

    /// 時刻 t に、点 center（体の真ん中）で、撃たれた向き (dx, dz) へ弾ける。seed が同じなら同じ肉片が出る。
    /// 肉片は countMin〜countMax 個で、上限を越えたら古い物から消す。
    pub def burst(g: JuiceDoc.Gib, art: Art, t: Float64, seed: Int32, center: Vec3.Vec3, dx: Float64, dz: Float64, s: State): State =
        let span = Int32.max(0, g#countMax - g#countMin);
        let count = g#countMin + Int32.min(span, Num.floorInt(Hash01.at(seed, 61) * Int32.toFloat64(span + 1)));
        let fresh = List.range(0, Int32.max(0, count)) |> List.map(i -> {
            let key = seed * 31 + i;
            let part = pickPart(Hash01.at(key, 62));
            let out = Vec3.mul(unitOf(key, 63), g#scatter * (0.4 + 0.6 * Hash01.at(key, 65)));
            let push = g#speed * (0.6 + 0.6 * Hash01.at(key, 66));
            let velocity = Vec3.add(out, Vec3.v3(dx * push, g#lift * (0.5 + 0.7 * Hash01.at(key, 67)), dz * push));
            let jitter = Vec3.mul(unitOf(key, 68), 0.25);
            { part = part, at = Vec3.add(center, jitter), velocity = velocity, axis = unitOf(key, 70),
              angle = Hash01.at(key, 72) * Num.tau(), spin = g#spin * Num.pi() / 180.0 * (0.5 + 0.5 * Hash01.at(key, 73)), born = t,
              radius = g#scale * (Map.get(part, art#shapes) |> Option.map(sh -> sh#radius) |> Option.getWithDefault(0.05)) }
        });
        { pieces = List.take(Int32.max(0, g#limit), List.append(fresh, s#pieces)), pops = { at = t, point = center } :: s#pops }

    // ── 1 コマ ──

    /// 時刻 t（このコマは dt 秒）に肉片を動かす: 下へ引き、床（高さ = 肉片の radius）で跳ね（縦は bounce・横と回る速さは friction の割合を残す）、
    /// 縦の速さが小さくなったら床に寝かせて 0.1 秒ごとに friction の割合まで滑りを減らす。壁に当たれば横の速さを返して減らす。
    /// 残る長さを過ぎた肉片と、光の長さを過ぎた弾けた所を消す。
    pub def step(g: JuiceDoc.Gib, isClear: (Vec3.Vec3, Vec3.Vec3) -> Bool, t: Float64, dt: Float64, s: State): State =
        { pieces = s#pieces |> List.filter(p -> t - p#born < g#life) |> List.map(move(g, isClear, dt)),
          pops = s#pops |> List.filter(p -> t - p#at < g#lightSeconds) }

    def move(g: JuiceDoc.Gib, isClear: (Vec3.Vec3, Vec3.Vec3) -> Bool, dt: Float64, p: Piece): Piece =
        let resting = p#at#y <= p#radius + 0.0001 and p#velocity#y == 0.0;
        let vy = if (resting) 0.0 else p#velocity#y - g#gravity * dt;
        let slide = if (resting) Float64.pow(base = Num.clamp01(g#friction), dt / 0.1) else 1.0;
        let v0 = Vec3.v3(p#velocity#x * slide, vy, p#velocity#z * slide);
        let next = Vec3.add(p#at, Vec3.mul(v0, dt));
        let hits = next#y <= p#radius and vy < 0.0;
        let bounced = if (not hits) v0
            else {
                let up = 0.0 - vy * g#bounce;
                let keep = g#friction;
                Vec3.v3(v0#x * keep, if (up < 0.6) 0.0 else up, v0#z * keep)
            };
        let landed = { y = Float64.max(p#radius, next#y) | next };
        let h = Num.sqrt(bounced#x * bounced#x + bounced#z * bounced#z);
        let ahead = if (h <= 0.0) landed else Vec3.add(landed, Vec3.v3(bounced#x / h * p#radius, 0.0, bounced#z / h * p#radius));
        let lift = (v: Vec3.Vec3) -> { y = Float64.max(0.1, v#y) | v };
        let walled = h > 0.0 and not isClear(lift(p#at), lift(ahead));
        let spin = if (hits) p#spin * g#friction else p#spin * slide;
        if (walled) { at = { y = landed#y | p#at }, velocity = Vec3.v3(0.0 - bounced#x * 0.3, bounced#y, 0.0 - bounced#z * 0.3), angle = p#angle + spin * dt, spin = spin | p }
        else { at = landed, velocity = bounced, angle = p#angle + spin * dt, spin = spin | p }

    // ── 描く ──

    /// 軸 k（長さ 1）のまわりに a（ラジアン）回す行列。
    def rotationAbout(k: Vec3.Vec3, a: Float64): Mat4.Mat4 =
        let (c, s) = (Num.cos(a), Num.sin(a));
        let t = 1.0 - c;
        Mat4.ofLinearRows(
            Vec3.v3(c + k#x * k#x * t, k#x * k#y * t - k#z * s, k#x * k#z * t + k#y * s),
            Vec3.v3(k#y * k#x * t + k#z * s, c + k#y * k#y * t, k#y * k#z * t - k#x * s),
            Vec3.v3(k#z * k#x * t - k#y * s, k#z * k#y * t + k#x * s, c + k#z * k#z * t))

    /// 時刻 t の肉片の置いた物（glb の大きさの scale 倍・発光の筋は glb の強さの glow 倍・残る長さの終わりの fade 秒で縮んで消える）。
    pub def instancesOf(g: JuiceDoc.Gib, art: Art, t: Float64, s: State): List[Scene3d.Instance3d] =
        s#pieces |> List.filterMap(p -> Map.get(p#part, art#shapes) |> Option.map(shape -> {
            let left = g#life - (t - p#born);
            let k = g#scale * (if (g#fade <= 0.0) 1.0 else Num.clamp01(left / g#fade));
            let world = Mat4.mul(Mat4.translate(p#at), Mat4.mul(rotationAbout(p#axis, p#angle), Mat4.scale(Vec3.v3(k, k, k))));
            let placed = Scene3d.meshInstance(shape#mesh, world) |> Scene3d.withName("gib:${p#part}");
            match shape#material {
                case Some(m) => Scene3d.withMaterial(Scene3d.withEmissionIntensity(Scene3d.materialFieldsOf(m)#emissionIntensity * g#glow, m), placed)
                case None    => placed
            }
        }))

    /// 時刻 t の弾けた瞬間の点光源（新しい方から lights 本・lightSeconds の間に消えていく）。
    pub def lightsOf(g: JuiceDoc.Gib, t: Float64, s: State): List[Scene3d.PointLight] =
        s#pops |> List.filter(p -> t >= p#at and t - p#at < g#lightSeconds) |> List.take(Int32.max(0, g#lights)) |> List.map(p -> {
            let k = 1.0 - (t - p#at) / Float64.max(0.001, g#lightSeconds);
            { position = p#point, color = g#lightColor, intensity = g#lightIntensity * k, range = g#lightRange }
        })
}
