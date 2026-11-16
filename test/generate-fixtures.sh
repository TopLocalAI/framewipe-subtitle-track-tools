#!/usr/bin/env bash
# generate-fixtures.sh — Generate temporary MKV and MP4 test videos with dual SRT tracks.
# Compatible with Bash 3.2+ and Bash 4/5+.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  generate-fixtures.sh [output-dir]

Description:
  Uses FFmpeg (testsrc + sine + two .srt subtitle files in English and Chinese)
  to generate temporary test videos for verifying the subtitle track scripts:
    - sample-dual-subs.mkv  (H.264 + AAC + 2 SubRip tracks: eng, zho)
    - sample-dual-subs.mp4  (H.264 + AAC + 2 mov_text tracks: eng, zho)
    - sample-pgs-bitmap.mkv (H.264 + 1 Blu-ray PGS bitmap subtitle track)

  Default [output-dir] is "<repo>/test/fixtures" (ignored by git).
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
OUT_DIR="${1:-${SCRIPT_DIR}/fixtures}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  printf 'Error: ffmpeg not found in PATH.\n' >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

EN_SRT="${OUT_DIR}/sub-en.srt"
ZH_SRT="${OUT_DIR}/sub-zh.srt"
PGS_SUP="${OUT_DIR}/sample.sup"

cat > "$EN_SRT" <<'EOF'
1
00:00:00,200 --> 00:00:01,400
Welcome to the subtitle track test.

2
00:00:01,600 --> 00:00:02,800
Second English cue for verification.
EOF

cat > "$ZH_SRT" <<'EOF'
1
00:00:00,200 --> 00:00:01,400
欢迎运行软字幕轨道测试。

2
00:00:01,600 --> 00:00:02,800
第二条中文字幕用于校验导出结果。
EOF

# 1. MKV container with 2 SRT (subrip) subtitle tracks
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=duration=3:size=320x240:rate=15" \
  -f lavfi -i "sine=frequency=440:duration=3" \
  -i "$EN_SRT" \
  -i "$ZH_SRT" \
  -map 0:v:0 -map 1:a:0 -map 2:0 -map 3:0 \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  -c:s srt \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title="English" \
  -metadata:s:s:1 language=zho -metadata:s:s:1 title="Simplified Chinese" \
  -disposition:s:0 default \
  -disposition:s:1 0 \
  "${OUT_DIR}/sample-dual-subs.mkv"

# 2. MP4 container with 2 mov_text subtitle tracks
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=duration=3:size=320x240:rate=15" \
  -f lavfi -i "sine=frequency=440:duration=3" \
  -i "$EN_SRT" \
  -i "$ZH_SRT" \
  -map 0:v:0 -map 1:a:0 -map 2:0 -map 3:0 \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  -c:s mov_text \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title="English" -metadata:s:s:0 handler_name="English" \
  -metadata:s:s:1 language=zho -metadata:s:s:1 title="Simplified Chinese" -metadata:s:s:1 handler_name="Simplified Chinese" \
  -disposition:s:0 default \
  -disposition:s:1 0 \
  "${OUT_DIR}/sample-dual-subs.mp4"

# 3. Minimal Blu-ray PGS (.sup) bitmap subtitle stream muxed into MKV
# 13-byte valid HDMV PGS END_OF_DISPLAY_SET segment: "PG" + PTS(90000) + DTS(0) + type(0x80) + size(0)
printf 'PG\x00\x01\x5f\x90\x00\x00\x00\x00\x80\x00\x00' > "$PGS_SUP"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=duration=2:size=320x240:rate=15" \
  -i "$PGS_SUP" \
  -map 0:v:0 -map 1:0 \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:s copy \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title="Blu-ray PGS" \
  "${OUT_DIR}/sample-pgs-bitmap.mkv"

printf 'Generated fixtures in %s:\n' "$OUT_DIR"
printf '  - %s\n' "${OUT_DIR}/sample-dual-subs.mkv"
printf '  - %s\n' "${OUT_DIR}/sample-dual-subs.mp4"
printf '  - %s\n' "${OUT_DIR}/sample-pgs-bitmap.mkv"
