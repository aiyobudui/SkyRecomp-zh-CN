#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SkyRecomp 简体中文界面 - 翻译词典与替换器。

用法：
    python tools/zh_apply.py            # 应用翻译
    python tools/zh_apply.py --check    # 只检查（不改文件）

替换规则：
1. 相邻字符串字面量（C 的隐式拼接）先合并，命中词典就把整段换成一条中文；
2. 剩下的单条字面量再逐条替换；
3. 以 ## 开头的 ImGui ID 片段、路径、格式串永远不会被碰。
"""
import json
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
UI = ROOT / 'runtime' / 'ui'
FILES = ['launcher.mm', 'menu.mm', 'cheats.mm', 'difficulty.mm',
         'option_rows.mm', 'controls_ui.mm', 'osk.mm']

DICT = {}

def add(en, zh):
    DICT[en] = zh

# ─────────────────────────── launcher.mm ───────────────────────────
add('Choose your display mode', '选择显示模式')
add('Select how the game camera fits your screen. You can change this at any time in Settings > Video.',
    '选择游戏画面如何适配屏幕。之后可随时在「设置 > 画面」中更改。')
add('Original 16:9', '原始 16:9')
add('Unlocked (fill window)', '自由拉伸（铺满窗口）')
add('Opening the in-game menu', '打开游戏内菜单')
add('Access controls, video, audio, and mods at any time while playing.',
    '游戏中可随时调整按键、画面、音频与 Mod。')
add('Press F1 or Esc on a keyboard, or press the %s (or %s together) on your controller.',
    '键盘按 F1 或 Esc；手柄按 %s（或同时按 %s）。')
add('Start game', '开始游戏')
add('Game files', '游戏文件')
add('Extracted game data and compiled library currently use %.1f GB.',
    '已解包的游戏数据与编译库当前占用 %.1f GB。')
add('Show in Explorer', '在资源管理器中显示')
add('Open folder', '打开文件夹')
add('Show in Finder', '在访达中显示')
add('Delete game files', '删除游戏文件')
add('Delete installed game files?', '删除已安装的游戏文件？')
add("This removes Sky Recomp's copy of the game files (%.1f GB).",
    '这会删除 Sky Recomp 复制的游戏文件（%.1f GB）。')
add('Your save files, settings, and original source folder are kept.',
    '你的存档、设置和原始源文件夹都会保留。')
add('Dev checkout: %s', '开发版目录：%s')
add('Keep files', '保留文件')
add('Game code', '游戏代码')
add('Rebuild game code', '重新构建游戏代码')
add('Rebuild compiles it again from the copied game files, the way chosen here.',
    '重新构建会按这里选定的方式，从已复制的游戏文件重新编译。')
add('System fonts', '系统字体')
add('Dialogue font: %s    Controller glyphs: %s', '对话字体：%s    手柄图标：%s')
add('Custom (imported)', '自定义（已导入）')
add('Built-in fallback', '内置后备')
add('Imported', '已导入')
add('Custom system fonts are optional. You can import compatible .bfttf or .ttf font files for dialogue and controller glyphs, or use the built-in fallback typeface.',
    '自定义系统字体是可选项。你可以导入兼容的 .bfttf 或 .ttf 字体文件，用于对话与手柄图标，也可以直接使用内置后备字体。')
add('Import font files', '导入字体文件')
add('Restore fallback font', '恢复后备字体')
add('Game language', '游戏语言')
add('Selects the in-game text language. Changes take effect when the game boots.',
    '选择游戏内文本语言。改动会在游戏下次启动时生效。')
add('Settings', '设置')
add('Game Files Setup', '游戏文件初始化')
add('1. Source Files', '1. 源文件')
add('Game files folder', '游戏文件文件夹')
add('2. Install & Compile', '2. 安装与编译')
add('Set up game files', '初始化游戏文件')
add('Working...', '处理中...')
add('Start', '开始')
add('Ready to Play', '可以开始游戏')
add('Start Game', '启动游戏')
add('Launch', '启动')
add('Launch the game now.', '立即启动游戏。')
add('Manage Game Files', '管理游戏文件')
add("Removes Sky Recomp's installed game data and compiled library to free disk space. Your save data, settings, and original source folder are kept.",
    '删除 Sky Recomp 已安装的游戏数据和编译库以释放磁盘空间。你的存档、设置与原始源文件夹都会保留。')
add('Delete game files now', '立即删除游戏文件')
add("Permanently deletes the installed game files from Sky Recomp's folder.",
    '从 Sky Recomp 目录中永久删除已安装的游戏文件。')
add('Keep game files', '保留游戏文件')
add('Cancels deletion and keeps your installed game files.', '取消删除，保留已安装的游戏文件。')
add('Game files ready', '游戏文件已就绪')
add('Setting up game files...', '正在初始化游戏文件...')
add('Open Set Up Game Files to get started.', '打开「初始化游戏文件」即可开始。')
add('update', '更新')
add('PLAY', '开始游戏')
add('SETTINGS', '设置')
add('SET UP GAME FILES', '初始化游戏文件')
add('QUIT', '退出')

# launcher 状态 / 错误 / 进度提示
add('No game files', '未找到游戏文件')
add('Wrong game version (needs v1.0.0)', '游戏版本不正确（需要 v1.0.0）')
add('Game data missing', '游戏数据缺失')
add('Game code not built yet', '游戏代码尚未构建')
add('No game files found in that folder', '该文件夹中没有游戏文件')
add('Packaged or archived files cannot be used directly', '不能直接使用打包或压缩格式的文件')
add('Setup could not finish copying files', '初始化未能完成文件复制')
add('Unsupported game version', '不支持的游戏版本')
add('Game files are incomplete', '游戏文件不完整')
add('The game code could not be built', '游戏代码构建失败')
add('Select the folder that contains your unpacked game files and assets.',
    '请选择包含已解包游戏文件与资源的文件夹。')
add('Unpack your game files into a regular folder first, then select that folder.',
    '请先把游戏文件解包到普通文件夹，再选择该文件夹。')
add('Check that your drive has at least 8 GB of free space and try again.',
    '请确认磁盘至少有 8 GB 可用空间后重试。')
add('Sky Recomp requires the base 1.0.0 version of the game without update patches.',
    'Sky Recomp 需要游戏本体 1.0.0 版本，且不含更新补丁。')
add('Some required program or asset files are missing. Verify your source folder and try again.',
    '缺少必要的程序或资源文件，请检查源文件夹后重试。')
add('Make sure the skygen and zig folders are next to skyrecomp.exe, then try again.',
    '请确认 skygen 与 zig 文件夹和 skyrecomp.exe 位于同一目录，然后重试。')
add('Game files ready.', '游戏文件已就绪。')
add('Scanning folder for game files...', '正在扫描游戏文件...')
add('Copying executable modules...', '正在复制可执行模块...')
add('Copying game data archive...', '正在复制游戏数据归档...')
add('Copying game assets...', '正在复制游戏资源...')
add('Building game data image...', '正在生成游戏数据镜像...')
add('Select your game files folder first.', '请先选择游戏文件文件夹。')
add("Choose 'Game files folder' above to pick the folder with your game files.",
    '点击上方的「游戏文件文件夹」选择包含游戏文件的目录。')
add('Setup could not start.', '初始化无法启动。')
add('Close other running applications and try again.', '请关闭其他正在运行的程序后重试。')
add('Faster build', '优先构建速度')
add('Faster game', '优先游戏性能')
add('This system has no folder dialog.', '当前系统没有文件夹选择对话框。')
add('Start Sky Recomp with SKYRECOMP_GAME_FILES=<your game files folder> set, then choose Start.',
    '请先设置 SKYRECOMP_GAME_FILES=<游戏文件文件夹> 再启动 Sky Recomp，然后点「开始」。')
add('Imported fonts removed. The built-in fallback font will be used.',
    '已移除导入的字体，将使用内置后备字体。')
add(' font file(s) imported', ' 个字体文件已导入')
add(' skipped', ' 个已跳过')
add('. Changes take effect next time you start the game.', '。下次启动游戏后生效。')
add('Choose folder...', '选择文件夹...')
add('Selected', '已选择')
add('Select the folder containing your unpacked game files (base version 1.0.0). Sky Recomp does not include any game assets or copyrighted data.',
    '选择包含已解包游戏文件的文件夹（本体 1.0.0 版本）。Sky Recomp 不包含任何游戏资源或受版权保护的数据。')
add('Copies the required files, builds the local data archive, and compiles the game code into a native library for your PC. This runs once during initial setup and leaves your source folder untouched.',
    '复制所需文件、生成本地数据归档，并把游戏代码编译成适用于你这台电脑的原生库。此步骤仅在首次初始化时执行一次，且不会改动你的源文件夹。')
add('Recompiling game code', '正在重编译游戏代码')
add('Setting up game files', '正在初始化游戏文件')
add('This runs once during initial setup and takes a couple of minutes.',
    '仅在首次初始化时执行一次，大约需要几分钟。')
add('Setting up the game files...', '正在初始化游戏文件...')
add('Base v1.0.0', '本体 v1.0.0')
add('  \\xc2\\xb7  4K Textures', '  \u00b7  4K 纹理')
add('  \\xc2\\xb7  ReShade', '  \u00b7  ReShade')
add('Up / Down: Navigate    Enter / A: Select', '上下：移动    回车 / A：确认')
add('Update available:  ', '有新版本可用：')
add('DOWNLOAD ', '下载 ')
add('Could not delete the game files', '无法删除游戏文件')
add("They are outside Sky Recomp's data folder, so nothing was removed.",
    '它们不在 Sky Recomp 的数据目录内，因此没有删除任何内容。')
add('Game files deleted.', '游戏文件已删除。')
add('Home button', 'Home 键')
add('Xbox button', 'Xbox 键')
add('PlayStation button', 'PlayStation 键')
add('Minus + Plus', 'Minus + Plus')
add('View + Menu', 'View + Menu')
add('Create + Options', 'Create + Options')

# ─────────────────────────── menu.mm ───────────────────────────
add('Display', '显示')
add('Aspect ratio', '画面比例')
add("Unlocked: the view fills the window, so wider (or taller) windows show more of the island - up to ultrawide; houses and dungeons keep their framing. Original 16:9: the game's own framing, with bars.",
    '自由：画面铺满窗口，窗口越宽（或越高）就能看到越多岛屿，最宽可到超宽屏；房屋与迷宫保持原有构图。原始 16:9：保持游戏本身的构图，四周留黑边。')
add('Fullscreen', '全屏')
add('Fills the screen. Also: F11, Alt+Enter or Cmd+Ctrl+F.', '铺满屏幕。也可用 F11、Alt+Enter 或 Cmd+Ctrl+F。')
add('Performance overlay', '性能覆盖层')
add('Top right. FPS: the frame rate and frame time. Full: also GPU, CPU and RAM load, temperatures, VRAM and a frame time graph, for benchmarking. F10 switches between them while you play.',
    '显示在右上角。FPS：帧率与帧时间。完整：另外显示 GPU、CPU、内存占用、温度、显存与帧时间曲线，便于跑分。游戏中按 F10 切换。')
add('Frame rate', '帧率')
add('Sets the rendering target while preserving game speed. 120 FPS requires faster hardware and a high refresh rate display.',
    '在保持游戏速度不变的前提下设定渲染目标帧率。120 帧需要更强的硬件和支持高刷新率的显示器。')
add('Rendering', '渲染')
add('4K Textures', '4K 纹理')
add('Uses the included high-resolution textures throughout the game. Turn off to use the original textures. Changes apply while playing.',
    '全程使用随附的高分辨率纹理。关闭则使用原始纹理。改动立即生效，无需重启。')
add('ReShade', 'ReShade')
add('Enables the included lighting and colour effects. Off disables the effects while playing and prevents loading ReShade on the next launch. If started with ReShade off, close and reopen the application to enable it.',
    '启用随附的光影与色彩效果。关闭会在游玩时停用效果，并在下次启动时不再加载 ReShade。若以关闭状态启动后想要启用，请关闭并重新打开程序。')
add('Internal resolution', '内部渲染分辨率')
add('Upscaler', '放大方式')
add('Anti-aliasing', '抗锯齿')
add("Smooths jagged edges of the game image before it is scaled to the window. SMAA: finds the edges and blends only along them, so textures stay sharp. FXAA: smooths more edges, including thin and curved ones, but softens the whole image a little. Both are most useful at a lower internal resolution; for the cleanest image, raise Internal resolution above your display's (supersampling).",
    '在画面放大到窗口之前，先平滑游戏图像边缘的锯齿。SMAA：只沿检测到的边缘混合，纹理保持锐利。FXAA：能平滑更多边缘（含细线与曲线），但整体会略微变软。两者在较低的内部渲染分辨率下最有用；想要最干净的画面，请把内部渲染分辨率调到高于显示器分辨率（超采样）。')
add('Anisotropic filtering', '各向异性过滤')
add('Keeps textures sharp when seen at a shallow angle - paths, floors and walls stretching into the distance - instead of blurring them. Game: the level the game asks for. 16x: sharpest; costs little on most GPUs.',
    '让以很小夹角看到的纹理（伸向远处的小路、地面与墙面）保持清晰，而不是糊成一片。游戏：使用游戏请求的等级。16x：最锐利，在多数显卡上开销很小。')
add('Shader compilation (Experimental)', '着色器编译（实验性）')
add("What happens the first time something needs a new shader. Hybrid: what's drawn every frame appears a moment later instead of the game pausing, while shadows and other reused images still wait, so they are never wrong. Wait: everything waits, which can stutter. Async: nothing waits, so a shadow can be missing until it's redrawn.",
    '第一次需要新着色器时如何处理。混合：每帧都要绘制的画面稍后出现，而不是卡住游戏；阴影等会被复用的图像仍然等待，因此不会出错。等待：全部等待，可能出现卡顿。异步：都不等待，阴影在重绘前可能缺失。')
add('Zelda & Loftwing amiibo', '塞尔达与飞鸟 amiibo')
add('Load another amiibo dump', '载入其他 amiibo 转储')
add('Load amiibo dump', '载入 amiibo 转储')
add("In Fi's menu, \"Use amiibo\" recognises your Zelda & Loftwing amiibo right away: from the surface Fi takes you to the sky, and from the sky back to the spot you left. Needs your own figure's dump, loaded below.%s%s",
    '在法伊菜单中，「使用 amiibo」会立刻识别你的塞尔达与飞鸟 amiibo：在地面时法伊会送你上天，在天上时则送回你离开的位置。需要你自己手办的转储文件，请在下方载入。%s%s')
add("Pick a dump of your own Zelda & Loftwing amiibo (a .bin made with an NFC phone app such as TagMo). A copy is kept in the game's data folder; only the figure's ID is read from it.%s%s",
    '选择你自己塞尔达与飞鸟 amiibo 的转储文件（用 TagMo 等手机 NFC 应用生成的 .bin）。副本会保存在游戏数据目录中，程序只从中读取手办 ID。%s%s')
add('Game', '游戏')
add('Language', '语言')
add("The game's text language. Changing language requires restarting the game to reload text archives.",
    '游戏的文本语言。更改语言需要重启游戏以重新载入文本包。')
add('Restart to apply language', '重启以应用语言')
add('Restarts the game immediately to reload text in the chosen language. Progress since your last save will be lost.',
    '立即重启游戏，按所选语言重新加载文本。上次存档之后的进度会丢失。')
add('Difficulty', '难度')
add('Link', '林克')
add('Loftwing', '飞鸟')
add('Drops', '掉落')
add('Accessibility', '辅助功能')
add('Color blind mode', '色盲模式')
add("Shifts the colors you can't tell apart into ones you can (daltonization), for each common kind of color blindness. Applies to the whole game picture.",
    '针对常见的各类色觉异常，把你难以区分的颜色偏移成能够区分的颜色（色觉矫正）。作用于整个游戏画面。')
add('amiibo', 'amiibo')
add('Colors', '颜色')
add('Tunic color', '服装颜色')
add("Link's tunic color. Default: the game's own (or the randomizer seed's).",
    '林克衣服的颜色。默认：游戏本来的颜色（随机化模式下则取该种子的设定）。')
add('Heart color', '心的颜色')
add('The color of the hearts on the HUD.', '界面心数图标的颜色。')
add('Random colors', '随机配色')
add('Picks a random tunic and heart color (any other color, Default included).',
    '随机挑选服装颜色与心的颜色（「默认」之外的任意颜色）。')
add('Sound', '声音')
add('Volume', '音量')
add("The game's volume. 100% is the game's own level; above it, louder.",
    '游戏音量。100% 为游戏原始音量，高于此值会更响。')
add('Room reverb', '房间混响')
add("The game's echo in caves, dungeons and big rooms.", '游戏在洞穴、迷宫与大房间中的回响。')
add('Movie audio', '影片音频')
add("Sound in the game's movies (the opening and the ending). Applies the next time a movie starts.",
    '游戏影片（片头与结局）的声音。下次影片播放时生效。')
add('Quit', '退出')
add('Quit to Start Screen', '退回启动界面')
add("You're on the start screen.", '你当前已在启动界面。')
add('Quit to Desktop', '退出到桌面')
add('Yes, quit to Start Screen', '是，退回启动界面')
add('Yes, quit to Desktop', '是，退出到桌面')
add('Cancel', '取消')
add('Stays where you are.', '保持当前状态。')
add('Leaves the game and goes back to the Sky Recomp start screen.%s',
    '离开游戏并回到 Sky Recomp 启动界面。%s')
add('Closes Sky Recomp.%s', '关闭 Sky Recomp。%s')
add('Movement', '移动')
add('D-pad moves Link', '用十字键移动林克')
add('Free camera look', '自由视角')
add("Moving the right stick looks around without having to hold L first. A short L press switches it off/on for this session; holding L while the eye is on turns the free camera off for the hold, so the right stick swings the sword. The eye at the bottom right shows the state. Targeting (ZL), items (ZR) and the pouch (R) keep their normal right-stick behavior.",
    '无需先按住 L，推右摇杆即可环视。短按 L 可在本次会话中开/关；按住 L 时右下角眼睛图标亮起，表示按住期间关闭自由视角，此时右摇杆恢复挥剑。右下角的眼睛图标显示当前状态。锁定（ZL）、道具（ZR）与布袋（R）仍保持右摇杆原有行为。')
add('Free camera sensitivity', '自由视角灵敏度')
add("How fast the right stick turns the camera while free camera look is active (1.00x = the game's speed).",
    '自由视角开启时右摇杆转动镜头的速度（1.00x = 游戏原速）。')
add('Mouse camera and combat', '鼠标视角与战斗')
add('Mouse sensitivity', '鼠标灵敏度')
add('Move the mouse to look around. Left click: sword slash (move before clicking to choose direction). Right click: target / shield bash. Middle click: sword thrust. Hold Left Alt or Mouse 4 for item aim: left click readies / uses the selected item; hold and release to fire the bow. Hold 3: item wheel. Mouse 5 or E: pouch. K still interacts. Esc releases the mouse. Explicit mouse button bindings take priority.',
    '移动鼠标即可环视。左键：挥剑（点击前先移动可决定方向）。右键：锁定 / 盾击。中键：突刺。按住左 Alt 或鼠标 4 号键进入道具瞄准：左键准备 / 使用所选道具；按住再松开可射箭。按住 3：道具轮盘。鼠标 5 号键或 E：布袋。K 仍可交互。Esc 释放鼠标。显式绑定的鼠标按键优先。')
add('Gyro sensitivity', '陀螺仪灵敏度')
add("How far the aim moves when you turn a controller with a gyro (bow, slingshot, first-person view). 1.00x = the controller's own motion; lower it if the aim is too twitchy.",
    '转动带陀螺仪的手柄时准星移动的幅度（弓、弹弓、第一人称视角）。1.00x = 手柄本身的动作幅度；若准星太飘可以调低。')
add('Button prompts', '按键提示')
add('Auto (%s)', '自动（%s）')
add('Keyboard', '键盘')
add('Button icons', '按键图标')
add('Light (the game\'s own)', '浅色（同游戏本体）')
add('Dark', '深色')
add('Button look', '按键外观')
add('Xbox, PlayStation and keyboard icons: light buttons like the game\'s own, or dark ones.',
    'Xbox、PlayStation 与键盘图标：使用和游戏本体一致的浅色按键，或使用深色按键。')
add('Controls', '按键设置')
add('Menu', '菜单')
add("Open / close this menu:  F1, Esc, the controller's Home / Xbox / PlayStation button, or Back + Start",
    '打开/关闭本菜单：F1、Esc、手柄的 Home / Xbox / PlayStation 键，或 Back + Start')
add('Switch tabs:  L / R  (Q / E)        Back:  B  (Esc)', '切换标签：L / R（Q / E）        返回：B（Esc）')
add('Fullscreen:  F11 / Alt+Enter', '全屏：F11 / Alt+Enter')
add('Enter your name', '输入名称')
add('Enter  confirm      Esc  cancel      (%d / %d)', '回车 确认      Esc 取消      (%d / %d)')

# menu 选项值与标签页
add('Prelaunch', '启动前')
add('Video', '画面')
add('Audio', '音频')
add('Save Editor', '存档编辑')
add('Randomizer', '随机化')
add('Warp', '传送')
add('Cheats', '作弊')
add('Gameplay', '玩法')
add('Cosmetics', '外观')
add('Mods', 'Mod')
add('Unlocked', '自由')
add('Full', '完整')
add('60 FPS', '60 帧')
add('120 FPS (Experimental)', '120 帧（实验性）')
add('Match display', '匹配显示器')
add('Dynamic', '动态')
add('Bilinear', '双线性')
add('Hybrid', '混合')
add('Wait', '等待')
add('Async', '异步')
add('Red-weak (protan)', '红色弱（protan）')
add('Green-weak (deutan)', '绿色弱（deutan）')
add('Blue-weak (tritan)', '蓝色弱（tritan）')

# ─────────────────────────── cheats.mm ───────────────────────────
add('Always on', '始终开启')
add('Infinite health', '无限生命')
add('Health refills to full whenever Link is hurt.\\n\\nA single hit bigger than all his hearts still defeats him.',
    '林克受伤后生命会立即回满。\\n\\n但单次伤害超过其全部心数时仍会被击倒。')
add('Infinite stamina', '无限耐力')
add('The stamina gauge never drains: sprint, climb and spin as long as you like.',
    '耐力槽永不消耗：可以随意冲刺、攀爬与旋转。')
add('Infinite rupees', '无限卢比')
add('Rupees stay at 9,900.', '卢比数量保持在 9,900。')
add('Infinite Beetle flight', '甲虫无限飞行')
add('The Beetle keeps flying until you call it back.', '甲虫会一直飞行，直到你把它召回。')
add('Skyward Strike always charged', '天空斩始终蓄力')
add("Link's sword is always charged: every vertical swing sends a Skyward Strike, with no need to hold it up.",
    '林克的剑始终保持蓄力：每次竖挥都会放出天空斩，不必先把剑举起。')
add('Infinite air dash', '无限空中冲刺')
add("Your Loftwing's dashes are never used up: dash as often as you like.",
    '飞鸟的冲刺次数永不耗尽：想冲几次就冲几次。')
add('Enemies always drop items', '敌人必定掉落物品')
add('Defeated enemies, grass and pots always drop something from what they can drop, and enemies always drop their monster materials. Drops turned off in the Gameplay tab stay off.',
    '击败的敌人、割草与打碎的罐子必定从可掉落物中给出东西，敌人也必定掉落怪物素材。在「玩法」页里关掉的掉落仍然保持关闭。')

# ─────────────────────────── difficulty.mm ───────────────────────────
add('Damage taken', '受到伤害')
add("How much damage enemies deal to Link: half, the game's own, or up to eight times as much. On top of Hero Mode's double damage.",
    '敌人对林克造成的伤害：一半、游戏原值，或最多八倍。在此之上还会叠加英雄模式的双倍伤害。')
add('One-hit KO', '一击必杀')
add('Any hit defeats Link, whatever his hearts.', '任何攻击都会击倒林克，无视心数。')
add('Dash charges', '冲刺次数')
add('How many dashes your Loftwing holds; they recharge one at a time as usual.\\n\\nApplies from the next time you call your Loftwing. The gauge shows the extra wings from the next start of the game.',
    '飞鸟一次可用的冲刺次数；仍按原规则逐个回复。\\n\\n从下次召唤飞鸟起生效，界面上的额外羽翼要等下次启动游戏才会显示。')
add('Flight speed', '飞行速度')
add('How fast your Loftwing flies, dashes included. Turning stays the same, so turns are wider when faster.',
    '飞鸟的飞行速度（含冲刺）。转向速度不变，因此速度越快转弯越宽。')
add('Hearts', '心')
add('Defeated enemies, grass and pots can drop recovery hearts.', '击败的敌人、割草与罐子可以掉落回复之心。')
add('Rupees', '卢比')
add('Defeated enemies, grass and pots can drop rupees.', '击败的敌人、割草与罐子可以掉落卢比。')
add('Ammo', '弹药')
add('Defeated enemies, grass and pots can drop arrows, Deku Seeds and bombs (once you have the bag).',
    '击败的敌人、割草与罐子可以掉落箭、德库种子与炸弹（需先拿到对应的袋）。')
add('Treasures', '宝物')
add('Defeated enemies can drop monster materials: Chu Jelly, Monster Claws, Ornamental and Golden Skulls, Evil Crystals.',
    '击败敌人可以掉落怪物素材：丘丘胶、怪物爪、装饰骷髅与黄金骷髅、邪恶结晶。')
add('Walking & running speed', '行走与奔跑速度')
add('How fast Link walks, runs and sprints. His animations keep their pace, so his feet may slide at the far ends.',
    '林克走路、奔跑与冲刺的速度。动作节奏不变，因此在极端值下可能会出现脚步滑动。')
add('Half', '一半')
add('Default', '默认')

# ─────────────────────────── option_rows.mm ───────────────────────────
add('On', '开')
add('Off', '关')
add('Enter / A: Select or toggle    Left / Right: Adjust    Esc / B: Back',
    '回车 / A：选择或切换    左右：调整    Esc / B：返回')

# ─────────────────────────── controls_ui.mm ───────────────────────────
add('Switch', '切换')
add('Controller', '手柄')
add('Left stick', '左摇杆')
add('Right stick', '右摇杆')
add('Reset controller to defaults', '手柄恢复默认')
add('Reset keyboard to defaults', '键盘恢复默认')
add('Select a binding, then press the new button or key. Esc (or 5 seconds) cancels. A button that\'s already in use swaps with the old one.',
    '先选中一项，再按下新的按键。Esc（或等待 5 秒）取消。若该按键已被占用，会与原按键互换。')
add("Bindings apply to the game only. Menus keep the fixed layout (right face button / Enter select, bottom face button / Esc back), and the in-game menu always opens with F1 or Esc, or the controller's Back + Start held together, or its Home / Guide button - so this page can't be locked out. The game's button icons follow the controller bindings.",
    '按键绑定只作用于游戏本体。菜单保持固定布局（右侧功能键 / 回车确认，下方功能键 / Esc 返回），游戏内菜单始终可以用 F1 或 Esc、手柄的 Back + Start 同时按、或 Home / Guide 键打开，因此本页不会把自己锁死。游戏内的按键图标会跟随手柄绑定。')
add('Press %s...  %d##%d_%d', '按下 %s...  %d##%d_%d')
add('a button', '按键')
add('a key', '按键')
add('Controller: %s  (%s button names)', '手柄：%s（%s 按键名）')
add('No controller connected  (%s button names shown)', '未连接手柄（当前显示 %s 按键名）')
add('%s bindings reset to the defaults.', '%s 的按键已恢复默认。')
add('%s is now %s.', '%s 已设为 %s。')
add('%s is now %s; %s moved to %s (swapped).', '%s 已设为 %s；%s 移到了 %s（已互换）。')
add('Cancelled: %s unchanged.', '已取消：%s 未更改。')
add('Nothing pressed: %s unchanged.', '没有检测到按键：%s 未更改。')

# ─────────────────────────── osk.mm ───────────────────────────
add('Space', '空格')
add('Delete', '删除')
add('OK', '确定')
add('Enter text', '输入文本')
add('A  type      B  delete      Start / +  OK      (%d / %d)', 'A 输入      B 删除      Start / + 确定      (%d / %d)')


# ── 二次补漏（长描述 / 格式串 / 选项值）──
add("How the image is scaled up to the window when it renders at a lower resolution. MetalFX: Apple's upscaler, sharper. Bilinear: plain and soft.",
    '画面以较低分辨率渲染时，如何放大到窗口尺寸。MetalFX：Apple 的放大技术，更锐利。双线性：简单柔和。')
add("How the image is scaled up to the window when it renders at a lower resolution. AMD FSR 1: AMD FidelityFX edge-aware upscaling and sharpening. NVIDIA NIS: NVIDIA Image Scaling with directional 6-tap filtering and adaptive sharpening. Bilinear: plain and soft.",
    '画面以较低分辨率渲染时，如何放大到窗口尺寸。AMD FSR 1：AMD FidelityFX 的边缘感知放大与锐化。NVIDIA NIS：NVIDIA Image Scaling，带方向性 6 抽头滤波与自适应锐化。双线性：简单柔和。')
add("%s\\n\\nNot used at Match display: the game already renders at your display's resolution.",
    '%s\\n\\n在「匹配显示器」下不使用此项：游戏本身就按显示器分辨率渲染。')
add("How sharp the 3D image is. Match display: your screen's own resolution. Dynamic: as sharp as your GPU keeps at full speed. 1x-4x: the Switch's 1080p times that. 75%% / 50%% / 25%%: a share of the display, for slower machines.\\n\\nRendering at %.0f x %.0f.",
    '3D 画面的清晰程度。匹配显示器：使用屏幕自身分辨率。动态：在不掉帧的前提下尽可能锐利。1x-4x：Switch 的 1080p 乘以该倍数。75%% / 50%% / 25%%：按显示器的比例渲染，适合较慢的机器。\\n\\n当前渲染分辨率 %.0f x %.0f。')
add(' Dynamic: %.0f%% of the display right now.', ' 动态：当前为显示器的 %.0f%%。')
add('3 (Default)', '3（默认）')
add('connected', '已连接')


RUN = re.compile(r'"(?:[^"\\]|\\.)*"(?:[ \t\r\n]*"(?:[^"\\]|\\.)*")*')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')


def raw(s):
    return s.replace('\\"', '"')


def apply_file(path, check_only):
    text = path.read_text(encoding='utf-8')
    hits = 0

    def run_sub(m):
        nonlocal hits
        parts = [raw(x) for x in LIT.findall(m.group(0))]
        merged = ''.join(parts)
        zh = DICT.get(merged)
        if zh is None:
            return m.group(0)
        hits += 1
        USED.add(merged)
        return '"' + zh + '"'

    global USED
    USED = set()
    out = RUN.sub(run_sub, text)

    def lit_sub(m):
        nonlocal hits
        parts = LIT.findall(m.group(0))
        if len(parts) != 1:  # 多段拼接已在上一轮处理，剩下的保持原样
            return m.group(0)
        en = raw(parts[0])
        zh = DICT.get(en)
        if zh is None:
            return m.group(0)
        hits += 1
        USED.add(en)
        return '"' + zh + '"'

    out = RUN.sub(lit_sub, out)
    if not check_only and out != text:
        path.write_text(out, encoding='utf-8')
    return hits


ALL_USED = set()


def main():
    global ALL_USED
    check_only = '--check' in sys.argv
    total = 0
    for name in FILES:
        p = UI / name
        n = apply_file(p, check_only)
        ALL_USED |= USED
        total += n
        print(f'{name:22s} 替换 {n} 处')
    print(f'\n合计 {total} 处')

    # 词典里没被任何文件命中的键（说明拼写与源码不一致）
    unused = [k for k in DICT if k not in ALL_USED]
    if unused:
        print(f'\n[提示] 有 {len(unused)} 条词典键未命中（拼写与源码不同，或已翻译过）：')
        for k in unused[:25]:
            print('   ·', k[:100])


if __name__ == '__main__':
    main()
