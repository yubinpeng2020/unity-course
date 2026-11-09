@echo off
title C# 课件局域网服务
cd /d "%~dp0"

echo ================================================
echo    C# 课件 - 局域网访问服务
echo    （关闭本窗口 = 停止服务）
echo ================================================
echo.

REM ---------- 获取本机 IPv4 地址 ----------
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do set "IP=%%a"
set "IP=%IP: =%"
if "%IP%"=="" set "IP=127.0.0.1"

echo    本机 IP: %IP%
echo    学生访问: http://%IP%:8000/
echo    本机测试: http://127.0.0.1:8000/
echo.

REM ---------- 使用 PowerShell 启动（Windows 自带，无需安装 Python） ----------
echo [方式] PowerShell（无需安装任何软件）
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
goto :end

:end
echo.
echo 服务已停止。
pause
