#!/usr/bin/env bash
# PiTV Transcoder — Converts video files for Pi Zero + Casio TV-880B playback
# Run this on your desktop/laptop, NOT on the Pi Zero.
#
# Usage:
#   ./transcode.sh input.mkv output.mp4
#   ./transcode.sh input_dir/ output_dir/

set -euo pipefail

# Target encoding parameters optimized for:
#   - Casio TV-880B 2.3" LCD (~200x150 effective pixels)
#   - Pi Zero hardware H.264 decode (VideoCore IV)
#   - NTSC 29.97fps
RESOLUTION="320:240"
VIDEO_BITRATE="500k"
VIDEO_MAXRATE="600k"
VIDEO_BUFSIZE="1200k"
FRAMERATE="29.97"
AUDIO_BITRATE="64k"

usage() {
    cat <<EOF
PiTV Transcoder — Prepare video files for Casio TV-880B playback

Usage:
  $(basename "$0") <input_file> <output_file>
  $(basename "$0") <input_dir> <output_dir>

Options:
  -r <WxH>    Override resolution (default: 320x240)
  -h          Show this help

Examples:
  $(basename "$0") simpsons_s01e01.mkv videos/s01e01.mp4
  $(basename "$0") ~/rips/ ./videos/

The output is H.264 Baseline / AAC mono in MP4, optimized for
hardware decode on the Raspberry Pi Zero and the tiny Casio screen.
EOF
    exit 0
}

# Parse options
while getopts "r:h" opt; do
    case $opt in
        r) RESOLUTION="${OPTARG/x/:}" ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -lt 2 ]]; then
    echo "Error: Expected input and output arguments." >&2
    usage
fi

INPUT="$1"
OUTPUT="$2"

# Check for ffmpeg
if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg is not installed. Install it first:" >&2
    echo "  macOS:  brew install ffmpeg" >&2
    echo "  Linux:  sudo apt install ffmpeg" >&2
    exit 1
fi

transcode_file() {
    local infile="$1"
    local outfile="$2"

    echo "Transcoding: $(basename "$infile") -> $(basename "$outfile")"

    ffmpeg -i "$infile" \
        -vf "scale=${RESOLUTION}:force_original_aspect_ratio=decrease,pad=${RESOLUTION}:(ow-iw)/2:(oh-ih)/2,setsar=1" \
        -c:v libx264 -profile:v baseline -level 3.0 \
        -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
        -r "$FRAMERATE" \
        -pix_fmt yuv420p \
        -c:a aac -ac 1 -b:a "$AUDIO_BITRATE" \
        -movflags +faststart \
        -y \
        "$outfile"

    echo "Done: $(basename "$outfile") ($(du -h "$outfile" | cut -f1))"
}

# Single file mode
if [[ -f "$INPUT" ]]; then
    if [[ -d "$OUTPUT" ]]; then
        # Output is a directory — derive filename
        BASENAME="$(basename "${INPUT%.*}").mp4"
        OUTPUT="${OUTPUT%/}/${BASENAME}"
    fi
    transcode_file "$INPUT" "$OUTPUT"
    exit 0
fi

# Directory batch mode
if [[ -d "$INPUT" ]]; then
    mkdir -p "$OUTPUT"

    FOUND=0
    for infile in "$INPUT"/*; do
        [[ -f "$infile" ]] || continue

        # Check if it's a video file by extension
        ext="${infile##*.}"
        case "${ext,,}" in
            mp4|mkv|avi|m4v|mov|wmv|flv|webm|ts|mpg|mpeg) ;;
            *) continue ;;
        esac

        BASENAME="$(basename "${infile%.*}").mp4"
        outfile="${OUTPUT%/}/${BASENAME}"

        if [[ -f "$outfile" ]]; then
            echo "Skipping (exists): $(basename "$outfile")"
            continue
        fi

        transcode_file "$infile" "$outfile"
        FOUND=$((FOUND + 1))
    done

    if [[ $FOUND -eq 0 ]]; then
        echo "No video files found in $INPUT"
        exit 1
    fi

    echo ""
    echo "Batch complete: $FOUND file(s) transcoded to $OUTPUT"
    exit 0
fi

echo "Error: $INPUT is not a file or directory" >&2
exit 1
