#!/bin/zsh

dir="/Volumes/Media/Photos/"

for file in ${dir}/**/*(.); do
    extension="${(L)file:e}"
    
    if [[ "$extension" = "ps1" ]]; then
        echo "Deleting script - ${file}"
        rm $file
    fi

done

echo "Done"
