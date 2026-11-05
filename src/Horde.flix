// Horde — 敵の群れの状態と、1 コマ進める規則（純粋）。projectile を進めるのは Projectiles・押し合いと壁は Separation。
//
// ── 1 コマ（step）──
//   1. 入った区画の次の wave を始めるか決め（Spawner.nextWave）、始めた wave を湧くのを待つ列に並べる。
//      列の頭から、生きている数が maxAlive より少なく、前に湧いてから spawnInterval が過ぎていれば 1 体湧かせる（Spawner.placeOf）
//   2. 距離の地図（FlowField）を fieldInterval 秒に 1 回だけ、プレイヤーのマスから塗り直す（全員で共有）
//   3. 倒れて corpseSeconds が過ぎた敵を消し、残りが考える: 追う（地図の隣のマスを読んで進む）・振る / 吐く・よろける
//   4. 吐いた projectile を足して進める（Projectiles）
//   5. 押し合いと壁（Separation）
// プレイヤーが受けたダメージ・弾けた所・起きた事を Outcome で返し、体力と粒と音は World が持つ。
//
// melee は lungeRange の内でプレイヤーまで見通せれば飛びかかる（Lunge: 速さ lungeBoost 倍でまっすぐ寄り、体が前へ伸びる）。
// attackRange の内に入れば attack のクリップを始め、始めてから hitTime を過ぎた最初のコマに 1 回だけ、プレイヤーが前の扇（reach・arc）の内ならダメージ。
// 飛びかかりが lungeSeconds の内に届かなければ追うへ戻り、cooldown の間は飛びかからない。
// ranged は keepDistance を保ち、壁の箱へレイを当てて見通しがある時だけ溜め（Charge: chargeSeconds の間立ち止まって喉を光らせる）を始め、
// 溜め終えて attack のクリップを始め、hitTime を過ぎた最初のコマに口から projectile を吐く（その時に飛んでいる数が上限なら吐かない）。
// 撃たれると（applyDamage）体力が減り、撃たれた向きへ押され（のけぞり・Knockback）、追う・飛びかかる・溜める途中で staggerCooldown が明けていれば
// よろけ（hit のクリップ）、0 で倒れる（die のクリップ）。倒れた敵は撃たれた向きへ吹っ飛ぶか、条件に当たれば弾けて消える（Gibs.bursts）。
mod Horde {
    use fge::{CollisionShape3d, Hash01, Mat4, Num, Ray3d, Vec3}
    use Creatures.{Clip, Kind}
    use Events.Event

    /// 敵のしている事。Attack = 始めた時刻と、当てた（吐いた）か・Lunge（melee の飛びかかり）・Charge（ranged の溜め）・Hurt と Dying はその時刻から。
    pub enum Act with Eq, ToString {
        case Chase
        case Lunge(Float64)
        case Charge(Float64)
        case Attack(Float64, Bool)
        case Hurt(Float64)
        case Dying(Float64)
    }

    /// 敵 1 体。readyAt = 次の攻撃を始められる時刻・staggerReadyAt = 次によろけられる時刻・moving = このコマに歩いたか（walk と idle を分ける）・
    /// home = 湧いた部屋・push = 撃たれて押されている（のけぞり）・flight = 倒れて吹っ飛んでいる。
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
        anim = Creatures.Anim,
        push = Knockback.Push,
        flight = Knockback.Flight
    }

    /// 群れ。queue = 湧くのを待っている敵（湧く順）・waves = 入った区画の wave の進み（鍵が無い区画はまだ入っていない）・
    /// nextSpawnAt = 次の 1 体を湧かせてよい時刻・fieldAt = 地図を塗った時刻・nextId = 次に出す敵と projectile の番号。
    pub type alias Horde = {
        enemies = List[Enemy],
        projectiles = List[Projectiles.Projectile],
        queue = List[Spawner.Queued],
        waves = Map[Char, Spawner.Progress],
        nextSpawnAt = Float64,
        field = FlowField.FlowField,
        fieldAt = Float64,
        nextId = Int32
    }

    /// 1 コマの結果: 次の群れ・プレイヤーが受けたダメージの合計・projectile が弾けた所・起きた事。
    pub type alias Outcome = { horde = Horde, damage = Float64, splashes = List[Projectiles.Splash], events = List[Event] }

    /// 撃った 1 回: 時刻・1 粒の威力・武器・撃った点（目）・何回目か（弾けるかの種）。
    pub type alias Shot = { t = Float64, damage = Float64, weapon = WeaponsDoc.Weapon, origin = Vec3.Vec3, index = Int32 }

    /// 撃たれた結果: 次の群れ・起きた事（当たった・倒れた）・この弾で倒れた敵（弾けた敵も）・そのうち弾けて群れから消えた敵。
    pub type alias Damaged = { horde = Horde, events = List[Event], fallen = List[Enemy], burst = List[Enemy] }

    /// 撃たれた 1 体のその後。
    enum Fate with Eq {
        case Hurt
        case Fell
        case Burst
    }

    /// 何もいない群れ。
    pub def empty(): Horde =
        { enemies = Nil, projectiles = Nil, queue = Nil, waves = Map.empty(), nextSpawnAt = -1000.0, field = FlowField.empty(), fieldAt = -1000.0, nextId = 0 }

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

    /// 区画 zone の残り: 倒れていない敵と湧くのを待っている敵のうち、その区画の wave で湧いた（湧く）数。
    def leftIn(zone: Char, h: Horde): Int32 =
        List.count(e -> e#home == zone and isAlive(e), h#enemies) + List.count(q -> q#home == zone, h#queue)

    def planOf(res: Res.Res, zone: Char): List[Spawner.Wave] = Map.getWithDefault(zone, Nil, res#wavePlans)

    /// 区画 zone に入り、全部の wave を始め、その wave の敵が残っていないか（まだ入っていなければ偽）。
    pub def isFinished(res: Res.Res, zone: Char, h: Horde): Bool =
        Map.get(zone, h#waves) |> Option.exists(p -> p#started >= List.length(planOf(res, zone))) and leftIn(zone, h) == 0

    /// 区画 zone で始めた wave の数（まだ入っていなければ 0）。
    pub def wavesStarted(zone: Char, h: Horde): Int32 = Map.get(zone, h#waves) |> Option.map(p -> p#started) |> Option.getWithDefault(0)

    /// 湧くのを待っている敵の数。
    pub def queuedCount(h: Horde): Int32 = List.length(h#queue)

    /// 敵 id（いなければ None）。
    pub def enemyOf(id: Int32, h: Horde): Option[Enemy] = h#enemies |> List.find(e -> e#id == id)

    /// 足元の world の行列。
    pub def worldOf(e: Enemy): Mat4.Mat4 = Creatures.worldOf(e#x, e#z, e#yaw)

    // ── 湧かせる ──

    /// 区画 zone に時刻 t に入った: まだ入っていない区画なら wave の進みを始める（最初の wave は step が after 秒の後に始める。1 区画 1 回だけ）。
    pub def enter(zone: Char, t: Float64, h: Horde): Horde =
        if (Map.memberOf(zone, h#waves)) h else { waves = Map.insert(zone, { started = 0, at = t }, h#waves) | h }

    /// 区画 zone にもう入ったか。
    pub def isTriggered(zone: Char, h: Horde): Bool = Map.memberOf(zone, h#waves)

    /// 時刻を待たずに敵を出す（描き出しの場面・測り・テスト）。向きは yaw（ラジアン）。
    pub def spawnNow(res: Res.Res, spawns: List[{ kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }], h: Horde): Horde =
        let born = spawns |> List.zipWithIndex |> List.map(e -> { let (i, sp) = e; newEnemy(res, h#nextId + i, sp) });
        { enemies = List.append(h#enemies, born), nextId = h#nextId + List.length(born) | h }

    def newEnemy(res: Res.Res, id: Int32, s: { kind = Kind, x = Float64, z = Float64, yaw = Float64, home = Char }): Enemy =
        { id = id, kind = s#kind, home = s#home, x = s#x, z = s#z, yaw = s#yaw, health = healthOf(doc(res), s#kind),
          act = Act.Chase, readyAt = 0.0, staggerReadyAt = 0.0, moving = true, anim = Creatures.walkAnim(),
          push = Knockback.noPush(), flight = Knockback.grounded() }

    def healthOf(d: EnemiesDoc.Rec, k: Kind): Float64 = match k {
        case Kind.Melee  => d#melee#health
        case Kind.Ranged => d#ranged#health
    }

    /// 入った区画のうち、時刻 t に次の wave を始める区画の wave を湧くのを待つ列に並べる（1 コマに 1 区画 1 wave まで）。
    def startWaves(res: Res.Res, t: Float64, h: Horde): (Horde, List[Event]) =
        h#waves |> Map.foldLeftWithKey((acc, zone, progress) -> {
            let (current, events) = acc;
            let plan = planOf(res, zone);
            let due = if (progress#started >= List.length(plan)) None else Spawner.nextWave(plan, t, leftIn(zone, current), progress);
            due |> Option.map(w -> ({ queue = List.append(current#queue, Spawner.queueOf(zone, w)),
                                      waves = Map.insert(zone, { started = progress#started + 1, at = t }, current#waves) | current },
                                    List.append(events, Event.WaveStarted(zone, progress#started) :: Nil)))
                |> Option.getWithDefault(acc)
        }, (h, Nil))

    /// 列の頭の 1 体を湧かせる: 生きている数が maxAlive より少なく、前に湧いてから spawnInterval が過ぎていれば（プレイヤーの方を向いて立つ）。
    /// 湧く印が無い 1 体は湧かせずに列から外す（plansOf が印の無い wave を捨てるので、来るのは迷路を読み直した時だけ）。
    def release(res: Res.Res, t: Float64, p: PlayerBody.PlayerBody, h: Horde): Horde =
        let sd = SpawnsDoc.rec(res#spawns);
        match h#queue {
            case q :: rest if t >= h#nextSpawnAt and aliveCount(h) < sd#maxAlive =>
                let viewer = { x = p#x, z = p#z, yaw = p#yaw, lineOfSight = (x, z) -> Collider.isLineClear(res#collision, p#eye, Vec3.v3(x, p#feet + 1.2, z)) };
                let next = { queue = rest, nextSpawnAt = t + sd#spawnInterval | h };
                Spawner.placeOf({ minDistance = sd#minDistance, scatter = sd#scatter }, viewer, q#source, h#nextId, res#spawnPoints)
                    |> Option.map(at -> { let (x, z) = at; spawnNow(res, { kind = q#kind, x = x, z = z, yaw = facing(x, z, p#x, p#z), home = q#home } :: Nil, next) })
                    |> Option.getWithDefault(next)
            case _ => h
        }

    /// 終えた区画の wave の進み（やり直す所に控え、やり直した時にこれだけを戻す）。
    pub def finishedOf(res: Res.Res, h: Horde): Map[Char, Spawner.Progress] = h#waves |> Map.filterWithKey((zone, _) -> isFinished(res, zone, h))

    /// やり直す時: 敵と projectile と湧くのを待つ列を全部消し、wave の進みを finished（やり直す所に控えた、終えた区画）へ戻す。
    /// ほかの区画は入っていない区画に戻り、もう一度入ると最初の wave から湧く。
    pub def restore(finished: Map[Char, Spawner.Progress], h: Horde): Horde =
        { enemies = Nil, projectiles = Nil, queue = Nil, waves = finished, nextSpawnAt = -1000.0, field = FlowField.empty(), fieldAt = -1000.0 | h }

    // ── 撃たれる ──

    /// 敵 1 体への一撃: 時刻・傷の量・生き残った時の押され方・倒れた時に弾けるか・倒れた時の飛び出し・
    /// 攻撃の途中でもよろけさせるか（蹴りと爆発。撃たれた時は振り下ろしを止めない）。
    type alias Blow = { t = Float64, amount = Float64, push = Knockback.Push, bursts = Bool, flight = Knockback.Flight, interrupts = Bool }

    /// 撃った 1 回 shot の粒が impacts に当たった（頭は headMultiplier 倍）。同じ敵に何粒当たっても 1 回の傷として足す。
    /// 生き残った敵は撃たれた向きへ押され、倒れた敵は吹っ飛ぶか、条件に当たれば弾けて群れから消える。
    pub def applyDamage(res: Res.Res, shot: Shot, impacts: List[Hitscan.Impact], h: Horde): Damaged =
        let d = doc(res);
        let juice = JuiceDoc.rec(res#juice);
        let hits = impacts |> List.filterMap(hit -> match hit#struck {
            case Hitscan.Struck.Enemy(id, part) => Some((id, part))
            case _ => None
        });
        let amountOf = (part: Hitscan.Part) -> shot#damage * (if (part == Hitscan.Part.Head) d#headMultiplier else 1.0);
        let taken = hits |> List.foldLeft((acc, hit) -> Map.insertWith((a, b) -> a + b, fst(hit), amountOf(snd(hit)), acc), Map.empty());
        let onHead = hits |> List.filter(hit -> snd(hit) == Hitscan.Part.Head)
            |> List.foldLeft((acc, hit) -> Map.insertWith((a, b) -> a + b, fst(hit), amountOf(snd(hit)), acc), Map.empty());
        let blows = h#enemies |> List.filterMap(e -> Map.get(e#id, taken) |> Option.map(amount ->
            (e#id, shotBlow(d, juice, shot, amount, Map.getWithDefault(e#id, 0.0, onHead), e)))) |> List.toMap;
        let kindOf = (id: Int32) -> enemyOf(id, h) |> Option.map(e -> e#kind);
        resolve(d, blows, hits |> List.filterMap(hit -> kindOf(fst(hit)) |> Option.map(k -> Event.EnemyHit(k, snd(hit)))), h)

    /// 撃った 1 回の、敵 e への一撃（押され方と飛び出しは武器と撃った点からの距離・弾けるかは Gibs.bursts）。
    def shotBlow(d: EnemiesDoc.Rec, juice: JuiceDoc.Rec, shot: Shot, amount: Float64, headDamage: Float64, e: Enemy): Blow =
        let away = Knockback.awayFrom(shot#origin#x, shot#origin#z, e#x, e#z);
        let cause = { weapon = shot#weapon, distance = away#distance, headDamage = headDamage, overkill = amount - e#health };
        { t = shot#t, amount = amount, push = Knockback.pushOf(d#flinch, shot#weapon, shot#t, away),
          bursts = Gibs.bursts(juice#gib, cause, Hash01.at(e#id * 7 + shot#index, 61)),
          flight = Knockback.launch(juice#fling, shot#weapon, away, Hash01.at(e#id, 62)), interrupts = false }

    /// 一撃の束 blows（敵の番号 → 一撃）を群れに当てる。hitEvents = 当たった音の出来事。
    def resolve(d: EnemiesDoc.Rec, blows: Map[Int32, Blow], hitEvents: List[Event], h: Horde): Damaged =
        let pairs = h#enemies |> List.map(e -> (e, Map.get(e#id, blows) |> Option.map(b -> struck(d, b, e))));
        let enemies = pairs |> List.filterMap(pair -> match snd(pair) {
            case Some((_, Fate.Burst)) => None
            case Some((next, _))       => Some(next)
            case None                  => Some(fst(pair))
        });
        let downs = pairs |> List.filterMap(pair -> snd(pair) |> Option.filter(o -> isAlive(fst(pair)) and snd(o) != Fate.Hurt));
        let downEvents = downs |> List.map(o -> Event.EnemyDown(fst(o)#kind, if (snd(o) == Fate.Burst) Events.Death.Burst else Events.Death.Fell));
        { horde = { enemies = enemies | h }, events = List.append(hitEvents, downEvents), fallen = downs |> List.map(fst),
          burst = downs |> List.filter(o -> snd(o) == Fate.Burst) |> List.map(fst) }

    /// 一撃を受けた 1 体: 傷を足し、生きていれば押す・倒れたら吹っ飛ぶか弾けるか（もう倒れていた体はそのまま）。
    def struck(d: EnemiesDoc.Rec, b: Blow, e: Enemy): (Enemy, Fate) =
        let next = hurt(d, b#t, b#amount, b#interrupts, e);
        if (not isAlive(e)) (next, Fate.Hurt)
        else if (isAlive(next)) ({ push = b#push | next }, Fate.Hurt)
        else if (b#bursts) (next, Fate.Burst)
        else ({ flight = b#flight | next }, Fate.Fell)

    // ── 蹴られる・爆発に巻き込まれる ──

    /// 蹴り 1 回: 時刻・蹴った足元と向き（ラジアン。0 が +Z）・値（MovesDoc の kick）。
    pub type alias Kick = { t = Float64, x = Float64, z = Float64, yaw = Float64, doc = MovesDoc.Kick }

    /// 敵 e が蹴りの扇の内か: 足元から体の縁までが range の内で、向きから arc の半分の角の内（倒れた体は入らない）。
    pub def isInKick(k: Kick, e: Enemy): Bool =
        let dx = e#x - k#x;
        let dz = e#z - k#z;
        let dist = distance(dx, dz);
        let ahead = if (dist < 0.001) 1.0 else (dx * Num.sin(k#yaw) + dz * Num.cos(k#yaw)) / dist;
        isAlive(e) and dist - Creatures.footprintOf(e#kind) <= k#doc#range and ahead >= Num.cos(rad(k#doc#arc) * 0.5)

    /// 蹴り: 扇の内の敵に傷を付け、蹴った足元から離れる向きへ押し返して、攻撃の途中でもよろけさせる（倒れた敵は弾けずに飛ぶ）。
    pub def kick(res: Res.Res, k: Kick, h: Horde): Damaged =
        let fl = JuiceDoc.rec(res#juice)#fling;
        let kicked = h#enemies |> List.filter(isInKick(k));
        let blows = kicked |> List.map(e -> {
            let away = Knockback.awayFrom(k#x, k#z, e#x, e#z);
            (e#id, { t = k#t, amount = k#doc#damage, push = Knockback.shove(k#t, away, k#doc#push, k#doc#pushDecay), bursts = false,
                     flight = Knockback.flingAt(fl, { speed = k#doc#fling, lift = fl#lift, spin = 1.0 }, away, Hash01.at(e#id, 62)), interrupts = true })
        }) |> List.toMap;
        resolve(doc(res), blows, kicked |> List.map(e -> Event.EnemyHit(e#kind, Hitscan.Part.Body)), h)

    /// 爆発 1 つ: 時刻・点・値（GrenadeDoc の blast）・種（手榴弾の番号）。
    pub type alias Blast = { t = Float64, point = Vec3.Vec3, doc = GrenadeDoc.Blast, seed = Int32 }

    /// 爆発: 半径の内で、爆発の点から胸まで壁に遮られない敵に、距離で減る傷を付ける（Grenades.damageAt）。
    /// 生き残った敵は外へ押されてよろけ、倒れた敵は弾ける半径の内なら肉片に・外なら外へ吹っ飛ぶ（近いほど強く）。
    pub def blast(res: Res.Res, b: Blast, h: Horde): Damaged =
        let fl = JuiceDoc.rec(res#juice)#fling;
        let g = b#doc;
        let low = Vec3.add(b#point, Vec3.v3(0.0, 0.3, 0.0));
        let blows = h#enemies |> List.filterMap(e -> {
            let away = Knockback.awayFrom(b#point#x, b#point#z, e#x, e#z);
            let near = 1.0 - Num.clamp01(away#distance / Float64.max(0.001, g#radius));
            let reached = isAlive(e) and away#distance <= g#radius and Collider.isLineClear(res#collision, low, Vec3.v3(e#x, 1.0, e#z));
            if (not reached) None
            else Some((e#id, { t = b#t, amount = Grenades.damageAt(g, away#distance), push = Knockback.shove(b#t, away, g#push * (0.5 + 0.5 * near), g#pushDecay),
                              bursts = away#distance <= g#gibRadius,
                              flight = Knockback.flingAt(fl, { speed = g#push * (0.5 + 0.5 * near), lift = g#lift * (0.5 + 0.5 * near), spin = 1.0 + near },
                                                         away, Hash01.at(e#id * 5 + b#seed, 62)),
                              interrupts = true }))
        }) |> List.toMap;
        resolve(doc(res), blows, Nil, h)

    /// 傷 amount を足す: 0 以下で倒れ、ほかは staggerCooldown が明けていればよろける（interrupts なら攻撃の途中でも・明けていなくても）。
    def hurt(d: EnemiesDoc.Rec, t: Float64, amount: Float64, interrupts: Bool, e: Enemy): Enemy =
        let health = e#health - amount;
        let staggers = interrupts or t >= e#staggerReadyAt;
        let (act, stagger) = match e#act {
            case Act.Dying(_) => (e#act, e#staggerReadyAt)
            case _ if health <= 0.0 => (Act.Dying(t), e#staggerReadyAt)
            case Act.Attack(_, _) if not interrupts => (e#act, e#staggerReadyAt)
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
        let (waved, waveEvents) = startWaves(res, t, h);
        let released = release(res, t, p, waved);
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
          damage = thought#damage + flight#damage, splashes = flight#splashes, events = List.flatten(waveEvents :: thought#events :: bursts :: Nil) }

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
        let moved = Separation.separate(res#maze, res#collision, res#openCells, p,
            alive |> List.map(e -> { id = e#id, x = e#x, z = e#z, radius = Creatures.footprintOf(e#kind) }));
        List.append(List.zip(alive, moved) |> List.map(pair -> { x = fst(snd(pair)), z = snd(snd(pair)) | fst(pair) }), fallen)

    // ── 考える ──

    /// 敵 1 体の 1 コマの結果: 次の敵・プレイヤーへのダメージ・吐いた projectile（点と速さ）・起きた事。
    type alias Thought = { enemy = Enemy, damage = Float64, spit = Option[{ at = Vec3.Vec3, velocity = Vec3.Vec3 }], events = List[Event] }

    def still(e: Enemy): Thought = { enemy = e, damage = 0.0, spit = None, events = Nil }

    def think(res: Res.Res, field: FlowField.FlowField, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, canSpit: Bool, e: Enemy): Thought =
        let r = match e#act {
            case Act.Chase             => chase(res, field, t, dt, p, canSpit, e)
            case Act.Lunge(s)          => lunge(res, t, dt, p, s, e)
            case Act.Charge(s)         => charge(res, t, dt, p, s, e)
            case Act.Attack(s, hit)    => swing(res, t, dt, p, canSpit, s, hit, e)
            case Act.Hurt(s)           => still(if (t - s >= Creatures.secondsOf(res#timing, e#kind, Clip.Hit)) { act = Act.Chase | e } else { moving = false | e })
            case Act.Dying(_)          => still(flown(res, dt, e))
        };
        { enemy = animated(t, pushed(t, dt, r#enemy)) | r }

    /// 撃たれて押されている分だけ動かす（倒れた体は押さない。壁は Separation が押し戻す）。
    def pushed(t: Float64, dt: Float64, e: Enemy): Enemy =
        if (not isAlive(e) or e#push#speed <= 0.0) e
        else {
            let (mx, mz) = Knockback.pushStep(t, dt, e#push);
            { x = e#x + mx, z = e#z + mz | e }
        }

    /// 倒れた体を 1 コマ飛ばす（撃たれた向きへの放物線・床を滑る・壁で止まる）。
    def flown(res: Res.Res, dt: Float64, e: Enemy): Enemy =
        if (e#flight#speed0 <= 0.0 and e#flight#y <= 0.0 and e#flight#vy <= 0.0) e
        else {
            let (at, flight) = Knockback.fly(JuiceDoc.rec(res#juice)#fling, (a, b) -> Collider.isLineClear(res#collision, a, b),
                Creatures.footprintOf(e#kind), dt, { x = e#x, z = e#z, yaw = e#yaw }, e#flight);
            { x = at#x, z = at#z, yaw = at#yaw, flight = flight | e }
        }

    /// 今のしている事に合うクリップへ替える。
    def animated(t: Float64, e: Enemy): Enemy =
        let track = match e#act {
            case Act.Chase        => { clip = if (e#moving) Clip.Walk else Clip.Idle, start = 0.0 }
            case Act.Lunge(_)     => { clip = Clip.Walk, start = 0.0 }
            case Act.Charge(_)    => { clip = Clip.Idle, start = 0.0 }
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
            case Kind.Melee if ready and dist <= d#melee#lungeRange and canLunge(res, e, p) =>
                { enemy = { act = Act.Lunge(t), moving = true, yaw = toPlayer | e }, damage = 0.0, spit = None, events = Event.Lunge :: Nil }
            case Kind.Melee if dist <= d#melee#stopDistance => still(turned(d, dt, toPlayer, { moving = false | e }))
            case Kind.Melee => still(advance(res, field, dt, p, d#melee#speed, e))
            case Kind.Ranged if ready and canSpit and dist <= ranged#sightRange and hasSight(res, e, p) =>
                { enemy = { act = Act.Charge(t), moving = false, yaw = toPlayer | e }, damage = 0.0, spit = None, events = Event.Charge :: Nil }
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
            else FlowField.downhill(field, cell) |> Option.map(Maze.centerOf(m)) |> Option.getWithDefault((p#x, p#z));
        let dist = distance(gx - e#x, gz - e#z);
        if (dist < 0.001) { moving = false | e }
        else {
            let stride = Float64.min(dist, speed * dt);
            turned(doc(res), dt, facing(e#x, e#z, gx, gz), { x = e#x + (gx - e#x) / dist * stride, z = e#z + (gz - e#z) / dist * stride, moving = true | e })
        }

    /// 飛びかかれるか: 胸の高さからプレイヤーの胸まで、壁の箱に遮られずに線が引けるか（壁越しに飛びかからない）。
    def canLunge(res: Res.Res, e: Enemy, p: PlayerBody.PlayerBody): Bool =
        Collider.isLineClear(res#collision, Vec3.v3(e#x, 1.0, e#z), Vec3.v3(p#x, 1.0, p#z))

    /// 飛びかかる: 速さ × lungeBoost でプレイヤーへまっすぐ寄り、attackRange の内に入れば attack を始める（当たりは振り下ろしと同じ扇で見る）。
    /// lungeSeconds の内に届かなければ追うへ戻り、cooldown の間は飛びかからない。
    def lunge(res: Res.Res, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, start: Float64, e: Enemy): Thought =
        let m = doc(res)#melee;
        let dist = distance(p#x - e#x, p#z - e#z);
        let toPlayer = facing(e#x, e#z, p#x, p#z);
        if (dist <= m#attackRange) still({ act = Act.Attack(t, false), moving = false, yaw = toPlayer | e })
        else if (t - start >= m#lungeSeconds) still({ act = Act.Chase, readyAt = t + m#cooldown | e })
        else {
            let stride = Float64.min(dist - m#attackRange * 0.5, m#speed * m#lungeBoost * dt);
            still({ x = e#x + (p#x - e#x) / dist * stride, z = e#z + (p#z - e#z) / dist * stride, yaw = toPlayer, moving = true | e })
        }

    /// 溜める: chargeSeconds の間立ち止まってプレイヤーを向き、溜め終えたら attack のクリップを始める（吐くのは hitTime の後）。
    def charge(res: Res.Res, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, start: Float64, e: Enemy): Thought =
        let faced = turned(doc(res), dt, facing(e#x, e#z, p#x, p#z), { moving = false | e });
        if (t - start >= doc(res)#ranged#chargeSeconds) still({ act = Act.Attack(t, false) | faced }) else still(faced)

    // ── 描く形 ──

    /// 時刻 t の溜めの進み（0..1。溜めていなければ None）。
    pub def chargeOf(res: Res.Res, t: Float64, e: Enemy): Option[Float64] = match e#act {
        case Act.Charge(s) => Some(Num.clamp01((t - s) / Float64.max(0.001, doc(res)#ranged#chargeSeconds)))
        case _             => None
    }

    /// 口の点（ステージの座標）。
    pub def mouthOf(e: Enemy): Vec3.Vec3 = Mat4.apply(worldOf(e), Creatures.hitboxOf(e#kind)#mouth)

    /// 縦の軸を、水平の向き (dx, dz) の側へ a（ラジアン）倒す回転。
    def tiltToward(dx: Float64, dz: Float64, a: Float64): Mat4.Mat4 =
        let heading = Num.atan2(dx, dz);
        Mat4.mul(Mat4.rotateY(heading), Mat4.mul(Mat4.rotateX(a), Mat4.rotateY(0.0 - heading)))

    /// 時刻 t に描く体の world の行列: 足元と向きに、吹っ飛ぶ高さ・押された向きへの傾き・飛ぶ向きへの反り・飛びかかる伸び・溜めの膨らみを重ねる。
    /// 当たり判定の形は足元と向きの worldOf のまま（描く形だけを変える）。
    pub def drawnWorldOf(res: Res.Res, t: Float64, e: Enemy): Mat4.Mat4 =
        let d = doc(res);
        let lift = Mat4.translate(Vec3.v3(e#x, e#flight#y, e#z));
        let lean = if (isAlive(e)) tiltToward(e#push#dx, e#push#dz, Knockback.leanAt(d#flinch, t, e#push))
            else Knockback.headingOf(e#flight) |> Option.map(h -> tiltToward(fst(h), snd(h), Knockback.tiltOf(JuiceDoc.rec(res#juice)#fling, e#flight)))
                    |> Option.getWithDefault(Mat4.identity());
        Mat4.mul(lift, Mat4.mul(lean, Mat4.mul(Mat4.rotateY(e#yaw), bodyShapeOf(d, t, e))))

    /// 体の局所の伸び縮み（飛びかかる間は前へ伸びて前へ傾き、溜める間は膨らむ）。
    def bodyShapeOf(d: EnemiesDoc.Rec, t: Float64, e: Enemy): Mat4.Mat4 = match e#act {
        case Act.Lunge(s) =>
            let k = Num.sin(Num.pi() * Num.clamp01((t - s) / Float64.max(0.001, d#melee#lungeSeconds)));
            let st = d#melee#lungeStretch * k;
            Mat4.mul(Mat4.rotateX(st), Mat4.scale(Vec3.v3(1.0 - st * 0.3, 1.0 - st * 0.4, 1.0 + st)))
        case Act.Charge(s) =>
            let k = d#ranged#chargePuff * Num.clamp01((t - s) / Float64.max(0.001, d#ranged#chargeSeconds));
            Mat4.scale(Vec3.v3(1.0 + k, 1.0 + k * 0.5, 1.0 + k))
        case _ => Mat4.identity()
    }

    /// 敵の口からプレイヤーの目まで、壁の箱に遮られずに線が引けるか。
    def hasSight(res: Res.Res, e: Enemy, p: PlayerBody.PlayerBody): Bool =
        Collider.isLineClear(res#collision, mouthOf(e), p#eye)

    /// 振る・吐く: 始めてから hitTime を過ぎた最初のコマに 1 回だけ当てる・吐く（コマが長くても飛ばさない）。
    /// クリップが終われば追うへ戻る（次を始められるのは cooldown の後）。
    def swing(res: Res.Res, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, canSpit: Bool, start: Float64, hit: Bool, e: Enemy): Thought =
        let d = doc(res);
        let elapsed = t - start;
        let (hitTime, cooldown) = match e#kind {
            case Kind.Melee  => (d#melee#hitTime, d#melee#cooldown)
            case Kind.Ranged => (d#ranged#hitTime, d#ranged#cooldown)
        };
        let due = not hit and elapsed >= hitTime;
        let aimed = if (elapsed < hitTime) turned(d, dt, facing(e#x, e#z, p#x, p#z), e) else e;
        let done = elapsed >= Creatures.secondsOf(res#timing, e#kind, Clip.Attack);
        let next = if (done) { act = Act.Chase, readyAt = t + cooldown | aimed } else { act = Act.Attack(start, hit or due) | aimed };
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
        let mouth = mouthOf(e);
        let chest = Vec3.v3(p#x, p#eye#y - 0.3, p#z);
        { at = mouth, velocity = Vec3.mul(Vec3.normalized(Vec3.sub(chest, mouth)), pr#speed) }
}
