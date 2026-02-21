#!/usr/bin/env bash
# -----------------------------------------------------
# check_h265_recursive.sh – Scan a directory tree for H.265/X265 and/or H.264/X264 videos
# -----------------------------------------------------
#
# Usage:
#   ./check_for_x265.sh [--codec x265|x264|both] [directory]
#   ./check_for_x265.sh                # Launch interactive menu (_whiptail)
#
# Options:
#   --codec x265   Search for H.265/HEVC only (default)
#   --codec x264   Search for H.264/AVC only
#   --codec both   Search for both codecs
#
# When called without arguments an interactive menu lets you:
#   1. Pick from predefined folders (loaded from .env)
#   2. Type a path manually
#   3. Browse the filesystem
#
# Predefined folders are read from the .env file next to this script.
# Each line of the form  SCAN_DIR_<Label>="/path"  becomes a menu entry.
#
# Prerequisite: ffprobe (from the FFmpeg suite) must be in $PATH.
# -----------------------------------------------------

# ---------------- Configuration -----------------------
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ENV_FILE="${SCRIPT_DIR}/.env"
UPDATE_EVERY=10                        # How often to refresh the progress line
DISPLAY_INTERVAL=5000                  # How often to update the file-list progress
WHIPTAIL_WIDTH=78
WHIPTAIL_HEIGHT=20
WHIPTAIL_LIST_HEIGHT=12
# -----------------------------------------------------

# ---------- ANSI colour helpers ----------
RED='\033[0;31m'
NC='\033[0m'
# -----------------------------------------

# ---------- Whiptail theme (purple) ----------------

export NEWT_COLORS='
root=,blue
window=black,lightgray
border=black,lightgray
shadow=black,black
button=black,cyan
actbutton=white,cyan
compactbutton=black,lightgray
title=black,lightgray
roottext=white,blue
textbox=black,lightgray
acttextbox=black,cyan
entry=black,white
disentry=gray,lightgray
checkbox=black,lightgray
actcheckbox=black,cyan
emptyscale=,cyan
fullscale=,cyan
listbox=black,lightgray
actlistbox=black,cyan
actsellistbox=white,cyan
sellistbox=black,lightgray
'

# Wrapper: temporarily set lilac palette, run _whiptail, then restore.
_whiptail() {
    printf '%s' "$_LILAC_SET" >&2
    command whiptail "$@"
    local rc=$?
    printf '%s' "$_LILAC_RESET" >&2
    return $rc
}
# ---------------------------------------------------

# ---------- Helper: video-file detection ----------
is_video_file() {
    local fname="${1##*/}"
    local ext="${fname##*.}"
    shopt -s nocasematch
    case "$ext" in
        mp4|mkv|avi|mov|webm|flv|wmv|ts) return 0 ;;
        *)                                return 1 ;;
    esac
    shopt -u nocasematch
}
# --------------------------------------------------

# ---------- Load predefined folders from .env ----------
declare -a MENU_LABELS=()
declare -a MENU_PATHS=()

load_env_dirs() {
    [[ -f "$ENV_FILE" ]] || return
    while IFS='=' read -r key value; do
        # Skip comments and blank lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # Only process SCAN_DIR_* entries
        [[ "$key" =~ ^SCAN_DIR_ ]] || continue
        local label="${key#SCAN_DIR_}"
        label="${label//_/ }"
        # Strip surrounding quotes
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        MENU_LABELS+=("$label")
        MENU_PATHS+=("$value")
    done < "$ENV_FILE"
}
# ------------------------------------------------------

# ---------- Interactive: filesystem browser ----------
browse_filesystem() {
    local current_dir="${1:-/}"
    while true; do
        local -a items=()
        items+=(".." "⬆  ..")
        items+=("." "✔  Select this directory")
        while IFS= read -r -d '' entry; do
            local base="${entry##*/}"
            [[ -z "$base" ]] && continue
            items+=("$base" "📁  $base")
        done < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

        local choice
        choice=$(whiptail --notags --title "Browse: $current_dir" \
                    --menu "Navigate to a directory, or select '.' to use the current one." \
                    $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH $WHIPTAIL_LIST_HEIGHT \
                    "${items[@]}" 3>&1 1>&2 2>&3) || return 1

        if [[ "$choice" == "." ]]; then
            printf '%s' "$current_dir"
            return 0
        elif [[ "$choice" == ".." ]]; then
            current_dir="$(dirname "$current_dir")"
        else
            current_dir="${current_dir%/}/${choice}"
        fi
    done
}
# -----------------------------------------------------

# ---------- Interactive: main menu ----------
interactive_menu() {
    if ! command -v whiptail &>/dev/null; then
        printf "${RED}[ERROR] whiptail is required for interactive mode. Install it or pass a directory as an argument.${NC}\n"
        exit 1
    fi

    load_env_dirs

    local -a menu_items=()
    local idx=0
    for label in "${MENU_LABELS[@]}"; do
        menu_items+=("$idx" "📁  ${label}  →  ${MENU_PATHS[$idx]}")
        ((idx++))
    done
    menu_items+=("manual"  "✏  Type a path manually")
    menu_items+=("browse"  "📂  Browse the filesystem")

    while true; do
        local choice
        choice=$(whiptail --notags --title "H.265 / X265 Scanner" \
                    --menu "Select a directory to scan:" \
                    $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH $WHIPTAIL_LIST_HEIGHT \
                    "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            manual)
                local typed
                typed=$(whiptail --title "Manual Path" \
                            --inputbox "Enter the full path to scan:" \
                            10 $WHIPTAIL_WIDTH "/" 3>&1 1>&2 2>&3) || continue
                printf '%s' "$typed"
                return 0
                ;;
            browse)
                local browsed
                browsed=$(browse_filesystem "/") || continue
                printf '%s' "$browsed"
                return 0
                ;;
            *)
                printf '%s' "${MENU_PATHS[$choice]}"
                return 0
                ;;
        esac
    done
}
# -------------------------------------------------

# ---------- Interactive: codec selection ----------
select_codec_menu() {
    local choice
    choice=$(whiptail --notags --title "Codec Selection" \
                --menu "Which codec(s) do you want to search for?" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH $WHIPTAIL_LIST_HEIGHT \
                "x265" "H.265 / HEVC (x265) only" \
                "x264" "H.264 / AVC (x264) only" \
                "both" "Both H.264 and H.265" \
                3>&1 1>&2 2>&3) || return 1
    printf '%s' "$choice"
}
# -------------------------------------------------

# ---------- Parse CLI arguments ----------
CODEC_FILTER=""
CLI_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --codec)
            shift
            case "${1,,}" in
                x265|x264|both) CODEC_FILTER="${1,,}" ;;
                *) printf "${RED}[ERROR] Invalid codec '%s'. Use x265, x264, or both.${NC}\n" "$1"; exit 1 ;;
            esac
            shift
            ;;
        *)
            CLI_DIR="$1"
            shift
            ;;
    esac
done
# -----------------------------------------

# ---------- Resolve BASE_DIR ----------
if [[ -n "$CLI_DIR" ]]; then
    BASE_DIR="$CLI_DIR"
else
    BASE_DIR="$(interactive_menu)" || { echo "Cancelled."; exit 0; }
fi

# ---------- Resolve CODEC_FILTER ----------
if [[ -z "$CODEC_FILTER" ]]; then
    if command -v whiptail &>/dev/null && [[ -z "$CLI_DIR" ]]; then
        CODEC_FILTER="$(select_codec_menu)" || { echo "Cancelled."; exit 0; }
    else
        CODEC_FILTER="x265"   # default for CLI usage
    fi
fi

if [[ ! -d "$BASE_DIR" ]]; then
    printf "${RED}[ERROR] '%s' is not a valid directory.${NC}\n" "$BASE_DIR"
    exit 1
fi
# --------------------------------------

# -------------------------------------------------------
# Build the list of candidate files with a live progress display
# -------------------------------------------------------
declare -a ALL_FILES
total_found=0
start_time=$(date +%s)

case "$CODEC_FILTER" in
    x265) codec_label="H.265/X265" ;;
    x264) codec_label="H.264/X264" ;;
    both) codec_label="H.264/X264 + H.265/X265" ;;
esac
printf "Scanning for %s under '%s' …\n" "$codec_label" "$BASE_DIR"

while IFS= read -r -d '' path; do
    ALL_FILES+=("$path")
    ((total_found++))

    if (( total_found % DISPLAY_INTERVAL == 0 )); then
        elapsed=$(( $(date +%s) - start_time ))
        printf "\r[+] Collected %'d files (elapsed %02dm:%02ds)" \
               "$total_found" $((elapsed/60)) $((elapsed%60))
    fi
done < <(find "$BASE_DIR" -type f -print0)

printf "\r[+] Collected %'d files – done.\n" "$total_found"

if (( total_found == 0 )); then
    printf "${RED}[ERROR] No files found under '%s'.${NC}\n" "$BASE_DIR"
    exit 1
fi

TOTAL=${#ALL_FILES[@]}
echo "Total candidates that will be examined: $TOTAL"
# -----------------------------------------------------

found_any=false
processed=0

for file in "${ALL_FILES[@]}"; do
    ((processed++))

    if (( processed % UPDATE_EVERY == 0 )) || (( processed == TOTAL )); then
        percent=$(( processed * 100 / TOTAL ))
        printf "\r[%3d%%] Processed %d/%d files…" "$percent" "$processed" "$TOTAL"
    fi

    if ! is_video_file "$file"; then
        continue
    fi

    ffprobe_output=$(ffprobe -v error -select_streams v:0 \
                   -show_entries stream=codec_name \
                     -of default=noprint_wrappers=1:nokey=1 "$file" 2>&1)
    ffprobe_status=$?

    if (( ffprobe_status != 0 )); then
        printf "\n${RED}[ERROR] ffprobe failed: %s${NC}\n" "$ffprobe_output"
        continue
    fi

    codec=${ffprobe_output,,}

    matched=""
    if [[ "$CODEC_FILTER" == "x265" || "$CODEC_FILTER" == "both" ]]; then
        if [[ "$codec" == "hevc" || "$codec" == *"x265"* ]]; then
            matched="H.265/X265"
        fi
    fi
    if [[ -z "$matched" ]] && [[ "$CODEC_FILTER" == "x264" || "$CODEC_FILTER" == "both" ]]; then
        if [[ "$codec" == "h264" || "$codec" == *"x264"* || "$codec" == *"avc"* ]]; then
            matched="H.264/X264"
        fi
    fi

    if [[ -n "$matched" ]]; then
        printf "\n%s detected: %s\n" "$matched" "$file"
        found_any=true
    fi
done

printf "\n"

if ! $found_any; then
    case "$CODEC_FILTER" in
        x265) printf "${RED}No H.265/X265 video files were found.${NC}\n" ;;
        x264) printf "${RED}No H.264/X264 video files were found.${NC}\n" ;;
        both) printf "${RED}No H.264/X264 or H.265/X265 video files were found.${NC}\n" ;;
    esac
fi
