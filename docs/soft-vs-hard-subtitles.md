[English](soft-vs-hard-subtitles.en.md) | 简体中文

# 软字幕与硬字幕：如何判断与各自怎么处理

想“去掉视频里的字幕”之前，第一步不是找去字幕工具，而是先确认视频里的字幕属于**软字幕（Soft Subtitles）**还是**硬字幕（Hard Subtitles / Burned-in Subtitles）**。两者的存储方式完全不同，对应的处理成本和画质影响也截然不同。

---

## 一、什么是软字幕，什么是硬字幕？

| 维度 | 软字幕（独立字幕轨） | 硬字幕（烧录字幕 / 内嵌压制字幕） |
| --- | --- | --- |
| 存储位置 | 作为独立的 `subtitle` 数据流封装在 MP4、MKV、MOV、WebM 等容器内，与视频流、音频流并列 | 在视频导出或压制阶段直接绘制进了每一帧画面的像素里，没有独立的字幕流 |
| 播放器能否开关 | 可以随时开启、关闭或切换不同语言轨道 | 无法在播放器菜单中关闭 |
| 移除是否损失画质 | **零画质损失**——直接流复制（`-c copy`）剔除字幕轨，不重新编码视频与音频 | **必须修改像素并重新编码**——无法通过 `-c copy` 去除 |
| 处理耗时 | 通常几秒内完成（仅取决于磁盘读写速度） | 需要逐帧解码、处理画面并重新编码，耗时取决于视频长度与分辨率 |
| 能否直接导出文本 | 文本类软字幕可直接导出 `.srt` / `.ass`；图形类软字幕需额外做 OCR | 无法从容器轨道导出，只能对画面做视频 OCR 识别 |

> **注意混合情况**：有些视频同时存在两层字幕——比如原片底部已经烧录了一层硬字幕，后期又在容器里封装了一条翻译软字幕轨。遇到这种情况时，移除软字幕轨只会去掉外封的那一层，原片画面里的硬字幕仍然存在。

---

## 二、软字幕内部的两种格式：文本字幕 vs 图形字幕

同样是独立的软字幕轨，内部编码又分为两类：

1. **文本类字幕（Text Subtitles）**
   - 常见编码：`subrip`（SRT）、`ass` / `ssa`（支持字体、位置与特效样式）、`mov_text`（MP4/MOV 标准文本字幕轨）、`webvtt`（WebM 常见文本字幕轨）。
   - 特点：轨道里保存的是字符文本和起止时间戳，可以用 `ffmpeg` 直接无损提取或转换为 `.srt`、`.ass` 文本文件。
2. **图形/位图类字幕（Bitmap / Image-based Subtitles）**
   - 常见编码：蓝光原盘常见的 PGS（`hdmv_pgs_subtitle`，通常为 `.sup`）、DVD 常见的 VobSub（`dvd_subtitle`，`.idx` + `.sub`）、数字电视广播字幕（`dvb_subtitle`）、`xsub`。
   - 特点：每一句字幕本质上是一张带透明通道的位图图像。它们依然是独立的软字幕轨——播放器可以开关，也可以用 `-c copy` 无损移除——但因为不含字符编码信息，**不能直接用 `ffmpeg` 转成 `.srt` 或 `.ass` 纯文本**，需要先导出图形流再用光学字符识别（OCR）工具（如 Subtitle Edit、Tesseract）识别成文字。

---

## 三、怎么判断视频是软字幕还是硬字幕？

按从快到准的顺序，可以用下面三种方法确认：

### 方法 1：在视频播放器里开关字幕菜单

用 VLC、IINA、mpv 或 PotPlayer 打开视频，查看菜单栏中的“字幕 / 字幕轨道（Subtitles / Subtitle Track）”：

- 如果列表里有可选轨道，且选择“禁用 / 关闭字幕”后画面上的文字随之消失，说明这是**软字幕**。
- 如果字幕轨道列表为空（或显示无可用轨道），但画面里仍然有字幕；或者把所有字幕轨都禁用之后画面上依然留有一层字，那么留下的那层字就是**硬字幕**。

### 方法 2：用 `ffprobe`（或本仓库脚本）检查容器流

在终端运行本仓库提供的检查脚本：

```bash
./scripts/list-subtitle-tracks.sh your-video.mp4
```

或者直接调用 `ffprobe`：

```bash
ffprobe -v error -select_streams s \
  -show_entries stream=index,codec_name:stream_tags=language,title \
  -of compact your-video.mp4
```

判读方式：

- **有输出行**：说明容器内存在独立的软字幕轨，同时能看到编码格式是文本类（如 `subrip`、`mov_text`、`ass`）还是图形类（如 `hdmv_pgs_subtitle`、`dvd_subtitle`）。
- **没有任何输出，但播放视频时看得到字幕**：说明字幕已经烧录进视频帧像素里，属于**硬字幕**。

### 方法 3：暂停并放大画面观察文字边缘

播放时暂停在有字幕的一帧并将画面放大：

- 软字幕由播放器按当前窗口分辨率实时渲染，文字笔画边缘通常与视频分辨率解耦。
- 硬字幕和底层画面一起经历过视频有损压缩（如 H.264 / HEVC 的 `yuv420p` 色度抽样与块变换），放大时往往能看到文字边缘带有与背景相连的压缩噪点（蚊噪）或色度边缘模糊。

---

## 四、各自应该怎么处理？

### 1. 如果是软字幕：直接无损移除或导出

软字幕不需要碰视频画面，直接用重新封装（remux）就能解决：

- **无损移除全部软字幕轨**（音视频流原样复制，不重新编码）：
  ```bash
  ./scripts/remove-subtitle-tracks.sh input.mkv output-clean.mkv
  ```
  等价的核心 `ffmpeg` 命令思路为：
  ```bash
  ffmpeg -i input.mkv -map 0:v? -map 0:a? -map_metadata 0 -map_chapters 0 -c copy output-clean.mkv
  ```
- **只移除指定语言或指定轨道索引的软字幕**：
  ```bash
  ./scripts/remove-subtitle-tracks.sh --lang zho input.mp4 output-en-only.mp4
  ./scripts/remove-subtitle-tracks.sh --index 0 input.mkv output.mkv
  ```
- **把文本软字幕导出为 `.srt` 或 `.ass`**：
  ```bash
  ./scripts/extract-subtitles.sh input.mkv ./subs
  ```
  如果 `list-subtitle-tracks.sh` 显示 `TYPE` 为 `bitmap`（例如 `hdmv_pgs_subtitle` 或 `dvd_subtitle`），则先用 `mkvextract` 或 `ffmpeg -map 0:s:0 -c:s copy out.sup` 解出原始图形字幕，再交给 OCR 工具转换。

### 2. 如果是硬字幕：裁切、遮盖，或做逐帧画面修复（Inpainting）

硬字幕已经是图像像素的一部分，任何轨道工具都无法“关掉”它。实际工程中通常有三条路线：

1. **画面裁切（Crop）**
   - 适用条件：字幕固定出现在上下黑边里，或位于画面最底部且裁掉后不破坏主体构图。
   - 局限：会改变视频分辨率与长宽比，需要对视频流重新编码。
2. **遮挡覆盖（Mask / Overlay）**
   - 适用条件：需要在旧字幕位置盖上一条不透明/半透明底色条再压制新字幕。
   - 局限：画面上会留下明显的遮挡色块或模糊带，不能得到干净背景。
3. **逐帧画面修复（Video Inpainting）**
   - 原理：先定位字幕所在的区域和时间段，利用相邻视频帧中未被文字挡住的真实背景像素做时域借用，再通过图像修补（inpainting）模型根据周围纹理填补剩余区域，最后重新编码输出。
   - 客观限制：画面修复填补的是“与周围环境相符的合理背景”，**并不是还原拍摄时被文字遮住的真实原始细节**；当字幕背后的画面运动剧烈或纹理复杂时，修补区域可能会出现闪烁（flicker）或残影（ghosting）。

#### 用本地桌面工具处理硬字幕

如果你手头的视频确认是烧录硬字幕、希望在本机按图形界面完成定位和画面修复，可以使用桌面应用 **[FrameWipe](https://framewipe.com)**（功能说明页：[framewipe.com/zh/remove-subtitles-from-video](https://framewipe.com/zh/remove-subtitles-from-video)）：

- **本机离线处理**：支持 Apple Silicon 芯片的 Mac（macOS 13 及以上，不支持 Intel Mac）和 Windows 10/11（64 位 x64）；所有处理都在本地电脑上完成，不上传素材，无需注册账号，导出结果一律另存为新文件，不覆盖原文件。
- **硬字幕与软字幕兼顾**：打开 MP4、MOV 或 WebM 视频后（暂不支持 MKV——若源文件是 MKV，可先用 `ffmpeg -i in.mkv -c copy out.mp4` 转封装），应用会自动检测烧录字幕区域，支持选择处理时间段并先渲染 2 秒预览确认效果；处理时先从相邻帧借用可见的真实背景像素，再修补剩余区域。若打开的视频带有独立软字幕轨，也可以在应用内一键无损移除。
- **其他清理能力与获取方式**：除视频字幕外，FrameWipe 还支持照片去文字与杂物（内置快速档 MI-GAN，可选应用内下载约 200 MB 的 LaMa 质量档模型）、照片与视频人脸打码（像素化、模糊、纯色遮盖及视频漏检时刻复核），以及仅限 Mac 可选安装的物体跟踪组件（Windows 版暂不支持物体跟踪，且安装包未做代码签名）。软件通过 Patreon 以 US$39.99 一次性买断方式提供（购买后 7 天内可邮件申请无理由全额退款）。
