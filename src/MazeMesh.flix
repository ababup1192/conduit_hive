// MazeMesh — 迷路のマス目から組む灰色の箱の絵（純粋）。Blender でベイクする前の確認用の道で、区画ごとに置く物と灯りを返す。
//
// 区画ごとの置いた物（区画ごとに描くか決めるので、区画をまたいで形をまとめない）:
//   面  … 床・天井・壁（足元と天井際は面取りの斜めの面・腰の高さに目地の暗い帯）。頂点の色で陰を付ける:
//          壁ぎわの床と天井の角を暗く・壁は下ほど暗く上へ明るく・マスごとに少し明るさを振ってパネルに見せる
//   筋  … 施設の光る筋（自分で光る材質）。通路は天井際を通し、部屋は足元にところどころ
//   灯具 … 天井の光る板（部屋は升目ごとの大きな板・通路は間をあけた小さな板）。灯りの点光源はその少し下に置く
// 高さの違う区画の境目には、高い側に段の壁（まぐさ）を立てる。
mod MazeMesh {
    use fge::{Color, Hash01, Log, Mat4, Mesh3d, Scene3d, ShaderDoc, Vec3}
    use fge::ShaderDoc.{Field, Shade, Out}

    /// 区画 1 つの絵: 置いた物・場面に入れる灯り・天井の灯具の灯り（lightmap の付かない手前の腕と銃へ写す）。
    /// 灰色の箱の道は lights と lamps が同じ。ベイクしたステージ（StageModel）は lights が空で、lamps だけを持つ。
    pub type alias ZoneArt = { instances = List[Scene3d.Instance3d], lights = List[Scene3d.PointLight], lamps = List[Scene3d.PointLight] }

    /// 四角 1 枚: 頂点 4 つ（表から見て時計回り）と頂点ごとの色。
    type alias Quad = { points = List[Vec3.Vec3], colors = List[Color] }

    /// マスの辺の 1 本: 内から壁を見た時の左の端 p と右の端 q（x・z）と、壁から内へ向く向き。
    type alias Edge = { p = (Float64, Float64), q = (Float64, Float64), inward = (Float64, Float64), side = Int32 }

    /// 面取りの幅（m）。
    def bevel(): Float64 = 0.3

    /// 腰の目地の下と上の高さ（m）。
    def seamLow(): Float64 = 1.1
    def seamHigh(): Float64 = 1.18

    /// 迷路の全部の区画の絵。
    pub def build(look: LookDoc.Rec, m: Maze.Maze): Map[Char, ZoneArt] =
        m#zones |> Map.map(zone -> zoneArt(look, m, zone))

    def zoneArt(look: LookDoc.Rec, m: Maze.Maze, zone: Maze.Zone): ZoneArt =
        let shell = zone#cells |> List.flatMap(cell -> cellQuads(look, m, zone, cell));
        let strips = zone#cells |> List.flatMap(cell -> stripQuads(look, m, zone, cell));
        let lamps = lampsOf(look, m, zone);
        let place = (name: String, mesh: Mesh3d.Mesh3d) -> Scene3d.meshInstance(mesh, Mat4.identity()) |> Scene3d.withName("${name}:${zone#id}");
        let glowing = (name: String, quads: List[Quad], c: Color) ->
            if (List.isEmpty(quads)) Nil
            else (place(name, meshOf(quads)) |> Scene3d.withMaterial(glowMaterial("conduit_${name}", c, look#stripIntensity))) :: Nil;
        let lit = lamps |> List.map(l -> l#light);
        { instances = place("shell", meshOf(shell)) :: List.append(glowing("strip", strips, look#stripColor), glowing("lamp", lamps |> List.map(l -> l#panel), lampColorOf(look, zone))),
          lights = lit, lamps = lit }

    /// 区画の天井の灯具の灯り（灰色の箱の灯具と、stage.py が灯具を吊るマスは同じ決め方）。
    pub def lampLightsOf(look: LookDoc.Rec, m: Maze.Maze, zone: Maze.Zone): List[Scene3d.PointLight] =
        lampsOf(look, m, zone) |> List.map(l -> l#light)

    // ── 1 マスの面 ──

    def v(x: Float64, y: Float64, z: Float64): Vec3.Vec3 = Vec3.v3(x, y, z)

    def shade(c: Color, k: Float64): Color = Color.rgb(c#r * k, c#g * k, c#b * k)

    /// マスごとの明るさの振れ（1 ± spread）。
    def jitter(cell: Maze.Cell, channel: Int32, spread: Float64): Float64 =
        1.0 + spread * (2.0 * Hash01.at(cell#row * 131 + cell#col, channel) - 1.0)

    /// マスの 4 本の辺（北・東・南・西の順）と、その向こうのマス。
    def edgesOf(m: Maze.Maze, cell: Maze.Cell): List[(Edge, Maze.Cell)] =
        let (x0, z0) = Maze.cornerOf(m, cell);
        let (x1, z1) = (x0 + m#cellSize, z0 + m#cellSize);
        ({ p = (x0, z1), q = (x1, z1), inward = (0.0, -1.0), side = 0 }, { row = cell#row - 1 | cell })
            :: ({ p = (x1, z1), q = (x1, z0), inward = (-1.0, 0.0), side = 1 }, { col = cell#col + 1 | cell })
            :: ({ p = (x1, z0), q = (x0, z0), inward = (0.0, 1.0), side = 2 }, { row = cell#row + 1 | cell })
            :: ({ p = (x0, z0), q = (x0, z1), inward = (1.0, 0.0), side = 3 }, { col = cell#col - 1 | cell })
            :: Nil

    /// 辺に立てる縦の帯（y が lo から hi）。下の辺は内へ insetLo・上の辺は内へ insetHi だけずらす（面取りの斜めの面）。
    def band(e: Edge, lo: Float64, hi: Float64, insetLo: Float64, insetHi: Float64, cLo: Color, cHi: Color): Quad =
        let (px, pz) = e#p;
        let (qx, qz) = e#q;
        let (nx, nz) = e#inward;
        { points = v(px + nx * insetLo, lo, pz + nz * insetLo) :: v(px + nx * insetHi, hi, pz + nz * insetHi)
                       :: v(qx + nx * insetHi, hi, qz + nz * insetHi) :: v(qx + nx * insetLo, lo, qz + nz * insetLo) :: Nil,
          colors = cLo :: cHi :: cHi :: cLo :: Nil }

    /// 壁の 1 面: 足元の面取り・腰板・目地・上の板・天井際の面取り。
    def wallQuads(look: LookDoc.Rec, cell: Maze.Cell, h: Float64, e: Edge): List[Quad] =
        let k = bevel();
        let w = shade(look#wallColor, jitter(cell, 10 + e#side, 0.06));
        band(e, 0.0, k, k, 0.0, shade(w, 0.35), shade(w, 0.55))
            :: band(e, k, seamLow(), 0.0, 0.0, shade(w, 0.6), shade(w, 0.78))
            :: band(e, seamLow(), seamHigh(), 0.0, 0.0, shade(w, 0.4), shade(w, 0.4))
            :: band(e, seamHigh(), h - k, 0.0, 0.0, shade(w, 0.95), shade(w, 0.72))
            :: band(e, h - k, h, 0.0, k, shade(w, 0.6), shade(w, 0.4))
            :: Nil

    /// 床か天井の 1 枚。壁に接する角の頂点を暗くする。up = 床（上を向く）・下を向くなら天井。
    def capQuad(m: Maze.Maze, cell: Maze.Cell, y: Float64, up: Bool, base: Color): Quad =
        let (x0, z0) = Maze.cornerOf(m, cell);
        let (x1, z1) = (x0 + m#cellSize, z0 + m#cellSize);
        let wall = (dc: Int32, dr: Int32) -> not Maze.isFloor(m, { col = cell#col + dc, row = cell#row + dr });
        let corner = (dc: Int32, dr: Int32) -> if (wall(dc, 0) or wall(0, dr) or wall(dc, dr)) shade(base, 0.55) else base;
        // 角の向き: 西南 (−1, +1)・西北 (−1, −1)・東北 (+1, −1)・東南 (+1, +1)（行は下へ増える）。
        let sw = (v(x0, y, z0), corner(-1, 1));
        let nw = (v(x0, y, z1), corner(-1, -1));
        let ne = (v(x1, y, z1), corner(1, -1));
        let se = (v(x1, y, z0), corner(1, 1));
        let ring = if (up) sw :: nw :: ne :: se :: Nil else sw :: se :: ne :: nw :: Nil;
        { points = ring |> List.map(fst), colors = ring |> List.map(snd) }

    /// 1 マスの面（床・天井・壁・段の壁）。
    def cellQuads(look: LookDoc.Rec, m: Maze.Maze, zone: Maze.Zone, cell: Maze.Cell): List[Quad] =
        let h = zone#height;
        let floor = capQuad(m, cell, 0.0, true, shade(look#floorColor, jitter(cell, 1, 0.08)));
        let ceiling = capQuad(m, cell, h, false, shade(look#ceilingColor, jitter(cell, 2, 0.08)));
        let sides = edgesOf(m, cell) |> List.flatMap(e -> {
            let (edge, other) = e;
            let otherHeight = Maze.heightAt(m, other);
            if (not Maze.isFloor(m, other)) wallQuads(look, cell, h, edge)
            else if (otherHeight < h) band(edge, otherHeight, h, 0.0, 0.0, shade(look#wallColor, 0.5), shade(look#wallColor, 0.7)) :: Nil
            else Nil
        });
        floor :: ceiling :: sides

    // ── 光る筋と灯具 ──

    /// 筋の幅（m）と、壁から浮かせる距離（m。壁の面とちらつかない）。
    def stripWidth(): Float64 = 0.08
    def stripLift(): Float64 = 0.02

    /// 1 マスの光る筋: 通路は壁ごとに天井際・部屋は足元に、マスの半分ほどに。
    def stripQuads(look: LookDoc.Rec, m: Maze.Maze, zone: Maze.Zone, cell: Maze.Cell): List[Quad] =
        let isRoom = zone#kind == MazeDoc.ZoneKind.Room;
        let y = if (isRoom) bevel() + 0.12 else zone#height - bevel() - 0.25;
        edgesOf(m, cell) |> List.filter(e -> not Maze.isFloor(m, snd(e)))
            |> List.filter(e -> not isRoom or Hash01.at(cell#row * 131 + cell#col, 20 + fst(e)#side) < 0.5)
            |> List.map(e -> band(fst(e), y, y + stripWidth(), stripLift(), stripLift(), look#stripColor, look#stripColor))

    /// 灯具の板と、その下の灯り。
    type alias Lamp = { panel = Quad, light = Scene3d.PointLight }

    /// 灯具を吊るマス: 部屋は lampSpacing マスごとの升目に当たる床のマス（1 つも当たらない小さな部屋は最初のマス）・
    /// 通路はマスの並びの lampSpacing 個ごと。
    def lampCells(look: LookDoc.Rec, zone: Maze.Zone): List[Maze.Cell] =
        let n = Int32.max(1, look#lampSpacing);
        let picked =
            if (zone#kind == MazeDoc.ZoneKind.Room) zone#cells |> List.filter(c -> Int32.modulo(c#col, n) == n / 2 and Int32.modulo(c#row, n) == n / 2)
            else zone#cells |> List.zipWithIndex |> List.filter(e -> Int32.modulo(fst(e), n) == n / 2) |> List.map(snd);
        if (List.isEmpty(picked)) List.take(1, zone#cells) else picked

    /// 区画の灯具の光る色（部屋は白い灯り・通路は光る筋の色へ寄せる）。
    def lampColorOf(look: LookDoc.Rec, zone: Maze.Zone): Color =
        if (zone#kind == MazeDoc.ZoneKind.Room) look#roomLightColor else Color.mix(look#roomLightColor, look#stripColor, 0.5)

    /// 区画の天井の灯具と、その下の灯り。部屋は大きな板・通路は小さな板で弱い灯り。
    def lampsOf(look: LookDoc.Rec, m: Maze.Maze, zone: Maze.Zone): List[Lamp] =
        let isRoom = zone#kind == MazeDoc.ZoneKind.Room;
        let half = if (isRoom) 0.9 else 0.35;
        let drop = if (isRoom) 1.5 else 0.8;
        let intensity = if (isRoom) look#roomLightIntensity else look#corridorLightIntensity;
        let range = m#cellSize * Int32.toFloat64(Int32.max(1, look#lampSpacing)) * look#roomLightReach;
        let c = lampColorOf(look, zone);
        let y = zone#height - 0.01;
        lampCells(look, zone) |> List.map(cell -> {
            let (cx, cz) = Maze.centerOf(m, cell);
            { panel = { points = v(cx - half, y, cz - half) :: v(cx + half, y, cz - half) :: v(cx + half, y, cz + half) :: v(cx - half, y, cz + half) :: Nil,
                        colors = c :: c :: c :: c :: Nil },
              light = { position = v(cx, zone#height - drop, cz), color = c, intensity = intensity, range = range } }
        })

    /// 自分で光る材質（頂点の色に光る色を足す。強さは線形の倍率）。
    pub def glowMaterial(name: String, c: Color, intensity: Float64): Scene3d.Material3d =
        let vc = chan -> Field.VertexColor({ chan = chan });
        let spec = { name = name, cycleRate = 0.0, bindings = Nil,
                     out = Out.Fill({ shade = Shade.Rgb({ r = vc(ShaderDoc.TexChan.R), g = vc(ShaderDoc.TexChan.G), b = vc(ShaderDoc.TexChan.B) }), alpha = Field.Const(1.0) }) };
        Scene3d.material(spec) |> Scene3d.withEmission(Shade.Solid(c)) |> Scene3d.withEmissionIntensity(intensity)

    // ── 四角の列 → 形 ──

    def flat3(vs: List[Vec3.Vec3]): List[Float64] = vs |> List.flatMap(p -> p#x :: p#y :: p#z :: Nil)

    /// 四角の向き（1 本目と 2 本目の辺の外積。表から見て時計回りの並びなら表の向き）。
    def normalOf(q: Quad): Vec3.Vec3 = match q#points {
        case a :: b :: c :: _ => Vec3.normalized(Vec3.cross(Vec3.sub(b, a), Vec3.sub(c, a)))
        case _                => Vec3.v3(0.0, 1.0, 0.0)
    }

    /// 四角の列の形（四角ごとに頂点 4 つ・三角 2 枚）。組めなければ空の形にして 1 行知らせる。
    def meshOf(quads: List[Quad]): Mesh3d.Mesh3d =
        let positions = quads |> List.flatMap(q -> flat3(q#points)) |> List.toVector;
        let normals = quads |> List.flatMap(q -> { let n = normalOf(q); flat3(n :: n :: n :: n :: Nil) }) |> List.toVector;
        let colors = quads |> List.flatMap(q -> q#colors |> List.flatMap(c -> c#r :: c#g :: c#b :: Nil)) |> List.toVector;
        let indices = List.range(0, List.length(quads)) |> List.flatMap(i -> {
            let b = i * 4;
            b :: b + 1 :: b + 2 :: b :: b + 2 :: b + 3 :: Nil
        }) |> List.toVector;
        match Mesh3d.fromArrays({ positions = positions, normals = normals, colors = colors, indices = indices, skin = None }) {
            case Ok(mesh) => mesh
            case Err(e)   => Log.warnThen("[maze] 灰色の箱の形を組めない: ${e}", Mesh3d.fromPolygons(Nil))
        }
}
