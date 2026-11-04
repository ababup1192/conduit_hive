# Conduit Hive

SF の施設の迷路を一人称で進み、群れで迫るクリーチャーを撃って倒すシューティング（flix_game_engine 0.85.0）。
画面に出るのは腕と銃（ビューモデル）だけ。部屋ごとの wave で全体で約 400 体が湧き（同時に生きているのは 50 体まで）、最後の広い部屋では約 170 体が 5 つの wave で迫る。計画は `plans/conduit-hive-plan.md`。

## 遊ぶ

| 操作 | |
|---|---|
| タイトルで Enter・窓を押す | 遊び始める（マウスを窓にキャプチャして見回す。タイトルの Esc で終了の確認） |
| Esc | ポーズ（W・S で選び Enter で決める・Esc で続ける。「タイトルへ」でタイトルに戻る） |
| WASD・Shift | 歩く・走る（走る間はスタミナが減り、走り切ると息切れして戻るまで走れない） |
| Space | 緊急回避（押している向きへ・押していなければ後ろへ跳ぶ。跳び始めの一瞬は攻撃が当たらない。スタミナを多めに使う） |
| F・V | 蹴り（前の扇の敵を押し返してよろけさせる。囲まれた時に隙間を作る） |
| G | 手榴弾を投げる（壁と床で跳ね、数秒で爆発。近いと自分も傷を受ける。持てる数に上限・拾って補充） |
| 左ボタン | 撃つ（連射銃は押している間） |
| 1・2・3・ホイール | 持ち替え（散弾銃と連射銃は拾ってから。弾が尽きた武器で撃つと空撃ちして弾のある武器へ替わる） |
| F3 | 1 コマの重さ（GPU・3D の数）を出す |

| コマンド | 何をするか |
|---|---|
| `make run` / `make debug` | 起動する（debug は保存即反映と F8） |
| `START=play make run`・`START="at x=66 z=134 yaw=90" make run` | タイトルを飛ばして始める・最後の部屋の入口から始める（始まりの登録簿 `src/Starts.flix`） |
| `SHOT=horde make run` | ギャラリーの場面を実機で開く（止まった 1 枚） |
| `make check` / `make test` / `make lint` | 型検査 / テスト / lint |
| `make render SHOT=horde` | 場面を `debug/horde.png` へ描き出す（場面の名前は `src/Shots.flix`） |
| `make render-all` / `make reference-update` / `make reference-check` | ギャラリーを全部描き出す / 基準を更新 / 基準と比べる |
| `make bench-horde BENCH_SETS=horde50` | 50 体の群れの 1 コマの重さを測る（`plans/bench-horde.md`） |
| `make bench-horde BENCH_SETS=horde-waves` | 最後の部屋で wave を湧かせ続け、自動の操縦が 3 分間倒し続ける間の 1 コマの重さ（GC は `JAVA_TOOL_OPTIONS="-Xlog:gc:file=…"`） |
| `make flow FLOW=e2e/walk.flow`・`e2e/title.flow` | 手順書を画面なしで実機と同じ道に流す（title.flow はタイトル → 遊ぶ → ポーズ → タイトル） |
| `make video` | 遊んでいる様子の紹介の動画（約 2 分・1920×1080・60 fps・音つき）を `debug/video/play.mp4` に撮る（手順 `e2e/video.flow`・道筋 `assets/conduit_hive.tour.json` を `START=tour` の自動の操縦が歩いて撃ち、囲まれたら蹴るか跳び、群れの塊に手榴弾を投げる。git には入れない） |

## 読む順

1. **遊ぶ** — `make run`（タイトルから。Enter で最初の部屋 A に立つ。部屋に入るとその部屋の wave が順に湧き（通路に入ると後ろや横の部屋から流れ込む wave もある）、倒れた敵は時々弾や回復を落とす。床の拾う物に近づくと拾う。最後の部屋 H の wave を全部倒すとクリア）。
2. **`src/Game.flix`** — App の組み立て。毎フレーム 入力（`Controls.step`）→ 規則（`World.step`）→ 描く（`View`）。音は `Sounds`（起きた事・足音・敵の叫びを一発の音へ、環境音と近い敵の唸りを鳴り続ける音へ写す。バスとダッキングは mixer）。
3. **`src/World.flix`** — 遊びの状態と 1 コマの規則。画面は `Screen`（`Title`・`Play`・`Clear`）で、遊んでいる場面の値は `Session`（ポーズもその中）。
   1 コマは 歩く（`Walker`）→ 部屋に入る → 拾う（`Pickups`）→ 撃つか空撃ち（`Arsenal`・`Hitscan`）→ 群れ（`Horde`）→ 体力（`Health`）→ 倒した数とクリア。起きた事は `Events`。
4. **敵** — `src/Horde.flix`（群れの 1 コマ・追う・飛びかかる・溜める・振る・吐く・撃たれる・蹴られる・爆発に巻き込まれる・吹っ飛ぶ・弾ける）→ `FlowField`（共有する距離の地図）・
   `Separation`（押し合いと壁）・`Knockback`（撃たれて押される・倒れて吹っ飛ぶ）・`Gibs`（弾けた肉片 `assets/models/gibs.glb`）・`Projectiles`（ranged の弾）・`Spawner`（区画ごとの wave・次の wave を始めるか・見えていない遠い印を選ぶ）・`Creatures`（glb・当たり判定の形・姿勢の共有）。
5. **囲まれた時の技** — `src/Moves.flix`（緊急回避と蹴りの状態と規則）・`src/Stamina.flix`（減る・戻る・息切れ）・`src/Grenades.flix`（投げる・放物線と跳ね・信管・爆発の傷・光）・`src/Boot.flix`（蹴りの間に画面の下から出る脚）。
6. **武器と拾う物** — `src/Arsenal.flix`（連射・弾・持ち替え・拾った武器と弾・空撃ち）・`src/Pickups.flix`（印から置く・拾う規則・浮き方）・`src/PickupModels.flix`（拾う物の形）・`src/Hitscan.flix`（レイの当たり）・`src/Tracers.flix`（連射銃の曳光弾）・`src/CameraShake.flix`（描くカメラの揺れと撃った時の目の跳ね）・`src/FpViewmodel.flix`（腕と銃の glb）。
7. **描く** — `src/View.flix`（入口で画面を選ぶ）→ `src/HudView.flix`（HUD）・`src/MenuView.flix`（タイトル・ポーズ・クリアのメニュー）→ `src/StageView.flix`（3D の場面とビューモデル）→ `src/PostView.flix`（ブルームと後処理）。
   迷路の絵は Blender でベイクしたステージ（`StageModel`。`assets/models/stage.glb` と区画ごとの lightmap）、確かめ用の灰色の箱は `MazeMesh`（look の `bakedStage` を false か、glb が迷路と合わない時）。形と当たり判定は `Maze`・`Collider`、粒は `Particles3d`。
8. **Doc** — 値は `assets/` の JSON（保存即反映）。読み込みと読み直しは `src/Controls.flix`、描く元の束は `src/Res.flix`。

## Doc（`assets/`）

| Doc | 中身 | 読む mod |
|---|---|---|
| `maze.stage.json` | 迷路のマス目・区画・印（start・spawn・pickup。spawn の印は湧く所だけで、何が湧くかは spawns） | `MazeDoc` |
| `conduit_hive.enemies.json` | 敵の型ごとの体力・速さ・攻撃の距離と時刻・melee の飛びかかり・ranged の溜め・撃たれた時ののけぞり・projectile | `EnemiesDoc` |
| `conduit_hive.spawns.json` | 区画ごとの wave（数・型・湧く印の区画・次の wave までの秒と残りの数）・同時に生きている数の上限・湧く間隔・近すぎる印から湧かせない距離 | `SpawnsDoc` |
| `conduit_hive.pickups.json` | pickup の印の名前ごとの量・拾う距離・浮き方・光・倒れた敵が落とす確率と物 | `PickupsDoc` |
| `conduit_hive.player.json` | プレイヤーの体力・被弾の赤み・やり直すまで・クリアから結果の画面まで | `PlayerDoc` |
| `conduit_hive.moves.json` | スタミナ（最大・戻る速さ・戻り始めるまで・息切れから戻る量・走る間に減る速さ）・緊急回避（使う量・長さ・距離・i-frame・間・目の沈み・画角）・蹴り（使う量・届く距離・扇の角・傷・押し返す速さ・間） | `MovesDoc` |
| `conduit_hive.grenade.json` | 手榴弾の持てる数・投げ方・飛び方（重さ・跳ね・信管）・爆発（半径・傷・弾ける半径・吹っ飛ぶ速さ・自分の傷）・爆発の光と揺れ | `GrenadeDoc` |
| `conduit_hive.weapons.json` | 武器ごとの威力・連射・ばらつき・弾と上限・反動 | `WeaponsDoc` |
| `conduit_hive.viewmodel.json` | 腕と銃の見え方（画角・揺れ・持ち替え） | `FpViewmodelDoc` |
| `conduit_hive.particles3d.json`・`conduit_hive.creaturefx.json`・`conduit_hive.blastfx.json` | 3D の粒（武器ごとのマズルフラッシュ・火花と煙・撃った瞬間の灯り・曳光弾）と、敵の側の粒（体液・弾けた時の体液と衝撃の輪・projectile の玉・溜めの光）と、手榴弾の爆発の粒（火の玉・輪・煙・破片）。3 つを 1 つの値に読む | `Particles3dDoc` |
| `conduit_hive.juice.json` | 撃った・倒した時の手応え（camera shake・撃った時の目の跳ね・hit marker と kill marker・吹っ飛ぶ強さ・弾ける条件と肉片・hit stop） | `JuiceDoc` |
| `conduit_hive.walk.json`・`conduit_hive.look.json` | 歩く手触り・ステージの絵の切り替えと lightmap の倍率・施設の色と光と霧 | `WalkDoc`・`LookDoc` |
| `conduit_hive.uitext.json`・`conduit_hive.theme.json`・`player.keys.json` | 画面の文言・色・キー割り当て | `UiTextDoc`・`ThemeDoc`・`KeysDoc` |
| `conduit_hive.sounds.json` | 音の鳴らし方（変化の数・音ごとの量・薬莢と先台の遅れ・跳弾の割合・敵の唸りと叫び・部屋ごとの環境音の混ぜ方） | `SoundsDoc` |
| `conduit_hive.mixer.json` | 音の通り道（銃・敵・自分・環境・UI のバス・銃声で環境音を下げるダッキング・cooldown。形は engine の AudioMixerDoc） | `Controls.mixerPath` |

それぞれ schema が並び、`project.json` の `editor.resources` が Studio に宣言している。
モデル（`assets/models/*.glb`）は `modeling/` の Blender のスクリプトが作る。ステージは `modeling/stage.py`（約 130 秒）・確かめは `modeling/stage_check.py`。
glb の `DOCHASH_<16 桁>` は迷路の rows と zones だけから取るハッシュ（`modeling/stagehash.py` と `StageModel.docHashOf` が同じ計算）で、合わなければゲームは 1 行知らせて灰色の箱で描く。

## 絵

画風は `AGENTS.local.md` の「このゲームの画風」。生成した `gallery/` と `reference/*.png` は git に入れず、
退行は `reference/SHA256SUMS.txt` で見る（`make reference-check`）。

## 音

効果音は Freesound の CC0 の素材から `tools/sfx_build.py` が `assets/sfx/*.wav` を作る（出どころは `assets/sfx/CREDITS.md`。作り直しも必ずこの道具を通す）。
メニュー・持ち替え・クリアの音だけは合成（`art/sfx.snd.star`）。名前の末尾の `_<番号>` は変化で、数は `conduit_hive.sounds.json` の variants。
音の名前と wav と project.json のずれは `bin/fge audio` で見る。
