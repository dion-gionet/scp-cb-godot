# Downloads the game files into <project>\assets, where the game and the editor find them (no Python needed).
#   .\tools\fetch_assets.ps1
#   .\tools\fetch_assets.ps1 -Manifest https://example.com/manifest.json
param(
	[string]$Manifest = $(if ($env:SCP_ASSET_MANIFEST) { $env:SCP_ASSET_MANIFEST } else { "https://github.com/dion-gionet/scp-cb-godot/releases/download/assets-v1/manifest.json" }),
	[string]$Dest = (Join-Path (Split-Path -Parent $PSScriptRoot) "assets"),
	[switch]$Force
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"    # Invoke-WebRequest is very slow with its progress bar

$remote = $Manifest -match '://'
$info = if ($remote) { Invoke-RestMethod $Manifest } else { Get-Content $Manifest -Raw | ConvertFrom-Json }
$archive = $info.archive
$stamp = Join-Path $Dest "installed.json"
if (-not $Force -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw | ConvertFrom-Json).sha256 -eq $archive.sha256)) {
	Write-Host "$Dest is up to date (version $($info.version))"
	exit 0
}
$urls = @($archive.urls | Where-Object { $_ })    # @($null) would count as one entry
if ($urls.Count -eq 0) {    # next to the manifest
	if ($remote) { $urls = @(($Manifest -replace '/[^/]*$', '') + "/" + $archive.name) }
	else { $urls = @(Join-Path (Split-Path -Parent (Resolve-Path $Manifest)) $archive.name) }
}

New-Item -ItemType Directory -Force $Dest | Out-Null
$zip = Join-Path $Dest "download.zip.part"
$ok = $false
foreach ($url in $urls) {
	Write-Host "downloading $url"
	try {
		if ($url -match '://') { Invoke-WebRequest $url -OutFile $zip } else { Copy-Item $url $zip -Force }
	} catch { Write-Host "  failed: $_"; continue }
	if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -eq $archive.sha256.ToLower()) { $ok = $true; break }
	Write-Host "  checksum mismatch"
}
if (-not $ok) { Remove-Item $zip -ErrorAction SilentlyContinue; Write-Error "could not download a valid copy"; exit 1 }

Expand-Archive $zip -DestinationPath $Dest -Force
Remove-Item $zip
New-Item -ItemType File -Force (Join-Path $Dest ".gdignore") | Out-Null     # keeps the editor from importing the files
@{ version = $info.version; sha256 = $archive.sha256 } | ConvertTo-Json | Set-Content $stamp
Write-Host "installed $($info.files) files into $Dest"
