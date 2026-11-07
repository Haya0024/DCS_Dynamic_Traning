@echo off
setlocal
set "DCS_TRAINING_SAVED_GAMES=%~1"
if not defined DCS_TRAINING_SAVED_GAMES set "DCS_TRAINING_SAVED_GAMES=%USERPROFILE%\Saved Games\DCS.dcs_serverrelease"
if exist "%~dp0Build-PersistenceHook.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-PersistenceHook.ps1" -SavedGamesPath "%DCS_TRAINING_SAVED_GAMES%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-PersistenceHook.ps1" -SavedGamesPath "%DCS_TRAINING_SAVED_GAMES%" -HookBundlePath "%~dp0DynamicTrainingPersistenceHook.lua"
)
set "DCS_TRAINING_INSTALL_RESULT=%ERRORLEVEL%"
if "%DCS_TRAINING_INSTALL_RESULT%"=="0" (
  echo Hook installation verified. Restart the DCS server.
) else (
  echo Hook installation FAILED. See the error above.
)
if /I "%~2"=="--no-pause" exit /b %DCS_TRAINING_INSTALL_RESULT%
pause
exit /b %DCS_TRAINING_INSTALL_RESULT%
