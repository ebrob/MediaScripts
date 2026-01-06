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

## convert-batch.sh

This will convert (with deinterlacing) a set of old `.avi` files to `.mp4`

## detect-scenes.sh

This will use the PySceneDetect tool to generate a `.csv` file of scenes in a set of `.m2ts` files

## split-scenes.sh

This will read the above `.csv` files and use `ffmpeg` to split, deinterlace, and convert each scene to its own `.mp4` file.

## organize-media.sh

This will pull the date that a photo was captured and append the date in `YYYY-MM-DD` format to the file name. Also will put it in folder with the date.

