// Knockback — 撃たれた敵が押される（のけぞり）と、倒れた敵が撃たれた向きへ吹っ飛ぶ（放物線・横の回転・床を滑って止まる）の規則（純粋）。
// 強さは武器ごとの値に、撃った点からの距離で決まる倍率（近いほど強い）を掛ける。値は EnemiesDoc の flinch と JuiceDoc の fling。
// 壁を抜けないかは呼ぶ側が渡す線の見通し（Collider.isLineClear）で見て、遮られたら横の速さを捨てる。
// 体の形の動き（die のクリップ）はそのまま流し、その上に体全体の飛びを重ねる（ラグドールではない）。
mod Knockback {
    use fge::{Num, Vec3}

    /// のけぞり: 押され始めた時刻・押す向き（長さ 1 の x・z）・始めの速さ（m/秒。decay 秒ごとに 1/e へ減る）。
    pub type alias Push = { at = Float64, dx = Float64, dz = Float64, speed = Float64 }

    /// 吹っ飛び: 足元の高さ（m）・速さ（m/秒）・横の回る速さ（ラジアン/秒。滑る速さに合わせて減る）・始めの横の速さ。
    pub type alias Flight = { y = Float64, vx = Float64, vy = Float64, vz = Float64, spin = Float64, speed0 = Float64 }

    /// 足元と向き（Horde の敵の位置の欄と同じ形）。
    pub type alias Place = { x = Float64, z = Float64, yaw = Float64 }

    /// 押されていない。
    pub def noPush(): Push = { at = -1000.0, dx = 0.0, dz = 0.0, speed = 0.0 }

    /// 飛んでいない（床の上で止まっている）。
    pub def grounded(): Flight = { y = 0.0, vx = 0.0, vy = 0.0, vz = 0.0, spin = 0.0, speed0 = 0.0 }

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    /// 近い時に強める倍率: 距離 0 で boost 倍・range 以上で 1 倍・その間は距離に比べて 2 つの値の間をなめらかにつなぐ。
    def closeFactor(range: Float64, boost: Float64, distance: Float64): Float64 =
        if (range <= 0.0) 1.0 else 1.0 + (boost - 1.0) * Num.clamp01(1.0 - distance / range)

    /// 撃った点 (fromX, fromZ) から足元 (x, z) へ向かう長さ 1 の向きと距離（重なっていれば +Z）。
    pub def awayFrom(fromX: Float64, fromZ: Float64, x: Float64, z: Float64): { dx = Float64, dz = Float64, distance = Float64 } =
        let (ex, ez) = (x - fromX, z - fromZ);
        let d = Num.sqrt(ex * ex + ez * ez);
        if (d < 0.0001) { dx = 0.0, dz = 1.0, distance = 0.0 } else { dx = ex / d, dz = ez / d, distance = d }

    // ── のけぞり ──

    /// 時刻 t に武器 w で、距離 distance から向き (dx, dz) へ撃たれた時の押され方。
    pub def pushOf(f: EnemiesDoc.Flinch, w: WeaponsDoc.Weapon, t: Float64, away: { dx = Float64, dz = Float64, distance = Float64 }): Push =
        let base = match w {
            case WeaponsDoc.Weapon.Pistol  => f#pistol
            case WeaponsDoc.Weapon.Shotgun => f#shotgun
            case WeaponsDoc.Weapon.Rifle   => f#rifle
        };
        { at = t, dx = away#dx, dz = away#dz, speed = base * closeFactor(f#closeRange, f#closeBoost, away#distance) }

    /// 時刻 t の押される速さ（m/秒）。
    def pushSpeedAt(f: EnemiesDoc.Flinch, t: Float64, p: Push): Float64 =
        if (t < p#at) 0.0 else p#speed * Float64.exp(0.0 - (t - p#at) / Float64.max(0.001, f#decay))

    /// このコマ（dt 秒）に押されて動く量（x, z の m）。
    pub def pushStep(f: EnemiesDoc.Flinch, t: Float64, dt: Float64, p: Push): (Float64, Float64) =
        let v = pushSpeedAt(f, t, p) * dt;
        (p#dx * v, p#dz * v)

    /// 時刻 t に体が押される向きへ傾く角（ラジアン）: 拳銃 1 発の速さで leanDeg まで、速さが減るのに合わせて戻る。
    pub def leanAt(f: EnemiesDoc.Flinch, t: Float64, p: Push): Float64 =
        rad(f#leanDeg) * Num.clamp01(pushSpeedAt(f, t, p) / Float64.max(0.001, f#pistol))

    // ── 吹っ飛び ──

    /// 武器 w で、向き away へ倒された時の飛び出し（seed で横の回る向きを決める）。上への速さは近さの倍率の平方根だけ強める。
    // WhyNot: 上への速さに近さの倍率をそのまま掛けない — 散弾銃の 0 m で 2 m 近く跳ね上がり、天井の灯りまで届く絵になる。
    pub def launch(fl: JuiceDoc.Fling, w: WeaponsDoc.Weapon, away: { dx = Float64, dz = Float64, distance = Float64 }, seed: Float64): Flight =
        let k = closeFactor(fl#closeRange, fl#closeBoost, away#distance);
        let speed = JuiceDoc.ofWeapon(w, fl#speed) * k;
        { y = 0.0, vx = away#dx * speed, vy = fl#lift * Num.sqrt(k), vz = away#dz * speed,
          spin = rad(fl#spin) * k * (if (seed < 0.5) -1.0 else 1.0), speed0 = speed }

    /// 横の速さ（m/秒）。
    def horizontal(f: Flight): Float64 = Num.sqrt(f#vx * f#vx + f#vz * f#vz)

    /// 今の滑る速さの、飛び出した時の速さに対する割合（0..1）。
    def slideRatio(f: Flight): Float64 = if (f#speed0 <= 0.0) 0.0 else Num.clamp01(horizontal(f) / f#speed0)

    /// 時刻に関わらず 1 コマ（dt 秒）飛ばす: 上へは下へ引く強さで放物線・床（高さ 0）に着いたら止め、床の上では friction で横の速さを減らす。
    /// 横の動きは足元から腰の高さで reach だけ先まで見通せる時だけ（isClear）。遮られたら横の速さを捨てて止まる（壁を抜けない）。
    pub def fly(fl: JuiceDoc.Fling, isClear: (Vec3.Vec3, Vec3.Vec3) -> Bool, reach: Float64, dt: Float64, at: Place, f: Flight): (Place, Flight) =
        let vy = if (f#y > 0.0 or f#vy > 0.0) f#vy - fl#gravity * dt else 0.0;
        let y = Float64.max(0.0, f#y + vy * dt);
        let landed = y <= 0.0;
        let h = horizontal(f);
        let slowed = if (landed and h > 0.0) Float64.max(0.0, h - fl#friction * dt) / h else 1.0;
        let (vx, vz) = (f#vx * slowed, f#vz * slowed);
        let (nx, nz) = (at#x + vx * dt, at#z + vz * dt);
        let moved = { y = y, vx = vx, vy = if (landed) 0.0 else vy, vz = vz | f };
        let hn = horizontal(moved);
        let waist = 0.6;
        let ahead = if (hn <= 0.0) Vec3.v3(nx, waist, nz) else Vec3.v3(nx + vx / hn * reach, waist, nz + vz / hn * reach);
        let clear = hn <= 0.0 or isClear(Vec3.v3(at#x, waist, at#z), ahead);
        let turn = f#spin * slideRatio(moved) * dt;
        if (clear) ({ x = nx, z = nz, yaw = at#yaw + turn }, moved)
        else ({ x = at#x, z = at#z, yaw = at#yaw + turn }, { vx = 0.0, vz = 0.0 | moved })

    /// 時刻に関わらず、飛んでいる間に後ろ（飛ぶ向き）へ反る角（ラジアン。滑る速さに合わせて 0 へ戻る）。
    pub def tiltOf(fl: JuiceDoc.Fling, f: Flight): Float64 = rad(fl#tilt) * slideRatio(f)

    /// 飛ぶ向き（長さ 1 の x・z。止まっていれば None）。
    pub def headingOf(f: Flight): Option[(Float64, Float64)] =
        let h = horizontal(f);
        if (h <= 0.0001) None else Some((f#vx / h, f#vz / h))
}
