// Hitscan — 弾の当たり判定（純粋）。弾は飛ばさず、撃った瞬間に照準からのレイを的の列に当て、一番近い物に当たる。
// 的は壁・床・天井（迷路の当たり判定と同じ箱）と、立てた物（的の柱）。壁も同じ列に入れるので、壁の向こうの物には当たらない。
// 敵は毎コマ、体のカプセルと頭の球を的の列の前へ足す（Horde.targetsOf。頭を体より前に置くので、同じ距離なら頭に当たる）。
mod Hitscan {
    use fge::{Camera3d, CollisionShape3d, Hash01, Num, Ray3d, Vec3}

    /// 敵の当たった所。Head は威力が EnemiesDoc の headMultiplier 倍。
    pub enum Part with Eq, ToString {
        case Body
        case Head
    }

    /// 弾が当たった物。Wall = 壁・床・天井・Prop = 立てた物（番号は Props.pillarsOf の並び）・Enemy = 敵（番号は Horde の敵の id）。
    pub enum Struck with Eq, ToString {
        case Wall
        case Prop(Int32)
        case Enemy(Int32, Part)
    }

    /// 当たった所。normal = 当たった面の向き（弾の来た側を向く・長さ 1）。
    pub type alias Impact = { struck = Struck, point = Vec3.Vec3, normal = Vec3.Vec3 }

    /// 的の列（並びの前ほど、同じ距離の時に選ばれる）。
    pub type alias Targets = List[(Struck, Ray3d.RayTarget)]

    def shapeOf(b: CollisionShape3d.Box3d): Ray3d.RayTarget = Ray3d.RayTarget.Shape(CollisionShape3d.BoxShape3d(b))

    /// 迷路の壁・床・天井と、立てた物の的の列（読み込みで 1 回作り、描く元に持つ）。
    pub def targetsOf(m: Maze.Maze, props: List[CollisionShape3d.Box3d]): Targets =
        let walls = Collider.floorBox(m) :: List.append(Collider.wallBoxes(m), Collider.ceilingBoxes(m));
        List.append(props |> List.zipWithIndex |> List.map(e -> { let (i, b) = e; (Struck.Prop(i), shapeOf(b)) }),
                    walls |> List.map(b -> (Struck.Wall, shapeOf(b))))

    def rad(d: Float64): Float64 = d * Num.pi() / 180.0

    /// 1 回に飛ぶ粒のレイ: 照準の向きから spread 度までの円錐の中へ、撃った番号 shot と粒の番号で決まった向きに散らす。
    /// spread が 0 なら全部の粒が照準の真ん中へ飛ぶ。
    def pelletRays(camera: Camera3d.Camera3d, spread: Float64, pellets: Int32, shot: Int32): List[Ray3d.Ray3d] =
        let forward = Camera3d.forward(camera);
        let right = Camera3d.right(camera);
        let up = Camera3d.up(camera);
        List.range(0, Int32.max(1, pellets)) |> List.map(i -> {
            let seed = shot * 64 + i;
            let cone = rad(Float64.max(0.0, spread));
            let r = Num.sqrt(Hash01.at(seed, 41)) * Num.sin(cone) / Num.cos(cone);
            let a = Hash01.at(seed, 42) * Num.tau();
            let dir = Vec3.add(forward, Vec3.add(Vec3.mul(right, r * Num.cos(a)), Vec3.mul(up, r * Num.sin(a))));
            Ray3d.ray3d(camera#eye, dir)
        })

    /// レイ 1 本が range までに最初に当たる所。
    def cast(targets: Targets, range: Float64, ray: Ray3d.Ray3d): Option[Impact] =
        Ray3d.pickNearest(ray, range, targets) |> Option.map(hit -> {
            let (struck, h) = hit;
            { struck = struck, point = h#point, normal = h#normal }
        })

    /// 1 回撃った時の当たった所の列（粒ごと・届かなかった粒は無い）。
    pub def fire(targets: Targets, camera: Camera3d.Camera3d, stats: WeaponsDoc.Stats, shot: Int32): List[Impact] =
        pelletRays(camera, stats#spread, stats#pellets, shot) |> List.filterMap(cast(targets, stats#range))
}
