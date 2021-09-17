param (
    [Parameter(Mandatory=$True)]
    [String] $AccessKey = "IXU58OGBOKAHMORADATF",

    [Parameter(Mandatory=$True)]
    [String] $SecretKey = "QSGFCACldj9C2hkY4PCIDTr1wbQoyzlYp3IQtMJ9",

    [Parameter(Mandatory=$True)]
    [String] $EndpointUrl = "http://s3.us-east-2.wasabisys.com",

    [Parameter(Mandatory=$True)]
    [String] $BucketName = "towle-hilt-family",

    [Parameter]
    [ValidateScript({
        if ( -not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "The LocalFolder argument must be an existing folder."
        }
        return $true
    })]
    [System.IO.FileInfo] $Source = "E:\Data",
)

# clean up variables
$Source = $Source -replace ("\\{1}$","")
$ProfileName = $AccessKey.Substring(0,5)
$Region = $EndpointUrl.Split(".")[-3]

# setup environment
Get-AWSCredential -ListProfileDetail | Where-Object {$_.ProfileName -match $ProfileName} | Remove-AWSCredentialProfile -Force
Set-AWSCredential -AccessKey $AccessKey -SecretKey $SecretKey -StoreAs $ProfileName

$Bucket = Get-S3Bucket -EndpointUrl $EndpointUrl -ProfileName $ProfileName -BucketName $BucketName
$Folders = Get-ChildItem -Path $Source -Recurse | Where-Object {$_.PSIsContainer -eq $True}

if ($Bucket -and $Folders) {

    $i=1

    foreach ($Folder in $Folders.FullName) {
        $KeyPrefix = "/backup" + $Folder.Replace($Source,"").Replace("\","/")

        Write-Progress -Activity "Uploading to $BucketName" -Status $KeyPrefix -PercentComplete (($i / $Folders.count) * 100)

        Write-S3Object -EndpointUrl $EndpointUrl -ProfileName $ProfileName -BucketName $Bucket.BucketName -Folder $Folder -KeyPrefix $KeyPrefix

        $i++
    }

}