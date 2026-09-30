@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo === DeepSeek Harness 鲸鱼娘桌宠（调试模式）===
echo 关闭本窗口即退出桌宠。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WhalePet.ps1" -Log
pause
