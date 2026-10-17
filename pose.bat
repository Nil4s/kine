@echo off
rem Poser: the mannequin for planning moves. Separate from the game on purpose.
rem FINDS GODOT 4.7 (GATES PP1), in order: the POSER_GODOT variable; a godot\ folder beside this file
rem (Godot_v4.7*.exe in it); Godot_v4.7*.exe or godot.exe on PATH; a godot.path file beside this file (one line:
rem the exe's full path; local, not in the repo). Arguments pass through. POSER_DRY=1: print the launch line only.
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "GODOT="

if defined POSER_GODOT if exist "%POSER_GODOT%" set "GODOT=%POSER_GODOT%"

if not defined GODOT (
  for %%F in ("%HERE%godot\Godot_v4.7*win64.exe") do if not defined GODOT set "GODOT=%%~fF"
)
if not defined GODOT (
  for /f "delims=" %%F in ('where Godot_v4.7*win64.exe 2^>nul') do if not defined GODOT set "GODOT=%%F"
)
if not defined GODOT (
  for /f "delims=" %%F in ('where godot.exe 2^>nul') do if not defined GODOT set "GODOT=%%F"
)
if not defined GODOT if exist "%HERE%godot.path" (
  set /p GP=<"%HERE%godot.path"
  if exist "!GP!" set "GODOT=!GP!"
)

if not defined GODOT (
  echo.
  echo  Poser needs Godot 4.7, and it was not found.
  echo.
  echo  Get it free from https://godotengine.org/download  ^(the "Godot Engine" .exe, version 4.7^), then either:
  echo    - put it in a folder named godot beside this file:  %HERE%godot\
  echo    - or set POSER_GODOT to the .exe's full path
  echo    - or write that path on one line in:  %HERE%godot.path
  echo.
  if not "%POSER_DRY%"=="1" pause
  exit /b 1
)

if "%POSER_DRY%"=="1" (
  echo LAUNCH "!GODOT!" --path "%HERE%." %*
  exit /b 0
)
start "" "%GODOT%" --path "%HERE%." %*
