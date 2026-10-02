# Run ONCE on Hyperion in an elevated PowerShell (Run as administrator):
#   .\setup-ssh.ps1 -PublicKey "ssh-ed25519 AAAA... you@AirSpaceBoundary"
# Get the key on the laptop with:  type $env:USERPROFILE\.ssh\id_ed25519.pub
#   (create one first with: ssh-keygen -t ed25519)
param([Parameter(Mandatory)][string]$PublicKey)
$ErrorActionPreference = 'Stop'

# 1. Install and start OpenSSH Server (works on Windows 10 Home)
if ((Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0).State -ne 'Installed') {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Set-Service sshd -StartupType Automatic
Start-Service sshd

# 2. Default shell = PowerShell 7 if present, else Windows PowerShell
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" }
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value $pwsh -PropertyType String -Force | Out-Null

# 3. Firewall: port 22, local subnet only
Get-NetFirewallRule -Name sshd-lan -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name sshd-lan -DisplayName 'OpenSSH (LAN only)' -Direction Inbound `
    -Protocol TCP -LocalPort 22 -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null

# 4. Authorise the laptop's key. Admin accounts use administrators_authorized_keys.
$isAdminUser = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
if ($isAdminUser) {
    $f = "$env:ProgramData\ssh\administrators_authorized_keys"
    Add-Content -Path $f -Value $PublicKey
    icacls $f /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
} else {
    $d = "$env:USERPROFILE\.ssh"; New-Item -ItemType Directory -Force $d | Out-Null
    Add-Content -Path "$d\authorized_keys" -Value $PublicKey
}

# 5. Never sleep while plugged in; allow ping
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Enable-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -ErrorAction SilentlyContinue

# 6. Topaz env vars (machine-wide) so the CLI finds its models
[Environment]::SetEnvironmentVariable('TVAI_MODEL_DIR',      'C:\ProgramData\Topaz Labs LLC\Topaz Video\models', 'Machine')
[Environment]::SetEnvironmentVariable('TVAI_MODEL_DATA_DIR', 'C:\ProgramData\Topaz Labs LLC\Topaz Video\models', 'Machine')

Write-Host "Done. From the laptop: ssh $env:USERNAME@192.168.0.186 nvidia-smi"
