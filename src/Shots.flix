// Shots — ギャラリーの場面（make render-all の 1 枚）の World を組む。描き出し（SceneRender）と実機（Game の App.withShots。
// START=shot:<場面>）が同じ関数で組むので、実機で開いた場面はギャラリーの絵と同じ World から始まる。
// WhyNot: 描き出しの物（HeadlessRender・HeadlessFont・java.io）を引かない — Game.app から engine_tools へつながり、ブラウザ版で組めなくなる。
mod Shots {
    /// 描き出せる場面の名前（この並びが source of truth。Makefile の SHOTS と assets/*.scenes.json もそろえる）。
    pub def names(): List[String] = "corridor" :: "hall" :: Nil

    /// 構図: 立つマス（列・行）と向き（度。0 が北・90 が東）と見下ろす角（度）。
    type alias Shot = { col = Int32, row = Int32, yaw = Float64, pitch = Float64 }

    /// 場面の構図。corridor = 東の長い通路の南の角から北の奥を見る（区画を 3 つまたいだ先まで見通す）・
    /// hall = 最後の広い部屋に入った所から奥を見る。
    def shotOf(name: String): Option[Shot] = match name {
        case "corridor" => Some({ col = 38, row = 34, yaw = 0.0, pitch = -2.0 })
        case "hall"     => Some({ col = 18, row = 10, yaw = 62.0, pitch = -6.0 })
        case _          => None
    }

    /// 名前 → 描き出しと同じ初めの World から組んだ場面の World。
    pub def worldOf(name: String, res: Res.Res): Option[World.World] =
        shotOf(name) |> Option.map(s -> {
            let (x, z) = Maze.centerOf(res#maze, { col = s#col, row = s#row });
            World.placeWalker(res, { x = x, z = z }, s#yaw, s#pitch, World.initial(res))
        })
}
