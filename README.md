# X-Wing Alliance Custom Music Guide

A complete guide to creating custom looping music for Star Wars: X-Wing Alliance using reverse-engineered iMUSE techniques.

## Table of Contents
- [Overview](#overview)
- [Background & Discovery](#background--discovery)
- [Requirements](#requirements)
- [The Mathematical Pattern](#the-mathematical-pattern)
- [Step-by-Step Process](#step-by-step-process)
- [Tools & Downloads](#tools--downloads)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)
- [Future Improvements](#future-improvements)

## Overview

This guide explains how to create custom music files (.IMC) for X-Wing Alliance that properly loop using the game's iMUSE adaptive music system. Through reverse engineering the original game files, we've discovered the mathematical relationships and positioning logic that make looping music work correctly.

## Background & Discovery

X-Wing Alliance uses LucasArts' iMUSE (Interactive MUsic Streaming Engine) system with VIMA-compressed audio files (.IMC). Each IMC file contains multiple segments that the game can dynamically blend based on gameplay events.

### Key Breakthrough: Relative Positioning

The critical discovery was that the VIMA Audio Compressor uses **relative positioning** starting from 0, then adds its own base offset to all blocks. This explains why manual absolute positioning failed - we were double-offsetting the values.

**Important**: The varying FRMT position values observed in original files (209, 207, 204, etc.) were red herrings - these are VIMA-generated artifacts from the original compression process, not values we need to manually replicate.

## Requirements

### Software Dependencies
- **ffprobe** (part of FFmpeg) - for audio analysis
- **jq** - for JSON parsing  
- **bc** - for mathematical calculations
- **VIMA Audio Compressor** - for creating IMC files
- **SCUMM Revisited** (optional) - for testing/verification

### Installation
```bash
# macOS
brew install ffmpeg jq bc

# Ubuntu/Debian  
sudo apt-get install ffmpeg jq bc

# Windows
# Install via package managers or download binaries
```

## The Mathematical Pattern

Through analysis of the original FRCONCOURSE.IMC file and several test files, we discovered a consistent mathematical relationship. **Note**: This pattern worked for our test cases but may not be universal for all X-Wing Alliance music files.

### Segment Structure (Discovered Pattern)
- **REGN1 (Intro)**: ~6.0 seconds + extra (0.32s for FRCONCOURSE, 0.25s default)
- **REGN2 (Loop)**: Remainder of audio data (the main looping content)  
- **REGN3 (Outro)**: ~6.0 seconds

**⚠️ Important**: The 6-second base pattern worked for ambient/concourse tracks in our testing, but different music types (combat, victory themes, etc.) may use different timing relationships. We recommend:

1. **Testing the 6-second pattern first** - it's a good starting point
2. **Analyzing original files** with SCUMM Revisited to find patterns for specific track types
3. **Experimenting with ratios** - some tracks might use 10% intro, 5% outro, 85% loop
4. **Musical consideration** - align segments with natural musical phrases rather than fixed durations

### Customizing Segment Lengths

To research optimal segments for your music type:

```bash
# Extract an original similar track with SCUMM Revisited
# Check its REGN1, REGN2, REGN3 lengths
# Calculate ratios: intro_ratio = REGN1_length / total_length

# Modify the script's calculate_segments() function:
# regn1_length = total_length * intro_ratio  
# regn3_length = total_length * outro_ratio
# regn2_length = total_length - regn1_length - regn3_length
```

### Position Calculation Logic
Positions advance only when traversing **through** a REGN block:
1. **Start**: Position 0 (FRMT, REGN1)
2. **After REGN1**: Position = REGN1.length (TEXT3 "lp", REGN2)
3. **After REGN2**: Position = REGN1.length + REGN2.length (JUMP, REGN3)
4. **After REGN3**: Position = REGN1.length + REGN2.length + REGN3.length (STOP)

The VIMA compressor then adds its own base offset to all these relative positions.

## Step-by-Step Process

### For Looping Music

1. **Prepare Your Audio**
   - Create a WAV file (16-bit recommended, any sample rate)
   - Ensure it's suitable for looping (intro, main loop section, outro)

2. **Generate the .imp File**
   - Use our automated script (see [Tools & Downloads](#tools--downloads))
   - The script calculates segment lengths and relative positions automatically

3. **Compress with VIMA**
   - Open VIMA Audio Compressor
   - **✅ CHECK** "Create Default TEXT blocks" 
   - **❌ UNCHECK** "Lossless" (use lossy compression)
   - Add your WAV file and corresponding .imp file
   - Compress to create the .IMC file

4. **Install in Game**
   - Navigate to your X-Wing Alliance installation directory
   - **Backup** the original `Music` folder
   - Replace the target .IMC file in the `Music` directory
   - Test in-game

### For Non-Looping Music

1. **Prepare Your Audio** (same as above)
2. **Compress with VIMA**
   - **✅ CHECK** "Create Default TEXT blocks"
   - **❌ UNCHECK** "Lossless"
   - Add only your WAV file (no .imp needed)
   - Compress to create the .IMC file
3. **Install in Game** (same as above)

## Tools & Downloads

### VIMA Audio Compressor
- **Download**: [quickandeasysoftware.net](https://quickandeasysoftware.net/software/vima-compressor)
- **Source Code**: Available on the same site for modifications
- **Note**: Originally designed for Grim Fandango, but compatible with X-Wing Alliance

### SCUMM Revisited (Optional)
- **Download**: [quickandeasysoftware.net](https://quickandeasysoftware.net/software/scumm-revisited)
- **Use**: For extracting original game audio and verifying IMC structure

### Our Automated Script

```bash
#!/bin/bash
# [Include the full working script here]
```

Save as `generate_looping_imps.sh`, make executable with `chmod +x generate_looping_imps.sh`, and run in your WAV directory.

## Technical Details

### iMUSE Map Structure (Looping)
```ini
[iMUSE Map]
Version = 1

[FRMT]
Position = 0
Unknown = 1

[REGN1]
Position = 0
Length = [calculated intro length]

[TEXT3]
Position = [REGN1.length]
Text = lp

[REGN2]  
Position = [REGN1.length]
Length = [calculated loop length]

[JUMP1]
Position = [REGN1.length + REGN2.length]
JumpDest = [REGN1.length]
ID = 0
Loop = 500

[REGN3]
Position = [REGN1.length + REGN2.length]
Length = [calculated outro length]

[STOP]
Position = [REGN1.length + REGN2.length + REGN3.length]
```

### Audio Format Compatibility
- **Sample Rates**: 22050 Hz (original), 44100 Hz (tested), others should work
- **Bit Depth**: 16-bit recommended, others may work
- **Channels**: Stereo preferred, mono should work
- **Format**: Uncompressed PCM WAV

### Segment Length Calculation (Starting Formula)
```bash
# For any audio format:
bytes_per_second = sample_rate × bits_per_sample ÷ 8 × channels

# Our discovered pattern (works for ambient tracks, experiment for others):
# REGN3 (outro): ~6 seconds
regn3_length = bytes_per_second × 6

# REGN1 (intro): ~6 seconds + extra
regn1_length = bytes_per_second × (6 + extra_seconds)

# REGN2 (loop): everything else  
regn2_length = total_data_size - regn1_length - regn3_length

# Alternative approach - percentage-based (more flexible):
# regn1_length = total_data_size × intro_percentage
# regn3_length = total_data_size × outro_percentage  
# regn2_length = total_data_size - regn1_length - regn3_length
```

## Troubleshooting

### Common Issues

**IMC file doesn't play in-game:**
- Verify the IMC file opens correctly in SCUMM Revisited
- Check that you used lossy compression (not lossless)
- Ensure "Create Default TEXT blocks" was checked in VIMA

**Music doesn't loop naturally:**
- The 6-second pattern may not suit your music type or tempo
- Try analyzing similar original tracks with SCUMM Revisited
- Experiment with different intro/outro ratios (5%, 10%, 15% of total duration)
- Consider musical phrasing - align segments with natural musical breaks
- For infinite looping, edit `Loop = 500` to `Loop = 9999` in the .imp file

**Audio quality issues:**
- VIMA compression is lossy - some quality loss is expected
- Try different compression settings in VIMA
- Ensure your source WAV is high quality

**Position calculation errors:**
- Double-check that your script calculates positions relative to 0
- Verify that the final STOP position equals the total audio data size
- Remember: VIMA adds its own base offset automatically
- Use standard FRMT values: Position = 0, Unknown = 1

### Verification Steps

1. **Test in SCUMM Revisited**: Open the generated IMC and check block structure
2. **Verify Positions**: Compare with original game files
3. **In-Game Test**: Load a mission that uses your custom music
4. **Loop Test**: Let the music play long enough to verify looping

## Future Improvements

### Discovered Patterns for Enhancement

1. **Segment Ratio Research**: Analyze different music types (combat, ambient, victory) to discover optimal intro/loop/outro ratios for each category

2. **Dynamic Segment Calculation**: Instead of fixed 6-second segments, calculate based on:
   - Musical phrasing analysis
   - Percentage of total duration  
   - Track category (combat vs ambient vs victory)
   - Tempo and rhythmic patterns

3. **Multi-Loop Structures**: Some original files have multiple loop regions for different intensity levels

4. **Format-Specific Optimizations**: Different sample rates might benefit from different segment ratios

5. **Automated Music Analysis**: Use audio analysis to detect natural loop points and musical phrases

6. **GUI Tool**: Create a user-friendly interface wrapping our command-line tools

### FRMT Block Configuration
The FRMT block should use these standard values:
- **Position**: 0 (relative positioning - VIMA adds its offset)
- **Unknown**: 1 (default value works for all files)

**Note**: The position values we observed in original files (209, 207, 204, etc.) were generated by VIMA during LucasArts' original compression process. These are artifacts of VIMA's internal positioning system, not values we need to manually replicate.

### Research Areas

1. **VIMA Source Modification**: Enhance the compressor for better X-Wing Alliance compatibility
2. **iMUSE Script Integration**: Understanding how the game triggers music transitions  
3. **Advanced Loop Structures**: Multi-region looping for dynamic intensity
4. **Compression Optimization**: Finding the best VIMA settings for different audio types
5. **VIMA Positioning Deep Dive**: Further investigation into VIMA's internal offset calculation system

## File Structure Reference

### X-Wing Alliance Music Directory
```
X-Wing Alliance/
└── Music/
    ├── FRCONCOURSE.IMC    # Concourse theme (looping)
    ├── FRFAMROOM.IMC      # Family room theme (looping)  
    ├── FRHANGAR.IMC       # Hangar theme (looping)
    ├── FRWIN.IMC          # Victory theme (non-looping)
    └── [other IMC files]
```

### Backup Strategy
```bash
# Before modifying, backup original music
cp -r "X-Wing Alliance/Music" "X-Wing Alliance/Music_Original_Backup"
```

## Credits & Acknowledgments

This guide represents a collaborative reverse engineering effort that discovered the mathematical relationships and positioning logic behind X-Wing Alliance's iMUSE system.

### Tools Used
- **VIMA Audio Compressor** by Jimmi Thøgersen (Serge) - The essential tool that made this possible
- **SCUMM Revisited** by QuickAndEasySoftware - For analyzing original IMC structure  
- **FFmpeg/ffprobe** - For audio analysis and format detection

### Key Discoveries
1. **Relative positioning system** in VIMA compressor
2. **Mathematical segment relationships** (6-second base pattern)
3. **iMUSE block traversal logic** for position calculation
4. **TEXT block encoding solutions** to avoid corruption
5. **FRMT position revelation** - values in originals are VIMA-generated, not manually set


This guide and associated scripts are provided for educational and personal use. Respect LucasArts' original game assets and only use custom music you have rights to use.

---
