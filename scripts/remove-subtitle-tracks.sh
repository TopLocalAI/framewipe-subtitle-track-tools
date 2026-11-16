#!/usr/bin/env bash
# remove-subtitle-tracks.sh — Losslessly remove all or selected soft subtitle tracks (-c copy).
# Compatible with Bash 3.2+ (macOS default bash) and Bash 4/5+ (Linux/WSL/Git Bash).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  remove-subtitle-tracks.sh [options] <input-video> <output-video>

Description:
  Losslessly removes embedded (soft) subtitle tracks from <input-video> and
  writes a new file to <output-video> using FFmpeg stream copy (-c copy).
  Video and audio streams are copied bit-for-bit without re-encoding.

  By default (or with --all), all subtitle tracks are removed. Use --index
  and/or --lang to remove only specific subtitle tracks while keeping others.

Options:
  -a, --all             Remove all subtitle tracks (default when --index/--lang omitted)
  -i, --index <list>    Remove 0-based subtitle track index(es), comma-separated
                        (matches INDEX from list-subtitle-tracks.sh, e.g. 0 or 0,2)
  -l, --lang <list>     Remove subtitle track(s) by language tag, comma-separated
                        (case-insensitive ISO 639 code, e.g. eng or eng,zho)
  -f, --force           Overwrite <output-video> if it already exists
  -h, --help            Show this help message and exit

Examples:
  # Remove all soft subtitle tracks
  ./scripts/remove-subtitle-tracks.sh input.mkv output-clean.mkv

  # Remove only Chinese subtitle track(s), keep other subtitle tracks
  ./scripts/remove-subtitle-tracks.sh --lang zho input.mp4 output-en-only.mp4

  # Remove subtitle track index 0
  ./scripts/remove-subtitle-tracks.sh --index 0 input.mkv output.mkv
EOF
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

canonical_file_path() {
  local p="$1"
  local dir base abs_dir
  dir="$(dirname "$p")"
  base="$(basename "$p")"
  abs_dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "$abs_dir" "$base"
}

REMOVE_ALL=0
FORCE=0
FILTER_INDICES=""
FILTER_LANGS=""
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -a|--all)
      REMOVE_ALL=1
      shift
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
      if [ -n "$FILTER_INDICES" ]; then
        FILTER_INDICES="${FILTER_INDICES},$2"
      else
        FILTER_INDICES="$2"
      fi
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
      if [ -n "$FILTER_LANGS" ]; then
        FILTER_LANGS="${FILTER_LANGS},$2"
      else
        FILTER_LANGS="$2"
      fi
      shift 2
      ;;
    --lang=*)
      val="${1#*=}"
      [ -z "$val" ] && { printf 'Error: --lang requires a value.\n' >&2; exit 1; }
      FILTER_LANGS="${FILTER_LANGS:+$FILTER_LANGS,}$val"
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

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  printf 'Error: Expected <input-video> and <output-video> arguments (got %d).\n\n' "${#POSITIONAL[@]}" >&2
  usage >&2
  exit 1
fi

INPUT_FILE="${POSITIONAL[0]}"
OUTPUT_FILE="${POSITIONAL[1]}"

if [ "$REMOVE_ALL" -eq 1 ] && { [ -n "$FILTER_INDICES" ] || [ -n "$FILTER_LANGS" ]; }; then
  printf 'Error: Cannot combine --all with --index or --lang.\n' >&2
  exit 1
fi

if [ -z "$FILTER_INDICES" ] && [ -z "$FILTER_LANGS" ]; then
  REMOVE_ALL=1
fi

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

OUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUT_DIR"

ABS_IN="$(canonical_file_path "$INPUT_FILE")"
ABS_OUT="$(canonical_file_path "$OUTPUT_FILE")"

if [ "$ABS_IN" = "$ABS_OUT" ]; then
  printf 'Error: Output path must differ from input path (refusing to overwrite source file).\n' >&2
  exit 1
fi

if [ -e "$OUTPUT_FILE" ] && [ "$FORCE" -ne 1 ]; then
  printf 'Error: Output file already exists: %s (pass -f / --force to overwrite).\n' "$OUTPUT_FILE" >&2
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
  printf 'Hint: If text is visible on the video frame, it is burned into the pixels (hardcoded) and cannot be stripped with -c copy.\n' >&2
  exit 1
fi

TRACK_LANGS=()
SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  L_TAG="$(ffprobe -v error -select_streams "s:${SUB_IDX}" -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | tr -d '\r' | head -n 1)"
  [ -z "$L_TAG" ] && L_TAG="und"
  TRACK_LANGS+=("$(to_lower "$L_TAG")")
  SUB_IDX=$((SUB_IDX + 1))
done

# Mark which tracks (0..TRACK_COUNT-1) should be removed: 1=remove, 0=keep
REMOVE_FLAGS=()
SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  if [ "$REMOVE_ALL" -eq 1 ]; then
    REMOVE_FLAGS+=(1)
  else
    REMOVE_FLAGS+=(0)
  fi
  SUB_IDX=$((SUB_IDX + 1))
done

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
    REMOVE_FLAGS[$req]=1
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
    if [ -z "$norm_lang" ]; then
      printf 'Error: Empty language code in --lang.\n' >&2
      exit 1
    fi
    matched=0
    SUB_IDX=0
    while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
      if [ "${TRACK_LANGS[$SUB_IDX]}" = "$norm_lang" ]; then
        REMOVE_FLAGS[$SUB_IDX]=1
        matched=1
      fi
      SUB_IDX=$((SUB_IDX + 1))
    done
    if [ "$matched" -eq 0 ]; then
      printf 'Error: No subtitle track with language "%s" found in %s (available: %s).\n' \
        "$req_lang" "$INPUT_FILE" "${TRACK_LANGS[*]}" >&2
      exit 1
    fi
  done
fi

MAP_ARGS=("-map" "0:v?" "-map" "0:a?")
REMOVED_COUNT=0
KEPT_COUNT=0

SUB_IDX=0
while [ "$SUB_IDX" -lt "$TRACK_COUNT" ]; do
  if [ "${REMOVE_FLAGS[$SUB_IDX]}" -eq 1 ]; then
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
  else
    MAP_ARGS+=("-map" "0:s:${SUB_IDX}")
    KEPT_COUNT=$((KEPT_COUNT + 1))
  fi
  SUB_IDX=$((SUB_IDX + 1))
done

OUT_BASE="$(basename "$OUTPUT_FILE")"
OUT_EXT=""
case "$OUT_BASE" in
  *.*)
    OUT_EXT=".${OUT_BASE##*.}"
    OUT_STEM="${OUT_BASE%.*}"
    ;;
  *)
    OUT_STEM="$OUT_BASE"
    ;;
esac

# Preserve font attachments on Matroska outputs when keeping subtitle tracks
OUT_EXT_LOWER="$(to_lower "$OUT_EXT")"
if [ "$KEPT_COUNT" -gt 0 ] && { [ "$OUT_EXT_LOWER" = ".mkv" ] || [ "$OUT_EXT_LOWER" = ".mks" ]; }; then
  MAP_ARGS+=("-map" "0:t?")
fi

TMP_OUT="${OUT_DIR}/.${OUT_STEM}.tmp.$$${OUT_EXT}"
cleanup_tmp() {
  if [ -n "${TMP_OUT:-}" ] && [ -e "$TMP_OUT" ]; then
    rm -f "$TMP_OUT"
  fi
}
trap cleanup_tmp EXIT INT TERM

ffmpeg -hide_banner -loglevel error -y \
  -i "$INPUT_FILE" \
  "${MAP_ARGS[@]}" \
  -map_metadata 0 \
  -map_chapters 0 \
  -c copy \
  "$TMP_OUT"

mv -f "$TMP_OUT" "$OUTPUT_FILE"
trap - EXIT INT TERM

printf 'Removed %d subtitle track(s), kept %d subtitle track(s) -> %s\n' \
  "$REMOVED_COUNT" "$KEPT_COUNT" "$OUTPUT_FILE"
