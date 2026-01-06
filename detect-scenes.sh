#!/bin/zsh

for f in /Volumes/Media/Archive/*.m2ts; do
    echo $f
    fname=${f:t}
    basename=${f:t:r}
    dir=${f:h}
    scenesFilename="${basename}-scenes.csv"
    scenesPath="${dir}/${scenesFilename}"

    if [[ -f "$scenesPath" ]]; then
        continue;
    fi

    echo $scenesPath
    scenedetect --input $f --output $dir list-scenes --filename $scenesPath
done