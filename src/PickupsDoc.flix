// PickupsDoc — conduit_hive.pickups.json（拾う物の量と見え方）の宣言ドキュメント層。
// 迷路の Doc の pickup の印は種類の名前だけを持ち、量はここの items（JSON の鍵）が正（名前がここで引けなければ、その印は置かない）。
// 倒れた敵が落とす確率と物もここ。何を拾えるか・満タンの時に拾わない・武器が加わる・どの敵が落とすかの規則はコード（Pickups・Arsenal・Health）。
// 長さは m・時間は秒・角は度。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod PickupsDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // 拾う距離（足元から拾う物の真ん中までの水平の距離）。
        radius = Float64,
        // 物の大きさの倍率（形の元の大きさに掛ける。床の台座は替えない）・床から浮かせる高さ・上下に揺れる幅・1 往復の長さ・回る速さ（度/秒）。
        scale = Float64,
        hover = Float64,
        bob = Float64,
        bobSeconds = Float64,
        spinDegPerSec = Float64,
        // 発光の筋の強さ（線形の倍率）。
        glow = Float64,
        // 弱い点光源の強さ・届く距離・灯す数（目に近い物から。点光源の上限 8 本を食いつぶさない）。
        lightIntensity = Float64,
        lightRange = Float64,
        lights = Int32,
        // 拾った時の知らせを出す長さ。
        noticeSeconds = Float64,
        // 種類の名前 → 量（回復は体力・弾倉と武器は弾の数。JSON の items の amount）。
        amounts = Map[String, Int32],
        // 倒れた敵が物を落とす確率（0〜1）・落とした物が消えるまで（秒）・落ちている物の上限（越えたら古い物から消す）・
        // 落とす物の種類の名前 → 選ばれやすさ（重み）と量（JSON の dropItems）。
        dropChance = Float64,
        dropSeconds = Float64,
        dropLimit = Int32,
        dropItems = Map[String, DropItem]
    }

    /// 落とす物 1 種類: 選ばれやすさ（ほかの種類の重みとの比）・量。
    pub type alias DropItem = { weight = Float64, amount = Int32 }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.pickups.json"

    /// コード側の既定値（assets/conduit_hive.pickups.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, radius = 1.3, scale = 1.4, hover = 0.6, bob = 0.08, bobSeconds = 2.4, spinDegPerSec = 55.0, glow = 2.2,
                  lightIntensity = 0.7, lightRange = 3.5, lights = 2, noticeSeconds = 1.6,
                  amounts = Map#{ "health_small" => 25, "health_large" => 60, "ammo_shotgun" => 8, "ammo_rifle" => 60,
                                  "weapon_shotgun" => 12, "weapon_rifle" => 90 },
                  dropChance = 0.22, dropSeconds = 30.0, dropLimit = 24,
                  dropItems = Map#{ "ammo_rifle" => { weight = 5.0, amount = 20 }, "ammo_shotgun" => { weight = 3.0, amount = 4 },
                                    "health_small" => { weight = 2.0, amount = 15 } } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (k, v) -> JsonCodec.floatOr(k, v, root);
        let amounts = Map.get("items", root) |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(o -> o |> Map.toList |> List.filterMap(e -> {
                let (name, v) = e;
                JsonCodec.expectObject(v) |> Option.flatMap(Map.get("amount")) |> Option.flatMap(JsonCodec.expectInt) |> Option.map(n -> (name, n))
            }) |> List.toMap)
            |> Option.getWithDefault(d#amounts);
        let dropItems = Map.get("dropItems", root) |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(o -> o |> Map.toList |> List.filterMap(e -> {
                let (name, v) = e;
                JsonCodec.expectObject(v) |> Option.map(item -> (name, { weight = JsonCodec.floatOr("weight", 1.0, item), amount = JsonCodec.intOr("amount", 0, item) }))
            }) |> List.toMap)
            |> Option.getWithDefault(d#dropItems);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root), radius = f("radius", d#radius), scale = f("scale", d#scale), hover = f("hover", d#hover),
                  bob = f("bob", d#bob), bobSeconds = f("bobSeconds", d#bobSeconds), spinDegPerSec = f("spinDegPerSec", d#spinDegPerSec),
                  glow = f("glow", d#glow), lightIntensity = f("lightIntensity", d#lightIntensity), lightRange = f("lightRange", d#lightRange),
                  lights = JsonCodec.intOr("lights", d#lights, root), noticeSeconds = f("noticeSeconds", d#noticeSeconds), amounts = amounts,
                  dropChance = f("dropChance", d#dropChance), dropSeconds = f("dropSeconds", d#dropSeconds),
                  dropLimit = JsonCodec.intOr("dropLimit", d#dropLimit, root), dropItems = dropItems })
}
