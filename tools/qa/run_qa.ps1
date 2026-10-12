<#
SINBOUND automated QA suite.

  powershell -ExecutionPolicy Bypass -File tools\qa\run_qa.ps1 [-LongSeconds 360] [-ShotTime 30]
                                                              [-SkipLong] [-SkipWindowed] [-SkipImport]

Runs (each Godot invocation takes the shared .godot_lock only for its own duration):
  import            --headless --import
  smoke_checks      --script res://tools/qa/smoke_checks.gd   (load every res, GLB animation sets)
  select_headless   demon select scene, 300 frames
  main_<demon>      main.tscn via tools/qa/probe.gd, autopilot, 45 s game time (fixed 60 fps)
  boss              main.tscn --boss, autopilot, 75 s game time
  long              main.tscn autopilot + --qa-immortal (hp refilled), -LongSeconds game time (default 360)
  shot_select       windowed screenshot of the demon select screen
  shot_<demon>      windowed screenshot at -ShotTime s of game time
  shot_boss         windowed --boss screenshot at 12 s
Output: tools/qa/results/<timestamp>/{logs,shots}, issues.csv, summary.md
#>
param(
    [int]$LongSeconds = 360,
    [int]$ShotTime = 30,
    [switch]$SkipLong,
    [switch]$SkipWindowed,
    [switch]$SkipImport,
    [string[]]$Demons = @('vharok', 'lilaeth', 'morvane', 'skarn', 'ysolde')
)

$ErrorActionPreference = 'Stop'
$Godot = 'C:\Users\buunn\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Lock = Join-Path $Root '.godot_lock'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Out = Join-Path $PSScriptRoot "results\$Stamp"
$LogDir = Join-Path $Out 'logs'
$ShotDir = Join-Path $Out 'shots'
New-Item -ItemType Directory -Force $LogDir, $ShotDir | Out-Null

$Runs = New-Object System.Collections.ArrayList

function Quote([string]$a) { if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }

function Invoke-Godot([string]$Name, [string[]]$GodotArgs, [int]$TimeoutSec) {
    $log = Join-Path $LogDir "$Name.log"
    $errLog = Join-Path $LogDir "$Name.stderr.log"
    $argStr = ((@('--path', $Root) + $GodotArgs) | ForEach-Object { Quote $_ }) -join ' '
    Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $Name) -NoNewline
    while (-not (New-Item -ItemType File $Lock -ErrorAction SilentlyContinue)) { Start-Sleep 5 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $code = $null
    try {
        $p = Start-Process -FilePath $Godot -ArgumentList $argStr -WorkingDirectory $Root -NoNewWindow -PassThru `
            -RedirectStandardOutput $log -RedirectStandardError $errLog
        $null = $p.Handle  # makes ExitCode available after exit
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
            $p.WaitForExit(10000) | Out-Null
        }
        $code = $p.ExitCode
    } finally {
        Remove-Item $Lock -ErrorAction SilentlyContinue
    }
    $sw.Stop()
    # Merge stderr into the main log (Godot prints errors to stderr).
    $text = ''
    if (Test-Path $log) { $text += [IO.File]::ReadAllText($log) }
    if (Test-Path $errLog) {
        $e = [IO.File]::ReadAllText($errLog)
        if ($e.Trim()) { $text += "`n----- stderr -----`n" + $e }
        Remove-Item $errLog
    }
    [IO.File]::WriteAllText($log, "# godot $argStr`n" + $text)
    Write-Host (" exit={0} {1:N0}s{2}" -f $code, $sw.Elapsed.TotalSeconds, $(if ($timedOut) { ' TIMEOUT' } else { '' }))
    [void]$Runs.Add([pscustomobject]@{
        Name = $Name; Exit = $code; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        TimedOut = $timedOut; Log = $log; Text = $text
    })
}

# ---------------------------------------------------------------- runs
if (-not $SkipImport) { Invoke-Godot 'import' @('--headless', '--import') 600 }
Invoke-Godot 'smoke_checks' @('--headless', '--script', 'res://tools/qa/smoke_checks.gd') 300
Invoke-Godot 'select_headless' @('--headless', '--fixed-fps', '60', '--quit-after', '300', 'res://scenes/menu/demon_select.tscn') 120

$probe = @('--headless', '--fixed-fps', '60', '--disable-vsync', '--script', 'res://tools/qa/probe.gd', '--')
foreach ($d in $Demons) {
    Invoke-Godot "main_$d" ($probe + @('--qa-seconds=45', '--qa-interval=15', '--autopilot', "--demon=$d")) 240
}
Invoke-Godot 'boss' ($probe + @('--qa-seconds=75', '--qa-interval=15', '--autopilot', '--boss', '--demon=vharok')) 300
if (-not $SkipLong) {
    Invoke-Godot 'long' ($probe + @("--qa-seconds=$LongSeconds", '--qa-interval=30', '--qa-immortal', '--autopilot', '--demon=skarn')) ([math]::Max(600, $LongSeconds * 3))
}

if (-not $SkipWindowed) {
    $win = @('--fixed-fps', '60', '--disable-vsync', '--resolution', '1280x720')
    Invoke-Godot 'shot_select' ($win + @('--', "--shot=$ShotDir\select.png", '--shot-time=5')) 90
    foreach ($d in $Demons) {
        Invoke-Godot "shot_$d" ($win + @('res://scenes/main.tscn', '--', '--autopilot', "--demon=$d",
                "--shot=$ShotDir\$d.png", "--shot-time=$ShotTime")) ($ShotTime + 120)
    }
    Invoke-Godot 'shot_boss' ($win + @('res://scenes/main.tscn', '--', '--autopilot', '--boss', '--demon=lilaeth',
            "--shot=$ShotDir\boss.png", '--shot-time=12')) 150
}

# ---------------------------------------------------------------- log parsing
$issues = @{}
$crashRe = 'Program crashed|CrashHandlerException|Segmentation fault|signal 11|Dumping the backtrace'
foreach ($r in $Runs) {
    $lines = $r.Text -split "`r?`n"
    $r | Add-Member Crashed ([bool]($r.Text -match $crashRe))
    $r | Add-Member Errors 0
    $r | Add-Member Warnings 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*(USER )?(SCRIPT ERROR|ERROR|WARNING|USER WARNING):\s*(.*)$') {
            $kind = $Matches[2]
            $msg = $Matches[3].Trim()
            $loc = ''
            # Look ahead for "at: func (file:line)" and the first GDScript backtrace frame.
            for ($j = $i + 1; $j -lt [math]::Min($i + 8, $lines.Count); $j++) {
                $n = $lines[$j]
                if ($n -match '^\s*(USER )?(SCRIPT ERROR|ERROR|WARNING):') { break }
                if (-not $loc -and $n -match '^\s+at:\s*(.*)$') { $loc = $Matches[1].Trim() }
                elseif ($n -match '^\s+\[0\]\s*(.*)$') { $loc = ($loc + ' <= ' + $Matches[1].Trim()).Trim(' <=') }
            }
            $isWarn = $kind -like '*WARNING'
            if ($isWarn) { $r.Warnings++ } else { $r.Errors++ }
            $norm = $msg -replace '0x[0-9a-fA-F]+', '0x?' -replace '\b\d{5,}\b', 'N' -replace '@\d+', '@N'
            $key = "$kind|$norm|$loc"
            if (-not $issues.ContainsKey($key)) {
                $issues[$key] = [pscustomobject]@{ Kind = $kind; Message = $msg; Location = $loc; Count = 0; Runs = @{} }
            }
            $issues[$key].Count++
            $issues[$key].Runs[$r.Name] = 1
        }
    }
}
$sorted = $issues.Values | Sort-Object @{ e = { if ($_.Kind -like '*WARNING') { 1 } else { 0 } } }, @{ e = 'Count'; Descending = $true }
$sorted | Select-Object Kind, Count, Message, Location, @{ n = 'Runs'; e = { ($_.Runs.Keys | Sort-Object) -join ' ' } } |
    Export-Csv (Join-Path $Out 'issues.csv') -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------- summary.md
function Esc([string]$s) { ($s -replace '\|', '\|') -replace '`', "'" }
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# SINBOUND QA run $Stamp`n")
[void]$md.AppendLine("Godot: ``$(Split-Path $Godot -Leaf)``  ")
[void]$md.AppendLine("Errors: **$(($Runs | Measure-Object Errors -Sum).Sum)** total, warnings: **$(($Runs | Measure-Object Warnings -Sum).Sum)**, unique issues: **$($issues.Count)**`n")
[void]$md.AppendLine("## Runs`n")
[void]$md.AppendLine('| run | exit | secs | errors | warnings | notes |')
[void]$md.AppendLine('|---|---|---|---|---|---|')
foreach ($r in $Runs) {
    $notes = @()
    if ($r.TimedOut) { $notes += '**TIMEOUT**' }
    if ($r.Crashed) { $notes += '**CRASH**' }
    $end = ($r.Text -split "`r?`n" | Where-Object { $_ -match '^QA_PROBE_(END|FAIL)' } | Select-Object -Last 1)
    if ($end) { $notes += ($end -replace '^QA_PROBE_', '') }
    elseif ($r.Name -like 'main_*' -or $r.Name -in 'boss', 'long') { $notes += '**probe never finished**' }
    $died = ($r.Text -split "`r?`n" | Where-Object { $_ -match '^QA_PROBE_DIED' } | Select-Object -First 1)
    if ($died) { $notes += "player died ($($died -replace '^QA_PROBE_DIED ', '' -replace ' elapsed.*', ''))" }
    $sm = ($r.Text -split "`r?`n" | Where-Object { $_ -match '^QA_SUMMARY' } | Select-Object -Last 1)
    if ($sm) { $notes += $sm }
    [void]$md.AppendLine("| $($r.Name) | $($r.Exit) | $($r.Seconds) | $($r.Errors) | $($r.Warnings) | $(Esc ($notes -join '; ')) |")
}
$smoke = $Runs | Where-Object Name -eq 'smoke_checks'
if ($smoke) {
    $sf = $smoke.Text -split "`r?`n" | Where-Object { $_ -match '^QA_(FAIL|WARN)' }
    [void]$md.AppendLine("`n## Smoke checks (load failures, GLB animations)`n")
    if ($sf) { foreach ($l in $sf) { [void]$md.AppendLine("- $(Esc $l)") } } else { [void]$md.AppendLine('- all resources loaded, all GLB animation sets complete') }
}
[void]$md.AppendLine("`n## Unique errors / warnings (deduplicated)`n")
[void]$md.AppendLine('| kind | count | message | location | runs |')
[void]$md.AppendLine('|---|---|---|---|---|')
foreach ($s in $sorted) {
    $m = $s.Message; if ($m.Length -gt 220) { $m = $m.Substring(0, 220) + '...' }
    [void]$md.AppendLine("| $($s.Kind) | $($s.Count) | $(Esc $m) | $(Esc $s.Location) | $(($s.Runs.Keys | Sort-Object) -join ' ') |")
}
[void]$md.AppendLine("`n## Probe timelines`n")
foreach ($r in $Runs | Where-Object { $_.Text -match 'QA_PROBE' }) {
    [void]$md.AppendLine("### $($r.Name)`n``````")
    $r.Text -split "`r?`n" | Where-Object { $_ -match '^QA_PROBE' } | ForEach-Object { [void]$md.AppendLine($_) }
    [void]$md.AppendLine('```')
}
[void]$md.AppendLine("`n## Screenshots`n")
foreach ($png in Get-ChildItem $ShotDir -Filter *.png -ErrorAction SilentlyContinue) {
    [void]$md.AppendLine("- $($png.BaseName): ![](shots/$($png.Name))")
}
$missing = @('select') + $Demons + @('boss') | Where-Object { -not (Test-Path (Join-Path $ShotDir "$_.png")) }
if (-not $SkipWindowed -and $missing) { [void]$md.AppendLine("`n**Missing screenshots:** $($missing -join ', ')") }
[IO.File]::WriteAllText((Join-Path $Out 'summary.md'), $md.ToString())
Write-Host "QA results: $Out"
