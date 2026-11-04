// EnemiesDoc — conduit_hive.enemies.json（敵の型ごとの体力・速さ・攻撃の距離と時刻・projectile）の宣言ドキュメント層。
// プレイヤーの体力は PlayerDoc。
// 追う・押し合う・当てる規則と当たり判定の形はコード（Horde・FlowField・Creatures）で、ここは調整する数だけ。
// 長さは m・角度は度・時間は秒・速さは 1 秒あたり。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod EnemiesDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// melee（走って寄り、腕を振り下ろす）。
    pub type alias Melee = {
        health = Float64,
        // 走る速さ（walk のクリップの足が滑らない速さに合わせる）。
        speed = Float64,
        // 振り下ろしを始める距離（足元どうし）と、振れない間に寄るのをやめる距離（プレイヤーの体へ押し込まない）。
        attackRange = Float64,
        stopDistance = Float64,
        // 振り下ろしが届く距離（足元からプレイヤーの体の縁まで）と、前の扇の角（全体）。
        reach = Float64,
        arc = Float64,
        // attack のクリップの始まりから当たる時刻。
        hitTime = Float64,
        damage = Float64,
        // 振り終えてから次を振れるまで。
        cooldown = Float64,
        // 飛びかかる突進: 始める距離（足元どうし。attackRange より遠い所から）・速さの倍率・続く長さの上限・体が前へ伸びる割合。
        lungeRange = Float64,
        lungeBoost = Float64,
        lungeSeconds = Float64,
        lungeStretch = Float64
    }

    /// ranged（距離を取って projectile を吐く）。
    pub type alias Ranged = {
        health = Float64,
        speed = Float64,
        // 保つ距離と、吐き始める一番遠い距離。保つ距離 + approachMargin より遠いと寄り、保つ距離 − retreatMargin より近いと下がる。
        keepDistance = Float64,
        approachMargin = Float64,
        retreatMargin = Float64,
        sightRange = Float64,
        // attack のクリップの始まりから吐く時刻。
        hitTime = Float64,
        cooldown = Float64,
        // 吐く前の溜め: 立ち止まって喉を光らせる長さ（この後に attack のクリップを始める）・発光を強める倍率・体が膨らむ割合。
        chargeSeconds = Float64,
        chargeGlow = Float64,
        chargePuff = Float64
    }

    /// 撃たれた時ののけぞり: 武器ごとの押される速さ（m/秒）・近い時に強める距離と倍率（0 m で倍率）・速さが減る長さ（秒）・体が傾く角（度）。
    pub type alias Flinch = { pistol = Float64, shotgun = Float64, rifle = Float64, closeRange = Float64, closeBoost = Float64,
                              decay = Float64, leanDeg = Float64 }

    /// ranged が吐く projectile。limit = 同時に飛ぶ数の上限（越える時は吐かない）。
    pub type alias Projectile = { speed = Float64, damage = Float64, radius = Float64, life = Float64, limit = Int32 }

    pub type alias Rec = {
        version = Int32,
        // 頭に当たった弾の威力の倍率。
        headMultiplier = Float64,
        // よろけてから次によろけられるまで（連射でずっとよろけて一歩も進めない、を防ぐ）。
        staggerCooldown = Float64,
        // 向きを変える速さ（度/秒）。
        turnRate = Float64,
        // 倒れたまま残る長さ・クリップを切り替える時に混ぜる長さ・距離の地図を塗り直す間隔。
        corpseSeconds = Float64,
        blendSeconds = Float64,
        fieldInterval = Float64,
        melee = Melee,
        ranged = Ranged,
        projectile = Projectile,
        flinch = Flinch
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/conduit_hive.enemies.json"

    /// コード側の既定値（assets/conduit_hive.enemies.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, headMultiplier = 2.0, staggerCooldown = 0.8, turnRate = 570.0,
                  corpseSeconds = 4.0, blendSeconds = 0.12, fieldInterval = 0.25,
                  melee = { health = 50.0, speed = 3.0, attackRange = 1.5, stopDistance = 1.2, reach = 1.3, arc = 100.0, hitTime = 0.5, damage = 10.0, cooldown = 0.4,
                            lungeRange = 4.5, lungeBoost = 2.6, lungeSeconds = 0.6, lungeStretch = 0.16 },
                  ranged = { health = 40.0, speed = 1.0, keepDistance = 9.0, approachMargin = 1.0, retreatMargin = 1.5, sightRange = 22.0, hitTime = 0.6, cooldown = 2.0,
                             chargeSeconds = 0.7, chargeGlow = 4.0, chargePuff = 0.08 },
                  projectile = { speed = 9.0, damage = 12.0, radius = 0.18, life = 4.0, limit = 8 },
                  flinch = { pistol = 1.6, shotgun = 3.0, rifle = 1.0, closeRange = 5.0, closeBoost = 2.0, decay = 0.12, leanDeg = 16.0 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(key: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def meleeOr(d: Melee, o: Map[String, Json]): Melee =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { health = f("health", d#health), speed = f("speed", d#speed), attackRange = f("attackRange", d#attackRange),
          stopDistance = f("stopDistance", d#stopDistance), reach = f("reach", d#reach), arc = f("arc", d#arc), hitTime = f("hitTime", d#hitTime), damage = f("damage", d#damage),
          cooldown = f("cooldown", d#cooldown), lungeRange = f("lungeRange", d#lungeRange), lungeBoost = f("lungeBoost", d#lungeBoost),
          lungeSeconds = f("lungeSeconds", d#lungeSeconds), lungeStretch = f("lungeStretch", d#lungeStretch) }

    def rangedOr(d: Ranged, o: Map[String, Json]): Ranged =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { health = f("health", d#health), speed = f("speed", d#speed), keepDistance = f("keepDistance", d#keepDistance),
          approachMargin = f("approachMargin", d#approachMargin), retreatMargin = f("retreatMargin", d#retreatMargin),
          sightRange = f("sightRange", d#sightRange), hitTime = f("hitTime", d#hitTime), cooldown = f("cooldown", d#cooldown),
          chargeSeconds = f("chargeSeconds", d#chargeSeconds), chargeGlow = f("chargeGlow", d#chargeGlow), chargePuff = f("chargePuff", d#chargePuff) }

    def projectileOr(d: Projectile, o: Map[String, Json]): Projectile =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { speed = f("speed", d#speed), damage = f("damage", d#damage), radius = f("radius", d#radius), life = f("life", d#life),
          limit = JsonCodec.intOr("limit", d#limit, o) }

    def flinchOr(d: Flinch, o: Map[String, Json]): Flinch =
        let f = (k, v) -> JsonCodec.floatOr(k, v, o);
        { pistol = f("pistol", d#pistol), shotgun = f("shotgun", d#shotgun), rifle = f("rifle", d#rifle), closeRange = f("closeRange", d#closeRange),
          closeBoost = f("closeBoost", d#closeBoost), decay = f("decay", d#decay), leanDeg = f("leanDeg", d#leanDeg) }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (k, v) -> JsonCodec.floatOr(k, v, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  headMultiplier = f("headMultiplier", d#headMultiplier), staggerCooldown = f("staggerCooldown", d#staggerCooldown),
                  turnRate = f("turnRate", d#turnRate),
                  corpseSeconds = f("corpseSeconds", d#corpseSeconds), blendSeconds = f("blendSeconds", d#blendSeconds),
                  fieldInterval = f("fieldInterval", d#fieldInterval),
                  melee = meleeOr(d#melee, objectOf("melee", root)), ranged = rangedOr(d#ranged, objectOf("ranged", root)),
                  projectile = projectileOr(d#projectile, objectOf("projectile", root)), flinch = flinchOr(d#flinch, objectOf("flinch", root)) })
}
