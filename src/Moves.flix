// Moves — 群れに囲まれた時に立て直す技（緊急回避・蹴り）の状態と規則と、それが使うスタミナ（純粋）。値は MovesDoc。
//
// 緊急回避: 押している歩く向き（押していなければ後ろ）へ seconds の間に distance だけ跳ぶ。跳び始めが速く、終わりへ遅くなる。
//   跳び始めから iframe の間は攻撃が当たらない（i-frame）。次に跳べるのは跳び始めから cooldown の後。壁から押し出すのは Walker（engine の moveAndSlide）。
// 蹴り: 前の扇の敵を押し返してよろけさせる（当てる規則は Horde.kick）。次に蹴れるのは蹴ってから cooldown の後。
// どちらもスタミナを cost 使い、足りなければ使えない（Refusal.Tired。音で知らせる）。
mod Moves {
    use fge::Num

    /// 押せる技: 緊急回避・蹴り・手榴弾を投げる。
    pub enum Move with Eq, Order, ToString {
        case Dodge
        case Kick
        case Grenade
    }

    /// このコマに押した技の組（1 コマに 2 つ押せる）。
    pub type alias Press = Set[Move]

    /// 何も押していない。
    pub def none(): Press = Set.empty()

    /// 技 m を押したか。
    pub def isPressed(m: Move, p: Press): Bool = Set.memberOf(m, p)

    /// 跳んだ回避: 跳び始めた時刻（押したコマの始め）・跳ぶ向き（長さ 1 の x・z）。
    pub type alias Dodge = { at = Float64, dx = Float64, dz = Float64 }

    /// 技の状態: スタミナ・最後の回避（跳び終えても次に跳べる時刻のために残す）・最後に蹴った時刻。
    pub type alias Moves = { stamina = Stamina.Stamina, dodge = Option[Dodge], kickAt = Float64 }

    /// 技を使えなかった訳: Busy = 前の技からの間がまだ・Tired = スタミナが足りない。
    pub enum Refusal with Eq, ToString {
        case Busy
        case Tired
    }

    /// 遊び始め（スタミナは満タン・技はまだ使っていない）。
    pub def initial(d: MovesDoc.Rec): Moves = { stamina = Stamina.full(d#stamina), dodge = None, kickAt = -1000.0 }

    def progress(seconds: Float64, t: Float64, at: Float64): Float64 = Num.clamp01((t - at) / Float64.max(0.0001, seconds))

    // ── スタミナ ──

    /// 走れるか（息切れしていなくて、残りがある）。
    pub def canSprint(m: Moves): Bool = Stamina.canSprint(m#stamina)

    /// このコマ（時刻 t・dt 秒）のスタミナ: 走ったなら減らし、走っていなければ休ませる。
    pub def breathe(d: MovesDoc.Stamina, t: Float64, dt: Float64, sprinting: Bool, m: Moves): Moves =
        { stamina = if (sprinting) Stamina.sprinted(d, t, dt, m#stamina) else Stamina.rested(d, t, dt, m#stamina) | m }

    // ── 緊急回避 ──

    /// 回避の向き（長さ 1 の x・z）: 歩く向き along（体の向きで水平にした物）・ほとんど押していなければ体の向き yaw の後ろ。
    pub def dodgeHeading(yaw: Float64, along: (Float64, Float64)): (Float64, Float64) =
        let (x, z) = along;
        let len = Num.sqrt(x * x + z * z);
        if (len < 0.1) (0.0 - Num.sin(yaw), 0.0 - Num.cos(yaw)) else (x / len, z / len)

    /// 時刻 t（このコマは dt 秒）に向き heading へ跳び始める: 前の回避から cooldown が過ぎていて、スタミナが cost ある時だけ。
    /// 跳ぶ間はこのコマの始めから数える（押したコマから動く）。
    pub def dodge(d: MovesDoc.Dodge, t: Float64, dt: Float64, heading: (Float64, Float64), m: Moves): Result[Refusal, Moves] =
        let ready = m#dodge |> Option.forAll(x -> t - dt - x#at >= d#cooldown);
        let (dx, dz) = heading;
        if (not ready) Err(Refusal.Busy)
        else Stamina.spend(t, d#cost, m#stamina) |> Option.map(s -> { stamina = s, dodge = Some({ at = t - dt, dx = dx, dz = dz }) | m })
                |> Option.toOk(Refusal.Tired)

    /// 跳ぶ距離の進み: 時間の進み u（0..1）に対して 1 − (1 − u)²（跳び始めが速く、終わりへ遅くなる）。
    def eased(u: Float64): Float64 = 1.0 - (1.0 - u) * (1.0 - u)

    /// このコマ（t − dt から t）に跳ぶ速さ（m/秒の x・z）。跳ぶ間に掛からないコマは None。
    /// 速さはこのコマの始めと終わりの進みの差を dt で割る（コマの長さで跳ぶ距離が変わらない）。
    pub def dashOf(d: MovesDoc.Dodge, t: Float64, dt: Float64, m: Moves): Option[(Float64, Float64)] =
        m#dodge |> Option.filter(x -> dt > 0.0 and t > x#at and t - dt < x#at + d#seconds) |> Option.map(x -> {
            let step = d#distance * (eased(progress(d#seconds, t, x#at)) - eased(progress(d#seconds, t - dt, x#at)));
            (x#dx * step / dt, x#dz * step / dt)
        })

    /// 時刻 t に跳んでいるか。
    pub def isDodging(d: MovesDoc.Dodge, t: Float64, m: Moves): Bool = m#dodge |> Option.exists(x -> t >= x#at and t - x#at < d#seconds)

    /// 時刻 t に攻撃が当たらないか（跳び始めから iframe の間）。
    pub def isInvulnerable(d: MovesDoc.Dodge, t: Float64, m: Moves): Bool = m#dodge |> Option.exists(x -> t >= x#at and t - x#at < d#iframe)

    /// 時刻 t の回避の見え方の強さ（0..1。跳ぶ間に 0 から 1 へ上がって 0 へ戻る山・跳んでいなければ 0）。
    pub def dodgeSwell(d: MovesDoc.Dodge, t: Float64, m: Moves): Float64 =
        if (isDodging(d, t, m)) m#dodge |> Option.map(x -> Num.sin(Num.pi() * progress(d#seconds, t, x#at))) |> Option.getWithDefault(0.0)
        else 0.0

    // ── 蹴り ──

    /// 時刻 t に蹴る: 前に蹴ってから cooldown が過ぎていて、スタミナが cost ある時だけ（当てるのは Horde.kick）。
    pub def kick(d: MovesDoc.Kick, t: Float64, m: Moves): Result[Refusal, Moves] =
        if (t - m#kickAt < d#cooldown) Err(Refusal.Busy)
        else Stamina.spend(t, d#cost, m#stamina) |> Option.map(s -> { stamina = s, kickAt = t | m }) |> Option.toOk(Refusal.Tired)

    /// 時刻 t の蹴りの進み（0..1。脚が見えている seconds の間だけ Some）。
    pub def kickProgress(d: MovesDoc.Kick, t: Float64, m: Moves): Option[Float64] =
        if (t >= m#kickAt and t - m#kickAt < d#seconds) Some(progress(d#seconds, t, m#kickAt)) else None
}
