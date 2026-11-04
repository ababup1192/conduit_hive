// Spawner — 迷路の spawn の印と spawns.json の wave から、区画ごとの wave の並び・次の wave を始めるか・1 体を湧かせる印を決める（純粋）。
// 印は湧く所だけを持ち、何がいつ何体湧くかは SpawnsDoc が正。区画が迷路に無い wave・湧く区画に印が無い wave は 1 行知らせて捨てる。
// wave は区画に入ると順に始まる: 前の wave（最初は入った時）から after 秒が過ぎるか、2 つ目からはその区画の残りが whenLeft 以下になった時。
// 始まった wave は湧くのを待つ列（Queued）に並び、Horde が上限と間隔を見て 1 体ずつ湧かせる。
// 1 体を湧かせる印は、プレイヤーから minDistance より遠く、見えていない印を選ぶ（見えている印しか無ければ遠い印・遠い印も無ければその区画で一番遠い印）。
mod Spawner {
    use fge::{Hash01, Log, Num}
    use Creatures.Kind

    /// spawn の点 1 つ: 区画・印のマスの真ん中。
    pub type alias Point = { zone = Char, x = Float64, z = Float64 }

    /// 区画の wave 1 つ（湧く印の区画を決めた後）: melee と ranged の数・湧く印の区画・始まる秒・始まる残りの数。
    pub type alias Wave = { melee = Int32, ranged = Int32, source = Char, after = Float64, whenLeft = Int32 }

    /// 区画 → wave の並び。
    pub type alias Plans = Map[Char, List[Wave]]

    /// 湧くのを待っている 1 体: 型・数える区画（wave の区画）・湧く印の区画。
    pub type alias Queued = { kind = Kind, home = Char, source = Char }

    /// 区画の wave の進み: 始めた wave の数・最後に wave を始めた時刻（まだ無ければ区画に入った時刻）。
    pub type alias Progress = { started = Int32, at = Float64 }

    /// プレイヤーの見え方: 足元・向き（ラジアン。0 が +Z・正で +X の側）・目から床の上の点 (x, z) までが壁に遮られないか。
    pub type alias Viewer = { x = Float64, z = Float64, yaw = Float64, lineOfSight = (Float64, Float64) -> Bool }

    /// 湧く所の決め方: 近すぎる距離（m）・印のマスの中で散らす幅（m）。
    pub type alias Placing = { minDistance = Float64, scatter = Float64 }

    /// 迷路の spawn の印の点の列（床でないマスの印は置かない）。
    pub def pointsOf(m: Maze.Maze): List[Point] =
        m#marks |> List.filter(mk -> mk#kind == MazeDoc.MarkKind.Spawn) |> List.filterMap(mk -> {
            let cell = { col = mk#col, row = mk#row };
            match Map.get(Maze.charAt(m, cell), m#zones) {
                case None    => Log.warnThen("[spawn] 印 (${mk#col}, ${mk#row}) は床のマスに無いので置かない", None)
                case Some(z) =>
                    let (x, cz) = Maze.centerOf(m, cell);
                    Some({ zone = z#id, x = x, z = cz })
            }
        })

    /// spawns.json の wave を区画ごとの並びにする（区画が迷路に無い wave・湧く区画に印の無い wave は 1 行知らせて捨てる）。
    pub def plansOf(m: Maze.Maze, points: List[Point], doc: SpawnsDoc.Doc): Plans =
        let marked = points |> List.map(p -> p#zone) |> List.toSet;
        SpawnsDoc.rec(doc)#waves |> List.filterMap(w -> {
            let source = w#source |> Option.getWithDefault(w#zone);
            if (not Map.memberOf(w#zone, m#zones)) Log.warnThen("[spawn] wave の区画 '${w#zone}' は迷路に無いので湧かせない", None)
            else if (not Set.memberOf(source, marked)) Log.warnThen("[spawn] 区画 '${source}' に spawn の印が無いので、'${w#zone}' の wave は湧かせない", None)
            else Some((w#zone, { melee = Int32.max(0, w#melee), ranged = Int32.max(0, w#ranged), source = source,
                                 after = Float64.max(0.0, w#after), whenLeft = w#whenLeft }))
        }) |> List.foldRight((e, acc) -> Map.insertWith((earlier, later) -> List.append(earlier, later), fst(e), snd(e) :: Nil, acc), Map.empty())

    /// 区画の wave の数を count まで切り詰めた並び（count が 0 以下なら切り詰めない）。
    pub def limitWaves(zone: Char, count: Int32, plans: Plans): Plans =
        if (count <= 0) plans else Map.adjust(List.take(count), zone, plans)

    /// 時刻 t に次の wave を始めるなら、その wave（left = その区画の生きている数 + 湧くのを待っている数）。
    pub def nextWave(plan: List[Wave], t: Float64, left: Int32, p: Progress): Option[Wave] =
        List.nth(p#started, plan) |> Option.filter(w -> t - p#at >= w#after or (p#started >= 1 and left <= w#whenLeft))

    /// 区画 zone の wave 1 つ分の湧くのを待つ列（ranged は列の中にならして混ぜる）。
    pub def queueOf(zone: Char, w: Wave): List[Queued] =
        let total = w#melee + w#ranged;
        List.range(0, total) |> List.map(i -> {
            let ranged = (i + 1) * w#ranged / total > i * w#ranged / total;
            { kind = if (ranged) Kind.Ranged else Kind.Melee, home = zone, source = w#source }
        })

    def distance2(v: Viewer, p: Point): Float64 = (p#x - v#x) * (p#x - v#x) + (p#z - v#z) * (p#z - v#z)

    /// 見回さずに見える角の半分（度）。
    // WhyNot: 歩く Doc の画角から計算しない — 画角 70° の 16:9 の横の半分は約 51° で、見回しの遅れと振り向きの途中を含めて広めに取る。
    def viewHalfAngle(): Float64 = 65.0

    /// プレイヤーから点が見えているか: 向きから viewHalfAngle の内で、目から壁に遮られない。
    def isSeen(v: Viewer, p: Point): Bool =
        let (dx, dz) = (p#x - v#x, p#z - v#z);
        let length = Num.sqrt(dx * dx + dz * dz);
        let ahead = if (length < 0.001) 1.0 else (dx * Num.sin(v#yaw) + dz * Num.cos(v#yaw)) / length;
        ahead >= Num.cos(viewHalfAngle() * Num.pi() / 180.0) and v#lineOfSight(p#x, p#z)

    /// 区画 source の印から 1 体を湧かせる床の上の点（印が無ければ None）。seed で印を順に回し、散らし方を決める。
    pub def placeOf(rules: Placing, v: Viewer, source: Char, seed: Int32, points: List[Point]): Option[(Float64, Float64)] =
        let here = points |> List.filter(p -> p#zone == source);
        let far = here |> List.filter(p -> distance2(v, p) >= rules#minDistance * rules#minDistance);
        let hidden = far |> List.filter(p -> not isSeen(v, p));
        let farthest = here |> List.foldLeft((best, p) -> if (best |> Option.forAll(b -> distance2(v, p) > distance2(v, b))) Some(p) else best, None);
        let pool = if (List.nonEmpty(hidden)) hidden else if (List.nonEmpty(far)) far else Option.toList(farthest);
        List.nth(Int32.modulo(seed, Int32.max(1, List.length(pool))), pool) |> Option.map(p ->
            (p#x + (Hash01.at(seed, 71) - 0.5) * rules#scatter, p#z + (Hash01.at(seed, 72) - 0.5) * rules#scatter))
}
