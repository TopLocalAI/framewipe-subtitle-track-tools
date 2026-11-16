# Test Suite (`test/`)

This directory contains the fixture generator and automated end-to-end test suite for the three subtitle track scripts (`list-subtitle-tracks.sh`, `remove-subtitle-tracks.sh`, and `extract-subtitles.sh`).

Generated test videos and temporary outputs are written to `test/fixtures/` and `test/output/`, both of which are listed in `.gitignore` and automatically cleaned up when `test/run-tests.sh` finishes (unless `KEEP_ARTIFACTS=1` is set).

## Files

- `generate-fixtures.sh`: Uses `ffmpeg` (`testsrc` video + `sine` audio + two `.srt` subtitle files in English `eng` and Simplified Chinese `zho`) to generate:
  - `sample-dual-subs.mkv` — H.264 video (`45` frames, `320x240`, `15 fps`) + AAC audio + 2 `subrip` subtitle tracks (`eng` / `zho`).
  - `sample-dual-subs.mp4` — H.264 video (`45` frames, `320x240`, `15 fps`) + AAC audio + 2 `mov_text` subtitle tracks (`eng` / `zho`).
  - `sample-pgs-bitmap.mkv` — H.264 video + 1 minimal Blu-ray PGS (`hdmv_pgs_subtitle`) bitmap subtitle stream to verify graphic subtitle detection.
- `run-tests.sh`: Runs `generate-fixtures.sh` and executes 57 assertions across `.mkv`, `.mp4`, bitmap PGS, and argument safety checks.

## How to Run

From the repository root:

```bash
bash test/run-tests.sh
```

To keep the generated fixtures and outputs in `test/fixtures/` and `test/output/` for manual inspection:

```bash
KEEP_ARTIFACTS=1 bash test/run-tests.sh
```

## Latest Verified Test Run

Environment: macOS (`arm64`), GNU Bash `3.2.57`, FFmpeg `8.1`.

### Summary Table

| Container / Case | Script & Scenario | Subtitle Tracks (Before -> After) | Video Codec (Before -> After) | Video Frames (Before -> After) | Video Stream MD5 Match | Result |
| --- | --- | --- | --- | --- | --- | --- |
| `.mkv` (`subrip`) | `list-subtitle-tracks.sh` | `2` (`eng`, `zho`) | `h264` | `45` | — | PASS |
| `.mkv` (`subrip`) | `remove-subtitle-tracks.sh --lang zho` | `2 -> 1` (`eng` kept) | `h264 -> h264` | `45 -> 45` | `76a38abf00e1da91ebd13d5aa181cd8e` (identical) | PASS |
| `.mkv` (`subrip`) | `remove-subtitle-tracks.sh --index 0` | `2 -> 1` (`zho` kept) | `h264 -> h264` | `45 -> 45` | `76a38abf00e1da91ebd13d5aa181cd8e` (identical) | PASS |
| `.mkv` (`subrip`) | `remove-subtitle-tracks.sh` (all) | `2 -> 0` | `h264 -> h264` | `45 -> 45` | `76a38abf00e1da91ebd13d5aa181cd8e` (identical) | PASS |
| `.mkv` (`subrip`) | `extract-subtitles.sh` (`.srt` & `.ass`) | Exported `eng` & `zho` `.srt` + `.ass` | — | — | — | PASS |
| `.mp4` (`mov_text`) | `list-subtitle-tracks.sh` | `2` (`eng`, `zho`) | `h264` | `45` | — | PASS |
| `.mp4` (`mov_text`) | `remove-subtitle-tracks.sh --lang zho` | `2 -> 1` (`eng` kept) | `h264 -> h264` | `45 -> 45` | `76a38abf00e1da91ebd13d5aa181cd8e` (identical) | PASS |
| `.mp4` (`mov_text`) | `remove-subtitle-tracks.sh --index 0` | `2 -> 1` (`zho` kept) | `h264 -> h264` | `45 -> 45` | `76a38abf00e1da91ebd13d5aa181cd8e` (identical) | PASS |
| `.mp4` (`mov_text`) | `remove-subtitle-tracks.sh` (all) | `2 -> 0` | `h264 -> h264` | `45 -> 45` | `76a38abf00e1da91ebd13d5aa181cd8e` (identical) | PASS |
| `.mp4` (`mov_text`) | `extract-subtitles.sh` (`.srt` & `.ass`) | Exported `eng` & `zho` `.srt` + `.ass` | — | — | — | PASS |
| `.mkv` (`hdmv_pgs_subtitle`) | `extract-subtitles.sh` (bitmap check) | Detected as `bitmap`, exited with code `2` & OCR notice | — | — | — | PASS |
| Validation | In-place overwrite, invalid `--index`, missing `--lang` | Rejected with non-zero exit code | — | — | — | PASS |

### Raw Output (`bash test/run-tests.sh`)

```text
============================================================
1. Generating MKV, MP4, and PGS bitmap fixtures via FFmpeg
============================================================
Generated fixtures in .../test/fixtures:
  - .../test/fixtures/sample-dual-subs.mkv
  - .../test/fixtures/sample-dual-subs.mp4
  - .../test/fixtures/sample-pgs-bitmap.mkv

============================================================
2. Container suite: .mkv
============================================================
Baseline (sample-dual-subs.mkv): video_codec=h264, video_frames=45, subtitle_tracks=2, video_stream_MD5=76a38abf00e1da91ebd13d5aa181cd8e
  [PASS] mkv: initial subtitle track count (2)

--- [mkv] list-subtitle-tracks.sh ---
File: .../test/fixtures/sample-dual-subs.mkv (2 subtitle track(s))

INDEX  STREAM  LANG    CODEC               TYPE     FLAGS           TITLE
-----  ------  ------  ------------------  -------  --------------  -----
0      #2      eng     subrip              text     default         English
1      #3      zho     subrip              text     -               Simplified Chinese
  [PASS] mkv: lists codec subrip
  [PASS] mkv: lists language eng
  [PASS] mkv: lists language zho
  [PASS] mkv: lists title 'English'
  [PASS] mkv: lists title 'Simplified Chinese'

--- [mkv] remove-subtitle-tracks.sh --lang zho ---
Removed 1 subtitle track(s), kept 1 subtitle track(s) -> .../test/output/removed-zho.mkv
  [PASS] mkv: subtitle count after --lang zho (1)
  [PASS] mkv: remaining subtitle language is eng (eng)
  [PASS] mkv: video codec unchanged (not re-encoded) (h264)
  [PASS] mkv: video frame count unchanged (45)
  [PASS] mkv: video compressed bitstream MD5 identical (MD5=76a38abf00e1da91ebd13d5aa181cd8e)

--- [mkv] remove-subtitle-tracks.sh --index 0 ---
Removed 1 subtitle track(s), kept 1 subtitle track(s) -> .../test/output/removed-idx0.mkv
  [PASS] mkv: subtitle count after --index 0 (1)
  [PASS] mkv: remaining subtitle language is zho (zho)
  [PASS] mkv: video codec unchanged (not re-encoded) (h264)
  [PASS] mkv: video frame count unchanged (45)
  [PASS] mkv: video compressed bitstream MD5 identical (MD5=76a38abf00e1da91ebd13d5aa181cd8e)

--- [mkv] remove-subtitle-tracks.sh (remove all) ---
Removed 2 subtitle track(s), kept 0 subtitle track(s) -> .../test/output/removed-all.mkv
  [PASS] mkv: subtitle count after removing all tracks (0)
  [PASS] mkv: video codec unchanged (not re-encoded) (h264)
  [PASS] mkv: video frame count unchanged (45)
  [PASS] mkv: video compressed bitstream MD5 identical (MD5=76a38abf00e1da91ebd13d5aa181cd8e)
  [PASS] mkv: list-subtitle-tracks reports 0 tracks on stripped file

--- [mkv] extract-subtitles.sh (.srt & .ass) ---
Exported track 0 (stream #2, lang=eng, subrip -> srt): .../test/output/subs-mkv/sample-dual-subs.track0.eng.srt
Exported track 1 (stream #3, lang=zho, subrip -> srt): .../test/output/subs-mkv/sample-dual-subs.track1.zho.srt
  [PASS] mkv: exported English .srt text verified
  [PASS] mkv: exported Chinese .srt text verified
Exported track 0 (stream #2, lang=eng, subrip -> ass): .../test/output/track0-mkv.ass
  [PASS] mkv: exported .ass header verified
  [PASS] mkv: exported .ass dialogue verified

============================================================
2. Container suite: .mp4
============================================================
Baseline (sample-dual-subs.mp4): video_codec=h264, video_frames=45, subtitle_tracks=2, video_stream_MD5=76a38abf00e1da91ebd13d5aa181cd8e
  [PASS] mp4: initial subtitle track count (2)

--- [mp4] list-subtitle-tracks.sh ---
File: .../test/fixtures/sample-dual-subs.mp4 (2 subtitle track(s))

INDEX  STREAM  LANG    CODEC               TYPE     FLAGS           TITLE
-----  ------  ------  ------------------  -------  --------------  -----
0      #2      eng     mov_text            text     default         English
1      #3      zho     mov_text            text     -               Simplified Chinese
  [PASS] mp4: lists codec mov_text
  [PASS] mp4: lists language eng
  [PASS] mp4: lists language zho
  [PASS] mp4: lists title 'English'
  [PASS] mp4: lists title 'Simplified Chinese'

--- [mp4] remove-subtitle-tracks.sh --lang zho ---
Removed 1 subtitle track(s), kept 1 subtitle track(s) -> .../test/output/removed-zho.mp4
  [PASS] mp4: subtitle count after --lang zho (1)
  [PASS] mp4: remaining subtitle language is eng (eng)
  [PASS] mp4: video codec unchanged (not re-encoded) (h264)
  [PASS] mp4: video frame count unchanged (45)
  [PASS] mp4: video compressed bitstream MD5 identical (MD5=76a38abf00e1da91ebd13d5aa181cd8e)

--- [mp4] remove-subtitle-tracks.sh --index 0 ---
Removed 1 subtitle track(s), kept 1 subtitle track(s) -> .../test/output/removed-idx0.mp4
  [PASS] mp4: subtitle count after --index 0 (1)
  [PASS] mp4: remaining subtitle language is zho (zho)
  [PASS] mp4: video codec unchanged (not re-encoded) (h264)
  [PASS] mp4: video frame count unchanged (45)
  [PASS] mp4: video compressed bitstream MD5 identical (MD5=76a38abf00e1da91ebd13d5aa181cd8e)

--- [mp4] remove-subtitle-tracks.sh (remove all) ---
Removed 2 subtitle track(s), kept 0 subtitle track(s) -> .../test/output/removed-all.mp4
  [PASS] mp4: subtitle count after removing all tracks (0)
  [PASS] mp4: video codec unchanged (not re-encoded) (h264)
  [PASS] mp4: video frame count unchanged (45)
  [PASS] mp4: video compressed bitstream MD5 identical (MD5=76a38abf00e1da91ebd13d5aa181cd8e)
  [PASS] mp4: list-subtitle-tracks reports 0 tracks on stripped file

--- [mp4] extract-subtitles.sh (.srt & .ass) ---
Exported track 0 (stream #2, lang=eng, mov_text -> srt): .../test/output/subs-mp4/sample-dual-subs.track0.eng.srt
Exported track 1 (stream #3, lang=zho, mov_text -> srt): .../test/output/subs-mp4/sample-dual-subs.track1.zho.srt
  [PASS] mp4: exported English .srt text verified
  [PASS] mp4: exported Chinese .srt text verified
Exported track 0 (stream #2, lang=eng, mov_text -> ass): .../test/output/track0-mp4.ass
  [PASS] mp4: exported .ass header verified
  [PASS] mp4: exported .ass dialogue verified

============================================================
3. Bitmap subtitle detection (Blu-ray PGS in .mkv)
============================================================
File: .../test/fixtures/sample-pgs-bitmap.mkv (1 subtitle track(s))

INDEX  STREAM  LANG    CODEC               TYPE     FLAGS           TITLE
-----  ------  ------  ------------------  -------  --------------  -----
0      #1      eng     hdmv_pgs_subtitle   bitmap   -               Blu-ray PGS
  [PASS] PGS fixture codec detected
  [PASS] PGS fixture classified as bitmap
Notice: Track 0 (stream #1, lang=eng) uses image/bitmap subtitles [Blu-ray PGS (hdmv_pgs_subtitle)] and cannot be directly converted to .srt/.ass plain text. Use an OCR tool (e.g. Subtitle Edit or Tesseract) to convert bitmap subtitles.
  [PASS] extract-subtitles exits with code 2 on bitmap-only subtitle track (2)
  [PASS] extract-subtitles prints clear OCR notice for bitmap track

============================================================
4. Parameter & safety validation checks
============================================================
  [PASS] remove-subtitle-tracks rejects in-place overwrite of input file
  [PASS] remove-subtitle-tracks rejects out-of-range --index
  [PASS] extract-subtitles rejects missing language code

============================================================
ALL 57 ASSERTIONS PASSED (MKV + MP4 + PGS bitmap + safety)
============================================================
```
