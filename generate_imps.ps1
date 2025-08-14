# Generate .imp files for X-Wing Alliance looping music
# Creates iMUSE map files that enable proper music looping in the game

# Check if required tools are available
function Test-Dependencies {
    $missingTools = @()
    
    try {
        $null = Get-Command ffprobe -ErrorAction Stop
    }
    catch {
        $missingTools += "ffprobe (from FFmpeg)"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Host "Error: Missing required tools:" -ForegroundColor Red
        foreach ($tool in $missingTools) {
            Write-Host "  - $tool" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "To install FFmpeg on Windows:" -ForegroundColor Yellow
        Write-Host "  1. Download from https://ffmpeg.org/download.html" -ForegroundColor Yellow
        Write-Host "  2. Extract to C:\ffmpeg\" -ForegroundColor Yellow
        Write-Host "  3. Add C:\ffmpeg\bin to your PATH environment variable" -ForegroundColor Yellow
        Write-Host "  4. Restart PowerShell" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Alternative: Install via chocolatey: choco install ffmpeg" -ForegroundColor Yellow
        exit 1
    }
}

# Function to calculate segment lengths based on discovered mathematical relationships
function Calculate-Segments {
    param(
        [long]$DataSize,
        [long]$BytesPerSecond,
        [string]$BaseName
    )
    
    # Pattern discovered from FRCONCOURSE analysis (worked for ambient tracks):
    # - REGN3 (outro): ~6.0 seconds  
    # - REGN1 (intro): ~6.0 seconds + extra (FRCONCOURSE has +0.32s)
    # - REGN2 (loop): everything else
    
    # Calculate 6 seconds in bytes for this audio format
    $sixSecondsBytes = [long]($BytesPerSecond * 6)
    
    # REGN3 (outro): ~6 seconds
    $regn3Length = $sixSecondsBytes
    
    # REGN1 (intro): ~6 seconds + extra amount
    $introExtraSeconds = switch ($BaseName.ToUpper()) {
        "FRCONCOURSE" { 0.32 }  # Original has 6.32 seconds
        default { 0.25 }        # Default quarter second extra
    }
    
    $introExtraBytes = [long]($BytesPerSecond * $introExtraSeconds)
    $regn1Length = $sixSecondsBytes + $introExtraBytes
    
    # REGN2 (main loop): everything else
    $regn2Length = $DataSize - $regn1Length - $regn3Length
    
    # Ensure no negative lengths (for very short files)
    if ($regn2Length -lt 0) {
        Write-Host "    Warning: Short audio file detected, using proportional segments instead of 6-second pattern" -ForegroundColor Yellow
        # For very short files, use proportional segments
        $regn1Length = [long]($DataSize / 10)  # 10% intro
        $regn3Length = [long]($DataSize / 10)  # 10% outro  
        $regn2Length = $DataSize - $regn1Length - $regn3Length  # 80% loop
    }
    
    return @($regn1Length, $regn2Length, $regn3Length)
}

# Function to get audio info using ffprobe
function Get-AudioInfo {
    param([string]$FilePath)
    
    try {
        $ffprobeOutput = & ffprobe -v error -show_streams -show_format -of json $FilePath 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        
        $audioInfo = $ffprobeOutput | ConvertFrom-Json
        $stream = $audioInfo.streams[0]
        
        return @{
            DurationTs = [long]$stream.duration_ts
            BitsPerSample = if ($stream.bits_per_sample) { [int]$stream.bits_per_sample } else { 16 }
            Channels = if ($stream.channels) { [int]$stream.channels } else { 2 }
            SampleRate = if ($stream.sample_rate) { [int]$stream.sample_rate } else { 22050 }
            Duration = [double]$stream.duration
        }
    }
    catch {
        return $null
    }
}

# Check dependencies first
Test-Dependencies

$foundWav = $false

# Process all WAV files (both .wav and .WAV)
$wavFiles = Get-ChildItem -Path "." -Include "*.wav", "*.WAV" -File

if ($wavFiles.Count -eq 0) {
    Write-Host "No WAV files found in the current directory." -ForegroundColor Red
    exit 1
}

foreach ($wavFile in $wavFiles) {
    $foundWav = $true
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($wavFile.Name)
    
    Write-Host "Processing $($wavFile.Name)..." -ForegroundColor Cyan
    
    # Get comprehensive audio info using ffprobe
    $audioInfo = Get-AudioInfo -FilePath $wavFile.FullName
    
    if (-not $audioInfo -or -not $audioInfo.DurationTs -or -not $audioInfo.Duration) {
        Write-Host "  Warning: Could not analyze $($wavFile.Name) (may not be a valid WAV file), skipping..." -ForegroundColor Yellow
        continue
    }
    
    # Calculate data size (duration_ts * bits_per_sample / 8 * channels)
    $dataSize = [long]($audioInfo.DurationTs * $audioInfo.BitsPerSample / 8 * $audioInfo.Channels)
    
    # Calculate bytes per second for this specific audio format
    $bytesPerSecond = [long]($audioInfo.SampleRate * $audioInfo.BitsPerSample / 8 * $audioInfo.Channels)
    
    Write-Host "  Audio format: $($audioInfo.SampleRate) Hz, $($audioInfo.BitsPerSample)-bit, $($audioInfo.Channels) channel(s)"
    Write-Host "  Duration: $($audioInfo.Duration.ToString('F2')) seconds ($($audioInfo.DurationTs) samples)"
    Write-Host "  Bytes per second: $bytesPerSecond"
    Write-Host "  Total data size: $dataSize bytes"
    
    # Calculate segment lengths using discovered mathematical relationships
    $segments = Calculate-Segments -DataSize $dataSize -BytesPerSecond $bytesPerSecond -BaseName $baseName
    $regn1Length = $segments[0]
    $regn2Length = $segments[1]
    $regn3Length = $segments[2]
    
    # Display the calculated segments in seconds for verification
    $regn1Seconds = [math]::Round($regn1Length / $bytesPerSecond, 3)
    $regn2Seconds = [math]::Round($regn2Length / $bytesPerSecond, 3)
    $regn3Seconds = [math]::Round($regn3Length / $bytesPerSecond, 3)
    
    Write-Host "  Calculated segments (using ~6-second pattern):"
    Write-Host "    REGN1 (intro): $regn1Length bytes = ${regn1Seconds}s"
    Write-Host "    REGN2 (loop):  $regn2Length bytes = ${regn2Seconds}s"  
    Write-Host "    REGN3 (outro): $regn3Length bytes = ${regn3Seconds}s"
    
    # Calculate RELATIVE positions (cumulative REGN lengths starting from 0)
    # VIMA compressor will add its own base offset to all these values
    
    # Start everything at relative position 0
    $currentRelativePosition = 0
    
    # FRMT and REGN1 start at relative position 0
    $regn1Position = $currentRelativePosition
    
    # After traversing through REGN1, relative position advances by REGN1 length
    $currentRelativePosition += $regn1Length
    
    # TEXT3 ("lp") and REGN2 start at this relative position
    $text3Position = $currentRelativePosition
    $regn2Position = $currentRelativePosition
    
    # After traversing through REGN2, relative position advances by REGN2 length  
    $currentRelativePosition += $regn2Length
    
    # JUMP and REGN3 start at this relative position
    $jumpPosition = $currentRelativePosition
    $regn3Position = $currentRelativePosition
    
    # After traversing through REGN3, relative position advances by REGN3 length
    $currentRelativePosition += $regn3Length
    
    # STOP is at the final relative position
    $stopPosition = $currentRelativePosition
    
    # Verify our math - final relative position should equal total data size
    if ($stopPosition -ne $dataSize) {
        Write-Host "  ERROR: Segment length calculation error!" -ForegroundColor Red
        Write-Host "    This indicates a bug in the script. Please check your audio file." -ForegroundColor Red
        Write-Host "    Expected total: $dataSize bytes, Calculated: $stopPosition bytes" -ForegroundColor Red
        continue
    }
    
    # Create the .imp file (removed TEXT1 and TEXT2 blocks to avoid encoding issues)
    $impFile = "$baseName.imp"
    
    $impContent = @"
[iMUSE Map]
Version = 1

[FRMT]
Position = 0
Unknown = 1

[REGN1]
Position = $regn1Position
Length = $regn1Length

[TEXT3]
Position = $text3Position
Text = lp

[REGN2]
Position = $regn2Position
Length = $regn2Length

[JUMP1]
Position = $jumpPosition
JumpDest = $text3Position
ID = 0
Loop = 500

[REGN3]
Position = $regn3Position
Length = $regn3Length

[STOP]
Position = $stopPosition
"@

    try {
        $impContent | Out-File -FilePath $impFile -Encoding ASCII -NoNewline
        Write-Host "  Created $impFile for looping music" -ForegroundColor Green
        Write-Host "    Intro: ${regn1Seconds}s → Loop: ${regn2Seconds}s → Outro: ${regn3Seconds}s"
    }
    catch {
        Write-Host "  Error: Could not create $impFile - $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    
    Write-Host ""
}

if (-not $foundWav) {
    Write-Host "No WAV files found in the current directory." -ForegroundColor Red
    exit 1
}

Write-Host "Done! Generated .imp files for looping music." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Open VIMA Audio Compressor"
Write-Host "2. CHECK 'Create Default TEXT blocks' (important for looping)"
Write-Host "3. UNCHECK 'Lossless' (use lossy compression)"
Write-Host "4. Add your WAV file and its .imp file, then compress"
Write-Host "5. Test the .IMC file in-game"
Write-Host ""
Write-Host "Notes:" -ForegroundColor Cyan
Write-Host "- For infinite looping: Edit 'Loop = 500' to 'Loop = 9999' in .imp files"
Write-Host "- For non-looping music: Skip the .imp file, just compress the WAV"
Write-Host "- If timing feels wrong: Try analyzing similar original tracks with SCUMM Revisited"