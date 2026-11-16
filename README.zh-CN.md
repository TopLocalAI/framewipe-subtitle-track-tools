[English](README.md) | 简体中文 | [日本語](./README.ja.md)

# framewipe-subtitle-track-tools

`framewipe-subtitle-track-tools` 是一套基于 FFmpeg / FFprobe 的独立命令行脚本（同时提供 Bash 与 PowerShell 版本）及配套说明文档，面向需要处理视频字幕的剪辑人员、内容创作者、资料整理者与开发者。你可以用它判断视频里的字幕属于软字幕还是硬字幕、列出文件内所有字幕轨的元数据、在不重新编码音视频的前提下（`-c copy`）无损移除全部或指定字幕轨，以及把文本类字幕轨导出为 `.srt` 或 `.ass` 文件。

FrameWipe 的官方网站是 [framewipe.com](https://framewipe.com)。

---

## 第一步：先分清软字幕还是硬字幕

很多人想“去掉视频字幕”时，首先要区分两种截然不同的字幕形态：

1. **软字幕（独立字幕轨）**：字幕作为独立的 `subtitle` 数据流封装在 `.mkv`、`.mp4`、`.mov`、`.webm` 等容器文件里，播放器可以自由开关，也能用 FFmpeg 的 `-c copy` 在几秒内无损移除（音视频零画质损失），或直接把文本字幕导出为 `.srt` / `.ass`。**本仓库直接解决软字幕这一半问题。**
2. **硬字幕（烧录字幕 / 内嵌压制字幕）**：文字在导出视频时已经被画进每一帧的像素里，容器中没有独立的字幕流可供剔除；要去除只能做画面裁切、遮盖，或者逐帧画面修复（inpainting）并重新编码。

不确定手头的视频属于哪一种？可以先运行 `./scripts/list-subtitle-tracks.sh your-video.mp4`，或阅读详细判断与处理指南：

- 中文指南：[docs/soft-vs-hard-subtitles.md](docs/soft-vs-hard-subtitles.md)
- English guide: [docs/soft-vs-hard-subtitles.en.md](docs/soft-vs-hard-subtitles.en.md)

---

## 仓库目录结构

```text
framewipe-subtitle-track-tools/
├── scripts/
│   ├── list-subtitle-tracks.sh          # Bash：列出全部字幕轨（索引、语言、编码格式、标题）
│   ├── remove-subtitle-tracks.sh        # Bash：无损移除全部或指定语言/索引字幕轨（-c copy）
│   ├── extract-subtitles.sh             # Bash：导出文本字幕为 .srt/.ass，图形字幕给出 OCR 提示
│   └── windows/
│       ├── list-subtitle-tracks.ps1     # Windows PowerShell 同功能脚本
│       ├── remove-subtitle-tracks.ps1   # Windows PowerShell 同功能脚本
│       └── extract-subtitles.ps1        # Windows PowerShell 同功能脚本
├── docs/
│   ├── soft-vs-hard-subtitles.md        # 软字幕与硬字幕判断及处理说明（中文）
│   └── soft-vs-hard-subtitles.en.md     # How to identify & handle soft vs. hard subtitles (EN)
├── test/
│   ├── generate-fixtures.sh             # 用 ffmpeg 生成含双语字幕轨的 MKV/MP4 与 PGS 测试视频
│   ├── run-tests.sh                     # 自动化验证脚本（共 57 项断言）
│   └── README.md                        # 测试说明与实测输出记录
└── LICENSE                              # MIT 许可证（代码与脚本部分）
```

---

## 环境准备

所有脚本仅依赖系统 `PATH` 中的 **`ffmpeg`** 与 **`ffprobe`**（标准 FFmpeg 安装包均同时包含这两项），无需安装额外的 Python 库或 `jq`。

- **macOS（Homebrew）**：
  ```bash
  brew install ffmpeg
  ```
- **Ubuntu / Debian**：
  ```bash
  sudo apt update && sudo apt install ffmpeg
  ```
- **Windows（运行 `scripts/windows/*.ps1` 前必装）**：
  本仓库的 PowerShell 脚本**不附带** FFmpeg，使用前请自行安装 FFmpeg，并确保 `ffmpeg.exe` 和 `ffprobe.exe` 已加入系统环境变量 `PATH`（安装后请重新打开 PowerShell 窗口）：
  ```powershell
  winget install Gyan.FFmpeg
  ```
  也可以从 [ffmpeg.org/download.html](https://ffmpeg.org/download.html) 下载编译包，将其 `bin` 目录手动添加到系统 `PATH`。

检查是否安装成功：

```bash
ffmpeg -version
ffprobe -version
```

---

## 使用说明（macOS / Linux / WSL / Git Bash）

### 1. 列出视频里的所有字幕轨（`list-subtitle-tracks.sh`）

查看视频中每一条软字幕轨的 0 起始字幕索引（`INDEX`）、FFmpeg 全局流编号（`STREAM`）、语言代码（`LANG`）、编码格式（`CODEC`）、轨道类型（`text` 文本 / `bitmap` 图形）、标记（`default` / `forced`）与标题（`TITLE`）：

```bash
./scripts/list-subtitle-tracks.sh movie.mkv
```

示例输出：

```text
File: movie.mkv (2 subtitle track(s))

INDEX  STREAM  LANG    CODEC               TYPE     FLAGS           TITLE
-----  ------  ------  ------------------  -------  --------------  -----
0      #2      eng     subrip              text     default         English
1      #3      zho     subrip              text     -               Simplified Chinese
```

如需在脚本里按制表符解析，可加 `--tsv` 输出无表头的纯数据行：

```bash
./scripts/list-subtitle-tracks.sh --tsv movie.mkv
```

### 2. 无损移除软字幕轨（`remove-subtitle-tracks.sh`）

使用 FFmpeg 流复制（`-c copy`）写出新视频文件，视频流与音频流逐字节原样保留，不重新编码，且禁止直接覆盖原输入文件。

```bash
# 移除全部软字幕轨
./scripts/remove-subtitle-tracks.sh input.mkv output-clean.mkv
./scripts/remove-subtitle-tracks.sh input.mp4 output-clean.mp4

# 只移除指定语言（忽略大小写，如 zho/eng），保留其余字幕轨
./scripts/remove-subtitle-tracks.sh --lang zho input.mp4 output-en-only.mp4

# 只移除指定索引（对应 list-subtitle-tracks.sh 输出的 INDEX 列）
./scripts/remove-subtitle-tracks.sh --index 0 input.mkv output.mkv
./scripts/remove-subtitle-tracks.sh --index 0,2 --force input.mkv output.mkv
```

### 3. 导出文本字幕轨为 `.srt` 或 `.ass`（`extract-subtitles.sh`）

将文本类字幕轨（`subrip`、`ass`、`ssa`、`mov_text`、`webvtt` 等）导出为 `.srt` 或 `.ass` 文件：

```bash
# 导出全部文本字幕轨到 ./subs/ 目录（默认保留 ASS/SSA 为 .ass，其余导出为 .srt）
./scripts/extract-subtitles.sh movie.mkv ./subs

# 将第 0 条字幕轨导出为单个 .srt 或 .ass 文件
./scripts/extract-subtitles.sh --index 0 movie.mp4 english.srt
./scripts/extract-subtitles.sh --index 0 movie.mkv english.ass

# 按语言筛选并强制转换为 .ass 格式
./scripts/extract-subtitles.sh --lang zho --format ass movie.mp4 ./subs
```

**遇到图形字幕时的行为**：如果目标字幕轨是蓝光 PGS（`hdmv_pgs_subtitle`）或 DVD VobSub（`dvd_subtitle`）等位图/图形字幕，脚本会明确提示该轨道属于图像字幕、无法直接转为 `.srt`/`.ass` 纯文本（需使用 Subtitle Edit、Tesseract 等 OCR 工具识别），并在未导出任何文本轨道时返回退出码 `2`。

---

## Windows 使用说明（PowerShell）

请先自行安装 FFmpeg 并确认 `ffmpeg.exe` 与 `ffprobe.exe` 已加入 `PATH`。若当前 PowerShell 会话限制运行本地脚本，可先在当前窗口临时放行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

随后调用 `scripts\windows\` 下的同功能脚本：

```powershell
# 1. 查看所有字幕轨
.\scripts\windows\list-subtitle-tracks.ps1 .\movie.mkv

# 2. 无损移除全部或指定字幕轨（-c copy，不重编码）
.\scripts\windows\remove-subtitle-tracks.ps1 .\movie.mkv .\movie-clean.mkv
.\scripts\windows\remove-subtitle-tracks.ps1 -Lang zho .\movie.mp4 .\movie-en.mp4
.\scripts\windows\remove-subtitle-tracks.ps1 -Index 0 -Force .\movie.mkv .\movie-out.mkv

# 3. 导出文本字幕为 .srt 或 .ass
.\scripts\windows\extract-subtitles.ps1 .\movie.mkv .\subs
.\scripts\windows\extract-subtitles.ps1 -Index 0 .\movie.mp4 .\english.srt
.\scripts\windows\extract-subtitles.ps1 -Lang zho -Format ass .\movie.mkv .\subs
```

---

## 常见字幕编码速查表

| FFmpeg 编码名 | 常见名称 | 类型 | 常见封装容器 | 能否 `-c copy` 无损移除？ | 能否直接导出 `.srt` / `.ass`？ |
| --- | --- | --- | --- | --- | --- |
| `subrip`（`srt`） | SubRip | 文本 | `.mkv` | 可以 | 可以 |
| `ass` / `ssa` | SubStation Alpha | 文本 | `.mkv` | 可以 | 可以 |
| `mov_text` | MPEG-4 Timed Text（`tx3g`） | 文本 | `.mp4`、`.mov`、`.m4v` | 可以 | 可以 |
| `webvtt` | WebVTT | 文本 | `.webm`、`.mkv` | 可以 | 可以 |
| `hdmv_pgs_subtitle` | 蓝光 PGS（`.sup`） | 图形（位图） | `.mkv`、`.m2ts` | 可以 | 否（需做 OCR） |
| `dvd_subtitle` | DVD VobSub（`.idx`/`.sub`） | 图形（位图） | `.mkv`、`.mp4`、`.vob` | 可以 | 否（需做 OCR） |
| `dvb_subtitle` | DVB 广播字幕 | 图形（位图） | `.ts`、`.mkv` | 可以 | 否（需做 OCR） |

---

## 运行自动化测试

`test/` 目录使用 `ffmpeg` 动态生成包含双语字幕轨的 `.mkv` 与 `.mp4` 测试视频以及蓝光 PGS 位图字幕测试视频，逐项验证三个脚本（含用 `ffprobe` 校验移除后的字幕轨数量，并对比视频流 `codec`、帧数与压缩码流 MD5 以确认未重新编码）：

```bash
bash test/run-tests.sh
```

详细测试说明与完整实测输出见 [test/README.md](test/README.md)。

---

## 想自动完成这件事

如果你的视频里是已经烧录进画面的硬字幕，或者你更习惯用图形界面一键移除软字幕轨，可以使用离线桌面应用 [FrameWipe](https://framewipe.com/zh/remove-subtitles-from-video)（支持 Apple Silicon 芯片的 Mac，macOS 13 及以上，以及 64 位 Windows 10/11）在本机完成处理，素材不上传且原文件不被改动。它支持打开 MP4、MOV、WebM 视频（暂不支持 MKV），自动定位字幕区域并在整段处理前提供 2 秒预览，结果另存为新文件；同时还提供照片去文字杂物、照片与视频人脸打码，以及仅限 Mac 可选安装的物体跟踪组件。FrameWipe 通过 Patreon 以 US$39.99 一次性买断方式发售（支持 7 天无理由全额退款），具体用法与功能限制见产品页 [framewipe.com/zh/remove-subtitles-from-video](https://framewipe.com/zh/remove-subtitles-from-video)。

---

## 许可证（License）

- 代码与脚本（`scripts/`、`test/*.sh`）：[MIT License](LICENSE)。
- 文档、数据与图片（`docs/`、`README.md`、`README.zh-CN.md`、`test/README.md`）：[知识共享署名 4.0 国际许可协议（CC BY 4.0）](https://creativecommons.org/licenses/by/4.0/)。
