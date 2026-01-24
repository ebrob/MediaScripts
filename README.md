# Scripts for converting and splitting videos

- Installed Python 3
- Ran these scripts
```
pip3 install opencv-python
pip3 install numpy
pip3 install Click
pip3 install tqdm
pip3 install appdirs
pip3 install --upgrade opencv
pip3 install --upgrade "scenedetect[opencv]"
```
- Installed homebrew
- Ran this
```
brew install ffmpeg
```

## Set permissions

```
sudo chmod 755 [filename]
```

## General-purpose scripts

### import-media.sh

Looks at the `/Photos/import` folder and finds all photos and movies there. For each, it will

- Pull the date that a photo/video was captured and prepend the date in `YYYY-MM-DD` format to the file name.
- Ensure that the approprate year/date folders exists in in `/Photos`,
- Move the photo/movie to the year/date folder.

### rename-by-folder.sh

Goes through the `/Photos` folders and ensures that all photos/movies have the date prepended, if possible.

## Video scripts

### convert-batch.sh

This will convert video (with deinterlacing) a set of old `.avi` files to `.mp4`

### detect-scenes.sh

This will use the PySceneDetect tool to generate a `.csv` file of scenes in a set of `.m2ts` vide files.

### split-scenes.sh

This will read the above `.csv` files and use `ffmpeg` to split, deinterlace, and convert each scene to its own `.mp4` file.

