@echo off
setlocal
cd /d "%~dp0"
set "TS=%ProgramFiles%\Tailscale\tailscale.exe"
if not exist "%TS%" (
 echo Tailscale is not installed. Install and sign in first.
 pause
 exit /b 1
)
set "ZAMER_BIND_IP="
for /f "delims=" %%I in ('"%TS%" ip -4 2^>nul') do set "ZAMER_BIND_IP=%%I"
if not defined ZAMER_BIND_IP (
 echo Tailscale is not connected. Sign in on PC and iPhone.
 pause
 exit /b 1
)
echo Zamer+ private VPN receiver: %ZAMER_BIND_IP%:8787
node receiver.js
if errorlevel 1 (
 echo Zamer+ remote receiver failed. Check that Node.js and Tailscale are running.
 pause
)
