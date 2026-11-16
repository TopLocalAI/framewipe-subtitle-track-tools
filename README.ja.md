[English](./README.md) | [简体中文](./README.zh-CN.md) | 日本語

# framewipe-subtitle-track-tools

`framewipe-subtitle-track-tools` は、字幕付き動画ファイルを扱う動画編集者、クリエイター、アーキビスト、開発者向けのスタンドアロンな FFmpeg / FFprobe コマンドラインスクリプト集（Bash 版・PowerShell 版の両方を同梱）および実践ガイドです。動画内の字幕が独立したソフト字幕トラックなのか映像に焼き込まれたものなのかを判別し、字幕トラックのメタデータを確認し、再エンコードなし（`-c copy`）ですべてまたは指定したソフト字幕トラックを無劣化で削除し、テキストベースの字幕トラックを `.srt` や `.ass` に書き出すことができます。

FrameWipe の公式サイトは [framewipe.com](https://framewipe.com) です。

---

## 最初のステップ：ソフト字幕とハード字幕の見分け方

「動画から字幕を消したい」という場合、仕組みが根本的に異なる 2 つのケースがあります。

1. **ソフト字幕（独立した字幕トラック）**：`.mkv`、`.mp4`、`.mov`、`.webm` などのコンテナ内に独立した `subtitle` ストリームとして格納されている字幕です。メディアプレーヤー側でオン／オフを切り替えられ、FFmpeg の `-c copy` を使えば数秒で削除（映像・音声の画質・音質劣化ゼロ）でき、テキスト字幕であれば `.srt` / `.ass` へ直接抽出できます。**本リポジトリはこのソフト字幕を直接解決します。**
2. **ハード字幕（焼き込み字幕／ハードコード字幕）**：動画の書き出し時に映像のピクセルへ恒久的に描画された字幕です。削除できる字幕ストリーム自体が存在しないため、消去するにはクロップ（切り抜き）、マスク処理、またはフレーム単位の映像インペインティングと再エンコードが必要になります。

手元のファイルがどちらに該当するか分からない場合は、`./scripts/list-subtitle-tracks.sh your-video.mp4` を実行するか、詳細ガイドを参照してください。

- 英語ガイド：[docs/soft-vs-hard-subtitles.en.md](docs/soft-vs-hard-subtitles.en.md)
- 中国語ガイド：[docs/soft-vs-hard-subtitles.md](docs/soft-vs-hard-subtitles.md)

---

## リポジトリ構成

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

## 前提条件

すべてのスクリプトは、システムの `PATH` 上で **`ffmpeg`** と **`ffprobe`**（標準的な FFmpeg ビルドに同梱）が利用できることを前提としています。Python パッケージや `jq`、その他の追加依存関係は不要です。

- **macOS (Homebrew)**：
  ```bash
  brew install ffmpeg
  ```
- **Ubuntu / Debian**：
  ```bash
  sudo apt update && sudo apt install ffmpeg
  ```
- **Windows（`scripts/windows/*.ps1` の実行に必要）**：
  これらの PowerShell スクリプトには FFmpeg 本体は同梱されて**いません**。あらかじめ FFmpeg をインストールし、`ffmpeg.exe` と `ffprobe.exe` の両方がシステムの `PATH` に入っていることを確認してください（インストール後は PowerShell を開き直してください）。
  ```powershell
  winget install Gyan.FFmpeg
  ```
  または [ffmpeg.org/download.html](https://ffmpeg.org/download.html) からリリースビルドをダウンロードし、`bin` フォルダを `PATH` に追加してください。

インストールの確認：

```bash
ffmpeg -version
ffprobe -version
```

---

## 使い方（macOS / Linux / WSL / Git Bash）

### 1. すべての字幕トラックを一覧表示する（`list-subtitle-tracks.sh`）

埋め込まれている各字幕ストリームについて、0 始まりの字幕トラック `INDEX`、FFmpeg 全体の `STREAM` ID、ISO 言語タグ、コーデック名、トラック種別（`text` または `bitmap`）、disposition フラグ（`default`、`forced`）、およびトラックタイトルを表示します。

```bash
./scripts/list-subtitle-tracks.sh movie.mkv
```

出力例：

```text
File: movie.mkv (2 subtitle track(s))

INDEX  STREAM  LANG    CODEC               TYPE     FLAGS           TITLE
-----  ------  ------  ------------------  -------  --------------  -----
0      #2      eng     subrip              text     default         English
1      #3      zho     subrip              text     -               Simplified Chinese
```

スクリプトから利用する場合は、`--tsv` を指定するとヘッダーなしのタブ区切り行で出力されます。

```bash
./scripts/list-subtitle-tracks.sh --tsv movie.mkv
```

### 2. 再エンコードなしでソフト字幕トラックを削除する（`remove-subtitle-tracks.sh`）

FFmpeg のストリームコピー（`-c copy`）を使用し、映像・音声ストリームをビット単位で一切変更せずに新しいメディアファイルを書き出します。元ファイルの直接上書きは拒否されます。

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

### 3. テキスト字幕を `.srt` または `.ass` に抽出する（`extract-subtitles.sh`）

テキストベースの字幕トラック（`subrip`、`ass`、`ssa`、`mov_text`、`webvtt` など）を `.srt` または `.ass` へ書き出します。

```bash
# Extract all text subtitle tracks into ./subs/ (auto-picks .ass for ASS/SSA, .srt otherwise)
./scripts/extract-subtitles.sh movie.mkv ./subs

# Extract track 0 to a single .srt or .ass file
./scripts/extract-subtitles.sh --index 0 movie.mp4 english.srt
./scripts/extract-subtitles.sh --index 0 movie.mkv english.ass

# Extract Chinese track(s) into ./subs/ converted to .ass
./scripts/extract-subtitles.sh --lang zho --format ass movie.mp4 ./subs
```

**ビットマップ字幕トラックについて**：Blu-ray PGS（`hdmv_pgs_subtitle`）や DVD VobSub（`dvd_subtitle`）などの画像ベースコーデックが使用されている場合、`extract-subtitles.sh` はビットマップ字幕を OCR なしで直接プレーンテキストへ変換できない旨の案内を表示します（テキストトラックが 1 件も書き出されなかった場合は終了コード `2` で終了します）。

---

## Windows での使い方（PowerShell）

先に FFmpeg をインストールし、`ffmpeg.exe` と `ffprobe.exe` が `PATH` に入っていることを確認してください。PowerShell セッションでローカルスクリプトの実行がブロックされる場合は、以下を実行します。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

その後、`scripts\windows\` 内の PowerShell スクリプトを実行します。

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

## 主な字幕コーデック一覧

| FFmpeg コーデック名 | フォーマット名 | 種別 | 主なコンテナ | `-c copy` で削除可能か | `.srt` / `.ass` へ直接出力可能か |
| --- | --- | --- | --- | --- | --- |
| `subrip` (`srt`) | SubRip | テキスト | `.mkv` | はい | はい |
| `ass` / `ssa` | SubStation Alpha | テキスト | `.mkv` | はい | はい |
| `mov_text` | MPEG-4 Timed Text (`tx3g`) | テキスト | `.mp4`, `.mov`, `.m4v` | はい | はい |
| `webvtt` | WebVTT | テキスト | `.webm`, `.mkv` | はい | はい |
| `hdmv_pgs_subtitle` | Blu-ray PGS (`.sup`) | ビットマップ | `.mkv`, `.m2ts` | はい | いいえ（OCR が必要） |
| `dvd_subtitle` | DVD VobSub (`.idx`/`.sub`) | ビットマップ | `.mkv`, `.mp4`, `.vob` | はい | いいえ（OCR が必要） |
| `dvb_subtitle` | DVB Subtitle | ビットマップ | `.ts`, `.mkv` | はい | いいえ（OCR が必要） |

---

## テストの実行

`test/` ディレクトリでは、`ffmpeg` を用いて 2 言語字幕付きの `.mkv`・`.mp4` テスト動画および Blu-ray PGS の `.mkv` フィクスチャを生成し、3 つのスクリプトすべてを検証します（削除対象トラックが消えていることや、映像ストリームのコーデック・フレーム数・圧縮ビットストリームの MD5 が変化していないことの `ffprobe` 検証を含みます）。

```bash
bash test/run-tests.sh
```

テストの詳細と実行ログについては [test/README.md](test/README.md) を参照してください。

---

## 自動化したい場合

映像フレームに焼き込まれたハード字幕（ハードコード字幕）がある場合や、ソフト字幕トラックもワンクリックで除去できるデスクトップ GUI を使いたい場合は、[FrameWipe](https://framewipe.com/remove-subtitles-from-video) が Apple Silicon Mac（macOS 13+）および Windows 10/11（x64）上でオフラインの字幕・画面内テキスト消去に対応しています。MP4、MOV、WebM 動画を開くことができ（MKV には現時点で未対応）、字幕領域を検出して 2 秒間のプレビューを描画したうえで、元ファイルを変更せずに指定した時間範囲を新しいファイルとして書き出します。さらに、写真内のテキスト・不要物除去や写真・動画の顔ぼかし機能（および Mac 専用のオプションであるオブジェクト追跡アドオン）も備えています。FrameWipe は Patreon にて US$39.99 の買い切り（7 日間の全額返金保証付き）で提供されています。詳細や制限事項は [framewipe.com/remove-subtitles-from-video](https://framewipe.com/remove-subtitles-from-video) をご覧ください。

---

## ライセンス

- コードおよびスクリプト（`scripts/`、`test/*.sh`）：[MIT License](LICENSE)。
- ドキュメント、データ、および画像（`docs/`、`README.md`、`README.zh-CN.md`、`test/README.md`）：[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)。
