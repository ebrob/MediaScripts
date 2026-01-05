#!/bin/zsh

for f in /Volumes/Media/Archive/1990-Rehearsal-Luncheon-Wedding.m2ts; do
    fname=${f:t}
    basename=${f:t:r}
    dir=${f:h}
    scenesFilename="${basename}-scenes.csv"
    scenesPath="${dir}/${scenesFilename}"

    if [ -f "$scenesPath" ]; then
        echo "Found scenes file ${scenesFilename}"

        # Read scene information
        sceneIndexes=()
        startTimecodes=()
        endTimecodes=()

        # Regular expression for integer
        isIntegerRe='^[0-9]+$'

        # Columns of standard scene CSV file
        # Start Frame,Start Timecode,Start Time (seconds),End Frame,End Timecode,End Time (seconds),Length (frames),Length (timecode),Length (seconds)

        IFS=','
        while read -rA array; do
            sceneIdx=${array[1]}
            if ! [[ $sceneIdx =~ $isIntegerRe ]] ; then
                continue;
            fi

            sceneIndexes+=$sceneIdx
            startTimecodes+=${array[3]}
            endTimecodes+=${array[6]}

        done < $scenesPath
        unset IFS

        # Create subdir
        subdir="${dir}/${basename}"
        mkdir -p $subdir

        # Deinterlace and split each scene
        for idx in {1..${#sceneIndexes[@]}..1}; do
            sceneIdx=${sceneIndexes[idx]}
            startTimecode=${startTimecodes[idx]}
            endTimecode=${endTimecodes[idx]}

            targetPath="${subdir}/${basename}-Scene-${(l:3::0:)sceneIdx}.mp4"
            if [ -f "$targetPath" ]; then
                echo "File ${targetPath} already exists. Skipping."
                continue;
            fi

            echo "Scene # ${sceneIdx} - ${startTimecode} to ${endTimecode}"
            ffmpeg -ss $startTimecode -to $endTimecode -i $f -vf bwdif -hide_banner -loglevel error $targetPath 

        done

    fi

done