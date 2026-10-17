#!/bin/zsh
# Detect mp4 files that are (almost) entirely blue screen, e.g. a VHS capture
# that ran past the end of the tape.
#
# Files found to be all blue are moved into a "blue" subfolder of <folder>.
#
# Usage: detect-blue.sh [-i seconds] [-t fraction] [-a] [-r] [-n] <folder>
#   -i  sample one frame every N seconds (default 5)
#   -t  fraction of sampled frames that must be blue to flag a file (default 0.95)
#   -a  also list files whose blue fraction is merely > 0.5 ("partial")
#   -r  recurse into subfolders
#   -n  dry run: report only, don't move anything
#
# A frame counts as "blue" when its average chroma is strongly blue:
#   U >= 140, V <= 125, U - V >= 40   (8-bit YUV, from ffmpeg signalstats)

setopt null_glob extended_glob

interval=5
threshold=0.95
show_partial=0
recurse=0
dry_run=0

while getopts "i:t:arn" opt; do
  case $opt in
    i) interval=$OPTARG ;;
    t) threshold=$OPTARG ;;
    a) show_partial=1 ;;
    r) recurse=1 ;;
    n) dry_run=1 ;;
    *) print -u2 "Usage: ${0:t} [-i seconds] [-t fraction] [-a] [-r] [-n] <folder>"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

dir=${1:-.}
[[ -d $dir ]] || { print -u2 "Not a directory: $dir"; exit 2; }
command -v ffmpeg >/dev/null || { print -u2 "ffmpeg not found"; exit 1; }

if (( recurse )); then
  files=("$dir"/**/*.(mp4|MP4)(.N))
  files=(${files:#"$dir"/blue/*})
else
  files=("$dir"/*.(mp4|MP4)(.N))
fi
(( ${#files} )) || { print -u2 "No mp4 files in $dir"; exit 0; }

flagged=0
for f in $files; do
  # One signalstats record per sampled frame -> "blue total avgU avgV avgY"
  result=$(ffmpeg -v error -nostdin -i "$f" -an -sn \
      -vf "fps=1/${interval},scale=160:-2,signalstats,metadata=print:file=-" \
      -f null - 2>/dev/null |
    awk -F= '
      /^lavfi.signalstats.UAVG/ { u = $2 }
      /^lavfi.signalstats.VAVG/ { v = $2 }
      /^lavfi.signalstats.YAVG/ {
        n++; su += u; sv += v; sy += $2
        if (u >= 140 && v <= 125 && u - v >= 40) b++
      }
      END { if (n) printf "%d %d %.0f %.0f %.0f", b, n, su/n, sv/n, sy/n }')

  if [[ -z $result ]]; then
    print -u2 "SKIP (unreadable or no frames): $f"
    continue
  fi

  read -r blue total au av ay <<< "$result"
  frac=$(awk -v b=$blue -v n=$total 'BEGIN { printf "%.2f", b / n }')
  detail="blue ${blue}/${total} (${frac})  avg YUV ${ay}/${au}/${av}"

  if (( $(awk -v f=$frac -v t=$threshold 'BEGIN { print (f >= t) }') )); then
    print -u2 "BLUE    $detail  ${f:t}"
    (( flagged++ ))
    if (( dry_run )); then
      print -u2 "        would move to $dir/blue/"
    else
      mkdir -p "$dir/blue"
      dest="$dir/blue/${f:t}"
      [[ -e $dest ]] && dest="$dir/blue/${f:t:r}-$RANDOM.${f:e}"
      mv -- "$f" "$dest"
    fi
  elif (( show_partial )) && (( $(awk -v f=$frac 'BEGIN { print (f > 0.5) }') )); then
    print -u2 "PARTIAL $detail  ${f:t}"
  fi
done

print -u2 "Checked ${#files} file(s), ${flagged} all blue$( (( dry_run )) && print " (dry run, nothing moved)" || print " (moved to $dir/blue)")"
