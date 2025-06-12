# CONFIG
$vmName    = "UbuntuDockerRunner"
$vmPath    = "C:\HyperV\$vmName"
$isoPath   = "$vmPath\ubuntu-22.04-live-server-amd64.iso"
$vhdxPath  = "$vmPath\ubuntu.vhdx"
$memory    = 2GB
$cpuCount  = 2
$switch    = "Default Switch"
$isoUrl    = "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"

# STEP 0: Ensure Hyper-V is enabled
if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -ne "Enabled") {
    Write-Error "❌ Hyper-V isn't enabled. Please enable via Windows Features and reboot."
    exit 1
}
Write-Host "✅ Hyper-V is already installed."

# STEP 1: Clean existing VM
if (Test-Path $vmPath) {
    Write-Host "🧹 Removing existing VM and data..."
    Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $vmPath
}
New-Item -ItemType Directory -Path $vmPath -Force | Out-Null

# STEP 2: Download Ubuntu Server ISO if missing
if (-not (Test-Path $isoPath)) {
    Write-Host "⬇️ Downloading Ubuntu Server ISO..."
    try {
        Invoke-WebRequest -Uri $isoUrl -OutFile $isoPath -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ ISO downloaded: $isoPath"
    } catch {
        Write-Error "❌ Failed to download ISO: $_"
        exit 1
    }
} else {
    Write-Host "✅ ISO already exists: $isoPath"
}

# STEP 3: Create new dynamic VHDX for install
if (Test-Path $vhdxPath) {
    Write-Host "🗑️ Removing existing VHDX: $vhdxPath"
    Remove-Item $vhdxPath -Force
}
Write-Host "💾 Creating new dynamic VHDX..."
try {
    New-VHD -Path $vhdxPath -SizeBytes 50GB -Dynamic -ErrorAction Stop | Out-Null
    Write-Host "✅ VHDX created: $vhdxPath"
} catch {
    Write-Error "❌ Failed to create VHDX: $_"
    exit 1
}

# STEP 4: Build VM
Write-Host "💻 Creating Hyper-V VM..."
try {
    New-VM -Name $vmName -MemoryStartupBytes $memory -Generation 2 -NewVHDPath $vhdxPath -Path $vmPath -ErrorAction Stop | Out-Null
    Set-VMProcessor -VMName $vmName -Count $cpuCount -ErrorAction Stop
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority" -ErrorAction Stop
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $switch -ErrorAction Stop
    Add-VMDvdDrive -VMName $vmName -Path $isoPath -ErrorAction Stop
    Write-Host "✅ VM configured successfully."
} catch {
    Write-Error "❌ Failed to configure VM: $_"
    exit 1
}

# STEP 5: Start Ubuntu installer
Write-Host "▶️ Starting VM..."
try {
    Start-VM -Name $vmName -ErrorAction Stop
    Write-Host "✅ VM '$vmName' started!"
} catch {
    Write-Error "❌ Failed to start VM: $_"
    exit 1
}

Write-Host "`n⚠️ Connect to the installer"
Write-Host "   Open Hyper‑V Manager → Connect to '$vmName' → install Ubuntu as usual."
Write-Host "💡 Set username 'ubuntu', auto-login 'ubuntu' for simplicity."
