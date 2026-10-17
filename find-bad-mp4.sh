#!/bin/zsh
# Find mp4 files that are corrupted or shorter than 1 second and move them
# into a "bad" subfolder of <folder>.
#
# A file is bad when any of these is true:
#   - it is empty, or ffprobe can't read it
#   - it has no video stream
#   - its duration is under 1 second (or unknown)
#   - a full decode reports errors (skipped with -q)
#
# Usage: find-bad-mp4.sh [-d seconds] [-q] [-r] [-n] <folder>
#   -d  minimum duration in seconds (default 1)
#   -q  quick mode: probe only, don't decode (fast, but misses mid-file damage)
#   -r  recurse into subfolders (skips the bad folder)
#   -n  dry run: report only, don't move anything

setopt null_glob extended_glob

min_dur=1
quick=0
recurse=0
dry_run=0

while getopts "d:qrn" opt; do
  case $opt in
    d) min_dur=$OPTARG ;;
    q) quick=1 ;;
    r) recurse=1 ;;
    n) dry_run=1 ;;
    *) print -u2 "Usage: ${0:t} [-d seconds] [-q] [-r] [-n] <folder>"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

dir=${1:-.}
[[ -d $dir ]] || { print -u2 "Not a directory: $dir"; exit 2; }
command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { print -u2 "ffmpeg/ffprobe not found"; exit 1; }
dir=${dir:A}
bad="$dir/bad"

if (( recurse )); then
  files=("$dir"/**/*.(mp4|MP4)(.N))
  files=(${files:#"$bad"/*})
else
  files=("$dir"/*.(mp4|MP4)(.N))
fi
(( ${#files} )) || { print -u2 "No mp4 files in $dir"; exit 0; }

# Echo a reason and return 0 if the file is bad; return 1 if it looks fine.
check() {
  local f=$1 vcodec dur err
  [[ -s $f ]] || { print "empty file"; return 0; }

  vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
             -of csv=p=0 "$f" 2>/dev/null)
  [[ -n $vcodec ]] || { print "unreadable or no video stream"; return 0; }

  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
  if [[ $dur != <->(.<->)# ]] || (( dur < min_dur )); then
    print "duration ${dur:-unknown}s (< ${min_dur}s)"; return 0
  fi

  if (( ! quick )); then
    err=$(ffmpeg -v error -nostdin -i "$f" -map 0:v:0 -f null - 2>&1 </dev/null | head -n 3)
    [[ -z $err ]] || { print "decode errors: ${err%%$'\n'*}"; return 0; }
  fi
  return 1
}

moved=0
for f in $files; do
  if reason=$(check "$f"); then
    print -u2 "BAD  ${f#$dir/}  -- $reason"
    (( moved++ ))
    (( dry_run )) && continue
    mkdir -p "$bad"
    dest="$bad/${f:t}"
    [[ -e $dest ]] && dest="$bad/${f:t:r}-$RANDOM.${f:e}"
    mv -- "$f" "$dest"
  fi
done

print -u2 "Checked ${#files} file(s), ${moved} bad$( (( dry_run )) && print " (dry run, nothing moved)" || print " (moved to $bad)")"
