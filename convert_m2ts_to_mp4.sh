#!/bin/zsh
# Convert .m2ts files to deinterlaced .mp4 (H.264 + AAC).
# Usage: convert_m2ts_to_mp4.sh [input_dir] [output_dir]

setopt null_glob nocaseglob

SRC_DIR="${1:-/Volumes/Projects/my-projects/projects-2026/Katrina-Josh-Wedding/katrina-videos/raw-videos}"
OUT_DIR="${2:-$SRC_DIR/mp4}"

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Input directory not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

files=("$SRC_DIR"/*.m2ts)
if (( ${#files} == 0 )); then
  echo "No .m2ts files in $SRC_DIR" >&2
  exit 1
fi

for f in "${files[@]}"; do
  out="$OUT_DIR/${f:t:r}.mp4"
  if [[ -e "$out" ]]; then
    echo "Skipping (exists): $out"
    continue
  fi
  echo "Converting: ${f:t} -> ${out:t}"
  # bwdif=mode=send_frame keeps the original frame rate (use send_field for double rate)
  if ! ffmpeg -nostdin -hide_banner -loglevel warning -stats -i "$f" \
      -map 0:v:0 -map '0:a?' \
      -vf "bwdif=mode=send_frame:parity=auto:deint=all" \
      -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
      -c:a aac -b:a 192k \
      -movflags +faststart \
      "$out"; then
    echo "FAILED: $f" >&2
    rm -f "$out"
  fi
done

echo "Done. Output in: $OUT_DIR"
