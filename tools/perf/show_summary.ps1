# Condensed view of a bench summary:  powershell -File tools/perf/show_summary.ps1 [-Path <summary.txt>]
param([string]$Path = "")
if (-not $Path) { $Path = (Get-ChildItem (Join-Path $PSScriptRoot "results\bench_*_summary.txt") | Sort-Object LastWriteTime | Select-Object -Last 1).FullName }
Write-Output $Path
foreach ($line in Get-Content $Path) {
	if ($line -match '^(== |   avg|   GPU|SINBOUND|GPU:|CPU:)') { Write-Output $line }
	elseif ($line -match 'process_ms') {
		Write-Output ("   " + ($line -replace '.*(process_ms=\S+\s+physics_ms=\S+\s+physics_steps_per_frame=\S+\s+draw_calls=\S+).*(visible_primitives=\S+).*(shadow_primitives=\S+\s+objects=\S+).*(nodes=\S+).*', '$1 $2 $3 $4'))
	} elseif ($line -match 'scan: (.*)') {
		$j = $matches[1] | ConvertFrom-Json
		Write-Output "   scan: geo=$($j.geometry_visible) shadowcast=$($j.shadow_casters) mats=$($j.unique_materials) shaders=$($j.unique_shaders) inst_uniform_users=$($j.instance_uniform_users) lights=$($j.lights_enabled)(shadowed $($j.lights_shadowed)) cpuParticles=$($j.cpu_particle_systems)/$($j.cpu_particle_amount) gpuParticles=$($j.gpu_particle_systems)/$($j.gpu_particle_amount) multimesh=$($j.multimesh_instances) visrange=$($j.visibility_range_set)"
		Write-Output ("   by category: " + ($j.geometry_by_category | ConvertTo-Json -Compress))
		if ($j.microbench -and $j.microbench.enemies) {
			Write-Output ("   micro: " + ($j.microbench | Select-Object * -ExcludeProperty per_enemy_type | ConvertTo-Json -Compress))
			Write-Output ("   types: " + ($j.microbench.per_enemy_type | ConvertTo-Json -Compress))
		}
	}
}
