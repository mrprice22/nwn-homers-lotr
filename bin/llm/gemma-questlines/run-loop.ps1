<#
  run-loop.ps1 — auto-loop that lets Gemma work a backlog of class questlines.

  For each backlog file it finds the next unchecked quest slot, builds a prompt from the
  shared design brief + the class premise + a running synopsis of prior quests, runs it
  through a local Gemma model via Ollama, appends the result to output/<class>.md,
  records a one-line synopsis for continuity, and ticks the box in the backlog.

  Usage:
    .\run-loop.ps1                      # work every backlog until all quests are done
    .\run-loop.ps1 -Once                # design just ONE quest, then stop (proof run)
    .\run-loop.ps1 -Only fighter        # only the fighter backlog
    .\run-loop.ps1 -Model gemma4:e4b-it-qat   # faster/smaller model
#>
[CmdletBinding()]
param(
  [string]$Model = "gemma4:12b-it-qat",
  [string]$Only  = "",           # backlog name (without .md) to restrict to
  [switch]$Once,                 # do a single quest then stop
  [int]$DelaySeconds = 2         # brief pause between calls
)

$ErrorActionPreference = "Stop"
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$brief    = Get-Content (Join-Path $root "prompts\design-brief.md") -Raw
$backDir  = Join-Path $root "backlog"
$outDir   = Join-Path $root "output"
$synDir   = Join-Path $root "output\.synopsis"
New-Item -ItemType Directory -Force -Path $outDir,$synDir | Out-Null

# make ollama reachable
$env:Path += ";$env:LOCALAPPDATA\Programs\Ollama"

function Get-Tier([int]$idx,[int]$total){
  if($idx -eq $total){ return "Legendary capstone" }
  $f = $idx / $total
  if($f -le 0.25){ "Apprentice" } elseif($f -le 0.5){ "Journeyman" }
  elseif($f -le 0.75){ "Veteran" } else { "Master" }
}

$backlogs = Get-ChildItem $backDir -Filter *.md | Sort-Object Name
if($Only){ $backlogs = $backlogs | Where-Object { $_.BaseName -eq $Only } }

do {
$didOne = $false
foreach($bl in $backlogs){
  $lines   = Get-Content $bl.FullName
  $premise = ($lines | Where-Object { $_ -match '^Premise:' }) -replace '^Premise:\s*',''
  $tone    = ($lines | Where-Object { $_ -match '^Tone:' })    -replace '^Tone:\s*',''
  $ctype   = ($lines | Where-Object { $_ -match '^Type:' })    -replace '^Type:\s*',''
  $className = (($lines | Where-Object { $_ -match '^# ' }) -replace '^#\s*','' -replace ' Questline Backlog','')

  $slots = @()
  foreach($l in $lines){
    if($l -match '^- \[( |x)\] Q(\d+) L(\d+)'){
      $slots += [pscustomobject]@{ Done=($Matches[1] -eq 'x'); Idx=[int]$Matches[2]; Level=[int]$Matches[3]; Raw=$l }
    }
  }
  $total = $slots.Count
  $next  = $slots | Where-Object { -not $_.Done } | Select-Object -First 1
  if(-not $next){ Write-Host "[$($bl.BaseName)] complete." -ForegroundColor DarkGray; continue }

  $tier    = Get-Tier $next.Idx $total
  $outFile = Join-Path $outDir "$($bl.BaseName).md"
  $synFile = Join-Path $synDir "$($bl.BaseName).txt"
  $story   = if(Test-Path $synFile){ (Get-Content $synFile -Raw).Trim() } else { "" }
  if(-not $story){ $story = "None yet - this is the opening quest of the line." }

  $prompt = @"
$brief

CLASS: $className
CLASS TYPE: $ctype
QUESTLINE PREMISE: $premise
TONE: $tone

STORY SO FAR (previously designed quests; do NOT repeat their structure, hooks, locations, foes, or rewards - escalate beyond them):
$story

YOUR TASK: Design quest #$($next.Idx) of $total for the $className, set at character level $($next.Level).
Reward tier: $tier.
Output ONLY the quest in the required OUTPUT FORMAT.
"@

  Write-Host "[$($bl.BaseName)] quest $($next.Idx)/$total  (L$($next.Level), $tier) -> $Model" -ForegroundColor Cyan
  $body = @{ model=$Model; prompt=$prompt; stream=$false; think=$false
             options=@{ temperature=0.8; num_ctx=8192 } } | ConvertTo-Json -Depth 6
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $r = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post `
         -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 900
  # strip any stray ANSI/control sequences just in case
  $respText = ($r.response -replace "\x1b\[[0-9;]*[A-Za-z]","").Trim()

  if([string]::IsNullOrWhiteSpace($respText)){ Write-Warning "empty response; skipping tick"; continue }

  Add-Content $outFile "`n$respText`n`n---`n" -Encoding utf8
  $syn = ($respText -split "`n" | Where-Object { $_ -match '^SYNOPSIS:' } | Select-Object -First 1)
  if(-not $syn){ $syn = "SYNOPSIS: (quest $($next.Idx) at level $($next.Level))" }
  Add-Content $synFile ("Q{0}: {1}" -f $next.Idx, ($syn -replace '^SYNOPSIS:\s*','')) -Encoding utf8

  # tick the box for this exact slot
  $newLines = Get-Content $bl.FullName | ForEach-Object {
    if($_ -eq $next.Raw){ $_ -replace '^- \[ \]','- [x]' } else { $_ }
  }
  Set-Content -Path $bl.FullName -Value $newLines -Encoding utf8

  $didOne = $true
  if($Once){ Write-Host "-Once set; stopping." -ForegroundColor Yellow; return }
  Start-Sleep -Seconds $DelaySeconds
}

} while($didOne)   # keep passing round-robin until every backlog is empty

Write-Host "All backlogs complete." -ForegroundColor Green
