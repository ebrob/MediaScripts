#!/bin/zsh
# Build a browsable thumbnail gallery for a folder of mp4 files.
#
# For each mp4 in <folder>:
#   - extracts a thumbnail every N seconds
#   - writes a page with the file name and all of its thumbnails
# Then writes web/index.html linking to every page, using one thumbnail
# per video (the middle one) and showing each file name.
#
# Output goes to <folder>/web:
#   web/index.html
#   web/<slug>.html
#   web/<slug>/thumb_0001.jpg ...
#
# Usage: make-contact-pages.sh [-i seconds] [-w pixels] [-f] [-r] <folder>
#   -i  seconds between thumbnails (default 10)
#   -w  thumbnail width in pixels (default 320)
#   -f  force: re-extract thumbnails even if they already exist
#   -r  recurse into subfolders (skips the web folder)

setopt null_glob extended_glob

interval=10
width=320
force=0
recurse=0

while getopts "i:w:fr" opt; do
  case $opt in
    i) interval=$OPTARG ;;
    w) width=$OPTARG ;;
    f) force=1 ;;
    r) recurse=1 ;;
    *) print -u2 "Usage: ${0:t} [-i seconds] [-w pixels] [-f] [-r] <folder>"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

dir=${1:-.}
[[ -d $dir ]] || { print -u2 "Not a directory: $dir"; exit 2; }
command -v ffmpeg >/dev/null || { print -u2 "ffmpeg not found"; exit 1; }
dir=${dir:A}
web="$dir/web"

if (( recurse )); then
  files=("$dir"/**/*.(mp4|MP4)(.N))
  files=(${files:#"$web"/*})
else
  files=("$dir"/*.(mp4|MP4)(.N))
fi
(( ${#files} )) || { print -u2 "No mp4 files in $dir"; exit 0; }
mkdir -p "$web"

html_escape() {
  local s=$1
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}
  print -r -- $s
}

# Percent-encode a path for use in an href (byte-wise, keeps "/").
url_encode() {
  local LC_ALL=C s=$1 out= c i
  for (( i = 1; i <= ${#s}; i++ )); do
    c=${s[i]}
    if [[ $c == [A-Za-z0-9._~/-] ]]; then out+=$c; else out+=$(printf '%%%02X' "'$c"); fi
  done
  print -r -- $out
}

fmt_time() {  # seconds -> H:MM:SS or M:SS
  local t=$1
  if (( t >= 3600 )); then printf '%d:%02d:%02d' $((t/3600)) $((t%3600/60)) $((t%60))
  else printf '%d:%02d' $((t/60)) $((t%60)); fi
}

style='body{font-family:system-ui,sans-serif;margin:1.5rem;background:#fafafa;color:#222}
h1{font-size:1.3rem;word-break:break-all}
a{color:#0b5cad;text-decoration:none}a:hover{text-decoration:underline}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax('"$width"'px,1fr));gap:1rem}
figure{margin:0}img{width:100%;height:auto;display:block;background:#000;border-radius:4px}
figcaption{font-size:.8rem;color:#555;margin-top:.2rem;word-break:break-all}'

typeset -A used_slugs
index_cards=()
count=0

for f in $files; do
  rel=${f#$dir/}
  slug=${rel:r}
  slug=${slug//[^A-Za-z0-9._-]/_}
  # Keep slugs unique if two files would collapse to the same name
  base=$slug; n=1
  while [[ -n ${used_slugs[$slug]} ]]; do slug="${base}_$((++n))"; done
  used_slugs[$slug]=1

  tdir="$web/$slug"
  thumbs=("$tdir"/thumb_*.jpg(N))

  if (( force || ${#thumbs} == 0 )); then
    rm -rf "$tdir"; mkdir -p "$tdir"
    print -u2 "Thumbnails: $rel"
    ffmpeg -v error -nostdin -y -i "$f" -an -sn \
      -vf "fps=1/${interval},scale=${width}:-2" -q:v 4 \
      "$tdir/thumb_%04d.jpg" 2>/dev/null
    thumbs=("$tdir"/thumb_*.jpg(N))
    if (( ${#thumbs} == 0 )); then   # very short or odd file: take the first frame
      ffmpeg -v error -nostdin -y -i "$f" -an -sn -frames:v 1 \
        -vf "scale=${width}:-2" -q:v 4 "$tdir/thumb_0001.jpg" 2>/dev/null
      thumbs=("$tdir"/thumb_*.jpg(N))
    fi
  else
    print -u2 "Skipping (thumbnails exist, use -f to redo): $rel"
  fi

  if (( ${#thumbs} == 0 )); then
    print -u2 "FAILED (no frames): $rel"
    continue
  fi

  title=$(html_escape "$rel")
  video_href=$(url_encode "../$rel")

  {
    print -r -- "<!doctype html><html><head><meta charset=\"utf-8\">"
    print -r -- "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    print -r -- "<title>$title</title><style>$style</style></head><body>"
    print -r -- "<p><a href=\"index.html\">&larr; All videos</a></p>"
    print -r -- "<h1>$title</h1>"
    print -r -- "<p><a href=\"$video_href\">Open video</a> &middot; ${#thumbs} thumbnails, one every ${interval}s</p>"
    print -r -- "<div class=\"grid\">"
    i=0
    for t in $thumbs; do
      src=$(url_encode "$slug/${t:t}")
      print -r -- "<figure><a href=\"$src\"><img src=\"$src\" loading=\"lazy\" alt=\"\"></a><figcaption>$(fmt_time $((i * interval)))</figcaption></figure>"
      (( i++ ))
    done
    print -r -- "</div></body></html>"
  } > "$web/$slug.html"

  mid=${thumbs[$(( (${#thumbs} + 1) / 2 ))]}
  index_cards+=("<figure><a href=\"$(url_encode "$slug.html")\"><img src=\"$(url_encode "$slug/${mid:t}")\" loading=\"lazy\" alt=\"\"></a><figcaption><a href=\"$(url_encode "$slug.html")\">$title</a></figcaption></figure>")
  (( count++ ))
done

{
  print -r -- "<!doctype html><html><head><meta charset=\"utf-8\">"
  print -r -- "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
  print -r -- "<title>${dir:t}</title><style>$style</style></head><body>"
  print -r -- "<h1>$(html_escape "${dir:t}") &mdash; $count videos</h1>"
  print -r -- "<div class=\"grid\">"
  print -rl -- $index_cards
  print -r -- "</div></body></html>"
} > "$web/index.html"

print -u2 "Done: $count video(s). Open $web/index.html"
