<#
.SYNOPSIS
  Builds a browsable contact-sheet site for the losslessly split .m2ts clips.

.DESCRIPTION
  Groups the clips in -InputDir by parent file (martin-01_003.m2ts -> martin-01), then for each clip:
    - extracts a thumbnail every -IntervalSeconds
    - encodes a 240p H.264/AAC .mp4 proxy
  and writes, under -ContactsDir:
    index.html                          one card per parent file
    <parent>.html                       one card per clip in that parent
    <parent>/<clip>.html                proxy video player + clickable thumbnails (click to seek)
    <parent>/<clip>.mp4                 the proxy
    <parent>/<clip>/thumb_0001.jpg ...  thumbnails

  Clips that already have a proxy are not re-encoded (use -Force to redo them), so the script
  can be stopped and re-run. HTML pages are always regenerated.
#>
[CmdletBinding()]
param(
    [string]$InputDir    = 'C:\video-capture\split-lossless',
    [string]$ContactsDir = 'C:\video-capture\contacts',
    [string]$Ffmpeg      = 'ffmpeg',
    [string]$Ffprobe     = 'ffprobe',
    [int]$IntervalSeconds = 10,
    [int]$ThumbWidth      = 320,
    [int]$ProxyHeight     = 240,
    [int]$ProxyCrf        = 28,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

foreach ($tool in $Ffmpeg, $Ffprobe) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found." }
}

function Esc([string]$s) { [Net.WebUtility]::HtmlEncode($s) }
# Percent-encode each path segment for use in an href
function Url([string]$path) { ($path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/' }
function Fmt-Time([double]$sec) {
    $t = [int][math]::Floor($sec)
    if ($t -ge 3600) { '{0}:{1:00}:{2:00}' -f [int][math]::Floor($t / 3600), [int][math]::Floor(($t % 3600) / 60), ($t % 60) }
    else { '{0}:{1:00}' -f [int][math]::Floor($t / 60), ($t % 60) }
}

function Get-Duration([string]$file) {
    $out = & $Ffprobe -v error -show_entries format=duration -of csv=p=0 $file 2>$null
    $d = 0.0
    if ([double]::TryParse(("$out").Trim(), [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { return $d }
    return 0.0
}

# Extracts thumbnails and encodes the proxy in one decode pass.
function New-ClipAssets([string]$src, [string]$thumbDir, [string]$proxy) {
    if (Test-Path $thumbDir) { Remove-Item $thumbDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $thumbDir | Out-Null
    $tmp = "$proxy.tmp"
    $args = @('-v', 'error', '-nostdin', '-y', '-i', $src,
        # The sources are anamorphic (720x480, 4:3 display), so size from the display aspect ratio
        '-map', '0:v:0', '-an', '-vf', "fps=1/$IntervalSeconds,scale=${ThumbWidth}:'trunc(${ThumbWidth}/dar/2)*2',setsar=1", '-q:v', '4',
        (Join-Path $thumbDir 'thumb_%04d.jpg'),
        '-map', '0:v:0', '-map', '0:a:0?',
        '-vf', "yadif=0,scale='trunc($ProxyHeight*dar/2)*2':${ProxyHeight},setsar=1", '-c:v', 'libx264', '-preset', 'veryfast', '-crf', $ProxyCrf,
        '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '96k', '-ac', '2',
        '-movflags', '+faststart', '-f', 'mp4', $tmp)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Ffmpeg @args 2>$null } finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        throw "ffmpeg failed for $src"
    }

    # Very short clip: no frame landed on the interval, so grab the first one
    if (-not (Get-ChildItem $thumbDir -Filter thumb_*.jpg)) {
        $ErrorActionPreference = 'Continue'
        try { & $Ffmpeg -v error -nostdin -y -i $src -an -frames:v 1 -vf "scale=${ThumbWidth}:'trunc(${ThumbWidth}/dar/2)*2',setsar=1" -q:v 4 (Join-Path $thumbDir 'thumb_0001.jpg') 2>$null }
        finally { $ErrorActionPreference = $prev }
    }
    Move-Item -LiteralPath $tmp -Destination $proxy -Force
}

$style = @"
body{font-family:system-ui,sans-serif;margin:1.5rem;background:#fafafa;color:#222}
h1{font-size:1.3rem;word-break:break-all}
a{color:#0b5cad;text-decoration:none}a:hover{text-decoration:underline}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(${ThumbWidth}px,1fr));gap:1rem}
figure{margin:0}img{width:100%;height:auto;display:block;background:#000;border-radius:4px}
figcaption{font-size:.8rem;color:#555;margin-top:.2rem;word-break:break-all}
video{max-width:100%;background:#000;border-radius:4px}
.nav{display:flex;justify-content:space-between;margin:.5rem 0 1rem}
.thumbs img{cursor:pointer}
"@

function Page([string]$title, [string]$body) {
    "<!doctype html><html><head><meta charset=`"utf-8`">" +
    "<meta name=`"viewport`" content=`"width=device-width,initial-scale=1`">" +
    "<title>$(Esc $title)</title><style>$style</style></head><body>$body</body></html>"
}

$srcFiles = Get-ChildItem -Path $InputDir -Filter *.m2ts -File | Sort-Object Name
if (-not $srcFiles) { Write-Host "No .m2ts files found in $InputDir"; return }

New-Item -ItemType Directory -Force -Path $ContactsDir | Out-Null

# Group by parent: martin-01_003.m2ts -> martin-01
$parents = [ordered]@{}
foreach ($f in $srcFiles) {
    $parent = if ($f.BaseName -match '^(.+)_\d+$') { $Matches[1] } else { $f.BaseName }
    if (-not $parents.Contains($parent)) { $parents[$parent] = New-Object System.Collections.Generic.List[object] }
    $parents[$parent].Add($f)
}
Write-Host "$($srcFiles.Count) clip(s) in $($parents.Count) parent file(s)"

$parentInfo = @()
foreach ($parent in $parents.Keys) {
    Write-Host "`n=== $parent ===" -ForegroundColor Cyan
    $pdir = Join-Path $ContactsDir $parent
    New-Item -ItemType Directory -Force -Path $pdir | Out-Null

    $clips = @()
    foreach ($f in $parents[$parent]) {
        $name  = $f.BaseName
        $proxy = Join-Path $pdir "$name.mp4"
        $tdir  = Join-Path $pdir $name
        try {
            if ($Force -or -not (Test-Path $proxy) -or -not (Get-ChildItem $tdir -Filter thumb_*.jpg -ErrorAction SilentlyContinue)) {
                Write-Host "  $($f.Name): thumbnails + proxy"
                New-ClipAssets $f.FullName $tdir $proxy
            }
            else {
                Write-Host "  $($f.Name): up to date"
            }
            $thumbs = @(Get-ChildItem $tdir -Filter thumb_*.jpg | Sort-Object Name | ForEach-Object Name)
            if (-not $thumbs) { throw "no thumbnails produced" }
            $clips += [pscustomobject]@{ Name = $name; Source = $f.FullName; Thumbs = $thumbs; Duration = (Get-Duration $proxy) }
        }
        catch {
            Write-Warning "Skipping $($f.Name): $_"
        }
    }
    if (-not $clips) { continue }

    # One page per clip: player + clickable thumbnails, with prev/next
    for ($i = 0; $i -lt $clips.Count; $i++) {
        $c = $clips[$i]
        $prev = if ($i -gt 0) { "<a href=`"$(Url "$($clips[$i-1].Name).html")`">&larr; $(Esc $clips[$i-1].Name)</a>" } else { '<span></span>' }
        $next = if ($i -lt $clips.Count - 1) { "<a href=`"$(Url "$($clips[$i+1].Name).html")`">$(Esc $clips[$i+1].Name) &rarr;</a>" } else { '<span></span>' }
        $figs = for ($k = 0; $k -lt $c.Thumbs.Count; $k++) {
            $src = Url "$($c.Name)/$($c.Thumbs[$k])"
            $t = $k * $IntervalSeconds
            "<figure><img src=`"$src`" data-t=`"$t`" loading=`"lazy`" alt=`"`"><figcaption>$(Fmt-Time $t)</figcaption></figure>"
        }
        $body = @"
<p><a href="../index.html">All files</a> &rsaquo; <a href="../$(Url "$parent.html")">$(Esc $parent)</a></p>
<h1>$(Esc $c.Name)</h1>
<p>$(Fmt-Time $c.Duration) &middot; source: $(Esc $c.Source)</p>
<video id="v" src="$(Url "$($c.Name).mp4")" controls preload="metadata"></video>
<div class="nav">$prev $next</div>
<p>Click a thumbnail to jump to that point.</p>
<div class="grid thumbs">$($figs -join '')</div>
<script>
var v=document.getElementById('v');
document.querySelectorAll('img[data-t]').forEach(function(im){
  im.addEventListener('click',function(){v.currentTime=+im.dataset.t;v.play();window.scrollTo(0,0);});
});
</script>
"@
        Set-Content -LiteralPath (Join-Path $pdir "$($c.Name).html") -Value (Page $c.Name $body) -Encoding UTF8
    }

    # Parent page: one card per clip
    $cards = foreach ($c in $clips) {
        $mid = $c.Thumbs[[int][math]::Floor(($c.Thumbs.Count - 1) / 2)]
        $href = Url "$parent/$($c.Name).html"
        "<figure><a href=`"$href`"><img src=`"$(Url "$parent/$($c.Name)/$mid")`" loading=`"lazy`" alt=`"`"></a>" +
        "<figcaption><a href=`"$href`">$(Esc $c.Name)</a> &middot; $(Fmt-Time $c.Duration)</figcaption></figure>"
    }
    $total = ($clips | Measure-Object Duration -Sum).Sum
    $body = "<p><a href=`"index.html`">&larr; All files</a></p><h1>$(Esc $parent)</h1>" +
            "<p>$($clips.Count) clips &middot; $(Fmt-Time $total)</p><div class=`"grid`">$($cards -join '')</div>"
    Set-Content -LiteralPath (Join-Path $ContactsDir "$parent.html") -Value (Page $parent $body) -Encoding UTF8

    $midClip = $clips[[int][math]::Floor(($clips.Count - 1) / 2)]
    $parentInfo += [pscustomobject]@{
        Name = $parent; Clips = $clips.Count; Duration = $total
        Thumb = "$parent/$($midClip.Name)/$($midClip.Thumbs[[int][math]::Floor(($midClip.Thumbs.Count - 1) / 2)])"
    }
}

# Main index: one card per parent file
$cards = foreach ($p in $parentInfo) {
    $href = Url "$($p.Name).html"
    "<figure><a href=`"$href`"><img src=`"$(Url $p.Thumb)`" loading=`"lazy`" alt=`"`"></a>" +
    "<figcaption><a href=`"$href`">$(Esc $p.Name)</a> &middot; $($p.Clips) clips &middot; $(Fmt-Time $p.Duration)</figcaption></figure>"
}
$body = "<h1>Contacts &mdash; $($parentInfo.Count) files</h1><div class=`"grid`">$($cards -join '')</div>"
Set-Content -LiteralPath (Join-Path $ContactsDir 'index.html') -Value (Page 'Contacts' $body) -Encoding UTF8

Write-Host "`nDone. Open $(Join-Path $ContactsDir 'index.html')" -ForegroundColor Green
