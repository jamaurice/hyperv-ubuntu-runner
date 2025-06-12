# Hyper-V Nested Virtualization and Ubuntu VM Setup

This repository documents the process of setting up a nested virtualization environment on a Hyper-V host and creating an Ubuntu VM (`UbuntuDockerRunner`) within a guest VM (`vm-name`) for running Docker and GitLab Runner.

## Problem Context
Initially, the `HvHost` service failed to start on the host with the error: "A device attached to the system is not functioning." Despite hardware virtualization being enabled (`VirtualizationFirmwareEnabled True`) and `hypervisorlaunchtype Auto` set, the issue persisted. The resolution required enabling nested virtualization within a guest VM.

## Solution
To run the `create-ubuntu-vm.ps1` script successfully inside a VM, the following steps were executed on the host:

### Steps to Enable Nested Virtualization
1. **Gracefully Stop the VM**:
   Stop the existing VM (`vm-name`) to apply changes.
   ```powershell
   Stop-VM -Name "vm-name" -Force
   ```

2. **Enable Nested Virtualization**:
   Configure the VM processor to expose virtualization extensions.
   ```powershell
   Set-VMProcessor -VMName "vm-name" -ExposeVirtualizationExtensions $true
   ```

3. **Start the VM Again**:
   Restart the VM to apply the nested virtualization settings.
   ```powershell
   Start-VM -Name "vm-name"
   ```

After these steps, the `create-ubuntu-vm.ps1` script was executed inside the `vm-name` VM, where Hyper-V could operate with nested virtualization support.

## Creating the Ubuntu VM
The following PowerShell script (`create-ubuntu-vm.ps1`) was used to create the `UbuntuDockerRunner` VM inside the `vm-name` VM:

```powershell
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
```

## Post-Installation Setup
After the `UbuntuDockerRunner` VM is created and Ubuntu is installed, configure it for Docker and GitLab Runner:

### Step 1: Configure Docker on the VM
1. SSH into the VM using the IP address obtained via:
   ```powershell
   Get-VMNetworkAdapter -VMName UbuntuDockerRunner | Select -ExpandProperty IPAddresses
   ```
   Example: `ssh ubuntu@<IP_ADDRESS>`.
2. Update and install Docker:
   ```bash
   sudo apt update
   sudo apt install -y docker.io
   sudo systemctl start docker
   sudo systemctl enable docker
   ```
3. Verify Docker:
   ```bash
   docker --version
   docker run hello-world
   ```

### Step 2: Install GitLab Runner
1. Download and install the GitLab Runner:
   ```bash
   curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
   sudo apt install -y gitlab-runner
   ```
2. Register the Runner (replace `YOUR_RUNNER_TOKEN` with your GitLab token):
   ```bash
   sudo gitlab-runner register \
     --non-interactive \
     --url "https://gitlab.com/" \
     --registration-token "YOUR_RUNNER_TOKEN" \
     --executor "docker" \
     --docker-image alpine:latest \
     --description "UbuntuDockerRunner" \
     --tag-list "ubuntu,linux,docker" \
     --run-untagged="true" \
     --locked="false"
   ```
3. Start the runner:
   ```bash
   sudo gitlab-runner start
   ```

### Step 3: Update `.gitlab-ci.yml`
Ensure your `.gitlab-ci.yml` uses the `ubuntu` tag. Example configuration:
```yaml
stages:
  - build
  - qa
  - staging
  - prod
  - rollback

.default_liquibase_job:
  tags:
    - ubuntu
  image: ubuntu:20.04
  services:
    - docker:dind
  before_script:
    - apt-get update -y
    - apt-get install -y wget unzip openjdk-17-jre
    - wget https://github.com/liquibase/liquibase/releases/download/v4.29.2/liquibase-4.29.2.zip -O liquibase.zip
    - unzip liquibase.zip -d liquibase
    - wget https://github.com/microsoft/mssql-jdbc/releases/download/v12.6.0/mssql-jdbc-12.6.0.jre11.jar -O mssql-jdbc.jar
    - export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    - export PATH=$JAVA_HOME/bin:$PATH:liquibase/liquibase-4.29.2
    - export CLASSPATH=$CLASSPATH:mssql-jdbc.jar
    - ls -la liquibase/liquibase-4.29.2
    - if [ ! -f liquibase/liquibase-4.29.2/liquibase ]; then echo "ERROR: liquibase not found" && exit 1; fi
    - echo $PATH
    - liquibase/liquibase-4.29.2/liquibase --version
    - export EDT_TIME=$(date -u '+%Y-%m-%d_%H-%M-%S_%z' | sed 's/+0000/-0400/')  # ~2025-06-12_02-42-00_-04:00
    - echo $EDT_TIME > current_edt_time.txt
    - cat current_edt_time.txt

build-dev:
  stage: build
  extends: .default_liquibase_job
  script:
    - liquibase/liquibase-4.29.2/liquibase --url=$DB_DEV_URL --username=$DB_USERNAME --password=$DB_PASSWORD --changeLogFile=pipeline/db.changelog-master.xml update
    - liquibase/liquibase-4.29.2/liquibase --url=$DB_DEV_URL --username=$DB_USERNAME --password=$DB_PASSWORD tag dev_$CI_PIPELINE_ID_$EDT_TIME
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: on_success
```

## Verification
1. **VM Creation**: Run the script inside `vm-name` and confirm the `UbuntuDockerRunner` VM starts in Hyper-V Manager.
2. **Installation**: Connect to the VM, install Ubuntu, and set the username to `ubuntu` with auto-login.
3. **Docker and Runner**: Verify Docker and GitLab Runner are operational.
4. **Pipeline Test**: Commit and push the `.gitlab-ci.yml` to trigger the `build-dev` job.

## Current Time Context
- The setup was completed around 02:42 AM EDT on June 12, 2025. The `EDT_TIME` in the pipeline should be approximately `2025-06-12_02-42-00_-04:00`.

## Troubleshooting
- If the script fails, check Event Viewer (Hyper-V-HvHost) inside the `vm-name` VM for errors.
- Ensure sufficient resources (e.g., at least 4GB free memory) on the host and guest VM.
- Share any new errors for further assistance.

