\
# create-ubuntu-vm.ps1
$vmName = "UbuntuDockerRunner"
$vmPath = "C:\HyperV\$vmName"
$vhddPath = "$vmPath\ubuntu.vhdx"
$ubuntuVhdxUrl = "https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso"  # ISO fallback if VHDX fails
$switchName = "Default Switch"
$memory = 2GB
$cpuCount = 2

Write-Host "🔍 Checking for Hyper-V feature..."
if (-not (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -eq "Enabled") {
    Write-Host "❌ Hyper-V is not installed."
    Exit 1
}
Write-Host "✅ Hyper-V is already installed."

if (Test-Path $vmPath) {
    Write-Host "🧼 Deleting VM directory $vmPath..."
    Remove-Item -Recurse -Force $vmPath
}
New-Item -ItemType Directory -Path $vmPath | Out-Null

Write-Host "`n🌐 Downloading Ubuntu VHDX image (22.04)..."
try {
    Invoke-WebRequest -Uri $ubuntuVhdxUrl -OutFile $vhddPath -UseBasicParsing
    Write-Host "✅ Download complete: $vhddPath"
} catch {
    Write-Host "❌ Failed to download VHDX: $($_.Exception.Message)"
    Exit 1
}

Write-Host "`n🔍 Validating VHDX..."
try {
    $vhd = Get-VHD -Path $vhddPath
    Write-Host "✅ VHDX is valid."
} catch {
    Write-Host "❌ VHDX is corrupt. Deleting and exiting..."
    Remove-Item $vhddPath -Force
    Exit 1
}

Write-Host "`n💻 Creating Hyper-V VM..."
New-VM -Name $vmName -MemoryStartupBytes $memory -VHDPath $vhddPath -Generation 2 -Path $vmPath
Set-VMProcessor -VMName $vmName -Count $cpuCount
Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority"
Add-VMNetworkAdapter -VMName $vmName -SwitchName $switchName
Start-VM -Name $vmName

Write-Host "`n✅ VM '$vmName' created and started!"
Write-Host "⏳ Wait 60 seconds, then run this to find the IP:"
Write-Host "`n   Get-VMNetworkAdapter -VMName $vmName | Select -ExpandProperty IPAddresses"
Write-Host "`n🔐 Default Ubuntu login: ubuntu / ubuntu"
