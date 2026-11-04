// StageModel — Blender で組んだステージの絵（assets/models/stage.glb と区画ごとの lightmap）の読み込みと、区画ごとの置いた物（読み込みのほかは純粋）。
//
// glb の中身（modeling/stage.py が書く）: 区画ごとのノード ZONE_<文字>（原点のまま・座標は Maze と同じ）と、作った時の迷路のハッシュの empty DOCHASH_<16 桁>。
// 区画の材質は 3 つ: M_hull（壁・床・天井・パイプ。trim sheet の絵 × lightmap）・M_strip（シアンの光る筋）・M_lamp（灯具）。
// lightmap の PNG と UV の島の間は stage.manifest.json の zones。PNG は線形の光の 1/4 を sRGB で書いてあり、弱い環境光も入っている。
// ベイクに入れた光（天井と壁の灯具・光る筋）は、ここでは点光源にしない（二重に照らさない）。
// 迷路の rows と zones が glb を作った時と違えば（docHashOf が DOCHASH と合わない）、絵は古いので Res が灰色の箱の道へ落とす。
mod StageModel {
    use fge::{DocJson, Gltf, ImageData, JsonCodec, LoadProgress, Log, Mat4, Model3d, Scene3d, Texture3d}

    /// 区画 1 つの絵: 形と材質の部品・その区画の lightmap・lightmap の UV の島の間（読んだ絵の上の px）。
    pub type alias Zone = { parts = List[Model3d.ModelPart], lightmap = Option[Texture3d.Texture3d], gapPx = Int32 }

    /// 読んだステージ: 区画の文字 → 絵・場面に渡す絵（trim sheet と lightmap）・作った時の迷路のハッシュ（DOCHASH の 16 桁）。
    pub type alias Stage = { zones = Map[Char, Zone], textures = List[Texture3d.Texture3d], docHash = Option[String] }

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
            case Ok((entries, model)) => Some(stageOf(entries, decodeLightmaps(dec, entries), model))
        }

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
    def stageOf(entries: Map[Char, Entry], lightmaps: Map[Char, Texture3d.Texture3d], model: Model3d.Model3d): Stage =
        let byNode = Model3d.partsByNode(model);
        let zones = model#nodes |> List.zipWithIndex |> List.filterMap(e -> {
            let (index, node) = e;
            String.stripPrefix({ substr = zonePrefix() }, node#name) |> Option.flatMap(rest -> String.toList(rest) |> List.head) |> Option.map(id ->
                (id, { parts = Map.getWithDefault(index, Nil, byNode), lightmap = Map.get(id, lightmaps),
                       gapPx = Map.get(id, entries) |> Option.map(en -> en#gapPx) |> Option.getWithDefault(8) }))
        }) |> List.toMap;
        { zones = zones, textures = List.append(model#textures, Map.valuesOf(lightmaps)),
          docHash = Model3d.nodesWithPrefix(hashPrefix(), model) |> List.head |> Option.flatMap(n -> String.stripPrefix({ substr = hashPrefix() }, n#name)) }

    // ── 置く ──

    /// 区画 id の置いた物: M_hull の部品には lightmap を付け、光る筋と灯具はそのまま（glb の emissive の強さで光る）。
    /// intensity = lightmap の倍率（線形。PNG を書いた時の 1/4 を戻す 4.0 が Blender のまま）。区画の絵が無ければ空。
    pub def instancesOf(intensity: Float64, stage: Stage, id: Char): List[Scene3d.Instance3d] =
        Map.get(id, stage#zones) |> Option.map(zone -> zone#parts |> List.map(part -> {
            let placed = Scene3d.meshInstance(part#mesh, Mat4.identity()) |> Scene3d.withName("stage:${id}");
            let shaded = part#material |> Option.map(m -> Scene3d.withMaterial(m, placed)) |> Option.getWithDefault(placed);
            let isHull = part#gltfMaterial |> Option.exists(g -> g#name == hullMaterial());
            zone#lightmap |> Option.filter(_ -> isHull)
                |> Option.map(lm -> Scene3d.withLightmap({ intensity = intensity, maxLevels = Scene3d.lightmapLevelsForGap(zone#gapPx) | Scene3d.lightmap(Texture3d.name(lm)) }, shaded))
                |> Option.getWithDefault(shaded)
        })) |> Option.getWithDefault(Nil)
}
