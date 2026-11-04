// ZOrder — 画面全体の重なりの層（奥から手前）。Unity の Sorting Layer と同じ考え方。
// 新しい層は case を足し、zRange に範囲を書く（書き忘れは match の網羅で止まる）。
// 層の中の前後は ZStack に積んだ順で決まり、葉の中の z は 0..31。根で SortingLayer.compose に渡す（View.frame）。
// 使い方の全文は engine の engine_world/src/SortingLayer.flix 冒頭と docs/z-bands.md。
mod ZOrder {

    use fge::SortingLayer

    pub enum Layer with Eq, ToString {
        case Scene   // 一人称の場面（3D と後処理を Pass で組み、面 1 枚で画面へ）
        case Menu    // タイトル・ポーズ・クリアのメニュー（場面の上）
        case Prompt  // 終了の確認の窓（どれよりも手前）
    }

    instance SortingLayer[Layer] {
        pub def zRange(layer: Layer): (Int32, Int32) =
            match layer {
                case Layer.Scene  => (0, 199)
                case Layer.Menu   => (200, 299)
                case Layer.Prompt => (300, 309)
            }
    }

    /// 奥から手前へ全部の層（F8 の注釈の文脈・表のテストが使う）。
    pub def layers(): List[Layer] = Layer.Scene :: Layer.Menu :: Layer.Prompt :: Nil
}
