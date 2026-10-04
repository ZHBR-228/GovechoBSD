#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoBSD - sborka FreeBSD+GNOME ISO na Windows.
.DESCRIPTION
    Iznachalno kachaet FreeBSD disc1 (yadro uzhe est'!). Novoe: -IsoPath -
    uzhe skhannyy pol''zovatelem FreeBSD-ISO; tip opredelyaetsya po imeni
    fayla (FreeBSD*/boothui*/disc1*). Slayvanie: loader.conf/rc.conf/GNOME
    manifest -> newfs/mkhybrid (cherez WSL) -> govechobsd ISO.
    Skript NE zapisyvaet obraz na nositeli.
.NOTES
    Avtor: ZHBR-228 | Litsenziya: MIT | github.com/ZHBR-228/GovechoBSD
#>
[CmdletBinding()]
param(
    [string]$IsoPath = '',
    [string]$WorkDir = "$env:USERPROFILE\govecho_bsd_build",
    [switch]$SkipDownload,
    [switch]$GuiProtocol
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Progress -Activity 'GovechoBSD Builder' -Status $phase -PercentComplete ([math]::Round($pct))
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}

$VER = (Get-Content (Join-Path $PSScriptRoot '..\VERSION') -EA SilentlyContinue); if (-not $VER) { $VER='1.0' }
$REL = '14.1-RELEASE'
$IsoUrl  = "https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/14.1/FreeBSD-${REL}-disc1-amd64.iso"
$IsoName = "FreeBSD-${REL}-disc1-amd64.iso"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ---------- 0. Istochnik: lokalnyy FreeBSD-ISO ili URL ----------
$origIso = ''
if ($IsoPath) {
    if (-not (Test-Path $IsoPath)) { throw "Ukazannyj ISO ne nayden: $IsoPath" }
    $origIso = (Resolve-Path $IsoPath).Path
    $nm = [IO.Path]::GetFileName($origIso).ToLower()
    $ok = ($nm -match 'freebsd') -or ($nm -match 'disc1') -or ($nm -match 'bootonly') -or ($nm -match 'dvd1')
    if (-not $ok) { throw "Fayl ne pakhodit na FreeBSD-ISO (imya: $nm). Ozhidalsya FreeBSD*disc1/dvd1/bootonly." }
    Report 5 ("Istochnik: lokalnyy FreeBSD ISO: " + $origIso)
} else {
    $origIso = Join-Path $WorkDir $IsoName
    Report 5 "Konfiguratsiya zagruzhen (baza: FreeBSD $REL)"
}
Write-Host "== GovechoBSD Windows Builder v$VER ==" -ForegroundColor Cyan
$outIso = Join-Path $WorkDir "govechobsd-$VER-gnome.iso"

# ---------- 1. Zagruzka FreeBSD-ISO (yadro i base uze vnutri!) ----------
if (-not $IsoPath -and -not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 10 "Skachivayu FreeBSD ISO: $IsoUrl"
    $wc = New-Object System.Net.WebClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dlArgs = {
        param($s, $e)
        if ($e.ProgressPercentage -ge 0) {
            $overall = 10 + ($e.ProgressPercentage * 0.35)
            $mbps = if ($sw.Elapsed.TotalSeconds -gt 1) { [math]::Round($e.BytesReceived/1MB/$sw.Elapsed.TotalSeconds,1) } else { 0 }
            [Console]::Out.WriteLine(("PROGRESS|{0}|Download FreeBSD ISO... {1} MB/s" -f [math]::Round($overall), $mbps))
            [Console]::Out.Flush()
        }
    }
    Register-ObjectEvent $wc DownloadProgressChanged -SourceIdentifier dlprog -Action $dlArgs | Out-Null
    $wc.DownloadFile($IsoUrl, "$origIso.part")
    Unregister-Event -SourceIdentifier dlprog -EA SilentlyContinue
    $wc.Dispose()
    Move-Item "$origIso.part" $origIso -Force
}
if (-not (Test-Path $origIso)) { throw "FreeBSD ISO ne nayden: $origIso" }

# ---------- 2. Raspakovka ----------
$src = Join-Path $WorkDir 'extracted'
if (-not (Test-Path $src)) {
    Report 48 "Raspakovyvayu FreeBSD ISO..."
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 3. Naslayvanie Govecho-sloya ----------
Report 62 "Naslaivayu konfiguratsiyu GovechoBSD (loader/rc/GNOME manifest)..."
$gv = Join-Path $src 'govecho'
New-Item -ItemType Directory -Force -Path $gv | Out-Null
foreach ($f in @('bsd/loader.conf','bsd/rc.conf','bsd/sysctl.conf','config/packages.freebsd.list')) {
    $host_f = Join-Path $PSScriptRoot ('..\..' + '\' + ($f -replace '/','\'))
    $alt    = Join-Path (Split-Path $PSScriptRoot) ('..' + '\' + ($f -replace '/','\'))
    foreach ($cand in @($host_f, $alt)) {
        if (Test-Path $cand) { Copy-Item $cand $gv -Force; break }
    }
}
# --- GNOME-privyazki: razkladyvaem faily iz gnome/bsd po katalogam ISO ---
$gdir = Join-Path $PSScriptRoot '..\gnome\bsd'
$mpath = Join-Path $gdir 'manifest.json'
if (Test-Path $mpath) {
    $man = Get-Content $mpath -Raw | ConvertFrom-Json
    foreach ($e in $man.files) {
        $sF = Join-Path $PSScriptRoot ('..' + '\' + ($e.src -replace '/','\'))
        if (Test-Path $sF) {
            $dD = Join-Path $src ($e.dst -replace '/','\')
            New-Item -ItemType Directory -Force -Path (Split-Path $dD) | Out-Null
            Copy-Item $sF $dD -Force
        }
    }
    Report 64 ("GNOME: razlozheno faizlov: " + @($man.files).Count)
} elseif (Test-Path $gdir) {
    Get-ChildItem $gdir -File | Where-Object Name -ne 'manifest.json' | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $gv $_.Name) -Force }
}

@"
#!/bin/sh
# GovechoBSD post-install hook: GNOME + start apps + zfs boot environment
pkg install -y gnome-shell gdm mutter gnome-session gnome-terminal nautilus \
  gnome-calculator gnome-system-monitor firefox htop vim 2>/dev/null \
  || pkg install -y gnome firefox
sysrc gnome_enable="YES" gdm_enable="YES" dbus_enable="YES" zfs_enable="YES" linux_enable="YES"
# perenos GNOME-privyazok Govecho iz CDROM-obraza na sistemnyy disk:
cp -n /cdrom/govecho/sessions/*.desktop /usr/local/share/wayland-sessions/ 2>/dev/null || true
cp -n /cdrom/govecho/autostart/*.desktop /usr/local/etc/xdg/autostart/ 2>/dev/null || true
cp -n /cdrom/govecho/applications/*.desktop /usr/local/share/applications/ 2>/dev/null || true
mkdir -p /usr/local/etc/dconf/db/local.d
cp -n /cdrom/govecho/dconf/30-govechoos /usr/local/etc/dconf/db/local.d/ 2>/dev/null || true
cp -n /cdrom/govecho/gdm/custom.conf /usr/local/etc/gdm/custom.conf 2>/dev/null || true
dconf update 2>/dev/null || true
echo 'GovechoBSD: GNOME established + privyazki pereneseny. Sessiya GovechoBSD v GDM.'
"@ | Set-Content (Join-Path $gv 'postinstall.sh') -Encoding ASCII

# ---------- 4. Peresborka ISO (mkisofs/newfs cherez WSL) ----------
Report 75 "Peresobirayu bootable FreeBSD ISO..."
function ToWslPath([string]$p) { ($p -replace '^([A-Za-z]):', '/mnt/$1').ToLower().Replace('\','/') }
$wSrc = ToWslPath $src; $wOut = ToWslPath $outIso
wsl -u root -- bash -c "command -v mkisofs >/dev/null || (apt-get update -qq && apt-get install -y -qq genisoimage)"
# FreeBSD boot catalog: perebiraem s sohraneniem boot-fragments (boot.catalog/efi)
wsl -u root -- bash -c "set -e; cd '$wSrc'; mkisofs -r -J -joliet-long -V GOVECHOBSD -allow-leading-dots -relaxed-filenames -b boot/cd1/boot.catalog -c bootinfo -no-emul-boot -boot-load-size 4 -boot-info-table -o '$wOut' ."
if (-not (Test-Path $outIso)) { throw "Ne udalos sobrat BSD-ISO" }
$szMB = [math]::Round((Get-Item $outIso).Length/1MB,1)
Report 100 "DONE: govechobsd-$VER-gnome.iso ($szMB MB)"
Write-Host "- DONE: $outIso ($szMB MB)" -ForegroundColor Green
Write-Host @"

- Sborka zavershena. Fayl: $outIso ($szMB MB)
  Zapis na fleshku - vruchnuyu (Rufus/Ventoy/Etcher). Ustanovka interaktivnaya
  (bsdinstall), postinstall.sh dodast GNOME i Govecho-nastroyki.
"@ -ForegroundColor Green
