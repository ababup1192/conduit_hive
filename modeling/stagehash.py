# ステージの glb が今の maze.stage.json に合っているかのハッシュ（DOCHASH_<16 桁>）。stage.py が書き、stage_check.py が確かめる。
# ゲーム側の同じ計算は src/StageModel.flix の docHashOf（決まった形を変えたら両方を直す・test/TestMaze.flix が同じ値を見る）。
import hashlib, math


def check_shape(d):
    """ゲームの MazeDoc が既定へ落とす形（rows が無い・空・文字列でない行がある・高さが数でない・区画の id が文字列でない）なら止める。
    ゲームはその形を既定の値で読むので、ここで続けると glb とゲームのハッシュが食い違う。"""
    rows = d.get("rows")
    if not isinstance(rows, list) or len(rows) == 0:
        raise ValueError("maze.stage.json: rows が無いか空（ゲームは既定の迷路で読む）")
    bad = [i for i, r in enumerate(rows) if not isinstance(r, str)]
    if bad:
        raise ValueError("maze.stage.json: rows の %s 番目が文字列でない（ゲームは rows を丸ごと既定へ落とす）" % bad)
    if "wallHeight" in d and (isinstance(d["wallHeight"], bool) or not isinstance(d["wallHeight"], (int, float))):
        raise ValueError("maze.stage.json: wallHeight が数でない（ゲームは既定の高さで読む）")
    for z in d.get("zones", []) or []:
        if not isinstance(z, dict):
            continue
        if "id" in z and not isinstance(z["id"], str):
            raise ValueError("maze.stage.json: zones の id %r が文字列でない（ゲームはその行を捨てる）" % (z["id"],))
        h = z.get("height")
        if h is not None and (isinstance(h, bool) or not isinstance(h, (int, float))):
            raise ValueError("maze.stage.json: zones の %r の height %r が数でない（ゲームは wallHeight で読む）" % (z.get("id"), h))


def stage_key(d):
    """rows と zones だけを決まった形に直した字: rows を 1 行ずつ・続けて zones を Doc の順に 'zone <文字> <room|corridor> <天井の高さ cm>'。改行でつなぐ。
    check_shape を通らない Doc では止まる。"""
    check_shape(d)
    # WhyNot: ファイル全体のバイトにしない — marks（spawn・pickup）・note・finalZone は絵に関わらず、動かすたびに glb が古いと判定される。
    # WhyNot: 区画の name を入れない — 名前は manifest に写すだけで形を変えない。高さは cm の整数（Flix と python で小数の書き方がずれない）。
    wall_h = float(d.get("wallHeight", 4.0))
    lines = list(d["rows"])
    for z in d.get("zones", []):
        zid = str(z.get("id", ""))[:1]
        if zid:
            kind = "room" if z.get("kind") == "room" else "corridor"
            lines.append("zone %s %s %d" % (zid, kind, int(math.floor(float(z.get("height", wall_h)) * 100.0 + 0.5))))
    return "\n".join(lines)


def doc_hash(d):
    """stage_key を UTF-8 にした SHA-256 の頭 16 桁（小文字の 16 進）。"""
    return hashlib.sha256(stage_key(d).encode("utf-8")).hexdigest()[:16]


RULE = "SHA-256 of the UTF-8 of stage_key(maze.stage.json) (rows, then 'zone <id> <room|corridor> <height cm>' per zone, joined by newlines), first 16 lowercase hex chars; node name DOCHASH_<hash> (modeling/stagehash.py = src/StageModel.flix docHashOf)"
