@echo off
chcp 936 >nul
title 数字产品设计（Unity）课件 - 局域网服务
cd /d "%~dp0"

echo ================================================
echo    数字产品设计（Unity）课件 - 局域网访问服务
echo    （关闭本窗口 = 停止服务）
echo ================================================
echo.
echo   提示：学生连不上，先在自己电脑上打开
echo         http://127.0.0.1:8000/  看能不能打开
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo 服务异常退出（代码 %RC%），把上面的提示发我。
pause
