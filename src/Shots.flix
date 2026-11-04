// Shots — ギャラリーの場面（make render-all の 1 枚）の World を組む。描き出し（SceneRender）と実機（Game の App.withShots。
// START=shot:<場面>）が同じ関数で組むので、実機で開いた場面はギャラリーの絵と同じ World から始まる。
// WhyNot: 描き出しの物（HeadlessRender・HeadlessFont・java.io）を引かない — Game.app から engine_tools へつながり、ブラウザ版で組めなくなる。
mod Shots {
    use fge::{Hash01, Num, Vec3}

    /// 描き出せる場面の名前（この並びが source of truth。Makefile の SHOTS と assets/*.scenes.json もそろえる）。
    pub def names(): List[String] = "corridor" :: "hall" :: "fire" :: "wall" :: "horde" :: "fight" :: "gib" :: "fling" :: "tracer" :: "title" :: "pickups" :: "clear" :: Nil

    /// 構図: 立つマス（列・行）・マスの真ん中から東へずらす距離（m）・向き（度。0 が北・90 が東）・見下ろす角（度）。
    type alias Shot = { col = Int32, row = Int32, dx = Float64, yaw = Float64, pitch = Float64 }

    /// 場面の構図。corridor = 東の長い通路の南の角から北の奥を見る（区画を 3 つまたいだ先まで見通す）・
    /// hall = 最後の広い部屋に入った所から奥を見る・fire = 最後の部屋で的の柱を撃った瞬間（柱から西へ 2 マス・南へ 1 マスの所から柱へ向く）・
    /// wall = 最初の部屋の西の壁に体を付けて壁を見る（銃が壁に埋まらないかを見る 1 枚）・
    /// horde = 最後の部屋の西の端から東を向き、40 体の群れが迫ってくる所・fight = 同じ所で近い群れを撃ち、何体か倒れている所・
    /// gib = 同じ所で散弾銃を構え、群れの前へ飛び出した 1 体が 2.8 m 先で弾けて 0.15 秒たった所（肉片・体液・衝撃の輪・弾けた光・倒した印）・
    /// fling = 同じ所で散弾銃で倒した 3 体が撃たれた向きへ吹っ飛んで 0.18 秒たった所・
    /// tracer = 同じ所で北寄りの奥を向いて連射銃を撃ち続け、曳光弾が奥の壁へ飛んでいる所（群れは右の手前から迫る）・
    /// pickups = 最初の部屋から東の通路を抜けた先の部屋の入口から北東を見る（散弾銃と、その奥に弾倉が浮いている）。
    /// title と clear は構図を持たない画面（titleWorld・clearWorld）。
    def shotOf(name: String): Option[Shot] = match name {
        case "corridor" => Some({ col = 38, row = 34, dx = 0.0, yaw = 0.0, pitch = -2.0 })
        case "hall"     => Some({ col = 18, row = 10, dx = 0.0, yaw = 62.0, pitch = -6.0 })
        case "fire"     => Some({ col = 22, row = 7, dx = 0.0, yaw = 63.43, pitch = 0.0 })
        case "wall"     => Some({ col = 2, row = 34, dx = -1.6, yaw = 270.0, pitch = 0.0 })
        case "horde"    => Some({ col = 16, row = 6, dx = 0.0, yaw = 90.0, pitch = -3.0 })
        case "fight"    => Some({ col = 16, row = 6, dx = 0.0, yaw = 90.0, pitch = 0.0 })
        case "gib"      => Some({ col = 16, row = 6, dx = 0.0, yaw = 90.0, pitch = 3.0 })
        case "fling"    => Some({ col = 16, row = 6, dx = 0.0, yaw = 90.0, pitch = 2.0 })
        case "tracer"   => Some({ col = 16, row = 6, dx = 0.0, yaw = 72.0, pitch = -2.0 })
        case "pickups"  => Some({ col = 15, row = 34, dx = 0.0, yaw = 45.0, pitch = 12.0 })
        case _          => None
    }

    /// 名前 → 描き出しと同じ初めの World から組んだ場面の World。
    pub def worldOf(name: String, res: Res.Res): Option[World.World] = match name {
        case "title" => Some(World.title())
        case "clear" => Some(clearWorld(res))
        case _       => playWorldOf(name, res)
    }

    /// クリアの画面: 最後の部屋の真ん中の 2 マス東で西を向いて終えた記録（5 分 12 秒・96 体）。
    def clearWorld(res: Res.Res): World.World =
        let (x, z) = Maze.middleCellOf(res#maze, res#maze#finalZone) |> Option.map(c -> Maze.centerOf(res#maze, { col = c#col + 2 | c }))
            |> Option.getWithDefault((res#maze#start#x, res#maze#start#z));
        { screen = World.Screen.Clear({ seconds = 312.4, kills = 96, x = x, z = z, yaw = Num.pi() * 1.5, endedAt = 0.0 }) | World.title() }

    /// 遊んでいる場面（構図のある場面）。
    def playWorldOf(name: String, res: Res.Res): Option[World.World] =
        shotOf(name) |> Option.map(s -> {
            let (x, z) = Maze.centerOf(res#maze, { col = s#col, row = s#row });
            let viewer = { x = x + s#dx, z = z, yaw = s#yaw * Num.pi() / 180.0 };
            let placed = World.settleZone(res, World.placeWalker(res, { x = viewer#x, z = viewer#z }, s#yaw, s#pitch, World.initial(res)));
            match name {
                case "fire"  => fired(res, placed)
                case "horde" => crowded(res, 40, viewer, placed)
                case "fight"  => fired(res, felled(res, crowded(res, 22, viewer, placed)))
                case "gib"    => popped(res, viewer, crowded(res, 14, viewer, armed(res, WeaponsDoc.Weapon.Shotgun, placed)))
                case "fling"  => flung(res, viewer, crowded(res, 16, viewer, armed(res, WeaponsDoc.Weapon.Shotgun, placed)))
                case "tracer" => streaked(res, crowded(res, 18, { yaw = viewer#yaw + 0.31 | viewer }, armed(res, WeaponsDoc.Weapon.Rifle, placed)))
                case _        => placed
            }
        })

    /// 前に count 体の群れを置く: 目の前 4〜22 m の扇に、列ごとに左右へ散らす（5 体に 1 体が ranged）。
    /// 群れは湧いた時の walk の構えで、1 コマ考えさせて（時計は進めない）向きと構えを決める。
    def crowded(res: Res.Res, count: Int32, b: { x = Float64, z = Float64, yaw = Float64 }, w: World.World): World.World =
        let (fx, fz) = (Num.sin(b#yaw), Num.cos(b#yaw));
        let spawns = List.range(0, count) |> List.map(i -> {
            let ahead = 4.0 + Int32.toFloat64(i / 5) * 2.2 + Hash01.at(i, 81) * 1.2;
            let side = (Int32.toFloat64(Int32.modulo(i, 5)) - 2.0) * (1.6 + Int32.toFloat64(i / 5) * 0.35) + (Hash01.at(i, 82) - 0.5) * 0.8;
            let (x, z) = (b#x + fx * ahead + fz * side, b#z + fz * ahead - fx * side);
            { kind = if (Int32.modulo(i, 5) == 3) Creatures.Kind.Ranged else Creatures.Kind.Melee, x = x, z = z,
              yaw = Num.atan2(b#x - x, b#z - z), home = res#maze#finalZone }
        });
        World.mapHorde(Horde.spawnNow(res, spawns), w)

    /// 群れの 1 列目の左右と 2 列目の真ん中を、時刻の少し前に倒しておく（倒れる途中と倒れ切った所が並ぶ）。
    def felled(res: Res.Res, w: World.World): World.World =
        let fell = (id: Int32, at: Float64, acc: Horde.Horde) ->
            Horde.applyDamage(res, { t = at, damage = 1000.0, weapon = WeaponsDoc.Weapon.Pistol, origin = Vec3.zero(), index = id },
                { struck = Hitscan.Struck.Enemy(id, Hitscan.Part.Body), point = Vec3.zero(), normal = Vec3.zero() } :: Nil, acc)#horde;
        World.mapHorde(h -> h |> fell(0, -1.5) |> fell(4, -0.35) |> fell(7, -0.8), w)

    /// 武器 w を構えた World。
    def armed(res: Res.Res, w: WeaponsDoc.Weapon, world: World.World): World.World = World.mapArsenal(Arsenal.readied(res#weapons, w), world)

    /// 足元 b に立つ目の高さのプレイヤーの体（群れを進める場面が使う）。
    def bodyAt(res: Res.Res, b: { x = Float64, z = Float64, yaw = Float64 }): PlayerBody.PlayerBody =
        let walk = WalkDoc.rec(res#walk);
        { x = b#x, feet = 0.0, z = b#z, eye = Vec3.v3(b#x, walk#eyeHeight, b#z), yaw = b#yaw, radius = walk#radius, height = walk#height }

    /// 1 コマの長さ（場面の中で肉片と群れを進める刻み）。
    def frameSeconds(): Float64 = 1.0 / 60.0

    /// 群れの前へ飛び出した 1 体（番号 1。目の前 2.8 m・左へ 0.9 m）が弾けてから 9 コマ（0.15 秒）たった所: その体を群れから消し、肉片を 9 コマ飛ばし、
    /// 体液と衝撃の輪と倒した印をその時刻に置く。
    // WhyNot: 撃ってから時計を進めた World にしない — 時計を進めるのは App だけ。弾けた時刻を前へずらし、肉片だけを刻みで進める。
    def popped(res: Res.Res, b: { x = Float64, z = Float64, yaw = Float64 }, w: World.World): World.World =
        let (fx, fz) = (Num.sin(b#yaw), Num.cos(b#yaw));
        let born = -9.0 * frameSeconds();
        let center = Vec3.v3(b#x + fx * 2.8 - fz * 0.9, 1.2, b#z + fz * 2.8 + fx * 0.9);
        let gd = JuiceDoc.rec(res#juice)#gib;
        let isClear = (p: Vec3.Vec3, q: Vec3.Vec3) -> Collider.isLineClear(res#collision, p, q);
        let flown = List.range(1, 10) |> List.foldLeft((g, i) -> Gibs.step(gd, isClear, born + Int32.toFloat64(i) * frameSeconds(), frameSeconds(), g),
            Gibs.burst(gd, res#gibArt, born, 7, center, fx, fz, Gibs.empty()));
        let up = Vec3.v3(0.0, 1.0, 0.0);
        let splash = List.append(Particles3d.emit(res#particles, Particles3d.Kind.Gore, Particles3d.Space.World, center, Vec3.v3(fx, 0.35, fz), born, 112),
                                 Particles3d.emit(res#particles, Particles3d.Kind.Ring, Particles3d.Space.World, center, up, born, 113));
        World.mapHorde(h -> { enemies = List.filter(e -> e#id != 1, h#enemies) | h }, w)
            |> World.mapEffects(e -> { particles = List.append(splash, e#particles), gibs = flown, marks = { hitAt = born, killAt = born } | e })

    /// 散弾銃で群れの 1 列目の両端の 2 体と 2 列目の 1 体（5〜7 m 先。弾ける近さの外）を倒してから 11 コマたった所:
    /// 撃たれた向き（両端は斜め外）への放物線と横の回転の途中。
    def flung(res: Res.Res, b: { x = Float64, z = Float64, yaw = Float64 }, w: World.World): World.World =
        let shotAt = -11.0 * frameSeconds();
        let eye = bodyAt(res, b)#eye;
        let health = EnemiesDoc.rec(res#enemies)#melee#health;
        let fell = (id: Int32, acc: Horde.Horde) ->
            Horde.applyDamage(res, { t = shotAt, damage = health, weapon = WeaponsDoc.Weapon.Shotgun, origin = eye, index = id },
                { struck = Hitscan.Struck.Enemy(id, Hitscan.Part.Body), point = Vec3.zero(), normal = Vec3.zero() } :: Nil, acc)#horde;
        World.mapHorde(h -> Horde.simulate(res, shotAt, frameSeconds(), 11, bodyAt(res, b), h |> fell(0) |> fell(4) |> fell(7))#horde, w)
            |> World.mapEffects(e -> { marks = { hitAt = shotAt, killAt = shotAt } | e })

    /// 連射銃を撃ち続けている所: 0.02 秒おきに撃った 6 発の曳光弾（照準の先の群れと壁へ）と、今撃った 1 発のマズルフラッシュ。
    def streaked(res: Res.Res, w: World.World): World.World =
        let rifle = WeaponsDoc.statsOf(WeaponsDoc.Weapon.Rifle, res#weapons);
        let tracers = World.sessionOf(w) |> Option.toList |> List.flatMap(s -> {
            let aim = World.aimCameraOf(res, 0.0, s);
            let targets = List.append(Horde.targetsOf(World.hordeOf(s)), res#hitTargets);
            List.range(0, 6) |> List.map(i -> World.tracerOf(aim, rifle#range, Hitscan.fire(targets, aim, rifle, i), -0.02 * Int32.toFloat64(i) - 0.012))
        });
        let flash = Particles3d.emit(res#particles, Particles3d.Kind.Muzzle(WeaponsDoc.Weapon.Rifle), Particles3d.Space.Muzzle,
            Vec3.v3(0.0, 0.0, Particles3d.muzzleOf(res#particles, WeaponsDoc.Weapon.Rifle)#size * 0.5), Vec3.v3(0.0, 0.0, 1.0), 0.0, 6);
        World.mapEffects(e -> { tracers = tracers, particles = List.append(flash, e#particles) | e }, w)

    /// 引き金を引いて 1 回撃った瞬間の World（マズルフラッシュと灯りが点き、照準が反動で跳ね上がった所）。
    // WhyNot: 撃ってから時計を少し進めた World にしない — 時計を進めるのは App だけで、場面の World は実機（START=shot:fire）と共有する。
    def fired(res: Res.Res, w: World.World): World.World =
        World.step(res, { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) }, World.setLooking(true, w))
}
