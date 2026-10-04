@echo off
chcp 866 >nul 2>nul
rem GovechoBSD Builder - двойной щелчок открывает окно с прогрессом сборки ISO FreeBSD (ZHBR-228, MIT)
rem Консольный режим без окна: build_bsd_windows.bat -Console [...параметры билдера]
setlocal
cd /d "%~dp0"
if "%1"=="-Console" ( shift & goto console )
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1 %*)
if errorlevel 1 (
    echo.
    echo [GovechoBSD] Окно не открылось? Запустите вручную из PowerShell:
    echo     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1
    pause
)
goto :eof
:console
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*)
endlocal
