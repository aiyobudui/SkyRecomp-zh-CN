@echo off
chcp 65001 >nul
setlocal
title SkyRecomp 简体中文界面 - 一键编译

rem =====================================================================
rem  把汉化源码编译成 skyrecomp.exe，并（可选）覆盖到游戏目录
rem  依赖：MSYS2 已安装在 C:\msys64（UCRT64 环境）
rem  说明：官方发行包用的就是 MSYS2 UCRT64 的 SDL3 / FFmpeg / shaderc，
rem        DLL 版本完全一致，所以不需要跑耗时的 make deps-windows
rem =====================================================================

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
for %%I in ("%SRC%\..\SkyRecomp-v2.1-Windows") do set "GAME=%%~fI"
set "OUT=%SRC%\build\win-release\skyrecomp.exe"
set "JOBS=8"

echo ============================================================
echo    SkyRecomp 简体中文界面 - 本地编译
echo ============================================================
echo    源码目录：%SRC%
echo    游戏目录：%GAME%
echo.

if not exist "C:\msys64\usr\bin\bash.exe" goto :no_msys
if not exist "%SRC%\Makefile"            goto :no_src
if not exist "%SRC%\runtime\ui\zh_glyphs.h" goto :no_glyphs
if not exist "%GAME%\skyrecomp.exe"      goto :no_game

rem ---------------------------------------------------------------- 备份
echo [1/3] 备份原版 exe
if exist "%GAME%\skyrecomp.exe.orig" (
    echo        已存在 skyrecomp.exe.orig，跳过备份
) else (
    copy /y "%GAME%\skyrecomp.exe" "%GAME%\skyrecomp.exe.orig" >nul
    if errorlevel 1 goto :backup_fail
    echo        已备份为 skyrecomp.exe.orig
)

rem ---------------------------------------------------------------- 编译
echo.
echo [2/3] 编译中（首次约 3-8 分钟，请不要关闭窗口）...
echo ------------------------------------------------------------
set "MSYSTEM=UCRT64"
set "CHERE_INVOKING=1"
"C:\msys64\usr\bin\bash.exe" -lc "cd \"$(cygpath -u '%SRC%')\" && make -j%JOBS% B=build/win-release RELEASE=1 build/win-release/skyrecomp.exe"
if errorlevel 1 goto :build_fail
echo ------------------------------------------------------------

if not exist "%OUT%" goto :no_output

echo.
echo [3/3] 编译成功
for %%I in ("%OUT%") do echo        产物：%%~fI
for %%I in ("%OUT%") do echo        大小：%%~zI 字节
echo.
choice /c YN /n /m "现在覆盖到游戏目录吗？(Y=覆盖 / N=先不覆盖) "
if errorlevel 2 goto :keep

copy /y "%OUT%" "%GAME%\skyrecomp.exe" >nul
if errorlevel 1 goto :copy_fail

echo.
echo ============================================================
echo  完成。直接启动游戏就能看到中文界面。
echo.
echo  原版备份：%GAME%\skyrecomp.exe.orig
echo  想回滚：把 skyrecomp.exe.orig 改名为 skyrecomp.exe
echo ============================================================
goto :end

:keep
echo.
echo 已保留编译产物，未覆盖游戏目录：
echo   %OUT%
goto :end

rem ---------------------------------------------------------------- 错误分支
:no_msys
echo [错误] 没找到 MSYS2：C:\msys64\usr\bin\bash.exe
echo        请先安装 MSYS2，并在 UCRT64 终端里执行：
echo        pacman -S --needed mingw-w64-ucrt-x86_64-clang mingw-w64-ucrt-x86_64-lld make ^
echo          mingw-w64-ucrt-x86_64-sdl3 mingw-w64-ucrt-x86_64-ffmpeg ^
echo          mingw-w64-ucrt-x86_64-vulkan-devel mingw-w64-ucrt-x86_64-shaderc
goto :fail

:no_src
echo [错误] 这个 bat 必须放在源码目录里（与 Makefile 同级）：
echo        %SRC%\Makefile 不存在
goto :fail

:no_glyphs
echo [错误] 缺少中文字形头文件：runtime\ui\zh_glyphs.h
echo        在源码目录执行：python tools/zh_glyphs.py
goto :fail

:no_game
echo [错误] 没找到游戏目录：%GAME%\skyrecomp.exe
echo        如果你的游戏装在别处，请手动把编译产物
echo        %OUT%
echo        复制过去覆盖 skyrecomp.exe
goto :fail

:backup_fail
echo [错误] 备份失败，请确认游戏没有在运行
goto :fail

:build_fail
echo.
echo [失败] 编译没有通过。请把上面红色/报错的几行发给我。
goto :fail

:no_output
echo [失败] make 执行完了，但没有生成 %OUT%
echo        请在 UCRT64 终端里手动执行一次 make 看具体报错
goto :fail

:copy_fail
echo [失败] 覆盖失败，游戏可能正在运行，关掉后重试
goto :fail

:fail
echo.
pause
exit /b 1

:end
echo.
pause
exit /b 0
