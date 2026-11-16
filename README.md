English | [简体中文](README.zh-CN.md) | [日本語](./README.ja.md)

# framewipe-subtitle-track-tools

`framewipe-subtitle-track-tools` is a standalone collection of FFmpeg/FFprobe command-line scripts (in both Bash and PowerShell) and a practical guide for video editors, creators, archivists, and developers working with subtitled video files. Use it to check whether subtitles in a video are separate soft tracks or burned into the picture, inspect subtitle track metadata, losslessly remove all or selected soft subtitle tracks without re-encoding (`-c copy`), and export text-based subtitle tracks to `.srt` or `.ass`.

The official website of FrameWipe is [framewipe.com](https://framewipe.com).

---

## First Step: Soft Subtitles vs. Hard Subtitles

When people want to "remove subtitles from a video," there are two fundamentally different cases:

1. **Soft subtitles (separate subtitle tracks)**: Stored as independent `subtitle` streams inside containers such as `.mkv`, `.mp4`, `.mov`, or `.webm`. Media players can toggle them on or off, and FFmpeg can strip them in seconds with `-c copy` (zero video or audio quality loss) or extract text tracks into `.srt` / `.ass`. **This repository solves soft subtitles directly.**
2. **Hard subtitles (burned-in / hardcoded subtitles)**: Drawn permanently into the video pixels when the clip was exported. No subtitle stream exists to remove; cleaning them up requires cropping, masking, or frame-by-frame video inpainting and re-encoding.

Not sure which kind your file has? Run `./scripts/list-subtitle-tracks.sh your-video.mp4` or read the full guide:

- English guide: [docs/soft-vs-hard-subtitles.en.md](docs/soft-vs-hard-subtitles.en.md)
- 中文指南：[docs/soft-vs-hard-subtitles.md](docs/soft-vs-hard-subtitles.md)

---

## Repository Structure

```text
framewipe-subtitle-track-tools/
├── scripts/
│   ├── list-subtitle-tracks.sh          # Bash: inspect subtitle tracks (index, lang, codec, title)
│   ├── remove-subtitle-tracks.sh        # Bash: lossless subtitle removal (-c copy)
│   ├── extract-subtitles.sh             # Bash: export text tracks to .srt/.ass, warn on bitmap
│   └── windows/
│       ├── list-subtitle-tracks.ps1     # PowerShell equivalent for Windows
│       ├── remove-subtitle-tracks.ps1   # PowerShell equivalent for Windows
│       └── extract-subtitles.ps1        # PowerShell equivalent for Windows
├── docs/
│   ├── soft-vs-hard-subtitles.en.md     # How to identify & handle soft vs. hard subtitles (EN)
│   └── soft-vs-hard-subtitles.md        # 软字幕与硬字幕判断及处理说明（中文）
├── test/
│   ├── generate-fixtures.sh             # Generates MKV, MP4, and PGS test videos via ffmpeg
│   ├── run-tests.sh                     # Automated test suite (57 assertions)
│   └── README.md                        # Test documentation and verified run output
└── LICENSE                              # MIT License (for code/scripts)
```

---

## Prerequisites

All scripts rely on **`ffmpeg`** and **`ffprobe`** (included in standard FFmpeg builds) being available on your `PATH`. No Python packages, `jq`, or extra dependencies are required.

- **macOS (Homebrew)**:
  ```bash
  brew install ffmpeg
  ```
- **Ubuntu / Debian**:
  ```bash
  sudo apt update && sudo apt install ffmpeg
  ```
- **Windows (required for `scripts/windows/*.ps1`)**:
  FFmpeg is **not** bundled with these PowerShell scripts—you must install FFmpeg yourself and ensure both `ffmpeg.exe` and `ffprobe.exe` are in your system `PATH` (reopen PowerShell after installing):
  ```powershell
  winget install Gyan.FFmpeg
  ```
  Or download a release build from [ffmpeg.org/download.html](https://ffmpeg.org/download.html) and add its `bin` folder to `PATH`.

Verify installation:

```bash
ffmpeg -version
ffprobe -version
```

---

## Usage (macOS / Linux / WSL / Git Bash)

### 1. List all subtitle tracks (`list-subtitle-tracks.sh`)

Prints every embedded subtitle stream's 0-based subtitle track `INDEX`, global FFmpeg `STREAM` ID, ISO language tag, codec name, track type (`text` vs. `bitmap`), disposition flags (`default`, `forced`), and track title:

```bash
./scripts/list-subtitle-tracks.sh movie.mkv
```

Example output:

```text
File: movie.mkv (2 subtitle track(s))

INDEX  STREAM  LANG    CODEC               TYPE     FLAGS           TITLE
-----  ------  ------  ------------------  -------  --------------  -----
0      #2      eng     subrip              text     default         English
1      #3      zho     subrip              text     -               Simplified Chinese
```

For scripting, pass `--tsv` to output tab-separated rows without headers:

```bash
./scripts/list-subtitle-tracks.sh --tsv movie.mkv
```

### 2. Remove soft subtitle tracks without re-encoding (`remove-subtitle-tracks.sh`)

Uses FFmpeg stream copy (`-c copy`) to write a new media file while keeping video and audio streams untouched bit-for-bit. Refuses to overwrite the source file in place.

```bash
# Remove ALL soft subtitle tracks
./scripts/remove-subtitle-tracks.sh input.mkv output-clean.mkv
./scripts/remove-subtitle-tracks.sh input.mp4 output-clean.mp4

# Remove only Chinese subtitle track(s) (case-insensitive ISO 639 code), keep others
./scripts/remove-subtitle-tracks.sh --lang zho input.mp4 output-en-only.mp4

# Remove specific 0-based subtitle track index(es) from list-subtitle-tracks.sh
./scripts/remove-subtitle-tracks.sh --index 0 input.mkv output.mkv
./scripts/remove-subtitle-tracks.sh --index 0,2 --force input.mkv output.mkv
```

### 3. Extract text subtitles to `.srt` or `.ass` (`extract-subtitles.sh`)

Exports text-based subtitle tracks (`subrip`, `ass`, `ssa`, `mov_text`, `webvtt`, etc.) to `.srt` or `.ass`.

```bash
# Extract all text subtitle tracks into ./subs/ (auto-picks .ass for ASS/SSA, .srt otherwise)
./scripts/extract-subtitles.sh movie.mkv ./subs

# Extract track 0 to a single .srt or .ass file
./scripts/extract-subtitles.sh --index 0 movie.mp4 english.srt
./scripts/extract-subtitles.sh --index 0 movie.mkv english.ass

# Extract Chinese track(s) into ./subs/ converted to .ass
./scripts/extract-subtitles.sh --lang zho --format ass movie.mp4 ./subs
```

**Bitmap subtitle tracks**: When a track uses an image-based codec such as Blu-ray PGS (`hdmv_pgs_subtitle`) or DVD VobSub (`dvd_subtitle`), `extract-subtitles.sh` prints a clear notice explaining that bitmap subtitles cannot be directly converted to plain text without OCR (and exits with code `2` if no text tracks were exported).

---

## Usage on Windows (PowerShell)

Make sure you have installed FFmpeg (`ffmpeg.exe` and `ffprobe.exe` in `PATH`) first. If PowerShell blocks local script execution in your session, run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run the PowerShell scripts in `scripts\windows\`:

```powershell
# 1. Inspect subtitle tracks
.\scripts\windows\list-subtitle-tracks.ps1 .\movie.mkv

# 2. Losslessly remove all or selected subtitle tracks (-c copy)
.\scripts\windows\remove-subtitle-tracks.ps1 .\movie.mkv .\movie-clean.mkv
.\scripts\windows\remove-subtitle-tracks.ps1 -Lang zho .\movie.mp4 .\movie-en.mp4
.\scripts\windows\remove-subtitle-tracks.ps1 -Index 0 -Force .\movie.mkv .\movie-out.mkv

# 3. Extract text subtitles to .srt or .ass
.\scripts\windows\extract-subtitles.ps1 .\movie.mkv .\subs
.\scripts\windows\extract-subtitles.ps1 -Index 0 .\movie.mp4 .\english.srt
.\scripts\windows\extract-subtitles.ps1 -Lang zho -Format ass .\movie.mkv .\subs
```

---

## Common Subtitle Codecs Reference

| FFmpeg Codec Name | Format Name | Type | Common Containers | Can Remove with `-c copy`? | Direct `.srt` / `.ass` Export? |
| --- | --- | --- | --- | --- | --- |
| `subrip` (`srt`) | SubRip | Text | `.mkv` | Yes | Yes |
| `ass` / `ssa` | SubStation Alpha | Text | `.mkv` | Yes | Yes |
| `mov_text` | MPEG-4 Timed Text (`tx3g`) | Text | `.mp4`, `.mov`, `.m4v` | Yes | Yes |
| `webvtt` | WebVTT | Text | `.webm`, `.mkv` | Yes | Yes |
| `hdmv_pgs_subtitle` | Blu-ray PGS (`.sup`) | Bitmap | `.mkv`, `.m2ts` | Yes | No (requires OCR) |
| `dvd_subtitle` | DVD VobSub (`.idx`/`.sub`) | Bitmap | `.mkv`, `.mp4`, `.vob` | Yes | No (requires OCR) |
| `dvb_subtitle` | DVB Subtitle | Bitmap | `.ts`, `.mkv` | Yes | No (requires OCR) |

---

## Running Tests

The `test/` directory generates dual-subtitle `.mkv` and `.mp4` test videos plus a Blu-ray PGS `.mkv` fixture using `ffmpeg`, then verifies all three scripts (including checking with `ffprobe` that removed tracks are gone and that the video stream codec, frame count, and compressed bitstream MD5 remain unchanged):

```bash
bash test/run-tests.sh
```

See [test/README.md](test/README.md) for full test details and recorded output.

---

## Want to Automate This?

If your video has burned-in (hardcoded) subtitles painted into the frames—or you prefer a desktop GUI that also strips soft subtitle tracks in one click—[FrameWipe](https://framewipe.com/remove-subtitles-from-video) handles subtitle and on-screen text cleanup offline on Apple Silicon Macs (macOS 13+) and Windows 10/11 (x64). It opens MP4, MOV, and WebM videos (MKV is not supported yet), detects the subtitle region, renders a 2-second preview before processing the chosen time range into a new file without touching your original, and also includes photo text/clutter removal and photo/video face blurring (plus an optional Mac-only object tracking add-on). FrameWipe is available on Patreon as a US$39.99 one-time purchase with a 7-day full refund; see [framewipe.com/remove-subtitles-from-video](https://framewipe.com/remove-subtitles-from-video) for details and limits.

---

## License

- Code and scripts (`scripts/`, `test/*.sh`): [MIT License](LICENSE).
- Documentation, data, and images (`docs/`, `README.md`, `README.zh-CN.md`, `test/README.md`): [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
