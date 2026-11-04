# Conduit Hive の計画（rev1・2026-11-04）

rev1 → rev2: 再レビュー 88 点。パーティクルの Doc の種類名を particles3d に（engine の fx は 2D の FxDoc）・押し合いの決め方・ピックアップと spawn の値の正・Doc の登録とハッシュの置き場・音の候補を人に見せてから落とす。
rev0 → rev1: レビュー 72 点・17 件を全部入れた。測る段を前へ（段 0.5）・部屋ごとの間引き・区画ごとの glb と lightmap・姿勢の計算を安くする手・Doc の割り方・ビューモデルの論点・音の距離・パーティクルの emitter・言葉づかい。

## 人の注文（2026-11-04）

- 一人称シューティング。画面にはビューモデル（腕と銃）だけを出し、クリーチャーを撃って倒す。大量の敵を撃ちまくる爽快さが主役。
- そこそこ広い、迷路のようなステージ。回復・弾倉・武器のピックアップがある。最初の拳銃は弾が無限。
- クリーチャーと銃は Blender で作る（`/Users/abab/Desktop/horror_apartment/skills_ref/scenario-blender-*` を参考に）。腕を振り下ろす melee 型と、遠距離の ranged 型がいる。
- 同時に 40〜50 体を出したい。
- ステージは SF の世界観。無機質でかっこいいパイプを這わせる。シンプルで重くしない。
- 音は Freesound の CC0（night_apartment と同じ集め方・加工）。
- エフェクトは 3D のパーティクル（Blender でもエンジンでもよい）。
- 画風の細かい軸はすべておまかせ。出来上がったら動画を撮って送る。
- 新しいリポジトリ（GitHub に公開）。

## 画風（おまかせの範囲で決めた物・段 0 で AGENTS.local.md の「このゲームの画風」へ写す）

- 画素を見せない 3D。面の数は少なめで、角の面取りとベイクした陰（AO・lightmap）で形を読ませる。
- 地はくすんだ鋼と黒鉛の色。差し色は 2 つだけ: 施設の光る筋（冷たいシアン）と、クリーチャーの発光（暖かい橙〜赤）。敵は暗い通路でも発光で背景から分かれる。
- パイプは壁と天井を這う束。太さ 3 段・継ぎ目のフランジ・ところどころに弁と警告の縞。
- 後処理は控えめなブルームと霧。`camera.far` を `fog.far` にそろえ、霧の先は描かない（霧だけでは描く量は減らない）。
- しない事: 既存の作品に似せた形・色・UI。画面を白く飛ばす加算の光。矩形を並べただけの壁。

## 遊びの形

- 移動: WASD・マウスで見回す・Shift で走る。跳ばない（エンジンに口が無く、迷路にも要らない）。
- 武器（数字キーとホイールで替える）: 拳銃（弾は無限・単発）・散弾銃（拾うと使える・近くの群れをまとめて倒す）・連射銃（拾うと使える・押している間撃ち続ける）。
- ピックアップ: 回復（小・大）・弾倉（武器ごと）・武器。
- 敵: melee（走って寄り、腕を振り下ろす・数が多い主力）・ranged（距離を取って光る projectile を吐く・見て避けられる速さ）・余裕があれば大きい melee（遅いが硬い）。
- 流れ: 部屋に入ると、決まった spawn 点から群れが出る。最後の広い部屋で 40〜50 体が同時に見える。最後の部屋を空にすれば終わり。
- 終わり方は最小限（タイトル・死んだら最後に入った部屋の入口からやり直し・クリアの 1 枚・Esc でポーズ）。注文の外なので凝らない。

## Doc（値は外へ・ふるまいはコードに）

| Doc | 中身 |
|---|---|
| `maze.stage.json`（`stage.schema.json`） | 迷路のマス目・部屋の区切り・spawn 点・ピックアップの置き場（マスに印） |
| `conduit_hive.weapons.json` | 武器ごとの威力・連射の間隔・ばらつき・弾数・散弾の粒の数・反動 |
| `conduit_hive.enemies.json` | 型ごとの体力・速さ・攻撃の距離と当たる時刻・projectile の速さ |
| `conduit_hive.spawns.json` | 部屋ごとの湧く数・間隔・型 |
| `conduit_hive.pickups.json` | 回復量・弾の量 |
| `conduit_hive.walk.json`・`look.json` | 歩く速さ・感度（night_apartment の WalkDoc / LookDoc を写す） |
| `conduit_hive.particles3d.json` | パーティクルの数・寿命・速さ・色（engine の `fx.json` は 2D の FxDoc の種類なので名前を分ける） |
| `conduit_hive.mixer.json` | 音のバス・cooldowns |

- ステージのマスの印は種類の名前だけを持つ。ピックアップの量は `pickups.json`、湧く数と型は `spawns.json` が正。印の名前が引けなければ 1 行知らせて、その印は置かない。
- 新しい Doc は作る段で schema を作り、project.json の `editor.resources[]` に登録する（docs/doc-conventions.md の外形）。

AI・当たり判定・spawn の決め方はコード。どの Doc も 1 本 30 スカラー前後に収める（docs/doc-conventions.md）。

## 作り（エンジン 0.85.0 の手持ち）

| 物 | 使う口 | 写し元 |
|---|---|---|
| 歩きと見回し | `CharacterBody3d.moveAndSlide`・`App.withMouseCapture`・`frame#mouseDelta` | night_apartment `src/Walker.flix`・`Collider.flix`・`Controls.flix`・`WalkDoc.flix` |
| ステージの絵 | Blender のスクリプトが `maze.stage.json` を読み、壁・床・天井・パイプを**区画（部屋と通路の塊）ごとのノード**に組む。パイプの留め具は区画ごとに 1 つの mesh へ結合する。lightmap も区画ごとにベイクし、場面の絵の予算（docs/lightmap.md）に収める。glb は 1 本で、`Model3d.partsByNode` で区画ごとに置く。glb に Doc のハッシュを empty ノードの名前 `DOCHASH_<16 進>` で書き、ゲームは `Model3d.nodesWithPrefix` で読んで、違えば 1 行知らせる。ベイクする前の確認用に、灰色の箱で描く道も残す | night_apartment `src/Stage.flix`・`/Users/abab/Desktop/horror_apartment/scripts` |
| 部屋ごとの間引き | マス目から区画の隣り合いと「見える区画の組」を前もって作り、今いる区画から見える区画の物と敵だけを描く（エンジンは視錐台の外しか間引かない） | — |
| ステージの当たり判定 | マス目から箱を作る（`CollisionWorld3d`） | night_apartment `Collider.flix` |
| 撃つ | `Camera3d.forwardRay`・`Ray3d.hitCapsule`（体はカプセル・頭は球）。壁で止まる | night_apartment `src/Inspect.flix` |
| 敵の動き | `GridSearch.distances` でプレイヤーへの距離の地図を数コマに 1 回だけ塗り、全員で共有する。隣のマスの値を読んで進む（`Steering.chase` は呼ぶたびに地図を作るので使わない）。敵どうしの押し合いは、マスごとに敵の番号を引ける Map を毎コマ 1 回作り、同じマスと隣のマスの敵とだけ押し離す。ranged は壁の列にレイを当てて見通しを確かめる。melee は振り下ろしのクリップの決まった時刻に、決まった距離の内なら当てる | — |
| 敵の絵 | 骨つき glb（idle・walk・attack・hit・die）を `Pose3d` で混ぜる。予算（段 0.5 で決める）: ジョイント 20 前後・1 体 1 材質・三角形の数。同じクリップは時刻を数通りに丸めて姿勢を共有する。遠い敵・背中側の敵は 2〜3 コマに 1 回だけ姿勢を作る | night_apartment `src/People.flix`（`poseAt`）・fps3d_lab `modeling/character.py` |
| ビューモデル | 2 つ目の `Scene3dCmd` を上の zIndex で同じ "scene" の Pass へ重ねる。深度は場面ごとに消える（GL は `Render3d.beginScene` の `glClear`・CPU は描くたびに深度の配列を作り直す）。2 つ目は `background` と `sky` を None・near を小さく・fovY を別に・霧なし・撃った瞬間の点光源を両方の場面に入れる（ビューモデルには lightmap が付かないので ambient と hemisphere も合わせる） | — |
| パーティクル | ゲームの小さな emitter モジュール（出す・動かす・消す）＋ `Billboard3d`。マズルフラッシュ・火花・体液・projectile。光る物は emission で見せ、点光源（上限 8 本）は撃った瞬間と projectile の近い数個だけ | — |
| 後処理 | ブルームと霧 | night_apartment `src/PostView.flix`（scene → bright → bloomA/B → post） |
| 音 | 銃声・被弾は `App.withAudio` ＋ mixer の cooldowns（同じ名前は同時に 1 本なので、銃声は数本の別名を回す）。敵の声と足音は近い数体だけを `App.withSustained` の volume で距離に合わせる | night_apartment `src/Sounds.flix`・`Soundscape.flix`・`tools/sfx_build.py` |
| HUD | 2D の上描き（体力・弾・武器・照準・被弾の赤み） | — |
| 測り | `App.withDiagnostics` の `scene3dCounts`・`gpuPasses` | engine `docs/performance.md` §11 |
| 動画 | 録った操作から動画を描き出す | night_apartment `src/render/VideoRender.flix` |

## エンジンに足すかもしれない物（**足す前に人へ相談する**）

段 0.5 と段 3 で測り、ゲーム側の手（部屋ごとの間引き・姿勢の共有と間引き・予算）を入れても足りない時だけ:

1. 骨つきの物を、Pose から広げた箱で視錐台の外なら描かない（今は外さない）。
2. 同じ名前の音を重ねて鳴らす口・左右の振り（パン）。上の音の作りで足りなかった時だけ。
3. 並列（C10a の `Par`）: 姿勢と AI がまだ重い時だけ。
4. 3D のインスタンス描き（C9 の一部）: 静的な物は区画ごとの結合で足りる見込みなので、弾や薬莢が多い時だけ。
5. ビューモデルの正式な口と文書: ゲームで形が固まった後に、エンジンへ上げるかを相談する。

## 段（各段の終わりに自分で動かし、絵と数字で確かめる）

| 段 | 中身 | 終わりの確かめ |
|---|---|---|
| 0 | 画風を AGENTS.local.md へ写す。night_apartment から歩き・見回し・当たり判定を写す。`maze.stage.json` から灰色の箱で迷路を組む。区画と見える区画の組・部屋ごとの間引き | 迷路を歩ける・壁を抜けない・描き出しの 1 枚・テスト（見える区画の組） |
| 0.5 | **測る**: fps3d_lab の guard の glb を 50 体、迷路の広い部屋で歩かせる。パイプの密度を仮の箱で入れる。`scene3dCounts` と 1 コマの時間を測る。姿勢の共有と間引きを試す | 数字を出し、クリーチャーの予算（ジョイント数・材質・三角形）を決める。足りなければ人に相談 |
| 1 | Blender でビューモデル（腕と拳銃・骨つき・撃つ・反動のクリップ）。撃つ・照準・emitter とマズルフラッシュ・仮の音。ビューモデルの 4 つの論点を確かめる | 撃つと的に当たる・ビューモデルが壁にめり込まない・GL と CPU の描き出しで同じ形 |
| 2 | Blender でクリーチャー 2 種（予算の内・5 つのクリップ）。追う・押し合い・melee の当たり・ranged の見通しと projectile・被弾・死ぬ。体力と死 | 1 対多で戦える・テスト（当たり判定・ダメージ・spawn・押し合い） |
| 3 | 本物のモデルで 50 体を測り直す | 50 体で 16.7 ms を切らない、を目標に数字を出す |
| 4 | ステージの絵: Blender で迷路を区画ごとに組み、パイプを這わせ、lightmap をベイクする。ピックアップ・散弾銃・連射銃・HUD・タイトルとクリアと死 | 描き出しを批評（絵の下限 5 性質） |
| 5 | 音（Freesound の CC0 を集めて加工・CREDITS.md）・エフェクトの仕上げ・遊びの調整・動画を撮る | 頭から最後の部屋まで遊べる・動画を送る |

- レビューは段 2 の後・段 4 の後・公開の前の 3 回。
- GitHub への公開（public で作ると人が決めた）は、最初のコミットの時に作る。コミットと push の前に人へ一言かける。
- 音: Freesound の音のページの試聴用の高音質版を落とす（ログイン不要。night_apartment と同じ）。CC0 であることをページで確かめる。段 5 の頭で候補の一覧（ページの URL・ライセンス・長さ）を人に見せてから落とし、`sfx_build.py` を写した道具で wav にする。

## まだ分からない所

- 50 体の重さ（段 0.5 で測るまで分からない）。
- Blender で骨つきのクリーチャーを作る道は fps3d_lab の guard で通っているが、腕の長い形は初めて。
