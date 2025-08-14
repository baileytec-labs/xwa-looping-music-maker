#!/bin/bash

# Generate .imp files for X-Wing Alliance looping music
# Creates iMUSE map files that enable proper music looping in the game

# Check if required tools are available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with:"
    echo "  macOS: brew install jq"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    exit 1
fi

if ! command -v ffprobe &> /dev/null; then
    echo "Error: ffprobe (from ffmpeg) is required. Install with:"
    echo "  macOS: brew install ffmpeg"
    echo "  Ubuntu/Debian: sudo apt-get install ffmpeg"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "Error: bc is required. Install with:"
    echo "  macOS: brew install bc"
    echo "  Ubuntu/Debian: sudo apt-get install bc"
    exit 1
fi

found_wav=false

# Function to calculate segment lengths based on discovered mathematical relationships
calculate_segments() {
    local data_size="$1"
    local bytes_per_second="$2"
    local base_name="$3"
    
    # Pattern discovered from FRCONCOURSE analysis (worked for ambient tracks):
    # - REGN3 (outro): ~6.0 seconds  
    # - REGN1 (intro): ~6.0 seconds + extra (FRCONCOURSE has +0.32s)
    # - REGN2 (loop): everything else
    # NOTE: This may not be optimal for all music types - experiment as needed!
    
    # Calculate 6 seconds in bytes for this audio format
    local six_seconds_bytes=$(echo "$bytes_per_second * 6" | bc -l | cut -d. -f1)
    
    # REGN3 (outro): ~6 seconds, rounded to sample boundary
    local regn3_length=$six_seconds_bytes
    
    # REGN1 (intro): ~6 seconds + extra amount
    # For known files, we can match the original pattern
    local intro_extra_seconds
    case "$base_name" in
        "FRCONCOURSE")
            # Original has 6.32 seconds, so extra = 0.32 seconds
            intro_extra_seconds="0.32"
            ;;
        *)
            # For unknown files, use a reasonable default (0.25 seconds = quarter second)
            intro_extra_seconds="0.25"
            ;;
    esac
    
    local intro_extra_bytes=$(echo "$bytes_per_second * $intro_extra_seconds" | bc -l | cut -d. -f1)
    local regn1_length=$((six_seconds_bytes + intro_extra_bytes))
    
    # REGN2 (main loop): everything else
    local regn2_length=$((data_size - regn1_length - regn3_length))
    
    # Ensure no negative lengths (for very short files)
    if [[ $regn2_length -lt 0 ]]; then
        echo "    Warning: Short audio file detected, using proportional segments instead of 6-second pattern"
        # For very short files, use proportional segments
        regn1_length=$((data_size / 10))  # 10% intro
        regn3_length=$((data_size / 10))  # 10% outro  
        regn2_length=$((data_size - regn1_length - regn3_length))  # 80% loop
    fi
    
    echo "$regn1_length $regn2_length $regn3_length"
}

# Process all WAV files (both .wav and .WAV)
for wav_file in *.wav *.WAV; do
    # Skip if no files match the pattern
    [[ ! -f "$wav_file" ]] && continue
    found_wav=true
    
    # Get base filename without extension
    base_name="${wav_file%.*}"
    
    echo "Processing $wav_file..."
    
    # Get comprehensive audio info using ffprobe
    audio_info=$(ffprobe -v error -show_streams -show_format -of json "$wav_file" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo "  Warning: Could not analyze $wav_file (may not be a valid WAV file), skipping..."
        continue
    fi
    
    # Extract audio properties
    duration_ts=$(echo "$audio_info" | jq -r '.streams[0].duration_ts // empty')
    bits_per_sample=$(echo "$audio_info" | jq -r '.streams[0].bits_per_sample // 16')
    channels=$(echo "$audio_info" | jq -r '.streams[0].channels // 2')
    sample_rate=$(echo "$audio_info" | jq -r '.streams[0].sample_rate // 22050')
    duration_seconds=$(echo "$audio_info" | jq -r '.streams[0].duration // empty')
    
    if [[ -z "$duration_ts" ]] || [[ -z "$duration_seconds" ]]; then
        echo "  Warning: Could not determine audio duration for $wav_file, skipping..."
        continue
    fi
    
    # Calculate data size (duration_ts * bits_per_sample / 8 * channels)
    data_size=$((duration_ts * bits_per_sample / 8 * channels))
    
    # Calculate bytes per second for this specific audio format
    bytes_per_second=$((sample_rate * bits_per_sample / 8 * channels))
    
    echo "  Audio format: $sample_rate Hz, $bits_per_sample-bit, $channels channel(s)"
    echo "  Duration: $duration_seconds seconds ($duration_ts samples)"
    echo "  Bytes per second: $bytes_per_second"
    echo "  Total data size: $data_size bytes"
    
    # Calculate segment lengths using discovered mathematical relationships
    segments=($(calculate_segments "$data_size" "$bytes_per_second" "$base_name"))
    regn1_length=${segments[0]}
    regn2_length=${segments[1]}
    regn3_length=${segments[2]}
    
    # Display the calculated segments in seconds for verification
    regn1_seconds=$(echo "scale=3; $regn1_length / $bytes_per_second" | bc -l)
    regn2_seconds=$(echo "scale=3; $regn2_length / $bytes_per_second" | bc -l)
    regn3_seconds=$(echo "scale=3; $regn3_length / $bytes_per_second" | bc -l)
    
    echo "  Calculated segments (using ~6-second pattern):"
    echo "    REGN1 (intro): $regn1_length bytes = ${regn1_seconds}s"
    echo "    REGN2 (loop):  $regn2_length bytes = ${regn2_seconds}s"  
    echo "    REGN3 (outro): $regn3_length bytes = ${regn3_seconds}s"
    
    # Calculate RELATIVE positions (cumulative REGN lengths starting from 0)
    # VIMA compressor will add its own base offset to all these values
    
    # Start everything at relative position 0
    current_relative_position=0
    
    # FRMT and REGN1 start at relative position 0
    regn1_position=$current_relative_position
    
    # After traversing through REGN1, relative position advances by REGN1 length
    current_relative_position=$((current_relative_position + regn1_length))
    
    # TEXT3 ("lp") and REGN2 start at this relative position
    text3_position=$current_relative_position
    regn2_position=$current_relative_position
    
    # After traversing through REGN2, relative position advances by REGN2 length  
    current_relative_position=$((current_relative_position + regn2_length))
    
    # JUMP and REGN3 start at this relative position
    jump_position=$current_relative_position
    regn3_position=$current_relative_position
    
    # After traversing through REGN3, relative position advances by REGN3 length
    current_relative_position=$((current_relative_position + regn3_length))
    
    # STOP is at the final relative position
    stop_position=$current_relative_position
    
    # Verify our math - final relative position should equal total data size
    if [[ $stop_position -ne $data_size ]]; then
        echo "  ERROR: Segment length calculation error!"
        echo "    This indicates a bug in the script. Please check your audio file."
        echo "    Expected total: $data_size bytes, Calculated: $stop_position bytes"
        continue
    fi
    
    # Create the .imp file (removed TEXT1 and TEXT2 blocks to avoid encoding issues)
    imp_file="${base_name}.imp"
    
    cat > "$imp_file" << EOF
[iMUSE Map]
Version = 1

[FRMT]
Position = 0
Unknown = 1

[REGN1]
Position = $regn1_position
Length = $regn1_length

[TEXT3]
Position = $text3_position
Text = lp

[REGN2]
Position = $regn2_position
Length = $regn2_length

[JUMP1]
Position = $jump_position
JumpDest = $text3_position
ID = 0
Loop = 500

[REGN3]
Position = $regn3_position
Length = $regn3_length

[STOP]
Position = $stop_position
EOF

    echo "  Created $imp_file for looping music"
    echo "    Intro: ${regn1_seconds}s → Loop: ${regn2_seconds}s → Outro: ${regn3_seconds}s"
    echo
done

if [[ "$found_wav" == false ]]; then
    echo "No WAV files found in the current directory."
    exit 1
fi

echo "Done! Generated .imp files for looping music."
echo
echo "Next steps:"
echo "1. Open VIMA Audio Compressor"
echo "2. CHECK 'Create Default TEXT blocks' (important for looping)"
echo "3. UNCHECK 'Lossless' (use lossy compression)"
echo "4. Add your WAV file and its .imp file, then compress"
echo "5. Test the .IMC file in-game"
echo
echo "Notes:"
echo "- For infinite looping: Edit 'Loop = 500' to 'Loop = 9999' in .imp files"
echo "- For non-looping music: Skip the .imp file, just compress the WAV"
echo "- If timing feels wrong: Try analyzing similar original tracks with SCUMM Revisited"