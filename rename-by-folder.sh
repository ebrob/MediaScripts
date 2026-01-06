#!/bin/zsh

echo "Please enter the year:"
read yr

dir="/Volumes/Media/Photos/${yr}"

for file in ${dir}/**/*(.); do
    extension="${(L)file:e}"
    basename="${file:t:r}"
    fileDir="${file:h}"
    
    path_array=("${(@s:/:)fileDir}")
    len=${#path_array}

    dateDir=${path_array[-1]}
    if [[ "$dateDir" =~ (^[0-9]{4}-[0-9]{2}-[0-9]{2}$) ]]; then
        #echo " - Valid!"
        if [[ "$basename" == "$dateDir"* ]]; then
            #echo " - Already done"
            continue;
        fi
        
        newPath="${fileDir}/${dateDir}-${basename}.${extension}"
        mv $file $newPath
        echo "Renamed ${file} to ${newPath}"

    fi

done

echo "Done"
