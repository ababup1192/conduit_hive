# 音の素材の出どころ（assets/sfx/src/）

assets/sfx/*.wav のうち下の表の音は、録音素材から `python3 -I tools/sfx_build.py` で作る。素材はすべて
Freesound（https://freesound.org）の **CC0 1.0（パブリックドメイン）** で、商用利用・改変・再配布ができ、表記の義務も
無い（礼儀として作者を残す）。CC BY・非商用・再配布不可・派生物（ほかの Freesound の音を混ぜた物）の素材は使っていない。

- 取得: 2026-11-05。plans/sfx-candidates.md の 52 本の音のページで CC0 1.0 であることを確かめてから、ページの試聴用の
  高音質版（`-hq.ogg`。元のファイルはログインが要るので取っていない）を落とした。
  `ir_corridor__fs732132.ogg` は night_apartment で同じやり方で取った物を写した。
- 加工の共通: モノラル化（ループはステレオのまま）・44.1 kHz・切り出し・低い音の削り（highpass）・必要な物は高い音の削り
  （lowpass）・一発の音は立ち上がりの前の雑音を落とし、通路のインパルス応答を薄く畳み込み（拾う音と振り下ろしは乾いたまま）、
  ピーク -1 dBFS にそろえる・ループは頭と尻を重ねて継ぎ目を消し RMS をそろえ、smpl チャンク（ループ点 = 全体）を付ける。
- 同じ名前は同時に 1 本しか鳴らないので、銃声・被弾・敵の声・足音は `_1..4` の変化を作った。素材が足りない所は
  同じ素材の高さをずらして作った（表の「高さを ○ 倍」）。
- 連射銃は重機関銃の連射の録音を 1 発ずつ切った。次の 1 発（0.1 秒おき・変化 4 本を順に回す）に切られる前に消えるよう、
  響きごと 0.45 秒で閉じる。
- `ui_move`・`ui_choose`・`switch`・`clear`・`pickup`・`shot` は合成の音で、この表の外（tools/sfx_build.py は消さない）。
- 細かい数（切る秒・フィルタ・響きの大きさ）は tools/sfx_build.py が正。この表も `--credits` でそこから書き直す。

| ファイル | 出どころ | 作者 | ライセンス | 元の題 | 使い道と加工 |
|---|---|---|---|---|---|
| `pistol_a__fs163456.ogg` | https://freesound.org/people/LeMudCrab/sounds/163456/ | LeMudCrab | CC0 1.0 | Pistol Shot | shot_pistol_1（拳銃 1・0.00 秒目から 0.46 秒ぶん）<br>shot_pistol_3（拳銃 3（高さを 0.92 倍）・0.00 秒目から 0.50 秒ぶん） |
| `pistol_b__fs427592.ogg` | https://freesound.org/people/michorvath/sounds/427592/ | michorvath | CC0 1.0 | 9mm pistol shot | shot_pistol_2（拳銃 2・0.10 秒目から 0.90 秒ぶん） |
| `shotgun_a__fs427595.ogg` | https://freesound.org/people/michorvath/sounds/427595/ | michorvath | CC0 1.0 | 20 gauge shotgun gunshot | shot_shotgun_1（散弾銃 1・0.03 秒目から 1.30 秒ぶん）<br>explosion_1（爆発 1（散弾銃 2 本を 0.45・0.5 倍の高さで重ね、倒れの低音を -6 dB・金属の破片を 0.38 秒後に -14 dB）・0.03 秒目から 2.20 秒ぶん）<br>explosion_2（爆発 2（散弾銃 2 本を 0.42・0.55 倍の高さで重ね、重い扉の唸りを -10 dB・金属の破片を 0.42 秒後に -15 dB）・0.03 秒目から 2.20 秒ぶん） |
| `shotgun_b__fs163455.ogg` | https://freesound.org/people/LeMudCrab/sounds/163455/ | LeMudCrab | CC0 1.0 | Shotgun Shot | shot_shotgun_2（散弾銃 2・0.00 秒目から 0.69 秒ぶん）<br>explosion_1（爆発 1（散弾銃 2 本を 0.45・0.5 倍の高さで重ね、倒れの低音を -6 dB・金属の破片を 0.38 秒後に -14 dB）・0.00 秒目から 2.20 秒ぶん）<br>explosion_2（爆発 2（散弾銃 2 本を 0.42・0.55 倍の高さで重ね、重い扉の唸りを -10 dB・金属の破片を 0.42 秒後に -15 dB）・0.00 秒目から 2.20 秒ぶん） |
| `mg_burst__fs165394.ogg` | https://freesound.org/people/ShawnyBoy/sounds/165394/ | ShawnyBoy | CC0 1.0 | Heavy Machine Gun | shot_rifle_1（連射銃 1・0.35 秒目から 0.17 秒ぶん）<br>shot_rifle_2（連射銃 2・0.52 秒目から 0.17 秒ぶん）<br>shot_rifle_3（連射銃 3・0.88 秒目から 0.17 秒ぶん）<br>shot_rifle_4（連射銃 4（高さを 0.96 倍）・1.05 秒目から 0.18 秒ぶん） |
| `laser_gun__fs187119.ogg` | https://freesound.org/people/unfa/sounds/187119/ | unfa | CC0 1.0 | unfa's Laser Weapon Sounds | 使っていない（候補として落とした予備） |
| `pump_a__fs200966.ogg` | https://freesound.org/people/Paul368/sounds/200966/ | Paul368 | CC0 1.0 | Shotgun Cock Reload Layered (Powerful) | shotgun_pump（先台を引く・0.10 秒目から 0.90 秒ぶん） |
| `pump_b__fs55341.ogg` | https://freesound.org/people/hiramjustus/sounds/55341/ | hiramjustus | CC0 1.0 | shotgun.wav | 使っていない（候補として落とした予備） |
| `reload_a__fs396331.ogg` | https://freesound.org/people/nioczkus/sounds/396331/ | nioczkus | CC0 1.0 | 1911 Reload | reload（弾倉を替える・0.00 秒目から 0.80 秒ぶん） |
| `reload_b__fs363167.ogg` | https://freesound.org/people/SamsterBirdies/sounds/363167/ | SamsterBirdies | CC0 1.0 | Mag reload | 使っていない（候補として落とした予備） |
| `dryfire_a__fs725402.ogg` | https://freesound.org/people/ser%C3%B8ut%C5%8Dnin--depriv%C9%99d/sounds/725402/ | serøutōnin--deprivəd | CC0 1.0 | A rifle being dry fired once | dryfire（空撃ち・0.00 秒目から 0.45 秒ぶん） |
| `dryfire_b__fs674568.ogg` | https://freesound.org/people/ser%C3%B8ut%C5%8Dnin--depriv%C9%99d/sounds/674568/ | serøutōnin--deprivəd | CC0 1.0 | 9mm Handgun Being Dry Fired | 使っていない（候補として落とした予備） |
| `shells_a__fs318964.ogg` | https://freesound.org/people/GryffDavid/sounds/318964/ | GryffDavid | CC0 1.0 | Bouncing Shell Casings (Various Sizes) | shell_1（薬莢 1・30.36 秒目から 0.65 秒ぶん）<br>shell_2（薬莢 2・39.29 秒目から 0.65 秒ぶん） |
| `shells_b__fs210102.ogg` | https://freesound.org/people/GrayJoy/sounds/210102/ | GrayJoy | CC0 1.0 | Brass bullet shell casing drop onto concrete, multiple takes | shell_3（薬莢 3（コンクリート）・4.09 秒目から 0.70 秒ぶん） |
| `metal_ping__fs351371.ogg` | https://freesound.org/people/wilhellboy/sounds/351371/ | wilhellboy | CC0 1.0 | HeavyBulletPing.mp3 | ricochet_1（金属に当たる 1・0.00 秒目から 0.42 秒ぶん）<br>grenade_bounce_1（手榴弾が跳ねる 1（金属に当たる音を 0.62 倍の高さ）・0.00 秒目から 0.32 秒ぶん） |
| `ricochet__fs30932.ogg` | https://freesound.org/people/aust_paul/sounds/30932/ | aust_paul | CC0 1.0 | bullet ricochet.wav | ricochet_2（金属に当たる 2（跳弾）・0.01 秒目から 0.50 秒ぶん） |
| `metal_hits__fs116645.ogg` | https://freesound.org/people/Woodingp/sounds/116645/ | Woodingp | CC0 1.0 | bullets hit EDIT.aif | ricochet_3（金属に当たる 3・3.41 秒目から 0.30 秒ぶん）<br>enemy_down_1（倒れる 1（金属板の打撃を -14 dB 重ねる）・6.71 秒目から 1.30 秒ぶん）<br>enemy_down_2（倒れる 2（高さを 0.86 倍・金属板の打撃を -16 dB 重ねる）・3.73 秒目から 1.45 秒ぶん）<br>grenade_bounce_2（手榴弾が跳ねる 2（金属板の打撃を 0.78 倍の高さ）・3.41 秒目から 0.30 秒ぶん）<br>explosion_1（爆発 1（散弾銃 2 本を 0.45・0.5 倍の高さで重ね、倒れの低音を -6 dB・金属の破片を 0.38 秒後に -14 dB）・6.71 秒目から 2.20 秒ぶん）<br>explosion_2（爆発 2（散弾銃 2 本を 0.42・0.55 倍の高さで重ね、重い扉の唸りを -10 dB・金属の破片を 0.42 秒後に -15 dB）・3.73 秒目から 2.20 秒ぶん） |
| `growl_a__fs442115.ogg` | https://freesound.org/people/Darsycho/sounds/442115/ | Darsycho | CC0 1.0 | troll idle noises.wav | enemy_growl_1（唸り 1・3.83 秒目から 2.77 秒ぶん）<br>enemy_growl_2（唸り 2・6.86 秒目から 1.65 秒ぶん）<br>enemy_growl_3（唸り 3・14.09 秒目から 2.36 秒ぶん） |
| `growl_b__fs20208.ogg` | https://freesound.org/people/ubecareful/sounds/20208/ | ubecareful | CC0 1.0 | growl1.wav | enemy_charge（吐く前の溜め（喉の唸り。高さを 1.25 倍）・0.87 秒目から 0.75 秒ぶん） |
| `scream_a__fs391552.ogg` | https://freesound.org/people/gpag1/sounds/391552/ | gpag1 | CC0 1.0 | Monster screams.wav | enemy_scream_1（叫び 1・17.45 秒目から 2.60 秒ぶん）<br>enemy_scream_2（叫び 2・64.20 秒目から 2.40 秒ぶん） |
| `scream_b__fs398908.ogg` | https://freesound.org/people/quadraslayer/sounds/398908/ | quadraslayer | CC0 1.0 | Monster Roar 2.wav | enemy_scream_3（咆哮（叫び 3）・1.45 秒目から 2.90 秒ぶん） |
| `swing_a__fs60013.ogg` | https://freesound.org/people/qubodup/sounds/60013/ | qubodup | CC0 1.0 | Whoosh | enemy_swing_1（振り下ろし 1・0.00 秒目から 0.43 秒ぶん）<br>kick（蹴り（風切り -6 dB・肉の打撃を 0.78 倍の高さで 0.07 秒後・倒れの低音を -9 dB 重ねる）・0.00 秒目から 0.62 秒ぶん）<br>kick_miss（空振りの蹴り（風切りを 0.85 倍の高さ・踏み込みの足音を -6 dB 重ねる）・0.00 秒目から 0.48 秒ぶん） |
| `swing_b__fs72191.ogg` | https://freesound.org/people/snowflakes/sounds/72191/ | snowflakes | CC0 1.0 | whip03.wav | enemy_swing_2（振り下ろし 2・0.00 秒目から 0.42 秒ぶん）<br>dodge（緊急回避（風切りを 0.72 倍の高さ・着地の足音を 0.24 秒後に -3 dB 重ねる）・0.00 秒目から 0.62 秒ぶん）<br>grenade_throw（手榴弾を投げる（ピンを抜く金具の音・速い風切りを 1.15 倍の高さで 0.09 秒後）・0.00 秒目から 0.62 秒ぶん） |
| `flesh_a__fs423301.ogg` | https://freesound.org/people/u1769092/sounds/423301/ | u1769092 | CC0 1.0 | VisceralBulletImpacts.wav | enemy_hit_1（被弾 1・0.11 秒目から 0.30 秒ぶん）<br>enemy_hit_2（被弾 2・0.82 秒目から 0.30 秒ぶん）<br>gib_2（弾ける 2（高さを 0.75 倍・肉の音を -4 dB 重ねる）・0.11 秒目から 0.65 秒ぶん） |
| `flesh_b__fs511194.ogg` | https://freesound.org/people/Pablobd/sounds/511194/ | Pablobd | CC0 1.0 | Headshot.wav | enemy_hit_3（被弾 3・0.03 秒目から 0.60 秒ぶん）<br>gib_1（弾ける 1（高さを 0.8 倍・肉の音を -4 dB 重ねる）・0.03 秒目から 0.60 秒ぶん）<br>kick（蹴り（風切り -6 dB・肉の打撃を 0.78 倍の高さで 0.07 秒後・倒れの低音を -9 dB 重ねる）・0.03 秒目から 0.62 秒ぶん） |
| `body_fall__fs504626.ogg` | https://freesound.org/people/leonelmail/sounds/504626/ | leonelmail | CC0 1.0 | BODY FALL - V HVY - DIRT | enemy_down_1（倒れる 1（金属板の打撃を -14 dB 重ねる）・0.30 秒目から 1.30 秒ぶん）<br>enemy_down_2（倒れる 2（高さを 0.86 倍・金属板の打撃を -16 dB 重ねる）・0.30 秒目から 1.45 秒ぶん）<br>kick（蹴り（風切り -6 dB・肉の打撃を 0.78 倍の高さで 0.07 秒後・倒れの低音を -9 dB 重ねる）・0.30 秒目から 0.62 秒ぶん）<br>explosion_1（爆発 1（散弾銃 2 本を 0.45・0.5 倍の高さで重ね、倒れの低音を -6 dB・金属の破片を 0.38 秒後に -14 dB）・0.30 秒目から 2.20 秒ぶん） |
| `spit_a__fs237386.ogg` | https://freesound.org/people/squareal/sounds/237386/ | squareal | CC0 1.0 | Spitting Blood 01.wav | 使っていない（候補として落とした予備） |
| `spit_b__fs751338.ogg` | https://freesound.org/people/qubodup/sounds/751338/ | qubodup | CC0 1.0 | Slime Attack 1 | enemy_spit（吐く（高さを 0.85 倍）・0.00 秒目から 0.52 秒ぶん） |
| `splat_a__fs445109.ogg` | https://freesound.org/people/Breviceps/sounds/445109/ | Breviceps | CC0 1.0 | Mud Splat | spit_burst_1（塊が弾ける 1・0.00 秒目から 0.36 秒ぶん）<br>gib_1（弾ける 1（高さを 0.8 倍・肉の音を -4 dB 重ねる）・0.00 秒目から 0.60 秒ぶん） |
| `splat_b__fs445968.ogg` | https://freesound.org/people/Breviceps/sounds/445968/ | Breviceps | CC0 1.0 | So slimy! | spit_burst_2（塊が弾ける 2・1.38 秒目から 0.40 秒ぶん）<br>gib_2（弾ける 2（高さを 0.75 倍・肉の音を -4 dB 重ねる）・1.38 秒目から 0.65 秒ぶん） |
| `grunt_a__fs547209.ogg` | https://freesound.org/people/MrFossy/sounds/547209/ | MrFossy | CC0 1.0 | Voice_AdultMale_PainGrunts_09.wav | player_hurt_1（うめき 1・0.00 秒目から 0.32 秒ぶん）<br>player_hurt_3（うめき 3（高さを 0.9 倍）・0.00 秒目から 0.36 秒ぶん） |
| `grunt_b__fs257709.ogg` | https://freesound.org/people/vmgraw/sounds/257709/ | vmgraw | CC0 1.0 | GRUNT 2.wav | player_hurt_2（うめき 2・0.20 秒目から 0.56 秒ぶん）<br>stamina_out（息切れ（うめきを 0.92 倍の高さで、高い音を削って息の荒さに）・0.20 秒目から 0.60 秒ぶん） |
| `death_voice__fs577033.ogg` | https://freesound.org/people/Blankened/sounds/577033/ | Blankened | CC0 1.0 | MaleDeathSound12.wav | player_down（倒れる声・0.00 秒目から 1.74 秒ぶん） |
| `step_metal_a__fs834029.ogg` | https://freesound.org/people/IENBA/sounds/834029/ | IENBA | CC0 1.0 | Footsteps On Metal | step_metal_1（足音 1・1.11 秒目から 0.38 秒ぶん）<br>step_metal_2（足音 2・1.61 秒目から 0.38 秒ぶん）<br>step_metal_3（足音 3・2.18 秒目から 0.38 秒ぶん）<br>step_metal_4（足音 4・4.96 秒目から 0.38 秒ぶん）<br>dodge（緊急回避（風切りを 0.72 倍の高さ・着地の足音を 0.24 秒後に -3 dB 重ねる）・1.11 秒目から 0.62 秒ぶん）<br>kick_miss（空振りの蹴り（風切りを 0.85 倍の高さ・踏み込みの足音を -6 dB 重ねる）・2.18 秒目から 0.48 秒ぶん） |
| `step_metal_b__fs50724.ogg` | https://freesound.org/people/RutgerMuller/sounds/50724/ | RutgerMuller | CC0 1.0 | Footsteps Metallic Muffled Louder.wav | 使っていない（候補として落とした予備） |
| `heal_a__fs204318.ogg` | https://freesound.org/people/juancamiloorjuela/sounds/204318/ | juancamiloorjuela | CC0 1.0 | Pick-up Health | pickup_health（回復を拾う・0.00 秒目から 1.00 秒ぶん） |
| `heal_b__fs471834.ogg` | https://freesound.org/people/KeshaFilm/sounds/471834/ | KeshaFilm | CC0 1.0 | Health Pickup | 使っていない（候補として落とした予備） |
| `ammo_pick__fs653032.ogg` | https://freesound.org/people/BBBBilly/sounds/653032/ | BBBBilly | CC0 1.0 | pickup_ammo.wav | pickup_ammo（弾を拾う・0.00 秒目から 0.72 秒ぶん） |
| `weapon_pick_a__fs363174.ogg` | https://freesound.org/people/runningmind/sounds/363174/ | runningmind | CC0 1.0 | Pickup_Weapon_Shock.wav | grenade_throw（手榴弾を投げる（ピンを抜く金具の音・速い風切りを 1.15 倍の高さで 0.09 秒後）・0.00 秒目から 0.62 秒ぶん） |
| `weapon_pick_b__fs464529.ogg` | https://freesound.org/people/pcmac/sounds/464529/ | pcmac | CC0 1.0 | Gun_Pickup.wav | pickup_weapon（武器を拾う・0.15 秒目から 0.41 秒ぶん） |
| `machine_a__fs100403.ogg` | https://freesound.org/people/pushkin/sounds/100403/ | pushkin | CC0 1.0 | EnginesTurbinesOne.wav | amb_machine（ループ・機械のうなり（2 本を重ね、艦橋の電子音は高い音を削って消す）・10.0 秒目から 20.0 秒ぶん） |
| `machine_b__fs211683.ogg` | https://freesound.org/people/Diboz/sounds/211683/ | Diboz | CC0 1.0 | control_room.wav | amb_machine（ループ・機械のうなり（2 本を重ね、艦橋の電子音は高い音を削って消す）・20.0 秒目から 20.0 秒ぶん） |
| `vent_a__fs427861.ogg` | https://freesound.org/people/leonelmail/sounds/427861/ | leonelmail | CC0 1.0 | Roomtone Warehouse Fans Vents Large | amb_vent（ループ・換気のファン・20.0 秒目から 20.0 秒ぶん） |
| `vent_b__fs166014.ogg` | https://freesound.org/people/amenhotepIV/sounds/166014/ | amenhotepIV | CC0 1.0 | Ambient Industrial Ventilation Soundscape | 使っていない（候補として落とした予備） |
| `creak_a__fs434692.ogg` | https://freesound.org/people/BuytheField/sounds/434692/ | BuytheField | CC0 1.0 | Return of the Mars Mission.wav | amb_pipes（ループ・配管の水の流れ・船体の軋み・配管の圧の音を重ねる・40.0 秒目から 24.0 秒ぶん） |
| `creak_b__fs172407.ogg` | https://freesound.org/people/EagleStealthTeam/sounds/172407/ | EagleStealthTeam | CC0 1.0 | Creaking Metal - With Metallic Reverb | 使っていない（候補として落とした予備） |
| `pipe_flow_a__fs155515.ogg` | https://freesound.org/people/klangfabrik/sounds/155515/ | klangfabrik | CC0 1.0 | waterthrupipes.aiff | amb_pipes（ループ・配管の水の流れ・船体の軋み・配管の圧の音を重ねる・30.0 秒目から 24.0 秒ぶん） |
| `pipe_flow_b__fs104087.ogg` | https://freesound.org/people/RutgerMuller/sounds/104087/ | RutgerMuller | CC0 1.0 | Pressure Meter Pipe Noises 1.aif | amb_pipes（ループ・配管の水の流れ・船体の軋み・配管の圧の音を重ねる・2.0 秒目から 24.0 秒ぶん） |
| `alarm_a__fs699248.ogg` | https://freesound.org/people/Mozfoo/sounds/699248/ | Mozfoo | CC0 1.0 | Emergency Alarm.wav | alarm（群れが出る警報（3 回鳴る所まで）・0.02 秒目から 3.20 秒ぶん） |
| `alarm_b__fs832414.ogg` | https://freesound.org/people/qubodup/sounds/832414/ | qubodup | CC0 1.0 | Factory Warning Buzzer | 使っていない（候補として落とした予備） |
| `door_a__fs543404.ogg` | https://freesound.org/people/alexo400/sounds/543404/ | alexo400 | CC0 1.0 | SCI_FI_DOOR.wav | door（SF の扉・0.00 秒目から 1.84 秒ぶん） |
| `door_b__fs130655.ogg` | https://freesound.org/people/PlayPauseAndRewind/sounds/130655/ | PlayPauseAndRewind | CC0 1.0 | Iron door opens | explosion_2（爆発 2（散弾銃 2 本を 0.42・0.55 倍の高さで重ね、重い扉の唸りを -10 dB・金属の破片を 0.42 秒後に -15 dB）・3.00 秒目から 2.20 秒ぶん）<br>door_heavy（重い鉄扉が開く・3.00 秒目から 4.70 秒ぶん） |
| `ir_corridor__fs732132.ogg` | https://freesound.org/people/djericmark/sounds/732132/ | djericmark | CC0 1.0 | GARAGE 0.78s CORRIDOR-STAIRS IR REVERB | 通路の響き（インパルス応答。直接音の前を落とし 0.9 秒で切って、響きを付ける一発の音に畳み込む） |
