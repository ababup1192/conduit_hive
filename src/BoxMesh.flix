// BoxMesh — 軸にそろった箱の列を 1 つの形にまとめる（純粋）。頂点の色で上を向く面ほど明るくする。
// 区画ごとの仮置き（測りのパイプ・撃つ的の柱）が使う。Blender で組む本番の形はここを通らない。
mod BoxMesh {
    use fge::{Color, Log, Mesh3d, Vec3}

    /// 箱 1 つ: 真ん中と大きさ（m。半分ではなく全体の長さ）。
    pub type alias Box = { center = Vec3.Vec3, size = Vec3.Vec3 }

    /// 面 6 枚: 外向きの向きと、面の上の 2 本の軸。
    def faces(): List[(Vec3.Vec3, Vec3.Vec3)] =
        (Vec3.v3(1.0, 0.0, 0.0), Vec3.v3(0.0, 1.0, 0.0)) :: (Vec3.v3(-1.0, 0.0, 0.0), Vec3.v3(0.0, 1.0, 0.0))
            :: (Vec3.v3(0.0, 1.0, 0.0), Vec3.v3(0.0, 0.0, 1.0)) :: (Vec3.v3(0.0, -1.0, 0.0), Vec3.v3(0.0, 0.0, 1.0))
            :: (Vec3.v3(0.0, 0.0, 1.0), Vec3.v3(0.0, 1.0, 0.0)) :: (Vec3.v3(0.0, 0.0, -1.0), Vec3.v3(0.0, 1.0, 0.0)) :: Nil

    def scaled(a: Vec3.Vec3, b: Vec3.Vec3): Vec3.Vec3 = Vec3.v3(a#x * b#x, a#y * b#y, a#z * b#z)

    /// 箱 1 つの頂点 24 個（面ごとに 4 つ）。上を向く面ほど明るい。
    def boxPoints(color: Color, b: Box): List[(Vec3.Vec3, Vec3.Vec3, Color)] =
        let h = Vec3.mul(b#size, 0.5);
        faces() |> List.flatMap(f -> {
            let (n, v) = f;
            let u = Vec3.cross(n, v);
            let c0 = Vec3.add(b#center, scaled(n, h));
            let du = scaled(u, h);
            let dv = scaled(v, h);
            let k = 0.75 + 0.25 * n#y;
            let c = Color.rgb(color#r * k, color#g * k, color#b * k);
            (Vec3.sub(Vec3.sub(c0, du), dv), n, c) :: (Vec3.add(Vec3.sub(c0, du), dv), n, c)
                :: (Vec3.add(Vec3.add(c0, du), dv), n, c) :: (Vec3.sub(Vec3.add(c0, du), dv), n, c) :: Nil
        })

    /// 箱の列を 1 つの形に（箱ごとに頂点 24・三角 12）。組めなければ空の形にして 1 行知らせる。
    pub def of(color: Color, boxes: List[Box]): Mesh3d.Mesh3d =
        let points = boxes |> List.flatMap(boxPoints(color));
        let flat3 = (p: Vec3.Vec3) -> p#x :: p#y :: p#z :: Nil;
        let quads = List.length(boxes) * 6;
        let indices = List.range(0, quads) |> List.flatMap(i -> { let b = i * 4; b :: b + 1 :: b + 2 :: b :: b + 2 :: b + 3 :: Nil });
        match Mesh3d.fromArrays({ positions = points |> List.flatMap(p -> { let (at, _, _) = p; flat3(at) }) |> List.toVector,
                                  normals = points |> List.flatMap(p -> { let (_, n, _) = p; flat3(n) }) |> List.toVector,
                                  colors = points |> List.flatMap(p -> { let (_, _, c) = p; c#r :: c#g :: c#b :: Nil }) |> List.toVector,
                                  indices = indices |> List.toVector, skin = None }) {
            case Ok(mesh) => mesh
            case Err(e)   => Log.warnThen("[box] 箱の形を組めない: ${e}", Mesh3d.fromPolygons(Nil))
        }

    /// 大きさ 1 の箱（伸ばして置く物の元）。
    pub def unit(color: Color): Mesh3d.Mesh3d = of(color, { center = Vec3.zero(), size = Vec3.one() } :: Nil)
}
