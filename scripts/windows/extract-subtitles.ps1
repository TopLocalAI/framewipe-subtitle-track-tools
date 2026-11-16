<#
.SYNOPSIS
    Exports text-based subtitle tracks to .srt / .ass and warns on bitmap subtitles.

.DESCRIPTION
    Extracts text subtitle tracks (SubRip/SRT, ASS/SSA, MP4 mov_text, WebVTT, etc.)
    from <InputPath> into .srt or .ass files. When encountering image/bitmap subtitle
    tracks (such as Blu-ray PGS hdmv_pgs_subtitle or DVD VobSub dvd_subtitle), prints
    a clear message explaining that bitmap subtitles cannot be directly converted to
    plain text without OCR.

    Prerequisite: You must install FFmpeg (including ffmpeg.exe and ffprobe.exe)
    yourself and ensure both commands are available on your system PATH:
      winget install Gyan.FFmpeg
    or download a build from https://ffmpeg.org/download.html .

.PARAMETER InputPath
    Source video file path.

.PARAMETER Output
    Destination .srt/.ass file (when extracting 1 track) or output directory
    (defaults to current directory ".").

.PARAMETER Index
    Comma-separated or array of 0-based subtitle track indices to extract.

.PARAMETER Lang
    Comma-separated or array of ISO 639 language codes to extract (case-insensitive).

.PARAMETER Format
    Output subtitle format: auto (default), srt, or ass.

.PARAMETER Force
    Overwrite existing output .srt/.ass file(s).

.PARAMETER Help
    Show usage instructions and exit.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [Alias('o')]
    [string]$Output = '.',

    [Alias('i')]
    [string[]]$Index,

    [Alias('l')]
    [string[]]$Lang,

    [ValidateSet('auto', 'srt', 'ass', IgnoreCase = $true)]
    [string]$Format = 'auto',

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
  .\scripts\windows\extract-subtitles.ps1 [options] <input-video> [output-file-or-dir]

Prerequisite:
  FFmpeg (ffmpeg.exe and ffprobe.exe) is NOT bundled. Install it yourself and add
  it to your PATH (for example: winget install Gyan.FFmpeg).

Options:
  -Index, -i <list>           Extract 0-based subtitle track index(es), e.g. 0 or "0,1"
  -Lang, -l <list>            Extract subtitle track(s) by language tag, e.g. eng or zho
  -Format <auto|srt|ass>      Target text format (default: auto)
  -Output, -o <path>          Destination .srt/.ass file or output directory (default: .)
  -Force, -f                  Overwrite existing output file(s)
  -Help, -h                   Show this help message and exit

Exit codes:
  0  At least one text subtitle track was exported
  1  Invalid arguments, missing file/tools, or FFmpeg error
  2  Selected subtitle track(s) are bitmap/image-based and cannot be exported as text

Examples:
  .\scripts\windows\extract-subtitles.ps1 .\movie.mkv .\subs
  .\scripts\windows\extract-subtitles.ps1 -Index 0 .\movie.mp4 .\english.srt
  .\scripts\windows\extract-subtitles.ps1 -Lang zho -Format ass .\movie.mkv .\subs
"@ | Write-Host
}

function Get-SubtitleType([string]$Codec) {
    $bitmap = @('hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle', 'xsub')
    $text = @(
        'subrip', 'srt', 'ass', 'ssa', 'mov_text', 'webvtt', 'text', 'ttml',
        'eia_608', 'hdmv_text_subtitle', 'jacosub', 'microdvd', 'mpl2', 'pjs',
        'realtext', 'sami', 'stl', 'subviewer', 'subviewer1', 'vplayer',
        'dvb_teletext', 'arib_caption'
    )
    if ($bitmap -contains $Codec) { return 'bitmap' }
    if ($text -contains $Codec)   { return 'text' }
    return 'unknown'
}

function Get-BitmapDescription([string]$Codec) {
    switch ($Codec) {
        'hdmv_pgs_subtitle' { return 'Blu-ray PGS (hdmv_pgs_subtitle)' }
        'dvd_subtitle'      { return 'DVD VobSub (dvd_subtitle)' }
        'dvb_subtitle'      { return 'DVB Subtitle (dvb_subtitle)' }
        'xsub'              { return 'DivX XSUB (xsub)' }
        default             { return $Codec }
    }
}

if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    [Console]::Error.WriteLine('Error: Missing required <input-video> argument.')
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

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).ProviderPath
$normFormat = $Format.ToLowerInvariant()

$jsonRaw = & ffprobe -v error `
    -select_streams s `
    -show_entries 'stream=index,codec_name:stream_tags=language' `
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
    [Console]::Error.WriteLine('Hint: If subtitles are visible on the video frame, they are burned-in (hardcoded) pixels and cannot be extracted as a subtitle track.')
    exit 1
}

$hasIndex = ($null -ne $Index -and $Index.Count -gt 0)
$hasLang  = ($null -ne $Lang  -and $Lang.Count -gt 0)

$trackLangs = @()
$trackCodecs = @()
$globalIdxs = @()
foreach ($s in $streams) {
    $globalIdxs += $s.index
    $c = if ($s.PSObject.Properties['codec_name'] -and $s.codec_name) { ([string]$s.codec_name).ToLowerInvariant() } else { 'unknown' }
    $l = 'und'
    if ($s.PSObject.Properties['tags'] -and $null -ne $s.tags -and $s.tags.PSObject.Properties['language'] -and $s.tags.language) {
        $l = ([string]$s.tags.language).ToLowerInvariant()
    }
    $trackCodecs += $c
    $trackLangs  += $l
}

$selected = New-Object bool[] $streams.Count
if (-not $hasIndex -and -not $hasLang) {
    for ($i = 0; $i -lt $streams.Count; $i++) { $selected[$i] = $true }
}

if ($hasIndex) {
    $idxTokens = @($Index | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    foreach ($tok in $idxTokens) {
        $parsedIdx = 0
        if (-not [int]::TryParse($tok, [ref]$parsedIdx) -or $parsedIdx -lt 0 -or $parsedIdx -ge $streams.Count) {
            [Console]::Error.WriteLine(("Error: Subtitle track index '{0}' out of range (valid: 0..{1})." -f $tok, ($streams.Count - 1)))
            exit 1
        }
        $selected[$parsedIdx] = $true
    }
}

if ($hasLang) {
    $langTokens = @($Lang | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })
    foreach ($reqLang in $langTokens) {
        $matched = $false
        for ($i = 0; $i -lt $streams.Count; $i++) {
            if ($trackLangs[$i] -eq $reqLang) {
                $selected[$i] = $true
                $matched = $true
            }
        }
        if (-not $matched) {
            [Console]::Error.WriteLine(("Error: No subtitle track with language '{0}' found in {1} (available: {2})." -f $reqLang, $InputPath, ($trackLangs -join ' ')))
            exit 1
        }
    }
}

$selectedCount = @($selected | Where-Object { $_ }).Count

$isSingleFile = $false
$fileExtFormat = ''
if (-not (Test-Path -LiteralPath $Output -PathType Container)) {
    $extLower = [System.IO.Path]::GetExtension($Output).ToLowerInvariant()
    if ($extLower -eq '.srt') {
        $isSingleFile = $true
        $fileExtFormat = 'srt'
    } elseif ($extLower -eq '.ass') {
        $isSingleFile = $true
        $fileExtFormat = 'ass'
    }
}

if ($isSingleFile) {
    if ($selectedCount -gt 1) {
        [Console]::Error.WriteLine("Error: Output path '$Output' is a single subtitle file, but $selectedCount tracks are selected.")
        [Console]::Error.WriteLine('       Pass -Index <n> to choose one track, or specify an output directory instead.')
        exit 1
    }
    if ($normFormat -ne 'auto' -and $normFormat -ne $fileExtFormat) {
        [Console]::Error.WriteLine("Error: -Format $normFormat conflicts with output file extension '$Output'.")
        exit 1
    }
} else {
    if (-not (Test-Path -LiteralPath $Output)) {
        New-Item -ItemType Directory -Path $Output -Force | Out-Null
    }
}

$inStem = [System.IO.Path]::GetFileNameWithoutExtension($resolvedInput)
if ([string]::IsNullOrWhiteSpace($inStem)) {
    $inStem = [System.IO.Path]::GetFileName($resolvedInput)
}

$exportedCount = 0
$bitmapSkipped = 0

for ($i = 0; $i -lt $streams.Count; $i++) {
    if (-not $selected[$i]) { continue }

    $codec = $trackCodecs[$i]
    $langCode = $trackLangs[$i]
    $gIdx = $globalIdxs[$i]
    $kind = Get-SubtitleType $codec

    if ($kind -eq 'bitmap') {
        $humanCodec = Get-BitmapDescription $codec
        [Console]::Error.WriteLine(("Notice: Track {0} (stream #{1}, lang={2}) uses image/bitmap subtitles [{3}] and cannot be directly converted to .srt/.ass plain text. Use an OCR tool (e.g. Subtitle Edit or Tesseract) to convert bitmap subtitles." -f $i, $gIdx, $langCode, $humanCodec))
        $bitmapSkipped++
        continue
    }

    if ($kind -eq 'unknown') {
        [Console]::Error.WriteLine(("Notice: Track {0} (stream #{1}, lang={2}) uses unsupported subtitle codec '{3}'; cannot directly export to .srt/.ass." -f $i, $gIdx, $langCode, $codec))
        $bitmapSkipped++
        continue
    }

    if ($isSingleFile) {
        $targetFmt = $fileExtFormat
        $destPath = $Output
        $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).ProviderPath, $destPath)))
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    } else {
        if ($normFormat -eq 'auto') {
            $targetFmt = if (@('ass', 'ssa') -contains $codec) { 'ass' } else { 'srt' }
        } else {
            $targetFmt = $normFormat
        }
        $safeLang = ($langCode -replace '[^A-Za-z0-9_-]', '_')
        $destPath = Join-Path $Output ("{0}.track{1}.{2}.{3}" -f $inStem, $i, $safeLang, $targetFmt)
    }

    if ((Test-Path -LiteralPath $destPath) -and (-not $Force)) {
        [Console]::Error.WriteLine("Error: Output file already exists: $destPath (pass -Force to overwrite).")
        exit 1
    }

    $ffSubCodec = $targetFmt
    if ($targetFmt -eq 'srt' -and $codec -eq 'subrip') {
        $ffSubCodec = 'copy'
    } elseif ($targetFmt -eq 'ass' -and $codec -eq 'ass') {
        $ffSubCodec = 'copy'
    }

    & ffmpeg -hide_banner -loglevel error -y -i $resolvedInput -map "0:s:$i" -c:s $ffSubCodec $destPath
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("Error: ffmpeg failed while exporting track $i.")
        exit 1
    }

    Write-Output ("Exported track {0} (stream #{1}, lang={2}, {3} -> {4}): {5}" -f $i, $gIdx, $langCode, $codec, $targetFmt, $destPath)
    $exportedCount++
}

if ($exportedCount -eq 0 -and $bitmapSkipped -gt 0) {
    exit 2
}
