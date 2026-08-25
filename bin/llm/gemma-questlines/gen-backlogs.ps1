# Generates one backlog file per class with a unique premise + tone.
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$backDir = Join-Path $root "backlog"
New-Item -ItemType Directory -Force -Path $backDir | Out-Null

$baseLevels = 1,5,10,15,20,25,30,36,42,48,54,60      # 12 quests, L1->60
$presLevels = 1,6,12,18,24,30                         # 6 quests, L1->30

# name = @(Type, Premise, Tone)
$classes = [ordered]@{
  # ---- base classes (12 quests) ----
  "Barbarian" = @("base","Last blood of a broken northern clan, hunting the warlord and dark spirits that scattered your people, to raise the horns again.","Savage grief, wild freedom, the cold North.")
  "Bard"      = @("base","Keeper of the Lost Lays, recovering songs that can wound the Shadow and rekindle courage in a fading age.","Melancholy wonder, memory, hope kindled in the dark.")
  "Cleric"    = @("base","A broken faith's last vessel, restoring desecrated shrines and proving a silent power still answers.","Solemn devotion, doubt tested, sacred wrath.")
  "Druid"     = @("base","Warden of a forest rotting from within, allied with tree-shepherds against a creeping industrial blight.","Ancient green anger, balance, the wild's slow judgement.")
  "Fighter"   = @("base","A nameless sellsword rising through war to command a free company and turn a losing campaign.","Grit, loyalty, the hard arithmetic of war.")
  "Monk"      = @("base","Last student of a hidden mountain order, guarding a discipline the Enemy would corrupt into a weapon.","Stillness, restraint, inner storm.")
  "Paladin"   = @("base","An oath-bound knight tempted by the Enemy's shortcut to victory, forced to choose honor over power.","Shining resolve shadowed by temptation.")
  "Ranger"    = @("base","A grey-cloaked warden of the wilds, thinning the Enemy's scouts and shielding the free folk who never learn your name.","Lonely vigilance, tracks in the snow, quiet mercy.")
  "Rogue"     = @("base","A gutter thief rising in a shadowed city's guild, toward a heist against a corrupt steward hoarding the realm's grain.","Wit, betrayal, honor among thieves.")
  "Sorcerer"  = @("base","Heir to an old and dangerous bloodline whose power wells up unbidden, courting corruption you must master or be mastered by.","Innate wildfire, dread inheritance, control.")
  "Wizard"    = @("base","A scholar chasing forbidden lore to fight the Shadow without falling as the great mage who fell before you.","Cold curiosity, hubris, the price of knowing.")
  # ---- prestige classes (6 quests) ----
  "Arcane-Archer"      = @("prestige","An elven marksman order binds spell to arrow to hunt a shadow that drinks starlight from the wood.","Elvish precision, twilight, fading light.")
  "Assassin"           = @("prestige","A guild of quiet knives serves a cause you half-believe; your marks are corrupt lords and the line between justice and murder.","Cold intimacy, moral weight, the quiet after.")
  "Blackguard"         = @("prestige","A fallen knight embraces the Enemy's gifts - each quest deepens the fall or claws toward a bitter redemption.","Seductive darkness, ruin, ruined pride.")
  "Champion-of-Torm"   = @("prestige","A divine champion sworn to a war-god's justice endures ordeals to unmask a false prophet wearing holy colors.","Iron faith, trial by fire, righteous wrath.")
  "Dwarven-Defender"   = @("prestige","The last shieldbearer of a fallen hold descends to reclaim the deeps from what woke in the dark below.","Stone-stubborn duty, grief, the unbroken line.")
  "Pale-Master"        = @("prestige","A necromantic scholar walks the edge of undeath, trading pieces of humanity for power over death itself.","Clinical dread, cold bargains, the creeping chill.")
  "Red-Dragon-Disciple"= @("prestige","Dragon blood wakes in your veins; ascend to the wyrm's power without becoming the monster the songs warn of.","Rising heat, pride, the beast under the skin.")
  "Shadowdancer"       = @("prestige","A dancer between light and shade owes a debt to a shadow-realm patron and must dance free before the shadow claims you.","Elegant menace, borrowed dark, the price of grace.")
  "Shifter"            = @("prestige","A shapechanger bound to the wild fights a corruption that traps shifters mid-form, hunting its source through beast and bog.","Feral freedom, identity, the fear of losing your face.")
  "Weapon-Master"      = @("prestige","A pilgrimage of the perfect blade: duel the age's legendary masters to earn, at last, a signature technique of your own.","Discipline, respect between rivals, the single cut.")
}

foreach($name in $classes.Keys){
  $type,$premise,$tone = $classes[$name]
  $levels = if($type -eq "base"){ $baseLevels } else { $presLevels }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# $($name.Replace('-',' ')) Questline Backlog")
  [void]$sb.AppendLine("Premise: $premise")
  [void]$sb.AppendLine("Tone: $tone")
  [void]$sb.AppendLine("Type: $type")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("## Quest Slots (leave [ ] = todo, [x] = done)")
  for($i=0; $i -lt $levels.Count; $i++){
    [void]$sb.AppendLine("- [ ] Q$($i+1) L$($levels[$i]):")
  }
  $file = Join-Path $backDir ("{0}.md" -f $name.ToLower())
  Set-Content -Path $file -Value $sb.ToString() -Encoding utf8
}
Write-Host "Generated $($classes.Count) backlog files in $backDir"
