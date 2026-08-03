// Dungeon Solitaire - ally OnConversation opener.
// Opens the ally's attack picker (ds_attack, via DialogResRef) ONLY when a real
// player clicks/uses the ally. Card creatures constantly overhear the game's
// narrator placeable (SpeakString); gating on GetIsPC(GetLastSpeaker()) makes sure
// the picker never pops on its own from that overheard speech.
void main()
{
    if (GetIsPC(GetLastSpeaker()) && GetCommandable())
    {
        ClearAllActions();
        BeginConversation();   // opens OBJECT_SELF's DialogResRef = ds_attack
    }
}
