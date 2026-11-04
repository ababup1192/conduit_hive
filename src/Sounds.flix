// Sounds — このコマに起きた事と、鳴り続ける音を、project.json の sounds に載せた音の名前へ写す（純粋）。
//
// 一発の音（Game の App.withAudio）: 遊んでいる場面の World.eventsOf と画面をまたぐ World.screenEventsOf を 1 つずつ名前の頭へ写し、
// 変化（<頭>_<番号>）を選ぶ。撃った音は撃った回数の順に回し、ほかは時刻と並びの番号から決まった種で選ぶ（乱数の状態を持たない）。
// 出来事でない音も前後の World から足す: 足音（歩いた距離が 1 歩を越えた）・敵の叫び（このコマに攻撃を始めた近い敵）。
// 同じ頭はコマに SoundsDoc の maxPerFamily まで。同じ名前が続く間引きは mixer の cooldowns（App が掛ける）。
//
// 鳴り続ける音（Game の App.withSustained）: 足元の区画の環境音 3 本と、近い敵の唸り（距離で量を下げる）。
// volume に sustainedScale を掛ける（ポーズ・終了の確認の間は 0）。タイトルとクリアの画面は部屋の環境音を menuAmbience の倍率で小さく流す。
mod Sounds {
    use fge::{App, Hash01, Num}
    use Events.Event

    // ── 名前 ──

    /// 頭 family の i 番目の変化の名前（"<頭>_<1..n>"。n は SoundsDoc の variants・変化の無い頭はそのまま）。
    pub def variantOf(sd: SoundsDoc.Rec, family: String, i: Int32): String = match Map.get(family, sd#variants) {
        case Some(n) if n > 0 => "${family}_${Int32.modulo(i, n) + 1}"
        case _                => family
    }

    /// 起きた事 1 つの音の名前の頭（finalZone = 最後の部屋。そこへ入る扉だけ重い音）。
    pub def familyOf(finalZone: Char, e: Event): String = match e {
        case Event.Fired(w)          => "shot_${WeaponsDoc.keyOf(w)}"
        case Event.ShellLanded(_)    => "shell"
        case Event.Pumped            => "shotgun_pump"
        case Event.Ricochet          => "ricochet"
        case Event.EnemyHit(_, _)    => "enemy_hit"
        case Event.EnemyDown(_, d)   => if (d == Events.Death.Burst) "gib" else "enemy_down"
        case Event.Lunge             => "enemy_scream"
        case Event.Charge            => "enemy_charge"
        case Event.Swing             => "enemy_swing"
        case Event.Spit              => "enemy_spit"
        case Event.Burst             => "spit_burst"
        case Event.PlayerHurt(_)     => "player_hurt"
        case Event.PlayerDown        => "player_down"
        case Event.Respawned         => "door"
        case Event.RoomTriggered(id) => if (id == finalZone) "door_heavy" else "door"
        case Event.WaveStarted(_, _) => "alarm"
        case Event.PickedUp(k)       => pickupFamilyOf(k)
        case Event.Switched(w)       => drawFamilyOf(w)
        case Event.DryFire(_)        => "dryfire"
        case Event.Cleared           => "clear"
        case Event.MenuMoved         => "ui_move"
        case Event.Started           => "ui_choose"
        case Event.Paused            => "ui_choose"
        case Event.Resumed           => "ui_choose"
        case Event.MenuChosen        => "ui_choose"
        case Event.ToTitle           => "ui_choose"
        case Event.ClearShown        => "ui_choose"
    }

    def pickupFamilyOf(k: Pickups.Kind): String = match k {
        case Pickups.Kind.HealthSmall   => "pickup_health"
        case Pickups.Kind.HealthLarge   => "pickup_health"
        case Pickups.Kind.AmmoShotgun   => "pickup_ammo"
        case Pickups.Kind.AmmoRifle     => "pickup_ammo"
        case Pickups.Kind.WeaponShotgun => "pickup_weapon"
        case Pickups.Kind.WeaponRifle   => "pickup_weapon"
    }

    /// 持ち替えた先の武器を構える音（散弾銃は先台・連射銃は弾倉）。
    def drawFamilyOf(w: WeaponsDoc.Weapon): String = match w {
        case WeaponsDoc.Weapon.Pistol  => "switch"
        case WeaponsDoc.Weapon.Shotgun => "shotgun_pump"
        case WeaponsDoc.Weapon.Rifle   => "reload"
    }

    // ── 一発の音 ──

    /// このコマに鳴らす音（App.withAudio。before・after は進める前後の World）。
    pub def events(res: Res.Res, before: World.World, after: World.World): List[String] =
        let sd = SoundsDoc.rec(res#sounds);
        let seed = seedOf(after);
        let play = World.sessionOf(after) |> Option.toList |> List.flatMap(World.eventsOf);
        let fromEvents = List.append(World.screenEventsOf(after), play) |> List.zipWithIndex |> List.map(e -> {
            let (i, ev) = e;
            let family = familyOf(res#maze#finalZone, ev);
            (family, variantOf(sd, family, indexOf(after, seed + i, ev)))
        });
        let extra = List.append(stepOf(res, before, after), screamOf(res, before, after));
        limitPerFamily(sd#maxPerFamily, List.append(fromEvents, extra)) |> List.distinct

    /// このコマの種（遊びの時計の千分の一秒。並びの番号を足しても次のコマと重ならないよう 16 倍）。
    def seedOf(w: World.World): Int32 =
        Float64.round(World.seconds(w) * 1000.0) |> Float64.tryToInt32 |> Option.getWithDefault(0) |> (n -> n * 16)

    /// 変化の番号: 撃った音は撃った回数の順に回し、ほかは種から決まった値で選ぶ。
    def indexOf(w: World.World, seed: Int32, e: Event): Int32 = match e {
        case Event.Fired(_) => World.sessionOf(w) |> Option.flatMap(s -> World.arsenalOf(s)#last) |> Option.map(shot -> shot#index) |> Option.getWithDefault(0)
        case _              => Float64.floor(Hash01.at(seed, 17) * 1024.0) |> Float64.tryToInt32 |> Option.getWithDefault(0)
    }

    /// (頭, 名前) の並びから、同じ頭の音をコマに max まで残した名前（並びの前から）。
    pub def limitPerFamily(max: Int32, picks: List[(String, String)]): List[String] =
        let (kept, _) = picks |> List.foldLeft((acc, p) -> {
            let (names, counts) = acc;
            let (family, name) = p;
            let n = Map.getWithDefault(family, 0, counts);
            if (n >= max) acc else (name :: names, Map.insert(family, n + 1, counts))
        }, (Nil, Map.empty()));
        List.reverse(kept)

    /// 足音: 歩いた距離が 1 歩（Walker.stridePhase の π）を越えたコマに 1 つ（走ると速く進むので速く鳴る）。変化は歩数の順に回す。
    def stepOf(res: Res.Res, before: World.World, after: World.World): List[(String, String)] =
        let walk = WalkDoc.rec(res#walk);
        let stepsOf = w -> Float64.floor(Walker.stridePhase(walk, w) / Num.pi()) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        let crossed = World.sessionOf(before) |> Option.flatMap(b -> World.sessionOf(after) |> Option.flatMap(a -> {
            let (wb, wa) = (World.walkerOf(b), World.walkerOf(a));
            let n = stepsOf(wa);
            // WhyNot: 前の体の歩数を前の 1 歩の長さで数えない — 歩くと走るが替わったコマに、長さの違いだけで歩数が跳ねて鳴る。
            if (n > stepsOf({ running = wa#running | wb })) Some(n) else None
        }));
        crossed |> Option.map(n -> ("step_metal", variantOf(SoundsDoc.rec(res#sounds), "step_metal", n))) |> Option.toList

    /// 敵 e がこのコマ（t0 より後・t1 まで）に攻撃を始めたか。
    def isStartingAttack(t0: Float64, t1: Float64, e: Horde.Enemy): Bool = match e#act {
        case Horde.Act.Attack(start, _) => start > t0 and start <= t1
        case _                          => false
    }

    /// 敵の叫び: このコマに攻撃を始めた敵のうち、叫ぶ番（screamChance）に当たって聞こえる距離の内の一番近い 1 体（変化は敵の番号で決まる）。
    def screamOf(res: Res.Res, before: World.World, after: World.World): List[(String, String)] =
        let sd = SoundsDoc.rec(res#sounds);
        let (t0, t1) = (World.seconds(before), World.seconds(after));
        World.sessionOf(after) |> Option.toList |> List.flatMap(s -> {
            let me = World.walkerOf(s);
            Horde.aliveEnemies(World.hordeOf(s))
                |> List.filter(e -> isStartingAttack(t0, t1, e) and Hash01.at(e#id, 33) < sd#screamChance)
                |> List.map(e -> (distanceOf(me#x, me#z, e#x, e#z), e#id))
                |> List.filter(p -> fst(p) <= sd#screamRange)
                |> List.minimum
                |> Option.map(p -> ("enemy_scream", variantOf(sd, "enemy_scream", snd(p))))
                |> Option.toList
        })

    def distanceOf(x0: Float64, z0: Float64, x1: Float64, z1: Float64): Float64 = Num.sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0))

    // ── 鳴り続ける音 ──

    /// 鳴り続ける音（App.withSustained）: 遊んでいる間は足元の区画の環境音と近い敵の唸り（量に sustainedScale を掛ける）・
    /// タイトルとクリアの画面は部屋の環境音を menuAmbience の倍率で。
    pub def sustained(res: Res.Res, w: World.World): List[App.Sustain] =
        let scale = sustainedScale(w);
        match World.sessionOf(w) {
            case Some(s) => List.append(ambienceOf(res, s), growlsOf(res, s)) |> List.map(x -> { volume = x#volume * scale | x })
            case None    => menuAmbienceOf(SoundsDoc.rec(res#sounds))
        }

    /// タイトルとクリアの画面の環境音（部屋の既定 × menuAmbience）。
    def menuAmbienceOf(sd: SoundsDoc.Rec): List[App.Sustain] =
        loopsOf(a -> a * sd#menuAmbience, sd#room)

    /// 環境音 3 本の宣言（量は混ぜ方の各欄を f に通した値）。
    def loopsOf(f: Float64 -> Float64, a: SoundsDoc.Ambience): List[App.Sustain] =
        { name = "amb_machine", volume = f(a#machine), pitch = 1.0 }
            :: { name = "amb_vent", volume = f(a#vent), pitch = 1.0 }
            :: { name = "amb_pipes", volume = f(a#pipes), pitch = 1.0 } :: Nil

    /// 遊んでいる間の鳴り続ける音の音量に掛ける倍率: ポーズも終了の確認もしていない間だけ 1（ほかと、遊んでいない画面は 0）。
    pub def sustainedScale(w: World.World): Float64 =
        if (Option.isEmpty(World.sessionOf(w)) or World.isPaused(w) or World.isAskingQuit(w)) 0.0 else 1.0

    /// 環境音 3 本の量: 足元と、その周り ambienceRadius の 4 点の区画の混ぜ方を平らに混ぜる（戸口をまたぐと少しずつ替わる）。
    /// どの点も壁の中なら通路の混ぜ方。
    def ambienceOf(res: Res.Res, s: World.Session): List[App.Sustain] =
        let sd = SoundsDoc.rec(res#sounds);
        let me = World.walkerOf(s);
        let r = sd#ambienceRadius;
        let mixes = ((0.0, 0.0) :: (r, 0.0) :: (0.0 - r, 0.0) :: (0.0, r) :: (0.0, 0.0 - r) :: Nil)
            |> List.filterMap(o -> Maze.zoneAt(res#maze, me#x + fst(o), me#z + snd(o)))
            |> List.map(zone -> mixOf(res, sd, zone));
        let n = Int32.toFloat64(List.length(mixes));
        let mean = (f: SoundsDoc.Ambience -> Float64) -> if (n == 0.0) f(sd#corridor) else (mixes |> List.foldLeft((acc, a) -> acc + f(a), 0.0)) / n;
        loopsOf(v -> v, { machine = mean(a -> a#machine), vent = mean(a -> a#vent), pipes = mean(a -> a#pipes) })

    /// 区画の環境音の混ぜ方（区画ごとの上書きか、部屋・通路の既定）。
    def mixOf(res: Res.Res, sd: SoundsDoc.Rec, zone: Char): SoundsDoc.Ambience =
        let isRoom = Map.get(zone, res#maze#zones) |> Option.exists(z -> z#kind == MazeDoc.ZoneKind.Room);
        Map.getWithDefault(zone, if (isRoom) sd#room else sd#corridor, sd#zones)

    /// 唸りの量の倍率（距離 d m）: growlNear までは 1、growlFar で 0、その間は 2 乗で下げる。
    pub def growlLevel(sd: SoundsDoc.Rec, d: Float64): Float64 =
        let span = Float64.max(0.001, sd#growlFar - sd#growlNear);
        let k = Num.clamp(0.0, 1.0, (sd#growlFar - d) / span);
        k * k

    /// 近い敵の唸り: 倒れていない敵を近い順に growlVoices 体（変化の数まで）。変化は敵の番号で決め、取られていれば空いている変化を使う
    /// （同じ名前は同時に 1 本しか鳴らないので、近い 2 体が同じ変化を取り合わない）。
    pub def growlsOf(res: Res.Res, s: World.Session): List[App.Sustain] =
        let sd = SoundsDoc.rec(res#sounds);
        let me = World.walkerOf(s);
        let n = Map.getWithDefault("enemy_growl", 1, sd#variants);
        let voices = Int32.min(sd#growlVoices, n);
        let near = Horde.aliveEnemies(World.hordeOf(s))
            |> List.map(e -> (distanceOf(me#x, me#z, e#x, e#z), e#id))
            |> List.filter(p -> fst(p) < sd#growlFar)
            |> List.sort;
        let (voiced, _) = near |> List.foldLeft((acc, p) -> {
            let (out, used) = acc;
            let (d, id) = p;
            let free = List.range(0, n) |> List.map(k -> Int32.modulo(id + k, n)) |> List.find(k -> not Set.memberOf(k, used));
            match free {
                case Some(k) if Set.size(used) < voices =>
                    let pitch = 1.0 + sd#growlPitchSpread * (Hash01.at(id, 41) * 2.0 - 1.0);
                    ({ name = variantOf(sd, "enemy_growl", k), volume = sd#growlVolume * growlLevel(sd, d), pitch = pitch } :: out, Set.insert(k, used))
                case _ => acc
            }
        }, (Nil, Set.empty()));
        List.reverse(voiced)
}
