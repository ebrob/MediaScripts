<#
.SYNOPSIS
  Finds .m2ts files that are entirely blue (VHS "no signal" screen) and moves them to a "blue" folder.

.DESCRIPTION
  For each .m2ts in the input folder, samples one frame every -SampleSeconds, downscaled, and
  measures its average color and how uniform it is (ffmpeg signalstats). A frame counts as blue when
    - chroma is blue:  U average >= -MinU and V average <= -MaxV   (8-bit YUV, neutral = 128)
    - the picture is flat: spread between the 10th and 90th luma percentile <= -MaxLumaSpread
  A file is moved only if at least -BluePercent of its sampled frames are blue.
  Use -WhatIf to see what would move, and -Verbose for per-file numbers.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InputDir  = 'C:\video-capture\toconvert',
    [string]$BlueDir   = 'C:\video-capture\blue',
    [string]$Ffmpeg    = 'ffmpeg',
    [double]$SampleSeconds = 5,
    [double]$MinU = 140,
    [double]$MaxV = 125,
    [double]$MaxLumaSpread = 40,
    # Share of sampled frames that must be blue for the file to count as blue.
    [double]$BluePercent = 98
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

if (-not (Get-Command $Ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg not found. Install it or pass -Ffmpeg <path>."
}

function Get-BlueRatio([string]$file) {
    $rate = (1 / $SampleSeconds).ToString($inv)
    $vf = "fps=$rate,scale=64:36,signalstats,metadata=print:file=-"
    # signalstats output goes to stdout (file=-); cmd discards ffmpeg's stderr noise
    $lines = cmd /c "`"$Ffmpeg`" -hide_banner -nostats -loglevel quiet -i `"$file`" -map 0:v:0 -an -vf `"$vf`" -f null - 2>nul"
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed on $file" }

    $frames = 0; $blue = 0
    $u = $v = $lo = $hi = $null
    foreach ($line in $lines) {
        if     ($line -match 'lavfi\.signalstats\.UAVG=([\d.]+)')   { $u  = [double]::Parse($Matches[1], $inv) }
        elseif ($line -match 'lavfi\.signalstats\.VAVG=([\d.]+)')   { $v  = [double]::Parse($Matches[1], $inv) }
        elseif ($line -match 'lavfi\.signalstats\.YLOW=([\d.]+)')   { $lo = [double]::Parse($Matches[1], $inv) }
        elseif ($line -match 'lavfi\.signalstats\.YHIGH=([\d.]+)')  { $hi = [double]::Parse($Matches[1], $inv) }
        elseif ($line -match '^frame:') {
            # a new frame block starts; score the previous one
            if ($null -ne $u) { $frames++; if (($u -ge $MinU) -and ($v -le $MaxV) -and (($hi - $lo) -le $MaxLumaSpread)) { $blue++ } }
            $u = $v = $lo = $hi = $null
        }
    }
    if ($null -ne $u) { $frames++; if (($u -ge $MinU) -and ($v -le $MaxV) -and (($hi - $lo) -le $MaxLumaSpread)) { $blue++ } }

    if ($frames -eq 0) { return $null }
    return [pscustomobject]@{ Frames = $frames; Blue = $blue; Percent = 100.0 * $blue / $frames }
}

$files = Get-ChildItem -Path $InputDir -Filter *.m2ts -File
if (-not $files) {
    Write-Host "No .m2ts files found in $InputDir"
    return
}

foreach ($file in $files) {
    try {
        $r = Get-BlueRatio $file.FullName
        if (-not $r) { Write-Warning "$($file.Name): no frames sampled, skipped"; continue }

        $summary = '{0}: {1}/{2} sampled frames blue ({3:N1}%)' -f $file.Name, $r.Blue, $r.Frames, $r.Percent
        if ($r.Percent -ge $BluePercent) {
            Write-Host "$summary -> BLUE" -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $BlueDir")) {
                New-Item -ItemType Directory -Force -Path $BlueDir | Out-Null
                Move-Item -LiteralPath $file.FullName -Destination $BlueDir
            }
        }
        else {
            Write-Host $summary
        }
    }
    catch {
        Write-Warning "Failed on $($file.Name): $_ (left in place)"
    }
}
