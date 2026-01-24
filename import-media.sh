#!/bin/zsh

zmodload zsh/datetime
#echo "Please enter the directory:"
#read sourceDir

sourceDir="/Volumes/Media/Photos/intake"
targetDir="/Volumes/Media/Photos"

notAllowed=( "db" "info" "jbp" "ps1" "sh" "aae" )

for file in ${sourceDir}/*(.); do
    extension="${(L)file:e}"
    basename="${file:t:r}"
    localDir="${file:h}"
    if (( notAllowed[(Ie)$extension] )); then
        continue;
    fi
    echo $file

    # Capture all metadata as a JSON string into a variable
    # The -g1 option sorts by group for better structure if needed
    json_metadata=$(exiftool -j "$file")

    textDateTaken=$(echo "$json_metadata" | jq -r '.[0].DateTimeOriginal') 
    if [[ -z "$textDateTaken" || "null" = "$textDateTaken" ]]; then
        textDateTaken=$(echo "$json_metadata" | jq -r '.[0].MediaCreateDate') 
    fi
    if [[ -z "$textDateTaken" || "null" = "$textDateTaken" ]]; then
        textDateTaken=$(echo "$json_metadata" | jq -r '.[0].FileModifyDate') 
    fi
    if [[ -z "$textDateTaken" || "null" = "$textDateTaken" ]]; then
        echo " - Could not find creation date"
        continue;
    fi

    whenTaken=$( strftime -r "%Y:%m:%d %H:%M:%S" "$textDateTaken" )
    yearPrefix=$( strftime "%Y" $whenTaken )
    datePrefix=$( strftime "%Y-%m-%d" $whenTaken )

    yearDir="${targetDir}/${yearPrefix}"
    dateDir="${targetDir}/${yearPrefix}/${datePrefix}"
    newPath="${dateDir}/${datePrefix}-${basename}.${extension}"
    if [[ "$basename" == "$datePrefix"* ]]; then
        echo " *** Already renamed"
        continue;
    fi

    mkdir -p $yearDir
    mkdir -p $dateDir

    if [[ -f "$newPath" ]]; then
        echo " *** Already exists at ${newPath}"
        continue;
    fi

    mv $file $newPath
    echo " - Renamed/moved to ${newPath}"
done