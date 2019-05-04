param(
    # VM Server Prefix
    [Parameter(Mandatory=$True)]
    [String] $vmPrefix = "FABRIC",

    # VM Virtual Disk Path
    [Parameter]
    [ValidateScript({
        if ( -not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "The vdPath argument must be an existing folder."
        }
        return $true
    })]
    [System.IO.FileInfo] $vdPath = "E:\Hyper-V\Virtual Hard Disks",

    # VM Virtual Machine Path
    [Parameter]
    [ValidateScript({
        if ( -not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "The vdPath argument must be an existing folder."
        }        
        return $true
    })]    
    [System.IO.FileInfo] $vmPath = "D:\Hyper-V\Virtual Machines",

    # Create Domain Controller
    [Parameter]
    [Switch] $CreateDomainController = $false,

    # Create System Center
    [Parameter]
    [Switch] $CreateSystemCenter = $false,

    # Create Storage Spaces Direct
    [Parameter]
    [Switch] $CreateS2D = $false
)

# if ending with letter, add space
if ($vmPrefix -match "[a-z]$") { $vmPrefix = $vmPrefix + " " }

# build server array
$servers = @()

# ... admin server
$servers += ($vmPrefix + "Admin Server")

# ... if, domain controller
if ($CreateDomainController) {
    $servers += ($vmPrefix + "Domain Controller")
}

# ... if, system center
if ($CreateSystemCenter) {
    ("VMM","OM","DPM") | ForEach-Object {
        $servers += ($vmPrefix + "System Center " + $_)
    }
}

# ... if, storage spaces direct
if ($CreateS2D) {
    (1..5) | ForEach-Object {
        $servers += ($vmPrefix + "S2D Node " + $_)
    }
}

foreach ($server in $servers){

    New-VHD -Path "$vdPath\$server.vhdx" -ParentPath "$vdPath\Windows 2019 Gold Image.vhdx" -Differencing

    New-VM -Name $server -MemoryStartupBytes 4GB -SwitchName "FABRIC" -Generation 2 -Path $vmPath

    Add-VMHardDiskDrive -VMName $server -Path "$vdPath\$server.vhdx" -ControllerType SCSI

    $vmServer = Get-VM -Name $server
    $vmDisk = $vmServer | Get-VMHardDiskDrive

    if ($vmServer -and $vmDisk) {

        $vmServer | Set-VMFirmware -BootOrder $vmDisk -EnableSecureBoot off -SecureBootTemplate MicrosoftUEFICertificateAuthority
        $vmServer | Set-VM -ProcessorCount 2 -AutomaticStartAction Nothing -AutomaticStopAction TurnOff -CheckpointType Disabled

    } else {
        Write-Host "Unable to access VM or VM Disk." -ForegroundColor Red -BackgroundColor Black
    }

    if ($server -match "S2D Node") {

        Enable-VMIntegrationService -Name 'Guest Service Interface' -VMName $server

    }

}

