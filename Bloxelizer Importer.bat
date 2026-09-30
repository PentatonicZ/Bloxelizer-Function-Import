@echo off
setlocal
PowerShell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bloxelizer Importer.ps1"
if errorlevel 1 pause
endlocal
