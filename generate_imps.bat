@echo off
setlocal enabledelayedexpansion

REM Generate .imp files for X-Wing Alliance looping music
REM Creates iMUSE map files that enable proper music looping in the game

echo Generate .imp files for X-Wing Alliance looping music
echo.

REM Check if ffprobe is available
ffprobe -version >nul 2>&1
if errorlevel 1 (
    echo Error: ffprobe ^(from FFmpeg^) is required but not found.
    echo.
    echo To install FFmpeg on Windows:
    echo   1. Download from https://ffmpeg.org/download.html
    echo   2. Extract to C:\ffmpeg\
    echo   3. Add C:\ffmpeg\bin to your PATH environment variable
    echo   4. Restart Command Prompt
    echo.
    echo Alternative: Install via chocolatey: choco install ffmpeg
    pause
    exit /b 1
)

set "found_wav=false"

REM Process all WAV files
for %%f in (*.wav *.WAV) do (
    if exist "%%f" (
        set "found_wav=true"
        call :process_wav "%%f"
    )
)

if "!found_wav!"=="false" (
    echo No WAV files found in the current directory.
    pause
    exit /b 1
)

echo.
echo Done! Generated .imp files for looping music.
echo.
echo Next steps:
echo 1. Open VIMA Audio Compressor
echo 2. CHECK 'Create Default TEXT blocks' ^(important for looping^)
echo 3. UNCHECK 'Lossless' ^(use lossy compression^)
echo 4. Add your WAV file and its .imp file, then compress
echo 5. Test the .IMC file in-game
echo.
echo Notes:
echo - For infinite looping: Edit 'Loop = 500' to 'Loop = 9999' in .imp files
echo - For non-looping music: Skip the .imp file, just compress the WAV
echo - If timing feels wrong: Try analyzing similar original tracks with SCUMM Revisited
pause
exit /b 0

:process_wav
set "wav_file=%~1"
set "base_name=%~n1"

echo Processing %wav_file%...

REM Get audio info using ffprobe (simplified - gets basic info)
for /f "tokens=*" %%i in ('ffprobe -v error -select_streams a:0 -show_entries stream^=duration,sample_rate,channels -of csv^=p^=0 "%wav_file%" 2^>nul') do (
    set "audio_info=%%i"
)

if "!audio_info!"=="" (
    echo   Warning: Could not analyze %wav_file% ^(may not be a valid WAV file^), skipping...
    goto :eof
)

REM Parse audio info (duration,sample_rate,channels)
for /f "tokens=1,2,3 delims=," %%a in ("!audio_info!") do (
    set "duration=%%a"
    set "sample_rate=%%b"
    set "channels=%%c"
)

REM Set defaults if missing
if "!sample_rate!"=="" set "sample_rate=22050"
if "!channels!"=="" set "channels=2"

REM Calculate basic values (using integer math approximations)
set /a "bits_per_sample=16"
set /a "bytes_per_second=sample_rate * bits_per_sample / 8 * channels"

REM Get file size as approximation for data size
for %%a in ("%wav_file%") do set "file_size=%%~za"
REM Subtract approximate WAV header size (44 bytes)
set /a "data_size=file_size - 44"

echo   Audio format: !sample_rate! Hz, !bits_per_sample!-bit, !channels! channel^(s^)
echo   Estimated data size: !data_size! bytes
echo   Bytes per second: !bytes_per_second!

REM Calculate segment lengths (using 6-second base pattern)
set /a "six_seconds_bytes=bytes_per_second * 6"

REM REGN3 (outro): 6 seconds
set /a "regn3_length=six_seconds_bytes"

REM REGN1 (intro): 6 seconds + extra
if /i "!base_name!"=="FRCONCOURSE" (
    REM 6.32 seconds for FRCONCOURSE (add ~0.32s = bytes_per_second * 32 / 100)
    set /a "extra_bytes=bytes_per_second * 32 / 100"
) else (
    REM 6.25 seconds for others (add ~0.25s = bytes_per_second / 4)
    set /a "extra_bytes=bytes_per_second / 4"
)
set /a "regn1_length=six_seconds_bytes + extra_bytes"

REM REGN2 (main loop): everything else
set /a "regn2_length=data_size - regn1_length - regn3_length"

REM Check for very short files
if !regn2_length! lss 0 (
    echo     Warning: Short audio file detected, using proportional segments
    set /a "regn1_length=data_size / 10"
    set /a "regn3_length=data_size / 10"
    set /a "regn2_length=data_size - regn1_length - regn3_length"
)

REM Calculate approximate durations for display
set /a "regn1_seconds_x100=regn1_length * 100 / bytes_per_second"
set /a "regn2_seconds_x100=regn2_length * 100 / bytes_per_second"
set /a "regn3_seconds_x100=regn3_length * 100 / bytes_per_second"

echo   Calculated segments ^(using ~6-second pattern^):
echo     REGN1 ^(intro^): !regn1_length! bytes = !regn1_seconds_x100!/100s
echo     REGN2 ^(loop^):  !regn2_length! bytes = !regn2_seconds_x100!/100s
echo     REGN3 ^(outro^): !regn3_length! bytes = !regn3_seconds_x100!/100s

REM Calculate relative positions
set /a "regn1_position=0"
set /a "text3_position=regn1_length"
set /a "regn2_position=text3_position"
set /a "jump_position=regn1_length + regn2_length"
set /a "regn3_position=jump_position"
set /a "stop_position=regn1_length + regn2_length + regn3_length"

REM Verify math
if !stop_position! neq !data_size! (
    echo   ERROR: Segment length calculation error!
    echo   Expected total: !data_size! bytes, Calculated: !stop_position! bytes
    goto :eof
)

REM Create the .imp file
set "imp_file=!base_name!.imp"

> "!imp_file!" (
    echo [iMUSE Map]
    echo Version = 1
    echo.
    echo [FRMT]
    echo Position = 0
    echo Unknown = 1
    echo.
    echo [REGN1]
    echo Position = !regn1_position!
    echo Length = !regn1_length!
    echo.
    echo [TEXT3]
    echo Position = !text3_position!
    echo Text = lp
    echo.
    echo [REGN2]
    echo Position = !regn2_position!
    echo Length = !regn2_length!
    echo.
    echo [JUMP1]
    echo Position = !jump_position!
    echo JumpDest = !text3_position!
    echo ID = 0
    echo Loop = 500
    echo.
    echo [REGN3]
    echo Position = !regn3_position!
    echo Length = !regn3_length!
    echo.
    echo [STOP]
    echo Position = !stop_position!
)

echo   Created !imp_file! for looping music
echo     Intro: !regn1_seconds_x100!/100s -^> Loop: !regn2_seconds_x100!/100s -^> Outro: !regn3_seconds_x100!/100s
echo.

goto :eof