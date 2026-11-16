#!/usr/bin/env bash
# run-tests.sh — End-to-end verification of list/remove/extract scripts on MKV and MP4.
# Compatible with Bash 3.2+ and Bash 4/5+.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

LIST_SH="${REPO_ROOT}/scripts/list-subtitle-tracks.sh"
REMOVE_SH="${REPO_ROOT}/scripts/remove-subtitle-tracks.sh"
EXTRACT_SH="${REPO_ROOT}/scripts/extract-subtitles.sh"
GEN_SH="${SCRIPT_DIR}/generate-fixtures.sh"

FIXTURES_DIR="${SCRIPT_DIR}/fixtures"
OUT_DIR="${SCRIPT_DIR}/output"

PASS_COUNT=0

cleanup() {
  if [ "${KEEP_ARTIFACTS:-0}" != "1" ]; then
    rm -rf "$FIXTURES_DIR" "$OUT_DIR"
  fi
}
trap cleanup EXIT INT TERM

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '  [PASS] %s\n' "$1"
}

fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" = "$actual" ]; then
    pass "${label} (${actual})"
  else
    fail "${label}: expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*)
      pass "$label"
      ;;
    *)
      fail "${label}: output did not contain '${needle}'"
      ;;
  esac
}

subtitle_count() {
  local file="$1"
  local raw count=0
  raw="$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$file" | tr -d '\r')"
  while IFS= read -r line; do
    [ -n "$line" ] && count=$((count + 1))
  done <<EOF
$raw
EOF
  printf '%d' "$count"
}

subtitle_langs() {
  local file="$1"
  ffprobe -v error -select_streams s -show_entries stream_tags=language -of csv=p=0 "$file" | tr -d '\r' | tr '\n' ',' | sed 's/,$//'
}

video_codec() {
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1" | tr -d '\r' | head -n 1
}

video_frame_count() {
  ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=noprint_wrappers=1:nokey=1 "$1" | tr -d '\r' | head -n 1
}

video_bitstream_md5() {
  ffmpeg -v error -i "$1" -map 0:v:0 -c copy -f md5 - | tr -d '\r' | head -n 1
}

rm -rf "$FIXTURES_DIR" "$OUT_DIR"
mkdir -p "$FIXTURES_DIR" "$OUT_DIR"

printf '============================================================\n'
printf '1. Generating MKV, MP4, and PGS bitmap fixtures via FFmpeg\n'
printf '============================================================\n'
bash "$GEN_SH" "$FIXTURES_DIR"

for container in mkv mp4; do
  printf '\n============================================================\n'
  printf '2. Container suite: .%s\n' "$container"
  printf '============================================================\n'

  SRC="${FIXTURES_DIR}/sample-dual-subs.${container}"
  EXPECTED_SUB_CODEC="subrip"
  [ "$container" = "mp4" ] && EXPECTED_SUB_CODEC="mov_text"

  ORIG_VCODEC="$(video_codec "$SRC")"
  ORIG_VFRAMES="$(video_frame_count "$SRC")"
  ORIG_VMD5="$(video_bitstream_md5 "$SRC")"
  ORIG_SUBS="$(subtitle_count "$SRC")"

  printf 'Baseline (%s): video_codec=%s, video_frames=%s, subtitle_tracks=%s, video_stream_%s\n' \
    "$(basename "$SRC")" "$ORIG_VCODEC" "$ORIG_VFRAMES" "$ORIG_SUBS" "$ORIG_VMD5"
  assert_eq "2" "$ORIG_SUBS" "${container}: initial subtitle track count"

  # --- 2a. list-subtitle-tracks.sh ---
  printf '\n--- [%s] list-subtitle-tracks.sh ---\n' "$container"
  LIST_OUT="$(bash "$LIST_SH" "$SRC")"
  printf '%s\n' "$LIST_OUT"
  assert_contains "$LIST_OUT" "$EXPECTED_SUB_CODEC" "${container}: lists codec ${EXPECTED_SUB_CODEC}"
  assert_contains "$LIST_OUT" "eng" "${container}: lists language eng"
  assert_contains "$LIST_OUT" "zho" "${container}: lists language zho"
  assert_contains "$LIST_OUT" "English" "${container}: lists title 'English'"
  assert_contains "$LIST_OUT" "Simplified Chinese" "${container}: lists title 'Simplified Chinese'"

  # --- 2b. remove-subtitle-tracks.sh (--lang zho) ---
  printf '\n--- [%s] remove-subtitle-tracks.sh --lang zho ---\n' "$container"
  OUT_LANG="${OUT_DIR}/removed-zho.${container}"
  bash "$REMOVE_SH" --lang zho "$SRC" "$OUT_LANG"
  assert_eq "1" "$(subtitle_count "$OUT_LANG")" "${container}: subtitle count after --lang zho"
  assert_eq "eng" "$(subtitle_langs "$OUT_LANG")" "${container}: remaining subtitle language is eng"
  assert_eq "$ORIG_VCODEC" "$(video_codec "$OUT_LANG")" "${container}: video codec unchanged (not re-encoded)"
  assert_eq "$ORIG_VFRAMES" "$(video_frame_count "$OUT_LANG")" "${container}: video frame count unchanged"
  assert_eq "$ORIG_VMD5" "$(video_bitstream_md5 "$OUT_LANG")" "${container}: video compressed bitstream MD5 identical"

  # --- 2c. remove-subtitle-tracks.sh (--index 0) ---
  printf '\n--- [%s] remove-subtitle-tracks.sh --index 0 ---\n' "$container"
  OUT_IDX="${OUT_DIR}/removed-idx0.${container}"
  bash "$REMOVE_SH" --index 0 "$SRC" "$OUT_IDX"
  assert_eq "1" "$(subtitle_count "$OUT_IDX")" "${container}: subtitle count after --index 0"
  assert_eq "zho" "$(subtitle_langs "$OUT_IDX")" "${container}: remaining subtitle language is zho"
  assert_eq "$ORIG_VCODEC" "$(video_codec "$OUT_IDX")" "${container}: video codec unchanged (not re-encoded)"
  assert_eq "$ORIG_VFRAMES" "$(video_frame_count "$OUT_IDX")" "${container}: video frame count unchanged"
  assert_eq "$ORIG_VMD5" "$(video_bitstream_md5 "$OUT_IDX")" "${container}: video compressed bitstream MD5 identical"

  # --- 2d. remove-subtitle-tracks.sh (--all / default) ---
  printf '\n--- [%s] remove-subtitle-tracks.sh (remove all) ---\n' "$container"
  OUT_ALL="${OUT_DIR}/removed-all.${container}"
  bash "$REMOVE_SH" "$SRC" "$OUT_ALL"
  assert_eq "0" "$(subtitle_count "$OUT_ALL")" "${container}: subtitle count after removing all tracks"
  assert_eq "$ORIG_VCODEC" "$(video_codec "$OUT_ALL")" "${container}: video codec unchanged (not re-encoded)"
  assert_eq "$ORIG_VFRAMES" "$(video_frame_count "$OUT_ALL")" "${container}: video frame count unchanged"
  assert_eq "$ORIG_VMD5" "$(video_bitstream_md5 "$OUT_ALL")" "${container}: video compressed bitstream MD5 identical"
  EMPTY_LIST_OUT="$(bash "$LIST_SH" "$OUT_ALL")"
  assert_contains "$EMPTY_LIST_OUT" "No subtitle tracks found" "${container}: list-subtitle-tracks reports 0 tracks on stripped file"

  # --- 2e. extract-subtitles.sh (.srt batch + .ass single file) ---
  printf '\n--- [%s] extract-subtitles.sh (.srt & .ass) ---\n' "$container"
  SUB_EXPORT_DIR="${OUT_DIR}/subs-${container}"
  bash "$EXTRACT_SH" "$SRC" "$SUB_EXPORT_DIR"
  EN_EXPORT="${SUB_EXPORT_DIR}/sample-dual-subs.track0.eng.srt"
  ZH_EXPORT="${SUB_EXPORT_DIR}/sample-dual-subs.track1.zho.srt"
  [ -s "$EN_EXPORT" ] || fail "${container}: expected non-empty ${EN_EXPORT}"
  [ -s "$ZH_EXPORT" ] || fail "${container}: expected non-empty ${ZH_EXPORT}"
  assert_contains "$(cat "$EN_EXPORT")" "Welcome to the subtitle track test." "${container}: exported English .srt text verified"
  assert_contains "$(cat "$ZH_EXPORT")" "欢迎运行软字幕轨道测试。" "${container}: exported Chinese .srt text verified"

  ASS_EXPORT="${OUT_DIR}/track0-${container}.ass"
  bash "$EXTRACT_SH" --index 0 "$SRC" "$ASS_EXPORT"
  [ -s "$ASS_EXPORT" ] || fail "${container}: expected non-empty ${ASS_EXPORT}"
  ASS_CONTENT="$(cat "$ASS_EXPORT")"
  assert_contains "$ASS_CONTENT" "[Script Info]" "${container}: exported .ass header verified"
  assert_contains "$ASS_CONTENT" "Welcome to the subtitle track test." "${container}: exported .ass dialogue verified"
done

printf '\n============================================================\n'
printf '3. Bitmap subtitle detection (Blu-ray PGS in .mkv)\n'
printf '============================================================\n'
BITMAP_SRC="${FIXTURES_DIR}/sample-pgs-bitmap.mkv"
BITMAP_LIST="$(bash "$LIST_SH" "$BITMAP_SRC")"
printf '%s\n' "$BITMAP_LIST"
assert_contains "$BITMAP_LIST" "hdmv_pgs_subtitle" "PGS fixture codec detected"
assert_contains "$BITMAP_LIST" "bitmap" "PGS fixture classified as bitmap"

set +e
BITMAP_ERR="$(bash "$EXTRACT_SH" "$BITMAP_SRC" "${OUT_DIR}/bitmap-subs" 2>&1)"
BITMAP_RC=$?
set -e
printf '%s\n' "$BITMAP_ERR"
assert_eq "2" "$BITMAP_RC" "extract-subtitles exits with code 2 on bitmap-only subtitle track"
assert_contains "$BITMAP_ERR" "cannot be directly converted to .srt/.ass plain text" "extract-subtitles prints clear OCR notice for bitmap track"

printf '\n============================================================\n'
printf '4. Parameter & safety validation checks\n'
printf '============================================================\n'
if bash "$REMOVE_SH" "${FIXTURES_DIR}/sample-dual-subs.mkv" "${FIXTURES_DIR}/sample-dual-subs.mkv" >/dev/null 2>&1; then
  fail "remove-subtitle-tracks should reject identical input and output paths"
else
  pass "remove-subtitle-tracks rejects in-place overwrite of input file"
fi

if bash "$REMOVE_SH" --index 9 "${FIXTURES_DIR}/sample-dual-subs.mp4" "${OUT_DIR}/bad.mp4" >/dev/null 2>&1; then
  fail "remove-subtitle-tracks should reject out-of-range --index"
else
  pass "remove-subtitle-tracks rejects out-of-range --index"
fi

if bash "$EXTRACT_SH" --lang jpn "${FIXTURES_DIR}/sample-dual-subs.mkv" "${OUT_DIR}/bad-subs" >/dev/null 2>&1; then
  fail "extract-subtitles should reject non-existent --lang"
else
  pass "extract-subtitles rejects missing language code"
fi

printf '\n============================================================\n'
printf 'ALL %d ASSERTIONS PASSED (MKV + MP4 + PGS bitmap + safety)\n' "$PASS_COUNT"
printf '============================================================\n'
