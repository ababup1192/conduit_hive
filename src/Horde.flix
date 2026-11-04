// Horde — 敵の群れの状態と、1 コマ進める規則（純粋）。projectile を進めるのは Projectiles・押し合いと壁は Separation。
//
// ── 1 コマ（step）──
//   1. 湧く予定（Spawner）の時刻が来た敵を出す
//   2. 距離の地図（FlowField）を fieldInterval 秒に 1 回だけ、プレイヤーのマスから塗り直す（全員で共有）
//   3. 倒れて corpseSeconds が過ぎた敵を消し、残りが考える: 追う（地図の隣のマスを読んで進む）・振る / 吐く・よろける
//   4. 吐いた projectile を足して進める（Projectiles）
//   5. 押し合いと壁（Separation）
// プレイヤーが受けたダメージ・弾けた所・起きた事を Outcome で返し、体力と粒と音は World が持つ。
//
// melee は attackRange の内で attack のクリップを始め、始めてから hitTime を過ぎた最初のコマに 1 回だけ、プレイヤーが前の扇（reach・arc）の内ならダメージ。
// ranged は keepDistance を保ち、壁の箱へレイを当てて見通しがある時だけ attack を始め、hitTime を過ぎた最初のコマに口から projectile を吐く
// （その時に飛んでいる数が上限なら吐かない）。
// 撃たれると（applyDamage）体力が減り、追っている途中で staggerCooldown が明けていればよろけ（hit のクリップ）、0 で倒れる（die のクリップ）。
mod Horde {
    use fge::{CollisionShape3d, CollisionWorld3d, Mat4, Num, Ray3d, Vec3}
    use Creatures.{Clip, Kind}
    use Events.Event

    /// 敵のしている事。Attack = 始めた時刻と、当てた（吐いた）か・Hurt と Dying はその時刻から。
    pub enum Act with Eq, ToString {
        case Chase
        case Attack(Float64, Bool)
        case Hurt(Float64)
        case Dying(Float64)
    }

    /// 敵 1 体。readyAt = 次の攻撃を始められる時刻・staggerReadyAt = 次によろけられる時刻・moving = このコマに歩いたか（walk と idle を分ける）・
    /// home = 湧いた部屋。
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
        staggerReadyAt = Float64,
        moving = Bool,
        anim = Creatures.Anim
    }

    /// 群れ。triggered = 湧かせ終えた部屋・fieldAt = 地図を塗った時刻・nextId = 次に出す敵と projectile の番号。
    pub type alias Horde = {
        enemies = List[Enemy],
        projectiles = List[Projectiles.Projectile],
        pending = List[Spawner.Pending],
        triggered = Set[Char],
        field = FlowField.FlowField,
        fieldAt = Float64,
        nextId = Int32
    }

    /// 1 コマの結果: 次の群れ・プレイヤーが受けたダメージの合計・projectile が弾けた所・起きた事。
    pub type alias Outcome = { horde = Horde, damage = Float64, splashes = List[Projectiles.Splash], events = List[Event] }

    /// 撃たれた結果: 次の群れと起きた事（当たった・倒れた）。
    pub type alias Damaged = { horde = Horde, events = List[Event] }

    /// 何もいない群れ。
    pub def empty(): Horde =
        { enemies = Nil, projectiles = Nil, pending = Nil, triggered = Set.empty(), field = FlowField.empty(), fieldAt = -1000.0, nextId = 0 }

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    def doc(res: Res.Res): EnemiesDoc.Rec = EnemiesDoc.rec(res#enemies)

    // ── 読む口 ──

    def isAlive(e: Enemy): Bool = match e#act {
        case Act.Dying(_) => false
        case _            => true
    }

    /// 倒れていない敵の数。
    pub def aliveCount(h: Horde): Int32 = h#enemies |> List.count(isAlive)

    /// 倒れていない敵。
    pub def aliveEnemies(h: Horde): List[Enemy] = h#enemies |> List.filter(isAlive)

    /// 湧く予定が残っているか、倒れていない敵がいる部屋。
    pub def zonesInPlay(h: Horde): Set[Char] =
        List.append(h#enemies |> List.filter(isAlive) |> List.map(e -> e#home), h#pending |> List.map(p -> p#home)) |> List.toSet

    /// 敵 id（いなければ None）。
    pub def enemyOf(id: Int32, h: Horde): Option[Enemy] = h#enemies |> List.find(e -> e#id == id)

    /// 足元の world の行列。
    pub def worldOf(e: Enemy): Mat4.Mat4 = Creatures.worldOf(e#x, e#z, e#yaw)

    // ── 湧かせる ──

    /// 部屋 zone に足元 at で入った: まだ湧かせていない部屋なら、その部屋の spawn の点から時刻 t に始まる予定を足す（1 部屋 1 回だけ。
    /// at から SpawnsDoc の minDistance より近い点は使わない）。
    pub def enter(res: Res.Res, zone: Char, t: Float64, at: { x = Float64, z = Float64 }, h: Horde): Horde =
        if (Set.memberOf(zone, h#triggered)) h
        else {
            let away = { x = at#x, z = at#z, minDistance = SpawnsDoc.rec(res#spawns)#minDistance };
            { triggered = Set.insert(zone, h#triggered), pending = List.append(h#pending, Spawner.scheduleOf(res#spawnPoints, zone, t, away)) | h }
        }

    /// 部屋 zone をもう湧かせ終えたか。
    pub def isTriggered(zone: Char, h: Horde): Bool = Set.memberOf(zone, h#triggered)

    /// 時刻を待たずに敵を出す（描き出しの場面・測り・テスト）。向きは yaw（ラジアン）。
    pub def spawnNow(res: Res.Res, spawns: List[{ kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }], h: Horde): Horde =
        let born = spawns |> List.zipWithIndex |> List.map(e -> { let (i, sp) = e; newEnemy(res, h#nextId + i, sp) });
        { enemies = List.append(h#enemies, born), nextId = h#nextId + List.length(born) | h }

    def newEnemy(res: Res.Res, id: Int32, s: { kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }): Enemy =
        { id = id, kind = s#kind, home = s#home, x = s#x, z = s#z, yaw = s#yaw, health = healthOf(doc(res), s#kind),
          act = Act.Chase, readyAt = 0.0, staggerReadyAt = 0.0, moving = true, anim = Creatures.walkAnim() }

    def healthOf(d: EnemiesDoc.Rec, k: Kind): Float64 = match k {
        case Kind.Melee  => d#melee#health
        case Kind.Ranged => d#ranged#health
    }

    /// 時刻 t までに湧く予定の敵を出す（プレイヤーの方を向いて立つ）。
    def release(res: Res.Res, t: Float64, p: PlayerBody.PlayerBody, h: Horde): Horde =
        let (due, later) = h#pending |> List.partition(s -> s#at <= t);
        spawnNow(res, due |> List.map(s -> { kind = s#kind, x = s#x, z = s#z, yaw = facing(s#x, s#z, p#x, p#z), home = s#home }), { pending = later | h })

    /// 死んでやり直す時: 敵と projectile と湧く予定を全部消し、zones の部屋をもう一度湧かせられるようにする。
    pub def resetRooms(zones: Set[Char], h: Horde): Horde =
        { enemies = Nil, projectiles = Nil, pending = Nil, triggered = Set.difference(h#triggered, zones), field = FlowField.empty(), fieldAt = -1000.0 | h }

    // ── 撃たれる ──

    /// 時刻 t に、1 粒の威力 damage の弾が impacts に当たった（頭は headMultiplier 倍）。同じ敵に何粒当たっても 1 回の傷として足す。
    pub def applyDamage(res: Res.Res, t: Float64, damage: Float64, impacts: List[Hitscan.Impact], h: Horde): Damaged =
        let d = doc(res);
        let hits = impacts |> List.filterMap(hit -> match hit#struck {
            case Hitscan.Struck.Enemy(id, part) => Some((id, part))
            case _ => None
        });
        let taken = hits |> List.foldLeft((acc, hit) -> {
            let (id, part) = hit;
            Map.insertWith((a, b) -> a + b, id, damage * (if (part == Hitscan.Part.Head) d#headMultiplier else 1.0), acc)
        }, Map.empty());
        let enemies = h#enemies |> List.map(e -> Map.get(e#id, taken) |> Option.map(amount -> hurt(d, t, amount, e)) |> Option.getWithDefault(e));
        let kindOf = (id: Int32) -> enemyOf(id, h) |> Option.map(e -> e#kind);
        let hitEvents = hits |> List.filterMap(hit -> kindOf(fst(hit)) |> Option.map(k -> Event.EnemyHit(k, snd(hit))));
        let downEvents = List.zip(h#enemies, enemies) |> List.filter(pair -> isAlive(fst(pair)) and not isAlive(snd(pair)))
            |> List.map(pair -> Event.EnemyDown(snd(pair)#kind));
        { horde = { enemies = enemies | h }, events = List.append(hitEvents, downEvents) }

    def hurt(d: EnemiesDoc.Rec, t: Float64, amount: Float64, e: Enemy): Enemy =
        let health = e#health - amount;
        let staggers = t >= e#staggerReadyAt;
        let (act, stagger) = match e#act {
            case Act.Dying(_) => (e#act, e#staggerReadyAt)
            case _ if health <= 0.0 => (Act.Dying(t), e#staggerReadyAt)
            case Act.Attack(_, _) => (e#act, e#staggerReadyAt)
            case _ if staggers => (Act.Hurt(t), t + d#staggerCooldown)
            case _ => (e#act, e#staggerReadyAt)
        };
        animated(t, { health = health, act = act, staggerReadyAt = stagger, moving = false | e })

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
    pub def step(res: Res.Res, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, h: Horde): Outcome =
        let d = doc(res);
        let released = release(res, t, p, h);
        let fielded = refreshField(res, t, p, released);
        let remaining = fielded#enemies |> List.filter(e -> not isGone(d, t, e));
        let thought = remaining |> List.foldLeft((acc, e) -> {
            let flying = List.length(fielded#projectiles) + List.length(acc#spits);
            let r = think(res, fielded#field, t, dt, p, flying < d#projectile#limit, e);
            { enemies = r#enemy :: acc#enemies, damage = acc#damage + r#damage, spits = List.append(r#spit |> Option.toList, acc#spits),
              events = List.append(r#events, acc#events) }
        }, { enemies = Nil, damage = 0.0, spits = Nil, events = Nil });
        let launched = thought#spits |> List.foldLeft((acc, sp) -> launch(sp#at, sp#velocity, t, acc), fielded);
        let flight = Projectiles.fly(d#projectile, res#collision, t, dt, p, launched#projectiles);
        let bursts = List.repeat(flight#bursts, Event.Burst);
        { horde = { enemies = separate(res, p, List.reverse(thought#enemies)), projectiles = flight#projectiles | launched },
          damage = thought#damage + flight#damage, splashes = flight#splashes, events = List.append(thought#events, bursts) }

    /// 同じ dt で frames コマ進めた結果（時刻 start の次のコマから。受けたダメージと弾けた所と起きた事は足し合わせる）。
    pub def simulate(res: Res.Res, start: Float64, dt: Float64, frames: Int32, p: PlayerBody.PlayerBody, h: Horde): Outcome =
        List.range(1, frames + 1) |> List.foldLeft((acc, i) -> {
            let o = step(res, start + Int32.toFloat64(i) * dt, dt, p, acc#horde);
            { horde = o#horde, damage = acc#damage + o#damage, splashes = List.append(o#splashes, acc#splashes), events = List.append(o#events, acc#events) }
        }, { horde = h, damage = 0.0, splashes = Nil, events = Nil })

    /// 時刻 t に点 at から velocity（m/秒）で projectile を飛ばす。
    pub def launch(at: Vec3.Vec3, velocity: Vec3.Vec3, t: Float64, h: Horde): Horde =
        { projectiles = List.append(h#projectiles, { id = h#nextId, at = at, velocity = velocity, born = t } :: Nil), nextId = h#nextId + 1 | h }

    /// 倒れてから corpseSeconds が過ぎたか。
    def isGone(d: EnemiesDoc.Rec, t: Float64, e: Enemy): Bool = match e#act {
        case Act.Dying(at) => t - at >= d#corpseSeconds
        case _             => false
    }

    /// 地図を塗り直す時刻が来ていれば、プレイヤーのマスから塗り直す。
    def refreshField(res: Res.Res, t: Float64, p: PlayerBody.PlayerBody, h: Horde): Horde =
        if (t - h#fieldAt < doc(res)#fieldInterval and Option.nonEmpty(h#field#goal)) h
        else { field = FlowField.build(res#maze, Maze.cellAt(res#maze, p#x, p#z)), fieldAt = t | h }

    /// 押し合いと壁（倒れた敵は動かさず、押し合いにも入れない）。
    def separate(res: Res.Res, p: PlayerBody.PlayerBody, enemies: List[Enemy]): List[Enemy] =
        let (alive, fallen) = enemies |> List.partition(isAlive);
        let moved = Separation.separate(res#maze, res#collision, p,
            alive |> List.map(e -> { id = e#id, x = e#x, z = e#z, radius = Creatures.footprintOf(e#kind) }));
        List.append(List.zip(alive, moved) |> List.map(pair -> { x = fst(snd(pair)), z = snd(snd(pair)) | fst(pair) }), fallen)

    // ── 考える ──

    /// 敵 1 体の 1 コマの結果: 次の敵・プレイヤーへのダメージ・吐いた projectile（点と速さ）・起きた事。
    type alias Thought = { enemy = Enemy, damage = Float64, spit = Option[{ at = Vec3.Vec3, velocity = Vec3.Vec3 }], events = List[Event] }

    def still(e: Enemy): Thought = { enemy = e, damage = 0.0, spit = None, events = Nil }

    def think(res: Res.Res, field: FlowField.FlowField, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, canSpit: Bool, e: Enemy): Thought =
        let r = match e#act {
            case Act.Chase             => chase(res, field, t, dt, p, canSpit, e)
            case Act.Attack(s, struck) => swing(res, t, dt, p, canSpit, s, struck, e)
            case Act.Hurt(s)           => still(if (t - s >= Creatures.secondsOf(res#timing, e#kind, Clip.Hit)) { act = Act.Chase | e } else { moving = false | e })
            case Act.Dying(_)          => still(e)
        };
        { enemy = animated(t, r#enemy) | r }

    /// 今のしている事に合うクリップへ替える。
    def animated(t: Float64, e: Enemy): Enemy =
        let track = match e#act {
            case Act.Chase        => { clip = if (e#moving) Clip.Walk else Clip.Idle, start = 0.0 }
            case Act.Attack(s, _) => { clip = Clip.Attack, start = s }
            case Act.Hurt(s)      => { clip = Clip.Hit, start = s }
            case Act.Dying(s)     => { clip = Clip.Die, start = s }
        };
        { anim = Creatures.play(track, t, e#anim) | e }

    def distance(dx: Float64, dz: Float64): Float64 = Num.sqrt(dx * dx + dz * dz)

    /// (x, z) から (tx, tz) を向く角（ラジアン。0 が +Z・正で +X の側）。
    def facing(x: Float64, z: Float64, tx: Float64, tz: Float64): Float64 = Num.atan2(tx - x, tz - z)

    /// 向きを target へ、このコマに回れる角（Doc の turnRate × dt）まで回す。
    def turned(d: EnemiesDoc.Rec, dt: Float64, target: Float64, e: Enemy): Enemy =
        let maxStep = rad(d#turnRate) * dt;
        let diff = Num.atan2(Num.sin(target - e#yaw), Num.cos(target - e#yaw));
        { yaw = e#yaw + Num.clamp(0.0 - maxStep, maxStep, diff) | e }

    /// 追う: 攻撃を始められるなら始め、ほかは地図を読んで進む（ranged は保つ距離の内なら止まって構え、近すぎれば下がる）。
    def chase(res: Res.Res, field: FlowField.FlowField, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, canSpit: Bool, e: Enemy): Thought =
        let d = doc(res);
        let dist = distance(p#x - e#x, p#z - e#z);
        let toPlayer = facing(e#x, e#z, p#x, p#z);
        let ready = t >= e#readyAt;
        let ranged = d#ranged;
        match e#kind {
            case Kind.Melee if ready and dist <= d#melee#attackRange =>
                still({ act = Act.Attack(t, false), moving = false, yaw = toPlayer | e })
            case Kind.Melee if dist <= d#melee#stopDistance => still(turned(d, dt, toPlayer, { moving = false | e }))
            case Kind.Melee => still(advance(res, field, dt, p, d#melee#speed, e))
            case Kind.Ranged if ready and canSpit and dist <= ranged#sightRange and hasSight(res, e, p) =>
                still({ act = Act.Attack(t, false), moving = false, yaw = toPlayer | e })
            case Kind.Ranged if dist > ranged#keepDistance + ranged#approachMargin => still(advance(res, field, dt, p, ranged#speed, e))
            case Kind.Ranged if dist < ranged#keepDistance - ranged#retreatMargin and dist > 0.001 =>
                let back = ranged#speed * dt / dist;
                still(turned(d, dt, toPlayer, { x = e#x - (p#x - e#x) * back, z = e#z - (p#z - e#z) * back, moving = true | e }))
            case Kind.Ranged => still(turned(d, dt, toPlayer, { moving = false | e }))
        }

    /// 地図を読んで speed で 1 コマ進む。プレイヤーと同じマスか隣のマスならまっすぐプレイヤーへ。
    def advance(res: Res.Res, field: FlowField.FlowField, dt: Float64, p: PlayerBody.PlayerBody, speed: Float64, e: Enemy): Enemy =
        let m = res#maze;
        let cell = Maze.cellAt(m, e#x, e#z);
        let direct = FlowField.stepsAt(field, cell) |> Option.exists(s -> s <= 1);
        let (gx, gz) = if (direct) (p#x, p#z)
            else FlowField.downhill(m, field, cell) |> Option.map(Maze.centerOf(m)) |> Option.getWithDefault((p#x, p#z));
        let dist = distance(gx - e#x, gz - e#z);
        if (dist < 0.001) { moving = false | e }
        else {
            let stride = Float64.min(dist, speed * dt);
            turned(doc(res), dt, facing(e#x, e#z, gx, gz), { x = e#x + (gx - e#x) / dist * stride, z = e#z + (gz - e#z) / dist * stride, moving = true | e })
        }

    /// 敵の口からプレイヤーの目まで、壁の箱に遮られずに線が引けるか。
    def hasSight(res: Res.Res, e: Enemy, p: PlayerBody.PlayerBody): Bool =
        Collider.isLineClear(res#collision, Mat4.apply(worldOf(e), Creatures.hitboxOf(e#kind)#mouth), p#eye)

    /// 振る・吐く: 始めてから hitTime を過ぎた最初のコマに 1 回だけ当てる・吐く（コマが長くても飛ばさない）。
    /// クリップが終われば追うへ戻る（次を始められるのは cooldown の後）。
    def swing(res: Res.Res, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, canSpit: Bool, start: Float64, struck: Bool, e: Enemy): Thought =
        let d = doc(res);
        let elapsed = t - start;
        let (hitTime, cooldown) = match e#kind {
            case Kind.Melee  => (d#melee#hitTime, d#melee#cooldown)
            case Kind.Ranged => (d#ranged#hitTime, d#ranged#cooldown)
        };
        let due = not struck and elapsed >= hitTime;
        let aimed = if (elapsed < hitTime) turned(d, dt, facing(e#x, e#z, p#x, p#z), e) else e;
        let done = elapsed >= Creatures.secondsOf(res#timing, e#kind, Clip.Attack);
        let next = if (done) { act = Act.Chase, readyAt = t + cooldown | aimed } else { act = Act.Attack(start, struck or due) | aimed };
        match e#kind {
            case Kind.Melee =>
                { enemy = next, damage = if (due and isInSwing(d#melee, aimed, p)) d#melee#damage else 0.0, spit = None,
                  events = if (due) Event.Swing :: Nil else Nil }
            case Kind.Ranged =>
                let spits = due and canSpit;
                { enemy = next, damage = 0.0, spit = if (spits) Some(spitOf(d#projectile, aimed, p)) else None,
                  events = if (spits) Event.Spit :: Nil else Nil }
        }

    /// melee の振り下ろしの扇の内か: 足元からプレイヤーの体の縁までが reach の内で、向きから arc の半分の角の内。
    pub def isInSwing(m: EnemiesDoc.Melee, e: Enemy, p: PlayerBody.PlayerBody): Bool =
        let dx = p#x - e#x;
        let dz = p#z - e#z;
        let dist = distance(dx, dz);
        let ahead = if (dist < 0.001) 1.0 else (dx * Num.sin(e#yaw) + dz * Num.cos(e#yaw)) / dist;
        dist - p#radius <= m#reach and ahead >= Num.cos(rad(m#arc) * 0.5)

    /// 口からプレイヤーの胸へ向けて吐く projectile の点と速さ。
    def spitOf(pr: EnemiesDoc.Projectile, e: Enemy, p: PlayerBody.PlayerBody): { at = Vec3.Vec3, velocity = Vec3.Vec3 } =
        let mouth = Mat4.apply(worldOf(e), Creatures.hitboxOf(e#kind)#mouth);
        let chest = Vec3.v3(p#x, p#eye#y - 0.3, p#z);
        { at = mouth, velocity = Vec3.mul(Vec3.normalized(Vec3.sub(chest, mouth)), pr#speed) }
}
