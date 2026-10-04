@echo off
rem GovechoBSD Builder launcher (ZHBR-228, MIT)
setlocal
cd /d "%~dp0"
if "%1"=="-Console" ( shift & goto console )
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1 %*)
if errorlevel 1 (
    echo.
    echo [GovechoBSD] GUI failed to start. Run manually from PowerShell:
    echo     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1
    pause
)
goto :eof
:console
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*)
endlocal
