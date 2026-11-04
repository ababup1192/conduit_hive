// Sounds — このコマに起きた事（World.eventsOf）を鳴らす音の名前へ写す（純粋）。音は project.json の sounds に載せた名前で鳴る。
// 撃った音は今は全部の武器で 1 つの仮の音（engine の合成。art/sfx.snd.star）。敵・被弾の音と Freesound の素材は段 5 で、ここに行を足す。
mod Sounds {
    use Events.Event

    /// 撃った音の名前。
    def shot(): String = "shot"

    /// 起きた事 1 つの音（まだ音の無い事は None）。
    def soundOf(e: Event): Option[String] = match e {
        case Event.Fired(_) => Some(shot())
        case _              => None
    }

    /// このコマに鳴らす音（同じ名前は 1 回）。
    pub def events(after: World.World): List[String] =
        World.sessionOf(after) |> Option.toList |> List.flatMap(World.eventsOf) |> List.filterMap(soundOf) |> List.distinct
}
