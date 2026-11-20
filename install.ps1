# 0JayShop Sunshine - install straight from GitHub.
#
# Run this on a shop client in an elevated Windows PowerShell:
#
#   iwr -useb https://raw.githubusercontent.com/fbpinote-svg/0jayshop-sunshine-installer/main/install.ps1 | iex
#
# To also seed the real shop config (IP map + web login) from a file you carry
# on a USB stick - the config is NOT on GitHub - pass -ShopConfig:
#
#   & ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/fbpinote-svg/0jayshop-sunshine-installer/main/install.ps1))) -ShopConfig 'E:\shop-config'
#
# The program is downloaded from the public release and its SHA256 is checked
# against the value pinned below, so a tampered or man-in-the-middled download
# is refused before anything on the machine is touched. The shop config never
# travels over GitHub; only the generic program does.
#
# ASCII only: Windows PowerShell 5.1 misreads Thai in BOM-less UTF-8.

param(
    [ValidateSet('', 'update', 'clean')]
    [string]$Mode = 'clean',
    [string]$ShopConfig = '',
    # Two gzip+base64 strings: sunshine.conf, then sunshine_state.json. The real
    # shop config travels inside the pasted command (on the operator's machines),
    # never on GitHub. The same pair works on every machine - each one picks its
    # own profile by matching its IP.
    [string[]]$ShopConfigB64 = @(),
    [string]$Target = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- what to fetch (filled in when the release is published) ------------------
$Version      = 'v1.0.0-beta.12'
$ZipUrl       = 'https://github.com/fbpinote-svg/0jayshop-sunshine-installer/releases/download/v1.0.0-beta.12/Sunshine-v1.0.0-beta.12-public.zip'
$ZipSha256    = '0aa49dd761f8c746bde173702987cedddf6ad546c306e117c650ab788e00a35c'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Done([int]$code) {
    Write-Host ''
    try { if (-not $DryRun) { Read-Host 'Press Enter to close' | Out-Null } } catch {}
    exit $code
}

# --- administrator ------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Say 'This needs administrator rights.' 'Yellow'
    Say 'Open PowerShell as administrator and run the command again.' 'Yellow'
    Done 1
}

Clear-Host
Say '=====================================================' 'Cyan'
Say "  0JayShop Sunshine installer   $Version" 'Cyan'
Say '=====================================================' 'Cyan'
if ($DryRun) { Say '  DRY RUN - nothing will be changed' 'Magenta' }
Say ''
Say '  Diskless machine? Switch to SUPER MODE first,' 'Yellow'
Say '  or everything installed here is lost on reboot.' 'Yellow'
Say '  Do not run while a customer is streaming.' 'Yellow'
Say ''

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$tmp     = Join-Path $env:TEMP "0jay-$stamp"
$zipPath = Join-Path $tmp 'Sunshine.zip'
$staging = Join-Path $tmp 'staging'
$log     = Join-Path $env:TEMP "0jay-install-$stamp.log"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function LogLine([string]$m) {
    $line = "$((Get-Date).ToString('HH:mm:ss'))  $m"
    Add-Content -Path $log -Value $line -Encoding ascii
}

# --- find an existing install -------------------------------------------------
# .NET path methods on purpose: a leftover service can point at a drive that is
# gone, and Join-Path / Split-Path throw on a missing drive.
function Find-Installed {
    $svc = Get-CimInstance Win32_Service -Filter "Name='SunshineService'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName) {
        $raw = $svc.PathName.Trim()
        if ($raw -match '^"([^"]+)"') { $p = $Matches[1] }
        elseif ($raw -match '^(.+?\.exe)') { $p = $Matches[1] }
        else { $p = $raw }
        $dir = [IO.Path]::GetDirectoryName($p)
        for ($i = 0; $i -lt 3 -and $dir; $i++) {
            if ([IO.File]::Exists([IO.Path]::Combine($dir, 'sunshine.exe'))) { return $dir }
            $dir = [IO.Path]::GetDirectoryName($dir)
        }
    }
    foreach ($p in @(Get-Process sunshine -ErrorAction SilentlyContinue)) {
        if ($p.Path) { return [IO.Path]::GetDirectoryName($p.Path) }
    }
    $c = @(Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { [IO.Path]::Combine($_.FullName, 'Sunshine') }) + @('C:\0JayShop\Sunshine', 'C:\Sunshine')
    foreach ($x in $c) { if ([IO.File]::Exists([IO.Path]::Combine($x, 'sunshine.exe'))) { return $x } }
    return $null
}

$installed = Find-Installed
if (-not $Target) { $Target = if ($installed) { $installed } else { 'C:\Users\AdminDemo\Sunshine' } }
Say "  Installed now : $(if ($installed) { $installed } else { '(nothing)' })"
Say "  Install to    : $Target"
Say "  Log           : $log"
Say ''

# --- download -----------------------------------------------------------------
Say '--- downloading the program ---' 'Cyan'
Say "  $ZipUrl"
if ($DryRun) {
    Say '  (dry run) would download and verify SHA256, then install.' 'Yellow'
    Done 0
}
try {
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
    $ProgressPreference = $old
} catch {
    Say "  Download failed: $($_.Exception.Message)" 'Red'
    Done 1
}
LogLine "downloaded $ZipUrl"

# --- verify -------------------------------------------------------------------
$got = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
if ($got -ne $ZipSha256.ToLower()) {
    Say '  CHECKSUM MISMATCH - the download is not the expected build.' 'Red'
    Say "    expected $ZipSha256" 'Red'
    Say "    got      $got" 'Red'
    Say '  Nothing was changed on this machine.' 'Red'
    LogLine "sha mismatch got=$got"
    Done 1
}
Say '  OK   checksum matches the pinned build.' 'Green'
LogLine "sha ok $got"

# --- stage --------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $staging)
if (-not (Test-Path (Join-Path $staging 'Sunshine\sunshine.exe'))) {
    Say '  The package did not extract correctly.' 'Red'; Done 1
}

function RunBat([string]$bat, [string]$phase) {
    if (-not (Test-Path $bat)) { LogLine "missing $bat"; return }
    $dir = Split-Path $bat -Parent
    $out = & cmd.exe /c "cd /d `"$dir`" && `"$bat`" < NUL 2>&1"
    $out | ForEach-Object { Add-Content -Path $log -Value "    | $_" -Encoding ascii }
    LogLine "$phase exit=$LASTEXITCODE"
}

# --- uninstall the old one (uninstaller from the NEW package) -----------------
Say ''
Say '--- installing ---' 'Cyan'
Say '  removing any previous install...'
RunBat (Join-Path $staging 'Sunshine\uninstall_portable.bat') 'uninstall'
Start-Sleep -Seconds 3
if ($installed -and (Test-Path -LiteralPath $Target)) {
    Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue
}

# --- place the new build ------------------------------------------------------
Say '  copying the new build...'
New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item -Path (Join-Path $staging 'Sunshine\*') -Destination $Target -Recurse -Force
if (-not (Test-Path (Join-Path $Target 'sunshine.exe'))) { Say '  Copy failed.' 'Red'; Done 1 }

# --- seed the REAL shop config, embedded in the command (never from GitHub) ---
if ($ShopConfigB64.Count -ge 1) {
    Say ''
    Say '--- seeding the real shop config (embedded) ---' 'Cyan'
    $cfgDir = Join-Path $Target 'config'
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    function Write-Gz([string]$name, [string]$b64) {
        $in = New-Object IO.MemoryStream(, [Convert]::FromBase64String($b64))
        $gz = New-Object IO.Compression.GzipStream($in, [IO.Compression.CompressionMode]::Decompress)
        $out = New-Object IO.MemoryStream; $gz.CopyTo($out); $gz.Dispose()
        [IO.File]::WriteAllBytes((Join-Path $cfgDir $name), $out.ToArray())
    }
    $names = @('sunshine.conf', 'sunshine_state.json')
    $seeded = @()
    for ($i = 0; $i -lt $ShopConfigB64.Count -and $i -lt 2; $i++) {
        if ($ShopConfigB64[$i]) { Write-Gz $names[$i] $ShopConfigB64[$i]; $seeded += $names[$i] }
    }
    Say "  OK   seeded: $($seeded -join ', ')" 'Green'
    LogLine "seeded(embedded) $($seeded -join ',')"
}

# --- or seed the REAL shop config from a file / USB (never from GitHub) -------
if ($ShopConfig) {
    Say ''
    Say '--- seeding the real shop config ---' 'Cyan'
    $cfgDir = Join-Path $Target 'config'
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    $src = $ShopConfig
    if ($ShopConfig.ToLower().EndsWith('.zip')) {
        $sx = Join-Path $tmp 'shopcfg'
        [IO.Compression.ZipFile]::ExtractToDirectory($ShopConfig, $sx)
        $src = $sx
    }
    $seeded = @()
    foreach ($name in 'sunshine.conf', 'sunshine_state.json') {
        $hit = Get-ChildItem -LiteralPath $src -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { Copy-Item $hit.FullName (Join-Path $cfgDir $name) -Force; $seeded += $name }
    }
    if ($seeded.Count) { Say "  OK   seeded: $($seeded -join ', ')" 'Green'; LogLine "seeded $($seeded -join ',')" }
    else { Say "  No sunshine.conf / sunshine_state.json found in $ShopConfig" 'Yellow' }
}

# --- run the portable installer + service -------------------------------------
RunBat (Join-Path $Target 'install_portable.bat') 'install'
RunBat (Join-Path $Target 'scripts\install-service.bat') 'service'
Set-Service SunshineService -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service SunshineService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10

# --- virtual display: the KORI20 check ----------------------------------------
function Get-Stack([string]$id) {
    $d = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Stack' -ErrorAction SilentlyContinue).Data
    if ($d) { return ($d -join ' | ') } ; return ''
}
function Test-VirtualDisplay {
    Say ''
    Say '--- virtual display ---' 'Cyan'
    $dev = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'Zako' } | Select-Object -First 1
    if (-not $dev) { Say '  Zako display adapter not found - skipped.' 'Yellow'; return }
    $stack = Get-Stack $dev.InstanceId
    Say "  stack : $stack"
    if ($stack -match 'IndirectKmd') { Say '  OK   it can create virtual monitors.' 'Green'; return }
    Say '  PROBLEM: IndirectKmd is not in the driver stack - no virtual monitor' 'Red'
    Say '  will ever appear and every stream fails with error 503 (seen on KORI20).' 'Red'
    $a = Read-Host '  Apply the known fix now (DisableVersionMismatchCheck)? [Y/N]'
    if ($a -notmatch '^[Yy]') { Say '  Not applied.' 'Yellow'; return }
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
        -Name 'DisableVersionMismatchCheck' -Value 1 -Type DWord
    Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    $stack = Get-Stack $dev.InstanceId
    if ($stack -match 'IndirectKmd') { Say '  FIXED  IndirectKmd is in the stack now.' 'Green' }
    else { Say '  Still missing. Photograph this window for the developer.' 'Red' }
}

# --- the four drivers ---------------------------------------------------------
# Same tests as the control panel's Device software page and the setup exe:
# only present devices count, the virtual mouse needs a working HID mouse
# (mouhid) under it, ViGEmBus must be 1.17 or newer. Returns how many are not OK.
function Show-Drivers {
    Say ''
    Say '--- drivers ---' 'Cyan'
    $all = $null
    try { $all = @(Get-PnpDevice -PresentOnly -ErrorAction Stop) } catch { }
    if ($null -eq $all) { Say '  could not read the device list' 'Yellow'; return 0 }
    function Ver([string]$id) { try { return [string](Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_DriverVersion -ErrorAction Stop).Data } catch { return '' } }
    $rows = @()
    $vdd = @($all | Where-Object { $ids = @($_.HardwareID); ($ids -contains 'Root\ZakoVDD') -or ($ids -contains 'ZakoVDD') })
    $rows += , @('Virtual display (Zako VDD)', $vdd, { param($d) $d.Status -eq 'OK' })
    $mouse = @($all | Where-Object { @($_.HardwareID) -contains 'Root\ZakoVirtualMouse' })
    $rows += , @('Virtual mouse (Zako Virtual Mouse)', $mouse, {
        param($d)
        if ($d.Status -ne 'OK') { return $false }
        $kids = $null
        try { $kids = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_Children -ErrorAction Stop).Data } catch { }
        if (-not $kids) { return $false }
        return @($all | Where-Object { ($kids -contains $_.InstanceId) -and $_.Service -eq 'mouhid' -and $_.Status -eq 'OK' }).Count -gt 0
    })
    $pad = @($all | Where-Object { ((@($_.HardwareID) -join ',') -match 'ViGEm') -or ($_.FriendlyName -like '*Virtual Gamepad Emulation*') })
    $rows += , @('Gamepad (ViGEmBus)', $pad, {
        param($d)
        $v = $null
        return ($d.Status -eq 'OK') -and [version]::TryParse((Ver $d.InstanceId), [ref]$v) -and ($v -ge [version]'1.17')
    })
    $mic = @($all | Where-Object { $_.Class -eq 'AudioEndpoint' -and $_.FriendlyName -like '*VB-Audio Virtual Cable*' })
    $rows += , @('Virtual mic (VB-CABLE)', $mic, { param($d) $d.Status -eq 'OK' })
    $bad = 0
    foreach ($r in $rows) {
        $name = $r[0]; $devs = @($r[1] | Where-Object { $null -ne $_ }); $works = $r[2]
        if ($devs.Count -eq 0) { Say ("  {0,-36} MISSING" -f $name) 'Red'; $bad++; continue }
        $ok = @($devs | Where-Object { & $works $_ })
        if ($ok.Count -gt 0) { Say ("  {0,-36} OK" -f $name) 'Green' }
        else { Say ("  {0,-36} NOT WORKING (status {1})" -f $name, $devs[0].Status) 'Red'; $bad++ }
    }
    if ($bad -gt 0) { Say '  Some drivers are missing. Restart Windows if asked, then run the command again.' 'Yellow' }
    return $bad
}

# --- verdict by result, not by a batch file exit code -------------------------
Say ''
$placed = Test-Path (Join-Path $Target 'sunshine.exe')
$svc = Get-Service SunshineService -ErrorAction SilentlyContinue
if ($placed -and $svc -and $svc.Status -eq 'Running') { Say '  OK   installed and the service is running.' 'Green'; $code = 0 }
elseif ($placed) { Say "  Installed, but the service is $(if($svc){$svc.Status}else{'missing'}). Check $log" 'Yellow'; $code = 2 }
else { Say "  Install failed. Check $log" 'Red'; $code = 1 }

$missing = Show-Drivers
if ($code -eq 0 -and $missing -gt 0) { $code = 3 }
Test-VirtualDisplay
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

if (-not $ShopConfig -and $ShopConfigB64.Count -eq 0) {
    Say ''
    Say '  No shop config was seeded. This machine will show the first-run' 'Yellow'
    Say '  web setup. To push the real IP map and login, re-run with' 'Yellow'
    Say '  -ShopConfigB64 (embedded) or -ShopConfig (a file on USB).' 'Yellow'
}
Done $code
