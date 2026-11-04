// Grenades — 手榴弾: 持っている数・投げる・放物線で飛んで壁と床と天井で跳ねる・信管で爆発する・爆発の傷の量・爆発の光・描く形（読み込みのほかは純粋）。
// 値は GrenadeDoc。爆発で敵を倒すのは Horde.blast、自分の傷・粒・揺れ・hit stop は World。
// 形は assets/models/grenade.glb（骨なし・原点は重心・筒の軸は +Y）。投げた向きへ縦に回りながら飛ぶ。
//
// 飛び方: 1 コマごとに、下へ引く強さの下での放物線をそのまま進める（コマの長さで軌跡が変わらない）。
// 床（y = 0 の面）と区画の天井は高さで、壁と立てた物は当たり判定の箱へ水平のレイを当てて跳ねる。
// 跳ねると面に向かう速さは bounce・面に沿う速さは friction の割合が残る。床で止まりかけたら転がって止まる。
mod Grenades {
    use fge::{CollisionWorld3d, Gltf, Hash01, LoadProgress, Log, Mat4, Model3d, Num, Scene3d, Vec3}

    /// 飛んでいる手榴弾: 番号・玉の真ん中・速さ（m/秒）・投げた時刻・回る角（ラジアン）と速さ（ラジアン/秒）・回る面の向き（ラジアン。投げた向き）。
    pub type alias Grenade = { id = Int32, at = Vec3.Vec3, velocity = Vec3.Vec3, born = Float64, angle = Float64, spin = Float64, heading = Float64 }

    /// 爆発した所（光と見た目）: 時刻・点。
    pub type alias Pop = { at = Float64, point = Vec3.Vec3 }

    /// 手榴弾の状態: 持っている数・飛んでいる物・次に投げられる時刻・次の番号・最近の爆発（新しい物が前）。
    pub type alias State = { carried = Int32, flying = List[Grenade], readyAt = Float64, nextId = Int32, pops = List[Pop] }

    /// 爆発 1 つ: 手榴弾の番号（粒と肉片の種）・点。
    pub type alias Blast = { id = Int32, point = Vec3.Vec3 }

    /// 1 コマの結果: 次の状態・強く跳ねた数（音を鳴らす）・このコマに爆発した物。
    pub type alias Step = { state = State, bounces = Int32, blasts = List[Blast] }

    /// 飛ぶ周り: 当たり判定の箱と、点の上の天井の高さ（迷路の外は高さを問わない）。
    pub type alias Room = { collision = CollisionWorld3d.CollisionWorld3d, ceilingAt = (Float64, Float64) -> Float64 }

    /// 遊び始め（持っている数は start。max で止める）。
    pub def initial(g: GrenadeDoc.Rec): State =
        { carried = Int32.max(0, Int32.min(g#carry#max, g#carry#start)), flying = Nil, readyAt = 0.0, nextId = 0, pops = Nil }

    /// 持っている数を amount 足す（max で止める）。もう上限・足す量が 0 以下なら None（拾わない）。
    pub def add(g: GrenadeDoc.Rec, amount: Int32, s: State): Option[State] =
        if (amount <= 0 or s#carried >= g#carry#max) None else Some({ carried = Int32.min(g#carry#max, s#carried + amount) | s })

    /// 持っている数を n より下げない（紹介の動画の自動の操縦だけが使う）。
    pub def atLeast(n: Int32, s: State): State = { carried = Int32.max(n, s#carried) | s }

    /// 時刻 t に投げられるか（持っていて、前に投げてから cooldown が過ぎた）。
    pub def canThrow(t: Float64, s: State): Bool = s#carried > 0 and t >= s#readyAt

    /// 時刻 t に、点 origin から照準の向き forward（長さ 1）へ投げる（投げられなければ None）。速さは照準の向きへ speed に、上へ lift を足す。
    pub def toss(g: GrenadeDoc.Rec, t: Float64, origin: Vec3.Vec3, forward: Vec3.Vec3, s: State): Option[State] =
        if (not canThrow(t, s)) None
        else {
            let th = g#throwing;
            let velocity = Vec3.add(Vec3.mul(forward, th#speed), Vec3.v3(0.0, th#lift, 0.0));
            let spin = th#spin * Num.pi() / 180.0 * (0.8 + 0.4 * Hash01.at(s#nextId, 31));
            let fresh = { id = s#nextId, at = origin, velocity = velocity, born = t, angle = 0.0, spin = spin, heading = Num.atan2(forward#x, forward#z) };
            Some({ carried = s#carried - 1, flying = List.append(s#flying, fresh :: Nil), readyAt = t + th#cooldown, nextId = s#nextId + 1 | s })
        }

    // ── 飛ぶ ──

    /// 時刻 t（このコマは dt 秒）に飛ばす: 信管が尽きた物は爆発して列から外れ、光の長さを過ぎた爆発を消す。
    pub def step(g: GrenadeDoc.Rec, room: Room, t: Float64, dt: Float64, s: State): Step =
        let (due, flying) = s#flying |> List.partition(x -> t - x#born >= g#flight#fuse);
        let moved = flying |> List.map(move(g#flight, room, dt));
        let blasts = due |> List.map(x -> { id = x#id, point = x#at });
        let pops = List.append(blasts |> List.map(b -> { at = t, point = b#point }), s#pops |> List.filter(p -> t - p#at < g#light#seconds));
        { state = { flying = moved |> List.map(fst), pops = pops | s }, bounces = moved |> List.count(snd), blasts = blasts }

    /// 時刻 start の次のコマから、同じ刻み dt で n コマ飛ばした状態（爆発した物は列から外れる）。
    pub def simulate(g: GrenadeDoc.Rec, room: Room, start: Float64, dt: Float64, n: Int32, s: State): State =
        List.range(1, n + 1) |> List.foldLeft((acc, i) -> step(g, room, start + Int32.toFloat64(i) * dt, dt, acc)#state, s)

    /// 跳ねた音を鳴らす、面に向かう速さの下限（m/秒）。
    // WhyNot: Doc へ出さない — 床で転がる間の小さな当たりを数えないための閾で、調整する手触りではない。
    def audibleImpact(): Float64 = 1.5

    /// 床に止まったとみなす縦の速さ（m/秒。これより弱く床で跳ねたら床に寝かせる）。
    def settleSpeed(): Float64 = 0.8

    /// 1 つを 1 コマ進める（と、強く跳ねたか）。
    def move(f: GrenadeDoc.Flight, room: Room, dt: Float64, x: Grenade): (Grenade, Bool) =
        let r = f#radius;
        let resting = x#at#y <= r + 0.0001 and x#velocity#y == 0.0;
        let gravity = if (resting) 0.0 else f#gravity;
        let roll = if (resting) Float64.pow(base = Num.clamp01(f#friction), dt / 0.1) else 1.0;
        let v0 = Vec3.v3(x#velocity#x * roll, x#velocity#y, x#velocity#z * roll);
        let ballistic = Vec3.add(x#at, Vec3.v3(v0#x * dt, v0#y * dt - 0.5 * gravity * dt * dt, v0#z * dt));
        let v1 = Vec3.v3(v0#x, v0#y - gravity * dt, v0#z);
        let (walled, vw, wallHit) = offWalls(f, room, x#at, ballistic, v1);
        let ceiling = room#ceilingAt(walled#x, walled#z) - r;
        let (capped, vc, roofHit) = if (walled#y > ceiling and vw#y > 0.0) ({ y = ceiling | walled }, Vec3.v3(vw#x * f#friction, 0.0 - vw#y * f#bounce, vw#z * f#friction), vw#y)
                                   else (walled, vw, 0.0);
        let (landed, vf, floorHit) = onFloor(f, capped, vc);
        let spin = if (wallHit > 0.0 or floorHit > 0.0) x#spin * f#friction else x#spin;
        let loud = Float64.max(wallHit, Float64.max(roofHit, floorHit)) >= audibleImpact();
        ({ at = landed, velocity = vf, angle = x#angle + spin * dt, spin = spin | x }, loud)

    /// 床（y = 半径）より下へ進んだら床の上へ戻して跳ねさせる（弱ければ床に寝かせる）。床に向かっていた速さも返す（跳ねなければ 0）。
    def onFloor(f: GrenadeDoc.Flight, at: Vec3.Vec3, v: Vec3.Vec3): (Vec3.Vec3, Vec3.Vec3, Float64) =
        if (at#y > f#radius or v#y > 0.0) (at, v, 0.0)
        else {
            let up = 0.0 - v#y * f#bounce;
            let keep = if (v#y < 0.0) f#friction else 1.0;
            ({ y = f#radius | at }, Vec3.v3(v#x * keep, if (up < settleSpeed()) 0.0 else up, v#z * keep), 0.0 - v#y)
        }

    /// 水平に進む間に壁か立てた物の箱へ当たれば、当たった面の手前（半径だけ離す）へ戻して跳ねさせる。面に向かっていた速さも返す（当たらなければ 0）。
    def offWalls(f: GrenadeDoc.Flight, room: Room, origin: Vec3.Vec3, to: Vec3.Vec3, v: Vec3.Vec3): (Vec3.Vec3, Vec3.Vec3, Float64) =
        let height = Float64.max(f#radius + 0.02, to#y);
        let (dx, dz) = (to#x - origin#x, to#z - origin#z);
        let flat = Num.sqrt(dx * dx + dz * dz);
        let ahead = Vec3.v3(to#x + dx / Float64.max(0.0001, flat) * f#radius, height, to#z + dz / Float64.max(0.0001, flat) * f#radius);
        let hit = if (flat <= 0.0) None else Collider.firstHit(room#collision, Vec3.v3(origin#x, height, origin#z), ahead);
        match hit {
            case None    => (to, v, 0.0)
            case Some(h) =>
                let n = Vec3.v3(h#normal#x, 0.0, h#normal#z);
                let inward = Vec3.dot(v, n);
                let along = Vec3.sub(v, Vec3.mul(n, inward));
                let bounced = Vec3.sub(Vec3.mul(along, f#friction), Vec3.mul(n, inward * f#bounce));
                let back = Vec3.add(Vec3.v3(h#point#x, to#y, h#point#z), Vec3.mul(n, f#radius));
                (back, if (inward < 0.0) bounced else v, Float64.abs(inward))
        }

    // ── 爆発の傷 ──

    /// 爆発の点から d m の敵が受ける傷（真ん中で damage・半径の縁で edgeDamage・その間はなめらかにつなぐ・半径の外は 0）。
    pub def damageAt(b: GrenadeDoc.Blast, d: Float64): Float64 =
        if (d > b#radius) 0.0 else b#damage + (b#edgeDamage - b#damage) * Num.clamp01(d / Float64.max(0.001, b#radius))

    /// 爆発の点から d m の自分が受ける傷（真ん中で selfDamage・selfRadius で 0）。
    pub def selfDamageAt(b: GrenadeDoc.Blast, d: Float64): Float64 =
        if (d >= b#selfRadius) 0.0 else b#selfDamage * (1.0 - Num.clamp01(d / Float64.max(0.001, b#selfRadius)))

    // ── 読み込みと描く ──

    def path(): String = "assets/models/grenade.glb"

    /// glb を絵つきで読む（読めなければ理由を 1 行出して None。投げた手榴弾は見えないが、飛んで爆発する）。
    pub def load(): Option[Model3d.Model3d] \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        LoadProgress.report("reading grenade...", 0, 0);
        match Fs.FileRead.readBytes(path()) |> Result.mapErr(e -> "読めない（${e}）")
                |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, Gltf.noTextureLimits(), b)) {
            case Ok(m)    => Some(m)
            case Err(why) => Log.warnThen("[grenade] ${path()}: ${why}", None)
        }

    /// 飛んでいる手榴弾の置いた物（glb の大きさの scale 倍・投げた向きの縦の面で回る）。
    pub def instancesOf(f: GrenadeDoc.Flight, model: Option[Model3d.Model3d], s: State): List[Scene3d.Instance3d] =
        model |> Option.toList |> List.flatMap(m -> s#flying |> List.flatMap(x -> {
            let k = f#scale;
            let world = Mat4.mul(Mat4.translate(x#at), Mat4.mul(Mat4.rotateY(x#heading), Mat4.mul(Mat4.rotateX(x#angle), Mat4.scale(Vec3.v3(k, k, k)))));
            Model3d.partInstances(world, m)
        }))

    /// 時刻 t の爆発の瞬間の点光源（光の長さの間に 2 乗で消えていく・床から少し上）。
    pub def lightsOf(l: GrenadeDoc.Light, t: Float64, s: State): List[Scene3d.PointLight] =
        s#pops |> List.filter(p -> t >= p#at and t - p#at < l#seconds) |> List.map(p -> {
            let k = 1.0 - (t - p#at) / Float64.max(0.001, l#seconds);
            { position = Vec3.add(p#point, Vec3.v3(0.0, 0.6, 0.0)), color = l#color, intensity = l#intensity * k * k, range = l#range }
        })
}
