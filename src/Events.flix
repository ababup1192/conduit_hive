// Events — 1 コマの中で起きた事（純粋な値）。World.step がこのコマの分だけを持ち、音（Sounds）と、後の段の画面の演出が写す。
// 前後の World の差から出来事を推し量らない（同じ欄が 1 コマに 2 回変わると取りこぼす）。
mod Events {
    use Creatures.Kind

    /// 起きた事。
    pub enum Event with Eq, ToString {
        // 撃った（構えていた武器）。
        case Fired(WeaponsDoc.Weapon)
        // 弾が敵に当たった（型・当たった所）。
        case EnemyHit(Kind, Hitscan.Part)
        // 敵が倒れた。
        case EnemyDown(Kind)
        // melee の振り下ろしが当たる時刻を迎えた（当たったかは PlayerHurt）。
        case Swing
        // ranged が projectile を吐いた。
        case Spit
        // projectile が壁で弾けた。
        case Burst
        // プレイヤーが傷を受けた（量）。
        case PlayerHurt(Float64)
        // プレイヤーが倒れた・やり直した。
        case PlayerDown
        case Respawned
        // 部屋に入って群れが湧き始めた。
        case RoomTriggered(Char)
    }
}
