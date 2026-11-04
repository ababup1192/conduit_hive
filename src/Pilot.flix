// Pilot — 紹介の動画で、決めた道筋（TourDoc）を歩いて撃つ自動の操縦（純粋）。`start tour` で始めた時だけ動く。
//
// 毎コマ: 見通しのある近い敵を 1 体選んで狙い（選んだ敵は倒れるか見えなくなるまで替えない）→ 向きを狙いへなめらかに寄せる
// → 次の点へ歩く（向きと歩く向きは別。狙いながら横や後ろへも歩く）→ 狙いのずれが fireCone の内なら引き金を引く → 敵との距離で武器を選ぶ。
// 出すのはキーとマウスと同じ入力（Command = World.Input と同じ形）なので、当たり判定・弾・拾う・音は手で遊ぶ時と同じ規則を通る。
mod Pilot {
    use fge::{Num, Vec3}
    use WeaponsDoc.Weapon

    /// 何番目の点へ向かっているか・着いたか・その点で待った秒・その点へ向かい始めてからの秒・狙っている敵の id・
    /// 最後に持ち替えた時刻・向きを変えている速さ（ラジアン/秒。yaw と pitch）。
    pub type alias State = { index = Int32, arrived = Bool, waited = Float64, heading = Float64, target = Option[Int32],
                             switchedAt = Float64, yawSpeed = Float64, pitchSpeed = Float64 }

    /// このコマに見る物: 遊びの時計の今と刻み（秒）・体・武器・群れ。
    pub type alias Situation = { t = Float64, dt = Float64, walker = Walker.Walker, arsenal = Arsenal.Arsenal, horde = Horde.Horde }

    /// このコマの入力（World.Input と同じ形）。
    pub type alias Command = { drive = Walker.Drive, trigger = Arsenal.Trigger, choice = Arsenal.Choice }

    /// 狙っている敵: id・狙う点・目からの水平の距離（m）。
    type alias Aim = { id = Int32, point = Vec3.Vec3, distance = Float64 }

    pub def start(): State =
        { index = 0, arrived = false, waited = 0.0, heading = 0.0, target = None, switchedAt = -100.0, yawSpeed = 0.0, pitchSpeed = 0.0 }

    /// 向かっている点の名前（歩き終えたら空）。
    pub def pointName(tour: TourDoc.Rec, s: State): String =
        List.nth(s#index, tour#points) |> Option.map(p -> p#name) |> Option.getWithDefault("")

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    def deg(r: Float64): Float64 = r * 180.0 / Num.pi()

    /// 角を -π..π へ。
    def wrapAngle(a: Float64): Float64 =
        let turn = 2.0 * Num.pi();
        a - turn * Float64.floor((a + Num.pi()) / turn)

    /// 1 コマの入力と次の状態。
    pub def drive(res: Res.Res, at: Situation, s: State): (Command, State) =
        let tour = TourDoc.rec(res#tour);
        let eye = Walker.eyeOf(WalkDoc.rec(res#walk), at#walker);
        let aim = pickAim(res, tour, eye, at, s#target);
        let point = List.nth(s#index, tour#points);
        let walked = walkOf(tour, at, aim, point, s);
        let (wantYaw, wantPitch) = lookOf(eye, at#walker, aim, point, walked);
        let turned = turnToward(tour, at, wantYaw, wantPitch, walked#state);
        let (forward, strafe) = relativeOf(at#walker#yaw, walked#direction);
        let fire = aim |> Option.exists(a -> isAligned(tour, wantYaw - at#walker#yaw, wantPitch - at#walker#pitch)
                                             and a#distance <= Arsenal.statsOf(res#weapons, at#arsenal)#range);
        let (choice, switched) = choiceOf(res, tour, at, aim, point, turned#state);
        ({ drive = { forward = forward, strafe = strafe, turnDeg = deg(turned#yaw), lookDeg = deg(turned#pitch),
                     turnRate = 0.0, sprint = walked#sprint },
           trigger = { pressed = fire, held = fire }, choice = choice },
         { target = aim |> Option.map(a -> a#id) | switched })

    // ── 狙う敵 ──

    /// 前のコマに狙っていた敵がまだ狙えればそのまま、でなければ見通しのある一番近い敵。
    /// ranged は rangedAimRange まで狙う（melee より遠くから吐くので、aimRange だけでは撃ち返さずに吐かれ続ける）。
    def pickAim(res: Res.Res, tour: TourDoc.Rec, eye: Vec3.Vec3, at: Situation, previous: Option[Int32]): Option[Aim] =
        let reach = e -> match e#kind {
            case Creatures.Kind.Melee  => tour#aimRange
            case Creatures.Kind.Ranged => tour#rangedAimRange
        };
        let candidates = Horde.aliveEnemies(at#horde) |> List.filter(e -> distanceTo(eye, e) <= reach(e)) |> List.map(e -> aimOf(tour, eye, at#walker, e));
        let visible = a -> Collider.isLineClear(res#collision, eye, a#point);
        let kept = previous |> Option.flatMap(id -> candidates |> List.find(a -> a#id == id)) |> Option.filter(visible);
        kept |> Option.withDefault(default = candidates |> List.sortBy(a -> a#distance) |> List.find(visible))

    /// 目から敵の足元までの水平の距離（m）。
    def distanceTo(eye: Vec3.Vec3, e: Horde.Enemy): Float64 = Num.sqrt((e#x - eye#x) * (e#x - eye#x) + (e#z - eye#z) * (e#z - eye#z))

    def aimOf(tour: TourDoc.Rec, eye: Vec3.Vec3, walker: Walker.Walker, e: Horde.Enemy): Aim =
        let point = Vec3.v3(e#x, walker#feet + tour#aimHeight, e#z);
        { id = e#id, point = point, distance = distanceTo(eye, e) }

    // ── 歩く ──

    /// 歩く向き（水平・長さ 0..1）・走るか・次の状態。
    type alias Walk = { direction = (Float64, Float64), sprint = Bool, state = State }

    /// 点へ歩く・着いたら待つ・待ち終えたら次の点へ（clear の点は狙える敵がいる間は進まない）。
    def walkOf(tour: TourDoc.Rec, at: Situation, aim: Option[Aim], point: Option[TourDoc.Point], s: State): Walk =
        let still = { direction = (0.0, 0.0), sprint = false, state = s };
        point |> Option.map(p -> {
            let dx = p#x - at#walker#x;
            let dz = p#z - at#walker#z;
            let distance = Num.sqrt(dx * dx + dz * dz);
            let arrived = s#arrived or distance <= tour#arriveRadius;
            let waited = if (arrived) s#waited + at#dt else s#waited;
            let busy = p#clear and Option.nonEmpty(aim);
            let leave = (arrived and waited >= p#wait and not busy) or (not arrived and s#heading >= tour#giveUpSeconds);
            let pace = Num.clamp01(distance / 1.5);
            if (leave) { state = { index = s#index + 1, arrived = false, waited = 0.0, heading = 0.0 | s } | still }
            else if (arrived) { state = { arrived = true, waited = waited | s } | still }
            else { direction = (dx / distance * pace, dz / distance * pace), sprint = p#sprint and Option.isEmpty(aim),
                   state = { heading = s#heading + at#dt | s } }
        }) |> Option.getWithDefault(still)

    /// 体の向き yaw に対して、水平の向き direction を前と右へ分ける（Walker.heading の逆）。
    def relativeOf(yaw: Float64, direction: (Float64, Float64)): (Float64, Float64) =
        let (dx, dz) = direction;
        let (s, c) = (Num.sin(yaw), Num.cos(yaw));
        (dx * s + dz * c, dx * c - dz * s)

    // ── 向く ──

    /// 向きたい yaw と pitch（ラジアン。pitch は正で下）: 敵がいればその狙う点・歩いていれば歩く向き・待つ間は点の lookYaw。
    def lookOf(eye: Vec3.Vec3, walker: Walker.Walker, aim: Option[Aim], point: Option[TourDoc.Point], walked: Walk): (Float64, Float64) =
        let (dx, dz) = walked#direction;
        let moving = dx * dx + dz * dz > 0.01;
        let waiting = point |> Option.flatMap(p -> p#lookYaw) |> Option.map(y -> (rad(y), 0.0));
        let toward = if (moving) Some((Num.atan2(dx, dz), 0.0)) else waiting;
        aim |> Option.map(a -> (Num.atan2(a#point#x - eye#x, a#point#z - eye#z), Num.atan2(eye#y - a#point#y, Float64.max(0.1, a#distance))))
            |> Option.withDefault(default = toward)
            |> Option.getWithDefault((walker#yaw, 0.0))

    /// このコマに回す角（ラジアン）と次の状態: ずれを lookEase 秒で消す速さを turnRate で切り、その速さへ turnSmooth 秒でなじませる。
    def turnToward(tour: TourDoc.Rec, at: Situation, wantYaw: Float64, wantPitch: Float64, s: State): { yaw = Float64, pitch = Float64, state = State } =
        let limit = rad(tour#turnRate);
        let blend = if (tour#turnSmooth <= 0.0) 1.0 else 1.0 - Float64.exp(0.0 - at#dt / tour#turnSmooth);
        let speedOf = (error, previous) -> {
            let wanted = Num.clamp(0.0 - limit, limit, error / Float64.max(0.01, tour#lookEase));
            previous + (wanted - previous) * blend
        };
        let yawSpeed = speedOf(wrapAngle(wantYaw - at#walker#yaw), s#yawSpeed);
        let pitchSpeed = speedOf(wantPitch - at#walker#pitch, s#pitchSpeed);
        { yaw = yawSpeed * at#dt, pitch = pitchSpeed * at#dt, state = { yawSpeed = yawSpeed, pitchSpeed = pitchSpeed | s } }

    /// 狙いのずれ（ラジアン）が fireCone の内か（上下は倍まで許す。敵の背は高い）。
    def isAligned(tour: TourDoc.Rec, yawError: Float64, pitchError: Float64): Bool =
        Float64.abs(deg(wrapAngle(yawError))) <= tour#fireCone and Float64.abs(deg(pitchError)) <= tour#fireCone * 2.0

    // ── 武器 ──

    /// 持ち替えの指示と次の状態: 点が武器を決めていればそれ、決めていなければ狙う敵が近いと散弾銃・遠いと連射銃（無ければ散弾銃・拳銃）。
    /// 狙う敵がいない間と、持ち替えてから switchHold 秒の間は替えない。
    def choiceOf(res: Res.Res, tour: TourDoc.Rec, at: Situation, aim: Option[Aim], point: Option[TourDoc.Point], s: State): (Arsenal.Choice, State) =
        let usable = w -> Arsenal.isUsable(res#weapons, w, at#arsenal);
        let byDistance = d -> (if (d <= tour#shotgunRange) Weapon.Shotgun :: Weapon.Rifle :: Nil else Weapon.Rifle :: Weapon.Shotgun :: Nil)
            |> List.find(usable) |> Option.getWithDefault(Weapon.Pistol);
        let fixed = point |> Option.flatMap(p -> p#weapon) |> Option.filter(usable);
        let wanted = fixed |> Option.withDefault(default = aim |> Option.map(a -> byDistance(a#distance)));
        let ready = at#t - s#switchedAt >= tour#switchHold;
        match wanted {
            case Some(w) if ready and w != at#arsenal#current => (Arsenal.Choice.Slot(w), { switchedAt = at#t | s })
            case _                                             => (Arsenal.Choice.Keep, s)
        }
}
