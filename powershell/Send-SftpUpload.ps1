<#
.SYNOPSIS
  Uploads a folder (and all subfolders) to an SFTP server.

.DESCRIPTION
  Reads <PREFIX>_HOST, <PREFIX>_USERNAME, <PREFIX>_PASSWORD (required),
  <PREFIX>_PORT (default 22) and <PREFIX>_REMOTE_PATH (default: remote home)
  from the environment. PREFIX defaults to SCOTTCLAN_WEBSITE_SFTP.
  Dotfiles and anything inside dot-folders are skipped.

  Uses the OpenSSH sftp.exe that ships with Windows. The password is handed to it through an
  SSH_ASKPASS helper, so it never appears on a command line.

.EXAMPLE
  .\Send-SftpUpload.ps1 -DryRun C:\site\public
.EXAMPLE
  .\Send-SftpUpload.ps1 -Prefix TD_WEBSITE_SFTP C:\site\public
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Folder = '.',
    # Environment variable prefix
    [string]$Prefix = 'SCOTTCLAN_WEBSITE_SFTP',
    # List what would be uploaded without connecting
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
    Write-Error "Not a directory: $Folder"
    exit 2
}
$dir = (Resolve-Path -LiteralPath $Folder).ProviderPath.TrimEnd('\')

function Get-Setting([string]$suffix) { [Environment]::GetEnvironmentVariable("${Prefix}_$suffix") }

$hostName = Get-Setting 'HOST'
$user     = Get-Setting 'USERNAME'
$pass     = Get-Setting 'PASSWORD'
$port     = Get-Setting 'PORT'
if (-not $port) { $port = '22' }
$remote   = (Get-Setting 'REMOTE_PATH')
if ($remote) { $remote = $remote.TrimEnd('/') }

$missing = @()
if (-not $hostName) { $missing += "${Prefix}_HOST" }
if (-not $user)     { $missing += "${Prefix}_USERNAME" }
if (-not $pass)     { $missing += "${Prefix}_PASSWORD" }
if ($missing) {
    Write-Error "Missing required environment variables: $($missing -join ', ')"
    exit 1
}

# Escape for sftp batch syntax (double-quoted string)
function Q([string]$s) { '"' + ($s -replace '([\\"])', '\$1') + '"' }

# Collect files, excluding anything under a dot-named component of the path relative to $dir
$files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($dir.Length + 1).Replace('\', '/')
    if ($rel -notmatch '(^|/)\.') { [pscustomobject]@{ Full = $_.FullName; Rel = $rel } }
})
if (-not $files) {
    Write-Error "No files found under $dir"
    exit 1
}

# Every relative directory (including ancestors), parents first
$allDirs = $files | ForEach-Object {
    $parts = $_.Rel -split '/'
    for ($i = 1; $i -lt $parts.Count; $i++) { ($parts[0..($i - 1)]) -join '/' }
} | Sort-Object -Unique

$target = if ($remote) { $remote } else { '~' }
$tag = if ($DryRun) { '[dry-run] ' } else { '' }
Write-Host "${tag}Uploading $($files.Count) file(s) from $dir to ${user}@${hostName}:$port -> $target"

if ($DryRun) {
    foreach ($f in $files) { Write-Host "  would upload $($f.Rel)" }
    exit 0
}

# Build the sftp batch: "-" prefix makes mkdir failures (already exists) non-fatal
$batch = New-Object System.Collections.Generic.List[string]
$base = ''
if ($remote) {
    $cur = ''
    foreach ($p in ($remote -split '/' | Where-Object { $_ })) {
        $cur = if ($cur -eq '' -and $remote.StartsWith('/')) { "/$p" } elseif ($cur -eq '') { $p } else { "$cur/$p" }
        $batch.Add("-mkdir $(Q $cur)")
    }
    $base = "$remote/"
}
foreach ($d in $allDirs) { $batch.Add("-mkdir $(Q "$base$d")") }
foreach ($f in $files) { $batch.Add("put $(Q $f.Full.Replace('\', '/')) $(Q "$base$($f.Rel)")") }

$batchFile  = Join-Path $env:TEMP ("sftp-batch-{0}.txt" -f [guid]::NewGuid())
$askpassFile = Join-Path $env:TEMP ("sftp-askpass-{0}.cmd" -f [guid]::NewGuid())
$oldEnv = @{}
foreach ($n in 'SFTP_UPLOAD_PASSWORD', 'SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE', 'DISPLAY') {
    $oldEnv[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
}

try {
    # No BOM: a BOM would corrupt the first batch command
    [IO.File]::WriteAllLines($batchFile, $batch, (New-Object Text.UTF8Encoding($false)))
    # Delayed expansion keeps special characters in the password (& ^ % etc.) literal
    [IO.File]::WriteAllLines($askpassFile, @('@echo off', 'setlocal EnableDelayedExpansion', 'echo(!SFTP_UPLOAD_PASSWORD!'))

    $env:SFTP_UPLOAD_PASSWORD = $pass
    $env:SSH_ASKPASS = $askpassFile
    $env:SSH_ASKPASS_REQUIRE = 'force'
    if (-not $env:DISPLAY) { $env:DISPLAY = 'none' }

    $sftpArgs = @()
    if ($env:SFTP_DEBUG) { $sftpArgs += '-v' }
    $sftpArgs += @('-o', 'BatchMode=no', '-b', $batchFile, '-P', $port,
        '-o', 'PreferredAuthentications=password,keyboard-interactive',
        '-o', 'PubkeyAuthentication=no',
        '-o', 'NumberOfPasswordPrompts=1',
        '-o', 'StrictHostKeyChecking=accept-new',
        "$user@$hostName")

    & sftp.exe @sftpArgs
    $rc = $LASTEXITCODE
}
finally {
    foreach ($n in $oldEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $oldEnv[$n], 'Process') }
    Remove-Item -LiteralPath $batchFile, $askpassFile -ErrorAction SilentlyContinue
}

if ($rc -eq 0) { Write-Host 'Done.' }
else { Write-Error "Upload failed (sftp exit $rc)" }
exit $rc
