@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0课表导入软件\课表导入程序.exe" (
    echo 找不到已构建的课表导入程序。
    echo 请先运行 build_exe.ps1 生成发布文件。
    pause
    exit /b 1
)
start "" "%~dp0课表导入软件\课表导入程序.exe"
endlocal
