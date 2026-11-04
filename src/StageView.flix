// StageView — 迷路を一人称で描く（純粋）。
//
// ── 組み方 ──
// 今いる区画から見える区画（Maze の見える区画の組）の灰色の箱と灯りだけを engine の Scene3d 1 つに入れる。
// engine は視錐台の外しか間引かないので、壁の向こうの区画を描かないのはここが決める。
// 霧は距離で施設の暗がりへ沈め、カメラの写す奥行きの端を霧のかかり切る距離にそろえる（霧の先は描かない）。
// 場面は窓の画素の HDR の Pass に描き、PostView がブルーム・トーンマップ・ビネット・粒を掛けて画面へ写す。
mod StageView {
    use fge::{App, Num, Render, Scene3d, SortingLayer, Vec2, Vec3, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値。
    pub type alias In = {
        t = Float64,
        // 目の位置と向き（ラジアン）・縦の画角（度）。
        eye = Vec3.Vec3,
        yaw = Float64,
        pitch = Float64,
        fovY = Float64,
        look = LookDoc.Rec,
        // 描く区画の絵（見える区画の組の分だけ）。
        zones = List[MazeMesh.ZoneArt]
    }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    /// 本編より先に描く Pass の計画（場面 → ブルーム → 後処理）。
    pub def passPlan(w: In): Render.PassPlan =
        let stack = SortingLayer.stack(App.pickCtx(p(World.width(), World.height())), Layer.Scene);
        PostView.chain(w#look, stack(ZStack.leaf(scene(w) :: Nil)), w#t)

    /// 本編の木: トーンマップ済みの後処理の Pass を FXAA でならした面 1 枚。
    pub def frameTree(): ZStack.Tree[Layer, World.Press] = ZStack.leaf(PostView.fxaaFill() :: Nil)

    /// 見える区画を engine の Scene3d 1 つで描く。
    def scene(w: In): Render.PlacedItem =
        let lk = w#look;
        let camera = { eye = w#eye, yaw = w#yaw, pitch = w#pitch, fovY = rad(w#fovY), near = 0.05, far = lk#fogFar };
        Render.scene3d(Vec2.zero(), { instances = w#zones |> List.flatMap(z -> z#instances),
                                      pointLights = w#zones |> List.flatMap(z -> z#lights),
                                      environment = { ambient = lk#ambient, hemisphere = lk#hemisphere, toonSteps = 0,
                                                      fog = Some({ color = lk#fogColor, near = lk#fogNear, far = lk#fogFar }),
                                                      background = None },
                                      time = w#t | Scene3d.scene(camera, p(World.width(), World.height())) })
}
