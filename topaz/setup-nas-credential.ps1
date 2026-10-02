# Run ONCE on Hyperion, in a normal PowerShell window, as robli (no admin needed).
# Prompts for the NAS login and saves it encrypted with Windows DPAPI: only this
# Windows user on this machine can decrypt it. The password is never written in plain text.
$dir = Join-Path $env:LOCALAPPDATA 'topaz-mcp'
New-Item -ItemType Directory -Force $dir | Out-Null
$cred = Get-Credential -UserName 'admin' -Message 'NAS login for \\192.168.5.5\tracklessdeep'
$cred | Export-Clixml (Join-Path $dir 'nas.cred.xml')
Write-Host "Saved to $dir\nas.cred.xml"
