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

# STEP 2: Check and download Ubuntu Server ISO if missing
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
    Write-Host "✅ ISO already exists at $isoPath, skipping download."
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

# STEP 4: Create virtual switch if it doesn't exist
if (-not (Get-VMSwitch -Name $switch -ErrorAction SilentlyContinue)) {
    Write-Host "🕹️ Creating Default Switch..."
    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        if ($adapter) {
            New-VMSwitch -Name $switch -NetAdapterName $adapter.Name -SwitchType External -ErrorAction Stop | Out-Null
            Write-Host "✅ Default Switch created as External."
        } else {
            New-VMSwitch -Name $switch -SwitchType Internal -ErrorAction Stop | Out-Null
            Write-Host "✅ Default Switch created as Internal (no active adapter found)."
        }
    } catch {
        try {
            New-VMSwitch -Name $switch -SwitchType Internal -ErrorAction Stop | Out-Null
            Write-Host "✅ Default Switch created as Internal (External failed)."
        } catch {
            Write-Error "❌ Failed to create Default Switch: $_"
            exit 1
        }
    }
} else {
    Write-Host "✅ Default Switch already exists."
}

# STEP 5: Build VM
Write-Host "💻 Creating Hyper-V VM..."
try {
    New-VM -Name $vmName -MemoryStartupBytes $memory -Generation 2 -VHDPath $vhdxPath -Path $vmPath -ErrorAction Stop | Out-Null
    Set-VMProcessor -VMName $vmName -Count $cpuCount -ErrorAction Stop
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority" -ErrorAction Stop
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $switch -ErrorAction Stop
    Add-VMDvdDrive -VMName $vmName -Path $isoPath -ErrorAction Stop
    Write-Host "✅ VM configured successfully."
} catch {
    Write-Error "❌ Failed to configure VM: $_"
    exit 1
}

# STEP 6: Check and start VM
Write-Host "▶️ Starting VM..."
try {
    $hvHostService = Get-Service HvHost -ErrorAction Stop
    $vmmsService = Get-Service vmms -ErrorAction Stop
    if ($hvHostService.Status -ne "Running") {
        try {
            Start-Service HvHost -Verbose -ErrorAction Stop
            Write-Host "✅ Started HV Host Service."
        } catch {
            Write-Error "❌ Failed to start HV Host Service: $_"
            Write-Host "ℹ️ Ensure hypervisor is enabled with 'bcdedit /set hypervisorlaunchtype auto' and reboot, or check Event Viewer (Hyper-V-HvHost) for details."
            exit 1
        }
    }
    if ($vmmsService.Status -ne "Running") {
        Start-Service vmms -ErrorAction Stop
        Write-Host "✅ Started Hyper-V Virtual Machine Management service."
    }
    Start-VM -Name $vmName -ErrorAction Stop
    Write-Host "✅ VM '$vmName' started!"
} catch {
    Write-Error "❌ Failed to start VM: $_"
    exit 1
}

Write-Host "`n⚠️ Connect to the installer"
Write-Host "   Open Hyper‑V Manager → Connect to '$vmName' → install Ubuntu as usual."
Write-Host "💡 Set username 'ubuntu', auto-login 'ubuntu' for simplicity."
