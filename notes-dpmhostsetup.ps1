$hosts = "med97a","med97b","med97c"

# make sure nothing is in our way
Invoke-Command -ComputerName $hosts -ScriptBlock { 
    shutdown /r /t 00
}



# create storage pool from appropriate drive types
Invoke-Command -ComputerName $hosts -ScriptBlock {
    $disks = Get-PhysicalDisk -CanPool $true | Where-Object {$_.FriendlyName -match 'ST6000NM0034|SSDSC2BX40'}
    New-StoragePool -FriendlyName 'pool0' -StorageSubsystemFriendlyName "Windows Storage*" -PhysicalDisks $disks
}

# create virtual disk, and initialize
Invoke-Command -ComputerName $hosts -ScriptBlock {
    $ssd = New-StorageTier -StoragePoolFriendlyName 'pool0' -FriendlyName "SSD_Tier" -MediaType SSD -ResiliencySettingName 'Mirror'
    $hdd = New-StorageTier -StoragePoolFriendlyName 'pool0' -FriendlyName "HDD_Tier" -MediaType HDD -ResiliencySettingName 'Mirror'

    Get-StoragePool -FriendlyName 'pool0' | New-VirtualDisk -FriendlyName 'disk0' -StorageTiers $ssd,$hdd -StorageTierSizes 365GB,27900GB -WriteCacheSize 2GB

    Get-VirtualDisk -FriendlyName 'disk0' | Initialize-Disk -PartitionStyle GPT -PassThru
}

# create volume with appropriate settings for dedupe of vhdx files
Invoke-Command -ComputerName $hosts -ScriptBlock {
    Get-VirtualDisk -FriendlyName 'disk0' | Get-Disk | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -AllocationUnitSize 64KB -UseLargeFRS -Force
}

# enable dedupe on volume
Invoke-Command -ComputerName $hosts -ScriptBlock {
    $Volume = Get-VirtualDisk -FriendlyName 'disk0' | Get-Disk | Get-Partition | Get-Volume

    $Volume | Enable-DedupVolume -UsageType HyperV
    
    $Volume | Set-DedupVolume -MinimumFileAgeDays 0 -OptimizePartialFiles:$false
}

# create additional hyper-v disks for dpm
Invoke-Command -ComputerName $hosts -ScriptBlock {

    $volume = Get-VirtualDisk -FriendlyName 'disk0' | Get-Disk | Get-Partition | Get-Volume
    $vm = Get-VM | Where-Object {$_.Name -match "med119"}
    $vdRoot = $Volume.DriveLetter + ':\Hyper-V\Virtual Hard Disks\'

    # how much space do we have to work with?

    #  convert space available to terabytes for better calculations
    $vSize = $volume.SizeRemaining / [math]::pow(1024,4) 

    #  take off 10%, to leave some space on volume. round down to closest integer
    $vSize = [math]::Floor($vSize * .90)

    # how many files should we create?

    #  best balance, between size and quantity, would be the square root. make it an integer because who wants a partial file?
    $quantity = [int][math]::Sqrt($vSize)

    #  because we also want an even number of files, if quantity is odd, make it even.
    if ($quantity % 2 -eq 1) { $quantity = $quantity - 1 }

    # how large should we make these files?
    #  devide volume size by quantity, round with two decimal places
    $vhdSize = [math]::Round(($vSize / $quantity),2)

    Write-Host ("Creating $quantity $vhdSize" + "TB files")

    # convert to bytes then int64 to hold all the digits
    $vdSize = [int64]($vhdSize * [math]::pow(1024,4)) 
    
    # all that leads to... create the vhdx files
    (1..$quantity) | ForEach-Object {
        $vdPath = ($vdRoot + $vm.name + ' DPM Disk ' + $_ + '.vhdx')

        New-VHD -Path $vdPath -SizeBytes $vdSize -Fixed
    }

    # get scsi controllers
    $controllers = Get-VMScsiController -VMName $vm.Name | Where-Object {$_.Drives.Count -eq 0}

    # create scsi controllers if they dont exist
    if (-not $controllers) {
        (0..1) | %{ Add-VMScsiController -VMName $vm.Name }

        $controllers = Get-VMScsiController -VMName $vm.Name | Where-Object {$_.Drives.Count -eq 0}
    }

    # add new vhdx files to controllers


}




# make sure nothing is in our way
Invoke-Command -ComputerName $hosts -ScriptBlock { 
    Add-AppxPackage -Register -DisableDevelopmentMode "C:\Windows\SystemApps\Microsoft.Windows.SecHealthUI_cw5n1h2txyewy\AppXManifest.xml"
}