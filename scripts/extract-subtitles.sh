#!/usr/bin/env bash
# extract-subtitles.sh — Export text-based subtitle tracks to .srt / .ass, and warn on bitmap subtitles.
# Compatible with Bash 3.2+ (macOS default bash) and Bash 4/5+ (Linux/WSL/Git Bash).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  extract-subtitles.sh [options] <input-video> [output-file-or-dir]

Description:
  Extracts text-based subtitle tracks (such as SubRip/SRT, ASS/SSA, MP4 mov_text,
  or WebVTT) from <input-video> into .srt or .ass files.

  Image/bitmap subtitle tracks (such as Blu-ray PGS hdmv_pgs_subtitle or DVD
  VobSub dvd_subtitle) cannot be converted directly to plain text; when
  encountered, this script prints a clear message explaining why OCR is needed.

Options:
  -i, --index <list>         Extract 0-based subtitle track index(es), comma-separated
                             (matches INDEX from list-subtitle-tracks.sh, e.g. 0 or 0,1)
  -l, --lang <list>          Extract subtitle track(s) matching language tag(s),
                             comma-separated (case-insensitive, e.g. eng or zho)
  -F, --format <srt|ass|auto>
                             Target text format (default: auto — keeps .ass for ASS/SSA
                             tracks and exports .srt for other text codecs)
  -o, --output <path>        Destination .srt/.ass file (when extracting 1 track) or
                             output directory (can also be passed as 2nd positional arg;
                             defaults to current directory ".")
  -f, --force                Overwrite existing output file(s)
  -h, --help                 Show this help message and exit

Exit codes:
  0  At least one text subtitle track was exported (and no fatal error occurred)
  1  Invalid arguments, missing file/tools, or FFmpeg error
  2  Selected subtitle track(s) are bitmap/image-based and cannot be exported as text

Examples:
  # Extract all text subtitle tracks into ./subs/
  ./scripts/extract-subtitles.sh movie.mkv ./subs

  # Extract track 0 to a specific .srt file
  ./scripts/extract-subtitles.sh --index 0 movie.mp4 english.srt

  # Extract Chinese track as .ass
  ./scripts/extract-subtitles.sh --lang zho --format ass movie.mkv ./subs
EOF
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
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

describe_bitmap_codec() {
  local codec="$1"
  case "$codec" in
    hdmv_pgs_subtitle) printf 'Blu-ray PGS (hdmv_pgs_subtitle)' ;;
    dvd_subtitle)      printf 'DVD VobSub (dvd_subtitle)' ;;
    dvb_subtitle)      printf 'DVB Subtitle (dvb_subtitle)' ;;
    xsub)              printf 'DivX XSUB (xsub)' ;;
    *)                 printf '%s' "$codec" ;;
  esac
}

FILTER_INDICES=""
FILTER_LANGS=""
FORMAT="auto"
OUTPUT_TARGET=""
FORCE=0
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    -i|--index)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        printf 'Error: %s requires a value.\n\n' "$1" >&2
        usage >&2
        exit 1
      fi
      FILTER_INDICES="${FILTER_INDICES:+$FILTER_INDICES,}$2"
      shift 2
      ;;
    --index=*)
      val="${1#*=}"
      [ -z "$val" ] && { printf 'Error: --index requires a value.\n' >&2; exit 1; }
      FILTER_INDICES="${FILTER_INDICES:+$FILTER_INDICES,}$val"
      shift
      ;;
    -l|--lang)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        printf 'Error: %s requires a value.\n\n' "$1" >&2
        usage >&2
        exit 1
      fi
      FILTER_LANGS="${FILTER_LANGS:+$FILTER_LANGS,}$2"
      shift 2
      ;;
    --lang=*)
      val="${1#*=}"
      [ -z "$val" ] && { printf 'Error: --lang requires a value.\n' >&2; exit 1; }
      FILTER_LANGS="${FILTER_LANGS:+$FILTER_LANGS,}$val"
      shift
      ;;
    -F|--format)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        printf 'Error: %s requires a value (srt, ass, or auto).\n' "$1" >&2
        exit 1
      fi
      FORMAT="$(to_lower "$2")"
      shift 2
      ;;
    --format=*)
      FORMAT="$(to_lower "${1#*=}")"
      shift
      ;;
    -o|--output)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        printf 'Error: %s requires a path.\n' "$1" >&2
        exit 1
      fi
      OUTPUT_TARGET="$2"
      shift 2
      ;;
    --output=*)
      OUTPUT_TARGET="${1#*=}"
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      printf 'Error: Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

case "$FORMAT" in
  auto|srt|ass) ;;
  *)
    printf 'Error: Unsupported --format "%s" (expected srt, ass, or auto).\n' "$FORMAT" >&2
    exit 1
    ;;
esac

if [ "${#POSITIONAL[@]}" -eq 0 ] || [ "${#POSITIONAL[@]}" -gt 2 ]; then
  printf 'Error: Expected <input-video> and optional [output-file-or-dir] (got %d positional arg(s)).\n\n' "${#POSITIONAL[@]}" >&2
  usage >&2
  exit 1
fi

INPUT_FILE="${POSITIONAL[0]}"
if [ "${#POSITIONAL[@]}" -eq 2 ]; then
  if [ -n "$OUTPUT_TARGET" ]; then
    printf 'Error: Output specified both via --output and positional argument.\n' >&2
    exit 1
  fi
  OUTPUT_TARGET="${POSITIONAL[1]}"
fi
[ -z "$OUTPUT_TARGET" ] && OUTPUT_TARGET="."

for bin in ffmpeg ffprobe; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'Error: %s not found in PATH. Please install FFmpeg.\n' "$bin" >&2
    exit 1
  fi
done

if [ ! -f "$INPUT_FILE" ]; then
  printf 'Error: Input file not found: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

if [ ! -r "$INPUT_FILE" ]; then
  printf 'Error: Input file is not readable: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

if ! ffprobe -v error -show_entries format=format_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" >/dev/null 2>&1; then
  printf 'Error: ffprobe could not read media container: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

STREAM_INDICES_RAW="$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT_FILE" | tr -d '\r')"

TRACK_COUNT=0
while IFS= read -r _line; do
  [ -n "$_line" ] && TRACK_COUNT=$((TRACK_COUNT + 1))
done <<EOF
$STREAM_INDICES_RAW
EOF

if [ "$TRACK_COUNT" -eq 0 ]; then
  printf 'Error: No soft subtitle tracks found in %s.\n' "$INPUT_FILE" >&2
  printf 'Hint: If subtitles are visible on the video frame, they are burned-in (hardcoded) pixels and cannot be extracted as a subtitle track.\n' >&2
  exit 1
fi

GLOBAL_IDXS=()
CODECS=()
LANGS=()
SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  G_IDX="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  C_NAME="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  L_NAME="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  [ -z "$C_NAME" ] && C_NAME="unknown"
  [ -z "$L_NAME" ] && L_NAME="und"
  GLOBAL_IDXS+=("$G_IDX")
  CODECS+=("$C_NAME")
  LANGS+=("$(to_lower "$L_NAME")")
  SUB_IDX=$((SUB_IDX + 1))
done

SELECTED=()
SUB_IDX=0
if [ -z "$FILTER_INDICES" ] && [ -z "$FILTER_LANGS" ]; then
  while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
    SELECTED+=(1)
    SUB_IDX=$((SUB_IDX + 1))
  done
else
  while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
    SELECTED+=(0)
    SUB_IDX=$((SUB_IDX + 1))
  done
fi

if [ -n "$FILTER_INDICES" ]; then
  OLD_IFS="$IFS"
  IFS=','
  set -f
  REQ_IDXS=($FILTER_INDICES)
  set +f
  IFS="$OLD_IFS"

  for req in "${REQ_IDXS[@]}"; do
    case "$req" in
      ''|*[!0-9]*)
        printf 'Error: Invalid subtitle track index "%s" (expected 0..%d).\n' "$req" "$((TRACK_COUNT - 1))" >&2
        exit 1
        ;;
    esac
    if [ "$req" -ge "$TRACK_COUNT" ]; then
      printf 'Error: Subtitle track index %s out of range (file has %d subtitle track(s): 0..%d).\n' \
        "$req" "$TRACK_COUNT" "$((TRACK_COUNT - 1))" >&2
      exit 1
    fi
    SELECTED[$req]=1
  done
fi

if [ -n "$FILTER_LANGS" ]; then
  OLD_IFS="$IFS"
  IFS=','
  set -f
  REQ_LANGS=($FILTER_LANGS)
  set +f
  IFS="$OLD_IFS"

  for req_lang in "${REQ_LANGS[@]}"; do
    norm_lang="$(to_lower "$req_lang")"
    [ -z "$norm_lang" ] && { printf 'Error: Empty language code in --lang.\n' >&2; exit 1; }
    matched=0
    SUB_IDX=0
    while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
      if [ "${LANGS[$SUB_IDX]}" = "$norm_lang" ]; then
        SELECTED[$SUB_IDX]=1
        matched=1
      fi
      SUB_IDX=$((SUB_IDX + 1))
    done
    if [ "$matched" -eq 0 ]; then
      printf 'Error: No subtitle track with language "%s" found in %s (available: %s).\n' \
        "$req_lang" "$INPUT_FILE" "${LANGS[*]}" >&2
      exit 1
    fi
  done
fi

SELECTED_COUNT=0
SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  [ "${SELECTED[$SUB_IDX]}" -eq 1 ] && SELECTED_COUNT=$((SELECTED_COUNT + 1))
  SUB_IDX=$((SUB_IDX + 1))
done

# Determine whether OUTPUT_TARGET is a single .srt/.ass file or a directory
TARGET_LOWER="$(to_lower "$OUTPUT_TARGET")"
IS_SINGLE_FILE=0
FILE_EXT_FORMAT=""
if [ ! -d "$OUTPUT_TARGET" ]; then
  case "$TARGET_LOWER" in
    *.srt)
      IS_SINGLE_FILE=1
      FILE_EXT_FORMAT="srt"
      ;;
    *.ass)
      IS_SINGLE_FILE=1
      FILE_EXT_FORMAT="ass"
      ;;
  esac
fi

if [ "$IS_SINGLE_FILE" -eq 1 ]; then
  if [ "$SELECTED_COUNT" -gt 1 ]; then
    printf 'Error: Output path "%s" is a single subtitle file, but %d tracks are selected.\n' "$OUTPUT_TARGET" "$SELECTED_COUNT" >&2
    printf '       Pass --index <n> to choose one track, or specify an output directory instead.\n' >&2
    exit 1
  fi
  if [ "$FORMAT" != "auto" ] && [ "$FORMAT" != "$FILE_EXT_FORMAT" ]; then
    printf 'Error: --format %s conflicts with output file extension "%s".\n' "$FORMAT" "$OUTPUT_TARGET" >&2
    exit 1
  fi
else
  mkdir -p "$OUTPUT_TARGET"
fi

IN_BASE="$(basename "$INPUT_FILE")"
IN_STEM="${IN_BASE%.*}"
[ -z "$IN_STEM" ] && IN_STEM="$IN_BASE"

EXPORTED_COUNT=0
BITMAP_SKIPPED=0

SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  if [ "${SELECTED[$SUB_IDX]}" -ne 1 ]; then
    SUB_IDX=$((SUB_IDX + 1))
    continue
  fi

  CODEC="${CODECS[$SUB_IDX]}"
  LANG_CODE="${LANGS[$SUB_IDX]}"
  G_IDX="${GLOBAL_IDXS[$SUB_IDX]}"
  KIND="$(classify_subtitle_codec "$CODEC")"

  if [ "$KIND" = "bitmap" ]; then
    HUMAN_CODEC="$(describe_bitmap_codec "$CODEC")"
    printf 'Notice: Track %d (stream #%s, lang=%s) uses image/bitmap subtitles [%s] and cannot be directly converted to .srt/.ass plain text. Use an OCR tool (e.g. Subtitle Edit or Tesseract) to convert bitmap subtitles.\n' \
      "$SUB_IDX" "$G_IDX" "$LANG_CODE" "$HUMAN_CODEC" >&2
    BITMAP_SKIPPED=$((BITMAP_SKIPPED + 1))
    SUB_IDX=$((SUB_IDX + 1))
    continue
  fi

  if [ "$KIND" = "unknown" ]; then
    printf 'Notice: Track %d (stream #%s, lang=%s) uses unsupported subtitle codec "%s"; cannot directly export to .srt/.ass.\n' \
      "$SUB_IDX" "$G_IDX" "$LANG_CODE" "$CODEC" >&2
    BITMAP_SKIPPED=$((BITMAP_SKIPPED + 1))
    SUB_IDX=$((SUB_IDX + 1))
    continue
  fi

  # Determine target format (srt or ass)
  if [ "$IS_SINGLE_FILE" -eq 1 ]; then
    TARGET_FMT="$FILE_EXT_FORMAT"
    DEST_PATH="$OUTPUT_TARGET"
    mkdir -p "$(dirname "$DEST_PATH")"
  else
    if [ "$FORMAT" = "auto" ]; then
      if [ "$CODEC" = "ass" ] || [ "$CODEC" = "ssa" ]; then
        TARGET_FMT="ass"
      else
        TARGET_FMT="srt"
      fi
    else
      TARGET_FMT="$FORMAT"
    fi
    SAFE_LANG="$(printf '%s' "$LANG_CODE" | tr -c '[:alnum:]_-' '_')"
    DEST_PATH="${OUTPUT_TARGET%/}/${IN_STEM}.track${SUB_IDX}.${SAFE_LANG}.${TARGET_FMT}"
  fi

  if [ -e "$DEST_PATH" ] && [ "$FORCE" -ne 1 ]; then
    printf 'Error: Output file already exists: %s (pass -f / --force to overwrite).\n' "$DEST_PATH" >&2
    exit 1
  fi

  # Choose copy vs text subtitle encoder
  FF_SUB_CODEC="$TARGET_FMT"
  if [ "$TARGET_FMT" = "srt" ] && [ "$CODEC" = "subrip" ]; then
    FF_SUB_CODEC="copy"
  elif [ "$TARGET_FMT" = "ass" ] && [ "$CODEC" = "ass" ]; then
    FF_SUB_CODEC="copy"
  fi

  ffmpeg -hide_banner -loglevel error -y \
    -i "$INPUT_FILE" \
    -map "0:s:${SUB_IDX}" \
    -c:s "$FF_SUB_CODEC" \
    "$DEST_PATH"

  printf 'Exported track %d (stream #%s, lang=%s, %s -> %s): %s\n' \
    "$SUB_IDX" "$G_IDX" "$LANG_CODE" "$CODEC" "$TARGET_FMT" "$DEST_PATH"
  EXPORTED_COUNT=$((EXPORTED_COUNT + 1))

  SUB_IDX=$((SUB_IDX + 1))
done

if [ "$EXPORTED_COUNT" -eq 0 ] && [ "$BITMAP_SKIPPED" -gt 0 ]; then
  exit 2
fi
