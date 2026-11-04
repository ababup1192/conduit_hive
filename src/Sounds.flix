// Sounds — このコマに起きた事（遊んでいる場面の World.eventsOf と、画面をまたぐ World.screenEventsOf）を鳴らす音の名前へ写す（純粋）。
// 音は project.json の sounds に載せた名前で鳴る。今の音は全部 engine の合成の仮の音（art/sfx.snd.star）で、撃った音は武器ごとの名前に
// 同じ wav を載せてある。敵・被弾の音と Freesound の素材は段 5 で、ここに行を足す。
// 鳴り続ける音（段 5 の環境音・App.withSustained）は、volume に sustainedScale を掛ける（ポーズ・終了の確認・タイトルとクリアの間は 0）。
mod Sounds {
    use Events.Event

    /// 起きた事 1 つの音（まだ音の無い事は None）。
    def soundOf(e: Event): Option[String] = match e {
        case Event.Fired(w)    => Some("shot_${WeaponsDoc.keyOf(w)}")
        case Event.PickedUp(_) => Some("pickup")
        case Event.Switched(_) => Some("switch")
        case Event.DryFire(_)  => Some("dryfire")
        case Event.Cleared     => Some("clear")
        case Event.Started     => Some("ui_choose")
        case Event.Paused      => Some("ui_choose")
        case Event.Resumed     => Some("ui_choose")
        case Event.MenuChosen  => Some("ui_choose")
        case Event.ToTitle     => Some("ui_choose")
        case Event.MenuMoved   => Some("ui_move")
        case _                 => None
    }

    /// このコマに鳴らす音（同じ名前は 1 回）。
    pub def events(after: World.World): List[String] =
        let play = World.sessionOf(after) |> Option.toList |> List.flatMap(World.eventsOf);
        List.append(World.screenEventsOf(after), play) |> List.filterMap(soundOf) |> List.distinct

    /// 鳴り続ける音の音量に掛ける倍率: 遊んでいて、ポーズも終了の確認もしていない間だけ 1（ほかは 0）。
    pub def sustainedScale(w: World.World): Float64 =
        if (Option.isEmpty(World.sessionOf(w)) or World.isPaused(w) or World.isAskingQuit(w)) 0.0 else 1.0
}
