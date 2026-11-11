// StageView — 迷路を一人称で描き、手前に腕と銃（ビューモデル）を重ねる（純粋）。
//
// ── 組み方 ──
// 今いる区画から見える区画（Maze の見える区画の組）の絵（ベイクしたステージか灰色の箱）、その区画にいる敵と projectile と拾う物だけを engine の Scene3d 1 つに入れる。
// engine は視錐台の外しか間引かないので、壁の向こうの区画を描かないのはここが決める。
// 霧は距離で施設の暗がりへ沈め、カメラの写す奥行きの端を霧のかかり切る距離にそろえる（霧の先は描かない）。
//
// ── ビューモデル ──
// 腕と銃は 2 つ目の Scene3d に入れ、同じ "scene" の Pass の上（ZStack の後ろ）に重ねる。深度は場面ごとに消えるので、
// 壁に近づいても銃は壁に埋まらない。カメラは照準のカメラと同じ点と向きで、画角と写す奥行きはビューモデルの Doc の物。
// 腕と銃は目の座標で組み、目の座標 → ステージの座標の行列（eyeToWorld）で置く（画面の上の見え方は目の座標で描くのと同じ）。
// WhyNot: 腕と銃の場面を目の座標のまま（原点・正面向きのカメラ）で描かない — 環境マップの映り込みはステージの座標の向きで絵を読むので、
//   振り向いても銃に映る景色が回らない。
// 背景・空・霧は無し（下のステージがそのまま見える）。光の色と向きはステージに合わせる: 環境光と hemisphere は look の値、
// 灯りは見える区画の天井の灯具（ZoneArt の lamps。engine が目に近い 8 本を選ぶ）。強さは FpViewmodelDoc の倍率で沈める（暗い鋼に見せる）。
// 映り込みの景色（環境マップ）は今いる区画の物を、ステージと腕と銃の両方の場面に入れる。
// WhyNot: 灯具の写しをステージの場面へ入れない — 点光源は lightmap の付いた壁にも足されるので、ベイクした灯りの下が二重に明るくなる。
//   ステージの場面の敵と拾う物は、lightmap の付いた物に足されない環境光と hemisphere で照らす。
// 撃った瞬間の灯りは両方の場面に入れる（腕の場面では沈めない）。
//
// 場面は窓の画素の HDR の Pass に描き、PostView がブルーム・トーンマップ・ビネット・粒を掛けて画面へ写す。
mod StageView {
    use fge::{App, Camera3d, Color, Mat4, Num, Render, Scene3d, SortingLayer, Texture3d, Vec2, Vec3, ZStack}
    use ZOrder.Layer

    /// 手前の腕と銃の場面に入れる物（置いた物・粒・灯りはステージの座標。View が目の座標で組んで eyeToWorld で置く）。
    pub type alias Viewmodel = {
        instances = List[Scene3d.Instance3d],
        // 材質が読む絵（glb の絵）。
        textures = List[Texture3d.Texture3d],
        // 銃口に付いて動く粒（マズルフラッシュ）と、撃った瞬間の灯り。
        billboards = List[Scene3d.Billboard3d],
        flash = List[Scene3d.PointLight],
        fovY = Float64,
        near = Float64,
        far = Float64,
        // 光の倍率（環境光と hemisphere・ステージの灯りの写し・映り込みの景色）。
        ambientScale = Float64,
        lampScale = Float64,
        envScale = Float64
    }

    /// 描くのに要る値。
    pub type alias In = {
        t = Float64,
        // 目（照準のカメラ。反動で跳ね上がった角を含む）。
        camera = Camera3d.Camera3d,
        look = LookDoc.Rec,
        // 画面の後処理の面。
        post = PostSpecs.Specs,
        // 描く区画の絵（見える区画の組の分だけ）。
        zones = List[MazeMesh.ZoneArt],
        // ステージの座標の粒（当たった所の火花と煙・体液・弾けた時の輪・projectile の玉・溜めの光）と、撃った瞬間の灯り・弾けた瞬間の光。
        billboards = List[Scene3d.Billboard3d],
        flash = List[Scene3d.PointLight],
        // 敵（姿勢つきの置いた物）と、拾う物（浮いて回る物と床の台座）と、場面の材質が読む絵（ステージの trim sheet と lightmap・敵と拾う武器の glb の絵）。
        creatures = List[Scene3d.Instance3d],
        pickups = List[Scene3d.Instance3d],
        // 弾けた肉片と、連射銃の曳光弾の光る線。
        effects = List[Scene3d.Instance3d],
        textures = List[Texture3d.Texture3d],
        // projectile の玉と拾う物の弱い点光源。
        glows = List[Scene3d.PointLight],
        // 手前の腕と銃（構えている武器の glb が読めていなければ None）。
        viewmodel = Option[Viewmodel],
        // 今いる区画の映り込みの景色（金属っぽさと粗さを持つ材質だけが読む。無ければ None。絵は textures に入っている）。
        environment = Option[Scene3d.EnvironmentMap],
        // 見える区画の非常灯の回転灯の明滅する点光源と、目に近い 1 つの回る筋（ステージと腕と銃の両方の場面に入れる）。
        alarms = List[Scene3d.PointLight],
        beams = List[Scene3d.SpotLight]
    }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def rad(d: Float64): Float64 = d * Num.pi() / 180.0
    def size(): Vec2.Vec2 = p(World.width(), World.height())

    /// 本編より先に描く Pass の計画（場面 → ブルーム → 後処理）。場面の Pass にはステージの上に手前の腕と銃を重ねる。
    pub def passPlan(w: In): Render.PassPlan =
        let stack = SortingLayer.stack(App.pickCtx(size()), Layer.Scene);
        let layers = ZStack.leaf(scene(w) :: Nil) :: (w#viewmodel |> Option.map(h -> ZStack.leaf(viewmodelScene(w, h) :: Nil)) |> Option.toList);
        PostView.chain(w#look, w#post, stack(ZStack.of(layers)), w#t)

    /// 本編の木: トーンマップ済みの後処理の Pass を FXAA でならした面 1 枚。
    pub def frameTree(post: PostSpecs.Specs): ZStack.Tree[Layer, World.Press] = ZStack.leaf(PostView.fxaaFill(post) :: Nil)

    /// ステージの場面に入れる灯り（見える区画の分。ベイクしたステージは空）。
    def stageLights(w: In): List[Scene3d.PointLight] = w#zones |> List.flatMap(z -> z#lights)

    /// 天井の灯具の灯り（見える区画の分。手前の腕と銃へ写す）。
    def lampLights(w: In): List[Scene3d.PointLight] = w#zones |> List.flatMap(z -> z#lamps)

    /// 見える区画を engine の Scene3d 1 つで描く。
    def scene(w: In): Render.PlacedItem =
        let lk = w#look;
        Render.scene3d(Vec2.zero(), { instances = List.flatten((w#zones |> List.flatMap(z -> z#instances)) :: w#creatures :: w#pickups :: w#effects :: Nil),
                                      textures = w#textures,
                                      billboards = w#billboards,
                                      pointLights = List.flatten(w#flash :: w#alarms :: w#glows :: stageLights(w) :: Nil), spotLights = w#beams,
                                      environment = { ambient = lk#ambient, hemisphere = lk#hemisphere, toonSteps = 0,
                                                      fog = Some({ color = lk#fogColor, near = lk#fogNear, far = lk#fogFar }),
                                                      background = None },
                                      time = w#t, environmentMap = w#environment | Scene3d.scene(w#camera, size()) })

    /// 目の座標の点 at をステージの座標へ写す（目の座標 = 右が +X・上が +Y・前が +Z）。
    pub def fromEye(c: Camera3d.Camera3d, at: Vec3.Vec3): Vec3.Vec3 = Mat4.apply(eyeToWorld(c), at)

    /// 目の座標 → ステージの座標の行列（カメラの右・上・前を列に、目の点へ動かす）。
    pub def eyeToWorld(c: Camera3d.Camera3d): Mat4.Mat4 =
        let (r, u, f) = (Camera3d.right(c), Camera3d.up(c), Camera3d.forward(c));
        Mat4.mul(Mat4.translate(c#eye), Mat4.ofLinearRows(Vec3.v3(r#x, u#x, f#x), Vec3.v3(r#y, u#y, f#y), Vec3.v3(r#z, u#z, f#z)))

    /// 画面の値の色の 1 成分 c を、線形の量で k 倍した画面の値（描き手は色を線形へ戻してから光を足す）。
    def dim(c: Float64, k: Float64): Float64 = Texture3d.linearToSrgb(Texture3d.srgbToLinear(c) * Float64.max(0.0, k))

    /// 手前の腕と銃の場面（照準のカメラの点と向き・ビューモデルの画角と奥行き・背景と空と霧は無し）。置いた物と粒と灯りはステージの座標。
    def viewmodelScene(w: In, h: Viewmodel): Render.PlacedItem =
        let lk = w#look;
        let camera = { fovY = rad(h#fovY), near = h#near, far = h#far | w#camera };
        let lamps = lampLights(w) |> List.map(l -> { intensity = l#intensity * h#lampScale | l });
        let ambient = Color.rgb(dim(lk#ambient#r, h#ambientScale), dim(lk#ambient#g, h#ambientScale), dim(lk#ambient#b, h#ambientScale));
        Render.scene3d(Vec2.zero(), { instances = h#instances, textures = h#textures, billboards = h#billboards,
                                      pointLights = List.flatten(h#flash :: w#alarms :: lamps :: Nil), spotLights = w#beams,
                                      environment = { ambient = ambient, hemisphere = lk#hemisphere * h#ambientScale, toonSteps = 0, fog = None, background = None },
                                      time = w#t, environmentMap = w#environment |> Option.map(scaled(h#envScale)) | Scene3d.scene(camera, size()) })

    /// 映り込みの景色の明るさを k 倍した物。
    def scaled(k: Float64, e: Scene3d.EnvironmentMap): Scene3d.EnvironmentMap =
        Scene3d.withEnvironmentIntensity(Scene3d.environmentMapFieldsOf(e)#intensity * k, e)
}
