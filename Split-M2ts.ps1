<#
.SYNOPSIS
  Deinterlaces .m2ts videos and splits them into individual .mp4 clips at scene changes.

.DESCRIPTION
  For each .m2ts in the input folder:
    1. Detects scene changes (ffmpeg scene filter on the deinterlaced video).
    2. Re-encodes to H.264/AAC .mp4, cutting a new clip at each scene change.
    3. Moves the source file to the "converted" folder (only if ffmpeg succeeded).
#>
[CmdletBinding()]
param(
    [string]$InputDir     = 'C:\video-capture\toconvert',
    [string]$OutputDir    = 'C:\video-capture\split',
    [string]$ConvertedDir = 'C:\video-capture\converted',
    [string]$Ffmpeg       = 'ffmpeg',
    # 0-1; lower = more cuts. 0.3 is a reasonable start for camcorder footage.
    [double]$SceneThreshold = 0.3,
    # Scene changes closer together than this are ignored (avoids tiny clips).
    [double]$MinClipSeconds = 2.0,
    [int]$Crf = 18
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg not found. Install it or pass -Ffmpeg <path>."
}

foreach ($dir in $OutputDir, $ConvertedDir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$deint = 'bwdif=mode=send_frame:parity=auto:deint=all'

function Get-SceneTimes([string]$file) {
    $log = Join-Path $env:TEMP ("scenes_{0}.log" -f [guid]::NewGuid())
    try {
        $vf = "$deint,select='gt(scene,$SceneThreshold)',showinfo"
        # cmd handles the stderr redirect so PowerShell doesn't treat ffmpeg output as errors
        cmd /c "`"$Ffmpeg`" -hide_banner -nostats -i `"$file`" -vf `"$vf`" -an -f null - 2> `"$log`""
        if ($LASTEXITCODE -ne 0) { throw "Scene detection failed for $file (see $log)" }

        $times = @()
        $last = 0.0
        foreach ($m in Select-String -Path $log -Pattern 'pts_time:([\d.]+)' ) {
            $t = [double]$m.Matches[0].Groups[1].Value
            if (($t - $last) -ge $MinClipSeconds) {
                $times += $t
                $last = $t
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
        Write-Host "Detecting scenes..."
        $times = @(Get-SceneTimes $file.FullName)
        Write-Host "Found $($times.Count) cut point(s) -> $($times.Count + 1) clip(s)"

        $pattern = Join-Path $OutputDir ("{0}_%03d.mp4" -f $file.BaseName)
        $args = @('-hide_banner', '-y', '-i', $file.FullName,
                  '-vf', $deint,
                  '-c:v', 'libx264', '-preset', 'medium', '-crf', $Crf, '-pix_fmt', 'yuv420p',
                  '-c:a', 'aac', '-b:a', '192k')

        if ($times.Count -gt 0) {
            $list = ($times | ForEach-Object { $_.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture) }) -join ','
            # Force keyframes at the cuts so segments split exactly on the scene change
            $args += @('-force_key_frames', $list,
                       '-f', 'segment', '-segment_times', $list,
                       '-segment_format', 'mp4', '-reset_timestamps', '1',
                       '-segment_start_number', '1')
        }
        else {
            $pattern = Join-Path $OutputDir ("{0}_001.mp4" -f $file.BaseName)
        }
        $args += $pattern

        & $Ffmpeg @args
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg exited with code $LASTEXITCODE" }

        Move-Item -LiteralPath $file.FullName -Destination $ConvertedDir -Force
        Write-Host "Done. Moved source to $ConvertedDir" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed on $($file.Name): $_ (source left in place)"
    }
}
