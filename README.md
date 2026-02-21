# Video Codec Checks

A bash script that recursively scans a directory tree for **H.265/X265** and/or **H.264/X264** video files using `ffprobe`.

## Features

- **CLI mode** — pass a directory (and optional codec filter) directly as arguments
- **Interactive mode** — when run without arguments, presents a menu (via `whiptail`) to:
  - Select from predefined folders (configured in `.env`)
  - Type a path manually
  - Browse the filesystem
- **Codec selection** — search for H.265, H.264, or both
- **Progress display** — live progress counter while scanning

## Requirements

- [FFmpeg](https://ffmpeg.org/) (`ffprobe` must be in `$PATH`)
- [whiptail](https://en.wikipedia.org/wiki/Newt_(programming_library)) (for interactive mode — pre-installed on most Debian/Ubuntu systems)

## Usage

```bash
# Interactive mode (launches menu)
./video-codec-checks.sh

# Scan a specific directory for H.265 (default)
./video-codec-checks.sh /path/to/videos

# Scan for H.264 only
./video-codec-checks.sh --codec x264 /path/to/videos

# Scan for both codecs
./video-codec-checks.sh --codec both /path/to/videos
```

## Configuration

Copy the example environment file and edit it to add your predefined scan directories:

```bash
cp .env.example .env
```

Each line should follow the format `SCAN_DIR_<Label>="/path/to/folder"`. Underscores in the label are replaced with spaces in the menu.
