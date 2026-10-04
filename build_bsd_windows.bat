@echo off
rem GovechoBSD Windows Builder (ZHBR-228, MIT)
setlocal
cd /d "%~dp0"
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*)
endlocal
