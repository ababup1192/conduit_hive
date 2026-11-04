// CameraShake — 描くカメラの揺れ（camera shake）と、撃った時に目が後ろへ下がる跳ね（kick）（純粋）。
// 揺れの強さ（0..1）は出来事ごとに足して 1 で止め、halfLife 秒ごとに半分へ減る。揺れの角は強さの 2 乗に比べる（弱い揺れはほとんど揺らさない）。
// 揺れは時刻から決まる 2 つの波を重ねた物で、乱数の状態を持たない（同じ時刻なら同じ揺れ）。値は JuiceDoc の shake と kick。
// WhyNot: 揺れを撃つレイの照準に入れない — 照準の真ん中と弾の向きがずれ、狙った所に当たらない。描くカメラだけを揺らす。
mod CameraShake {
    use fge::{Num, Vec3}

    /// 揺れ: 強さを最後に足した時刻と、その時の強さ（0..1）。
    pub type alias Shake = { at = Float64, amount = Float64 }

    pub def none(): Shake = { at = -1000.0, amount = 0.0 }

    /// 時刻 t の強さ（0..1）。
    def amountAt(doc: JuiceDoc.Shake, t: Float64, s: Shake): Float64 =
        if (t < s#at) s#amount else s#amount * Float64.pow(base = 0.5, (t - s#at) / Float64.max(0.001, doc#halfLife))

    /// 時刻 t に強さ k を足す（1 で止める）。
    pub def add(doc: JuiceDoc.Shake, t: Float64, k: Float64, s: Shake): Shake =
        if (k <= 0.0) s else { at = t, amount = Num.clamp01(amountAt(doc, t, s) + k) }

    /// 時刻 t の揺れの角（ラジアン。yaw, pitch）。
    pub def offsetAt(doc: JuiceDoc.Shake, t: Float64, s: Shake): (Float64, Float64) =
        let a = amountAt(doc, t, s);
        let angle = doc#maxDeg * Num.pi() / 180.0 * a * a;
        let w = Num.tau() * doc#frequency * t;
        (angle * (0.7 * Num.sin(w) + 0.3 * Num.sin(w * 2.3 + 1.1)), angle * (0.7 * Num.sin(w * 1.3 + 2.0) + 0.3 * Num.sin(w * 3.1 + 0.4)))

    /// 時刻 t に、時刻 shotAt に武器 w で撃った跳ねで目が後ろへ下がっている距離（m。recover 秒で 0 へ戻る）。
    pub def kickAt(doc: JuiceDoc.Kick, w: WeaponsDoc.Weapon, t: Float64, shotAt: Float64): Float64 =
        let k = 1.0 - Num.clamp01((t - shotAt) / Float64.max(0.001, doc#recover));
        if (t < shotAt) 0.0 else JuiceDoc.ofWeapon(w, doc#back) * k * k

    /// 目 eye を前の向き forward（長さ 1）の逆へ back m 下げた点。
    pub def pulledBack(eye: Vec3.Vec3, forward: Vec3.Vec3, back: Float64): Vec3.Vec3 = Vec3.sub(eye, Vec3.mul(forward, back))
}
