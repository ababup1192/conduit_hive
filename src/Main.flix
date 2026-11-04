// エントリーポイント。App の組み立ては Game.app（flow の入口 E2e とテストも同じ物を使う）。
// ここで足すのは main だけが知る物（Pass の計画・終了の確認・注釈・デバッグの印・開発の道具の /render）。

use fge::{App, LwjglLayer, Resources}

def main(): Unit \ IO =
    if (LwjglLayer.ensureMainThread()) ()
    else {
        run {
            App.loadAndLaunch(() -> {
                Game.app(Controls.loadDocs())
                    // 3D の場面・ブルーム・後処理を先に Pass へ描き、本編の面が読み返す。
                    |> App.withPassPlan(Resources.read((res, w) -> View.passPlan(res, w)))
                    // 窓の閉じるボタンも Esc と同じ確認へ回し、はいを選んだら終わる。
                    |> App.withCloseRequest(Resources.mapWorld((_, w) -> World.askQuit(w)))
                    |> App.withAnnotationContext(Resources.read((res, w) ->
                        { facts = ("状態", E2e.fingerprint(res, w)) :: Nil,
                          layers = ZOrder.layers(), hudLayers = (Nil: List[ZOrder.Layer]) }))
                    |> App.withDebug(App.debugFromEnv())
                    // WhyNot: Game.app で繋がない — Game.app はテスト・flow・ブラウザ版と共有するので、開発の道具（POST /render）を持たせない。
                    |> App.onRenderRequest(SceneRender.allShots)
            })
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }
