// Arsenal — 持っている武器・弾・連射の間隔・持ち替え・反動の規則（純粋）。
// 弾の当たりは Hitscan、粒は Particles3d。ここは「撃てるか」と「撃った後の状態」だけを決める。
// 時刻は遊びの時計の秒（ポーズの間は進まない）。値は WeaponsDoc（武器ごと）と HandsDoc（持ち替えと反動の戻り）。
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

    /// 始めの状態: Doc の owned の武器を持ち、始めの弾を持つ。構えているのは持っている武器の並びの最初（無ければ拳銃）。
    pub def initial(doc: WeaponsDoc.Doc): Arsenal =
        let owned = WeaponsDoc.all() |> List.filter(w -> WeaponsDoc.statsOf(w, doc)#owned);
        { current = List.head(owned) |> Option.getWithDefault(Weapon.Pistol), owned = List.toSet(owned),
          ammo = WeaponsDoc.all() |> List.map(w -> (w, WeaponsDoc.statsOf(w, doc)#ammo)) |> List.toMap,
          readyAt = 0.0, hands = Hands.Ready, shots = 0, last = None }

    /// 武器 w を持っているか。
    def owns(w: Weapon, a: Arsenal): Bool = Set.memberOf(w, a#owned)

    /// 構えている武器の値。
    pub def statsOf(doc: WeaponsDoc.Doc, a: Arsenal): WeaponsDoc.Stats = WeaponsDoc.statsOf(a#current, doc)

    /// 構えている武器の残りの弾（無限なら None）。
    pub def ammoOf(doc: WeaponsDoc.Doc, a: Arsenal): Option[Int32] =
        if (statsOf(doc, a)#infinite) None else Some(Map.getWithDefault(a#current, 0, a#ammo))

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
    pub def equip(vm: HandsDoc.Rec, t: Float64, c: Choice, a: Arsenal): Arsenal =
        match targetOf(c, a) {
            case None    => a
            case Some(w) => { current = w, hands = Hands.Drawing(t), readyAt = Float64.max(a#readyAt, t + vm#drawSeconds) | a }
        }

    /// 引き金で撃とうとしているか（連射の武器は押している間・ほかは押したコマだけ）。
    pub def wantsToFire(stats: WeaponsDoc.Stats, trigger: Trigger): Bool =
        if (stats#automatic) trigger#held else trigger#pressed

    /// 時刻 t に撃てるか（間隔と持ち替えが済み・弾がある）。
    pub def canFire(doc: WeaponsDoc.Doc, t: Float64, a: Arsenal): Bool =
        t >= a#readyAt and (ammoOf(doc, a) |> Option.forAll(n -> n > 0))

    /// 時刻 t に 1 回撃った後の状態（弾を 1 つ減らし、次を撃てる時刻を間隔だけ先へ）。撃てるかは呼ぶ側が canFire で見る。
    pub def fire(doc: WeaponsDoc.Doc, t: Float64, a: Arsenal): Arsenal =
        let stats = statsOf(doc, a);
        let ammo = if (stats#infinite) a#ammo else Map.adjust(n -> Int32.max(0, n - 1), a#current, a#ammo);
        { ammo = ammo, readyAt = t + stats#interval, shots = a#shots + 1,
          last = Some({ weapon = a#current, at = t, index = a#shots }) | a }

    /// 時刻 t に持ち替えの最中か。
    pub def isDrawing(vm: HandsDoc.Rec, t: Float64, a: Arsenal): Bool = match a#hands {
        case Hands.Ready      => false
        case Hands.Drawing(s) => t - s < vm#drawSeconds
    }

    /// 時刻 t の反動で照準が跳ね上がっている角（度。撃った瞬間が recoil で、recoilRecover 秒で 0 へ戻る）。
    pub def punchAt(doc: WeaponsDoc.Doc, vm: HandsDoc.Rec, t: Float64, a: Arsenal): Float64 =
        a#last |> Option.map(s -> {
            let k = 1.0 - Num.clamp01((t - s#at) / Float64.max(0.001, vm#recoilRecover));
            WeaponsDoc.statsOf(s#weapon, doc)#recoil * k * k
        }) |> Option.getWithDefault(0.0)
}
