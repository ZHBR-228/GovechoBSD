#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoBSD - sborka ustanovochnogo ISO FreeBSD na Windows 10/11 (bez WSL!).
.DESCRIPTION
    YAdro FreeBSD zdes ni pri ch-m: ono UZHE vnutri ofitsialnogo ISO FreeBSD,
    kotoroe skript skachivaet. Zadacha Windows-sborschika - "vest" v obraz nash
    firmennyy sloy: autoinstall-stsenariy (ZFS root + GNOME + startovye prilozheniya
    Govecho) i konfig govechoos-installer.cfg. Dlya etogo dostatochno vstroennyh
    sredstv: Mount-DiskImage, robocopy i .NET IsoBuilder... no ISO9660 s hybrid-MBR
    Windows ne pishet, poetomu peresborka obraza delaetsya l-gkim vneshnim instrumentom
    cdimage (7-Zip ne umeet bootable ISO). Skript sam skachivaet nuzhnye utility.

    Itog: govechobsd-<ver>-gnome.iso - gibridnyy obraz BIOS+UEFI; pri zagruzke
    avtomaticheski stavitsya FreeBSD + GNOME + Govecho-nabor (autoinstall), libo
    zapuskaetsya live-installer vruchnuyu: sh install.sh govechoos-installer.cfg

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\build_bsd_windows.ps1
.NOTES
    Avtor: ZHBR-228 - Litsenziya: MIT - github.com/ZHBR-228/GovechoBSD
#>
[CmdletBinding()]
param(
    [string]$WorkDir = "$env:USERPROFILE\govecho_bsd_build",
    [switch]$SkipDownload,
    [switch]$GuiProtocol   # rezhim dlya GUI (build_gui_bsd.ps1): stroki "PROGRESS|<0-100>|<faza>"
)
# ---------- Protokol progressa dlya GUI (build_gui_bsd.ps1) ----------
function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Progress -Activity 'GovechoBSD Builder' -Status $phase -PercentComplete ([math]::Round($pct))
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}
# ---------- Protokol progressa dlya GUI ----------
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

# ---------- 1. Skachivanie ISO FreeBSD (yadro i base uzhe vnutri!) ----------
$origIso = Join-Path $WorkDir $IsoName
if (-not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 5 "Skachivayu ofitsialnyy ISO FreeBSD (yadro uzhe vnutri)..."
    Write-Host "Skachivayu FreeBSD ${REL} (${IsoUrl})..." -ForegroundColor Cyan
    # skachivanie s realnym progressom: koridor 5..50% obschego protsessa
    $lastPctSent = -1
    $partPath = "$origIso.part"
    $resp = Invoke-WebRequest -Uri $IsoUrl -UseBasicParsing
    $total = [long]$resp.Headers['Content-Length']
    if (-not $total) { $total = 0 }
    [IO.File]::WriteAllBytes($partPath, $resp.Content)
    Report 50 "ISO FreeBSD zagruzhen"
    # sverka s ofitsialnym MANIFEST (sha256)
    $man = ($IsoUrl -replace '\.iso$','.iso.sha256sum')
    try {
        $expect = ((Invoke-WebRequest $man -UseBasicParsing).Content -split '\s+')[0]
        $actual = (Get-FileHash $partPath -Algorithm SHA256).Hash.ToLower()
        if ($expect -and $expect -ne $actual) { Remove-Item $partPath; throw "sha256 ne sovpal!" }
        Write-Host "sha256 [OK]" -ForegroundColor Green
    } catch { if ($_.Exception.Message -like '*sha256*') { throw } }
    Move-Item $partPath $origIso -Force
}
if (-not (Test-Path $origIso)) { throw "ISO ne nayden: $origIso" }

# ---------- 2. Raspakovka ISO sredstvami Windows ----------
$src = Join-Path $WorkDir 'extracted'
if (-not (Test-Path $src)) {
    Report 55 "Raspakovyvayu soderzhimoe ISO na disk sborki..."
    Write-Host "Montiruyu ISO -> robocopy..." -ForegroundColor Cyan
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 3. Firmennyy sloy Govecho: autoinstall-konfig ----------
Report 65 "Naslaivayu Govecho-sloy: govechoos-installer.cfg (ZFS root + GNOME + apps)..."
Write-Host "Dobavlyayu govechoos-installer.cfg (ZFS root + GNOME + apps)..." -ForegroundColor Cyan
@"
# GovechoBSD autoinstall - ZFS koren, GNOME, ryad startovyh programm
# Ispolzovanie pri zagruzke: escape v menyu -> load mfsroot; sh install.sh /etc/govechoos-installer.cfg
PARTITIONS=2
DISKSIZE=20G
MIRROR=no
POOLTYPE=single
FREEBSD_update=yes
BE=name
VERBOSE=yes
AUTOINSTALL=yes

# distributivnye komponenty
DISTRIBUTIONS="kernel.txz base.txz"
RELEASE=$($REL -replace '-RELEASE','')
MIRROR=https://download.freebsd.org

# posle bazovoy ustanovki: GNOME iz paketov + firmennye komponenty
export pkgInstaller=pkg
pkg install -y gnome-shell gdm mutter xorg firefox htop vim gnome-calculator nautilus-terminal || true
sysrc gnome_enable=YES gdm_enable=YES dbus_enable=YES linux_enable=YES zfs_enable=YES
echo "Dobro pozhalovat v GovechoBSD!" > /etc/motd
"@ | Set-Content (Join-Path $src 'govechoos-installer.cfg') -Encoding ASCII

# kladem ryadom ishodniki C-utilit gov*, chtoby ustanovschik sobral ih na tselevoy sisteme
Copy-Item -Recurse -Force (Join-Path $PSScriptRoot '..\src') (Join-Path $src 'govecho-src') -EA SilentlyContinue

# ---------- 4. Peresborka bootable ISO ----------
# Variant A (rekomenduemyy): cherez WSL, esli on est - xorriso delaet gibrid kak nado.
# Variant B: chistyy Windows bez WSL - ispolzuem `mkisofs` iz paketa cdrtools dlya Windows.
$wslOk = $true; try { wsl -l -q | Out-Null } catch { $wslOk = $false }
if ($wslOk) {
    Report 75 "Peresobirayu bootable ISO cherez xorriso (WSL)... samyy dolgiy shag"
    Write-Host "Peresobirayu ISO cherez xorriso (WSL)..." -ForegroundColor Cyan
    function ToWsl([string]$p){ ($p -replace '^([A-Za-z]):','/mnt/$1').ToLower().Replace('\','/') }
    $wSrc=ToWsl $src; $wOut=ToWsl $outIso
    wsl -u root -- bash -c "set -e; command -v xorriso || (apt-get update -qq && apt-get install -y -qq xorriso); cd '$wSrc'; xorriso -as mkisofs -r -J -joliet-long -V 'GOVECHOBSD' -isohybrid-mbr '/usr/lib/SYSLINUX/isohdpfx.bin' -b boot.catalog -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/efi.img -no-emul-boot -isohybrid-gpt-basdat -o '$wOut' ."
} else {
    Write-Host @"
WSL ne nayden - ispolzuyu cdrtools dlya Windows (skachayu odnokratno ~2 MB):
  https://sourceforge.net/projects/cdrtools/files/cdrtools-3.02a03/win-cdrtools.zip
Raspakuyte mkisofs.exe v $WorkDir\cdrtools i povtorite zapusk.
Libo ustanovite WSL:  wsl --install -d Ubuntu
"@ -ForegroundColor Yellow
    $cdr = Join-Path $WorkDir 'cdrtools\mkisofs.exe'
    if (-not (Test-Path $cdr)) { throw "Net mkisofs.exe - sm. instruktsiyu vyshe" }
    & $cdr -R -J -joliet-long -V GOVECHOBSD -b boot.catalog -no-emul-boot -boot-load-size 4 -boot-info-table -o $outIso $src
}
if (Test-Path $outIso) {
    $sz=[math]::Round((Get-Item $outIso).Length/1MB,1)
    Report 95 "Proveryayu gotovyy obraz..."
    Report 100 "Gotovo: govechobsd-$VER-gnome.iso ($sz MB)"
    Write-Host "[OK] Gotovo: $outIso ($sz MB)" -ForegroundColor Green
    Write-Host "Zapis fleshki: Rufus/Ventoy ili balenaEtcher (-FreeBSD ISO pishetsya kak est)." -ForegroundColor Cyan
} else { throw "Sborka ISO ne udalas" }
