// Shots — ギャラリーの場面（make render-all の 1 枚）の World を組む。描き出し（SceneRender）と実機（Game の App.withShots。
// START=shot:<場面>）が同じ関数で組むので、実機で開いた場面はギャラリーの絵と同じ World から始まる。
// WhyNot: 描き出しの物（HeadlessRender・HeadlessFont・java.io）を引かない — Game.app から engine_tools へつながり、ブラウザ版で組めなくなる。
mod Shots {
    /// 描き出せる場面の名前（この並びが source of truth。Makefile の SHOTS と assets/*.scenes.json もそろえる）。
    pub def names(): List[String] = "corridor" :: "hall" :: "fire" :: "wall" :: Nil

    /// 構図: 立つマス（列・行）・マスの真ん中から東へずらす距離（m）・向き（度。0 が北・90 が東）・見下ろす角（度）。
    type alias Shot = { col = Int32, row = Int32, dx = Float64, yaw = Float64, pitch = Float64 }

    /// 場面の構図。corridor = 東の長い通路の南の角から北の奥を見る（区画を 3 つまたいだ先まで見通す）・
    /// hall = 最後の広い部屋に入った所から奥を見る・fire = 最後の部屋で的の柱を撃った瞬間（柱から西へ 2 マス・南へ 1 マスの所から柱へ向く）・
    /// wall = 最初の部屋の西の壁に体を付けて壁を見る（銃が壁に埋まらないかを見る 1 枚）。
    def shotOf(name: String): Option[Shot] = match name {
        case "corridor" => Some({ col = 38, row = 34, dx = 0.0, yaw = 0.0, pitch = -2.0 })
        case "hall"     => Some({ col = 18, row = 10, dx = 0.0, yaw = 62.0, pitch = -6.0 })
        case "fire"     => Some({ col = 22, row = 7, dx = 0.0, yaw = 63.43, pitch = 0.0 })
        case "wall"     => Some({ col = 2, row = 34, dx = -1.6, yaw = 270.0, pitch = 0.0 })
        case _          => None
    }

    /// 名前 → 描き出しと同じ初めの World から組んだ場面の World。
    pub def worldOf(name: String, res: Res.Res): Option[World.World] =
        shotOf(name) |> Option.map(s -> {
            let (x, z) = Maze.centerOf(res#maze, { col = s#col, row = s#row });
            let placed = World.placeWalker(res, { x = x + s#dx, z = z }, s#yaw, s#pitch, World.initial(res));
            if (name == "fire") fired(res, placed) else placed
        })

    /// 引き金を引いて 1 回撃った瞬間の World（マズルフラッシュと灯りが点き、照準が反動で跳ね上がった所）。
    // WhyNot: 撃ってから時計を少し進めた World にしない — 時計を進めるのは App だけで、場面の World は実機（START=shot:fire）と共有する。
    def fired(res: Res.Res, w: World.World): World.World =
        World.step(res, { trigger = { pressed = true, held = true } | World.walking(Walker.idle()) }, World.setLooking(true, w))
}
