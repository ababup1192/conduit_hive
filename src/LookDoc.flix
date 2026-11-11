// LookDoc — conduit_hive.look.json（施設の色と光・霧・画面の仕上げ）の宣言ドキュメント層。
// ベイクしたステージの使い方と明るさ・灰色の箱の面の色・光る筋・部屋の灯り・環境光・霧・トーンマップ・ブルーム・ビネット・粒の数だけを持つ。
// 面の組み方は MazeMesh・後処理の Pass の並べ方と式は PostView（コード）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod LookDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // Blender でベイクしたステージ（stage.glb）で描くか（偽なら灰色の箱。glb が迷路と合わない時も灰色の箱）と、lightmap の倍率（線形）。
        // PNG は線形の光の 1/4 を書いてあるので、4.0 が Blender で見たままの明るさ。
        bakedStage = Bool,
        lightmapIntensity = Float64,
        // 面の色: 壁（くすんだ鋼）・床（黒鉛）・天井。
        wallColor = Color,
        floorColor = Color,
        ceilingColor = Color,
        // 施設の光る筋（冷たいシアン）と、その明るさの線形の倍率（ブルームの効き）。
        stripColor = Color,
        stripIntensity = Float64,
        // 天井の灯り: 部屋の灯りの色・部屋と通路の強さ・灯具の間隔（マス）・届く距離の灯具の間隔に対する割合。
        roomLightColor = Color,
        roomLightIntensity = Float64,
        corridorLightIntensity = Float64,
        lampSpacing = Int32,
        roomLightReach = Float64,
        // どこにでも当たる光・上を向く面ほど明るくする量。lightmap の付いた物（ベイクしたステージ）には足されないので、
        // ベイクしたステージでは敵・拾う物・的の柱（と、倍率を掛けて手前の腕と銃）だけを照らす。
        ambient = Color,
        hemisphere = Float64,
        // 距離の霧（色・かかり始め・かかり切る距離 m）。かかり切る距離はカメラの写す奥行きの端と見える区画の距離も兼ねる。
        fogColor = Color,
        fogNear = Float64,
        fogFar = Float64,
        // トーンマップ: 露出（stop の数。1 増やすと 2 倍明るく）と白の点。
        exposure = Float64,
        whitePoint = Float64,
        // ブルーム: しきい（HDR の明るさ）・幅・強さ・ぼかしの半径・標本の数・Pass の倍率。
        bloomThreshold = Float64,
        bloomKnee = Float64,
        bloomStrength = Float64,
        bloomRadius = Float64,
        bloomTaps = Int32,
        bloomScale = Float64,
        // 場面の Pass の 1 画素の標本の数（MSAA。1 で掛けない）。
        msaaSamples = Int32,
        // 画面の仕上げ: ビネット・フィルムの粒。
        vignette = Float64,
        grain = Float64,
        // 映り込みの景色（環境マップ。金属っぽさと粗さを持つ材質だけが読む）: 使うか・明るさの線形の倍率（パノラマは線形の半分で書いてあるので 2.0 が Blender のまま）・
        // 区画を囲む箱で景色の位置を合わせるか（偽なら無限に遠い景色）・区画の種類ごとのパノラマの名前（assets/models/stage_env/<名前>.png。
        // 最後の部屋・ほかの部屋・通路。読めない名前の区画は映り込み無し）。
        envMaps = Bool,
        // 区画ごとのパノラマ（stage_env/zone_<文字の 16 進>.png。render_panorama.py --zones）を使うか（偽か絵が無い区画は種類ごとのパノラマ）。
        envPerZone = Bool,
        envIntensity = Float64,
        // ほかの区画との境目の手前で映り込みを弱め始める距離（m。境目で 0。区画をまたいで景色の絵を替える瞬間を見せない。0 で弱めない）。
        envFade = Float64,
        envBox = Bool,
        envFinal = String,
        envRoom = String,
        envCorridor = String,
        // ベイクしたステージの壁・床・天井・パイプ（M_hull）の金属っぽさと粗さを付けるか（偽で拡散の光だけ）と、trim sheet の帯ごとの値。
        // floor = 床の板と格子・ceiling = 天井・panel = 壁の板・kick = 腰板と目地・trim = 暗い金物（面取り・柱・梁・扉の枠・フランジ・灯具の枠）・
        // pipeSteel・pipePaint・pipeGraphite = パイプ 3 種・hazard = 警告の縞・vent = 換気の羽根。
        stagePbr = Bool,
        floorSurface = Surface,
        ceilingSurface = Surface,
        panelSurface = Surface,
        kickSurface = Surface,
        trimSurface = Surface,
        pipeSteelSurface = Surface,
        pipePaintSurface = Surface,
        pipeGraphiteSurface = Surface,
        hazardSurface = Surface,
        ventSurface = Surface,
        // trim sheet の暗い所（継ぎ目の溝・格子の穴・羽根の隙間）に足す粗さと、金属っぽさを下げる割合（0..1。いちばん暗い所でこの割合だけ下げる）。
        grooveRoughness = Float64,
        grooveMetal = Float64,
        // 敵の体の金属っぽさと粗さを付けるか（濡れた肌の照り。偽で拡散の光だけ）と、その値。
        creaturePbr = Bool,
        creatureSurface = Surface,
        // 区画ごとの天井の灯り（区画の文字 → 色・強さの倍率）。色と強さは modeling/stage.py のベイクに入り、ゲームでは手前の腕と銃に写す灯具の色と強さに使う。
        // 書いていない区画は roomLightColor と 1。色の光は区画を染めず、下の fixtures の物から出す。
        zoneLights = Map[Char, ZoneLight],
        // 色の光を出す物（非常口の灯り・回転灯・制御盤・薬品のタンク・消火栓・明滅する蛍光灯）の置き場所と色。
        // 物の形と動かない光は stage.py がベイクに入れ（変えたら stage.py と render_panorama.py を流し直す）、回転灯と蛍光灯の光はゲームが毎コマ足す。
        fixtures = List[Fixture],
        // 回転灯と明滅する蛍光灯の毎コマの光。
        beacon = BeaconLight,
        flicker = FlickerLight,
        // 床の標示の塗料と水たまりの粗さ（どちらも金属っぽさ 0）。
        decalRoughness = Float64,
        puddleRoughness = Float64
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    /// 区画 1 つの天井の灯り: 色・強さの倍率（1 未満で薄暗い区画）。
    pub type alias ZoneLight = { color = Color, intensity = Float64 }

    /// 色の光を出す物の種類。
    pub enum FixtureKind with Eq, ToString {
        case Exit      // 非常口の扉の上の灯り（扉の上の壁）
        case Beacon    // 警告の回転灯（壁の腕の先・ゆっくり回る）
        case Panel     // 制御盤・端末（床に立つ箱と画面）
        case Tank      // 薬品のタンク（光る帯の窓）
        case Hydrant   // 消火栓・非常ボタン（小さな灯り）
        case Flicker   // 壊れて明滅する蛍光灯（天井の際）
    }

    /// 物 1 つ: 種類・マス（列 x・行 y）・付ける壁の向き（'n'・'e'・'s'・'w'。非常口は扉の向き）・光の色。
    pub type alias Fixture = { kind = FixtureKind, x = Int32, y = Int32, side = Char, color = Color }

    /// 回転灯: 灯の点光源の強さ・届く距離と、回る 2 本のスポットの速さ（rad/秒）・円錐の角（rad）・強さ・届く距離。色は物の色。
    pub type alias BeaconLight = { intensity = Float64, range = Float64, spin = Float64, beamFov = Float64, beamIntensity = Float64, beamRange = Float64 }

    /// 明滅する蛍光灯: 点光源の強さ・届く距離と、明滅の速さ（1 秒に切り替わる回数）・消えている割合（0..1）。色は物の色。
    pub type alias FlickerLight = { intensity = Float64, range = Float64, rate = Float64, dark = Float64 }

    /// 区画 id の灯り（書いていなければ roomLightColor・強さ 1）。
    pub def zoneLightOf(r: Rec, id: Char): ZoneLight =
        Map.get(id, r#zoneLights) |> Option.getWithDefault({ color = r#roomLightColor, intensity = 1.0 })

    def kindOf(s: String): Option[FixtureKind] = match s {
        case "exit"    => Some(FixtureKind.Exit)
        case "beacon"  => Some(FixtureKind.Beacon)
        case "panel"   => Some(FixtureKind.Panel)
        case "tank"    => Some(FixtureKind.Tank)
        case "hydrant" => Some(FixtureKind.Hydrant)
        case "flicker" => Some(FixtureKind.Flicker)
        case _         => None
    }

    /// fixtures の行（種類の綴りが引けない行・向きが n e s w でない行は置かない）。
    def fixturesOf(fallback: List[Fixture], room: Color, root: Map[String, Json]): List[Fixture] =
        Map.get("fixtures", root) |> Option.flatMap(JsonCodec.decodeList(json -> Some(fixtureOf(room, json))))
            |> Option.map(List.flatMap(Option.toList)) |> Option.getWithDefault(fallback)

    def fixtureOf(room: Color, json: Json): Option[Fixture] =
        forM (
            o <- JsonCodec.expectObject(json);
            kind <- JsonCodec.stringOr("kind", "", o) |> kindOf;
            side <- String.toList(JsonCodec.stringOr("side", "", o)) |> List.head |> Option.filter(c -> List.memberOf(c, 'n' :: 'e' :: 's' :: 'w' :: Nil))
        ) yield { kind = kind, x = JsonCodec.intOr("x", 0, o), y = JsonCodec.intOr("y", 0, o), side = side, color = colorOr(room, "color", o) }

    def beaconOr(fallback: BeaconLight, root: Map[String, Json]): BeaconLight =
        let o = Map.get("beacon", root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty());
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { intensity = f("intensity", fallback#intensity), range = f("range", fallback#range), spin = f("spin", fallback#spin),
          beamFov = f("beamFov", fallback#beamFov), beamIntensity = f("beamIntensity", fallback#beamIntensity), beamRange = f("beamRange", fallback#beamRange) }

    def flickerOr(fallback: FlickerLight, root: Map[String, Json]): FlickerLight =
        let o = Map.get("flicker", root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty());
        let f = (k, d) -> JsonCodec.floatOr(k, d, o);
        { intensity = f("intensity", fallback#intensity), range = f("range", fallback#range), rate = f("rate", fallback#rate), dark = f("dark", fallback#dark) }

    def zoneLightsOf(fallback: Map[Char, ZoneLight], room: Color, root: Map[String, Json]): Map[Char, ZoneLight] =
        match Map.get("zoneLights", root) |> Option.flatMap(JsonCodec.expectObject) {
            case None    => fallback
            case Some(o) => Map.toList(o) |> List.filterMap(e -> {
                let (key, json) = e;
                forM (
                    id <- String.toList(key) |> List.head;
                    z <- JsonCodec.expectObject(json)
                ) yield (id, { color = colorOr(room, "color", z), intensity = JsonCodec.floatOr("intensity", 1.0, z) })
            }) |> List.toMap
        }

    /// 面の金属っぽさ（0 で絶縁体・1 で金属）と粗さ（0 で鏡・1 でざらざら）。engine の Scene3d.withMetallicRoughness に渡す 2 つの値。
    pub type alias Surface = { metallic = Float64, roughness = Float64 }

    /// root の key の { metallic, roughness }（無い欄は fallback の値）。
    pub def surfaceOr(fallback: Surface, key: String, root: Map[String, Json]): Surface =
        match Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) {
            case None    => fallback
            case Some(o) => { metallic = JsonCodec.floatOr("metallic", fallback#metallic, o), roughness = JsonCodec.floatOr("roughness", fallback#roughness, o) }
        }

    pub def path(): String = "assets/conduit_hive.look.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/conduit_hive.look.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, bakedStage = true, lightmapIntensity = 4.0, wallColor = hx("#5b636b"), floorColor = hx("#34383d"), ceilingColor = hx("#24272b"),
                  stripColor = hx("#5fe3f0"), stripIntensity = 6.0,
                  roomLightColor = hx("#cfe6ee"), roomLightIntensity = 2.2, corridorLightIntensity = 1.2, lampSpacing = 4, roomLightReach = 1.6,
                  ambient = hx("#2e3640"), hemisphere = 0.35,
                  fogColor = hx("#0b0e12"), fogNear = 10.0, fogFar = 56.0,
                  exposure = 0.0, whitePoint = 4.0,
                  bloomThreshold = 0.9, bloomKnee = 0.6, bloomStrength = 0.6, bloomRadius = 0.04, bloomTaps = 12, bloomScale = 0.5,
                  msaaSamples = 4, vignette = 0.35, grain = 0.015,
                  envMaps = true, envPerZone = true, envIntensity = 4.0, envFade = 1.6, envBox = true, envFinal = "hive", envRoom = "room", envCorridor = "corridor",
                  stagePbr = true,
                  floorSurface = { metallic = 0.4, roughness = 0.34 }, ceilingSurface = { metallic = 0.1, roughness = 0.8 },
                  panelSurface = { metallic = 0.6, roughness = 0.5 }, kickSurface = { metallic = 0.5, roughness = 0.55 },
                  trimSurface = { metallic = 0.9, roughness = 0.4 }, pipeSteelSurface = { metallic = 1.0, roughness = 0.25 },
                  pipePaintSurface = { metallic = 0.1, roughness = 0.5 }, pipeGraphiteSurface = { metallic = 0.6, roughness = 0.4 },
                  hazardSurface = { metallic = 0.0, roughness = 0.6 }, ventSurface = { metallic = 0.8, roughness = 0.45 },
                  grooveRoughness = 0.35, grooveMetal = 0.6,
                  creaturePbr = false, creatureSurface = { metallic = 0.0, roughness = 0.25 },
                  zoneLights = Map.empty(),
                  fixtures = Nil,
                  beacon = { intensity = 1.5, range = 5.0, spin = 1.6, beamFov = 0.55, beamIntensity = 5.0, beamRange = 12.0 },
                  flicker = { intensity = 2.5, range = 7.0, rate = 9.0, dark = 0.35 },
                  decalRoughness = 0.55, puddleRoughness = 0.05 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        let c = (key, fallback) -> colorOr(fallback, key, root);
        let i = (key, fallback) -> JsonCodec.intOr(key, fallback, root);
        let s = (key, fallback) -> JsonCodec.stringOr(key, fallback, root);
        Doc.Doc({ version = i("version", d#version),
                  bakedStage = JsonCodec.boolOr("bakedStage", d#bakedStage, root), lightmapIntensity = f("lightmapIntensity", d#lightmapIntensity),
                  wallColor = c("wallColor", d#wallColor), floorColor = c("floorColor", d#floorColor), ceilingColor = c("ceilingColor", d#ceilingColor),
                  stripColor = c("stripColor", d#stripColor), stripIntensity = f("stripIntensity", d#stripIntensity),
                  roomLightColor = c("roomLightColor", d#roomLightColor), roomLightIntensity = f("roomLightIntensity", d#roomLightIntensity),
                  corridorLightIntensity = f("corridorLightIntensity", d#corridorLightIntensity), lampSpacing = i("lampSpacing", d#lampSpacing),
                  roomLightReach = f("roomLightReach", d#roomLightReach),
                  ambient = c("ambient", d#ambient), hemisphere = f("hemisphere", d#hemisphere),
                  fogColor = c("fogColor", d#fogColor), fogNear = f("fogNear", d#fogNear), fogFar = f("fogFar", d#fogFar),
                  exposure = f("exposure", d#exposure), whitePoint = f("whitePoint", d#whitePoint),
                  bloomThreshold = f("bloomThreshold", d#bloomThreshold), bloomKnee = f("bloomKnee", d#bloomKnee),
                  bloomStrength = f("bloomStrength", d#bloomStrength), bloomRadius = f("bloomRadius", d#bloomRadius),
                  bloomTaps = i("bloomTaps", d#bloomTaps), bloomScale = f("bloomScale", d#bloomScale),
                  msaaSamples = i("msaaSamples", d#msaaSamples), vignette = f("vignette", d#vignette), grain = f("grain", d#grain),
                  envMaps = JsonCodec.boolOr("envMaps", d#envMaps, root), envPerZone = JsonCodec.boolOr("envPerZone", d#envPerZone, root), envFade = f("envFade", d#envFade), envIntensity = f("envIntensity", d#envIntensity),
                  envBox = JsonCodec.boolOr("envBox", d#envBox, root), envFinal = s("envFinal", d#envFinal), envRoom = s("envRoom", d#envRoom),
                  envCorridor = s("envCorridor", d#envCorridor),
                  stagePbr = JsonCodec.boolOr("stagePbr", d#stagePbr, root),
                  floorSurface = surfaceOr(d#floorSurface, "floorSurface", root), ceilingSurface = surfaceOr(d#ceilingSurface, "ceilingSurface", root),
                  panelSurface = surfaceOr(d#panelSurface, "panelSurface", root), kickSurface = surfaceOr(d#kickSurface, "kickSurface", root),
                  trimSurface = surfaceOr(d#trimSurface, "trimSurface", root), pipeSteelSurface = surfaceOr(d#pipeSteelSurface, "pipeSteelSurface", root),
                  pipePaintSurface = surfaceOr(d#pipePaintSurface, "pipePaintSurface", root),
                  pipeGraphiteSurface = surfaceOr(d#pipeGraphiteSurface, "pipeGraphiteSurface", root),
                  hazardSurface = surfaceOr(d#hazardSurface, "hazardSurface", root), ventSurface = surfaceOr(d#ventSurface, "ventSurface", root),
                  grooveRoughness = f("grooveRoughness", d#grooveRoughness), grooveMetal = f("grooveMetal", d#grooveMetal),
                  creaturePbr = JsonCodec.boolOr("creaturePbr", d#creaturePbr, root), creatureSurface = surfaceOr(d#creatureSurface, "creatureSurface", root),
                  zoneLights = zoneLightsOf(d#zoneLights, c("roomLightColor", d#roomLightColor), root),
                  fixtures = fixturesOf(d#fixtures, c("roomLightColor", d#roomLightColor), root), beacon = beaconOr(d#beacon, root), flicker = flickerOr(d#flicker, root),
                  decalRoughness = f("decalRoughness", d#decalRoughness), puddleRoughness = f("puddleRoughness", d#puddleRoughness) })
}
