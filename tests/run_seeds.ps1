# Runs the playtest bot headless for several seeds at once (one Godot process per seed) and
# prints a one-line result per seed, then every failing check.
#   .\tests\run_seeds.ps1 [-Seeds 12345,777] [-Only fast|full|name,name] [-Godot path]
# Reports: tests\reports\bot_<seed>.txt
param(
	[string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }),
	[string[]]$Seeds = @("12345,777"),
	[string]$Only = "fast",
	[switch]$FixedFps   # run frames as fast as possible (--fixed-fps 70) instead of in real time
	,[switch]$Intro      # play the real intro (SCP_INTRO=1; use with -Only intro)
)
$project = [System.IO.Path]::GetFullPath("$PSScriptRoot\..")
$reports = Join-Path $project "tests\reports"
New-Item -ItemType Directory -Force $reports | Out-Null
$started = Get-Date
$jobs = @()
foreach ($seed in ($Seeds | ForEach-Object { $_ -split "[,\s]+" } | Where-Object { $_ })) {
	$report = Join-Path $reports "bot_$seed.txt"
	Remove-Item $report -ErrorAction SilentlyContinue
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = $Godot
	$info.Arguments = "--headless --path `"$project`"" + $(if ($FixedFps) { " --fixed-fps 70" } else { "" })
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$info.EnvironmentVariables["SCP_BOT"] = "1"
	$info.EnvironmentVariables["SCP_SEED"] = "$seed"
	$info.EnvironmentVariables["SCP_BOT_ONLY"] = $Only
	if ($Intro) { $info.EnvironmentVariables["SCP_INTRO"] = "1" }
	$info.EnvironmentVariables["SCP_REPORT"] = $report
	$process = [System.Diagnostics.Process]::Start($info)
	# drain output so the child never blocks on a full pipe
	$out = $process.StandardOutput.ReadToEndAsync()
	$err = $process.StandardError.ReadToEndAsync()
	$jobs += [pscustomobject]@{ Seed = $seed; Process = $process; Report = $report; Out = $out; Err = $err }
}
$failed = $false
foreach ($job in $jobs) {
	$job.Process.WaitForExit()
	$elapsed = [int]((Get-Date) - $started).TotalSeconds
	if (Test-Path $job.Report) {
		$lines = Get-Content $job.Report
		$result = ($lines | Where-Object { $_ -like "RESULT*" }) -join ""
		"seed $($job.Seed): $result  (${elapsed}s)"
		$lines | Where-Object { $_ -like "FAIL*" -or $_ -like "-- *" } | ForEach-Object { "    $_" }
		if ($result -notlike "*PASS*") { $failed = $true }
		$engine = @(($job.Out.Result + "`n" + $job.Err.Result) -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|^ERROR:" } | Sort-Object -Unique)
		if ($engine.Count -gt 0) {
			"    engine errors ($($engine.Count) distinct):"
			$engine | Select-Object -First 15 | ForEach-Object { "      $_" }
		}
	} else {
		"seed $($job.Seed): no report written (crash?)"
		$failed = $true
	}
}
exit ([int]$failed)
