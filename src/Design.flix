// Design — 描く面の大きさ（design px）。規則・描く物・Doc から組む物のどれからも読む一番下の値。
// WhyNot: World に置いたままにしない — 描く元の束の中で大きさを読む物（後処理の面）があると、World と描く元の束が互いに使い合う。
mod Design {

    pub def width(): Float64 = 480.0

    pub def height(): Float64 = 270.0
}
