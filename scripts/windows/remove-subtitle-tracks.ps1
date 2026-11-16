<#
.SYNOPSIS
    Losslessly removes all or selected soft subtitle tracks from a video file (-c copy).

.DESCRIPTION
    Uses FFmpeg stream copy (-c copy) to strip soft subtitle tracks from <InputPath>
    and save a new file to <OutputPath> without re-encoding video or audio.

    Prerequisite: You must install FFmpeg (including ffmpeg.exe and ffprobe.exe)
    yourself and ensure both commands are available on your system PATH:
      winget install Gyan.FFmpeg
    or download a build from https://ffmpeg.org/download.html .

.PARAMETER InputPath
    Source video file path.

.PARAMETER OutputPath
    Destination video file path (must differ from InputPath).

.PARAMETER All
    Remove all subtitle tracks (default when neither -Index nor -Lang is provided).

.PARAMETER Index
    Comma-separated or array of 0-based subtitle track indices to remove (matching
    INDEX from list-subtitle-tracks.ps1).

.PARAMETER Lang
    Comma-separated or array of ISO 639 language codes to remove (case-insensitive,
    e.g. eng, zho).

.PARAMETER Force
    Overwrite OutputPath if it already exists.

.PARAMETER Help
    Show usage instructions and exit.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutputPath,

    [Alias('a')]
    [switch]$All,

    [Alias('i')]
    [string[]]$Index,

    [Alias('l')]
    [string[]]$Lang,

    [Alias('f')]
    [switch]$Force,

    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Usage {
    @"
Usage:
  .\scripts\windows\remove-subtitle-tracks.ps1 [options] <input-video> <output-video>

Prerequisite:
  FFmpeg (ffmpeg.exe and ffprobe.exe) is NOT bundled. Install it yourself and add
  it to your PATH (for example: winget install Gyan.FFmpeg).

Options:
  -All, -a            Remove all subtitle tracks (default if -Index/-Lang omitted)
  -Index, -i <list>   Remove 0-based subtitle track index(es), e.g. 0 or "0,2"
  -Lang, -l <list>    Remove subtitle track(s) by language tag, e.g. eng or "eng,zho"
  -Force, -f          Overwrite <output-video> if it already exists
  -Help, -h           Show this help message and exit

Examples:
  .\scripts\windows\remove-subtitle-tracks.ps1 .\input.mkv .\output-clean.mkv
  .\scripts\windows\remove-subtitle-tracks.ps1 -Lang zho .\input.mp4 .\output-en.mp4
  .\scripts\windows\remove-subtitle-tracks.ps1 -Index 0 .\input.mkv .\output.mkv
"@ | Write-Host
}

if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InputPath) -or [string]::IsNullOrWhiteSpace($OutputPath)) {
    [Console]::Error.WriteLine('Error: Both <input-video> and <output-video> arguments are required.')
    Show-Usage
    exit 1
}

foreach ($tool in @('ffmpeg', 'ffprobe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        [Console]::Error.WriteLine("Error: $tool was not found in PATH.")
        [Console]::Error.WriteLine('Please install FFmpeg yourself and reopen PowerShell (e.g. winget install Gyan.FFmpeg).')
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: Input file not found: $InputPath")
    exit 1
}

$hasIndex = ($null -ne $Index -and $Index.Count -gt 0)
$hasLang  = ($null -ne $Lang  -and $Lang.Count -gt 0)

if ($All -and ($hasIndex -or $hasLang)) {
    [Console]::Error.WriteLine('Error: Cannot combine -All with -Index or -Lang.')
    exit 1
}

$removeAll = $All -or (-not $hasIndex -and -not $hasLang)

$resolvedInput = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputPath).ProviderPath)
$resolvedOutput = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).ProviderPath, $OutputPath))
if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
}

if ([string]::Equals($resolvedInput, $resolvedOutput, [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine('Error: Output path must differ from input path (refusing to overwrite source file).')
    exit 1
}

if ((Test-Path -LiteralPath $resolvedOutput) -and (-not $Force)) {
    [Console]::Error.WriteLine("Error: Output file already exists: $OutputPath (pass -Force to overwrite).")
    exit 1
}

$outDir = [System.IO.Path]::GetDirectoryName($resolvedOutput)
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$jsonRaw = & ffprobe -v error `
    -select_streams s `
    -show_entries 'stream=index:stream_tags=language' `
    -of json `
    $resolvedInput

if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("Error: ffprobe could not read media container: $InputPath")
    exit 1
}

$parsed = $jsonRaw | ConvertFrom-Json
$streams = @()
if ($null -ne $parsed -and $null -ne $parsed.streams) {
    $streams = @($parsed.streams)
}

if ($streams.Count -eq 0) {
    [Console]::Error.WriteLine("Error: No soft subtitle tracks found in $InputPath.")
    [Console]::Error.WriteLine('Hint: If text is visible on the video frame, it is burned into the pixels (hardcoded) and cannot be stripped with -c copy.')
    exit 1
}

$trackLangs = @()
foreach ($s in $streams) {
    $l = 'und'
    if ($s.PSObject.Properties['tags'] -and $null -ne $s.tags -and $s.tags.PSObject.Properties['language'] -and $s.tags.language) {
        $l = ([string]$s.tags.language).ToLowerInvariant()
    }
    $trackLangs += $l
}

$removeFlags = New-Object bool[] $streams.Count
if ($removeAll) {
    for ($i = 0; $i -lt $streams.Count; $i++) { $removeFlags[$i] = $true }
}

if ($hasIndex) {
    $idxTokens = @($Index | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    foreach ($tok in $idxTokens) {
        $parsedIdx = 0
        if (-not [int]::TryParse($tok, [ref]$parsedIdx) -or $parsedIdx -lt 0 -or $parsedIdx -ge $streams.Count) {
            [Console]::Error.WriteLine(("Error: Subtitle track index '{0}' out of range (valid: 0..{1})." -f $tok, ($streams.Count - 1)))
            exit 1
        }
        $removeFlags[$parsedIdx] = $true
    }
}

if ($hasLang) {
    $langTokens = @($Lang | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })
    foreach ($reqLang in $langTokens) {
        $matched = $false
        for ($i = 0; $i -lt $streams.Count; $i++) {
            if ($trackLangs[$i] -eq $reqLang) {
                $removeFlags[$i] = $true
                $matched = $true
            }
        }
        if (-not $matched) {
            [Console]::Error.WriteLine(("Error: No subtitle track with language '{0}' found in {1} (available: {2})." -f $reqLang, $InputPath, ($trackLangs -join ' ')))
            exit 1
        }
    }
}

$ffArgs = @('-hide_banner', '-loglevel', 'error', '-y', '-i', $resolvedInput, '-map', '0:v?', '-map', '0:a?')
$removedCount = 0
$keptCount = 0

for ($i = 0; $i -lt $streams.Count; $i++) {
    if ($removeFlags[$i]) {
        $removedCount++
    } else {
        $ffArgs += @('-map', "0:s:$i")
        $keptCount++
    }
}

$outExt = [System.IO.Path]::GetExtension($resolvedOutput)
$outStem = [System.IO.Path]::GetFileNameWithoutExtension($resolvedOutput)
if ($keptCount -gt 0 -and @('.mkv', '.mks') -contains $outExt.ToLowerInvariant()) {
    $ffArgs += @('-map', '0:t?')
}

$tmpOut = [System.IO.Path]::Combine($outDir, (".{0}.tmp.{1}{2}" -f $outStem, $PID, $outExt))
$ffArgs += @('-map_metadata', '0', '-map_chapters', '0', '-c', 'copy', $tmpOut)

try {
    & ffmpeg @ffArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg exited with code $LASTEXITCODE"
    }
    Move-Item -LiteralPath $tmpOut -Destination $resolvedOutput -Force
    Write-Output ("Removed {0} subtitle track(s), kept {1} subtitle track(s) -> {2}" -f $removedCount, $keptCount, $OutputPath)
} finally {
    if (Test-Path -LiteralPath $tmpOut) {
        Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
    }
}
