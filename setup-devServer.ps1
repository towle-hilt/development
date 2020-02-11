# setup-devServer.ps1

$credential = Get-Credential

$servers = @()

$servers += New-Object PSObject -Property ([ordered]@{
    name = "MED119z"
    hostIP = "10.250.64.102"
    storageRedIP = "10.250.65.102"
    storageRedPrefixLength = 24
    storageRedNICName = "X520-2-1"
    storageRedVLANName = "Storage_Red"
    storageRedVLANId = "648"
    storageBlueIP = "10.250.67.102"
    storageBluePrefixLength = 24
    storageBlueNICName = "X520-2-2"
    storageBlueVLANName = "Storage_Blue"
    storageBlueVLANId = "646"
})

# test connections
Invoke-Command -Computername $servers.name -Credential $credential -ScriptBlock {
    if ($env:computername) { Write-Host "$env:computername is up" -ForegroundColor Green } else { Write-Host "Computer unavailable" -ForegroundColor Red }
}

# apply license and activate
Invoke-Command -ComputerName $servers.name -Credential $credential -ScriptBlock {
    $computer = Get-Content env:computername
    $sku = (Get-WmiObject Win32_OperatingSystem).OperatingSystemSku
    # standard
    if ($sku -eq 7) {
        $key = "RNFBV-B3V4R-FD8RR-2GRGX-T8473"
    # datacenter
    } elseif ($sku -eq 8) {
        $key = "4JNXT-FGKTV-3HF6J-JV7K2-4RJV7"
    }
    $service = Get-WmiObject -query "select * from SoftwareLicensingService" -computername $computer
    $service.InstallProductKey($key)
    $service.RefreshLicenseStatus()
}

# install features
Invoke-Command -Computername $servers.name -Credential $credential -ScriptBlock {
    Install-WindowsFeature -Name Hyper-V, Data-Center-Bridging, File-Services -IncludeManagementTools
}

# setup servers for WinRM
Invoke-Command -ComputerName $servers.name -Credential $credential -ScriptBlock {
    winrm quickconfig
}

# check for unhealthy disks and reset
Invoke-Command -Computername $servers.name -Credential $credential -ScriptBlock {
    Get-PhysicalDisk | Where-Object {($_.BusType -EQ "SAS" -or $_.BusType -EQ "SATA") -and $_.HealthStatus -eq "Unknown"} | Reset-PhysicalDisk
}

# clean disks
Invoke-Command -Computername $servers.name -Credential $credential -ScriptBlock {

	$disks = Get-PhysicalDisk | Where-Object {($_.BusType -EQ "SAS") -or ($_.BusType -EQ "SATA")}
    
	foreach ($disk in $disks) {       
		Clear-ClusterDiskReservation -Disk $disk.SlotNumber -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue      
	}

	Update-StorageProviderCache -DiscoveryLevel Full
	Start-Sleep 5
	Update-StorageProviderCache -DiscoveryLevel Full

	$storagePools = Get-StoragePool | Where-Object { $_.FriendlyName -ne "primordial" }
	$storagePools | Set-StoragePool -IsReadOnly:$false
	Get-VirtualDisk | Set-VirtualDisk -IsManualAttach:$false
	Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false
	$storagePools | Remove-StoragePool -Confirm:$false

	Update-StorageProviderCache -DiscoveryLevel Full
	Start-Sleep 5
	Update-StorageProviderCache -DiscoveryLevel Full

	$disks = Get-Disk | Where-Object { $_.IsBoot -eq $false -or $_.IsSystem -eq $false }
	foreach ($disk in $disks) {
		$disk | Set-Disk -IsOffline:$false -ErrorAction SilentlyContinue
		$disk | Set-Disk -IsReadOnly:$false -ErrorAction SilentlyContinue
		if ($disk.IsOffline -eq $false -or $disk.IsReadOnly -eq $false) {
			$disk | Where-Object { $_.PartitionStyle -ne "RAW" } | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
			$disk | Initialize-Disk -PartitionStyle GPT -ErrorAction SilentlyContinue
		}
	}
}

# check disks, again
Invoke-Command -Computername $servers.name -Credential $credential -ScriptBlock {
    Get-PhysicalDisk | Where-Object {($_.BusType -EQ "SAS" -or $_.BusType -EQ "SATA") -and $_.HealthStatus -eq "Unknown"}
} | Select-Object PSComputerName,FriendlyName,CanPool,OperationalStatus | Sort-Object PSComputerName,FriendlyName | Format-Table

# setup hyper-v networking
foreach ($server in $servers) {
    Invoke-Command -Computername $server.name -Credential $credential -ArgumentList $server -ScriptBlock {

        # SETUO : Enable Jumbo Frames
        Get-NetAdapterAdvancedProperty | Where-Object {($_.Name -like "NIC*" -or $_.Name -like "X520*") -and ($_.RegistryKeyword -like "*jumbopacket")} | Set-NetAdapterAdvancedProperty -RegistryValue 9014

	    # SETUP : Networking
	    $switch = "vSwitch"

        $nics = $server.storageRedNICName,$server.storageBlueNICName

	    $nets = @()
	    $nets += New-Object PSObject -Property @{
		    name = $server.storageBlueVLANName
		    vlan = $server.storageBlueVLANId
	    }
	    $nets += New-Object PSObject -Property @{
		    name = $server.storageRedVLANName
		    vlan = $server.storageRedVLANId
	    }

	    New-VMSwitch -Name $switch -AllowManagementOS $True -NetAdapterName $nics -EnableEmbeddedTeaming $true
   
        foreach ($net in $nets) {
            Add-VMNetworkAdapter -ManagementOS -SwitchName $switch -Name $net.name
            
		    Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $net.name -Access -VlanId $net.vlan -Confirm:$false
        }

        Get-VMNetworkAdapter -Name $switch -all | Rename-VMNetworkAdapter -NewName "Management"
        ## Get-VMNetworkAdapterVlan -ManagementOS "Management" -NativeVlan 0 -AllowedVlan 66

        Get-NetAdapterRdma | Where-Object {$_.Name -notmatch "Management"} | Enable-NetAdapterRdma

        # SETUP : Interface Affinity
        $nets | Where-Object {$_.Name -match $storageRedVLANName -or $_.Name -match $storageBlueVLANName} | ForEach-Object {
            Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName $_.Name -ManagementOS -PhysicalNetAdapterName $nics[0]
            Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName $_.Name -ManagementOS -PhysicalNetAdapterName $nics[1]
        }

        # SETUP : Quality of Service
        if ($disabled -eq $false) {
		    Remove-NetQosTrafficClass -confirm:$False
		    Remove-NetQosPolicy -confirm:$False

		    New-NetQosPolicy -Name "SMB" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3
		    New-NetQosTrafficClass -Name "SMB" -Priority 3 -BandwidthPercentage 50 -Algorithm ETS

		    Enable-NetQosFlowControl -Priority 3
		    Disable-NetQosFlowControl -Priority 0,1,2,4,5,6,7
		
            foreach ($nic in $nics) {
			    Enable-NetAdapterQos $nic
            }
        }
    }
}

# assign ip addresses
foreach ($server in $servers) {
    Invoke-Command -ComputerName $server.name -Credential $credential -ArgumentList $server -ScriptBlock {
        param ($server)

        New-NetIPAddress -InterfaceAlias ("vEthernet ("+ $server.privateVLANName + ")") -IPAddress $server.privateIP -PrefixLength $server.privatePrefixLength
        New-NetIPAddress -InterfaceAlias ("vEthernet ("+ $server.storageRedVLANName +")") -IPAddress $server.storageRedIP -PrefixLength $server.storageRedPrefixLength
        New-NetIPAddress -InterfaceAlias ("vEthernet ("+ $server.storageBlueVLANName +")") -IPAddress $server.storageBlueIP -PrefixLength $server.storageBluePrefixLength

    }
}

# restart servers
Invoke-Command -ComputerName $servers.name -Credential $credential -ScriptBlock {    
    shutdown /r /t 00
}

# test connections
Invoke-Command -Computername $servers.name -Credential $credential -ScriptBlock {
    if ($env:computername) { Write-Host "$env:computername is up" -ForegroundColor Green } else { Write-Host "Computer unavailable" -ForegroundColor Red }
}

# test cluster resources
Write-Host ("Please log into " + $servers.name[0] + " and execute Test-Cluster command") -ForegroundColor Yellow
Write-Host ("... Command: Test-Cluster -Node '" + ($servers.name -join "','") + "' -Include 'Storage Spaces Direct','Inventory','Network','System Configuration'") -ForegroundColor Yellow
Write-Host "... Initiating remote desktop"
Start-Sleep 3
mstsc /v:($servers.name[0])