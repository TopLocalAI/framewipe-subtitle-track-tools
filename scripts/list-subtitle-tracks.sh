#!/usr/bin/env bash
# list-subtitle-tracks.sh — Inspect all subtitle tracks in a media file via ffprobe.
# Compatible with Bash 3.2+ (macOS default bash) and Bash 4/5+ (Linux/WSL/Git Bash).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  list-subtitle-tracks.sh [options] <video-file>

Description:
  Lists every embedded (soft) subtitle track in <video-file>, showing its
  0-based subtitle track index, global FFmpeg stream index, language tag,
  codec name, track type (text vs. bitmap), disposition flags, and title.

Options:
  --tsv        Output machine-readable tab-separated rows (no header/footer)
  -h, --help   Show this help message and exit

Examples:
  ./scripts/list-subtitle-tracks.sh movie.mkv
  ./scripts/list-subtitle-tracks.sh --tsv lecture.mp4
EOF
}

classify_subtitle_codec() {
  local codec="$1"
  case "$codec" in
    hdmv_pgs_subtitle|dvd_subtitle|dvb_subtitle|xsub)
      printf 'bitmap'
      ;;
    subrip|srt|ass|ssa|mov_text|webvtt|text|ttml|eia_608|hdmv_text_subtitle|jacosub|microdvd|mpl2|pjs|realtext|sami|stl|subviewer|subviewer1|vplayer|dvb_teletext|arib_caption)
      printf 'text'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

is_generic_handler() {
  local h="$1"
  case "$h" in
    ""|"SubtitleHandler"|"Core Media Text"|"GPAC Streaming Text Handler"|"VideoHandler"|"SoundHandler")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

TSV_MODE=0
INPUT_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --tsv)
      TSV_MODE=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'Error: Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$INPUT_FILE" ]; then
        printf 'Error: Unexpected extra argument: %s\n\n' "$1" >&2
        usage >&2
        exit 1
      fi
      INPUT_FILE="$1"
      shift
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  if [ -z "$INPUT_FILE" ] && [ "$#" -eq 1 ]; then
    INPUT_FILE="$1"
  else
    printf 'Error: Too many arguments.\n\n' >&2
    usage >&2
    exit 1
  fi
fi

if [ -z "$INPUT_FILE" ]; then
  printf 'Error: Missing required <video-file> argument.\n\n' >&2
  usage >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  printf 'Error: ffprobe not found in PATH. Please install FFmpeg (which includes ffprobe).\n' >&2
  printf '  macOS:   brew install ffmpeg\n' >&2
  printf '  Ubuntu:  sudo apt install ffmpeg\n' >&2
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  printf 'Error: File not found: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

if [ ! -r "$INPUT_FILE" ]; then
  printf 'Error: File is not readable: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

# Verify ffprobe can open the container
if ! ffprobe -v error -show_entries format=format_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" >/dev/null 2>&1; then
  printf 'Error: ffprobe could not read media container: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

STREAM_INDICES_RAW="$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT_FILE" | tr -d '\r')"

if [ -z "$STREAM_INDICES_RAW" ]; then
  if [ "$TSV_MODE" -eq 0 ]; then
    printf 'No subtitle tracks found in: %s\n' "$INPUT_FILE"
    printf 'Hint: If subtitles are visible on the video image, they are burned into the pixels (hardcoded subtitles) rather than stored as a separate track.\n'
  fi
  exit 0
fi

TRACK_COUNT=0
while IFS= read -r _line; do
  [ -n "$_line" ] && TRACK_COUNT=$((TRACK_COUNT + 1))
done <<EOF
$STREAM_INDICES_RAW
EOF

if [ "$TSV_MODE" -eq 0 ]; then
  printf 'File: %s (%d subtitle track(s))\n\n' "$INPUT_FILE" "$TRACK_COUNT"
  printf '%-5s  %-6s  %-6s  %-18s  %-7s  %-14s  %s\n' \
    "INDEX" "STREAM" "LANG" "CODEC" "TYPE" "FLAGS" "TITLE"
  printf '%-5s  %-6s  %-6s  %-18s  %-7s  %-14s  %s\n' \
    "-----" "------" "------" "------------------" "-------" "--------------" "-----"
fi

SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  GLOBAL_IDX="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  CODEC="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  LANG_TAG="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  TITLE_TAG="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_tags=title -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  HANDLER_TAG="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_tags=handler_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  DISP_DEFAULT="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_disposition=default -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  DISP_FORCED="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_disposition=forced -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"

  [ -z "$CODEC" ] && CODEC="unknown"
  [ -z "$LANG_TAG" ] && LANG_TAG="und"

  if [ -z "$TITLE_TAG" ] && ! is_generic_handler "$HANDLER_TAG"; then
    TITLE_TAG="$HANDLER_TAG"
  fi
  [ -z "$TITLE_TAG" ] && TITLE_TAG="-"

  SUB_TYPE="$(classify_subtitle_codec "$CODEC")"

  FLAGS=""
  if [ "$DISP_DEFAULT" = "1" ]; then
    FLAGS="default"
  fi
  if [ "$DISP_FORCED" = "1" ]; then
    if [ -n "$FLAGS" ]; then
      FLAGS="${FLAGS},forced"
    else
      FLAGS="forced"
    fi
  fi
  [ -z "$FLAGS" ] && FLAGS="-"

  if [ "$TSV_MODE" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$SUB_IDX" "$GLOBAL_IDX" "$LANG_TAG" "$CODEC" "$SUB_TYPE" "$FLAGS" "$TITLE_TAG"
  else
    printf '%-5s  %-6s  %-6s  %-18s  %-7s  %-14s  %s\n' \
      "$SUB_IDX" "#${GLOBAL_IDX}" "$LANG_TAG" "$CODEC" "$SUB_TYPE" "$FLAGS" "$TITLE_TAG"
  fi

  SUB_IDX=$((SUB_IDX + 1))
done
