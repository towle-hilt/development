Invoke-Command -ComputerName $server -ScriptBlock {

    $allPhysicalDisks = Get-PhysicalDisk | Where-Object {($_.BusType -EQ "SAS") -or ($_.BusType -EQ "SATA")}

    foreach ($allPhysicalDisk in $allPhysicalDisks) {       
        Clear-ClusterDiskReservation -Disk $allPhysicalDisk.DeviceId -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue    
    }

    Update-StorageProviderCache -DiscoveryLevel Full
    Start-Sleep 1
    Update-StorageProviderCache -DiscoveryLevel Full

    $storagePools = Get-StoragePool | ? FriendlyName -NE "primordial"
    $storagePools | Set-StoragePool -IsReadOnly:$false
    Get-VirtualDisk | Set-VirtualDisk -IsManualAttach:$false
    Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false
    $storagePools | Remove-StoragePool -Confirm:$false

    Update-StorageProviderCache -DiscoveryLevel Full
    Start-Sleep 1
    Update-StorageProviderCache -DiscoveryLevel Full

    $disks = Get-Disk
    $diskIdsToRemove = @()
    foreach ($disk in $disks) {
        if ($disk.IsBoot -or $disk.IsSystem) {
            $diskIdsToRemove += $disk.UniqueId
        }
    }

    # Get collection of physical disks
    $allPhysicalDisks = Get-PhysicalDisk | Where-Object {($_.BusType -EQ "SAS") -or ($_.BusType -EQ "SATA")}

    # Create a new collection of physical disks without any system/boot disks
    $physicalDisks = @()
    foreach ($physicalDisk in $allPhysicalDisks) {
        $addDisk = $true

        foreach ($diskIdToRemove in $diskIdsToRemove) {
            if ($physicalDisk.UniqueId -eq $diskIdToRemove) {
                $addDisk = $false
            }
        }

        if ($addDisk) {
            $physicalDisks += $physicalDisk
        }
    }

    # Iterate through all remaining physcial disks and wipe
    foreach ($physicalDisk in $physicalDisks) {
        $disk = $physicalDisk | Get-Disk        

        # Make sure disk is Online and not ReadOnly otherwise, display reason
        # and continue
        $disk | Set-Disk –IsOffline:$false -ErrorAction SilentlyContinue
        $disk | Set-Disk –IsReadOnly:$false -ErrorAction SilentlyContinue

        # Re-instantiate disks to update changes
        $disk = $physicalDisk | Get-Disk        

        if ($disk.IsOffline -or $disk.IsReadOnly) {
        } else {
            # Wipe disk and initialize
            $disk | ? PartitionStyle -NE "RAW" | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
            $disk | Initialize-Disk -PartitionStyle GPT
        }
    }

}