@echo off
chcp 65001 >nul
setlocal
title SkyRecomp 简体中文界面 - 一键编译

rem =====================================================================
rem  编译汉化后的 skyrecomp.exe，并把中间文件清干净
rem  依赖：MSYS2 已安装在 C:\msys64（UCRT64 环境）
rem
rem  流程：编译 -> 把成品拷到本目录 -> 删除 build 等临时文件
rem  不碰游戏目录，编完自己把 skyrecomp.exe 拖过去覆盖即可
rem =====================================================================

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "BUILD=%SRC%\build\win-release"
set "OUT=%BUILD%\skyrecomp.exe"
set "FINAL=%SRC%\skyrecomp.exe"
set "JOBS=8"

echo ============================================================
echo    SkyRecomp 简体中文界面 - 一键编译
echo ============================================================
echo    源码目录：%SRC%
echo.

if not exist "C:\msys64\usr\bin\bash.exe" goto :no_msys
if not exist "%SRC%\Makefile"                goto :no_src
if not exist "%SRC%\runtime\ui\zh_glyphs.h"  goto :no_glyphs

rem ---------------------------------------------------------------- 编译
echo [1/2] 编译中（首次约 3-8 分钟，请不要关闭窗口）...
echo ------------------------------------------------------------
set "MSYSTEM=UCRT64"
set "CHERE_INVOKING=1"
"C:\msys64\usr\bin\bash.exe" -lc "cd \"$(cygpath -u '%SRC%')\" && make -j%JOBS% B=build/win-release RELEASE=1 build/win-release/skyrecomp.exe"
if errorlevel 1 goto :build_fail
echo ------------------------------------------------------------

if not exist "%OUT%" goto :no_output

rem ---------------------------------------------------------------- 提取成品 + 清理
echo.
echo [2/2] 提取成品并清理临时文件

copy /y "%OUT%" "%FINAL%" >nul
if errorlevel 1 goto :copy_fail
for %%I in ("%FINAL%") do echo        成品：%%~fI
for %%I in ("%FINAL%") do echo        大小：%%~zI 字节

rem 编译中间文件（.o、.a、链接临时目录等）
if exist "%SRC%\build" (
    rmdir /s /q "%SRC%\build" 2>nul
    if exist "%SRC%\build" (
        echo        注意：build 目录有文件被占用，未能全部删除
    ) else (
        echo        已删除 build\
    )
)

rem 生成代码 / 临时清单 / 缓存
for %%D in ("%SRC%\generated" "%SRC%\tools\__pycache__") do (
    if exist "%%~D" (
        rmdir /s /q "%%~D" 2>nul
        if not exist "%%~D" echo        已删除 %%~nxD\
    )
)
del /q "%SRC%\tools\_*.txt" 2>nul
del /q "%SRC%\*.log" 2>nul

echo.
echo ============================================================
echo  完成
echo.
echo  成品位置：%FINAL%
echo.
echo  应用方法：把上面这个 skyrecomp.exe 复制到游戏安装目录，
echo            覆盖同名文件即可。DLL、ini、mods、reshade 都不用动。
echo.
echo  提示：临时文件已清理，下次编译会全量重编（约 3-8 分钟）。
echo        想保留增量编译就别删 build 目录，改本脚本最后一段即可。
echo ============================================================
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

:build_fail
echo.
echo [失败] 编译没有通过。请把上面报错的几行发给我。
echo        中间文件已保留在 build\，方便下次增量重试。
goto :fail

:no_output
echo [失败] make 执行完了，但没有生成 %OUT%
goto :fail

:copy_fail
echo [失败] 无法把成品拷到源码目录（文件被占用？）
goto :fail

:fail
echo.
pause
exit /b 1

:end
echo.
pause
exit /b 0
