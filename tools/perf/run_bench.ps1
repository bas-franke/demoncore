# Runs the SINBOUND perf bench (windowed) under the shared .godot lock.
#   powershell -File tools/perf/run_bench.ps1 -Label run2 [-Extra "--bench-short"]
# Results: tools/perf/results/bench_<label>_<stamp>.csv / _summary.txt ; console log next to them.
param([string]$Label = "run", [string]$Extra = "", [int]$TimeoutSec = 300)
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root
$godot = "C:\Users\buunn\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$log = Join-Path $root "tools\perf\results\console_$Label.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
$gargs = @('--path', '.', 'res://tools/perf/bench.tscn', '--', '--autopilot', '--demon=lilaeth', "--bench-label=$Label")
if ($Extra) { $gargs += $Extra.Split(' ') }
while (-not (New-Item -ItemType File ".godot_lock" -ErrorAction SilentlyContinue)) { Start-Sleep 5 }
try {
	$p = Start-Process -FilePath $godot -ArgumentList $gargs -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
	if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); Write-Output "KILLED (timeout)" }
} finally { Remove-Item ".godot_lock" -ErrorAction SilentlyContinue }
Get-Content $log | Select-String -Pattern "^\[bench\]|^   (avg|GPU)"
$errs = (Get-Content "$log.err" | Select-String -Pattern "^(SCRIPT )?ERROR").Count
Write-Output "errors in log: $errs"

