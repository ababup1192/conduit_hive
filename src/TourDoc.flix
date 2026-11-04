// TourDoc — conduit_hive.tour.json（紹介の動画で自動の操縦が歩いて撃つ道筋）の宣言ドキュメント層。
// 道筋は通る点の並び。点へどう歩くか・どの敵へどう向くか・いつ撃つかはコード（Pilot）。
// 体力の下限と弾を足す所は動画の口（`start tour`）の間だけ効き、手で遊ぶ時は効かない（World）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod TourDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json
    use WeaponsDoc.Weapon

    /// 通る点 1 つ: 名前・足元の x・z（m）・着いてから待つ秒・この点へは走るか・
    /// 構える武器（None = 敵との距離で選ぶ）・待つ間に向く向き（度。0 が北・90 が東。None なら歩いて来た向きのまま）・
    /// 待ち終えても狙える敵がいる間は次へ進まないか。
    pub type alias Point = { name = String, x = Float64, z = Float64, wait = Float64, sprint = Bool,
                             weapon = Option[Weapon], lookYaw = Option[Float64], clear = Bool }

    pub type alias Rec = {
        version = Int32,
        // 向きを変える速さの上限（度/秒）・狙いへ寄る速さ（狙いとのずれが何秒で消える勢いか）・向きの速さがなじむ秒（急に回り始めない）。
        turnRate = Float64,
        lookEase = Float64,
        turnSmooth = Float64,
        // 狙う敵の距離の上限（m。melee と ranged）・撃ち始める狙いのずれ（度）・狙う高さ（敵の足元から m）。
        aimRange = Float64,
        rangedAimRange = Float64,
        fireCone = Float64,
        aimHeight = Float64,
        // 散弾銃へ持ち替える距離（m）・持ち替えてから次に替えるまで（秒）。
        shotgunRange = Float64,
        switchHold = Float64,
        // 点に着いたとみなす距離（m）・1 つの点へ向かうのを諦める秒。
        arriveRadius = Float64,
        giveUpSeconds = Float64,
        // 動画の口の間だけ、体力をこれより下げない・弾がこれを切ったら上限まで足す。
        minHealth = Float64,
        minAmmo = Int32,
        points = List[Point]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.tour.json"

    /// コード側の既定値（道筋そのものは JSON が正なので、点は迷路の start の印の近くの 1 つだけ）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, turnRate = 220.0, lookEase = 0.16, turnSmooth = 0.1, aimRange = 14.0, rangedAimRange = 45.0, fireCone = 3.0, aimHeight = 1.15,
                  shotgunRange = 7.0, switchHold = 1.6, arriveRadius = 0.8, giveUpSeconds = 15.0, minHealth = 45.0, minAmmo = 20,
                  points = { name = "start", x = 18.0, z = 22.0, wait = 1.0, sprint = false, weapon = None, lookYaw = None, clear = false } :: Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// JSON の weapon（pistol・shotgun・rifle。auto と知らない名前は None）。
    def weaponOf(key: String): Option[Weapon] = WeaponsDoc.all() |> List.find(w -> WeaponsDoc.keyOf(w) == key)

    def pointOf(obj: Map[String, Json]): Option[Point] =
        let num = key -> Map.get(key, obj) |> Option.flatMap(JsonCodec.expectFloat);
        forM (x <- num("x"); z <- num("z")) yield
            { name = JsonCodec.stringOr("name", "", obj), x = x, z = z, wait = JsonCodec.floatOr("wait", 0.0, obj),
              sprint = JsonCodec.boolOr("run", false, obj), weapon = weaponOf(JsonCodec.stringOr("weapon", "auto", obj)),
              lookYaw = num("lookYaw"), clear = JsonCodec.boolOr("clear", false, obj) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  turnRate = f("turnRate", d#turnRate), lookEase = f("lookEase", d#lookEase), turnSmooth = f("turnSmooth", d#turnSmooth),
                  aimRange = f("aimRange", d#aimRange), rangedAimRange = f("rangedAimRange", d#rangedAimRange),
                  fireCone = f("fireCone", d#fireCone), aimHeight = f("aimHeight", d#aimHeight),
                  shotgunRange = f("shotgunRange", d#shotgunRange), switchHold = f("switchHold", d#switchHold),
                  arriveRadius = f("arriveRadius", d#arriveRadius), giveUpSeconds = f("giveUpSeconds", d#giveUpSeconds),
                  minHealth = f("minHealth", d#minHealth), minAmmo = JsonCodec.intOr("minAmmo", d#minAmmo, root),
                  points = Map.get("points", root)
                      |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
                      |> Option.map(rows -> rows |> List.filterMap(pointOf))
                      |> Option.getWithDefault(d#points) })
}
