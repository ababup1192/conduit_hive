// Shots — ギャラリーの場面（make render-all の 1 枚）の World を組む。描き出し（SceneRender）と実機（Game の App.withShots。
// START=shot:<場面>）が同じ関数で組むので、実機で開いた場面はギャラリーの絵と同じ World から始まる。
// WhyNot: 描き出しの物（HeadlessRender・HeadlessFont・java.io）を引かない — Game.app から engine_tools へつながり、ブラウザ版で組めなくなる。
mod Shots {
    use fge::{Hash01, Num, Vec3}

    /// 描き出せる場面の名前（この並びが source of truth。Makefile の SHOTS と assets/*.scenes.json もそろえる）。
    pub def names(): List[String] = "corridor" :: "hall" :: "fire" :: "wall" :: "horde" :: "fight" :: "title" :: "pickups" :: "clear" :: Nil

    /// 構図: 立つマス（列・行）・マスの真ん中から東へずらす距離（m）・向き（度。0 が北・90 が東）・見下ろす角（度）。
    type alias Shot = { col = Int32, row = Int32, dx = Float64, yaw = Float64, pitch = Float64 }

    /// 場面の構図。corridor = 東の長い通路の南の角から北の奥を見る（区画を 3 つまたいだ先まで見通す）・
    /// hall = 最後の広い部屋に入った所から奥を見る・fire = 最後の部屋で的の柱を撃った瞬間（柱から西へ 2 マス・南へ 1 マスの所から柱へ向く）・
    /// wall = 最初の部屋の西の壁に体を付けて壁を見る（銃が壁に埋まらないかを見る 1 枚）・
    /// horde = 最後の部屋の西の端から東を向き、40 体の群れが迫ってくる所・fight = 同じ所で近い群れを撃ち、何体か倒れている所・
    /// pickups = 最初の部屋から東の通路を抜けた先の部屋の入口から北東を見る（散弾銃と、その奥に弾倉が浮いている）。
    /// title と clear は構図を持たない画面（titleWorld・clearWorld）。
    def shotOf(name: String): Option[Shot] = match name {
        case "corridor" => Some({ col = 38, row = 34, dx = 0.0, yaw = 0.0, pitch = -2.0 })
        case "hall"     => Some({ col = 18, row = 10, dx = 0.0, yaw = 62.0, pitch = -6.0 })
        case "fire"     => Some({ col = 22, row = 7, dx = 0.0, yaw = 63.43, pitch = 0.0 })
        case "wall"     => Some({ col = 2, row = 34, dx = -1.6, yaw = 270.0, pitch = 0.0 })
        case "horde"    => Some({ col = 16, row = 6, dx = 0.0, yaw = 90.0, pitch = -3.0 })
        case "fight"    => Some({ col = 16, row = 6, dx = 0.0, yaw = 90.0, pitch = 0.0 })
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
                case "fight" => fired(res, felled(res, crowded(res, 22, viewer, placed)))
                case _       => placed
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
            Horde.applyDamage(res, at, 1000.0, { struck = Hitscan.Struck.Enemy(id, Hitscan.Part.Body), point = Vec3.zero(), normal = Vec3.zero() } :: Nil, acc)#horde;
        World.mapHorde(h -> h |> fell(0, -1.5) |> fell(4, -0.35) |> fell(7, -0.8), w)

    /// 引き金を引いて 1 回撃った瞬間の World（マズルフラッシュと灯りが点き、照準が反動で跳ね上がった所）。
    // WhyNot: 撃ってから時計を少し進めた World にしない — 時計を進めるのは App だけで、場面の World は実機（START=shot:fire）と共有する。
    def fired(res: Res.Res, w: World.World): World.World =
        World.step(res, { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) }, World.setLooking(true, w))
}
