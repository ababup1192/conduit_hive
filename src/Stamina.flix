// Stamina — 走る・緊急回避・蹴りが使うスタミナの規則（純粋）。値は MovesDoc の stamina。
// 走る間は毎秒 sprintPerSecond ずつ減り、0 まで走り切ると息切れ（exhausted）になって、resumeAt まで戻るまで走れない。
// 回避と蹴りは 1 回ごとに cost を使い、足りなければ使えない（息切れでも足りていれば使える）。
// 最後に使ってから regenDelay の間は戻らず、その後は毎秒 regenPerSecond ずつ max まで戻る。
mod Stamina {
    use fge::Num

    /// スタミナ: 残り・最後に使った時刻（遊びの時計の秒）・息切れしているか。
    pub type alias Stamina = { points = Float64, usedAt = Float64, exhausted = Bool }

    /// 満タン。
    pub def full(d: MovesDoc.Stamina): Stamina = { points = d#max, usedAt = -1000.0, exhausted = false }

    /// 走れるか（息切れしていなくて、残りがある）。
    pub def canSprint(s: Stamina): Bool = not s#exhausted and s#points > 0.0

    /// 時刻 t に dt 秒走った後（0 まで走り切ったら息切れ）。
    pub def sprinted(d: MovesDoc.Stamina, t: Float64, dt: Float64, s: Stamina): Stamina =
        let points = Float64.max(0.0, s#points - d#sprintPerSecond * dt);
        { points = points, usedAt = t, exhausted = s#exhausted or points <= 0.0 }

    /// 時刻 t に cost を使う（足りなければ None）。
    pub def spend(t: Float64, cost: Float64, s: Stamina): Option[Stamina] =
        if (s#points < cost) None else Some({ points = s#points - cost, usedAt = t | s })

    /// 時刻 t まで dt 秒使わなかった後: 最後に使ってから regenDelay を過ぎていれば戻し、resumeAt まで戻ったら息切れを解く。
    pub def rested(d: MovesDoc.Stamina, t: Float64, dt: Float64, s: Stamina): Stamina =
        if (t - s#usedAt < d#regenDelay) s
        else {
            let points = Float64.min(d#max, s#points + d#regenPerSecond * dt);
            { points = points, exhausted = s#exhausted and points < d#resumeAt | s }
        }

    /// 残りの割合（0..1）。
    pub def fraction(d: MovesDoc.Stamina, s: Stamina): Float64 = Num.clamp01(s#points / Float64.max(1.0, d#max))
}
