// Sounds — 前後の World から鳴らす音の名前を導く（純粋）。音は project.json の sounds に載せた名前で鳴る。
// 撃った音は今は全部の武器で 1 つの仮の音（engine の合成。art/sfx.snd.star）。武器ごとの音と Freesound の素材は後の段。
mod Sounds {
    /// 撃った音の名前。
    def shot(): String = "shot"

    /// このコマに鳴らす音: 撃った回数が増えていれば撃った音を 1 回。
    pub def events(before: World.World, after: World.World): List[String] =
        if (World.arsenalOf(after)#shots > World.arsenalOf(before)#shots) shot() :: Nil else Nil
}
