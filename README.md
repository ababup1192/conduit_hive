# Conduit Hive

SF の施設の迷路を一人称で進み、群れで迫るクリーチャーを撃って倒すシューティング（flix_game_engine 0.85.0）。
画面に出るのは腕と銃（ビューモデル）だけ。最後の広い部屋では 40〜50 体が同時に迫る。計画は `plans/conduit-hive-plan.md`。

## 遊ぶ

| 操作 | |
|---|---|
| 窓を押す | マウスを窓にキャプチャして見回す（Esc で放す。放している時の Esc で終了の確認） |
| WASD・Shift | 歩く・走る |
| 左ボタン | 撃つ（連射銃は押している間） |
| 1・2・3・ホイール | 持ち替え（散弾銃と連射銃は拾ってから。拾う所は段 4） |
| F3 | 1 コマの重さ（GPU・3D の数）を出す |

| コマンド | 何をするか |
|---|---|
| `make run` / `make debug` | 起動する（debug は保存即反映と F8） |
| `START="at x=66 z=134 yaw=90" make run` | 最後の部屋の入口から始める（始まりの登録簿 `src/Starts.flix`） |
| `SHOT=horde make run` | ギャラリーの場面を実機で開く（止まった 1 枚） |
| `make check` / `make test` / `make lint` | 型検査 / テスト / lint |
| `make render SHOT=horde` | 場面を `debug/horde.png` へ描き出す（場面の名前は `src/Shots.flix`） |
| `make render-all` / `make reference-update` / `make reference-check` | ギャラリーを全部描き出す / 基準を更新 / 基準と比べる |
| `make bench-horde BENCH_SETS=horde50` | 50 体の群れの 1 コマの重さを測る（`plans/bench-horde.md`） |
| `make flow FLOW=e2e/walk.flow` | 手順書を画面なしで実機と同じ道に流す |

## 読む順

1. **遊ぶ** — `make run`（最初の部屋 A から始まる。部屋に入るとその部屋の spawn の印から群れが湧く）。
2. **`src/Game.flix`** — App の組み立て。毎フレーム 入力（`Controls.step`）→ 規則（`World.step`）→ 描く（`View`）。音は `Sounds`。
3. **`src/World.flix`** — 遊びの状態と 1 コマの規則。画面は `Screen`（今は `Play`）で、遊んでいる場面の値は `Session`。
   1 コマは 歩く（`Walker`）→ 部屋に入る → 撃つ（`Arsenal`・`Hitscan`）→ 群れ（`Horde`）→ 体力（`Health`）。起きた事は `Events`。
4. **敵** — `src/Horde.flix`（群れの 1 コマ・追う・振る・吐く・撃たれる）→ `FlowField`（共有する距離の地図）・
   `Separation`（押し合いと壁）・`Projectiles`（ranged の弾）・`Spawner`（印から湧く予定）・`Creatures`（glb・当たり判定の形・姿勢の共有）。
5. **武器** — `src/Arsenal.flix`（連射・弾・持ち替え）・`src/Hitscan.flix`（レイの当たり）・`src/FpViewmodel.flix`（腕と銃の glb）。
6. **描く** — `src/View.flix`（入口で画面を選び、HUD も描く）→ `src/StageView.flix`（3D の場面とビューモデル）→ `src/PostView.flix`（ブルームと後処理）。
   迷路の絵は `Maze`・`MazeMesh`・`Collider`、粒は `Particles3d`。
7. **Doc** — 値は `assets/` の JSON（保存即反映）。読み込みと読み直しは `src/Controls.flix`、描く元の束は `src/Res.flix`。

## Doc（`assets/`）

| Doc | 中身 | 読む mod |
|---|---|---|
| `maze.stage.json` | 迷路のマス目・区画・印（start・spawn・pickup） | `MazeDoc` |
| `conduit_hive.enemies.json` | 敵の型ごとの体力・速さ・攻撃の距離と時刻・projectile | `EnemiesDoc` |
| `conduit_hive.spawns.json` | spawn の印の名前ごとの群れ（数・間隔・型） | `SpawnsDoc` |
| `conduit_hive.player.json` | プレイヤーの体力・被弾の赤み・やり直すまで | `PlayerDoc` |
| `conduit_hive.weapons.json` | 武器ごとの威力・連射・ばらつき・弾・反動 | `WeaponsDoc` |
| `conduit_hive.viewmodel.json` | 腕と銃の見え方（画角・揺れ・持ち替え） | `FpViewmodelDoc` |
| `conduit_hive.particles3d.json` | 3D の粒（マズルフラッシュ・火花・体液・projectile の玉） | `Particles3dDoc` |
| `conduit_hive.walk.json`・`conduit_hive.look.json` | 歩く手触り・施設の色と光と霧 | `WalkDoc`・`LookDoc` |
| `conduit_hive.uitext.json`・`conduit_hive.theme.json`・`player.keys.json` | 画面の文言・色・キー割り当て | `UiTextDoc`・`ThemeDoc`・`KeysDoc` |

それぞれ schema が並び、`project.json` の `editor.resources` が Studio に宣言している。
モデル（`assets/models/*.glb`）は `modeling/` の Blender のスクリプトが作る。

## 絵

画風は `AGENTS.local.md` の「このゲームの画風」。生成した `gallery/` と `reference/*.png` は git に入れず、
退行は `reference/SHA256SUMS.txt` で見る（`make reference-check`）。
