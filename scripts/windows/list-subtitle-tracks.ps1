<#
.SYNOPSIS
    Lists all embedded (soft) subtitle tracks in a video file using ffprobe.

.DESCRIPTION
    Inspects <InputPath> with ffprobe and prints every subtitle stream's 0-based
    subtitle track index, global FFmpeg stream index, language code, codec name,
    type (text vs. bitmap), disposition flags, and title.

    Prerequisite: You must install FFmpeg (which includes ffprobe) yourself and
    make sure both `ffmpeg` and `ffprobe` are on your system PATH:
      winget install Gyan.FFmpeg
    or download a build from https://ffmpeg.org/download.html .

.PARAMETER InputPath
    Path to the video file to inspect.

.PARAMETER Tsv
    Emit tab-separated rows without table headers.

.PARAMETER Help
    Show usage instructions and exit.

.EXAMPLE
    .\scripts\windows\list-subtitle-tracks.ps1 .\movie.mkv

.EXAMPLE
    .\scripts\windows\list-subtitle-tracks.ps1 -Tsv .\lecture.mp4
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputPath,

    [switch]$Tsv,

    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Usage {
    @"
Usage:
  .\scripts\windows\list-subtitle-tracks.ps1 [-Tsv] [-Help] <video-file>

Prerequisite:
  FFmpeg (including ffprobe) is NOT bundled. Install it yourself and ensure
  ffprobe.exe is in your PATH (for example: winget install Gyan.FFmpeg).

Options:
  -Tsv         Output machine-readable tab-separated rows
  -Help, -h    Show this help message and exit

Examples:
  .\scripts\windows\list-subtitle-tracks.ps1 .\movie.mkv
  .\scripts\windows\list-subtitle-tracks.ps1 -Tsv .\lecture.mp4
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

if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    [Console]::Error.WriteLine('Error: Missing required <video-file> argument.')
    Show-Usage
    exit 1
}

if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Error: ffprobe was not found in PATH.')
    [Console]::Error.WriteLine('Please install FFmpeg (which includes ffprobe) yourself and reopen PowerShell:')
    [Console]::Error.WriteLine('  winget install Gyan.FFmpeg')
    exit 1
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: File not found: $InputPath")
    exit 1
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).ProviderPath

$jsonRaw = & ffprobe -v error `
    -select_streams s `
    -show_entries 'stream=index,codec_name:stream_disposition=default,forced:stream_tags=language,title,handler_name' `
    -of json `
    $resolvedInput

if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("Error: ffprobe failed to read media file: $InputPath")
    exit 1
}

$parsed = $jsonRaw | ConvertFrom-Json
$streams = @()
if ($null -ne $parsed -and $null -ne $parsed.streams) {
    $streams = @($parsed.streams)
}

if ($streams.Count -eq 0) {
    if (-not $Tsv) {
        Write-Output "No subtitle tracks found in: $InputPath"
        Write-Output 'Hint: If subtitles are visible on the video image, they are burned into the pixels (hardcoded subtitles) rather than stored as a separate track.'
    }
    exit 0
}

$genericHandlers = @(
    'SubtitleHandler',
    'Core Media Text',
    'GPAC Streaming Text Handler',
    'VideoHandler',
    'SoundHandler'
)

if (-not $Tsv) {
    Write-Output ("File: {0} ({1} subtitle track(s))" -f $InputPath, $streams.Count)
    Write-Output ''
    Write-Output ('{0,-5}  {1,-6}  {2,-6}  {3,-18}  {4,-7}  {5,-14}  {6}' -f 'INDEX', 'STREAM', 'LANG', 'CODEC', 'TYPE', 'FLAGS', 'TITLE')
    Write-Output ('{0,-5}  {1,-6}  {2,-6}  {3,-18}  {4,-7}  {5,-14}  {6}' -f '-----', '------', '------', '------------------', '-------', '--------------', '-----')
}

for ($i = 0; $i -lt $streams.Count; $i++) {
    $s = $streams[$i]
    $globalIdx = $s.index
    $codec = if ($s.PSObject.Properties['codec_name'] -and $s.codec_name) { [string]$s.codec_name } else { 'unknown' }
    $lang = 'und'
    $title = ''
    $handler = ''

    if ($s.PSObject.Properties['tags'] -and $null -ne $s.tags) {
        if ($s.tags.PSObject.Properties['language'] -and $s.tags.language) {
            $lang = [string]$s.tags.language
        }
        if ($s.tags.PSObject.Properties['title'] -and $s.tags.title) {
            $title = [string]$s.tags.title
        }
        if ($s.tags.PSObject.Properties['handler_name'] -and $s.tags.handler_name) {
            $handler = [string]$s.tags.handler_name
        }
    }

    if ([string]::IsNullOrWhiteSpace($title) -and -not [string]::IsNullOrWhiteSpace($handler) -and ($genericHandlers -notcontains $handler)) {
        $title = $handler
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = '-'
    }

    $flagsList = @()
    if ($s.PSObject.Properties['disposition'] -and $null -ne $s.disposition) {
        if ($s.disposition.default -eq 1) { $flagsList += 'default' }
        if ($s.disposition.forced -eq 1)  { $flagsList += 'forced' }
    }
    $flags = if ($flagsList.Count -gt 0) { $flagsList -join ',' } else { '-' }
    $subType = Get-SubtitleType $codec

    if ($Tsv) {
        Write-Output ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $i, $globalIdx, $lang, $codec, $subType, $flags, $title)
    } else {
        Write-Output ('{0,-5}  {1,-6}  {2,-6}  {3,-18}  {4,-7}  {5,-14}  {6}' -f $i, "#$globalIdx", $lang, $codec, $subType, $flags, $title)
    }
}
