// StageModel — Blender で組んだステージの絵（assets/models/stage.glb と区画ごとの lightmap）の読み込みと、区画ごとの置いた物（読み込みのほかは純粋）。
//
// glb の中身（modeling/stage.py が書く）: 区画ごとのノード ZONE_<文字>（原点のまま・座標は Maze と同じ）と、作った時の迷路のハッシュの empty DOCHASH_<16 桁>。
// 区画の材質は 3 つ: M_hull（壁・床・天井・パイプ。trim sheet の絵 × lightmap）・M_strip（シアンの光る筋）・M_lamp（灯具）。
// lightmap の PNG と UV の島の間は stage.manifest.json の zones。PNG は線形の光の 1/4 を sRGB で書いてあり、弱い環境光も入っている。
// ベイクに入れた光（天井と壁の灯具・光る筋）は、ここでは点光源にしない（二重に照らさない）。
// 迷路の rows と zones が glb を作った時と違えば（docHashOf が DOCHASH と合わない）、絵は古いので Res が灰色の箱の道へ落とす。
mod StageModel {
    use fge::{DocJson, Gltf, ImageData, JsonCodec, LoadProgress, Log, Mat4, Model3d, Num, Scene3d, Texture3d, Vec3}

    /// 区画 1 つの絵: 形と材質の部品・その区画の lightmap・lightmap の UV の島の間（読んだ絵の上の px）。
    pub type alias Zone = { parts = List[Model3d.ModelPart], lightmap = Option[Texture3d.Texture3d], gapPx = Int32 }

    /// 読んだステージ: 区画の文字 → 絵・場面に渡す絵（trim sheet と lightmap と映り込みのパノラマ）・作った時の迷路のハッシュ（DOCHASH の 16 桁）・
    /// 映り込みのパノラマ（名前 → 絵。modeling/render_panorama.py が stage_env/<名前>.png に書く。読めない名前は無い）。
    /// trim = M_hull の trim sheet の絵（金属っぽさと粗さの絵の継ぎ目を読む）。
    pub type alias Stage = { zones = Map[Char, Zone], textures = List[Texture3d.Texture3d], docHash = Option[String], panoramas = Map[String, Texture3d.Texture3d],
                             trim = Option[Texture3d.Texture3d] }

    /// manifest の区画の行: lightmap の PNG（models からの相対）と UV の島の間（px）。
    type alias Entry = { lightmap = Option[String], gapPx = Int32 }

    def modelsDir(): String = "assets/models"

    def glbPath(): String = "${modelsDir()}/stage.glb"

    def manifestPath(): String = "${modelsDir()}/stage.manifest.json"

    def zonePrefix(): String = "ZONE_"

    def hashPrefix(): String = "DOCHASH_"

    /// lightmap を掛ける材質（ほかの材質は自分で光るので、ベイクした光を受けない）。
    def hullMaterial(): String = "M_hull"

    // ── 迷路のハッシュ ──

    /// 迷路の rows と zones だけを決まった形に直した字: rows を 1 行ずつ・続けて zones を Doc の順に「zone <文字> <room|corridor> <天井の高さ cm>」。改行でつなぐ。
    // WhyNot: maze.stage.json のファイル全体のバイトにしない — marks（spawn・pickup）・note・finalZone は絵に関わらず、動かすたびに glb が古いと判定される。
    // WhyNot: 高さを小数の字にしない — Flix と python で小数の書き方がずれる。cm の整数にそろえる（modeling/stagehash.py の stage_key と同じ形）。
    def stageKeyOf(doc: MazeDoc.Doc): String =
        let d = MazeDoc.rec(doc);
        let kindName = (k: MazeDoc.ZoneKind) -> if (k == MazeDoc.ZoneKind.Room) "room" else "corridor";
        let cm = (h: Float64) -> Float64.tryToInt32(Float64.floor(h * 100.0 + 0.5)) |> Option.getWithDefault(0);
        let zoneLines = d#zones |> List.map(z -> "zone ${z#id} ${kindName(z#kind)} ${cm(z#height)}");
        String.intercalate("\n", List.append(d#rows, zoneLines))

    /// 迷路のハッシュ: stageKeyOf を UTF-8 にした SHA-256 の頭 16 桁（小文字の 16 進）。glb の DOCHASH_<16 桁> と比べる。
    pub def docHashOf(doc: MazeDoc.Doc): String =
        String.take(16, Util.Codec.encodeHex(Util.Checksum.sha256(String.toBytes(stageKeyOf(doc)))))

    /// 今の迷路に合うステージ（ハッシュが合わない・DOCHASH の無い glb は 1 行知らせて None）。
    pub def currentFor(doc: MazeDoc.Doc, stage: Stage): Option[Stage] =
        let want = docHashOf(doc);
        match stage#docHash {
            case Some(h) if h == want => Some(stage)
            case Some(h) => Log.warnThen("[stage] ${glbPath()} は迷路の rows・zones と合わない（glb ${h}・今 ${want}）。灰色の箱で描く（modeling/stage.py を流し直す）", None)
            case None    => Log.warnThen("[stage] ${glbPath()} に ${hashPrefix()} のノードが無い。灰色の箱で描く", None)
        }

    // ── 読み込み ──

    /// glb・manifest・lightmap を読む。glb か manifest が読めなければ 1 行知らせて None（灰色の箱で描く）。
    /// 読めない lightmap はその区画だけ lightmap 無しにして 1 行知らせる。
    pub def load(): Option[Stage] \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        LoadProgress.report("reading stage...", 0, 0);
        let loaded = forM (
            text <- Fs.FileRead.read(manifestPath()) |> Result.mapErr(e -> "${manifestPath()}: 読めない（${e}）");
            entries <- entriesOf(text);
            model <- Gltf.loadTexturedUsing(dec, Gltf.noTextureLimits(), glbPath())
        ) yield (entries, model);
        match loaded {
            case Err(why)            => Log.warnThen("[stage] ${why}。灰色の箱で描く", None)
            case Ok((entries, model)) => Some(stageOf(entries, decodeLightmaps(dec, entries), decodePanoramas(dec, Map.keysOf(entries) |> Set.toList), model))
        }

    /// 映り込みのパノラマの名前: 区画の種類ごとの 3 枚（modeling/render_panorama.py の CAPTURES と同じ）と、区画ごとの 1 枚（zonePanoramaName）。
    def panoramaNames(zones: List[Char]): List[String] = "room" :: "hive" :: "corridor" :: (zones |> List.map(zonePanoramaName))

    /// 区画 id のパノラマの名前（render_panorama.py の --zones と同じ）: zone_<文字>・小文字の区画は zone_lc_<文字>。
    // WhyNot: zone_<文字> だけにしない — 大文字と小文字を区別しないファイルの場所（macOS の既定）で、区画 A と a が同じファイルになる。
    def zonePanoramaName(id: Char): String =
        if (Char.isLowerCase(id)) "zone_lc_${id}" else "zone_${id}"

    /// パノラマを読んで解く（並列）。読めない絵は 1 行知らせて無い（その名前を使う区画は映り込み無し・区画ごとの絵が無ければ種類ごとの絵）。
    def decodePanoramas(dec: ImageData.ImageDecoder, zones: List[Char]): Map[String, Texture3d.Texture3d] \ Fs.FileRead + IO + LoadProgress =
        panoramaNames(zones)
            |> LoadProgress.mapWithProgress("reading reflections...", name -> (name, Fs.FileRead.readBytes("${modelsDir()}/stage_env/${name}.png") |> Result.mapErr(err -> "${err}")))
            |> LoadProgress.parMapWithProgress("decoding reflections...", raw -> {
                let (name, bytes) = raw;
                bytes |> Result.flatMap(b -> Texture3d.decodeUsing(dec, b)) |> Result.mapErr(why -> "stage_env/${name}.png: ${why}") |> Result.map(t -> (name, t))
            })
            |> List.filterMap(r -> match r {
                case Ok(pair) => Some(pair)
                case Err(why) => Log.warnThen("[stage] 映り込みのパノラマを読めない（その区画は映り込み無し）: ${why}", None)
            })
            |> List.toMap

    /// manifest の zones の行（区画の文字 → lightmap の PNG と島の間）。
    def entriesOf(text: String): Result[String, Map[Char, Entry]] =
        DocJson.parse(text)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(root -> Map.get("zones", root))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(zones -> Map.toList(zones) |> List.filterMap(e -> {
                let (id, json) = e;
                forM (
                    c <- String.toList(id) |> List.head;
                    o <- JsonCodec.expectObject(json)
                ) yield (c, { lightmap = Map.get("lightmap_png", o) |> Option.flatMap(JsonCodec.expectString), gapPx = JsonCodec.intOr("uv_gap_px", 8, o) })
            }) |> List.toMap)
            |> Option.toOk("${manifestPath()}: zones が無い")

    /// 区画ごとの lightmap の絵を読んで解く（並列）。
    def decodeLightmaps(dec: ImageData.ImageDecoder, entries: Map[Char, Entry]): Map[Char, Texture3d.Texture3d] \ Fs.FileRead + IO + LoadProgress =
        entries |> Map.toList
            |> List.filterMap(e -> snd(e)#lightmap |> Option.map(rel -> (fst(e), "${modelsDir()}/${rel}")))
            |> LoadProgress.mapWithProgress("reading lightmaps...", e -> (e, Fs.FileRead.readBytes(snd(e)) |> Result.mapErr(err -> "${err}")))
            |> LoadProgress.parMapWithProgress("decoding lightmaps...", raw -> {
                let ((id, path), bytes) = raw;
                bytes |> Result.flatMap(b -> Texture3d.decodeUsing(dec, b)) |> Result.mapErr(why -> "${path}: ${why}") |> Result.map(t -> (id, t))
            })
            |> List.filterMap(r -> match r {
                case Ok(pair) => Some(pair)
                case Err(why) => Log.warnThen("[stage] lightmap を読めない（その区画は lightmap 無し）: ${why}", None)
            })
            |> List.toMap

    /// 読んだ glb と lightmap から区画ごとの絵を組む（ZONE_ の付かないノードの部品は置かない）。
    def stageOf(entries: Map[Char, Entry], lightmaps: Map[Char, Texture3d.Texture3d], panoramas: Map[String, Texture3d.Texture3d], model: Model3d.Model3d): Stage =
        let byNode = Model3d.partsByNode(model);
        let zones = model#nodes |> List.zipWithIndex |> List.filterMap(e -> {
            let (index, node) = e;
            String.stripPrefix({ substr = zonePrefix() }, node#name) |> Option.flatMap(rest -> String.toList(rest) |> List.head) |> Option.map(id ->
                (id, { parts = Map.getWithDefault(index, Nil, byNode), lightmap = Map.get(id, lightmaps),
                       gapPx = Map.get(id, entries) |> Option.map(en -> en#gapPx) |> Option.getWithDefault(8) }))
        }) |> List.toMap;
        { zones = zones, textures = List.flatten(model#textures :: Map.valuesOf(lightmaps) :: Map.valuesOf(panoramas) :: Nil), panoramas = panoramas, trim = trimOf(model),
          docHash = Model3d.nodesWithPrefix(hashPrefix(), model) |> List.head |> Option.flatMap(n -> String.stripPrefix({ substr = hashPrefix() }, n#name)) }

    /// 壁・床・天井の材質の trim sheet の絵（glb には床の標示の絵も入っているので、材質の絵の名前で引く）。
    def trimOf(model: Model3d.Model3d): Option[Texture3d.Texture3d] =
        let name = model#parts |> List.filterMap(p -> p#gltfMaterial) |> List.find(g -> g#name == hullMaterial()) |> Option.flatMap(g -> g#baseColorTexture);
        name |> Option.flatMap(n -> model#textures |> List.find(t -> Texture3d.name(t) == n))

    // ── 置く ──

    /// 区画 id の置いた物: M_hull の部品には lightmap と（hullSurface があれば）金属っぽさと粗さの絵を付け、光る筋と灯具はそのまま（glb の emissive の強さで光る）。
    /// intensity = lightmap の倍率（線形。PNG を書いた時の 1/4 を戻す 4.0 が Blender のまま）・hullSurface = hullSurfaceOf の絵の名前。区画の絵が無ければ空。
    pub def instancesOf(look: LookDoc.Rec, hullSurface: Option[String], stage: Stage, id: Char): List[Scene3d.Instance3d] =
        Map.get(id, stage#zones) |> Option.map(zone -> zone#parts |> List.map(part -> {
            let placed = Scene3d.meshInstance(part#mesh, Mat4.identity()) |> Scene3d.withName("stage:${id}");
            let name = part#gltfMaterial |> Option.map(g -> g#name) |> Option.getWithDefault("");
            let material = part#material |> Option.map(surfaced(look, hullSurface, name));
            let shaded = material |> Option.map(m -> Scene3d.withMaterial(m, placed)) |> Option.getWithDefault(placed);
            zone#lightmap |> Option.filter(_ -> List.memberOf(name, lightmappedMaterials()))
                |> Option.map(lm -> Scene3d.withLightmap({ intensity = look#lightmapIntensity, maxLevels = Scene3d.lightmapLevelsForGap(zone#gapPx) | Scene3d.lightmap(Texture3d.name(lm)) }, shaded))
                |> Option.getWithDefault(shaded)
        })) |> Option.getWithDefault(Nil)

    /// 床の標示（塗料・α で抜く）と水たまり（半透明）の材質の名前（modeling/floormarks.py）。どちらも下の床の lightmap を読む。
    def decalMaterial(): String = "M_decal"
    def puddleMaterial(): String = "M_puddle"

    /// lightmap を掛ける材質（ほかの材質は自分で光るので、ベイクした光を受けない）。
    def lightmappedMaterials(): List[String] = hullMaterial() :: decalMaterial() :: puddleMaterial() :: Nil

    /// 材質の名前 name の部品の材質: 壁・床は金属っぽさと粗さの絵・標示は α で抜く塗料・水たまりは粗さの低い半透明。
    // WhyNot: 標示を glb のまま半透明で描かない — Blender は α を使う材質を全部 BLEND で書き出し、半透明は深度を書かないので、水たまりと重なった所で順が入れ替わる。
    def surfaced(look: LookDoc.Rec, hullSurface: Option[String], name: String, m: Scene3d.Material3d): Scene3d.Material3d =
        if (name == hullMaterial()) surfacedHull(hullSurface, m)
        else if (name == decalMaterial()) m |> Scene3d.withAlphaBlend(false) |> Scene3d.withCutout(true) |> Scene3d.withMetallicRoughness(0.0, look#decalRoughness)
        else if (name == puddleMaterial()) m |> Scene3d.withAlphaBlend(true) |> Scene3d.withMetallicRoughness(0.0, look#puddleRoughness)
        else m

    def surfacedHull(hullSurface: Option[String], m: Scene3d.Material3d): Scene3d.Material3d = match hullSurface {
        case Some(t) => Scene3d.withMetallicRoughness(1.0, 1.0, m) |> Scene3d.withMetallicRoughnessTexture(t)
        case None    => m
    }

    // ── 壁・床・天井の金属っぽさと粗さ ──

    /// trim sheet の帯（上の行・下の行。2048 px の絵の上から）と、その帯の金属っぽさと粗さ（look）。modeling/stage.py の STRIPS と同じ並び。
    def hullBands(look: LookDoc.Rec): List[(Int32, Int32, LookDoc.Surface)] =
        (0, 512, look#floorSurface) :: (512, 768, look#ceilingSurface) :: (768, 1280, look#panelSurface) :: (1280, 1504, look#kickSurface)
            :: (1504, 1632, look#trimSurface) :: (1632, 1696, look#pipeSteelSurface) :: (1696, 1760, look#pipePaintSurface)
            :: (1760, 1824, look#pipeGraphiteSurface) :: (1824, 1888, look#hazardSurface) :: (1888, 2048, look#ventSurface) :: Nil

    /// 金属っぽさと粗さの絵の 1 辺（px）。trim sheet（2048 px）の 4 px を 1 px にする。帯の境（16 px の倍数）は px の境に乗る。
    def hullSurfaceSide(): Int32 = 512

    def trimSide(): Int32 = 2048

    /// M_hull の金属っぽさと粗さの絵（B = metallic・G = roughness・512 px 四方）: 帯ごとの値（look）に、trim sheet の暗い所（継ぎ目の溝・格子の穴・羽根の隙間）ほど
    /// 粗く・金属っぽさを下げる差を付ける（look の grooveRoughness・grooveMetal）。look の stagePbr が偽なら None。
    // WhyNot: 帯ごとに材質を分けない — 区画の M_hull は 1 つの形（draw call 1 つ）で、分けるには stage.py で形を切り直し lightmap もベイクし直す。帯の値は絵で分けられる。
    // WhyNot: 絵を Blender で書かない — 帯の値を look で保存即反映に調整したい。継ぎ目の位置は trim sheet の暗さから読めるので、ここで塗れば足りる。
    pub def hullSurfaceOf(look: LookDoc.Rec, stage: Stage): Option[Texture3d.Texture3d] =
        if (not look#stagePbr) None
        else {
            let n = hullSurfaceSide();
            let scale = trimSide() / n;
            let lum = trimLuminance(stage);
            let bands = hullBands(look);
            let bandOf = (py: Int32) -> bands |> List.find(b -> { let (top, bottom, _) = b; py >= top and py < bottom });
            let meanOf = (top: Int32, bottom: Int32) -> {
                let ys = List.range(top / scale, bottom / scale);
                let total = ys |> List.foldLeft((acc, y) -> List.range(0, n / 8) |> List.foldLeft((a2, x) -> a2 + lum(x * 8 * scale, y * scale), acc), 0.0);
                total / Int32.toFloat64(Int32.max(1, List.length(ys) * (n / 8)))
            };
            let means = bands |> List.map(b -> { let (top, bottom, _) = b; (top, meanOf(top, bottom)) }) |> List.toMap;
            let byte = (v: Float64) -> Float64.tryToInt32(Float64.floor(Num.clamp01(v) * 255.0 + 0.5)) |> Option.getWithDefault(0);
            let texel = (x: Int32, y: Int32) -> {
                let py = y * scale + scale / 2;
                let (top, s) = bandOf(py) |> Option.map(b -> { let (t0, _, sf) = b; (t0, sf) }) |> Option.getWithDefault((0, { metallic = 0.0, roughness = 1.0 }));
                let local = (lum(x * scale, y * scale) + lum(x * scale + scale / 2, y * scale + scale / 2)) / 2.0;
                let ratio = local / Float64.max(0.001, Map.getWithDefault(top, 1.0, means));
                let groove = Num.clamp01((0.75 - ratio) / 0.4);
                let rough = s#roughness + groove * look#grooveRoughness;
                let metal = s#metallic * (1.0 - groove * look#grooveMetal);
                Int32.bitwiseOr(Int32.bitwiseOr(Int32.leftShift(255, 24), Int32.leftShift(byte(rough), 8)), byte(metal))
            };
            let pixels = Vector.range(0, n * n) |> Vector.map(i -> texel(Int32.modulo(i, n), i / n));
            Texture3d.fromArgb(n, n, pixels) |> Result.toOption
        }

    /// trim sheet の点 (x, y)（2048 px の絵の上から）の明るさ（0..1・r g b の平均）。絵の画素を持たない時（ブラウザの絵）は全部 1（差を付けない）。
    def trimLuminance(stage: Stage): (Int32, Int32) -> Float64 =
        let argb = stage#trim |> Option.flatMap(t -> match Texture3d.sourceOf(t) {
            case Texture3d.Source.Argb(px) if Texture3d.width(t) == trimSide() and Texture3d.height(t) == trimSide() => Some(px)
            case _ => None
        });
        (x, y) -> argb |> Option.map(px -> {
            let c = Vector.get(Int32.max(0, Int32.min(trimSide() * trimSide() - 1, y * trimSide() + x)), px);
            let ch = (shift: Int32) -> Int32.toFloat64(Int32.bitwiseAnd(Int32.rightShift(c, shift), 255)) / 255.0;
            (ch(16) + ch(8) + ch(0)) / 3.0
        }) |> Option.getWithDefault(1.0)

    // ── 映り込みの景色 ──

    /// パノラマを撮った目の高さ（m。modeling/render_panorama.py の CAPTURES の y）。
    def captureHeight(): Float64 = 1.65

    /// 区画 zone に立った時の映り込みの景色: look の envPerZone なら区画ごとのパノラマ（その区画の箱の真ん中から撮った物）、
    /// 無ければ区画の種類ごとのパノラマ（look の envFinal・envRoom・envCorridor）を look の envIntensity で照らし、
    /// envBox なら区画のマスを囲む箱（床から天井まで・撮った点は箱の真ん中の目の高さ）で景色の位置を合わせる。使わない・絵が無い時は None。
    // WhyNot: 種類ごとの絵の撮った点を区画ごとに持たない — 同じ絵を同じ種類の区画で使い回すので、撮った区画の外では点の値に意味が無い。箱の真ん中で足りる。
    pub def environmentOf(look: LookDoc.Rec, maze: Maze.Maze, stage: Stage, zone: Maze.Zone): Option[Scene3d.EnvironmentMap] =
        let byKind = if (zone#id == maze#finalZone) look#envFinal else if (zone#kind == MazeDoc.ZoneKind.Room) look#envRoom else look#envCorridor;
        let own = Map.get(zonePanoramaName(zone#id), stage#panoramas) |> Option.filter(_ -> look#envPerZone);
        (match own { case Some(t) => Some(t) case None => Map.get(byKind, stage#panoramas) }) |> Option.filter(_ -> look#envMaps) |> Option.map(t -> {
            let env = Scene3d.environmentMap(t) |> Scene3d.withEnvironmentIntensity(look#envIntensity);
            if (look#envBox) Scene3d.withEnvironmentBox(zoneBox(maze, zone), env) else env
        })

    /// 区画のマスを囲む箱（床から天井まで）と、その真ん中の目の高さの点。
    def zoneBox(maze: Maze.Maze, zone: Maze.Zone): Scene3d.EnvironmentBox =
        let corners = zone#cells |> List.map(Maze.cornerOf(maze));
        let xs = corners |> List.map(fst);
        let zs = corners |> List.map(snd);
        let lo = (vs: List[Float64]) -> List.minimum(vs) |> Option.getWithDefault(0.0);
        let hi = (vs: List[Float64]) -> (List.maximum(vs) |> Option.getWithDefault(0.0)) + maze#cellSize;
        let (x0, x1, z0, z1) = (lo(xs), hi(xs), lo(zs), hi(zs));
        let snap = (v: Float64) -> if (zone#kind == MazeDoc.ZoneKind.Room) Float64.floor(v / maze#cellSize) * maze#cellSize else v;
        { min = Vec3.v3(x0, 0.0, z0), max = Vec3.v3(x1, zone#height, z1), center = Vec3.v3(snap((x0 + x1) / 2.0), captureHeight(), snap((z0 + z1) / 2.0)) }
}
