// Projectiles — ranged が吐いた projectile を進める規則（純粋）。壁の箱に当たれば弾け、プレイヤーの体に触れればダメージ、寿命で消える。
// 吐く時刻と上限は Horde、値は EnemiesDoc の projectile、見え方は Particles3dDoc の spit。
mod Projectiles {
    use fge::{CollisionWorld3d, Ray3d, Vec3}

    /// 飛んでいる projectile。at = 今の点・velocity = m/秒・born = 吐いた時刻。
    pub type alias Projectile = { id = Int32, at = Vec3.Vec3, velocity = Vec3.Vec3, born = Float64 }

    /// 弾けた所と面の向き。seed = 弾けた projectile の id（粒の散らし方の種）。
    pub type alias Splash = { point = Vec3.Vec3, normal = Vec3.Vec3, seed = Int32 }

    /// 1 コマの結果: 飛び続ける物・プレイヤーへのダメージの合計・弾けた所（壁で弾けた数は bursts）。
    pub type alias Flight = { projectiles = List[Projectile], damage = Float64, splashes = List[Splash], bursts = Int32 }

    /// dt 秒進める（時刻 t）。
    pub def fly(pr: EnemiesDoc.Projectile, world: CollisionWorld3d.CollisionWorld3d, t: Float64, dt: Float64, p: PlayerBody.PlayerBody, ps: List[Projectile]): Flight =
        ps |> List.foldLeft((acc, x) -> {
            let next = Vec3.add(x#at, Vec3.mul(x#velocity, dt));
            match wallHit(world, x#at, next) {
                case Some(hit) => { splashes = { point = hit#point, normal = hit#normal, seed = x#id } :: acc#splashes, bursts = acc#bursts + 1 | acc }
                case None if touchesPlayer(pr, p, next) =>
                    { damage = acc#damage + pr#damage, splashes = { point = next, normal = Vec3.normalized(Vec3.mul(x#velocity, -1.0)), seed = x#id } :: acc#splashes | acc }
                case None if t - x#born >= pr#life => acc
                case None => { projectiles = { at = next | x } :: acc#projectiles | acc }
            }
        }, { projectiles = Nil, damage = 0.0, splashes = Nil, bursts = 0 })
            |> (f -> { projectiles = List.reverse(f#projectiles) | f })

    /// origin から target へ進む間に当たる壁の箱（一番近い所）。
    def wallHit(world: CollisionWorld3d.CollisionWorld3d, origin: Vec3.Vec3, target: Vec3.Vec3): Option[Ray3d.RayHit] =
        let toward = Vec3.sub(target, origin);
        let length = Vec3.length(toward);
        let ray = Ray3d.ray3d(origin, toward);
        CollisionWorld3d.boxesNear(world, origin, length + 0.5)
            |> List.filterMap(b -> Ray3d.hitBox(ray, length, b))
            |> List.foldLeft((best, h) -> match best {
                case Some(b) if b#distance <= h#distance => best
                case _ => Some(h)
            }, None)

    /// 点 at の projectile がプレイヤーの体（足元から高さまでの縦の筒）に触れているか。
    def touchesPlayer(pr: EnemiesDoc.Projectile, p: PlayerBody.PlayerBody, at: Vec3.Vec3): Bool =
        let dx = at#x - p#x;
        let dz = at#z - p#z;
        dx * dx + dz * dz <= (p#radius + pr#radius) * (p#radius + pr#radius) and at#y >= p#feet - pr#radius and at#y <= p#feet + p#height + pr#radius
}
