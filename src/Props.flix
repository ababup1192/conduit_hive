// Props — 迷路に立てる仮の物（純粋）。今は撃つ練習の的の柱だけ: 最後の部屋の真ん中から 2 マス西に、床から天井まで立つ角柱。
// 敵が来る段までの仮置きで、当たると火花が出るだけ（壊れない・動かない・音を出さない）。
// 当たり判定の箱（体を止める・弾を止める）と絵（鋼の柱と光る筋の帯）を同じ箱から作る。
mod Props {
    use fge::{CollisionShape3d, Mat4, Scene3d, Vec3}

    /// 柱の太さ（m）。
    def pillarWidth(): Float64 = 1.0

    /// 真ん中のマスから西へずらすマスの数。
    // WhyNot: 真ん中のマスに立てない — 測り（make bench-horde）が真ん中に立つので、柱の中に立ってしまう。
    def pillarShift(): Int32 = 2

    /// 光る筋の帯の高さ（m）と厚さ（m）。
    def bandHeights(): List[Float64] = 1.5 :: 2.6 :: Nil
    def bandThick(): Float64 = 0.08

    /// 的の柱の箱（最後の部屋が無い迷路では空）。
    pub def pillarsOf(m: Maze.Maze): List[CollisionShape3d.Box3d] =
        Maze.middleCellOf(m, m#finalZone) |> Option.toList |> List.map(cell -> {
            let (cx, cz) = Maze.centerOf(m, { col = cell#col - pillarShift() | cell });
            let h = Maze.heightAt(m, cell);
            CollisionShape3d.box3d(Vec3.v3(cx, h / 2.0, cz), Vec3.v3(pillarWidth() / 2.0, h / 2.0, pillarWidth() / 2.0))
        })

    def sizeOf(b: CollisionShape3d.Box3d): Vec3.Vec3 = Vec3.mul(b#half, 2.0)

    /// 的の柱の絵: 壁と同じ鋼の色の角柱と、光る筋の色の帯。
    pub def artOf(look: LookDoc.Rec, pillars: List[CollisionShape3d.Box3d]): List[Scene3d.Instance3d] =
        if (List.isEmpty(pillars)) Nil
        else {
            let bodies = pillars |> List.map(b -> { center = b#center, size = sizeOf(b) });
            let bands = pillars |> List.flatMap(b -> bandHeights() |> List.map(y ->
                { center = Vec3.v3(b#center#x, y, b#center#z), size = Vec3.v3(sizeOf(b)#x + 0.04, bandThick(), sizeOf(b)#z + 0.04) }));
            Scene3d.meshInstance(BoxMesh.of(look#wallColor, bodies), Mat4.identity()) |> Scene3d.withName("prop:pillar")
                :: (Scene3d.meshInstance(BoxMesh.of(look#stripColor, bands), Mat4.identity()) |> Scene3d.withName("prop:pillar-band")
                        |> Scene3d.withMaterial(MazeMesh.glowMaterial("conduit_prop_band", look#stripColor, look#stripIntensity)))
                :: Nil
        }
}
