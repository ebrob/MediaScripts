<#
.SYNOPSIS
  Losslessly splits .m2ts videos into clips at scene changes (stream copy, no re-encode).

.DESCRIPTION
  For each .m2ts in the input folder:
    1. Detects scene changes with ffmpeg's scene filter (on a downscaled copy, so it is fast).
    2. Drops cut points that would make a clip shorter than -MinClipSeconds.
    3. Splits with "-c copy", so video and audio are untouched. Because nothing is re-encoded,
       each cut lands on the next keyframe at or after the scene change (AVCHD GOPs are ~1.5 s),
       so a cut can be up to ~1.5 s late.
    4. Moves the source file to the "converted" folder (only if ffmpeg succeeded).

  Use -DetectOnly to print the cut points without writing anything, to tune the thresholds.
#>
[CmdletBinding()]
param(
    [string]$InputDir     = 'C:\video-capture\toconvert',
    [string]$OutputDir    = 'C:\video-capture\split-lossless',
    [string]$ConvertedDir = 'C:\video-capture\converted',
    [string]$Ffmpeg       = 'ffmpeg',
    # 0-1; higher = fewer cuts. Handheld home video needs a high value to ignore camera motion.
    [double]$SceneThreshold = 0.4,
    # Cut points closer than this to the previous cut are ignored.
    [double]$MinClipSeconds = 20.0,
    # Print cut points and stop; no clips written, source not moved.
    [switch]$DetectOnly,
    # Leave the source where it is after a successful split.
    [switch]$KeepSource
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

if (-not (Get-Command $Ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg not found. Install it or pass -Ffmpeg <path>."
}

if (-not $DetectOnly) {
    foreach ($dir in $OutputDir, $ConvertedDir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

function Get-SceneTimes([string]$file) {
    $log = Join-Path $env:TEMP ("scenes_{0}.log" -f [guid]::NewGuid())
    try {
        $t = $SceneThreshold.ToString($inv)
        $vf = "scale=320:-2,select='gt(scene,$t)',showinfo"
        # cmd handles the stderr redirect so PowerShell doesn't treat ffmpeg output as errors
        cmd /c "`"$Ffmpeg`" -hide_banner -nostats -i `"$file`" -map 0:v:0 -vf `"$vf`" -an -f null - 2> `"$log`""
        if ($LASTEXITCODE -ne 0) { throw "Scene detection failed for $file (see $log)" }

        $times = @()
        $last = 0.0
        foreach ($m in Select-String -Path $log -Pattern 'pts_time:([\d.]+)') {
            $s = [double]::Parse($m.Matches[0].Groups[1].Value, $inv)
            if (($s - $last) -ge $MinClipSeconds) {
                $times += $s
                $last = $s
            }
        }
        Remove-Item $log -ErrorAction SilentlyContinue
        return $times
    }
    catch {
        throw
    }
}

$files = Get-ChildItem -Path $InputDir -Filter *.m2ts -File
if (-not $files) {
    Write-Host "No .m2ts files found in $InputDir"
    return
}

foreach ($file in $files) {
    Write-Host "`n=== $($file.Name) ===" -ForegroundColor Cyan
    try {
        Write-Host "Detecting scenes (threshold $SceneThreshold, min clip $MinClipSeconds s)..."
        $times = @(Get-SceneTimes $file.FullName)
        Write-Host "Found $($times.Count) cut point(s) -> $($times.Count + 1) clip(s)"

        if ($DetectOnly) {
            if ($times.Count) { Write-Host ("  cuts at (s): " + (($times | ForEach-Object { $_.ToString('0.0', $inv) }) -join ', ')) }
            continue
        }

        $pattern = Join-Path $OutputDir ("{0}_%03d.m2ts" -f $file.BaseName)
        $args = @('-hide_banner', '-y', '-i', $file.FullName, '-map', '0', '-c', 'copy')

        if ($times.Count -gt 0) {
            $list = ($times | ForEach-Object { $_.ToString('0.######', $inv) }) -join ','
            $args += @('-f', 'segment', '-segment_times', $list,
                       '-segment_format', 'mpegts', '-reset_timestamps', '1',
                       '-segment_start_number', '1')
        }
        else {
            $pattern = Join-Path $OutputDir ("{0}_001.m2ts" -f $file.BaseName)
            $args += @('-f', 'mpegts')
        }
        $args += $pattern

        & $Ffmpeg @args
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg exited with code $LASTEXITCODE" }

        if ($KeepSource) {
            Write-Host "Done. Source left in place." -ForegroundColor Green
        }
        else {
            Move-Item -LiteralPath $file.FullName -Destination $ConvertedDir -Force
            Write-Host "Done. Moved source to $ConvertedDir" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed on $($file.Name): $_ (source left in place)"
    }
}
