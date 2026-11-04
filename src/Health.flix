// Health — プレイヤーの体力・被弾・倒れた時刻（純粋）。値は PlayerDoc（health・hurtSeconds・respawnSeconds）。
// 倒れたら respawnSeconds の後に、最後に入った部屋の入口からやり直す（置き直すのは World）。
mod Health {
    use fge::Num

    /// 体力。hurtAt = 最後に傷を受けた時刻・downAt = 倒れた時刻（倒れていなければ None）。
    pub type alias Health = { points = Float64, hurtAt = Option[Float64], downAt = Option[Float64] }

    /// 満タンの体力。
    pub def full(d: PlayerDoc.Rec): Health = { points = d#health, hurtAt = None, downAt = None }

    /// 時刻 t に amount の傷を受ける（0 以下は何もしない・倒れている間は受けない）。0 以下になったら倒れる。
    pub def hurt(t: Float64, amount: Float64, h: Health): Health =
        if (amount <= 0.0 or isDown(h)) h
        else {
            let points = Float64.max(0.0, h#points - amount);
            { points = points, hurtAt = Some(t), downAt = if (points <= 0.0) Some(t) else None }
        }

    /// amount を足す（体力の最大で止める）。満タン・倒れている・足す量が 0 以下の時は None（拾わない）。
    pub def heal(d: PlayerDoc.Rec, amount: Float64, h: Health): Option[Health] =
        if (isDown(h) or amount <= 0.0 or h#points >= d#health) None
        else Some({ points = Float64.min(d#health, h#points + amount) | h })

    /// 倒れているか。
    pub def isDown(h: Health): Bool = Option.nonEmpty(h#downAt)

    /// 倒れてから respawnSeconds が過ぎたか。
    pub def isRespawnDue(d: PlayerDoc.Rec, t: Float64, h: Health): Bool = h#downAt |> Option.exists(at -> t - at >= d#respawnSeconds)

    /// 残りの割合（0..1）。
    pub def fraction(d: PlayerDoc.Rec, h: Health): Float64 = Num.clamp01(h#points / Float64.max(1.0, d#health))

    /// 被弾の赤みの強さ（傷を受けた瞬間が 1・hurtSeconds で 0。倒れている間は 1）。
    pub def flash(d: PlayerDoc.Rec, t: Float64, h: Health): Float64 =
        if (isDown(h)) 1.0
        else h#hurtAt |> Option.map(at -> 1.0 - Num.clamp01((t - at) / Float64.max(0.01, d#hurtSeconds))) |> Option.getWithDefault(0.0)

    /// 倒れてからやり直すまでの進み（0..1。倒れていなければ 0）。
    pub def downProgress(d: PlayerDoc.Rec, t: Float64, h: Health): Float64 =
        h#downAt |> Option.map(at -> Num.clamp01((t - at) / Float64.max(0.01, d#respawnSeconds))) |> Option.getWithDefault(0.0)
}
