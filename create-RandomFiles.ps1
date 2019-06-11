# create-RandomFiles.ps1
[cmdletbinding()]
param(
    # Path
    [Parameter(Mandatory = $true)]
    [System.Io.FileInfo] $Path,

    # Size MB
    [Parameter(Mandatory = $true)]
    [int] $SizeMB
)

begin{
    $ext = "docx","xml","csv","txt","xlsx","mp3","pptx"

    if (-Not (Test-Path -Path $Path -PathType Container) ){
        Write-Verbose "PATH: Destination folder does not exist, creating."
        try {
            New-Item -ItemType "directory" -Path $path | Out-Null
        } catch {
            throw "Unable to create destination directory."
        }
    }

    $vol = (Get-Item -Path $Path).Root.Name -replace ("\\","")
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$vol'"

    # check free space on drive
    Write-Verbose "SIZE: Checking volume utilization"
    if ($disk.FreeSpace/1MB -le $SizeMB) {
        Write-Verbose ("... There is only " + $disk.FreeSpace/1MB + "MB available on $vol")
        throw "There is insufficent space on $vol"
    } else {
        Write-Verbose "... SizeMB specified is less than free space."
    }

    if ($disk.FreeSpace / $disk.Size -lt .20) {
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Continue."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Exit."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        $title = "WARNING: Volume utilization warning"
        $question = "There is less than 20% free on $vol. Do you want to continue?"
        
        $result = $host.UI.PromptForChoice($title,$question,$options,1)

        switch($result) {
            0{
                # yes
                Write-Verbose "... Volume utilization warning, continue: Yes"
            }
            1{
                # no
                Write-Verbose "... Volume utilization warning, continue: No"
                throw "Volume utilization warning."
            }
        }
    }

}
process {

    Write-Verbose "Creating files"

    $MaxB = $SizeMB * 1048576

    do{
        # get folder size, in bytes
        $FolderB = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum

        # Once we start dealing with larger sizes, the script may generate
        # only a few large files. This will help create a sufficent number
        # of files.
        if ($SizeMB -ge 1024) {
            [Int]$Bytes = $MaxB / 50
        } else {
            [Int]$Bytes = $MaxB / 10
        }

        # create new random size, in bytes.
        $FileB = Get-Random -Minimum 1 -Maximum $Bytes

        # make sure we stay under the max folder size
        if ($FolderB + $FileB -gt $MaxB) {
            $FileB = $MaxB - $FolderB
        }

        $name = (Get-Item -Path $Path).FullName + "\random" + (Get-Random -InputObject (100000..999999)) + "." + (Get-Random -InputObject $ext)
        
        if ($FileB -ne 0) {

            Write-Verbose "... creating $name, size $FileB"

            fsutil file createnew $name $FileB
        }

    } while (
        $FolderB -lt $MaxB
    )
}

