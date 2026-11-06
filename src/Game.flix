// Game — App の組み立て。実機の起動（Main）・flow の入口（E2e）・テスト・描き出しが同じ物を使う。
// Doc と迷路は App を組む前に読み、その値から描く元（Res）を作る（壊れていても defaults で必ず起動する）。
// App の w は描く元と遊びの状態（World）の組（Resources.With）で、系・絵・問いは Resources の口で両方を受ける。
//
// ── ゲームループの全体像（App.game の 1 レコード）──
//   init    = 出発点の組（描く元 Res とタイトルの画面の World）。
//   update  = 毎フレームの更新（入力 → 次の World。秒は遊びの時計 = Resources.addClock が先に進める）。
//   view    = (Res, World) → 「何をどこに描くか」。Pass の計画（3D の場面・ブルーム・後処理）は Main の withPassPlan。
mod Game {
    use fge::{App, Resources}

    pub def app(docs: Res.Docs): App.App[Resources.With[Res.Res, World.World], {}] =
        let res = Res.build(docs);
        App.game({
            init = Resources.of(res, World.title()),
            update = Resources.system(Controls.step),
            view = Resources.view(View.frame),
            reloads = Nil
        })
            // 照準・体力・武器の並び・弾の数・拾った知らせ・F3 の診断の行（view の絵のどれよりも手前）。
            |> App.withHudView(Resources.view(View.hudFrame))
            |> Resources.addClock({ clockOf = w -> w#play, withClock = (c, w) -> { play = c | w }, paceOf = (r, w) -> World.paceOf(r, w) })
            |> App.withDocTable(Controls.docTable())
            // このコマに起きた事の音（Sounds が World の events と前後の歩数・敵の攻撃を写す）・環境音と近い敵の唸り・バスと音ごとの量とダッキング。
            |> App.withAudio(ws -> Resources.read((r, w) -> Sounds.events(r, ws#before#world, w), ws#after))
            |> App.withSustained(Resources.read(Sounds.sustained))
            |> App.withMixer(Resources.read((r, _) -> r#mixer))
            // 3D の粒のビルボードの絵を GPU へ上げる（鍵が同じ間は上げ直さない）。
            |> App.withSpriteAtlases(Resources.read((r, _) -> { texture = Particles3d.textureName(), key = Particles3d.textureKey(), baked = r#particleTexture } :: Nil))
            // 窓を押すとマウスをキャプチャして視点を回す（Esc で放す。放している時の Esc は終了の確認で、既定の Esc の終了は使わない）。
            |> App.withMouseCapture(Resources.read((_, w) -> World.isLooking(w)))
            |> App.quitWhen((_, h) -> Resources.read((_, w) -> World.isQuitting(w), h))
            // F3 で出す 1 コマの重さ（GPU の時間・3D の置いた物と描いた物の数を含む）。
            |> App.withDiagnostics
            // 好きな場面から起動する・テストと flow が場面を名前で組む（START=play・START="at x=18 z=26 yaw=0" など）。
            |> App.withStarts(Starts.all() |> List.map(Resources.liftStart))
            // ギャラリーの場面を実機でも開く（START=shot:corridor。描き出しと同じ World から始まる）。
            |> App.withShots(Resources.shotsOf(Shots.names(), Shots.worldOf))
            |> App.withFlow(E2e.table())
            |> App.withFingerprint(Resources.read(E2e.fingerprint))
            |> App.withStatusLine(Resources.read(E2e.fingerprint))
            |> Preload3d.withPreload(Resources.read((r, _) -> r))
            // WhyNot: 規則と描くのを直列に戻さない — 群れの場面で 60 fps を割る。照準が画面に出るのが 1 コマ遅れるのは許した。
            |> App.withPipelinedRendering
}
