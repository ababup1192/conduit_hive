#!/usr/bin/env python3
"""施設の音を、録音素材（assets/sfx/src/）から assets/sfx/*.wav へ作る。

  python3 -I tools/sfx_build.py            … wav を作る（ffmpeg が要る）
  python3 -I tools/sfx_build.py --credits  … assets/sfx/CREDITS.md の表を、下の定義と sources.tsv から書き直す
  python3 -I tools/sfx_build.py --report   … 作った wav の長さ・ピーク・RMS を debug/sfx/report.tsv へ書く

素材の出どころとライセンスは assets/sfx/CREDITS.md、素材の一覧表は assets/sfx/src/sources.tsv。
加工は ffmpeg と、響きの畳み込みだけ Python で行う。同じ素材と同じ ffmpeg なら、何度流しても同じ WAV になる。

  一発の音  … 切り出し（いくつかの素材を重ねてもよい）、低い音を削り、立ち上がりの前の雑音を落とし、
              通路のインパルス応答を薄く畳み込んで、-1 dBFS のピークへそろえる。モノラル。
  ループ    … 素材の落ち着いた区間を切り、頭と尻を重ねて継ぎ目を消し、RMS をそろえる。ステレオ。smpl チャンク付き。

project.json は書き換えない（音の名前をつなぐのはゲームの側の仕事）。この表に無い wav（合成の UI の音）も消さない。
"""
import array
import cmath
import glob
import math
import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "sfx", "src")
OUT = os.path.join(ROOT, "assets", "sfx")
TMP = os.path.join(ROOT, "debug", "sfx", "work")
DEBUG = os.path.join(ROOT, "debug", "sfx")
RATE = 44100
PEAK_DB = -1.0

IR = "ir_corridor"
IR_LOWPASS = 7000
WET_RATE = 22050   # 響きの成分は高い音を削るので、半分の速さで畳み込んで速くする
IR_MAX = 0.9


def layer(src, start, gain_db=0.0, af=""):
    return {"src": src, "start": start, "gain_db": gain_db, "af": af}


def shot(name, layers, dur, wet_db=None, gain_db=0.0, gate_db=None, max_len=None, use=""):
    """wet_db: 乾いた音の RMS から見た響きの大きさ（None なら響きを付けない）。
    gate_db: 立ち上がりの前を落とす閾（ピークからの dB。None なら落とさない）。
    max_len: 響きを足した後の長さの上限（速い連射で次の 1 発に切られる前に自分で消える）。"""
    if isinstance(layers, dict):
        layers = [layers]
    return {"name": name, "layers": layers, "dur": dur, "wet_db": wet_db, "gain_db": gain_db,
            "gate_db": gate_db, "max_len": max_len, "use": use}


def loop(name, layers, length, xfade=3.0, rms_db=-26.0, use=""):
    return {"name": name, "layers": layers, "length": length, "xfade": xfade, "rms_db": rms_db, "use": use}


def pitch(p):
    """高さを p 倍にする（長さも 1/p になる）。"""
    return f"aresample={RATE},asetrate={RATE}*{p},aresample={RATE}"


GUN_HP = "highpass=f=45"
VOICE_HP = "highpass=f=70"

SHOTS = [
    # ── 撃つ ──
    shot("shot_pistol_1", layer("pistol_a", 0.000, 0, GUN_HP), 0.46, -16.0, gate_db=30, use="拳銃 1"),
    shot("shot_pistol_2", layer("pistol_b", 0.105, 0, GUN_HP + ",lowpass=f=12000"), 0.90, -18.0, gate_db=30, use="拳銃 2"),
    shot("shot_pistol_3", layer("pistol_a", 0.000, 0, GUN_HP + "," + pitch(0.92)), 0.50, -16.0, gate_db=30, use="拳銃 3（高さを 0.92 倍）"),
    shot("shot_shotgun_1", layer("shotgun_a", 0.030, 0, "highpass=f=35"), 1.30, -16.0, gate_db=30, use="散弾銃 1"),
    shot("shot_shotgun_2", layer("shotgun_b", 0.000, 0, "highpass=f=35"), 0.69, -14.0, gate_db=30, use="散弾銃 2"),
    # 連射銃は録音が 0.175 秒おきの連射なので 1 発ずつ切る。次の 1 発までに消えるよう響きごと 0.45 秒で閉じる
    shot("shot_rifle_1", layer("mg_burst", 0.348, -3, GUN_HP + ",lowpass=f=10000"), 0.17, -12.0, max_len=0.45, use="連射銃 1"),
    shot("shot_rifle_2", layer("mg_burst", 0.523, -3, GUN_HP + ",lowpass=f=10000"), 0.17, -12.0, max_len=0.45, use="連射銃 2"),
    shot("shot_rifle_3", layer("mg_burst", 0.876, -3, GUN_HP + ",lowpass=f=10000"), 0.17, -12.0, max_len=0.45, use="連射銃 3"),
    shot("shot_rifle_4", layer("mg_burst", 1.052, -3, GUN_HP + ",lowpass=f=10000," + pitch(0.96)), 0.18, -12.0, max_len=0.45,
         use="連射銃 4（高さを 0.96 倍）"),
    # ── 銃の手元 ──
    shot("shotgun_pump", layer("pump_a", 0.100, 0, "highpass=f=60"), 0.90, -20.0, gate_db=40, use="先台を引く"),
    shot("reload", layer("reload_a", 0.000, 0, "highpass=f=80"), 0.80, -20.0, gate_db=40, use="弾倉を替える"),
    shot("dryfire", layer("dryfire_a", 0.000, 0, "highpass=f=200"), 0.45, -20.0, gate_db=30, use="空撃ち"),
    shot("shell_1", layer("shells_a", 30.358, 0, "highpass=f=300,afftdn=nr=10:nf=-50"), 0.65, -18.0, gate_db=30, use="薬莢 1"),
    shot("shell_2", layer("shells_a", 39.291, 0, "highpass=f=300,afftdn=nr=10:nf=-50"), 0.65, -18.0, gate_db=30, use="薬莢 2"),
    shot("shell_3", layer("shells_b", 4.088, 0, "highpass=f=300,afftdn=nr=10:nf=-50"), 0.70, -18.0, gate_db=30, use="薬莢 3（コンクリート）"),
    shot("ricochet_1", layer("metal_ping", 0.000, 0, "highpass=f=150"), 0.42, -12.0, gate_db=30, use="金属に当たる 1"),
    shot("ricochet_2", layer("ricochet", 0.010, 0, "highpass=f=150"), 0.50, -12.0, gate_db=30, use="金属に当たる 2（跳弾）"),
    shot("ricochet_3", layer("metal_hits", 3.407, 0, "highpass=f=150"), 0.30, -12.0, gate_db=30, use="金属に当たる 3"),
    # ── 敵 ──
    shot("enemy_growl_1", layer("growl_a", 3.83, 0, "highpass=f=40"), 2.77, -14.0, use="唸り 1"),
    shot("enemy_growl_2", layer("growl_a", 6.86, 0, "highpass=f=40"), 1.65, -14.0, use="唸り 2"),
    shot("enemy_growl_3", layer("growl_a", 14.09, 0, "highpass=f=40"), 2.36, -14.0, use="唸り 3"),
    shot("enemy_scream_1", layer("scream_a", 17.45, 0, "highpass=f=60"), 2.60, -14.0, gate_db=45, use="叫び 1"),
    shot("enemy_scream_2", layer("scream_a", 64.20, 0, "highpass=f=60"), 2.40, -14.0, gate_db=45, use="叫び 2"),
    shot("enemy_scream_3", layer("scream_b", 1.45, 0, "highpass=f=40"), 2.90, -14.0, gate_db=45, use="咆哮（叫び 3）"),
    shot("enemy_swing_1", layer("swing_a", 0.000, 0, "highpass=f=120"), 0.43, None, gate_db=40, use="振り下ろし 1"),
    shot("enemy_swing_2", layer("swing_b", 0.000, 0, "highpass=f=120"), 0.42, None, gate_db=40, use="振り下ろし 2"),
    shot("enemy_hit_1", layer("flesh_a", 0.114, 0, "highpass=f=70"), 0.30, -16.0, gate_db=30, use="被弾 1"),
    shot("enemy_hit_2", layer("flesh_a", 0.820, 0, "highpass=f=70"), 0.30, -16.0, gate_db=30, use="被弾 2"),
    shot("enemy_hit_3", layer("flesh_b", 0.030, 0, "highpass=f=70"), 0.60, -16.0, gate_db=30, use="被弾 3"),
    # 倒れる: 重い倒れに金属板の打撃を薄く重ね、通路の床に落ちた音にする
    shot("enemy_down_1", [layer("body_fall", 0.30, 0, "highpass=f=40"),
                          layer("metal_hits", 6.706, -14, "highpass=f=200,adelay=250")], 1.30, -10.0, gate_db=40,
         use="倒れる 1（金属板の打撃を -14 dB 重ねる）"),
    shot("enemy_down_2", [layer("body_fall", 0.30, 0, "highpass=f=40," + pitch(0.86)),
                          layer("metal_hits", 3.725, -16, "highpass=f=200,adelay=280")], 1.45, -10.0, gate_db=40,
         use="倒れる 2（高さを 0.86 倍・金属板の打撃を -16 dB 重ねる）"),
    shot("enemy_spit", layer("spit_b", 0.000, 0, "highpass=f=80," + pitch(0.85)), 0.52, -14.0, gate_db=40, use="吐く（高さを 0.85 倍）"),
    shot("spit_burst_1", layer("splat_a", 0.000, 0, "highpass=f=80"), 0.36, -12.0, gate_db=30, use="塊が弾ける 1"),
    shot("spit_burst_2", layer("splat_b", 1.378, 0, "highpass=f=80"), 0.40, -12.0, gate_db=30, use="塊が弾ける 2"),
    # ── 自分 ──
    shot("player_hurt_1", layer("grunt_a", 0.000, 0, VOICE_HP), 0.32, -20.0, gate_db=40, use="うめき 1"),
    shot("player_hurt_2", layer("grunt_b", 0.200, 0, VOICE_HP), 0.56, -20.0, gate_db=40, use="うめき 2"),
    shot("player_hurt_3", layer("grunt_a", 0.000, 0, VOICE_HP + "," + pitch(0.9)), 0.36, -20.0, gate_db=40, use="うめき 3（高さを 0.9 倍）"),
    shot("player_down", layer("death_voice", 0.000, 0, VOICE_HP), 1.74, -16.0, gate_db=45, use="倒れる声"),
    shot("step_metal_1", layer("step_metal_a", 1.108, 0, "highpass=f=70"), 0.38, -18.0, gate_db=30, use="足音 1"),
    shot("step_metal_2", layer("step_metal_a", 1.613, 0, "highpass=f=70"), 0.38, -18.0, gate_db=30, use="足音 2"),
    shot("step_metal_3", layer("step_metal_a", 2.176, 0, "highpass=f=70"), 0.38, -18.0, gate_db=30, use="足音 3"),
    shot("step_metal_4", layer("step_metal_a", 4.962, 0, "highpass=f=70"), 0.38, -18.0, gate_db=30, use="足音 4"),
    # ── 拾う（響きを付けない。画面の手前の出来事なので） ──
    shot("pickup_health", layer("heal_a", 0.000, 0, "highpass=f=60"), 1.00, None, gate_db=40, use="回復を拾う"),
    shot("pickup_ammo", layer("ammo_pick", 0.000, 0, "highpass=f=80"), 0.72, None, gate_db=40, use="弾を拾う"),
    shot("pickup_weapon", layer("weapon_pick_b", 0.150, 0, "highpass=f=80"), 0.41, None, gate_db=30, use="武器を拾う"),
    # ── 合図 ──
    shot("alarm", layer("alarm_a", 0.020, 0, "highpass=f=80"), 3.20, -14.0, use="群れが出る警報（3 回鳴る所まで）"),
    shot("door", layer("door_a", 0.000, 0, "highpass=f=40"), 1.84, -14.0, gate_db=45, use="SF の扉"),
    shot("door_heavy", layer("door_b", 3.000, 0, "highpass=f=35"), 4.70, -12.0, gate_db=45, use="重い鉄扉が開く"),
]

LOOPS = [
    loop("amb_machine", [layer("machine_a", 10.0, 0.0, "highpass=f=30"),
                         layer("machine_b", 20.0, -6.0, "highpass=f=30,lowpass=f=2500")], 20.0, 3.0, -26.0,
         use="機械のうなり（2 本を重ね、艦橋の電子音は高い音を削って消す）"),
    loop("amb_vent", [layer("vent_a", 20.0, 0.0, "highpass=f=30,lowpass=f=9000")], 20.0, 3.0, -28.0, use="換気のファン"),
    loop("amb_pipes", [layer("pipe_flow_a", 30.0, 0.0, "highpass=f=60"),
                       layer("creak_a", 40.0, -5.0, "highpass=f=40"),
                       layer("pipe_flow_b", 2.0, -8.0, "highpass=f=60")], 24.0, 3.0, -28.0,
         use="配管の水の流れ・船体の軋み・配管の圧の音を重ねる"),
]


def run(args, binary=False):
    r = subprocess.run(args, capture_output=True, text=not binary)
    if r.returncode != 0:
        err = r.stderr if not binary else r.stderr.decode("utf-8", "replace")
        sys.exit(f"[sfx] 失敗: {' '.join(args)}\n{err[-2000:]}")
    return r


def ffmpeg(*args):
    return run(["ffmpeg", "-nostdin", "-hide_banner", "-v", "error", "-y", *args])


def source(key):
    hits = glob.glob(os.path.join(SRC, f"{key}__*.ogg"))
    if len(hits) != 1:
        sys.exit(f"[sfx] 素材 {key} が assets/sfx/src に 1 つだけ無い: {hits}")
    return hits[0]


def measure(path):
    """(RMS dB, ピーク dB)。全チャンネルを通した値。"""
    r = run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af", "astats=measure_perchannel=none", "-f", "null", "-"])
    rms = float(re.search(r"RMS level dB:\s*(-?[\d.]+|-inf)", r.stderr).group(1).replace("-inf", "-120"))
    peak = float(re.search(r"Peak level dB:\s*(-?[\d.]+|-inf)", r.stderr).group(1).replace("-inf", "-120"))
    return rms, peak


def gain(src, dst, db):
    ffmpeg("-i", src, "-af", f"volume={db:.3f}dB", "-ar", str(RATE), "-c:a", "pcm_s16le", dst)


def decode(path, rate, af=""):
    args = ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-ac", "1", "-ar", str(rate)]
    if af:
        args += ["-af", af]
    a = array.array("f")
    a.frombytes(run(args + ["-f", "f32le", "-"], binary=True).stdout)
    return list(a)


def encode(samples, rate, path):
    a = array.array("f", samples)
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "-",
                    "-ar", str(RATE), "-c:a", "pcm_f32le", path], input=a.tobytes(), check=True)


TWIDDLE = {}
IR_SPECTRA = {}


def fft(x, inverse=False):
    n = len(x)
    if n == 1:
        return x
    even = fft(x[0::2], inverse)
    odd = fft(x[1::2], inverse)
    sign = 1 if inverse else -1
    tw = TWIDDLE.get((n, sign))
    if tw is None:
        tw = [cmath.exp(sign * 2j * math.pi * k / n) for k in range(n // 2)]
        TWIDDLE[(n, sign)] = tw
    t = [w * o for w, o in zip(tw, odd)]
    return [e + u for e, u in zip(even, t)] + [e - u for e, u in zip(even, t)]


def convolve(signal, ir):
    """FFT で畳み込む（ffmpeg の afir は手元の版で無音を返したので使わない）。"""
    need = len(signal) + len(ir) - 1
    n = 1
    while n < need:
        n *= 2
    if n not in IR_SPECTRA:
        IR_SPECTRA[n] = fft([complex(v) for v in ir] + [0j] * (n - len(ir)))
    spec = fft([complex(v) for v in signal] + [0j] * (n - len(signal)))
    out = fft([a * b for a, b in zip(spec, IR_SPECTRA[n])], inverse=True)
    return [v.real / n for v in out[:need]]


def prepare_ir():
    return decode(source(IR), WET_RATE,
                  f"silenceremove=start_periods=1:start_threshold=-45dB,atrim=end={IR_MAX},"
                  f"areverse,afade=t=in:d=0.2,areverse")


def cut_layers(name, layers, dur, channels):
    """素材を切り出して重ねる。重ねた後に長さ dur で閉じる。"""
    parts = []
    for i, ly in enumerate(layers):
        seg = os.path.join(TMP, f"{name}_l{i}.wav")
        chain = ",".join(c for c in (f"aresample={RATE}", ly["af"], f"volume={ly['gain_db']}dB") if c)
        ffmpeg("-ss", f"{ly['start']:.3f}", "-t", f"{dur + 1.0:.3f}", "-i", source(ly["src"]),
               "-ac", str(channels), "-af", chain, "-ar", str(RATE), "-c:a", "pcm_f32le", seg)
        parts.append(seg)
    return parts


def build_shot(s, ir):
    parts = cut_layers(s["name"], s["layers"], s["dur"], 1)
    cut = os.path.join(TMP, f"{s['name']}_cut.wav")
    fade = min(0.06, s["dur"] * 0.3)
    ins = sum((["-i", p] for p in parts), [])
    ffmpeg(*ins, "-filter_complex",
           f"{''.join(f'[{i}:a]' for i in range(len(parts)))}amix=inputs={len(parts)}:normalize=0:duration=first,"
           f"atrim=end={s['dur']:.4f},afade=t=in:d=0.003,afade=t=out:st={s['dur'] - fade:.4f}:d={fade:.4f}",
           "-c:a", "pcm_f32le", cut)
    dry = os.path.join(TMP, f"{s['name']}_dry.wav")
    if s["gate_db"] is not None:
        # 立ち上がりの前の素材の雑音を落とす（鳴らした瞬間に音が出ないと、出来事と音がずれて聞こえる）
        _, peak = measure(cut)
        ffmpeg("-i", cut, "-af",
               f"silenceremove=start_periods=1:start_threshold={peak - s['gate_db']:.1f}dB:start_silence=0.004,afade=t=in:d=0.003",
               "-c:a", "pcm_f32le", dry)
    else:
        shutil.copy(cut, dry)
    out = dry
    if s["wet_db"] is not None:
        tail = len(ir) / WET_RATE
        padded = os.path.join(TMP, f"{s['name']}_pad.wav")
        raw_wet = os.path.join(TMP, f"{s['name']}_wetraw.wav")
        wet = os.path.join(TMP, f"{s['name']}_wet.wav")
        ffmpeg("-i", dry, "-af", f"apad=pad_dur={tail:.3f}", "-c:a", "pcm_f32le", padded)
        encode(convolve(decode(dry, WET_RATE), ir), WET_RATE, raw_wet)
        ffmpeg("-i", raw_wet, "-af", f"lowpass=f={IR_LOWPASS}", "-c:a", "pcm_f32le", wet)
        dry_rms, _ = measure(dry)
        wet_rms, _ = measure(wet)
        wet_gain = 10 ** ((dry_rms + s["wet_db"] - wet_rms) / 20)
        out = os.path.join(TMP, f"{s['name']}_mix.wav")
        ffmpeg("-i", padded, "-i", wet, "-filter_complex",
               f"[1:a]volume={wet_gain:.6f}[w];[0:a][w]amix=inputs=2:normalize=0:duration=longest,"
               "silenceremove=stop_periods=-1:stop_threshold=-70dB:stop_duration=0.2",
               "-c:a", "pcm_f32le", out)
    if s["max_len"] is not None:
        capped = os.path.join(TMP, f"{s['name']}_cap.wav")
        ffmpeg("-i", out, "-af", f"atrim=end={s['max_len']:.3f},afade=t=out:st={s['max_len'] - 0.12:.3f}:d=0.12",
               "-c:a", "pcm_f32le", capped)
        out = capped
    _, peak = measure(out)
    gain(out, os.path.join(OUT, f"{s['name']}.wav"), PEAK_DB + s["gain_db"] - peak)
    return s["name"]


def build_loop(lp):
    n = int(round(lp["length"] * RATE))
    x = int(round(lp["xfade"] * RATE))
    parts = cut_layers(lp["name"], lp["layers"], (n + x) / RATE, 2)
    seg = os.path.join(TMP, f"{lp['name']}_seg.wav")
    ins = sum((["-i", p] for p in parts), [])
    ffmpeg(*ins, "-filter_complex",
           f"{''.join(f'[{i}:a]' for i in range(len(parts)))}amix=inputs={len(parts)}:normalize=0:duration=shortest,"
           f"atrim=end_sample={n + x}",
           "-c:a", "pcm_f32le", seg)
    looped = os.path.join(TMP, f"{lp['name']}_loop.wav")
    ffmpeg("-i", seg, "-filter_complex",
           f"[0:a]asplit=3[a][b][c];"
           f"[a]atrim=end_sample={x},asetpts=PTS-STARTPTS,afade=t=in:ss=0:ns={x}:curve=qsin[h];"
           f"[b]atrim=start_sample={n}:end_sample={n + x},asetpts=PTS-STARTPTS,afade=t=out:ss=0:ns={x}:curve=qsin[t];"
           f"[h][t]amix=inputs=2:normalize=0[j];"
           f"[c]atrim=start_sample={x}:end_sample={n},asetpts=PTS-STARTPTS[m];"
           f"[j][m]concat=n=2:v=0:a=1",
           "-c:a", "pcm_f32le", looped)
    rms, peak = measure(looped)
    db = min(lp["rms_db"] - rms, PEAK_DB - peak)
    dst = os.path.join(OUT, f"{lp['name']}.wav")
    gain(looped, dst, db)
    add_loop_points(dst)
    return lp["name"]


def add_loop_points(path):
    """WAV の後ろに smpl チャンク（全体を回るループ 1 本）を足す。"""
    data = bytearray(open(path, "rb").read())
    channels = struct.unpack_from("<H", data, 22)[0]
    frames = None
    pos = 12
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        if cid == b"data":
            frames = size // (2 * channels)
        pos += 8 + size + (size & 1)
    smpl = struct.pack("<9I", 0, 0, 1000000000 // RATE, 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
    data += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    struct.pack_into("<I", data, 4, len(data) - 8)
    open(path, "wb").write(bytes(data))


def load_sources():
    rows = []
    with open(os.path.join(SRC, "sources.tsv"), encoding="utf-8") as f:
        for line in f:
            fid, key, fname, url, author, lic, title = line.rstrip("\n").split("\t")
            rows.append({"id": fid, "key": key, "file": fname, "url": url, "author": author, "license": lic, "title": title})
    return rows


def uses_of(key):
    out = []
    for s in SHOTS:
        for ly in s["layers"]:
            if ly["src"] == key:
                out.append(f"{s['name']}（{s['use']}・{ly['start']:.2f} 秒目から {s['dur']:.2f} 秒ぶん）")
    for lp in LOOPS:
        for ly in lp["layers"]:
            if ly["src"] == key:
                out.append(f"{lp['name']}（ループ・{lp['use']}・{ly['start']:.1f} 秒目から {lp['length']:.1f} 秒ぶん）")
    if key == IR:
        out.append("通路の響き（インパルス応答。直接音の前を落とし 0.9 秒で切って、響きを付ける一発の音に畳み込む）")
    return out


CREDITS_HEAD = """# 音の素材の出どころ（assets/sfx/src/）

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
"""


def write_credits():
    lines = [CREDITS_HEAD]
    for r in load_sources():
        uses = uses_of(r["key"]) or ["使っていない（候補として落とした予備）"]
        title = r["title"].replace("|", "/")
        lines.append(f"| `{r['file']}` | {r['url']} | {r['author']} | {r['license']} | {title} | {'<br>'.join(uses)} |\n")
    with open(os.path.join(OUT, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write("".join(lines))
    print("[sfx] CREDITS.md を書き直した")


def wav_info(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "stream=duration,channels,sample_rate", "-of", "csv=p=0", path])
    rate, ch, dur = r.stdout.strip().split(",")
    return int(rate), int(ch), float(dur)


def head_silence(path):
    """頭から、ピークより 40 dB 下を超えるまでの秒。"""
    _, peak = measure(path)
    r = run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af",
             f"silencedetect=n={peak - 40:.1f}dB:d=0.001", "-f", "null", "-"])
    m = re.search(r"silence_start: (-?[\d.]+)\n.*?silence_end: ([\d.]+)", r.stderr, re.S)
    if m and float(m.group(1)) <= 0.0005:
        return float(m.group(2))
    return 0.0


def loop_seam(path):
    """ループの継ぎ目（尻の 1 サンプル → 頭の 1 サンプル）の跳びを、全体の隣どうしの差の最大と比べる。"""
    a = array.array("h")
    raw = run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-f", "s16le", "-"], binary=True).stdout
    a.frombytes(raw)
    _, ch, _ = wav_info(path)
    worst = 0.0
    for c in range(ch):
        x = a[c::ch]
        seam = abs(x[0] - x[-1])
        inner = max(abs(x[i + 1] - x[i]) for i in range(0, len(x) - 1, 7))
        worst = max(worst, seam / max(1, inner))
    return worst


def report():
    os.makedirs(DEBUG, exist_ok=True)
    rows = ["name\tch\trate\tsec\tpeak_db\trms_db\thead_s\tseam"]
    loops = {lp["name"] for lp in LOOPS}
    for name in [s["name"] for s in SHOTS] + [lp["name"] for lp in LOOPS]:
        path = os.path.join(OUT, f"{name}.wav")
        rate, ch, dur = wav_info(path)
        rms, peak = measure(path)
        seam = f"{loop_seam(path):.2f}" if name in loops else "-"
        rows.append(f"{name}\t{ch}\t{rate}\t{dur:.3f}\t{peak:.2f}\t{rms:.2f}\t{head_silence(path):.3f}\t{seam}")
    with open(os.path.join(DEBUG, "report.tsv"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    print("\n".join(rows))


def main():
    if shutil.which("ffmpeg") is None:
        sys.exit("[sfx] ffmpeg が見つからない")
    if "--credits" in sys.argv:
        write_credits()
        return
    if "--report" in sys.argv:
        report()
        return
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    ir = prepare_ir()
    names = []
    for s in SHOTS:
        if not only or s["name"] in only:
            names.append(build_shot(s, ir))
    for lp in LOOPS:
        if not only or lp["name"] in only:
            names.append(build_loop(lp))
    print(f"[sfx] {len(names)} 本 → assets/sfx/")


if __name__ == "__main__":
    main()
