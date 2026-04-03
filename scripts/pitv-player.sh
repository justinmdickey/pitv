#!/usr/bin/env bash
# PiTV Player — Loops video files on composite output via mplayer
# Designed for Raspberry Pi Zero + Casio TV-880B

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/../config/pitv.conf"

# Defaults (overridden by pitv.conf)
VIDEO_DIR="$HOME/pitv/videos"
VIDEO_EXTENSIONS="mp4 mkv avi m4v"
SHUFFLE=false
RESTART_DELAY=3
NO_VIDEO_RETRY=30

# Source config
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=../config/pitv.conf
    source "$CONF_FILE"
else
    echo "[pitv] Warning: Config not found at $CONF_FILE, using defaults" >&2
fi

log() {
    echo "[pitv] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# Build playlist from video directory
build_playlist() {
    local files=()
    for ext in $VIDEO_EXTENSIONS; do
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$VIDEO_DIR" -maxdepth 1 -iname "*.${ext}" -print0 2>/dev/null)
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        return 1
    fi

    if [[ "$SHUFFLE" == "true" ]]; then
        printf '%s\n' "${files[@]}" | shuf
    else
        printf '%s\n' "${files[@]}" | sort
    fi
}

# Clean shutdown on SIGTERM
cleanup() {
    log "Received shutdown signal, stopping playback"
    if [[ -n "${PLAYER_PID:-}" ]] && kill -0 "$PLAYER_PID" 2>/dev/null; then
        kill "$PLAYER_PID" 2>/dev/null || true
        wait "$PLAYER_PID" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

log "PiTV player starting"

# Main loop — restarts mplayer if it exits
while true; do
    PLAYLIST=$(build_playlist) || {
        log "No video files found in $VIDEO_DIR — retrying in ${NO_VIDEO_RETRY}s"
        sleep "$NO_VIDEO_RETRY"
        continue
    }

    FILE_COUNT=$(echo "$PLAYLIST" | wc -l)
    log "Found $FILE_COUNT video file(s), starting playback"

    # Play each file in sequence, then loop
    while IFS= read -r file; do
        log "Playing: $(basename "$file")"

        /usr/bin/mplayer \
            -vo fbdev:/dev/fb0 \
            -vf scale=720:480 \
            -nosound \
            -really-quiet \
            -slave \
            "$file" &
        PLAYER_PID=$!

        wait "$PLAYER_PID" || true
        PLAYER_PID=""
    done <<< "$PLAYLIST"

    log "Playlist complete, looping"
    sleep "$RESTART_DELAY"
done
