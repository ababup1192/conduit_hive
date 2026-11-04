// StageView — 迷路を一人称で描き、手前に腕と銃（ビューモデル）を重ねる（純粋）。
//
// ── 組み方 ──
// 今いる区画から見える区画（Maze の見える区画の組）の灰色の箱と灯り、その区画にいる敵と projectile だけを engine の Scene3d 1 つに入れる。
// engine は視錐台の外しか間引かないので、壁の向こうの区画を描かないのはここが決める。
// 霧は距離で施設の暗がりへ沈め、カメラの写す奥行きの端を霧のかかり切る距離にそろえる（霧の先は描かない）。
//
// ── ビューモデル ──
// 腕と銃は 2 つ目の Scene3d に入れ、同じ "scene" の Pass の上（ZStack の後ろ）に重ねる。深度は場面ごとに消えるので、
// 壁に近づいても銃は壁に埋まらない。カメラは原点・正面向きで、画角と写す奥行きはビューモデルの Doc の物。
// 背景・空・霧は無し（下のステージがそのまま見える）。光の色と向きはステージに合わせる: 環境光と hemisphere は look の値、
// 灯りはステージの灯りを目の座標へ写した物（engine が目に近い 8 本を選ぶ）。強さは HandsDoc の倍率で沈める（暗い鋼に見せる）。
// 撃った瞬間の灯りは両方の場面に入れる（腕の場面では沈めない）。
//
// 場面は窓の画素の HDR の Pass に描き、PostView がブルーム・トーンマップ・ビネット・粒を掛けて画面へ写す。
mod StageView {
    use fge::{App, Camera3d, Color, Num, Render, Scene3d, SortingLayer, Texture3d, Vec2, Vec3, ZStack}
    use ZOrder.Layer

    /// 手前の腕と銃の場面に入れる物（座標はビューモデルの場面の座標 = 目の座標）。
    pub type alias Hands = {
        instances = List[Scene3d.Instance3d],
        // 材質が読む絵（glb の絵）。
        textures = List[Texture3d.Texture3d],
        // 銃口に付いて動く粒（マズルフラッシュ）と、撃った瞬間の灯り。
        billboards = List[Scene3d.Billboard3d],
        flash = List[Scene3d.PointLight],
        fovY = Float64,
        near = Float64,
        far = Float64,
        // 光の倍率（環境光と hemisphere・ステージの灯りの写し）。
        ambientScale = Float64,
        lampScale = Float64
    }

    /// 描くのに要る値。
    pub type alias In = {
        t = Float64,
        // 目（照準のカメラ。反動で跳ね上がった角を含む）。
        camera = Camera3d.Camera3d,
        look = LookDoc.Rec,
        // 描く区画の絵（見える区画の組の分だけ）。
        zones = List[MazeMesh.ZoneArt],
        // ステージの座標の粒（当たった所の火花・体液・projectile の玉）と、撃った瞬間の灯り。
        billboards = List[Scene3d.Billboard3d],
        flash = List[Scene3d.PointLight],
        // 敵（姿勢つきの置いた物）と、敵の材質が読む絵。
        creatures = List[Scene3d.Instance3d],
        creatureTextures = List[Texture3d.Texture3d],
        // projectile の玉の点光源。
        glows = List[Scene3d.PointLight],
        // 手前の腕と銃（構えている武器の glb が読めていなければ None）。
        hands = Option[Hands]
    }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def rad(d: Float64): Float64 = d * Num.pi() / 180.0
    def size(): Vec2.Vec2 = p(World.width(), World.height())

    /// 本編より先に描く Pass の計画（場面 → ブルーム → 後処理）。場面の Pass にはステージの上に手前の腕と銃を重ねる。
    pub def passPlan(w: In): Render.PassPlan =
        let stack = SortingLayer.stack(App.pickCtx(size()), Layer.Scene);
        let layers = ZStack.leaf(scene(w) :: Nil) :: (w#hands |> Option.map(h -> ZStack.leaf(handsScene(w, h) :: Nil)) |> Option.toList);
        PostView.chain(w#look, stack(ZStack.of(layers)), w#t)

    /// 本編の木: トーンマップ済みの後処理の Pass を FXAA でならした面 1 枚。
    pub def frameTree(): ZStack.Tree[Layer, World.Press] = ZStack.leaf(PostView.fxaaFill() :: Nil)

    /// ステージの灯り（見える区画の分）。
    def stageLights(w: In): List[Scene3d.PointLight] = w#zones |> List.flatMap(z -> z#lights)

    /// 見える区画を engine の Scene3d 1 つで描く。
    def scene(w: In): Render.PlacedItem =
        let lk = w#look;
        Render.scene3d(Vec2.zero(), { instances = List.append(w#zones |> List.flatMap(z -> z#instances), w#creatures),
                                      textures = w#creatureTextures,
                                      billboards = w#billboards,
                                      pointLights = List.append(w#flash, List.append(w#glows, stageLights(w))),
                                      environment = { ambient = lk#ambient, hemisphere = lk#hemisphere, toonSteps = 0,
                                                      fog = Some({ color = lk#fogColor, near = lk#fogNear, far = lk#fogFar }),
                                                      background = None },
                                      time = w#t | Scene3d.scene(w#camera, size()) })

    /// ステージの点 at を目の座標（右が +X・上が +Y・前が +Z）へ写す。
    def toEye(c: Camera3d.Camera3d, at: Vec3.Vec3): Vec3.Vec3 =
        let d = Vec3.sub(at, c#eye);
        Vec3.v3(Vec3.dot(d, Camera3d.right(c)), Vec3.dot(d, Camera3d.up(c)), Vec3.dot(d, Camera3d.forward(c)))

    /// 目の座標の点 at をステージの座標へ戻す（toEye の逆）。
    pub def fromEye(c: Camera3d.Camera3d, at: Vec3.Vec3): Vec3.Vec3 =
        Vec3.add(c#eye, Vec3.add(Vec3.mul(Camera3d.right(c), at#x), Vec3.add(Vec3.mul(Camera3d.up(c), at#y), Vec3.mul(Camera3d.forward(c), at#z))))

    /// 画面の値の色の 1 成分 c を、線形の量で k 倍した画面の値（描き手は色を線形へ戻してから光を足す）。
    def dim(c: Float64, k: Float64): Float64 = Texture3d.linearToSrgb(Texture3d.srgbToLinear(c) * Float64.max(0.0, k))

    /// 手前の腕と銃の場面（原点から正面を見るカメラ・背景と空と霧は無し）。
    def handsScene(w: In, h: Hands): Render.PlacedItem =
        let lk = w#look;
        let camera = { eye = Vec3.zero(), yaw = 0.0, pitch = 0.0, fovY = rad(h#fovY), near = h#near, far = h#far };
        let lamps = stageLights(w) |> List.map(l -> { position = toEye(w#camera, l#position), intensity = l#intensity * h#lampScale | l });
        let ambient = Color.rgb(dim(lk#ambient#r, h#ambientScale), dim(lk#ambient#g, h#ambientScale), dim(lk#ambient#b, h#ambientScale));
        Render.scene3d(Vec2.zero(), { instances = h#instances, textures = h#textures, billboards = h#billboards,
                                      pointLights = List.append(h#flash, lamps),
                                      environment = { ambient = ambient, hemisphere = lk#hemisphere * h#ambientScale, toonSteps = 0, fog = None, background = None },
                                      time = w#t | Scene3d.scene(camera, size()) })
}
