@echo off
setlocal
cd /d "%~dp0"
if not defined ZAMER_BIND_IP (
 for /f "delims=" %%I in ('powershell -NoProfile -Command "$a=Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -and $_.AddressState -eq 'Preferred' } | Select-Object -First 1; if($a){$a.IPAddress}"') do set "ZAMER_BIND_IP=%%I"
)
if not defined ZAMER_BIND_IP (
 echo Could not detect the home Wi-Fi IPv4 address. Set ZAMER_BIND_IP before starting.
 pause
 exit /b 1
)
echo Zamer+ home receiver: %ZAMER_BIND_IP%:8787
node receiver.js
if errorlevel 1 (
 echo Zamer+ receiver failed. Ensure Node.js is installed and TCP 8787 is available.
 pause
)
