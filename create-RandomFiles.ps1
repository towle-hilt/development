# create-RandomFiles.ps1
[cmdletbinding()]
param(
    # Path
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if(-Not ($_ | Test-Path -PathType Container) ){
            throw "The Path argument must be a folder. File paths are not allowed."
        }
        return $true    
    })]
    [System.Io.FileInfo] $Path,

    # Size MB
    [Parameter(Mandatory = $true)]
    [int] $SizeMB
)

begin{
    $ext = "docx","xml","csv","txt","xlsx","mp3","pptx"

    $vol = (Get-Item -Path $Path).Root.Name -replace ("\\","")
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$vol'"

    # check free space on drive
    Write-Verbose "SIZE: Checking volume utilization"
    if ($disk.FreeSpace/1MB -le $SizeMB) {
        Write-Verbose ("... There is only " + $disk.FreeSpace/1MB + "MB available on $vol")
        Throw "There is insufficent space on $vol"
    } else {
        Write-Verbose "... SizeMB specified is less than free space."
    }

    if ($disk.FreeSpace / $disk.Size -lt .20) {
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Continue."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Exit."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        $title = "Volume utilization warning"
        $question = "There is less than 20% free on $vol. Do you want to continue?"
        
        $result = $host.UI.PromptForChoice($title,$question,$options,1)

        switch($result) {
            0{
                Write-Verbose "... Volume utilization warning: ACCEPTED"
            }
            1{
                Write-Verbose "... Volume utilization warning: IGNORED"
                Throw "Volume utilization warning: IGNORED"
            }
        }
    }

}
process {

    Write-Verbose "Creating files"
    do{
        $name = (Get-Item -Path $Path).FullName + "random" + (Get-Random -InputObject (10000..99999)) + "." + (Get-Random -InputObject $ext)
        # $bytes = [math]::pow(1024, (Get-Random -InputObject (1..2))) * (Get-Random -InputObject (1..9))

        $bytes = Get-Random -Minimum 1 -Maximum ([Int64]::($SizeMB * 1024))
    
        Write-Verbose "... creating $name, size $bytes"

        fsutil file createnew $name $bytes

        $FolderMB = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    } while (
        $FolderMB -lt $SizeMB   
    )
}

