// Starts — 始まりの登録簿（App.withStarts。Game が Resources.liftStart で組の行へ持ち上げる）。名前と引数から、新しく作った初期の World を場面へ組む。
// 起動（START="at x=18 z=26 yaw=0"）・リモートの POST /start・flow の `start at`・テストの App.startOrBug が同じ表を引く。
mod Starts {
    use fge::Resources

    /// 登録簿。先頭が起動の既定。
    pub def all(): List[Resources.Start[Res.Res, World.World]] =
        { name = "play", doc = "迷路の start の印に立つ所（起動の既定）", args = Map.empty(), build = (_, w, _) -> Ok(w) } ::
        { name = "at", doc = "体を x・z（m）に置き、yaw（度。0 が北・90 が東）を向いた所", args = Map#{"x" => "0", "z" => "0", "yaw" => "0"}, build = at } :: Nil

    def at(res: Res.Res, w: World.World, args: Map[String, String]): Result[String, World.World] =
        forM (
            x <- numOf("x", args);
            z <- numOf("z", args);
            yaw <- numOf("yaw", args)
        ) yield World.placeWalker(res, { x = x, z = z }, yaw, 0.0, w)

    def numOf(name: String, args: Map[String, String]): Result[String, Float64] =
        let text = Map.getWithDefault(name, "0", args);
        Float64.fromString(text) |> Option.toOk("${name} は数（'${text}'）")
}
