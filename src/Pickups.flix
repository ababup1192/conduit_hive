// Pickups — 迷路に置いた拾う物と、拾う規則（純粋）。
// 迷路の pickup の印は種類の名前だけを持ち、量は PickupsDoc が正。名前が引けない印・床でないマスの印は 1 行知らせて置かない。
// 足元から radius の内に入ると拾う: 回復は体力を足す（満タンなら拾わない）・弾倉は弾を足す（上限なら拾わない）・
// 武器は持っている武器に加えてその場で持ち替える（もう持っていれば弾倉と同じ）。拾った物は Session の taken に番号で残る。
// 浮き方と回り方（hoverAt・spinAt）もここで決め、描くのは View（PickupModels の形を置く）。
mod Pickups {
    use fge::{Log, Num}
    use WeaponsDoc.Weapon

    /// 拾う物の種類。並びは Doc の名前の並び。
    pub enum Kind with Eq, Order, ToString {
        case HealthSmall
        case HealthLarge
        case AmmoShotgun
        case AmmoRifle
        case WeaponShotgun
        case WeaponRifle
    }

    /// 拾うと増える物。Heal = 体力・Ammo = その武器の弾・Arm = その武器（と弾）。
    pub enum Gain with Eq, ToString {
        case Heal
        case Ammo(Weapon)
        case Arm(Weapon)
    }

    /// 置いた拾う物 1 つ: 番号（印の並びの順）・種類・量・床の上の x・z（マスの真ん中）・区画。
    pub type alias Point = { id = Int32, kind = Kind, amount = Int32, x = Float64, z = Float64, zone = Char }

    /// 拾った時に要る値: 時刻・武器と持ち替えの Doc・体力の Doc。
    pub type alias Rules = { t = Float64, weapons = WeaponsDoc.Doc, viewmodel = FpViewmodelDoc.Rec, player = PlayerDoc.Rec }

    /// 拾うと変わる物: 武器と体力。
    pub type alias Carry = { arsenal = Arsenal.Arsenal, health = Health.Health }

    /// 拾った結果: 変わった武器と体力・拾った物の番号（前から拾っていた物も）・このコマに拾った物（拾った順）。
    pub type alias Collected = { carry = Carry, taken = Set[Int32], picked = List[Point] }

    /// 全部の種類。
    def all(): List[Kind] =
        Kind.HealthSmall :: Kind.HealthLarge :: Kind.AmmoShotgun :: Kind.AmmoRifle :: Kind.WeaponShotgun :: Kind.WeaponRifle :: Nil

    /// 種類の名前（迷路の印の name・PickupsDoc の items の鍵）。
    def nameOf(k: Kind): String = match k {
        case Kind.HealthSmall   => "health_small"
        case Kind.HealthLarge   => "health_large"
        case Kind.AmmoShotgun   => "ammo_shotgun"
        case Kind.AmmoRifle     => "ammo_rifle"
        case Kind.WeaponShotgun => "weapon_shotgun"
        case Kind.WeaponRifle   => "weapon_rifle"
    }

    /// 拾うと増える物。
    pub def gainOf(k: Kind): Gain = match k {
        case Kind.HealthSmall   => Gain.Heal
        case Kind.HealthLarge   => Gain.Heal
        case Kind.AmmoShotgun   => Gain.Ammo(Weapon.Shotgun)
        case Kind.AmmoRifle     => Gain.Ammo(Weapon.Rifle)
        case Kind.WeaponShotgun => Gain.Arm(Weapon.Shotgun)
        case Kind.WeaponRifle   => Gain.Arm(Weapon.Rifle)
    }

    def kindOf(name: String): Option[Kind] = all() |> List.find(k -> nameOf(k) == name)

    /// 迷路の pickup の印を、種類の名前で量を引いた物の列（番号は pickup の印の並びの順）。
    pub def pointsOf(m: Maze.Maze, doc: PickupsDoc.Doc): List[Point] =
        let amounts = PickupsDoc.rec(doc)#amounts;
        m#marks |> List.filter(mk -> mk#kind == MazeDoc.MarkKind.Pickup) |> List.zipWithIndex |> List.filterMap(e -> {
            let (id, mk) = e;
            let cell = { col = mk#col, row = mk#row };
            let zone = Map.get(Maze.charAt(m, cell), m#zones) |> Option.map(z -> z#id);
            let named = forM (k <- kindOf(mk#name); n <- Map.get(mk#name, amounts)) yield (k, n);
            match (named, zone) {
                case (None, _) => Log.warnThen("[pickup] 印 (${mk#col}, ${mk#row}) の '${mk#name}' は pickups.json に無いので置かない", None)
                case (_, None) => Log.warnThen("[pickup] 印 (${mk#col}, ${mk#row}) は床のマスに無いので置かない", None)
                case (Some((kind, amount)), Some(z)) =>
                    let (x, cz) = Maze.centerOf(m, cell);
                    Some({ id = id, kind = kind, amount = amount, x = x, z = cz, zone = z })
            }
        })

    /// p を 1 つ拾おうとする（満タン・上限で拾えなければ None）。
    pub def take(r: Rules, p: Point, c: Carry): Option[Carry] = match gainOf(p#kind) {
        case Gain.Heal    => Health.heal(r#player, Int32.toFloat64(p#amount), c#health) |> Option.map(h -> { health = h | c })
        case Gain.Ammo(w) => Arsenal.addAmmo(r#weapons, w, p#amount, c#arsenal) |> Option.map(a -> { arsenal = a | c })
        case Gain.Arm(w)  => Arsenal.arm(r#weapons, r#viewmodel, r#t, w, p#amount, c#arsenal) |> Option.map(a -> { arsenal = a | c })
    }

    /// 足元 at から radius の内の、まだ拾っていない物を並びの順に拾う（拾えない物は置いたまま）。
    pub def collect(r: Rules, radius: Float64, at: { x = Float64, z = Float64 }, points: List[Point], taken: Set[Int32], c: Carry): Collected =
        let near = (p: Point) -> { let (dx, dz) = (p#x - at#x, p#z - at#z); dx * dx + dz * dz <= radius * radius };
        let got = points |> List.filter(p -> near(p) and not Set.memberOf(p#id, taken)) |> List.foldLeft((acc, p) ->
            match take(r, p, acc#carry) {
                case None    => acc
                case Some(n) => { carry = n, taken = Set.insert(p#id, acc#taken), picked = p :: acc#picked }
            }, { carry = c, taken = taken, picked = Nil });
        { picked = List.reverse(got#picked) | got }

    // ── 浮き方と回り方 ──

    /// 時刻 t の床からの高さ（hover を真ん中に bob の幅で揺れる。物ごとに揺れの位相をずらす）。
    pub def hoverAt(doc: PickupsDoc.Doc, t: Float64, p: Point): Float64 =
        let d = PickupsDoc.rec(doc);
        let phase = Int32.toFloat64(p#id) * 1.7;
        d#hover + d#bob * Num.sin(Num.tau() * t / Float64.max(0.1, d#bobSeconds) + phase)

    /// 時刻 t の向き（ラジアン。物ごとに始まりの向きをずらす）。
    pub def spinAt(doc: PickupsDoc.Doc, t: Float64, p: Point): Float64 =
        (PickupsDoc.rec(doc)#spinDegPerSec * t + Int32.toFloat64(p#id) * 47.0) * Num.pi() / 180.0
}
