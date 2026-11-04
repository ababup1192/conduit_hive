// GrenadeDoc — conduit_hive.grenade.json（手榴弾の持てる数・投げ方・飛び方・爆発の範囲と傷・光と揺れ）の宣言ドキュメント層。
// 放物線・跳ね・爆発で敵を倒す・自分も傷を受ける規則はコード（Grenades・Horde.blast・World）。拾う量と落とす確率は conduit_hive.pickups.json。
// 爆発の粒（光の玉・輪・煙・破片）は conduit_hive.blastfx.json。
// 長さは m・時間は秒・速さは 1 秒あたり・角度は度。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod GrenadeDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    /// 持てる数の上限と、遊び始めに持っている数。
    pub type alias Carry = { max = Int32, start = Int32 }

    /// 投げ方: 照準の向きへの速さ・上へ足す速さ・次に投げられるまで・回る速さ（度/秒）。
    pub type alias Throw = { speed = Float64, lift = Float64, cooldown = Float64, spin = Float64 }

    /// 飛び方: 下へ引く強さ（m/秒²）・面で跳ねた時に残る、面に向かう速さの割合と面に沿う速さの割合・玉の半径（床に着く高さ）・
    /// 投げてから爆発するまで・glb の大きさの倍率。
    pub type alias Flight = { gravity = Float64, bounce = Float64, friction = Float64, radius = Float64, fuse = Float64, scale = Float64 }

    /// 爆発: 届く半径・真ん中の傷と縁の傷（その間は距離でなめらかにつなぐ）・弾ける半径（この内で倒れた敵は肉片になる）・
    /// 吹っ飛ぶ横の速さ（真ん中。縁で半分）と上への速さ・生き残った敵が押される速さが減る秒・
    /// 自分が傷を受ける半径と真ん中の傷（縁で 0）。
    pub type alias Blast = { radius = Float64, damage = Float64, edgeDamage = Float64, gibRadius = Float64, push = Float64, lift = Float64,
                             pushDecay = Float64, selfRadius = Float64, selfDamage = Float64 }

    /// 爆発の瞬間の点光源（色・強さ・届く距離・長さ）と camera shake の強さ（0..1）。
    pub type alias Light = { color = Color, intensity = Float64, range = Float64, seconds = Float64 }

    pub type alias Rec = { version = Int32, carry = Carry, throwing = Throw, flight = Flight, blast = Blast, light = Light, shake = Float64 }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.grenade.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/conduit_hive.grenade.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, carry = { max = 3, start = 2 },
                  throwing = { speed = 13.0, lift = 3.5, cooldown = 0.9, spin = 540.0 },
                  flight = { gravity = 14.0, bounce = 0.4, friction = 0.65, radius = 0.06, fuse = 2.0, scale = 1.6 },
                  blast = { radius = 6.0, damage = 150.0, edgeDamage = 25.0, gibRadius = 3.0, push = 8.0, lift = 4.5, pushDecay = 0.25,
                            selfRadius = 4.5, selfDamage = 50.0 },
                  light = { color = hx("#ff8a3c"), intensity = 2.6, range = 7.0, seconds = 0.16 }, shake = 0.85 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(key: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    def carryOr(d: Carry, o: Map[String, Json]): Carry =
        { max = JsonCodec.intOr("max", d#max, o), start = JsonCodec.intOr("start", d#start, o) }

    def throwOr(d: Throw, o: Map[String, Json]): Throw =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { speed = f("speed", d#speed), lift = f("lift", d#lift), cooldown = f("cooldown", d#cooldown), spin = f("spin", d#spin) }

    def flightOr(d: Flight, o: Map[String, Json]): Flight =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { gravity = f("gravity", d#gravity), bounce = f("bounce", d#bounce), friction = f("friction", d#friction), radius = f("radius", d#radius),
          fuse = f("fuse", d#fuse), scale = f("scale", d#scale) }

    def blastOr(d: Blast, o: Map[String, Json]): Blast =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { radius = f("radius", d#radius), damage = f("damage", d#damage), edgeDamage = f("edgeDamage", d#edgeDamage), gibRadius = f("gibRadius", d#gibRadius),
          push = f("push", d#push), lift = f("lift", d#lift), pushDecay = f("pushDecay", d#pushDecay),
          selfRadius = f("selfRadius", d#selfRadius), selfDamage = f("selfDamage", d#selfDamage) }

    def lightOr(d: Light, o: Map[String, Json]): Light =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { color = colorOr(d#color, "color", o), intensity = f("intensity", d#intensity), range = f("range", d#range), seconds = f("seconds", d#seconds) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), carry = carryOr(d#carry, objectOf("carry", root)),
                  throwing = throwOr(d#throwing, objectOf("throw", root)), flight = flightOr(d#flight, objectOf("flight", root)),
                  blast = blastOr(d#blast, objectOf("blast", root)), light = lightOr(d#light, objectOf("light", root)),
                  shake = JsonCodec.floatOr("shake", d#shake, root) })
}
