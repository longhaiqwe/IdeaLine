# 灵感晾台 · 3D 介绍片

39.5 秒，1920×1080，30 帧/秒，H.264 + AAC。成片在 `promo/out/灵感晾台-介绍.mp4`，封面在 `promo/out/灵感晾台-封面.png`。

封面用在三处：视频开头 0.5 秒（之后 0.4 秒溶解进正片，供用第一帧当缩略图的平台使用）；嵌入 MP4 的封面元数据（covr）；单独的 PNG，供需要另传封面的平台使用。

## 分镜

| 时间 | 镜头 | 字幕 |
| --- | --- | --- |
| 0:00 | 封面 | — |
| 0:00.5 | 微距：衣杆、木夹、便签，焦点从木夹移到便签文字 | 想到一个选题，先记下来。 |
| 0:04.7 | 按键 ⌃ ⌥ N 依次按下 | 按 ⌃⌥N，打开书写窗口 |
| 0:08.3 | 书写窗口弹出，逐字输入 | — |
| 0:13.1 | 按键 ⌘ ↵ | 按 ⌘↵，挂上衣杆 |
| 0:14.3 | 窗口收成便签，飞到衣杆最左侧，木夹夹住，其余便签右移 | （同上） |
| 0:18.5 | 镜头拉远：衣杆在显示器顶部 | 便签挂在屏幕边缘，抬眼可见 |
| 0:22.1 | 衣杆依次移到右、下、左侧 | 衣杆可放在屏幕上、下、左、右 |
| 0:26.9 | 按住一张便签向左拖两格，相邻便签让位 | 按住便签左右拖动，调整顺序 |
| 0:31.1 | 全部选题窗口 | 全部选题：搜索、收纳、导出 Markdown |
| 0:34.1 | 3D 图标、名称、标语、系统要求、仓库地址 | — |

## 重新生成

需要 Blender 5.2、Xcode 命令行工具、Python 3（numpy、scipy、Pillow）、ffmpeg。在仓库根目录依次运行：

```sh
promo/textures/render-textures.sh                                   # 界面贴图和字幕层
/Applications/Blender.app/Contents/MacOS/Blender -b --python promo/blender/build_scene.py
python3 promo/audio/make_audio.py                                   # 音乐和音效
/Applications/Blender.app/Contents/MacOS/Blender -b promo/build/idealine_promo.blend -a
/Applications/Blender.app/Contents/MacOS/Blender -b promo/build/idealine_promo.blend --python promo/blender/render_cover.py
swiftc scripts/make-icon.swift -o promo/build/make-icon && promo/build/make-icon promo/build/cover/icon.png
swiftc -parse-as-library Sources/IdeaLine/{Store,HotKeys,Views,LinePosition}.swift promo/textures/CoverText.swift -o promo/build/cover-text
promo/build/cover-text promo/build/cover/icon.png promo/build/cover/cover_text.png
python3 promo/composite/make_cover.py                               # 封面
python3 promo/composite/composite.py                                # 成片
promo/composite/make_web.sh                                         # 10 MB 以内的 720p 网页版，用于 README
```

- 文案在 `promo/content.json`，镜头时长在 `promo/timeline.py`（100 BPM，每拍 18 帧）。改完从第一步重跑。
- `build_scene.py` 里所有动画都按帧计算后写入关键帧；它同时导出 `promo/build/events.json`，音频脚本按其中的帧号放音效。
- 渲染引擎是 EEVEE，48 采样。我的 M2（10 核 GPU）实测每帧约 6～14 秒，全片约 3.5 小时。设置 `PROMO_QUALITY=preview` 可降低采样做预览。
- 注意：`build_scene.py` 会重建 `promo/build/composer_seq/`，正在渲染时不要运行它；`render_cover.py` 只读场景，可以同时运行。
- 便签、书写窗口、全部选题页的贴图由应用源码里的颜色、字号和 `LibraryView` 渲染，内容为示例数据。
- 界面按 v1.3.0：衣杆背后有磨砂底板，工具条带「固定」按钮。视频里衣杆一直展开，所以按钮显示「已固定」。切换方位时衣杆滑动，底板原位淡入淡出，与 `ClotheslineView` 一致。

## 素材来源

- 音乐和音效全部由 `make_audio.py` 用代码合成，没有使用外部采样。需要换成授权音乐时，`promo/build/audio/` 下有单独的 `music.wav` 和 `sfx.wav`。
- 字体使用 macOS 自带的苹方、宋体和 SF 系列。
