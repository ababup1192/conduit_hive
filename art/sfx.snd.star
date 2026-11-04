# 仮の効果音（段 5 で Freesound の CC0 の素材に替える）。鳴らす所は src/Sounds.flix（World の出来事 → 音）。
# bin/fge snd build art/sfx.snd.star で art/sfx/*.sndsrc.json を書き、検査を通った物を atelier/sfx/<名前>.wav へ書く
# （採用した物を assets/sfx へ移し、project.json の sounds に載せる）。

def burst(ms, at = 0, amp = 0.5, hz = 3000, decay = 60, attack = 2):
    return {"at": at, "ops": [op.noise(ms = ms, amp = amp), op.lowpass(hz = hz, stages = 2), op.env(attack_ms = attack, decay_ms = decay)]}

def thump(hz, ms, at = 0, amp = 0.4, decay = 50, to_hz = None, attack = 2):
    return {"at": at, "ops": [op.pulse(hz = hz, ms = ms, amp = amp, duty = 0.5, to_hz = to_hz, accumulate = to_hz != None),
                              op.lowpass(hz = 900, stages = 2), op.env(attack_ms = attack, decay_ms = decay)]}

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
    # 撃つ: 乾いた破裂（明るい雑音を短く）と、胴に響く低い下がる音、少し遅れて部屋に残る暗い雑音。
    sound("shot", [burst(60, amp = 0.6, hz = 5200, decay = 35),
                   thump(140, 120, amp = 0.45, decay = 80, to_hz = 55),
                   burst(260, at = 20, amp = 0.2, hz = 900, decay = 220, attack = 6)])
main()
