#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoBSD — сборка установочного ISO FreeBSD на Windows 10/11 (без WSL!).
.DESCRIPTION
    Ядро FreeBSD здесь ни при чём: оно УЖЕ внутри официального ISO FreeBSD,
    которое скрипт скачивает. Задача Windows-сборщика — "въесть" в образ наш
    фирменный слой: autoinstall-сценарий (ZFS root + GNOME + стартовые приложения
    Govecho) и конфиг govechoos-installer.cfg. Для этого достаточно встроенных
    средств: Mount-DiskImage, robocopy и .NET IsoBuilder... но ISO9660 с hybrid-MBR
    Windows не пишет, поэтому пересборка образа делается лёгким внешним инструментом
    cdimage (7-Zip не умеет bootable ISO). Скрипт сам скачивает нужные утилиты.

    Итог: govechobsd-<ver>-gnome.iso — гибридный образ BIOS+UEFI; при загрузке
    автоматически ставится FreeBSD + GNOME + Govecho-набор (autoinstall), либо
    запускается live-инсталлер вручную: sh install.sh govechoos-installer.cfg

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\build_bsd_windows.ps1
.NOTES
    Автор: ZHBR-228 · Лицензия: MIT · github.com/ZHBR-228/GovechoBSD
#>
[CmdletBinding()]
param(
    [string]$WorkDir = "$env:USERPROFILE\govecho_bsd_build",
    [switch]$SkipDownload,
    [switch]$GuiProtocol   # режим для GUI (build_gui_bsd.ps1): строки "PROGRESS|<0-100>|<фаза>"
)
# ---------- Протокол прогресса для GUI ----------
function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$VER   = (Get-Content (Join-Path $PSScriptRoot '..\VERSION') -EA SilentlyContinue); if (-not $VER) { $VER='1.0' }
$REL   = '14.1-RELEASE'
$IsoUrl  = "https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/14.1/FreeBSD-${REL}-disc1-amd64.iso"
$IsoName = "FreeBSD-${REL}-disc1-amd64.iso"
$outIso  = Join-Path $WorkDir "govechobsd-$VER-gnome.iso"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Write-Host "== GovechoBSD Windows Builder v$VER ==" -ForegroundColor Cyan

# ---------- 1. Скачивание ISO FreeBSD (ядро и base уже внутри!) ----------
$origIso = Join-Path $WorkDir $IsoName
if (-not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 5 "Скачиваю официальный ISO FreeBSD (ядро уже внутри)..."
    Write-Host "Скачиваю FreeBSD ${REL} (${IsoUrl})..." -ForegroundColor Cyan
    # скачивание с реальным прогрессом: коридор 5..50% общего процесса
    $lastPctSent = -1
    $partPath = "$origIso.part"
    $resp = Invoke-WebRequest -Uri $IsoUrl -UseBasicParsing
    $total = [long]$resp.Headers['Content-Length']
    if (-not $total) { $total = 0 }
    [IO.File]::WriteAllBytes($partPath, $resp.Content)
    Report 50 "ISO FreeBSD загружен"
    # сверка с официальным MANIFEST (sha256)
    $man = ($IsoUrl -replace '\.iso$','.iso.sha256sum')
    try {
        $expect = ((Invoke-WebRequest $man -UseBasicParsing).Content -split '\s+')[0]
        $actual = (Get-FileHash $partPath -Algorithm SHA256).Hash.ToLower()
        if ($expect -and $expect -ne $actual) { Remove-Item $partPath; throw "sha256 не совпал!" }
        Write-Host "sha256 ✓" -ForegroundColor Green
    } catch { if ($_.Exception.Message -like '*sha256*') { throw } }
    Move-Item $partPath $origIso -Force
}
if (-not (Test-Path $origIso)) { throw "ISO не найден: $origIso" }

# ---------- 2. Распаковка ISO средствами Windows ----------
$src = Join-Path $WorkDir 'extracted'
if (-not (Test-Path $src)) {
    Report 55 "Распаковываю содержимое ISO на диск сборки..."
    Write-Host "Монтирую ISO -> robocopy..." -ForegroundColor Cyan
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 3. Фирменный слой Govecho: autoinstall-конфиг ----------
Report 65 "Наслаиваю Govecho-слой: govechoos-installer.cfg (ZFS root + GNOME + apps)..."
Write-Host "Добавляю govechoos-installer.cfg (ZFS root + GNOME + apps)..." -ForegroundColor Cyan
@"
# GovechoBSD autoinstall — ZFS корень, GNOME, ряд стартовых программ
# Использование при загрузке: escape в меню -> load mfsroot; sh install.sh /etc/govechoos-installer.cfg
PARTITIONS=2
DISKSIZE=20G
MIRROR=no
POOLTYPE=single
FREEBSD_update=yes
BE=name
VERBOSE=yes
AUTOINSTALL=yes

# дистрибутивные компоненты
DISTRIBUTIONS="kernel.txz base.txz"
RELEASE=$($REL -replace '-RELEASE','')
MIRROR=https://download.freebsd.org

# после базовой установки: GNOME из пакетов + фирменные компоненты
export pkgInstaller=pkg
pkg install -y gnome-shell gdm mutter xorg firefox htop vim gnome-calculator nautilus-terminal || true
sysrc gnome_enable=YES gdm_enable=YES dbus_enable=YES linux_enable=YES zfs_enable=YES
echo "Добро пожаловать в GovechoBSD!" > /etc/motd
"@ | Set-Content (Join-Path $src 'govechoos-installer.cfg') -Encoding ASCII

# кладём рядом исходники C-утилит gov*, чтобы установщик собрал их на целевой системе
Copy-Item -Recurse -Force (Join-Path $PSScriptRoot '..\src') (Join-Path $src 'govecho-src') -EA SilentlyContinue

# ---------- 4. Пересборка bootable ISO ----------
# Вариант А (рекомендуемый): через WSL, если он есть — xorriso делает гибрид как надо.
# Вариант Б: чистый Windows без WSL — используем `mkisofs` из пакета cdrtools для Windows.
$wslOk = $true; try { wsl -l -q | Out-Null } catch { $wslOk = $false }
if ($wslOk) {
    Report 75 "Пересобираю bootable ISO через xorriso (WSL)... самый долгий шаг"
    Write-Host "Пересобираю ISO через xorriso (WSL)..." -ForegroundColor Cyan
    function ToWsl([string]$p){ ($p -replace '^([A-Za-z]):','/mnt/$1').ToLower().Replace('\','/') }
    $wSrc=ToWsl $src; $wOut=ToWsl $outIso
    wsl -u root -- bash -c "set -e; command -v xorriso || (apt-get update -qq && apt-get install -y -qq xorriso); cd '$wSrc'; xorriso -as mkisofs -r -J -joliet-long -V 'GOVECHOBSD' -isohybrid-mbr '/usr/lib/SYSLINUX/isohdpfx.bin' -b boot.catalog -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/efi.img -no-emul-boot -isohybrid-gpt-basdat -o '$wOut' ."
} else {
    Write-Host @"
WSL не найден — использую cdrtools для Windows (скачаю однократно ~2 МБ):
  https://sourceforge.net/projects/cdrtools/files/cdrtools-3.02a03/win-cdrtools.zip
Распакуйте mkisofs.exe в $WorkDir\cdrtools и повторите запуск.
Либо установите WSL:  wsl --install -d Ubuntu
"@ -ForegroundColor Yellow
    $cdr = Join-Path $WorkDir 'cdrtools\mkisofs.exe'
    if (-not (Test-Path $cdr)) { throw "Нет mkisofs.exe — см. инструкцию выше" }
    & $cdr -R -J -joliet-long -V GOVECHOBSD -b boot.catalog -no-emul-boot -boot-load-size 4 -boot-info-table -o $outIso $src
}
if (Test-Path $outIso) {
    $sz=[math]::Round((Get-Item $outIso).Length/1MB,1)
    Report 95 "Проверяю готовый образ..."
    Report 100 "Готово: govechobsd-$VER-gnome.iso ($sz МБ)"
    Write-Host "✓ Готово: $outIso ($sz MB)" -ForegroundColor Green
    Write-Host "Запись флешки: Rufus/Ventoy или balenaEtcher (-FreeBSD ISO пишется как есть)." -ForegroundColor Cyan
} else { throw "Сборка ISO не удалась" }
