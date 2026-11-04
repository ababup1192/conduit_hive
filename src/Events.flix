// Events — 1 コマの中で起きた事（純粋な値）。遊んでいる場面の事は Session が、画面をまたぐ事（遊び始めた・ポーズ・タイトルへ…）は World が
// このコマの分だけを持ち、音（Sounds）と、後の段の画面の演出が写す。
// 前後の World の差から出来事を推し量らない（同じ欄が 1 コマに 2 回変わると取りこぼす）。
// 後の時刻に起きる事（薬莢・先台）は Session の pending に時刻つきで控え、その時刻を迎えたコマの events へ出す。
mod Events {
    use Creatures.Kind

    /// 敵の倒れ方。Fell = 撃たれた向きへ吹っ飛んで倒れた・Burst = 弾けて肉片になった。
    pub enum Death with Eq, ToString {
        case Fell
        case Burst
    }

    /// 起きた事。
    pub enum Event with Eq, ToString {
        // 撃った（構えていた武器）。
        case Fired(WeaponsDoc.Weapon)
        // 撃った武器の薬莢が床に落ちた（撃ってから SoundsDoc の shellDelay の後）。
        case ShellLanded(WeaponsDoc.Weapon)
        // 散弾銃の先台を引いた（撃ってから SoundsDoc の pumpDelay の後）。
        case Pumped
        // 弾が壁や柱で跳ねた（当たった回のうち SoundsDoc の ricochetChance の割合）。
        case Ricochet
        // 弾が敵に当たった（型・当たった所）。
        case EnemyHit(Kind, Hitscan.Part)
        // 敵が倒れた（型・倒れ方）。
        case EnemyDown(Kind, Death)
        // melee の振り下ろしが当たる時刻を迎えた（当たったかは PlayerHurt）。
        case Swing
        // melee が飛びかかり始めた。
        case Lunge
        // ranged が吐く前の溜めを始めた。
        case Charge
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
        // 区画の wave が始まった（区画・何番目の wave か。0 が最初）。
        case WaveStarted(Char, Int32)
        // 拾った（種類）。
        case PickedUp(Pickups.Kind)
        // 持ち替えた（替えた先の武器。数字キー・ホイール・拾った武器・弾が尽きた時の自動の持ち替え）。
        case Switched(WeaponsDoc.Weapon)
        // 弾の尽きた武器で引き金を引いた（空撃ち）。
        case DryFire(WeaponsDoc.Weapon)
        // 最後の部屋を空にした。
        case Cleared
        // ── 画面をまたぐ事（World.screenEventsOf。遊んでいる場面の外でも起きる） ──
        // タイトルから遊び始めた・ポーズした・ポーズを解いた。
        case Started
        case Paused
        case Resumed
        // ポーズの項目を動かした・決めた。
        case MenuMoved
        case MenuChosen
        // タイトルへ戻った・クリアの画面へ移った。
        case ToTitle
        case ClearShown
    }
}
