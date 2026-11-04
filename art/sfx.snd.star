# 合成の UI の音（持ち替え・クリア・メニュー）。銃・敵・自分・拾う・合図・環境音は Freesound の CC0 の素材から tools/sfx_build.py が作る。鳴らす所は src/Sounds.flix。
# bin/fge snd build art/sfx.snd.star で art/sfx/*.sndsrc.json を書き、検査を通った物を atelier/sfx/<名前>.wav へ書く
# （採用した物を assets/sfx へ移し、project.json の sounds に載せる）。

def burst(ms, at = 0, amp = 0.5, hz = 3000, decay = 60, attack = 2):
    return {"at": at, "ops": [op.noise(ms = ms, amp = amp), op.lowpass(hz = hz, stages = 2), op.env(attack_ms = attack, decay_ms = decay)]}

def thump(hz, ms, at = 0, amp = 0.4, decay = 50, to_hz = None, attack = 2):
    return {"at": at, "ops": [op.pulse(hz = hz, ms = ms, amp = amp, duty = 0.5, to_hz = to_hz, accumulate = to_hz != None),
                              op.lowpass(hz = 900, stages = 2), op.env(attack_ms = attack, decay_ms = decay)]}

def blip(hz, ms, at = 0, amp = 0.3, to_hz = None, decay = 80):
    return {"at": at, "ops": [op.pulse(hz = hz, ms = ms, amp = amp, duty = 0.25, to_hz = to_hz, accumulate = to_hz != None),
                              op.lowpass(hz = 3200, stages = 2), op.env(attack_ms = 2, decay_ms = decay)]}

def sound(name, voices):
    snd.write_spec("//art/sfx/%s.sndsrc.json" % name, {
        "version": 1,
        "target": "//atelier/sfx/%s.wav" % name,
        "kind": "sfx",
        "style": "free",
        "channels": "mono",
        "voices": voices,
        "post": [op.finish(in_ms = 2, out_ms = 30), op.normalize(lufs = -18)],
    })

def main():
    # 持ち替える: 金属の短い擦れと、重い留め金の低い当たり。
    sound("switch", [burst(40, amp = 0.35, hz = 2600, decay = 25), thump(220, 60, at = 45, amp = 0.35, decay = 40, to_hz = 160)])
    # クリア: ゆっくり上がる 3 音と、部屋に残る暗い響き。
    sound("clear", [blip(392, 260, amp = 0.25, decay = 220), blip(523, 260, at = 180, amp = 0.25, decay = 220),
                    blip(784, 520, at = 360, amp = 0.25, decay = 420), burst(700, at = 360, amp = 0.08, hz = 700, decay = 600, attack = 40)])
    # メニューの項目を動かす: ごく短い高い 1 音。
    sound("ui_move", [blip(1320, 30, amp = 0.2, decay = 25)])
    # メニューで決める・始める・ポーズ: 下がる 2 音の短い合図。
    sound("ui_choose", [blip(880, 50, amp = 0.25, decay = 40), blip(660, 80, at = 45, amp = 0.22, decay = 60)])
main()
