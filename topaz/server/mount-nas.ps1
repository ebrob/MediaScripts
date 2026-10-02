# Connects this logon session to the NAS share using the DPAPI-encrypted credential
# saved by setup-nas-credential.ps1. Needed because SSH logons do not see drive letters
# or saved credentials from the desktop session. Exit 0 = connected.
param([string]$Share = '\\192.168.5.5\tracklessdeep')
$f = Join-Path $env:LOCALAPPDATA 'topaz-mcp\nas.cred.xml'
if (-not (Test-Path $f)) { Write-Error "no credential file at $f (run setup-nas-credential.ps1)"; exit 2 }
$c = Import-Clixml $f
try {
    New-SmbMapping -RemotePath $Share -UserName $c.UserName `
        -Password $c.GetNetworkCredential().Password -ErrorAction Stop | Out-Null
} catch {
    Write-Error $_.Exception.Message; exit 1
}
