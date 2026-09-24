#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$Distro = "Ubuntu-24.04"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Test-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "=== Secure App Appliance - Windows Bootstrap ==="

if (-not (Test-Administrator)) {
    Write-Host ""
    Write-Host "This script must be run from PowerShell as Administrator."
    exit 1
}

Write-Step "Checking WSL"

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue

if (-not $wslCommand) {
    Write-Host "WSL is not available."
    Write-Host "Installing WSL with $Distro..."

    wsl.exe --install -d $Distro

    Write-Host ""
    Write-Host "WSL installation was requested."
    Write-Host "Restart Windows if prompted, launch $Distro once to create your Linux user,"
    Write-Host "then rerun this script."
    exit 0
}

$installedDistros = @(
    wsl.exe --list --quiet 2>$null |
    ForEach-Object { $_.Trim().Replace([char]0, '') } |
    Where-Object { $_ }
)

if ($installedDistros -notcontains $Distro) {
    Write-Step "Installing $Distro"

    wsl.exe --install -d $Distro

    Write-Host ""
    Write-Host "$Distro installation was requested."
    Write-Host "Launch it once to complete Linux user creation, then rerun this script."
    exit 0
}

Write-Step "Checking WSL version"

$wslStatus = wsl.exe --status 2>&1
$wslStatus | ForEach-Object { Write-Host $_ }

Write-Step "Checking Ubuntu initialization"

$probe = wsl.exe -d $Distro -- bash -lc 'printf "WSL_USER=%s\n" "$USER"; id -u' 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "$Distro exists but has not completed first-run initialization."
    Write-Host "Launch $Distro from the Start menu, create the Linux user, then rerun this script."
    exit 0
}

$probe | ForEach-Object { Write-Host $_ }

Write-Step "Ensuring systemd is enabled"

$systemdCheck = wsl.exe -d $Distro -- bash -lc 'ps -p 1 -o comm=' 2>$null

if (($systemdCheck | Out-String).Trim() -ne "systemd") {
    wsl.exe -d $Distro -u root -- bash -lc "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"

    Write-Host ""
    Write-Host "systemd configuration was written."
    Write-Host "Restarting WSL..."
    wsl.exe --shutdown

    Write-Host ""
    Write-Host "Rerun this script after WSL starts again."
    exit 0
}

Write-Host "systemd=PASS"

Write-Step "Windows/WSL baseline ready"

Write-Host ""
Write-Host "WINDOWS_BOOTSTRAP_READY=YES"
Write-Host ""
Write-Host "Next:"
Write-Host "1. Clone the private secure-app-appliance repository inside WSL."
Write-Host "2. Run: ./bootstrap/wsl-bootstrap.sh"
Write-Host "3. Run: ./bootstrap/verify-builder.sh"
