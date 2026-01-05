#!/bin/zsh

dir="/Volumes/Media/Photos/2021/2021-04-04"

for file in ${dir}/**/*(.); do
    extension="${(L)file:e}"
    basename="${file:t:r}"
    fileDir="${file:h}"
    
    echo $file

    path_array=("${(@s:/:)fileDir}")
    len=${#path_array}

    dateDir=${path_array[-1]}
    echo $dateDir
    if [[ "$dateDir" =~ (^[0-9]{4}-[0-9]{2}-[0-9]{2}$) ]]; then
        echo " - Valid!"
        if [[ "$basename" == "$dateDir"* ]]; then
            echo " - Already done"
            continue;
        fi
        
        newPath="${fileDir}/${dateDir}-${basename}.${extension}"
        mv $file $newPath
        echo " - Renamed to ${newPath}"

    fi

done

echo "Done"
