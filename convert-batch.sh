#!/bin/zsh

for f in /Volumes/LocalBackup/Mega/Active-Projects-2/MiniDv-Capture-2017/**/*.avi; do
    fname=${f:t}
    basename=${f:t:r}
    dir=${f:h}

    targetPath="${dir}/${basename}.mp4"

    if [[ -f "$targetPath" ]]; then
        continue;
    fi
    echo $f

    ffmpeg -i $f -vf bwdif -hide_banner -loglevel error $targetPath 
done