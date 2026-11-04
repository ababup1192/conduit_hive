// Horde — 敵の群れと projectile の状態と、1 コマ進める規則（純粋）。
//
// ── 1 コマ（step）──
//   1. 湧く予定（Spawner）の時刻が来た敵を出す
//   2. 距離の地図（FlowField）を fieldInterval 秒に 1 回だけ、プレイヤーのマスから塗り直す（全員で共有）
//   3. 敵ごとに考える: 追う（地図の隣のマスを読んで進む）・振る / 吐く・よろける・倒れる
//   4. 押し合い: マス → そのマスにいる敵の Map を 1 回作り、同じマスと隣のマスの敵とだけ押し離す。プレイヤーの体からも離す。最後に壁から押し出す
//   5. projectile を進める: 壁で弾け、プレイヤーに当たればダメージ、寿命で消える
//   6. 倒れて corpseSeconds が過ぎた敵を消す
// プレイヤーが受けたダメージと弾けた所を Outcome で返し、体力と粒は World が持つ。
//
// melee は attackRange の内で attack のクリップを始め、hitTime の瞬間にプレイヤーが前の扇（reach・arc）の内ならダメージ。
// ranged は keepDistance を保ち、壁の箱へレイを当てて見通しがある時だけ attack を始め、hitTime の瞬間に口から projectile を吐く。
// 撃たれると（wound）体力が減り、追っている途中ならよろけ（hit のクリップ）、0 で倒れる（die のクリップ）。振っている途中はよろけない。
mod Horde {
    use fge::{CollisionShape3d, CollisionWorld3d, Hash01, Mat4, Num, Ray3d, Vec3}
    use Creatures.{Clip, Kind}

    /// 敵のしている事。Attack・Hurt・Dying はその時刻から。
    pub enum Act with Eq, ToString {
        case Chase
        case Attack(Float64)
        case Hurt(Float64)
        case Dying(Float64)
    }

    /// 敵 1 体。readyAt = 次の攻撃を始められる時刻・moving = このコマに歩いたか（walk と idle を分ける）・home = 湧いた部屋。
    pub type alias Enemy = {
        id = Int32,
        kind = Kind,
        home = Char,
        x = Float64,
        z = Float64,
        yaw = Float64,
        health = Float64,
        act = Act,
        readyAt = Float64,
        moving = Bool,
        anim = Creatures.Anim
    }

    /// 飛んでいる projectile。at = 今の点・velocity = m/秒・born = 吐いた時刻。
    pub type alias Projectile = { id = Int32, at = Vec3.Vec3, velocity = Vec3.Vec3, born = Float64 }

    /// 群れ。triggered = 湧かせ終えた部屋・fieldAt = 地図を塗った時刻・nextId = 次に出す敵と projectile の番号。
    pub type alias Horde = {
        enemies = List[Enemy],
        projectiles = List[Projectile],
        pending = List[Spawner.Pending],
        triggered = Set[Char],
        field = FlowField.FlowField,
        fieldAt = Float64,
        nextId = Int32
    }

    /// 敵が見るプレイヤー: 足元・目・体の半径と高さ。
    pub type alias Player = { x = Float64, feet = Float64, z = Float64, eye = Vec3.Vec3, radius = Float64, height = Float64 }

    /// 当たった所と、その面の向き（粒を出す）。
    pub type alias Splash = { point = Vec3.Vec3, normal = Vec3.Vec3 }

    /// 1 コマの結果: 次の群れ・プレイヤーが受けたダメージの合計・projectile が弾けた所。
    pub type alias Outcome = { horde = Horde, damage = Float64, splashes = List[Splash] }

    /// 何もいない群れ。
    pub def empty(): Horde =
        { enemies = Nil, projectiles = Nil, pending = Nil, triggered = Set.empty(), field = FlowField.empty(), fieldAt = -1000.0, nextId = 0 }

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    def doc(res: Res.Res): EnemiesDoc.Rec = EnemiesDoc.rec(res#enemies)

    // ── 読む口 ──

    /// 倒れていない敵か。
    def isAlive(e: Enemy): Bool = match e#act {
        case Act.Dying(_) => false
        case _            => true
    }

    /// 倒れていない敵の数。
    pub def aliveCount(h: Horde): Int32 = h#enemies |> List.count(isAlive)

    /// 湧く予定が残っているか、倒れていない敵がいる部屋。
    pub def zonesInPlay(h: Horde): Set[Char] =
        List.append(h#enemies |> List.filter(isAlive) |> List.map(e -> e#home), h#pending |> List.map(p -> p#home)) |> List.toSet

    /// 敵 id（いなければ None）。
    pub def enemyOf(id: Int32, h: Horde): Option[Enemy] = h#enemies |> List.find(e -> e#id == id)

    /// 足元の world の行列。
    pub def worldOf(e: Enemy): Mat4.Mat4 = Creatures.worldOf(e#x, e#z, e#yaw)

    // ── 湧かせる ──

    /// 部屋 zone に入った: まだ湧かせていない部屋なら、その部屋の spawn の点から時刻 t に始まる予定を足す（1 部屋 1 回だけ）。
    pub def enter(res: Res.Res, zone: Char, t: Float64, h: Horde): Horde =
        if (Set.memberOf(zone, h#triggered)) h
        else { triggered = Set.insert(zone, h#triggered), pending = List.append(h#pending, Spawner.scheduleOf(res#spawnPoints, zone, t)) | h }

    /// 時刻を待たずに敵を出す（描き出しの場面・測り・テスト）。向きは yaw（ラジアン）。
    pub def spawnNow(res: Res.Res, spawns: List[{ kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }], h: Horde): Horde =
        let born = spawns |> List.zipWithIndex |> List.map(e -> { let (i, sp) = e; newEnemy(res, h#nextId + i, sp) });
        { enemies = List.append(h#enemies, born), nextId = h#nextId + List.length(born) | h }

    def newEnemy(res: Res.Res, id: Int32, s: { kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }): Enemy =
        { id = id, kind = s#kind, home = s#home, x = s#x, z = s#z, yaw = s#yaw, health = healthOf(doc(res), s#kind),
          act = Act.Chase, readyAt = 0.0, moving = true, anim = Creatures.walkAnim() }

    def healthOf(d: EnemiesDoc.Rec, k: Kind): Float64 = match k {
        case Kind.Melee  => d#melee#health
        case Kind.Ranged => d#ranged#health
    }

    /// 時刻 t までに湧く予定の敵を出す（プレイヤーの方を向いて立つ）。
    def release(res: Res.Res, t: Float64, p: Player, h: Horde): Horde =
        let (due, later) = h#pending |> List.partition(s -> s#at <= t);
        spawnNow(res, due |> List.map(s -> { kind = s#kind, x = s#x, z = s#z, yaw = facing(s#x, s#z, p#x, p#z), home = s#home }), { pending = later | h })

    /// 死んでやり直す時: 敵と projectile と湧く予定を全部消し、zones の部屋をもう一度湧かせられるようにする。
    pub def rearm(zones: Set[Char], h: Horde): Horde =
        { enemies = Nil, projectiles = Nil, pending = Nil, triggered = Set.difference(h#triggered, zones), field = FlowField.empty(), fieldAt = -1000.0 | h }

    // ── 撃たれる ──

    /// 時刻 t に、1 粒の威力 damage の弾が impacts に当たった（頭は headMultiplier 倍）。同じ敵に何粒当たっても 1 回の傷として足す。
    pub def wound(res: Res.Res, t: Float64, damage: Float64, impacts: List[Hitscan.Impact], h: Horde): Horde =
        let d = doc(res);
        let taken = impacts |> List.foldLeft((acc, hit) -> match hit#struck {
            case Hitscan.Struck.Enemy(id, part) =>
                Map.insertWith((a, b) -> a + b, id, damage * (if (part == Hitscan.Part.Head) d#headMultiplier else 1.0), acc)
            case _ => acc
        }, Map.empty());
        { enemies = h#enemies |> List.map(e -> Map.get(e#id, taken) |> Option.map(amount -> hurt(t, amount, e)) |> Option.getWithDefault(e)) | h }

    def hurt(t: Float64, amount: Float64, e: Enemy): Enemy =
        let health = e#health - amount;
        let act = match e#act {
            case Act.Dying(_) => e#act
            case _ if health <= 0.0 => Act.Dying(t)
            case Act.Attack(_) => e#act
            case _ => Act.Hurt(t)
        };
        animated(t, { health = health, act = act, moving = false | e })

    /// 弾の的: 倒れていない敵の頭の球と体のカプセル（頭が前）。
    pub def targetsOf(h: Horde): List[(Hitscan.Struck, Ray3d.RayTarget)] =
        h#enemies |> List.filter(isAlive) |> List.flatMap(e -> {
            let box = Creatures.hitboxOf(e#kind);
            let world = worldOf(e);
            let feet = Mat4.apply(world, box#feet);
            (Hitscan.Struck.Enemy(e#id, Hitscan.Part.Head),
                Ray3d.RayTarget.Shape(CollisionShape3d.SphereShape3d({ center = Mat4.apply(world, box#head), radius = box#headRadius })))
            :: (Hitscan.Struck.Enemy(e#id, Hitscan.Part.Body),
                Ray3d.RayTarget.Shape(CollisionShape3d.CapsuleShape3d({ feet = feet, radius = box#radius, height = box#height })))
            :: Nil
        })

    // ── 1 コマ ──

    /// 時刻 t（このコマに dt 秒進んだ）に群れを進める。
    pub def step(res: Res.Res, t: Float64, dt: Float64, p: Player, h: Horde): Outcome =
        let d = doc(res);
        let released = release(res, t, p, h);
        let fielded = refreshField(res, t, p, released);
        let corpses = fielded#enemies |> List.filter(e -> not isGone(d, t, e));
        let thought = corpses |> List.foldLeft((acc, e) -> {
            let room = d#projectile#limit - List.length(fielded#projectiles) - List.length(acc#spits);
            let r = think(res, fielded#field, t, dt, p, room > 0, e);
            { enemies = r#enemy :: acc#enemies, damage = acc#damage + r#damage, spits = List.append(r#spit |> Option.toList, acc#spits) }
        }, { enemies = Nil, damage = 0.0, spits = Nil });
        let launched = thought#spits |> List.foldLeft((acc, sp) -> launch(sp#at, sp#velocity, t, acc), fielded);
        let flying = flyAll(res, t, dt, p, launched#projectiles);
        let settled = settle(res, p, List.reverse(thought#enemies));
        { horde = { enemies = settled, projectiles = flying#projectiles | launched },
          damage = thought#damage + flying#damage, splashes = flying#splashes }

    /// 同じ dt で frames コマ進めた結果（時刻 start の次のコマから。受けたダメージと弾けた所は足し合わせる）。
    pub def simulate(res: Res.Res, start: Float64, dt: Float64, frames: Int32, p: Player, h: Horde): Outcome =
        List.range(1, frames + 1) |> List.foldLeft((acc, i) -> {
            let o = step(res, start + Int32.toFloat64(i) * dt, dt, p, acc#horde);
            { horde = o#horde, damage = acc#damage + o#damage, splashes = List.append(o#splashes, acc#splashes) }
        }, { horde = h, damage = 0.0, splashes = Nil })

    /// 時刻 t に点 at から velocity（m/秒）で projectile を飛ばす。
    pub def launch(at: Vec3.Vec3, velocity: Vec3.Vec3, t: Float64, h: Horde): Horde =
        { projectiles = List.append(h#projectiles, { id = h#nextId, at = at, velocity = velocity, born = t } :: Nil), nextId = h#nextId + 1 | h }

    /// 倒れてから corpseSeconds が過ぎたか。
    def isGone(d: EnemiesDoc.Rec, t: Float64, e: Enemy): Bool = match e#act {
        case Act.Dying(at) => t - at >= d#corpseSeconds
        case _             => false
    }

    /// 地図を塗り直す時刻が来ていれば、プレイヤーのマスから塗り直す。
    def refreshField(res: Res.Res, t: Float64, p: Player, h: Horde): Horde =
        if (t - h#fieldAt < doc(res)#fieldInterval and Option.nonEmpty(h#field#goal)) h
        else { field = FlowField.build(res#maze, Maze.cellAt(res#maze, p#x, p#z)), fieldAt = t | h }

    // ── 考える ──

    /// 敵 1 体の 1 コマの結果: 次の敵・プレイヤーへのダメージ・吐いた projectile（点と速さ）。
    type alias Thought = { enemy = Enemy, damage = Float64, spit = Option[{ at = Vec3.Vec3, velocity = Vec3.Vec3 }] }

    def still(e: Enemy): Thought = { enemy = e, damage = 0.0, spit = None }

    def think(res: Res.Res, field: FlowField.FlowField, t: Float64, dt: Float64, p: Player, canSpit: Bool, e: Enemy): Thought =
        let r = match e#act {
            case Act.Chase     => chase(res, field, t, dt, p, canSpit, e)
            case Act.Attack(s) => swing(res, t, dt, p, s, e)
            case Act.Hurt(s)   => still(if (t - s >= Creatures.secondsOf(res#timing, e#kind, Clip.Hit)) { act = Act.Chase | e } else { moving = false | e })
            case Act.Dying(_)  => still(e)
        };
        { enemy = animated(t, r#enemy) | r }

    /// 今のしている事に合うクリップへ替える。
    def animated(t: Float64, e: Enemy): Enemy =
        let track = match e#act {
            case Act.Chase     => { clip = if (e#moving) Clip.Walk else Clip.Idle, start = 0.0 }
            case Act.Attack(s) => { clip = Clip.Attack, start = s }
            case Act.Hurt(s)   => { clip = Clip.Hit, start = s }
            case Act.Dying(s)  => { clip = Clip.Die, start = s }
        };
        { anim = Creatures.play(track, t, e#anim) | e }

    def distance(dx: Float64, dz: Float64): Float64 = Num.sqrt(dx * dx + dz * dz)

    /// (x, z) から (tx, tz) を向く角（ラジアン。0 が +Z・正で +X の側）。
    def facing(x: Float64, z: Float64, tx: Float64, tz: Float64): Float64 = Num.atan2(tx - x, tz - z)

    /// 向きを target へ、1 コマで maxStep（ラジアン）まで回す。
    def turnToward(current: Float64, target: Float64, maxStep: Float64): Float64 =
        let diff = Num.atan2(Num.sin(target - current), Num.cos(target - current));
        current + Num.clamp(0.0 - maxStep, maxStep, diff)

    /// 1 秒に回れる角（ラジアン）。
    def turnRate(): Float64 = 10.0

    /// 追う: 攻撃を始められるなら始め、ほかは地図を読んで進む（ranged は保つ距離の内なら止まって構え、近すぎれば下がる）。
    def chase(res: Res.Res, field: FlowField.FlowField, t: Float64, dt: Float64, p: Player, canSpit: Bool, e: Enemy): Thought =
        let d = doc(res);
        let dist = distance(p#x - e#x, p#z - e#z);
        let toPlayer = facing(e#x, e#z, p#x, p#z);
        let ready = t >= e#readyAt;
        match e#kind {
            case Kind.Melee if ready and dist <= d#melee#attackRange =>
                still({ act = Act.Attack(t), moving = false, yaw = toPlayer | e })
            case Kind.Melee if dist <= d#melee#attackRange * 0.8 =>
                still({ moving = false, yaw = turnToward(e#yaw, toPlayer, turnRate() * dt) | e })
            case Kind.Melee => still(advance(res, field, dt, p, d#melee#speed, e))
            case Kind.Ranged if ready and canSpit and dist <= d#ranged#sightRange and hasSight(res, e, p) =>
                still({ act = Act.Attack(t), moving = false, yaw = toPlayer | e })
            case Kind.Ranged if dist > d#ranged#keepDistance + 1.0 => still(advance(res, field, dt, p, d#ranged#speed, e))
            case Kind.Ranged if dist < d#ranged#keepDistance - 1.5 and dist > 0.001 =>
                let step = d#ranged#speed * dt / dist;
                still({ x = e#x - (p#x - e#x) * step, z = e#z - (p#z - e#z) * step, moving = true, yaw = turnToward(e#yaw, toPlayer, turnRate() * dt) | e })
            case Kind.Ranged => still({ moving = false, yaw = turnToward(e#yaw, toPlayer, turnRate() * dt) | e })
        }

    /// 地図を読んで speed で 1 コマ進む。プレイヤーと同じマスか隣のマスならまっすぐプレイヤーへ。
    def advance(res: Res.Res, field: FlowField.FlowField, dt: Float64, p: Player, speed: Float64, e: Enemy): Enemy =
        let m = res#maze;
        let cell = Maze.cellAt(m, e#x, e#z);
        let direct = FlowField.stepsAt(field, cell) |> Option.exists(s -> s <= 1);
        let (gx, gz) = if (direct) (p#x, p#z)
            else FlowField.downhill(m, field, cell) |> Option.map(Maze.centerOf(m)) |> Option.getWithDefault((p#x, p#z));
        let dist = distance(gx - e#x, gz - e#z);
        if (dist < 0.001) { moving = false | e }
        else {
            let stride = Float64.min(dist, speed * dt);
            { x = e#x + (gx - e#x) / dist * stride, z = e#z + (gz - e#z) / dist * stride, moving = true,
              yaw = turnToward(e#yaw, facing(e#x, e#z, gx, gz), turnRate() * dt) | e }
        }

    /// 敵の口からプレイヤーの目まで、壁の箱に遮られずに線が引けるか。
    def hasSight(res: Res.Res, e: Enemy, p: Player): Bool =
        let mouth = Mat4.apply(worldOf(e), Creatures.hitboxOf(e#kind)#mouth);
        let toward = Vec3.sub(p#eye, mouth);
        let length = Vec3.length(toward);
        let ray = Ray3d.ray3d(mouth, toward);
        let middle = Vec3.add(mouth, Vec3.mul(toward, 0.5));
        CollisionWorld3d.boxesNear(res#collision, middle, length * 0.5 + 0.5)
            |> List.forAll(b -> Option.isEmpty(Ray3d.hitBox(ray, length, b)))

    /// 振る・吐く: 当たる時刻を越えたコマに 1 回だけ当てる・吐く。クリップが終われば追うへ戻る（次を始められるのは cooldown の後）。
    def swing(res: Res.Res, t: Float64, dt: Float64, p: Player, start: Float64, e: Enemy): Thought =
        let d = doc(res);
        let elapsed = t - start;
        let hitTime = match e#kind {
            case Kind.Melee  => d#melee#hitTime
            case Kind.Ranged => d#ranged#hitTime
        };
        let crossed = elapsed - dt < hitTime and hitTime <= elapsed;
        let aimed = if (elapsed < hitTime) { yaw = turnToward(e#yaw, facing(e#x, e#z, p#x, p#z), turnRate() * dt) | e } else e;
        let done = elapsed >= Creatures.secondsOf(res#timing, e#kind, Clip.Attack);
        let cooldown = match e#kind {
            case Kind.Melee  => d#melee#cooldown
            case Kind.Ranged => d#ranged#cooldown
        };
        let next = if (done) { act = Act.Chase, readyAt = t + cooldown | aimed } else aimed;
        match e#kind {
            case Kind.Melee  => { enemy = next, damage = if (crossed and isInSwing(d#melee, aimed, p)) d#melee#damage else 0.0, spit = None }
            case Kind.Ranged => { enemy = next, damage = 0.0, spit = if (crossed) Some(spitOf(d#projectile, aimed, p)) else None }
        }

    /// melee の振り下ろしの扇の内か: 足元からプレイヤーの体の縁までが reach の内で、向きから arc の半分の角の内。
    pub def isInSwing(m: EnemiesDoc.Melee, e: Enemy, p: Player): Bool =
        let dx = p#x - e#x;
        let dz = p#z - e#z;
        let dist = distance(dx, dz);
        let ahead = if (dist < 0.001) 1.0 else (dx * Num.sin(e#yaw) + dz * Num.cos(e#yaw)) / dist;
        dist - p#radius <= m#reach and ahead >= Num.cos(rad(m#arc) * 0.5)

    /// 口からプレイヤーの胸へ向けて吐く projectile の点と速さ。
    def spitOf(pr: EnemiesDoc.Projectile, e: Enemy, p: Player): { at = Vec3.Vec3, velocity = Vec3.Vec3 } =
        let mouth = Mat4.apply(worldOf(e), Creatures.hitboxOf(e#kind)#mouth);
        let chest = Vec3.v3(p#x, p#eye#y - 0.3, p#z);
        { at = mouth, velocity = Vec3.mul(Vec3.normalized(Vec3.sub(chest, mouth)), pr#speed) }

    // ── projectile ──

    type alias Flight = { projectiles = List[Projectile], damage = Float64, splashes = List[Splash] }

    def flyAll(res: Res.Res, t: Float64, dt: Float64, p: Player, ps: List[Projectile]): Flight =
        let pr = doc(res)#projectile;
        ps |> List.foldLeft((acc, x) -> {
            let next = Vec3.add(x#at, Vec3.mul(x#velocity, dt));
            match wallHit(res, x#at, next) {
                case Some(hit) => { splashes = { point = hit#point, normal = hit#normal } :: acc#splashes | acc }
                case None if touchesPlayer(pr, p, next) =>
                    { damage = acc#damage + pr#damage, splashes = { point = next, normal = Vec3.normalized(Vec3.mul(x#velocity, -1.0)) } :: acc#splashes | acc }
                case None if t - x#born >= pr#life => acc
                case None => { projectiles = { at = next | x } :: acc#projectiles | acc }
            }
        }, { projectiles = Nil, damage = 0.0, splashes = Nil })
            |> (f -> { projectiles = List.reverse(f#projectiles) | f })

    /// from から to へ進む間に当たる壁の箱（一番近い所）。
    def wallHit(res: Res.Res, origin: Vec3.Vec3, target: Vec3.Vec3): Option[Ray3d.RayHit] =
        let toward = Vec3.sub(target, origin);
        let length = Vec3.length(toward);
        let ray = Ray3d.ray3d(origin, toward);
        CollisionWorld3d.boxesNear(res#collision, origin, length + 0.5)
            |> List.filterMap(b -> Ray3d.hitBox(ray, length, b))
            |> List.foldLeft((best, h) -> match best {
                case Some(b) if b#distance <= h#distance => best
                case _ => Some(h)
            }, None)

    /// 点 at の projectile がプレイヤーの体（足元から高さまでの縦の筒）に触れているか。
    def touchesPlayer(pr: EnemiesDoc.Projectile, p: Player, at: Vec3.Vec3): Bool =
        distance(at#x - p#x, at#z - p#z) <= p#radius + pr#radius and at#y >= p#feet - pr#radius and at#y <= p#feet + p#height + pr#radius

    // ── 押し合いと壁 ──

    /// マス (列, 行)。
    def cellKey(res: Res.Res, x: Float64, z: Float64): (Int32, Int32) =
        let c = Maze.cellAt(res#maze, x, z);
        (c#col, c#row)

    /// 押し合い・プレイヤーの体から離す・壁から押し出す（倒れた敵は動かさない）。
    def settle(res: Res.Res, p: Player, enemies: List[Enemy]): List[Enemy] =
        let byCell = enemies |> List.filter(isAlive)
            |> List.foldLeft((m, e) -> Map.insertWith((a, b) -> List.append(b, a), cellKey(res, e#x, e#z), e :: Nil, m), Map.empty());
        enemies |> List.map(e -> if (isAlive(e)) walled(res, apart(res, p, byCell, e)) else e)

    /// 同じマスと隣のマスの敵から、重なった分の半分ずつ離す。プレイヤーの体からは重なった分を全部離す。
    def apart(res: Res.Res, p: Player, byCell: Map[(Int32, Int32), List[Enemy]], e: Enemy): Enemy =
        let (col, row) = cellKey(res, e#x, e#z);
        let r = Creatures.footprintOf(e#kind);
        let others = List.range(-1, 2) |> List.flatMap(dr -> List.range(-1, 2) |> List.flatMap(dc -> Map.getWithDefault((col + dc, row + dr), Nil, byCell)))
            |> List.filter(o -> o#id != e#id);
        let push = others |> List.foldLeft((acc, o) -> {
            let (px, pz) = acc;
            let (ax, az) = awayFrom(e#id, o#id, e#x - o#x, e#z - o#z, r + Creatures.footprintOf(o#kind), 0.5);
            (px + ax, pz + az)
        }, (0.0, 0.0));
        let (bx, bz) = awayFrom(e#id, -1, e#x - p#x, e#z - p#z, r + p#radius, 1.0);
        { x = e#x + fst(push) + bx, z = e#z + snd(push) + bz | e }

    /// 間 (dx, dz) が reach より近い時に離すずれ（重なった分 × share）。ちょうど同じ点なら番号から決まった向きへ。
    def awayFrom(self: Int32, other: Int32, dx: Float64, dz: Float64, reach: Float64, share: Float64): (Float64, Float64) =
        let d = distance(dx, dz);
        if (d >= reach) (0.0, 0.0)
        else if (d < 0.0001) {
            let a = Hash01.at(Int32.min(self, other) * 977 + Int32.max(self, other), 73) * Num.tau() + (if (self < other) 0.0 else Num.pi());
            (Num.sin(a) * reach * share, Num.cos(a) * reach * share)
        }
        else ((dx / d) * (reach - d) * share, (dz / d) * (reach - d) * share)

    /// 壁と立てた物の箱から押し出す（足元の円を腰の高さの球で見る）。
    def walled(res: Res.Res, e: Enemy): Enemy =
        let r = Creatures.footprintOf(e#kind);
        let center = Vec3.v3(e#x, 1.0, e#z);
        let moved = CollisionWorld3d.boxesNear(res#collision, center, r + 0.1) |> List.foldLeft((at, b) ->
            CollisionShape3d.pushOutHorizontal(b, at, r) |> Option.map(Vec3.add(at)) |> Option.getWithDefault(at), center);
        { x = moved#x, z = moved#z | e }
}
