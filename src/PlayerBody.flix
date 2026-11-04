// PlayerBody — 敵と projectile が見るプレイヤーの体（純粋な値）。World が歩く体と歩く Doc から毎コマ作る。
mod PlayerBody {
    use fge::Vec3

    /// 足元（x・feet・z）・目・向き（ラジアン。0 が +Z・正で +X の側）・体の半径と高さ（m）。
    pub type alias PlayerBody = { x = Float64, feet = Float64, z = Float64, eye = Vec3.Vec3, yaw = Float64, radius = Float64, height = Float64 }
}
