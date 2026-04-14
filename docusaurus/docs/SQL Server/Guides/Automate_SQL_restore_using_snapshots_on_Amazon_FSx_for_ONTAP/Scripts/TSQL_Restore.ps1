param (
    [Parameter(Mandatory = $true)]
        [string]$FSxID,
        [Parameter(Mandatory = $true)]
        [string]$FSxRegion,
        [Parameter(Mandatory = $true)]
        [string]$serverInstanceName,
        [Parameter(Mandatory = $true)]
        [string]$databaseName,
        [Parameter(Mandatory = $true)]
        [bool]$isClustered = $False,       
        [Parameter(Mandatory = $false)]
        [bool]$transactionRestore = $False,
        [Parameter(Mandatory = $true)]
        [string]$snapshot,
        [Parameter(Mandatory = $false)]
        [string]$tlogbackup_lastfile,
        [Parameter(Mandatory = $false)]
        [string]$transaction_date
)



#Get Mapped Ontap Volumes
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$responseObject = $responseObject -or @{}


# Define and create the log directory if it doesn't exist
$LogFilesPath = "C:\cfn\log"
if (-not (Test-Path -Path $LogFilesPath -PathType Container)) {
New-Item -Path $LogFilesPath -ItemType Directory
}

$includeLogVolumes = [System.Convert]::ToBoolean('false')

try {
#Requires -Module AWS.Tools.SimpleSystemsManagement

$svmOntapUuid = ''
$dblist = @()
if(-not ([string]::IsNullOrEmpty($databaseName))) {
$dblist = $databaseName.Split(",")
$databaseList = ''
$databaseqList = ''
$dblist | ForEach-Object{
   $db = $_
   $dbgroup ="["+$db+"]"
   $dbquote = "'"+$db+"'"
   if ([string]::IsNullOrEmpty($databaseList)){
      $databaseList += $dbgroup
      $databaseqList += $dbquote
      }
    else {
     $databaseList = $databaseList+','+$dbgroup
     $databaseqList = $databaseqList+','+$dbquote 
    }
   }
}

$executableInstance = "$env:COMPUTERNAME"
if ($serverInstanceName -ne 'MSSQLSERVER') {
    $executableInstance = "$env:COMPUTERNAME\$serverInstanceName"
}

if ("TrustAllCertsPolicy" -as [type]) {} else {
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
    ServicePoint srvPoint, X509Certificate certificate,
    WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($connection -eq $null) {
$connection = Test-Connection -ComputerName fsx-aws-certificates.s3.amazonaws.com -Quiet -Count 1
}
if ($connection -eq $False) {
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing\" -Name State -Value 146944 -Force | Out-Null
}
#The solution is expecting that FSx credentials are saved in AWS SSM parameter store to have a safe and encrypted manner of passing credentials
$SsmParameter = (Get-SSMParameter -Name "/tsql/filesystem/$FSxID" -WithDecryption $True).Value | Out-String | ConvertFrom-Json
$FSxUserName = $SsmParameter.fsx.username
$FSxPassword = $SsmParameter.fsx.password
$FSxPasswordSecureString = ConvertTo-SecureString $FSxPassword -AsPlainText -Force
$FSxCredentials = New-Object System.Management.Automation.PSCredential($FSxUserName, $FSxPasswordSecureString)
$FSxCredentialsInBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($FSxUserName + ':' + $FSxPassword))
$FSxHostName = "management.$FSxID.fsx.$FSxRegion.amazonaws.com"

$isprivatesubnet = $connection -eq $False
if (-not $isprivatesubnet) {
$FSxCertificateificateUri = 'https://fsx-aws-Certificates.s3.amazonaws.com/bundle-' + $FSxRegion + '.pem'
$tempCertFile = (New-TemporaryFile).FullName
Invoke-WebRequest -Uri $FSxCertificateificateUri -OutFile $tempCertFile
$Certificate = Import-Certificate -FilePath $tempCertFile -CertStoreLocation Cert:\LocalMachine\Root
$regionCertificate = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -like $Certificate.Subject }
Remove-Item -Path $tempCertFile -Force -ErrorAction SilentlyContinue
}

Function Invoke-ONTAPRequest {
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$ApiQueryFilter = '',

    [Parameter(Mandatory = $false)]
    [string]$ApiQueryFields = '',

    [Parameter(Mandatory = $false)]
    [string]$method = 'GET',

    [Parameter(Mandatory = $false)]
    [hashtable]$body
)


if (-not ([string]::IsNullOrEmpty($ApiQueryFilter))) {

$Params = @{
    "URI"     = 'https://' + $FSxHostName + '/api' + $ApiEndpoint + '?' + $ApiQueryFilter + '&' + $ApiQueryFields
    "Method"  = $method
    "Headers" =@{"Authorization" = "Basic $FSxCredentialsInBase64"}
    "ContentType" = "application/json"
 }
} else {
    $Params = @{
    "URI"     = 'https://' + $FSxHostName + '/api' + $ApiEndpoint
    "Method"  = $method
    "Headers" =@{"Authorization" = "Basic $FSxCredentialsInBase64"}
    "ContentType" = "application/json"
 }   
}
if (-not ([string]::IsNullOrEmpty($body))) {
    $jsonbody = ConvertTo-JSON $body
    $Params.Add("Body", $jsonbody)
}
       $paybod = ConvertTo-JSON $body
        $payload = ConvertTo-JSON $Params -Depth 5


if ($isprivatesubnet -eq $False -and $regionCertificate -ne $null) {
    try {
        return Invoke-RestMethod @Params -Certificate $regionCertificate
    } catch {
        Write-Host "Failed to execute ONTAP REST command: $_"
        throw
    }
} else {
    try {
        return Invoke-RestMethod @Params
    } catch {
        Write-Host "Failed to execute ONTAP REST command: $_"
        throw
    }
}
}

Function Get-VolumeIdsList($sqlqueryresponse) {        
        $sqlJsonResponse = $sqlqueryresponse | convertFrom-Json
        $volumeIds = @()
        foreach ($record in $sqlJsonResponse) {    
            if ($null -ne $record.volumeId) {
                $cleanVolumeId = $record.volumeId.Replace(" ", "").Replace("`r","").Replace("`n","")
                if ($volumeIds -notcontains $cleanVolumeId) {
                    $volumeIds += $cleanVolumeId
                }
            }
            elseif ($null -ne $record.PhysicalFilePath) {
                $path = $record.PhysicalFilePath.Replace("`r","").Replace("`n","")
                $drive = (Get-Item $path).PSDrive.Name
                $volume = Get-Volume -DriveLetter $drive

                [PSCustomObject]@{
                    VolumeName = $volume.FileSystemLabel
                    VolumeId   = $volume.UniqueId
                }
               $volumeIds += $volume.UniqueId
            }
        }
        $volumeIds
    }

Function Get-SerialNumberOfWinVolumes($winvolumes) {
        try {
            $Lunserialnumbers = @()
            $VolumeSerialMapping = @{}
            $BusTypes = @()

            
            $allDisks = Get-Disk | Select SerialNumber, Number, BusType

            foreach ($volumeid in $winvolumes) {
                if ($null -eq $volumeid) {
                    Write-Host "Skipping volume with null volumeid"
                    continue
                }

                $vol = Get-Volume -Path $volumeid | Get-Partition | Where-Object DiskNumber -in $allDisks.Number
                $serialNumber = $allDisks | Where-Object Number -eq $vol.DiskNumber | Select -ExpandProperty SerialNumber
                $BusType = $allDisks | Where-Object Number -eq $vol.DiskNumber | Select -ExpandProperty BusType

                $VolumeSerialMapping[$volumeid] = $serialNumber
                $Lunserialnumbers += $serialNumber
                $BusTypes += $BusType
            }

            $Lunserialnumbers = $Lunserialnumbers | where { -not $_.StartsWith('vol') } | select -Unique
            if ($Lunserialnumbers.count -eq 0 -and $BusTypes.Count -gt 0 -and  $BusTypes -notcontains 'iSCSI') {
                throw "Only iSCSI volumes are supported"
            }

            return @{
                Lunserialnumbers = $Lunserialnumbers | select -Unique
                VolumeSerialMapping = $VolumeSerialMapping
            }
        }
        catch {
            throw "An error occurred while getting the serial numbers of Windows volumes: $_"
        }
    }

Function Get-LunFromSerialNumber($SerialNumbers, $VolumeSerialMapping) {
        Write-Host "Get ONTAP lun name from serial numbers for: $VolumeSerialMapping"

        $QueryFilter = ''
        foreach ($SerialNumber in $SerialNumbers) {
            if ($SerialNumber -ne '') {
                $QueryFilter += [System.Web.HttpUtility]::UrlEncode($SerialNumber) + '|'
            }
        }
        
        $QueryFilter = $QueryFilter.TrimEnd('|')

        $Params = @{
            "ApiEndPoint" = "/storage/luns"
            "method" = "GET"
        }

        [string[]]$LunNames = @()
        $VolumeLunMapping = @{}
        $LunNameUUIDMap = @{}
        if ($QueryFilter -ne '') {
            $Params += @{
                "ApiQueryFilter" = "serial_number=$QueryFilter"
                "ApiQueryFields" = "fields=uuid,name,serial_number,lun_maps.igroup,svm"
                }
            $Response = Invoke-ONTAPRequest @Params
            $LunRecords = $Response.records

            Write-Host "Lun Records  Mapping: $($LunRecords | ConvertTo-Json)"

            foreach ($record in $LunRecords) {
                $LunNames += $record.name
                foreach ($volumeId in $VolumeSerialMapping.Keys) {
                    if ($VolumeSerialMapping[$volumeId] -eq $record.serial_number) {
                        $lunName = $record.name -replace '^\/vol\/(.*?)\/.*$', '$1'
                        $VolumeLunMapping[$volumeId] = $lunName
                        $LunNameUUIDMap[$record.uuid] = @{
                            "Path" = $record.name
                            "igroupUUID" = $record.lun_maps.igroup.uuid
                            "igroupName" = $record.lun_maps.igroup.name
                            "svm" = $record.svm.name
                        }
                    }
                }
            }
        }
 
        return @{
            LunNames = $LunNames
            VolumeLunMapping = $VolumeLunMapping
            LunNameUUIDMap = $LunNameUUIDMap
        }
    }

Function Get-VolumeIdFromName($Names, $volumeLunMapping) {
        Write-Host "Get Volume Id from name: $Names"

        $QueryFilter = ''
        foreach ($Name in $Names) {
            if ($Name -ne '') {
                $QueryFilter += [System.Web.HttpUtility]::UrlEncode($Name) + '|'
            }
        }
        $QueryFilter = $QueryFilter.TrimEnd('|')


        $Params = @{
            "ApiEndPoint" = "/storage/volumes"
            "method" = "GET"
        }

        if ($QueryFilter -ne '') {
            $Params += @{"ApiQueryFilter" = "name=$QueryFilter"}
        
            $Response = Invoke-ONTAPRequest @Params
            $VolumeNameMapping = @{}
            foreach ($record in $Response.records) {
                foreach ($volumeId in $volumeLunMapping.Keys) {
                    if ($volumeLunMapping[$volumeId] -eq $record.name) {
                        $VolumeNameMapping[$volumeId] = @{
                            "uuid" = $record.uuid
                            "name" = $record.name
                        }
                    }
                }
            }
        }
        

        return @{
            Response = $Response
            volumeNameMapping = $VolumeNameMapping
        }
    }

Function Get-ONTAPJobStatus($jobUUID) {
        $Params = @{
            "ApiEndPoint" = "/cluster/jobs/$jobUUID"
            "method" = "GET"
        }
        return Invoke-ONTAPRequest @Params
    }

Function Wait-ForONTAPJob($jobUUID, $timeoutSeconds, $operationLabel) {
        $elapsed = 0
        $pollInterval = 5
        while ($elapsed -lt $timeoutSeconds) {
            $jobStatus = Get-ONTAPJobStatus $jobUUID
            Write-Host "Job $jobUUID ($operationLabel) state: $($jobStatus.state)"
            if ($jobStatus.state -eq 'success') {
                return $jobStatus
            }
            if ($jobStatus.state -eq 'failure') {
                throw "ONTAP job $jobUUID ($operationLabel) failed: $($jobStatus.message)"
            }
            Start-Sleep -Seconds $pollInterval
            $elapsed += $pollInterval
        }
        throw "ONTAP job $jobUUID ($operationLabel) did not complete within $timeoutSeconds seconds"
    }

Function Restore-ONTAPSnapshot($volumeUUID,$volumeName,$snapshot,$action) {
       
        if ($action -eq 'CREATE') {
            Write-Host "Creating pre-restore safety snapshot $snapshot on volume $volumeName"
            $Params = @{
                "ApiEndPoint" = "/storage/volumes/$volumeUUID/snapshots"
                "method" = "POST"
                "ApiQueryFields" = "return_records=true"
                "body" = @{
                    "name" = "$snapshot"
                    "comment" = "TSQL backup pre-restore snapshot"
                }
            }
        }
        else {
            Write-Host "Restoring snapshot $snapshot on volume $volumeName" 
            $Params = @{
                "ApiEndPoint" = "/storage/volumes/$volumeUUID"
                "method" = "PATCH"
                "body" = @{
                    "restore_to.snapshot.name" = "$snapshot"
                }
            }
        }
            
        Write-Host $Params
        $Response = Invoke-ONTAPRequest @Params

        if ($null -eq $Response) {
            throw "ONTAP API returned null response for $action on volume $volumeName"
        }

        if ($Response.job -ne $null) {
            $timeoutSeconds = 120
            Write-Host "$action returned async job $($Response.job.uuid) - polling for completion (timeout: ${timeoutSeconds}s)"
            $jobResult = Wait-ForONTAPJob $Response.job.uuid $timeoutSeconds "$action snapshot on $volumeName"
            Write-Host "$action job completed successfully for volume $volumeName"
        }

        Write-Host $Response
        return($Response)
    }

Function ONTAP-LUNMapping($lunUUID,$igroupUUID,$lunPath,$igroupName,$svm,$action) {
 
        $MapParams = @{
            "ApiEndPoint" = "/protocols/san/lun-maps"
            "method" = "POST"
            "body" = @{
                "igroup.name" = "$igroupName"
                "lun.name" = "$lunPath"
                "svm.name" = "$svm"
            }
        }

        $UnmapParams = @{
            "ApiEndPoint" = "/protocols/san/lun-maps/$lunUUID/$igroupUUID"
            "method" = "DELETE"
            "body" = @{
                "igroup.name" = "$igroupName"
                "lun.name" = "$lunPath"
            }
        }

        if($action -eq 'map') {
            Write-Host "Mapping LUN $lunPath to igroup $igroupName"
            try {
                $Response = Invoke-ONTAPRequest @MapParams
                Write-Host $Response
                return($Response)
            } catch {
                throw "Failed to map LUN $lunPath to igroup $igroupName : $_"
            }
         }   
         elseif($action -eq 'unmap') {
            Write-Host "Unmapping LUN $lunPath from igroup $igroupName"
            try {
                $Response = Invoke-ONTAPRequest @UnmapParams
                Write-Host $Response
                return($Response)
            } catch {
                throw "Failed to unmap LUN $lunPath from igroup $igroupName : $_"
            }
         } 

    }    

Function Get-VolumeIdFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$absolutePath
    )
    $pattern = '{(.+)}'
    if ($absolutePath -match $pattern) {
         $volumeID= $matches[1]
         Write-Host $volumeID
    }
    else {
        throw "Could not find VolumeID for $absolutePath"
    }
    return $volumeID
}

Function Wait-ForSQLClusterResourceOnline {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SQLresource,
        [Parameter(Mandatory = $false)]
        [int]$timeoutSeconds = 120,
        [Parameter(Mandatory = $false)]
        [int]$pollIntervalSeconds = 5
    )
    $elapsed = 0
    $moveAttempted = $false
    $thisNode = $env:COMPUTERNAME
    Write-Host "Waiting for SQL cluster resource '$SQLresource' to be Online on this node ($thisNode)..."

    while ($elapsed -lt $timeoutSeconds) {
        try {
            $resource = Get-ClusterResource -Name $SQLresource -ErrorAction Stop
            $ownerNode = $resource.OwnerNode.Name
            $state = $resource.State
            $groupName = $resource.OwnerGroup.Name

            Write-Host "SQL resource '$SQLresource' state: $state, owner: $ownerNode (elapsed: ${elapsed}s)"

            if ($state -eq 'Online' -and $ownerNode -eq $thisNode) {
                Write-Host "SQL resource '$SQLresource' is Online on this node ($thisNode)"
                return $true
            }

            if ($ownerNode -ne $thisNode -and -not $moveAttempted) {
                Write-Host "SQL FCI role '$groupName' is owned by '$ownerNode', moving back to this node ($thisNode)..."
                try {
                    Move-ClusterGroup -Name $groupName -Node $thisNode -ErrorAction Stop | Out-Null
                    Write-Host "Move-ClusterGroup issued for '$groupName' to node '$thisNode'. Waiting for it to come Online..."
                    $moveAttempted = $true
                } catch {
                    throw ("Failed to move SQL FCI role '$groupName' back to this node ($thisNode): $_. " +
                           "Move the role manually and re-run the script.")
                }
            }
        } catch [Microsoft.FailoverClusters.PowerShell.ClusterCmdletException] {
            Write-Host "Cluster resource query failed (may be transitioning): $_"
        }
        Start-Sleep -Seconds $pollIntervalSeconds
        $elapsed += $pollIntervalSeconds
    }
    throw "SQL resource '$SQLresource' did not come Online on this node ($thisNode) within $timeoutSeconds seconds. Check cluster status manually."
}


Function Remove-SQLDependency($instanceName,$DBName,$volPaths) {
    try {
        

        if ($volPaths.count -ne 0) {
            $query = "set nocount on; SELECT DB_NAME(dbid) as DBName, COUNT(dbid) as NumberOfConnections FROM sys.sysprocesses WHERE DB_NAME(dbid) = '$DBName' GROUP BY dbid FOR JSON PATH"

            $sqlres = sqlcmd -Q $query -y 0

            if (-not [string]::IsNullOrEmpty($sqlres)) {
                Write-Information "$logPrefix Database $dbname is in use"
                $responseObject['error'] = 'SQLServerError: Database $dbname is in use'
                return $responseObject | ConvertTo-Json -Depth 5
            }

            $clusterServiceStatus = (Get-Service -Name clussvc -ErrorAction SilentlyContinue).Status
            if ($instanceName -eq 'MSSQLSERVER') {
                $resourceType  = 'SQL Server'
            } else {
                $resourceType  = 'SQL Server (' + $instanceName + ')'
            }


            $windowsVolumeIds = $volPaths | ForEach-Object {        
                Get-VolumeIdFromPath -absolutePath $_                
            } | Sort-Object -Unique

            Write-Information "$logPrefix Windows Volume Ids: $windowsVolumeIds"
            if ($clusterServiceStatus -eq 'Running') {
                $sqlgroup = Get-ClusterResource | Where-Object Name -eq $resourceType
                $sqlserver = Get-WmiObject -namespace root\MSCluster MSCluster_Resource -filter "Name='$sqlgroup'"
                $resourcegroup = $sqlserver.GetRelated() | Where Type -eq 'Physical Disk'
                Write-Host "Resource Group: $resourcegroup"

                Write-Host "Resource type: $resourceType  Server resource:$sqlserver"
                $clusterdisksToRemove = @()
                foreach ($resource in $resourcegroup) {
                    $disks = $resource.GetRelated("MSCluster_Disk")
                    foreach ($disk in $disks) {
                        $diskpart = $disk.GetRelated("MSCluster_DiskPartition")
                        $clusterdisk = ($resource.name).replace('\\r\\n','')
                        $diskdrive = $diskpart.path
                        $disklabel = $diskpart.volumelabel
                        $diskvolume = $diskpart.VolumeGuid
                        if ($windowsVolumeIds -contains $diskpart.VolumeGuid) {
                            $clusterdisksToRemove += $clusterdisk
                        }
                    }
                }

                Write-Information "$logPrefix Cluster Disks to remove $clusterdisksToRemove"
                if ($clusterdisksToRemove.count -ne 0) {
                    $clusterdisksToRemove | ForEach-Object {
                        $diskToRemove = $_
                        $diskToRemove = $diskToRemove.ToString()
                        write-Information "$logPrefix Removing disk $diskToRemove"
                        $null = (Remove-ClusterResourceDependency -Resource $resourceType -Provider $diskToRemove)
                    }
                return($clusterdisksToRemove)     
                }   
            }
        }

    }  catch {
        Write-Host "$logPrefix An error occurred while removing SQL dependency: $_.Exception.Message"
        $responseObject['error'] = 'SQLServerError: $_.Exception.Message'
        return $responseObject | ConvertTo-Json -Depth 5
    }
}   

Function Get-AvailableTLogBackups{
    param(
        [Parameter(Mandatory = $true)]
        [string]$executableInstance,
        [Parameter(Mandatory = $true)]
        [string]$databaseName,
        [Parameter(Mandatory = $true)]
        [string]$snapshot

    )
    $Dblisterrlog = "C:\cfn\log\dblist_err.log"

    $sqlqueryfortlogbackuplist = @"
    SET NOCOUNT ON;
    DECLARE @JSONData nvarchar(max)
    SET @JSONData = (SELECT 
        bs.database_name,
		bs.backup_finish_date,
        bm.physical_device_name
    FROM 
        msdb.dbo.backupset bs
    INNER JOIN 
        msdb.dbo.backupmediafamily bm ON bs.media_set_id = bm.media_set_id
    WHERE 
        bm.physical_device_name LIKE  '%$snapshot%' AND bs.database_name = '$databaseName'
    FOR JSON PATH)
    SELECT @JSONData;
"@


try{
$sqlqueryresponse =  (sqlcmd -S $executableInstance -Q $sqlqueryfortlogbackuplist -y 0 -r1 2> $Dblisterrlog)
 if (Get-Content $Dblisterrlog) { throw }

$sqlJsonResponse = $sqlqueryresponse | convertFrom-Json
Write-Host "Backup records found: $($sqlJsonResponse | ConvertTo-Json -Compress)"
$sortedBackups = @($sqlJsonResponse) | Sort-Object { [datetime]::Parse($_.backup_finish_date) }
$backup_finishtime = [datetime]::Parse($sortedBackups[0].backup_finish_date).ToString("yyyy-MM-dd HH:mm:ss")
Write-Host "Using earliest backup finish time as baseline: $backup_finishtime"

    }
    catch {
       Write-Host "Failed to get backup details from msdb: $($_.Exception.Message )"
       $Errordetails = Get-Content $Dblisterrlog
       Write-Host $Errordetails
       throw "Cannot determine backup finish time for snapshot $snapshot from msdb: $_"
    }
 
 
    $tlogbackupquery = @"
    SET NOCOUNT ON;
    DECLARE @JSONData nvarchar(max)
    DECLARE @BackupDate DATETIME = '$backup_finishtime';
    SET @JSONData = (

SELECT 
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
	bs.type,
    bs.recovery_model,
    bm.physical_device_name
FROM 
    msdb.dbo.backupset bs
INNER JOIN 
    msdb.dbo.backupmediafamily bm ON bs.media_set_id = bm.media_set_id
WHERE 
    bs.backup_start_date > @BackupDate  AND bs.type = 'L'
    FOR JSON PATH)
    SELECT @JSONData;
"@

try{
$tbkpqueryresponse =  (sqlcmd -S $executableInstance -Q $tlogbackupquery -y 0 -r1 2> $Dblisterrlog)
 if (Get-Content $Dblisterrlog) { throw }
 $tlogJsonResponse = $tbkpqueryresponse | convertFrom-Json

$tlogbackups = @()
$sortedRecords = $tlogJsonResponse | Sort-Object {[datetime]::Parse($_.backup_finish_date)}
$tlogbackups = $sortedRecords | ForEach-Object { $_.physical_device_name }


Write-Host "$tlogbackups"
return $tlogbackups
    }
    catch {
       Write-Host "Failed to get transaction backup list from msdb: $($_.Exception.Message )!"
       $Errordetails = Get-Content $Dblisterrlog
       Write-Host $Errordetails
       throw "Cannot retrieve transaction log backup list: $_"
    } 


}
$instanceRespones = @{}

try {

if(-not ([string]::IsNullOrEmpty($databaseName))) {
    $sqlqueryfordatabaseandvolumelist = @"
    IF EXISTS (    SELECT 1  FROM sys.databases WHERE name IN ($databaseqList)  AND state_desc = 'ONLINE')
    BEGIN
                SET NOCOUNT ON;
                DECLARE @JSONData nvarchar(max)
                SET @JSONData = (SELECT DISTINCT 
                    DB_NAME(mf.database_id) AS DatabaseName,
                    vs.logical_volume_name as VolumeName,
                    vs.volume_id as VolumeId
                FROM 
                    sys.master_files AS mf
                INNER JOIN 
                    sys.databases d ON mf.database_id = d.database_id
                CROSS APPLY 
                    sys.dm_os_volume_stats(mf.database_id, mf.[file_id]) AS vs
                WHERE 
                    vs.volume_mount_point collate SQL_Latin1_General_CP1_CI_AS != 'C:\'
                    AND REVERSE(SUBSTRING(REVERSE(mf.physical_name), 1, 3)) in ('mdf','ndf','ldf')
                    AND d.name collate SQL_Latin1_General_CP1_CI_AS IN ($databaseqList)
                FOR JSON PATH)
                SELECT @JSONData;
    END
    ELSE
    BEGIN
            SET NOCOUNT ON;

            DECLARE @JSON_Data nvarchar(max);

            SET @JSON_Data = (
                SELECT DISTINCT
                    DB_NAME(mf.database_id) AS DatabaseName,
                    LEFT(mf.physical_name, 3) AS DriveLetter,
                    mf.physical_name AS PhysicalFilePath
                FROM sys.master_files mf
                INNER JOIN sys.databases d
                    ON mf.database_id = d.database_id
                WHERE
                    d.name COLLATE SQL_Latin1_General_CP1_CI_AS IN ($databaseqList)
                    AND RIGHT(mf.physical_name, 3) IN ('mdf','ndf','ldf')
                    AND LEFT(mf.physical_name, 3) <> 'C:\'
                FOR JSON PATH
            );

            SELECT @JSON_Data;
    END

"@
} else {
    Write-Host "databaseName needs to be provided for restore. Only single database restore is supported!"
    exit 1
}
    $MappedVolumesErrorFile = "C:\cfn\log\mapped_volumes_err_$serverInstanceName_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().toString()).log"
    $Dblisterrlog = "C:\cfn\log\dblist_err.log"
    try {
    $sqlqueryresponse =  (sqlcmd -S $executableInstance -Q $sqlqueryfordatabaseandvolumelist -y 0 -r1 2> $Dblisterrlog) 
    if (Get-Content $Dblisterrlog) { throw }
    }
    catch {
       Write-Host "Failed to get mapping for disks: $_. Check if database is in running state!"
       Write-Host $sqlqueryresponse
       throw "Cannot proceed with restore - failed to get disk mappings: $_"
    }

    Write-Host "Mapped disks:$sqlqueryresponse"
    $volumeIds = Get-VolumeIdsList $sqlqueryresponse


    $result = Get-SerialNumberOfWinVolumes $volumeIds
    $SerialNumbers = $result.Lunserialnumbers

    $lunResult = Get-LunFromSerialNumber $SerialNumbers $result.VolumeSerialMapping

    $VolumeNames = $lunResult.LunNames
    #Write-Host "LUNs: $($VolumeNames |ConvertTo-Json)" 
    $volumeLunMapping = $lunResult.VolumeLunMapping
    
    if (!($VolumeNames.count -gt 0)) {
        throw "Couldn't get associated Ontap LUN volume names"
    }

    $volumeResult = Get-VolumeIdFromName $VolumeNames $volumeLunMapping
    $volumes = $volumeResult.Response
    $volumeNameMapping = $volumeResult.volumeNameMapping
    $LunUUIDMap = $lunResult.LunNameUUIDMap
   # Write-Host "Volume Ids: $($volumes | ConvertTo-Json)"
   # Write-Host "LUN Ids: $($LunUUIDMap | ConvertTo-Json)"

      $sqlConn = New-Object System.Data.SQLClient.SQLConnection
      # Open SQL Server connection to master
      $sqlConn.ConnectionString = "server='" + $executableInstance +"';database='master';Integrated Security=True;"
      $sqlConn.Open()
      $Command = New-Object System.Data.SQLClient.SQLCommand
      $Command.Connection = $sqlConn

    #Offline the database(s)
    try {
        Write-Host "Putting database $databaseName offline for restore"

        $offlinedatabases= "ALTER DATABASE ["+$databaseName+"] SET OFFLINE WITH ROLLBACK IMMEDIATE"
        $Command.CommandText = $offlinedatabases
        $Command.ExecuteNonQuery() | Out-Null
        Write-Host "Database $databaseName is now offline"
        Write-Host $offlinedatabases
    } catch {
       Write-Host "Failed to offline database! Retry after sometime"
       exit 1 
    }



    #Remove disks from Windows cluster disks if clustered
    if ($isClustered -eq $True) {
        Write-Host "Removing database $databaseName from cluster disks"
        $sqlclusterdisks = Remove-SQLDependency $serverinstanceName $databaseName $volumeIds
        Write-Host "Disks for database $databaseName is now removed from SQL server dependency"
        Write-Host $sqlclusterdisks
        }
    
    #Unmap LUNs from the cluster
    foreach ($Lun in $LunUUIDMap.GetEnumerator()) {
        $lunUUID = $($Lun.Key)
        $lunPath = $($Lun.Value).Path
        $igroupName = $($Lun.Value).igroupName
        $igroupUUID = $($Lun.Value).igroupUUID
        $svmname = $($Lun.Value).svm
        try {
            $unmapResult = ONTAP-LUNMapping $lunUUID $igroupUUID $lunPath $igroupName $svmname 'unmap'
            Write-Host "Unmapped LUN $lunPath ($lunUUID) from igroup $igroupName ($igroupUUID)"
        } catch {
            Write-Host "Failed to unmap LUN $lunPath. Aborting restore - LUNs must be unmapped before volume restore."
            throw "LUN unmap failed for $lunPath : $_"
        }
    }   

    #Create pre-restore safety snapshot
    $prerestore_timestamp = (Get-Date -Format "yyyyMMddHHmmss")
    $prerestore_snapshot = "prerestore_" + $prerestore_timestamp
    foreach ($record in $volumes.records) {
        try {
            Restore-ONTAPSnapshot $record.uuid $record.name $prerestore_snapshot 'CREATE'
        } catch {
            Write-Warning "Failed to create pre-restore safety snapshot on $($record.name): $_. Proceeding with restore."
        }
    }

    #Restore snapshot for all the volumes
    $restoreFailed = $false
     foreach ($record in $volumes.records) {
           $volumeUUID = $record.uuid
           $volumeName = $record.name
           Write-Host "Restoring snapshot for $volumeName ($volumeUUID)"
           try {
                $snapshotResult = Restore-ONTAPSnapshot $volumeUUID $volumeName $snapshot 'RESTORE'
            } catch {
                Write-Host "Snapshot restore failed for volume $volumeName. Error: $_"
                Write-Host "Pre-restore safety snapshot '$prerestore_snapshot' is available for manual recovery."
                $restoreFailed = $true
                break
            }
        }

    Start-Sleep -Seconds 2

    #Map back LUNs — must happen regardless of restore success so disks are accessible
    foreach ($Lun in $LunUUIDMap.GetEnumerator()) {
        $lunUUID = $($Lun.Key)
        $lunPath = $($Lun.Value).Path
        $igroupName = $($Lun.Value).igroupName
        $igroupUUID = $($Lun.Value).igroupUUID
        $svmname = $($Lun.Value).svm
        try {
            $mapResult = ONTAP-LUNMapping $lunUUID $igroupUUID $lunPath $igroupName $svmname 'map'
            Write-Host "Mapped LUN $lunPath ($lunUUID) to igroup $igroupName ($igroupUUID)"
        } catch {
            Write-Host "CRITICAL: Failed to re-map LUN $lunPath to igroup $igroupName. Manual intervention required. Error: $_"
        }
    }   
    Start-Sleep -Seconds 2

    if ($restoreFailed) {
        throw "Snapshot restore failed. LUNs have been re-mapped. Pre-restore snapshot '$prerestore_snapshot' available for recovery."
    }

    #Rescan disks
    echo "RESCAN" | diskpart 
    
    #Add back disk to cluster and SQL Server dependency
    if ($isClustered -eq $True) {
        Write-Host "Adding cluster disks of database $databaseName to SQL server:$sqlclusterdisks"
        if ($serverInstanceName -eq 'MSSQLSERVER') {
                $SQLresourceName  = 'SQL Server'
        } else {
                $SQLresourceName  = 'SQL Server (' + $serverInstanceName + ')'
         }
        Wait-ForSQLClusterResourceOnline -SQLresource $SQLresourceName -timeoutSeconds 120
        $sqlclusterdisks | ForEach-Object {
            $diskToAdd = $_
            $diskToAdd = $diskToAdd.ToString()
            write-Host "Starting cluster disk $diskToAdd"
            Start-ClusterResource -Name $diskToAdd
            write-Host "Adding back disk $diskToAdd to $SQLresourceName"
            Add-ClusterResourceDependency -Resource $SQLresourceName -Provider $diskToAdd
        }
        Write-Host "Disks for database $databaseName is now added to SQL server dependency"

        Wait-ForSQLClusterResourceOnline -SQLresource $SQLresourceName -timeoutSeconds 120
     } else {
        Start-Sleep -Seconds 5
     }

     
         
    #Restore metadata backup on SQL server

    $metabackup = $snapshot+'.bkm'
    if ($transactionRestore -eq $True) {
            Write-Host "Restoring metadatabackup with NORECOVERY for database $databaseName"
            Sleep 5
            $sqlbackupquery = "RESTORE DATABASE  "+$databaseList+" FROM DISK = '"+$metabackup+"' WITH METADATA_ONLY, REPLACE, NORECOVERY;"
            Write-Host $sqlbackupquery
            $Command.CommandText = $sqlbackupquery
            try {
                $sqlbackupresponse = $Command.ExecuteNonQuery();
                Write-Host "Successfully restored database $databaseName to base metadata backup - $metabackup"
                Sleep 4
            } catch {
                Write-Host "Failed to restore metadata backup database(s) $databaseName for backup $metabackup!"
                exit 1
            }
        
            Write-Host "Restoring transaction log backup for database $databaseName" 
            $tlogs_to_restore = Get-AvailableTLogBackups $executableInstance $databaseName $snapshot 
            if (-not [string]::IsNullOrEmpty($tlogbackup_lastfile)) {
                $matchIndex = -1
                for ($i = 0; $i -lt $tlogs_to_restore.count; $i++) {
                    if ([System.IO.Path]::GetFileName($tlogs_to_restore[$i]) -eq $tlogbackup_lastfile) {
                        $matchIndex = $i
                        break
                    }
                }
                if ($matchIndex -eq -1) {
                    throw "Specified last transaction log backup '$tlogbackup_lastfile' was not found in the available backup list. Verify the filename and retry."
                }
                Write-Host "Truncating tlog list at '$tlogbackup_lastfile' (index $matchIndex of $($tlogs_to_restore.count - 1))"
                $tlogs_to_restore = $tlogs_to_restore[0..$matchIndex]
            } 
            

            if ($null -eq $tlogs_to_restore -or $tlogs_to_restore.count -eq 0) {
                Write-Host "WARNING: No transaction log backups found after snapshot $snapshot. Recovering database without transaction logs."
                $recoverQuery = "RESTORE DATABASE $databaseName WITH RECOVERY;"
                $Command.CommandText = $recoverQuery
                try {
                    $Command.ExecuteNonQuery() | Out-Null
                    Write-Host "Database $databaseName recovered without transaction logs."
                } catch {
                    throw "No transaction log backups found and failed to recover database $databaseName from NORECOVERY state: $_"
                }
            }
            else {
            $totalRecords = $tlogs_to_restore.count
            $counter = 0
            $tlogs_to_restore | ForEach-Object {
                $tlog = $_
                $counter++
                Write-Host "Restoring transaction log backup $counter of $totalRecords"

                if (($counter -eq $totalRecords) -Or ((-not [string]::IsNullOrEmpty($tlogbackup_lastfile)) -And ($tlog -match $tlogbackup_lastfile))) {
                    if([string]::IsNullOrEmpty($transaction_date)){
                        $sqlbackupquery = "RESTORE LOG "+$databaseName+" FROM DISK = '"+$tlog+"' WITH FILE = 1,  NOUNLOAD,  STATS = 5, RECOVERY;"
                    } else {
                        Write-Host "Recovering point-in-time to provided transaction timestamp $transaction_date fromm $tlog"
                        $sqlbackupquery = "RESTORE LOG "+$databaseName+" FROM DISK = '"+$tlog+"' WITH FILE = 1,  NOUNLOAD,  STATS = 5, STOPAT = N'$transaction_date';"
                    }
                    }
                else {
                $sqlbackupquery = "RESTORE LOG "+$databaseName+" FROM DISK = '"+$tlog+"' WITH FILE = 1,  NOUNLOAD,  STATS = 5, NORECOVERY;"
                }
                Write-Host $sqlbackupquery
                $Command.CommandText = $sqlbackupquery
                try {
                    $sqlbackupresponse = $Command.ExecuteNonQuery();
                    Sleep 2
                    Write-Host "Successfully restored transaction log backup - $tlog"
                } catch {
                      Write-Host "Failed to restore transaction log backup $tlog on database $databaseName!"
                      exit 1
                    }                    
                }
            }

            }
       
    else {
    $sqlbackupquery = "RESTORE DATABASE  "+$databaseList+" FROM DISK = '"+$metabackup+"' WITH REPLACE,METADATA_ONLY;"

    Write-Host $sqlbackupquery
    $Command.CommandText = $sqlbackupquery
    try {
        $sqlbackupresponse = $Command.ExecuteNonQuery();
        Write-Host "Successfully restored database - $databaseName"
        } catch {
          Write-Host "Failed to restore metadata backup database(s) $databaseName for snapshot $snapshot!"

          if ($sqlConn.State -eq [System.Data.ConnectionState]::Open) {
              $sqlConn.Close()
          }
          $sqlConn.Dispose()
          $Command.Dispose()
          throw "Metadata restore failed for $databaseName. Database is offline and needs manual recovery."
        }
    }
    #Online the database
    try {
        Write-Host "Putting database $databaseName online after restore"

        $onlinedatabases= "ALTER DATABASE ["+$databaseName+"] SET ONLINE"
        $Command.CommandText = $onlinedatabases
        $Command.ExecuteNonQuery() | Out-Null
        Write-Host "Database $databaseName is now online"
        Write-Host $onlinedatabases
    } catch {
       Write-Host "Failed to online database! Retry after sometime"
       exit 1 
    }

    if ($sqlConn.State -eq [System.Data.ConnectionState]::Open) {
        $sqlConn.Close()
    }
    $sqlConn.Dispose()
    $Command.Dispose()


    $responseObject = @{
        volumes = $processedRecords
    }
    $instanceRespones[$serverInstanceName] = $responseObject
} catch {
    Write-Information "An error occurred while processing the records: $_.Exception.Message"
    $instanceRespones[$serverInstanceName] = "error: $_"
}


return 
} catch {
Write-Host "Failed to execute: $_"
return $_.Exception.Message
}