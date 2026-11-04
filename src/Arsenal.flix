// Arsenal — 持っている武器・弾・連射の間隔・持ち替え・反動の規則（純粋）。
// 弾の当たりは Hitscan、粒は Particles3d。ここは「撃てるか」と「撃った後の状態」と、拾った武器と弾の足し方だけを決める。
// 弾が尽きた武器で引き金を引くと空撃ち（撃てない・間隔だけ空く）になり、弾のある武器へ自動で持ち替える（dryFire）。
// 時刻は遊びの時計の秒（ポーズの間は進まない）。値は WeaponsDoc（武器ごと）と FpViewmodelDoc（持ち替えと反動の戻り）。
mod Arsenal {
    use fge::Num
    use WeaponsDoc.Weapon

    /// 手の状態。Ready = 構えている・Drawing(秒) = その時刻から持ち替えている。
    pub enum Hands with Eq, ToString {
        case Ready
        case Drawing(Float64)
    }

    /// 撃った 1 回。index = 何回目か（粒のばらつきの種）。
    pub type alias Shot = { weapon = Weapon, at = Float64, index = Int32 }

    /// 武器の状態。readyAt = 次を撃てる時刻・shots = 撃った回数の合計・last = 最後に撃った 1 回。
    pub type alias Arsenal = {
        current = Weapon,
        owned = Set[Weapon],
        ammo = Map[Weapon, Int32],
        readyAt = Float64,
        hands = Hands,
        shots = Int32,
        last = Option[Shot]
    }

    /// 引き金: pressed = このコマに押した・held = 押している。
    pub type alias Trigger = { pressed = Bool, held = Bool }

    /// 持ち替えの指示。Keep = 替えない・Slot = その武器へ・Next / Previous = 持っている武器の並びの次・前へ（端で回る）。
    pub enum Choice with Eq, ToString {
        case Keep
        case Slot(Weapon)
        case Next
        case Previous
    }

    /// 引いていない引き金。
    pub def released(): Trigger = { pressed = false, held = false }

    /// 始めの状態: Doc の owned の武器を持ち、始めの弾を持つ（maxAmmo で止める）。構えているのは持っている武器の並びの最初（無ければ拳銃）。
    pub def initial(doc: WeaponsDoc.Doc): Arsenal =
        let owned = WeaponsDoc.all() |> List.filter(w -> WeaponsDoc.statsOf(w, doc)#owned);
        { current = List.head(owned) |> Option.getWithDefault(Weapon.Pistol), owned = List.toSet(owned),
          ammo = WeaponsDoc.all() |> List.map(w -> { let st = WeaponsDoc.statsOf(w, doc); (w, if (st#infinite) st#ammo else Int32.min(st#maxAmmo, st#ammo)) }) |> List.toMap,
          readyAt = 0.0, hands = Hands.Ready, shots = 0, last = None }

    /// 武器 w を持っているか。
    def owns(w: Weapon, a: Arsenal): Bool = Set.memberOf(w, a#owned)

    /// 構えている武器の値。
    pub def statsOf(doc: WeaponsDoc.Doc, a: Arsenal): WeaponsDoc.Stats = WeaponsDoc.statsOf(a#current, doc)

    /// 構えている武器の残りの弾（無限なら None）。
    pub def ammoOf(doc: WeaponsDoc.Doc, a: Arsenal): Option[Int32] =
        if (statsOf(doc, a)#infinite) None else Some(Map.getWithDefault(a#current, 0, a#ammo))

    /// 武器 w の残りの弾（無限の武器は Map の値のまま）。
    def ammoIn(w: Weapon, a: Arsenal): Int32 = Map.getWithDefault(w, 0, a#ammo)

    /// 武器 w に撃てる弾があるか（無限の武器はいつもある）。
    def isLoaded(doc: WeaponsDoc.Doc, w: Weapon, a: Arsenal): Bool = WeaponsDoc.statsOf(w, doc)#infinite or ammoIn(w, a) > 0

    /// 構えている武器の弾が尽きているか。
    pub def isEmpty(doc: WeaponsDoc.Doc, a: Arsenal): Bool = not isLoaded(doc, a#current, a)

    /// 武器 w の弾を amount 足す（maxAmmo で止める）。もう上限・無限の武器・足す量が 0 以下なら None（拾わない）。
    /// 持っていない武器の弾も足す（後で武器を拾えば使える）。
    pub def addAmmo(doc: WeaponsDoc.Doc, w: Weapon, amount: Int32, a: Arsenal): Option[Arsenal] =
        let stats = WeaponsDoc.statsOf(w, doc);
        let now = ammoIn(w, a);
        if (stats#infinite or amount <= 0 or now >= stats#maxAmmo) None
        else Some({ ammo = Map.insert(w, Int32.min(stats#maxAmmo, now + amount), a#ammo) | a })

    /// 時刻 t に武器 w を拾う: 持っていなければ加えて弾を amount 足し（maxAmmo で止める）、その場で持ち替える。
    /// もう持っていれば弾を足すだけ（addAmmo と同じ・上限なら None）。
    pub def arm(doc: WeaponsDoc.Doc, vm: FpViewmodelDoc.Rec, t: Float64, w: Weapon, amount: Int32, a: Arsenal): Option[Arsenal] =
        if (owns(w, a)) addAmmo(doc, w, amount, a)
        else {
            let max = WeaponsDoc.statsOf(w, doc)#maxAmmo;
            let held = { owned = Set.insert(w, a#owned), ammo = Map.insert(w, Int32.min(max, ammoIn(w, a) + Int32.max(0, amount)), a#ammo) | a };
            Some(equip(vm, t, Choice.Slot(w), held))
        }

    /// 弾が尽きた時の持ち替え先: 持っている武器の並びを今の次から回り、最初に弾のある武器（無ければ None）。
    def fallbackOf(doc: WeaponsDoc.Doc, a: Arsenal): Option[Weapon] =
        let ring = WeaponsDoc.all() |> List.filter(w -> owns(w, a));
        let at = List.indexOf(a#current, ring) |> Option.getWithDefault(0);
        let n = List.length(ring);
        List.range(1, n) |> List.filterMap(k -> List.drop(Int32.modulo(at + k, Int32.max(1, n)), ring) |> List.head)
            |> List.find(w -> isLoaded(doc, w, a))

    /// 時刻 t に弾の尽きた武器で引き金を引いた（空撃ち）: 撃たずに間隔だけ空け（押し続けても空撃ちは間隔ごと）、
    /// 弾のある武器があれば持ち替える。撃てるかは呼ぶ側が canFire と isEmpty で見る。
    pub def dryFire(doc: WeaponsDoc.Doc, vm: FpViewmodelDoc.Rec, t: Float64, a: Arsenal): Arsenal =
        let waited = { readyAt = t + statsOf(doc, a)#interval | a };
        fallbackOf(doc, a) |> Option.map(w -> equip(vm, t, Choice.Slot(w), waited)) |> Option.getWithDefault(waited)

    /// 指示 c の行き先（持っていない・今と同じなら None）。
    def targetOf(c: Choice, a: Arsenal): Option[Weapon] =
        let ring = WeaponsDoc.all() |> List.filter(w -> owns(w, a));
        let n = List.length(ring);
        let at = List.indexOf(a#current, ring) |> Option.getWithDefault(0);
        let step = k -> List.drop(Int32.modulo(at + k, Int32.max(1, n)), ring) |> List.head;
        let picked = match c {
            case Choice.Keep     => None
            case Choice.Slot(w)  => if (owns(w, a)) Some(w) else None
            case Choice.Next     => step(1)
            case Choice.Previous => step(-1)
        };
        picked |> Option.filter(w -> w != a#current)

    /// 持ち替える（行き先が無ければそのまま）。持ち替えの間（drawSeconds）は撃てない。
    pub def equip(vm: FpViewmodelDoc.Rec, t: Float64, c: Choice, a: Arsenal): Arsenal =
        match targetOf(c, a) {
            case None    => a
            case Some(w) => { current = w, hands = Hands.Drawing(t), readyAt = Float64.max(a#readyAt, t + vm#drawSeconds) | a }
        }

    /// 引き金で撃とうとしているか（連射の武器は押している間・ほかは押したコマだけ）。
    pub def wantsToFire(stats: WeaponsDoc.Stats, trigger: Trigger): Bool =
        if (stats#automatic) trigger#held else trigger#pressed

    /// 時刻 t に撃てるか（間隔と持ち替えが済み・弾がある）。
    pub def canFire(doc: WeaponsDoc.Doc, t: Float64, a: Arsenal): Bool = isReady(t, a) and not isEmpty(doc, a)

    /// 時刻 t に間隔と持ち替えが済んでいるか（弾は見ない）。
    pub def isReady(t: Float64, a: Arsenal): Bool = t >= a#readyAt

    /// 時刻 t（このコマは dt 秒）に 1 回撃った後の状態（弾を 1 つ減らし、次を撃てる時刻を間隔だけ先へ）。撃てるかは呼ぶ側が canFire で見る。
    /// 撃てる時刻から 1 コマの内に撃った時（押し続けている連射）は、撃てる時刻から間隔を数える。
    // WhyNot: いつも t + interval にしない — 間隔がコマの長さで割り切れないと、毎回コマの境目まで遅れて連射が遅くなる（0.1 秒の連射が 60 Hz で 1 秒 9 発）。
    pub def fire(doc: WeaponsDoc.Doc, t: Float64, dt: Float64, a: Arsenal): Arsenal =
        let stats = statsOf(doc, a);
        let ammo = if (stats#infinite) a#ammo else Map.adjust(n -> Int32.max(0, n - 1), a#current, a#ammo);
        let since = if (t - a#readyAt < dt) a#readyAt else t;
        { ammo = ammo, readyAt = since + stats#interval, shots = a#shots + 1,
          last = Some({ weapon = a#current, at = t, index = a#shots }) | a }

    /// 時刻 t に持ち替えの最中か。
    pub def isDrawing(vm: FpViewmodelDoc.Rec, t: Float64, a: Arsenal): Bool = match a#hands {
        case Hands.Ready      => false
        case Hands.Drawing(s) => t - s < vm#drawSeconds
    }

    /// 時刻 t の反動で照準が跳ね上がっている角（度。撃った瞬間が recoil で、recoilRecover 秒で 0 へ戻る）。
    pub def punchAt(doc: WeaponsDoc.Doc, vm: FpViewmodelDoc.Rec, t: Float64, a: Arsenal): Float64 =
        a#last |> Option.map(s -> {
            let k = 1.0 - Num.clamp01((t - s#at) / Float64.max(0.001, vm#recoilRecover));
            WeaponsDoc.statsOf(s#weapon, doc)#recoil * k * k
        }) |> Option.getWithDefault(0.0)
}
