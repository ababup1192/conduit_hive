// WeaponsDoc — conduit_hive.weapons.json（武器ごとの威力・連射の間隔・ばらつき・弾数・散弾の粒の数・反動）の宣言ドキュメント層。
// 撃ち方の規則（連射・持ち替え・当たり判定）はコード（Arsenal・Hitscan）で、ここは調整する数だけ。
// 角度は度・長さは m・時間は秒。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod WeaponsDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 武器の種類。持ち替えの並び（数字キーの 1・2・3 とホイール）もこの順。
    pub enum Weapon with Eq, Order, ToString {
        case Pistol
        case Shotgun
        case Rifle
    }

    /// 武器 1 つの値。damage = 1 発（散弾は 1 粒）の威力。
    pub type alias Stats = {
        damage = Float64,
        // 次を撃てるまでの間隔（秒）。
        interval = Float64,
        // ばらつき（度。照準から外れる角の最大）。
        spread = Float64,
        // 1 回に飛ぶ粒の数（散弾のほかは 1）。
        pellets = Int32,
        // 撃つと照準が跳ね上がる角（度）。
        recoil = Float64,
        // 弾が届く距離（m）。
        range = Float64,
        // 押している間撃ち続けるか（偽なら押すたびに 1 回）。
        automatic = Bool,
        // 弾が無限か（真なら ammo は見ない）。
        infinite = Bool,
        // 始めに持っている弾の数。
        ammo = Int32,
        // 持てる弾の上限（拾っても超えない。無限の武器は見ない）。
        maxAmmo = Int32,
        // 始めから持っているか（偽の武器は拾うまで持ち替えられない）。
        owned = Bool
    }

    pub type alias Rec = { version = Int32, pistol = Stats, shotgun = Stats, rifle = Stats }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.weapons.json"

    /// 全部の武器（持ち替えの並び）。
    pub def all(): List[Weapon] = Weapon.Pistol :: Weapon.Shotgun :: Weapon.Rifle :: Nil

    /// 武器の Doc の欄の名前（JSON のキー・音の名前の頭）。
    pub def keyOf(w: Weapon): String = match w {
        case Weapon.Pistol  => "pistol"
        case Weapon.Shotgun => "shotgun"
        case Weapon.Rifle   => "rifle"
    }

    /// 武器 w の値。
    pub def statsOf(w: Weapon, d: Doc): Stats = match w {
        case Weapon.Pistol  => rec(d)#pistol
        case Weapon.Shotgun => rec(d)#shotgun
        case Weapon.Rifle   => rec(d)#rifle
    }

    /// コード側の既定値（assets/conduit_hive.weapons.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  pistol  = { damage = 25.0, interval = 0.25, spread = 0.6, pellets = 1, recoil = 2.0, range = 60.0,
                              automatic = false, infinite = true, ammo = 0, maxAmmo = 0, owned = true },
                  shotgun = { damage = 20.0, interval = 0.9, spread = 10.0, pellets = 9, recoil = 6.0, range = 30.0,
                              automatic = false, infinite = false, ammo = 0, maxAmmo = 40, owned = false },
                  rifle   = { damage = 20.0, interval = 0.1, spread = 1.8, pellets = 1, recoil = 1.0, range = 70.0,
                              automatic = true, infinite = false, ammo = 0, maxAmmo = 240, owned = false } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// 武器 1 つの欄（無い欄はその欄だけ既定）。
    def statsOr(fallback: Stats, key: String, root: Map[String, Json]): Stats =
        match Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) {
            case None => fallback
            case Some(o) =>
                let f = (k, d) -> JsonCodec.floatOr(k, d, o);
                let b = (k, d) -> JsonCodec.boolOr(k, d, o);
                let i = (k, d) -> JsonCodec.intOr(k, d, o);
                { damage = f("damage", fallback#damage), interval = f("interval", fallback#interval), spread = f("spread", fallback#spread),
                  pellets = i("pellets", fallback#pellets), recoil = f("recoil", fallback#recoil), range = f("range", fallback#range),
                  automatic = b("automatic", fallback#automatic), infinite = b("infinite", fallback#infinite),
                  ammo = i("ammo", fallback#ammo), maxAmmo = i("maxAmmo", fallback#maxAmmo), owned = b("owned", fallback#owned) }
        }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  pistol = statsOr(d#pistol, "pistol", root), shotgun = statsOr(d#shotgun, "shotgun", root), rifle = statsOr(d#rifle, "rifle", root) })
}
