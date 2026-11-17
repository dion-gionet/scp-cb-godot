# Runs the playtest bot in the background: the window is created off-screen, non-focusing,
# not always-on-top, with audio muted and the mouse never captured.
#   .\tests\run_bot.ps1 [-Godot path\to\godot.exe] [-Seed 12345] [-Only controller] [-Shots] [-Visible]
# A temporary override.cfg applies the window settings for this run only and is removed
# afterwards. Results: tests/bot_report.txt (and tests/shots with -Shots).
param(
	[string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }),
	[string]$Seed = "",
	[string]$Only = "",
	[switch]$Shots,
	[switch]$Visible,
	[switch]$NoBot   # run the plain game (menu screenshots etc.) instead of the bot
	,[switch]$Intro   # play the real intro (SCP_INTRO=1) instead of starting in the breach
)
$project = [System.IO.Path]::GetFullPath("$PSScriptRoot\..")
$override = Join-Path $project "override.cfg"
if ($Visible) {
	$lines = "[display]`nwindow/size/no_focus=true"
} else {
	$lines = "[display]`nwindow/size/no_focus=true`nwindow/size/always_on_top=false`nwindow/size/initial_position_type=0`nwindow/size/initial_position=Vector2i(-30000, -30000)"
}
Set-Content -Path $override -Value $lines
try {
	if (-not $NoBot) { $env:SCP_BOT = "1" }
	if ($Seed) { $env:SCP_SEED = $Seed }
	if ($Only) { $env:SCP_BOT_ONLY = $Only }
	if ($Shots) { $env:SCP_SHOT = "1" }
	if ($Intro) { $env:SCP_INTRO = "1" }
	Set-Location $project
	if ($Shots) { & $Godot --path $project | Out-Host } else { & $Godot --headless --path $project | Out-Host }
	exit $LASTEXITCODE
} finally {
	Remove-Item $override -ErrorAction SilentlyContinue
	Remove-Item Env:SCP_BOT, Env:SCP_SEED, Env:SCP_BOT_ONLY, Env:SCP_SHOT, Env:SCP_INTRO -ErrorAction SilentlyContinue
}
