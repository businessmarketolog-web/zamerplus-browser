@echo off
cd /d "%~dp0"
node receiver.js
if errorlevel 1 (
 echo Node.js не найден. Установите Node.js LTS с https://nodejs.org/ и запустите снова.
 pause
)
