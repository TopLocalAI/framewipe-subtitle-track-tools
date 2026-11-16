English | [简体中文](soft-vs-hard-subtitles.md)

# Soft Subtitles vs. Hard Subtitles: How to Tell Them Apart and What to Do

Before trying to "remove subtitles from a video," the first step is finding out whether the subtitles are **soft subtitles** (separate subtitle tracks inside the container) or **hard subtitles** (also called **burned-in** or **hardcoded** subtitles, painted directly into the video pixels). They are stored in completely different ways and require completely different tools.

---

## 1. Soft Subtitles vs. Hard Subtitles at a Glance

| Aspect | Soft Subtitles (Subtitle Tracks) | Hard Subtitles (Burned-in / Hardcoded) |
| --- | --- | --- |
| How they are stored | Stored as separate `subtitle` stream(s) inside containers like MP4, MKV, MOV, or WebM alongside video and audio streams | Rendered directly into the pixels of each video frame when the video was exported; no separate subtitle stream exists |
| Toggleable in players? | Yes — players can turn them on/off or switch languages | No — there is no track to turn off |
| Quality impact on removal | **Zero quality loss** — remuxing (`-c copy`) drops the subtitle stream without touching video or audio | **Requires modifying pixels and re-encoding** — cannot be removed with `-c copy` |
| Processing speed | Finishes in seconds (bound only by disk I/O) | Must decode, process, and re-encode frames; takes much longer |
| Exporting to text | Text subtitle codecs export directly to `.srt` / `.ass`; bitmap subtitle codecs require OCR | Cannot be demuxed; requires video OCR over rendered frames |

> **Watch out for hybrid files**: A video can contain both at once — for example, original dialogue burned into the picture plus a translated soft subtitle track muxed into the container. Stripping the soft track removes only the separate track; any text painted into the video frames will remain.

---

## 2. Two Kinds of Soft Subtitles: Text vs. Bitmap

Even when subtitles are stored as a separate soft track, FFmpeg distinguishes two families of subtitle codecs:

1. **Text-based subtitle codecs**
   - Common codecs: `subrip` (SRT), `ass` / `ssa` (styled SubStation Alpha), `mov_text` (standard MP4/MOV text track), `webvtt` (common in WebM).
   - Characteristics: Store character strings and timestamps. FFmpeg can copy or convert them directly into `.srt` or `.ass` text files.
2. **Bitmap / image-based subtitle codecs**
   - Common codecs: Blu-ray PGS (`hdmv_pgs_subtitle`, `.sup`), DVD VobSub (`dvd_subtitle`, `.idx` + `.sub`), DVB broadcast subtitles (`dvb_subtitle`), `xsub`.
   - Characteristics: Every subtitle cue is stored as a transparent bitmap image rather than characters. They are still soft subtitle tracks — media players can toggle them off, and `-c copy` removes them losslessly — **but FFmpeg cannot directly convert them into `.srt` or `.ass` text**. Converting bitmap subtitles to text requires demuxing the image stream and running an OCR tool such as Subtitle Edit or Tesseract.

---

## 3. How to Check Which Kind You Have

Use any of the following three checks (from quickest to most definitive):

### Check 1: Toggle subtitles in a media player

Open the video in VLC, IINA, mpv, or PotPlayer and check the **Subtitles / Subtitle Track** menu:

- If subtitle tracks are listed and choosing **Disable / Off** makes the text disappear, you have **soft subtitles**.
- If no subtitle tracks appear in the menu (or if disabling all listed tracks still leaves text on screen), that visible text is **burned into the video frames** (hard subtitles).

### Check 2: Inspect streams with `ffprobe` (or this repo's script)

Run `list-subtitle-tracks.sh` from this repository:

```bash
./scripts/list-subtitle-tracks.sh your-video.mp4
```

Or run `ffprobe` directly:

```bash
ffprobe -v error -select_streams s \
  -show_entries stream=index,codec_name:stream_tags=language,title \
  -of compact your-video.mp4
```

How to read the output:

- **One or more subtitle streams listed**: The file contains soft subtitle tracks, and the `codec_name` / `TYPE` column tells you whether each track is `text` (`subrip`, `mov_text`, `ass`) or `bitmap` (`hdmv_pgs_subtitle`, `dvd_subtitle`).
- **No subtitle streams listed, while text is visible during playback**: The subtitles are **burned-in (hardcoded)**.

### Check 3: Zoom into a paused frame

Pause on a line of dialogue and zoom into the edges of the letters:

- Soft subtitles are rendered by your player at display resolution, so glyph edges stay crisp even on low-bitrate footage.
- Hardcoded subtitles went through the same lossy video encoder (`yuv420p` chroma subsampling and block compression) as the picture behind them, so zooming in usually reveals compression ringing ("mosquito noise") around the strokes.

---

## 4. How to Handle Each Type

### Case A: Soft Subtitles (Lossless Remux or Extraction)

Because soft subtitles live in their own container streams, you never need to re-encode the video:

- **Remove all soft subtitle tracks losslessly**:
  ```bash
  ./scripts/remove-subtitle-tracks.sh input.mkv output-clean.mkv
  ```
  Under the hood, this runs stream copy without re-encoding video or audio:
  ```bash
  ffmpeg -i input.mkv -map 0:v? -map 0:a? -map_metadata 0 -map_chapters 0 -c copy output-clean.mkv
  ```
- **Remove only a specific language or track index**:
  ```bash
  ./scripts/remove-subtitle-tracks.sh --lang zho input.mp4 output-en-only.mp4
  ./scripts/remove-subtitle-tracks.sh --index 0 input.mkv output.mkv
  ```
- **Export text subtitle tracks to `.srt` or `.ass`**:
  ```bash
  ./scripts/extract-subtitles.sh input.mkv ./subs
  ```
  If `list-subtitle-tracks.sh` reports `bitmap` (such as `hdmv_pgs_subtitle` or `dvd_subtitle`), demux the raw bitmap stream (for example `ffmpeg -i input.mkv -map 0:s:0 -c:s copy out.sup`) and run OCR software to produce `.srt`.

### Case B: Hard Subtitles (Crop, Mask, or Frame-by-Frame Inpainting)

Once text is baked into the pixels, stream remuxing has no effect. Practical ways to deal with burned-in subtitles are:

1. **Cropping (`crop`)**
   - Works when subtitles sit inside black letterbox bars or at the very bottom edge where trimming does not cut off important content.
   - Trade-off: Changes frame dimensions/aspect ratio and requires re-encoding the video stream.
2. **Covering / Masking (`drawbox` or blur band)**
   - Works when you plan to place a solid or blurred banner over old captions and render new captions on top.
   - Trade-off: Leaves a visible bar or blur band rather than a clean background.
3. **Frame-by-Frame Video Inpainting**
   - How it works: Detects the subtitle region across frames within a chosen time range, borrows visible real background pixels from neighboring frames where possible, fills remaining masked pixels with surrounding-matched background (inpainting), and re-encodes the cleaned video.
   - Important trade-offs: Inpainting reconstructs a **plausible background** that fits the surroundings — it does **not** recover the true original detail that was hidden behind the text. When the scene behind the subtitles moves quickly or has complex textures, the filled region may show some flicker or ghosting.

#### Cleaning Up Burned-in Subtitles Locally with FrameWipe

If your clip has burned-in subtitles and you want a local desktop workflow to paint them out without uploading footage, you can use **[FrameWipe](https://framewipe.com)** (subtitle removal guide: [framewipe.com/remove-subtitles-from-video](https://framewipe.com/remove-subtitles-from-video)):

- **Offline on your computer**: Runs locally on Mac with Apple Silicon (macOS 13 or later; Intel Macs are not supported) and Windows 10/11 (64-bit x64). Files are never uploaded, no account is needed, and results are always saved as new files without overwriting originals.
- **Burned-in and soft subtitles**: Opens MP4, MOV, and WebM video files (MKV is not supported yet — if you have an MKV file, you can remux to MP4 first when codecs allow). For burned-in subtitles, FrameWipe detects the subtitle area, lets you choose a time range, renders a 2-second preview before processing the whole clip, borrows visible pixels from neighboring frames, and fills what remains. If a file carries a separate soft subtitle track, FrameWipe can also remove that track in one click without re-encoding.
- **Other cleanup tools and availability**: FrameWipe also erases text and clutter from photos (with a bundled Fast MI-GAN engine and an optional ~200 MB LaMa Quality model download), blurs/pixelates/solid-fills faces in photos and video (listing possible missed moments in video for review), and offers an optional object tracking add-on on Mac only (Windows does not support object tracking yet, and the Windows installer is not code-signed). It is sold on Patreon as a one-time purchase of US$39.99 with a 7-day no-questions-asked full refund.
