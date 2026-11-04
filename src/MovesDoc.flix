// MovesDoc — conduit_hive.moves.json（スタミナ・走る・緊急回避・蹴りの数）の宣言ドキュメント層。
// 減る・戻る・跳ぶ・押し返す規則はコード（Stamina・Moves・Horde.kick）で、ここは調整する数だけ。
// 長さは m・角度は度・時間は秒・速さは 1 秒あたり。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod MovesDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// スタミナ: 最大・使わない間に戻る速さ（/秒）・最後に使ってから戻り始めるまで・走って使い切った後に走れるまで戻る量・走る間に減る速さ（/秒）。
    pub type alias Stamina = { max = Float64, regenPerSecond = Float64, regenDelay = Float64, resumeAt = Float64, sprintPerSecond = Float64 }

    /// 緊急回避: 使うスタミナ・跳ぶ長さ（秒）・跳ぶ距離・攻撃が当たらない長さ（i-frame。跳び始めから）・次に跳べるまで（跳び始めから）・
    /// 目が沈む深さ（m）・画角が広がる角（度）。
    pub type alias Dodge = { cost = Float64, seconds = Float64, distance = Float64, iframe = Float64, cooldown = Float64, dip = Float64, fovKick = Float64 }

    /// 蹴り: 使うスタミナ・届く距離（足元から敵の体の縁まで）・前の扇の角の全体（度）・傷・押す速さ（m/秒）と減る秒（その秒ごとに 1/e へ）・
    /// 倒れた敵が飛ぶ速さ（m/秒）・次に蹴れるまで・脚が見えている長さ・camera shake の強さ（0..1）。
    pub type alias Kick = { cost = Float64, range = Float64, arc = Float64, damage = Float64, push = Float64, pushDecay = Float64,
                            fling = Float64, cooldown = Float64, seconds = Float64, shake = Float64 }

    pub type alias Rec = { version = Int32, stamina = Stamina, dodge = Dodge, kick = Kick }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.moves.json"

    /// コード側の既定値（assets/conduit_hive.moves.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  stamina = { max = 100.0, regenPerSecond = 28.0, regenDelay = 0.9, resumeAt = 35.0, sprintPerSecond = 18.0 },
                  dodge = { cost = 34.0, seconds = 0.3, distance = 4.5, iframe = 0.24, cooldown = 0.55, dip = 0.26, fovKick = 9.0 },
                  kick = { cost = 22.0, range = 1.6, arc = 120.0, damage = 18.0, push = 11.0, pushDecay = 0.22, fling = 4.5,
                           cooldown = 0.7, seconds = 0.42, shake = 0.45 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(key: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def staminaOr(d: Stamina, o: Map[String, Json]): Stamina =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { max = f("max", d#max), regenPerSecond = f("regenPerSecond", d#regenPerSecond), regenDelay = f("regenDelay", d#regenDelay),
          resumeAt = f("resumeAt", d#resumeAt), sprintPerSecond = f("sprintPerSecond", d#sprintPerSecond) }

    def dodgeOr(d: Dodge, o: Map[String, Json]): Dodge =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { cost = f("cost", d#cost), seconds = f("seconds", d#seconds), distance = f("distance", d#distance), iframe = f("iframe", d#iframe),
          cooldown = f("cooldown", d#cooldown), dip = f("dip", d#dip), fovKick = f("fovKick", d#fovKick) }

    def kickOr(d: Kick, o: Map[String, Json]): Kick =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { cost = f("cost", d#cost), range = f("range", d#range), arc = f("arc", d#arc), damage = f("damage", d#damage), push = f("push", d#push),
          pushDecay = f("pushDecay", d#pushDecay), fling = f("fling", d#fling), cooldown = f("cooldown", d#cooldown),
          seconds = f("seconds", d#seconds), shake = f("shake", d#shake) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  stamina = staminaOr(d#stamina, objectOf("stamina", root)), dodge = dodgeOr(d#dodge, objectOf("dodge", root)),
                  kick = kickOr(d#kick, objectOf("kick", root)) })
}
