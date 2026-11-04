// Walker — 一人称で歩く体の状態と、1 コマ進める規則（純粋: 前の体 + 歩き方 + 遊びの時計 → 次の体）。
//
// 体は足元の点（x・feet・z）と向き（yaw・pitch）と、足の着き方（engine の CharacterBody3d.Footing）で表す。座標は engine の Scene3d と同じ
// （左手系・X 東・Y 上・Z 北）。前へ歩く向きは (sin yaw, 0, cos yaw)。跳ばない（engine に口が無く、迷路にも要らない）。
// 壁から押し出す・床に吸い付く・落ちるは engine の CharacterBody3d.moveAndSlide。ここは向きと頭の上下を持つ。
mod Walker {
    use fge::{CharacterBody3d, Clock, CollisionShape3d, CollisionWorld3d, Num, Vec3}

    /// このコマの歩き方: 前後（-1..1）・左右（-1..1。正で右）・このコマで向きを変える角（度。正で右へ。マウスの動き）・
    /// 見上げ見下ろしの角（度。正で下を向く）・向きを変え続ける速さ（度/秒。キー）・走るか。
    /// 速さの方は遊びの時計の秒を掛けて角にする（実時間で向きが変わらない）。
    pub type alias Drive = { forward = Float64, strafe = Float64, turnDeg = Float64, lookDeg = Float64, turnRate = Float64, sprint = Bool }

    /// 体の状態。distance = 歩いた距離の合計（頭の上下が読む）・running = 今のコマに走っていたか（1 歩の長さが替わる）。
    pub type alias Walker = { x = Float64, feet = Float64, z = Float64, yaw = Float64, pitch = Float64, footing = CharacterBody3d.Footing,
                              distance = Float64, running = Bool }

    def rad(deg: Float64): Float64 = deg * Num.pi() / 180.0

    /// 止まって立っている体（足の着き方は呼ぶ側が settle で床に合わせる）。
    pub def standing(x: Float64, feet: Float64, z: Float64, yawDeg: Float64): Walker =
        { x = x, feet = feet, z = z, yaw = rad(yawDeg), pitch = 0.0, footing = CharacterBody3d.bodyAt(Vec3.v3(x, feet, z))#footing,
          distance = 0.0, running = false }

    /// 何もしないコマ。
    pub def idle(): Drive = { forward = 0.0, strafe = 0.0, turnDeg = 0.0, lookDeg = 0.0, turnRate = 0.0, sprint = false }

    /// 体の寸法と動き方（WalkDoc から。吸い付く深さ・区切りの長さは engine の既定）。
    def settingsOf(walk: WalkDoc.Rec): CharacterBody3d.Settings =
        { stepHeight = walk#stepHeight, gravity = walk#gravity | CharacterBody3d.settings(walk#radius, walk#height) }

    def bodyOf(w: Walker): CharacterBody3d.Body = { feet = Vec3.v3(w#x, w#feet, w#z), footing = w#footing }

    def withBody(b: CharacterBody3d.Body, w: Walker): Walker = { x = b#feet#x, feet = b#feet#y, z = b#feet#z, footing = b#footing | w }

    /// 足元を床に合わせた体（床が無ければそのまま）。始まりと置き直しで使う。
    pub def settle(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, w: Walker): Walker =
        withBody(CharacterBody3d.snapToFloor(world, Nil, settingsOf(walk), bodyOf(w)), w)

    /// 歩く向き（体の向き yaw に対して、前と右を足した水平の向き。長さは 1 以下）。
    pub def headingOf(yaw: Float64, d: Drive): (Float64, Float64) =
        let (s, c) = (Num.sin(yaw), Num.cos(yaw));
        let x = d#forward * s + d#strafe * c;
        let z = d#forward * c - d#strafe * s;
        let len = Num.sqrt(x * x + z * z);
        if (len > 1.0) (x / len, z / len) else (x, z)

    /// 1 コマ進める（秒は遊びの時計の今のコマの分）。
    pub def step(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, d: Drive, clock: Clock.Clock[PlayClock.Play], w: Walker): Walker =
        stepSeconds(world, walk, d, None, Num.clamp(0.0, 0.05, Clock.dtOf(clock)), w)

    /// 緊急回避の 1 コマ: 向きと見上げ見下ろしは歩き方 d のまま、体は velocity（m/秒の水平の x・z）で動かす（壁から押し出すのは engine）。
    pub def dash(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, d: Drive, velocity: (Float64, Float64), clock: Clock.Clock[PlayClock.Play], w: Walker): Walker =
        stepSeconds(world, walk, { sprint = false | d }, Some(velocity), Num.clamp(0.0, 0.05, Clock.dtOf(clock)), w)

    /// step の本体: 向き → engine の体を動かす（速さは歩き方から・dashing があればその速さ）→ 歩いた距離を足す。
    def stepSeconds(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, d: Drive, dashing: Option[(Float64, Float64)], dt: Float64, w: Walker): Walker =
        let limit = rad(walk#pitchLimit);
        let yaw = w#yaw + rad(d#turnDeg + d#turnRate * dt);
        let pitch = Num.clamp(0.0 - limit, limit, w#pitch + rad(d#lookDeg));
        let speed = if (d#sprint) walk#runSpeed else walk#walkSpeed;
        let (hx, hz) = headingOf(yaw, d);
        let (vx, vz) = dashing |> Option.getWithDefault((hx * speed, hz * speed));
        let body = CharacterBody3d.moveAndSlide(world, Nil, settingsOf(walk), Vec3.v3(vx, 0.0, vz), dt, bodyOf(w));
        let moved = withBody(body, w);
        let flat = Num.sqrt((moved#x - w#x) * (moved#x - w#x) + (moved#z - w#z) * (moved#z - w#z));
        { yaw = yaw, pitch = pitch, distance = w#distance + flat, running = d#sprint | moved }

    /// 同じ歩き方と同じ時計の刻みで n コマ進めた後の体。
    pub def simulate(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, d: Drive, clock: Clock.Clock[PlayClock.Play], n: Int32, w: Walker): Walker =
        List.range(0, n) |> List.foldLeft((cur, _) -> step(world, walk, d, clock, cur), w)

    /// 体が箱に食い込んでいる一番深い所（m。0 なら食い込んでいない）。
    pub def overlapDepth(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, w: Walker): Float64 =
        CharacterBody3d.overlapDepth(world, Nil, settingsOf(walk), bodyOf(w))

    /// 歩いた距離の 1 歩の位相（ラジアン。1 歩で π 進む）。頭の上下とビューモデルの揺れが同じ拍で動く。
    pub def stridePhase(walk: WalkDoc.Rec, w: Walker): Float64 =
        let stride = Float64.max(0.1, if (w#running) walk#runStride else walk#stride);
        Num.pi() * w#distance / stride

    /// 目の位置（足元の真上・目の高さ + 歩く上下）。
    pub def eyeOf(walk: WalkDoc.Rec, w: Walker): Vec3.Vec3 =
        Vec3.v3(w#x, w#feet + walk#eyeHeight + walk#bobHeight * Float64.abs(Num.sin(stridePhase(walk, w))), w#z)
}
