# Sky Recomp 简体中文界面（非官方分支）

这是 [Apolinario-coder/SkyRecomp](https://github.com/Apolinario-coder/SkyRecomp) 的**界面汉化分支**，
基于上游 `main`（v2.1.0）修改，只动了 `runtime/ui/` 下的界面文案与字体加载，**没有改动重编译管线、渲染后端或游戏逻辑**。

- 游戏本体（对话、字幕、道具名、地图、存档界面）的中文由游戏自身的语言包提供，
  在启动器 **设置 → 游戏语言** 里选 `Chinese (Simplified)` 即可，与本分支无关。
- 本分支解决的是另一件事：**启动器与 ESC 控制面板原本只有英文界面**。

---

## 1. 汉化范围

| 界面 | 文件 | 状态 |
|---|---|---|
| 启动器主界面（开始游戏 / 设置 / 初始化游戏文件 / 退出） | `runtime/ui/launcher.mm` | ✅ 已汉化 |
| 启动器设置页（游戏文件、游戏代码、系统字体、游戏语言） | `runtime/ui/launcher.mm` | ✅ 已汉化 |
| 游戏文件初始化向导、进度与错误提示 | `runtime/ui/launcher.mm` | ✅ 已汉化 |
| ESC 面板：按键设置 | `runtime/ui/controls_ui.mm` | ✅ 已汉化 |
| ESC 面板：画面（显示、比例、渲染、放大、抗锯齿、着色器） | `runtime/ui/menu.mm` | ✅ 已汉化 |
| ESC 面板：音频 | `runtime/ui/menu.mm` | ✅ 已汉化 |
| ESC 面板：玩法（语言、难度、飞鸟、掉落、辅助功能） | `runtime/ui/menu.mm` + `difficulty.mm` | ✅ 已汉化 |
| ESC 面板：作弊 | `runtime/ui/cheats.mm` | ✅ 已汉化 |
| ESC 面板：退出确认 | `runtime/ui/menu.mm` | ✅ 已汉化 |
| 选项行、页脚操作提示（开/关、回车确认等） | `runtime/ui/option_rows.mm` | ✅ 已汉化 |
| 屏幕键盘（OSK） | `runtime/ui/osk.mm` | ✅ 已汉化 |

共替换 **337 处**文案（唯一字符串约 200 条）。

### 刻意保留英文的部分

| 内容 | 原因 |
|---|---|
| `THE LEGEND OF ZELDA · SKYWARD SWORD HD`、`Sky Recomp` | 游戏 logo 与产品名，本地化的通行做法是保留 |
| `4K`、`ReShade`、`MetalFX`、`AMD FSR 1`、`NVIDIA NIS`、`SMAA`、`FXAA`、`amiibo`、`Xbox/PlayStation/Nintendo` | 专有名词与商标 |
| `GPU` / `CPU` / `RAM` / `VRAM` / `FPS` | 性能覆盖层的通用缩写 |
| 存档编辑器、随机化、传送、外观、Mods 标签页 | **本版本根本不可达**（见下） |

### 为什么没汉化存档编辑器 / 随机化 / 传送 / 外观 / Mods

`menu.mm` 里标签页由这张表决定：

```c
static const char *names[] = {"Video", "Audio", "Save Editor", "Randomizer", "Warp", "Cheats", "Gameplay",
                              "Cosmetics", "Controls", "Quit", "Mods"};
static const int order[] = {8, 0, 1, 6, 5, 9};  // Controls, Video, Audio, Gameplay, Cheats, Quit (Mods: hidden for now)
```

只有 `order[]` 里的 6 个页签会被创建。其余页面（`save_editor.mm`、`rando_tab.mm`、`warp_tab.mm`、
`inventory_overlay.mm`、`tracker_overlay.mm`、`mods_ui.mm` 等）是从上游 **LASRecomp（塞尔达传说 织梦岛）**
继承来的代码，内容是马里恩、汪汪、鹰之塔之类与《御天之剑》无关的东西，界面上看不到。
把它们翻译成中文没有意义，故保持原样。若上游以后放开这些页签，再补翻即可。

---

## 2. 编译（Windows）

需要 **MSYS2 UCRT64** 环境，包含 `clang`、`lld`、`make`。

```bash
# 1. 装好依赖（SDL3 + LGPL FFmpeg，脚本会下载并固定校验）
make deps-windows

# 2. 编译启动器
make build/skyrecomp.exe
```

产物：`build/skyrecomp.exe`。

## 3. 安装

把编译出的 `skyrecomp.exe` 复制到你现有 SkyRecomp 安装目录，**覆盖同名文件**即可。
其余文件（`skygame.dll`、`skyrecomp.ini`、`mods/`、`reshade*`、`fonts/` 等）都不要动。

首次启动会读到已有的 `skyrecomp.ini`，界面语言无需额外设置（中文字符串是编译进程序的）。

---

## 4. 中文字体

上游的界面字体 `Baloo2-SemiBold.ttf` 只有拉丁字形，直接替换文案会显示成方框，所以本分支同时改了字体加载：

- 自动按顺序寻找中文字体：
  `SKYRECOMP_ZH_FONT` 环境变量 → `C:/Windows/Fonts/msyh.ttc`（微软雅黑）→ `msyhbd.ttc` → `simhei.ttf`
  → macOS `PingFang.ttc` → Linux `NotoSansCJK-Regular.ttc` → `fonts/NotoSansSC-Regular.ttf` → `fonts/msyh.ttc`
- 找不到中文字体时**自动回退**到原来的英文方案（不会崩，只是显示英文）。
- 字形范围不是整段 CJK 区间，而是由 `runtime/ui/zh_glyphs.h` 里的 **642 个实际用到的字符**生成，
  这样 4 套字号同时加载也不会把字形图集撑爆（`TexDesiredWidth = 4096`）。

想换字体或调字号，改文件顶部的宏即可（不用改逻辑）：

| 宏 | 位置 | 默认 | 含义 |
|---|---|---|---|
| `ZH_PX_SMALL` | `launcher.mm` 顶部 | 30 | 启动器小字 |
| `ZH_PX_MENU` | `launcher.mm` 顶部 | 52 | 启动器按钮/标题字 |
| `ZH_MENU_PX` | `menu.mm` 顶部 | 33 | ESC 面板正文 |
| `ZH_MENU_PX_BIG` | `menu.mm` 顶部 | 61 | ESC 面板页签与标题 |
| `ZH_OVERLAY_PX` | `menu.mm` 顶部 | 30 | 覆盖层/键盘 |
| `ZH_OVERLAY_PX_BIG` | `menu.mm` 顶部 | 48 | 覆盖层大字 |

也可以用环境变量 `SKYRECOMP_ZH_FONT=C:/路径/字体.ttc` 指定字体，不必重编译。

---

## 5. 与上游同步

改动集中在两处，同步上游时冲突面很小：

1. `runtime/ui/*.mm` 的字符串字面量（纯文案替换，保留 `##ID` 与 `%s`/`%.1f` 等格式符）；
2. `launcher.mm` / `menu.mm` 各自的字体初始化块（各一段，带 `简体中文界面：` 注释）。

辅助脚本（可重复执行，幂等）：

```bash
python tools/zh_apply.py --check   # 只统计，不改文件
python tools/zh_apply.py           # 应用翻译
python tools/zh_runs.py runtime/ui/*.mm   # 导出待翻译清单（含跨行拼接）
```

对照改动可以直接和上游比：

```bash
git diff ad649b4f -- runtime/ui/   # 只含文案与字体加载的差异
```

---

## 6. 许可与致谢

- 上游项目：Apolinario-coder/SkyRecomp（MIT，见 `LICENSE`）
- 框架来源：peiikai/LASRecomp（MIT，见 `LICENSE-LASRecomp`）
- 本分支只包含界面文案与字体加载的修改，遵循同样的 MIT 许可。
- 不包含任何游戏资源。使用仍需自备合法取得的《塞尔达传说：御天之剑 HD》v1.0.0 游戏文件。
