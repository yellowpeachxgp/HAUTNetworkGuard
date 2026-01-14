@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   HAUT Network Guard Windows 构建脚本
echo ==========================================
echo.

:: 设置变量
set PROJECT_DIR=%~dp0
set BUILD_DIR=%PROJECT_DIR%build
set BUILD_TYPE=Release

:: 解析参数
if "%1"=="debug" set BUILD_TYPE=Debug
if "%1"=="clean" goto :clean
if "%1"=="help" goto :help

:: 检查 Visual Studio
where cl >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 MSVC 编译器
    echo.
    echo 请从以下方式之一运行此脚本:
    echo   1. Visual Studio Developer Command Prompt
    echo   2. Visual Studio Developer PowerShell
    echo   3. 运行 vcvars64.bat 后执行此脚本
    echo.
    echo 或者安装 Visual Studio Build Tools:
    echo   https://visualstudio.microsoft.com/downloads/
    echo.
    exit /b 1
)

:: 检查 CMake
where cmake >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 CMake
    echo.
    echo 请安装 CMake:
    echo   https://cmake.org/download/
    echo.
    exit /b 1
)

:: 创建构建目录
echo [1/4] 准备构建目录...
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: 运行 CMake 配置
echo [2/4] 配置 CMake (%BUILD_TYPE%)...
cd /d "%BUILD_DIR%"
cmake -G "Visual Studio 17 2022" -A x64 ^
      -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
      "%PROJECT_DIR%"

if errorlevel 1 (
    echo.
    echo [错误] CMake 配置失败
    echo.
    echo 如果您使用的是 Visual Studio 2019, 请将 "Visual Studio 17 2022"
    echo 改为 "Visual Studio 16 2019"
    exit /b 1
)

:: 编译
echo.
echo [3/4] 编译项目...
cmake --build . --config %BUILD_TYPE% --parallel

if errorlevel 1 (
    echo.
    echo [错误] 编译失败
    exit /b 1
)

:: 整理输出
echo.
echo [4/4] 整理输出文件...
set OUTPUT_DIR=%BUILD_DIR%\output
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: 复制可执行文件
copy "%BUILD_DIR%\bin\%BUILD_TYPE%\HAUTNetworkGuard.exe" "%OUTPUT_DIR%\" >nul 2>&1
if not exist "%OUTPUT_DIR%\HAUTNetworkGuard.exe" (
    copy "%BUILD_DIR%\%BUILD_TYPE%\HAUTNetworkGuard.exe" "%OUTPUT_DIR%\" >nul 2>&1
)

:: 显示结果
echo.
echo ==========================================
echo   构建完成!
echo ==========================================
echo.

if exist "%OUTPUT_DIR%\HAUTNetworkGuard.exe" (
    echo 输出文件:
    echo   %OUTPUT_DIR%\HAUTNetworkGuard.exe
    echo.

    :: 显示文件大小
    for %%A in ("%OUTPUT_DIR%\HAUTNetworkGuard.exe") do (
        set SIZE=%%~zA
        set /a SIZE_KB=!SIZE! / 1024
        echo 文件大小: !SIZE_KB! KB
    )
) else (
    echo [警告] 未找到输出文件，请检查构建日志
)

echo.
echo 运行方式:
echo   双击 HAUTNetworkGuard.exe 启动
echo.

goto :eof

:clean
echo 清理构建目录...
if exist "%BUILD_DIR%" rd /s /q "%BUILD_DIR%"
echo 清理完成
goto :eof

:help
echo.
echo 使用方法:
echo   build.bat          - 构建 Release 版本
echo   build.bat debug    - 构建 Debug 版本
echo   build.bat clean    - 清理构建目录
echo   build.bat help     - 显示帮助
echo.
goto :eof
