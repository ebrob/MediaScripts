#!/bin/zsh
# Upload a folder (and all subfolders) to an SFTP server.
#
# Reads <PREFIX>_HOST, <PREFIX>_USERNAME, <PREFIX>_PASSWORD (required),
# <PREFIX>_PORT (default 22) and <PREFIX>_REMOTE_PATH (default: remote home)
# from the environment. PREFIX defaults to TD_WEBSITE_SFTP.
# Dotfiles/dot-folders and .DS_Store are skipped.
#
# Usage: sftp-upload.sh [-n] [-p PREFIX] <folder>
#   -n  dry run (list what would be uploaded)
#   -p  environment variable prefix (default TD_WEBSITE_SFTP)

setopt null_glob extended_glob

dry=0
prefix=SCOTTCLAN_WEBSITE_SFTP

while getopts "np:" opt; do
  case $opt in
    n) dry=1 ;;
    p) prefix=$OPTARG ;;
    *) print -u2 "Usage: ${0:t} [-n] [-p PREFIX] <folder>"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

dir=${1:-.}
[[ -d $dir ]] || { print -u2 "Not a directory: $dir"; exit 2; }
dir=${dir:A}

# Indirect lookup of PREFIX_* variables
host=${(P)${:-${prefix}_HOST}}
user=${(P)${:-${prefix}_USERNAME}}
pass=${(P)${:-${prefix}_PASSWORD}}
port=${(P)${:-${prefix}_PORT}:-22}
remote=${(P)${:-${prefix}_REMOTE_PATH}}
remote=${remote%/}

missing=()
[[ -n $host ]] || missing+=${prefix}_HOST
[[ -n $user ]] || missing+=${prefix}_USERNAME
[[ -n $pass ]] || missing+=${prefix}_PASSWORD
if (( $#missing )); then
  print -u2 "Missing required environment variables: ${(j:, :)missing}"
  exit 1
fi

# Escape for sftp batch syntax (double-quoted string)
q() { print -rn -- "\"${1//(#m)[\\\"]/\\$MATCH}\"" }

# Collect files, excluding anything under a dot-named component
files=(${dir}/**/*(.N))
files=(${files:#*/.*})
(( $#files )) || { print -u2 "No files found under $dir"; exit 1; }

# Unique relative directories, parents first (sorted)
dirs=()
for f in $files; do
  rel=${f#$dir/}
  [[ $rel == */* ]] && dirs+=${rel:h}
done
dirs=(${(ou)dirs})
# Include every ancestor
all_dirs=()
for d in $dirs; do
  parts=(${(s:/:)d}); cur=""
  for p in $parts; do cur=${cur:+$cur/}$p; all_dirs+=$cur; done
done
all_dirs=(${(ou)all_dirs})

print "${${dry:#0}:+[dry-run] }Uploading $#files file(s) from $dir to $user@$host:$port -> ${remote:-~}"

batch=$(mktemp -t sftp-batch)
askpass=$(mktemp -t sftp-askpass)
trap 'rm -f $batch $askpass' EXIT INT TERM

{
  if [[ -n $remote ]]; then
    cur=""
    [[ $remote == /* ]] && cur=""
    for p in ${(s:/:)remote}; do
      if [[ $remote == /* && -z $cur ]]; then cur=/$p; else cur=${cur:+$cur/}$p; fi
      print -r -- "-mkdir $(q $cur)"
    done
    base=$remote/
  else
    base=""
  fi
  for d in $all_dirs; do print -r -- "-mkdir $(q $base$d)"; done
  for f in $files; do
    rel=${f#$dir/}
    print -r -- "put $(q $f) $(q $base$rel)"
  done
} > $batch

if (( dry )); then
  for f in $files; do print "  would upload ${f#$dir/}"; done
  exit 0
fi

# Password auth without extra tools: SSH_ASKPASS helper reads the env var
print -r -- '#!/bin/sh' > $askpass
print -r -- "printf '%s\n' \"\$SFTP_UPLOAD_PASSWORD\"" >> $askpass
chmod 700 $askpass

SFTP_UPLOAD_PASSWORD=$pass \
SSH_ASKPASS=$askpass SSH_ASKPASS_REQUIRE=force DISPLAY=${DISPLAY:-none} \
sftp ${SFTP_DEBUG:+-v} -o BatchMode=no -b $batch \
  -P $port \
  -o PreferredAuthentications=password,keyboard-interactive \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  -o StrictHostKeyChecking=accept-new \
  "$user@$host"
rc=$?

(( rc == 0 )) && print "Done." || print -u2 "Upload failed (sftp exit $rc)"
exit $rc
