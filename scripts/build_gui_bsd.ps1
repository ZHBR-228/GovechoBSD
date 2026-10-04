#Requires -Version 5.0
# ============================================================
# САМОДЕКОДИРУЮЩИЙСЯ ЗАПУСКЧИК (fixes "окно открывается на миллисекунды"):
# Если .ps1 сохранён без BOM и содержит кириллицу, Windows PowerShell 5.1
# читает его как ANSI(cp1251), код ломается и скрипт мгновенно завершается.
# При первом запуске файл сам перезаписывает себя с UTF-8 BOM и перезапускается.
if ($args[0] -ne '-Relaunched') {
    $f = $MyInvocation.MyCommand.Path
    if (-not $f) { $f = (Resolve-Path '.\build_gui_bsd.ps1').Path }
    $bytes = [IO.File]::ReadAllBytes($f)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        [IO.File]::WriteAllBytes($f, [byte[]](0xEF,0xBB,0xBF) + [Text.Encoding]::UTF8.GetBytes($text))
        $exe = if (Get-Command pwsh -EA SilentlyContinue) { 'pwsh' } else { 'powershell' }
        Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$f`"", '-Relaunched') -WindowStyle Hidden
        exit 0
    }
}
<#
.SYNOPSIS
    GovechoBSD Builder GUI — мини-приложение с интерфейсом и прогрессом сборки ISO FreeBSD.
.DESCRIPTION
    Окно (WPF, без внешних зависимостей): процент + прогресс-бар, текущая фаза,
    живой лог, кнопки «Собрать / Отмена / Папка сборки». Ядро FreeBSD уже внутри
    официального ISO — скрипт только наслаивает govechoos-конфиг и пересобирает образ.
    Работает с build_bsd_windows.ps1 через протокол "PROGRESS|<0-100>|<фаза>".

    Автор: ZHBR-228 · Лицензия: MIT · github.com/ZHBR-228/GovechoBSD
#>
param(
    [string]$Relaunched = '',   # служебный: метка перезапуска после самодекодирования
    [string]$Builder = ''
)
$ErrorActionPreference = 'Stop'
# Страховка: любая ошибка покажет диалог с текстом причины, а не закроет окно молча
trap {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = 'Ошибка запуска Govecho Builder:' + [Environment]::NewLine + $_.Exception.Message +
           [Environment]::NewLine + [Environment]::NewLine + 'Запустите вручную из PowerShell:' +
           [Environment]::NewLine + 'powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_gui_bsd.ps1
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Govecho Builder', 'OK', 'Error')
    exit 1
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------- Консольный режим (для тестов/серверов без GUI) ----------
if ($env:GOVECHO_GUI -eq 'console') {
    & $Builder -GuiProtocol
    exit $LASTEXITCODE
}

$XAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GovechoBSD Builder" Height="540" Width="740" MinHeight="400" MinWidth="580"
        Background="#1c2030" WindowStartupLocation="CenterScreen">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Orientation="Horizontal">
      <TextBlock Text="GOVECHO" FontSize="30" FontWeight="Bold" Foreground="#ff9d5c"/>
      <TextBlock Text="BSD Builder" FontSize="30" Foreground="#dddddd" Margin="8,0,0,0"/>
      <TextBlock x:Name="TxtVer" Text="" FontSize="14" Foreground="#8888aa"
                 VerticalAlignment="Bottom" Margin="10,0,0,6"/>
    </StackPanel>
    <Border Grid.Row="1" Background="#252a40" CornerRadius="8" Padding="12" Margin="0,12,0,0">
      <StackPanel>
        <DockPanel>
          <TextBlock x:Name="TxtPhase" DockPanel.Dock="Left" Text="Готов к сборке"
                     FontSize="16" Foreground="#ffffff"/>
          <TextBlock x:Name="TxtPct" DockPanel.Dock="Right" Text="0%"
                     FontSize="26" FontWeight="Bold" Foreground="#ff9d5c"/>
        </DockPanel>
        <ProgressBar x:Name="Bar" Height="16" Minimum="0" Maximum="100" Value="0"
                     Foreground="#e8734a" Background="#3a3f5c" BorderThickness="0" Margin="0,8,0,0"/>
        <TextBlock x:Name="TxtHint" Text="" Foreground="#9aa0c0" FontSize="12" Margin="0,6,0,0"
                   TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="2" Background="#12161f" CornerRadius="8" Padding="6" Margin="0,10,0,0">
      <TextBox x:Name="TxtLog" IsReadOnly="True" Background="Transparent" Foreground="#c0e0c0"
               FontFamily="Consolas" FontSize="12" BorderThickness="0"
               VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
    </Border>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnOpen" Content="📂 Папка сборки" Width="130" Height="30" Margin="0,0,8,0"
              Background="#3a3f5c" Foreground="#eeeeee" BorderThickness="0"/>
      <Button x:Name="BtnCancel" Content="✖ Отмена" Width="100" Height="30" Margin="0,0,8,0"
              Background="#6e3434" Foreground="#ffffff" BorderThickness="0" IsEnabled="False"/>
      <Button x:Name="BtnRun" Content="▶ Собрать ISO" Width="140" Height="30"
              Background="#e8734a" Foreground="#ffffff" FontWeight="Bold" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader ([xml]$XAML)
$win = [Windows.Markup.XamlReader]::Load($reader)
$TxtPhase=$win.FindName('TxtPhase'); $TxtPct=$win.FindName('TxtPct')
$Bar=$win.FindName('Bar');           $TxtHint=$win.FindName('TxtHint')
$TxtLog=$win.FindName('TxtLog');     $BtnRun=$win.FindName('BtnRun')
$BtnCancel=$win.FindName('BtnCancel'); $BtnOpen=$win.FindName('BtnOpen')
$TxtVer=$win.FindName('TxtVer')

$root = Join-Path $PSScriptRoot '..'
if (-not $Builder) { $Builder = Join-Path $PSScriptRoot 'build_bsd_windows.ps1' }
$verFile = Join-Path $root 'VERSION'
if (Test-Path $verFile) { $TxtVer.Text = 'v' + (Get-Content $verFile -Raw).Trim() }
$WorkDir = Join-Path $env:USERPROFILE 'govecho_bsd_build'

function Set-Progress([double]$pct,[string]$phase){
    if($pct -lt 0){$pct=0}; if($pct -gt 100){$pct=100}
    $Bar.Value=$pct; $TxtPct.Text="$([math]::Round($pct))%"
    if($phase){$TxtPhase.Text=$phase}
}
function Add-Log([string]$s){ if($s){ $TxtLog.AppendText($s+"`r`n"); $TxtLog.ScrollToEnd() } }

$job=$null; $lastPct=0.0

$BtnRun.Add_Click({
    if($job){return}
    $TxtLog.Clear(); Set-Progress 1 'Запуск...'
    $BtnRun.IsEnabled=$false; $BtnCancel.IsEnabled=$true
    $b='powershell'; if(Get-Command pwsh -EA SilentlyContinue){$b='pwsh'}
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Builder,'-GuiProtocol')
    $job = Start-Job -ScriptBlock {
        param($exe,$a)
        $psi=New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName=$exe
        $psi.Arguments=($a|%{ if($_ -match '\s'){"'$_'"}else{$_} }) -join ' '
        $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
        $psi.UseShellExecute=$false
        $p=[System.Diagnostics.Process]::Start($psi)
        while(-not $p.StandardOutput.EndOfStream){ Write-Output $p.StandardOutput.ReadLine() }
        while(-not $p.StandardError.EndOfStream){ Write-Output ('ERR|'+$p.StandardError.ReadLine()) }
        $p.WaitForExit(); Write-Output ('EXIT|'+$p.ExitCode)
    } -ArgumentList $b,$args
    Add-Log 'Сборка запущена (ядро FreeBSD уже в базовом ISO — остаётся наслаивание).'
})
$BtnCancel.Add_Click({ if($job){ Stop-Job $job; Add-Log 'Отменено пользователем.'; Set-Progress 0 'Отменено' } })
$BtnOpen.Add_Click({
    if(-not(Test-Path $WorkDir)){New-Item -ItemType Directory -Force -Path $WorkDir|Out-Null}
    Start-Process explorer.exe $WorkDir
})

$timer=New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if(-not $job){return}
    foreach($line in @(Receive-Job $job)){
        $s="$line"
        if($s -like 'PROGRESS|*'){
            $parts=$s.Split('|'); $pct=0.0; [double]::TryParse($parts[1],[ref]$pct)|Out-Null
            $ph=if($parts.Length -gt 2){$parts[2]}else{''}
            Set-Progress $pct $ph; $lastPct=$pct; Add-Log "[$([math]::Round($pct))%] $ph"
        } elseif($s -like 'ERR|*'){ Add-Log ('⚠ '+$s.Substring(4)) }
        elseif($s -like 'EXIT|*'){
            $code=[int]($s.Split('|')[1]); $timer.Stop()
            $BtnRun.IsEnabled=$true; $BtnCancel.IsEnabled=$false
            if($code -eq 0){
                Set-Progress 100 '✓ Сборка завершена!'
                $TxtHint.Text="ISO готов в папке: $WorkDir"
                Add-Log '=== ГОТОВО. Флешку пишите сами: Rufus/Ventoy/balenaEtcher. ==='
                try{ Start-Process explorer.exe ("'/select,"+(Join-Path $WorkDir ((Get-ChildItem $WorkDir -Filter '*.iso' -EA SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1).FullName))+"'") }catch{}
            } else {
                Set-Progress $lastPct ('✖ Ошибка сборки (код '+$code+')')
                Add-Log "Ошибка. Код выхода: $code"
            }
            Remove-Job $job -Force -EA SilentlyContinue; $job=$null
        } elseif($s){ Add-Log $s }
    }
})
$win.Add_Closed({ if($script:job){ Stop-Job $script:job -EA SilentlyContinue } })
$TxtHint.Text='Подсказка: скачивается официальный ISO FreeBSD (~600 МБ), добавляется конфиг Govecho (ZFS root + GNOME + стартовые приложения), пересобирается bootable ISO. Запись на носители скрипт НЕ выполняет.'
$timer.Start()
$win.ShowDialog()|Out-Null
