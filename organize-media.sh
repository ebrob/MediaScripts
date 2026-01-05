#!/bin/zsh
#echo "Current date and time: $(date)"

zmodload zsh/datetime
echo "Please enter the directory:"
read dir
#dir="/Volumes/LocalBackup/Mega/iPhone-backups/iPhone-backup-2019-06-16/101APPLE"

notAllowed=( "db" "info" "jbp" "ps1" "sh" "aae" )

for file in ${dir}/*(.); do
    extension="${(L)file:e}"
    echo $extension
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
        #echo $json_metadata
        continue;
    fi

    whenTaken=$( strftime -r "%Y:%m:%d %H:%M:%S" "$textDateTaken" )
    yearPrefix=$( strftime "%Y" $whenTaken )
    datePrefix=$( strftime "%Y-%m-%d" $whenTaken )

    yearDir="${localDir}/${yearPrefix}"
    dateDir="${localDir}/${yearPrefix}/${datePrefix}"
    newPath="${dateDir}/${datePrefix}-${basename}.${extension}"
    if [[ "$basename" == "$datePrefix"* ]]; then
        echo " - Already done"
        continue;
    fi

    mkdir -p $yearDir
    mkdir -p $dateDir
    mv $file $newPath
    echo " - Renamed to ${newPath}"
done