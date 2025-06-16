param (
    [Parameter(Mandatory = $true)]
        [string]$FSxID,
        [Parameter(Mandatory = $true)]
        [string]$FSxRegion,
        [Parameter(Mandatory = $true)]
        [string]$serverInstanceName,
        [Parameter(Mandatory = $false)]
        [string]$databaseName,
        [Parameter(Mandatory = $false)]
        [string]$groupName = "DatabaseGroup",
        [Parameter(Mandatory = $false)]
        [int]$snapshot_timeout = 30
)



#Get Mapped Ontap Volumes
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$responseObject = $responseObject -or @{}


Import-Module -Name SQLPS
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
    } catch { Write-Host "Failed to execute ONTAP REST command $_"}
} else {
    return Invoke-RestMethod @Params
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
        }
        $volumeIds
    }

Function Get-SerialNumberOfWinVolumes($winvolumes) {
        try {
            $Lunserialnumbers = @()
            $VolumeSerialMapping = @{}
            $BusTypes = @()

            Write-output "win volumes: $($winvolumes | ConvertTo-Json)"
            $allDisks = Get-Disk | Select SerialNumber, Number, BusType

            foreach ($volumeid in $winvolumes) {
                if ($null -eq $volumeid) {
                    Write-output "Skipping volume with null volumeid"
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
        Write-output "Get ONTAP lun name from serial numbers for: $VolumeSerialMapping"

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
        if ($QueryFilter -ne '') {
            $Params += @{"ApiQueryFilter" = "serial_number=$QueryFilter"}
        
            $Response = Invoke-ONTAPRequest @Params
            $LunRecords = $Response.records

            Write-output "Lun Records  Mapping: $($LunRecords | ConvertTo-Json)"

            foreach ($record in $LunRecords) {
                $LunNames += $record.name
                foreach ($volumeId in $VolumeSerialMapping.Keys) {
                    if ($VolumeSerialMapping[$volumeId] -eq $record.serial_number) {
                        $lunName = $record.name -replace '^\/vol\/(.*?)\/.*$', '$1'
                        $VolumeLunMapping[$volumeId] = $lunName
                    }
                }
            }
        }
 
        return @{
            LunNames = $LunNames
            VolumeLunMapping = $VolumeLunMapping
        }
    }

Function Get-VolumeIdFromName($Names, $volumeLunMapping) {
        Write-output "Get Volume Id from name: $Names"

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

Function Suspend-DatabasesForSnapshot {
        param (
        [Parameter(Mandatory = $true)]
        [string]$BackupType,
        [Parameter(Mandatory = $false)]
        [string]$databaseList,
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Conn,
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SQLCommand]$cmdsession,
        [Parameter(Mandatory = $true)]
        [string]$action,
        [Parameter(Mandatory = $false)]
        [int]$maxRetries = 5
                 )

       $maxRetries = 5
     
        
        if($action -eq 'suspend') {
            if($BackupType -eq 'DATABASE') {                        
                $sqlsuspend = "ALTER DATABASE $databaseList SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON;"
            } 
            if($BackupType -eq 'GROUP') {
                $sqlsuspend = "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON (GROUP =($databaseList));"
            }
            if($BackupType -eq 'SERVER') {
                $sqlsuspend = "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON;"
            } 
            $cmdsession.CommandText = $sqlsuspend
            $attempt = 1
            $success = $False
            while(-not($success) -and ($attempt -le $maxRetries)) {
            try {
            $suspenddatabases = $cmdsession.ExecuteNonQuery();
            $success = $True
            } catch {
                 $attempt++
                 Write-Host "Failed to suspend database(s) $databaseList"
                 Write-Host $Error[0].Exception.InnerException.message
                 Start-Sleep -Seconds 10
                 if($attempt -eq 5) {
                     Write-Host "Failed to suspend database(s) $databaseList after $maxRetries attempts. Aborting!"
                     Write-Host "Resuming all databases in case of partial suspension with more than one database"
                     if($BackupType -eq 'GROUP') {
                         $sqlresume = "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF (GROUP =($databaseList));"
                        } 
                     if($BackupType -eq 'SERVER'){
                         $sqlresume = "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF;"
                        }

                     try {
                        $cmdsession.CommandText = $sqlresume   
                        $resumedatabases = $cmdsession.ExecuteNonQuery(); 
                        } catch {
                        Write-Host "Failed to resume databases."
                        Write-Host $Error[0].Exception.InnerException.message
                        }
                     if ($Conn.State -eq [System.Data.ConnectionState]::Open) {
                        $Conn.Close()
                     }
                    # Dispose of the connection and command objects
                    $Conn.Dispose()
                    $cmdsession.Dispose()
                    throw 
                }
              } 
            }

        }else {
            if($BackupType -eq 'DATABASE') {                        
                $sqlresume = "ALTER DATABASE [$databaseName] SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF;"
            } 
            if($BackupType -eq 'GROUP') {
                $sqlresume = "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF (GROUP =($databaseList));"
            } 
            if($BackupType -eq 'SERVER'){
                $sqlresume = "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF;"
            }  
            $cmdsession.CommandText = $sqlresume   
            $resumedatabases = $cmdsession.ExecuteNonQuery();            
        }
            

         }

Function Create-ONTAPSnapshot($volumeUUID,$volumeName,$snapshot,$timeout) {
        Write-Host "Creating snapshot $snapshot on the volume $volumeName "
  
        

        $Params = @{
            "ApiEndPoint" = "/storage/volumes/$volumeUUID/snapshots"
            "method" = "POST"
            "ApiQueryFilter" = "return_timeout=$timeout"
            "ApiQueryFields" = "return_records=true"
            "body" = @{
                "name" = "$snapshot"
                "comment" = "TSQL backup snapshot"
            }
        }

            
            Write-output $Params
            $Response = Invoke-ONTAPRequest @Params
            Write-output $Response
            return($Response)

    }

$instanceRespones = @{}

try {

if(-not ([string]::IsNullOrEmpty($databaseName))) {
    $sqlqueryfordatabaseandvolumelist = @"
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
"@
} else {
    $sqlqueryfordatabaseandvolumelist = @"
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
                FOR JSON PATH)
                SELECT @JSONData;
"@

}
    $MappedVolumesErrorFile = "C:\cfn\log\mapped_volumes_err_$serverInstanceName_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().toString()).log"
    $sqlqueryresponse =  sqlcmd -S $executableInstance -Q $sqlqueryfordatabaseandvolumelist -y 0 -r1 2>&1

    if ($LASTEXITCODE -ne 0) {
        $sqlqueryresponse | Out-File -FilePath $MappedVolumesErrorFile
        throw $sqlqueryresponse
    }


    $volumeIds = Get-VolumeIdsList $sqlqueryresponse


    $result = Get-SerialNumberOfWinVolumes $volumeIds
    $SerialNumbers = $result.Lunserialnumbers
    
    $lunResult = Get-LunFromSerialNumber $SerialNumbers $result.VolumeSerialMapping
    $VolumeNames = $lunResult.LunNames
    $volumeLunMapping = $lunResult.VolumeLunMapping
    
    if (!($VolumeNames.count -gt 0)) {
        throw "Couldn't get associated Ontap LUN volume names"
    }

    $volumeResult = Get-VolumeIdFromName $VolumeNames $volumeLunMapping
    $volumes = $volumeResult.Response
    $volumeNameMapping = $volumeResult.volumeNameMapping
    #Write-output "Volume Ids: $($volumes | ConvertTo-Json)"

    #try {
    if($dblist.Length -gt 1) {
        $snapshot_prefix = $groupName
        $backup_type = 'GROUP'                
    }
    
    if($dblist.Length -eq 0){
            $snapshot_prefix = $serverInstanceName
            $backup_type = 'SERVER'
        } 
    if($dblist.Length -eq 1) {
            $snapshot_prefix = $databaseName
            $backup_type = 'DATABASE'
        }
      $sqlConn = New-Object System.Data.SQLClient.SQLConnection
      # Open SQL Server connection to master
      $sqlConn.ConnectionString = "server='" + $executableInstance +"';database='master';Integrated Security=True;"
      $sqlConn.Open()
      $Command = New-Object System.Data.SQLClient.SQLCommand
      $Command.Connection = $sqlConn

      $SQLParams= @{
         "Action" = 'suspend'
         "Conn" = $sqlConn
         "cmdsession" = $Command
         "BackupType" = $backup_type
      }
                    
     #Quiesce the database(s)
    try {
        Write-Output "Suspending database(s) $databaseName"

        if($backup_type -eq 'SERVER') {
            $suspenddatabases = Suspend-DatabasesForSnapshot @SQLParams
        } else {
        $SQLParams.Add("databaseList",$databaseList)
            $suspenddatabases = Suspend-DatabasesForSnapshot @SQLParams
        }

        Write-Output $suspenddatabases
    } catch {
       Write-Output "Failed to suspend databases! retry after sometime"
       exit 1
    
    }

     #Create snapshot for all the volumes
     $timestamp = (Get-Date -Format "yyyyMMddHHmmss")


     foreach ($record in $volumes.records) {
           $volumeUUID = $record.uuid
           $volumeName = $record.name
           Write-output "Taking snapshot for $volumeName ($volumeUUID)"
           $snapshot = $snapshot_prefix+"_"+$timestamp
           try {
                $snapshotResult = Create-ONTAPSnapshot $volumeUUID $volumeName $snapshot $snapshot_timeout
            } catch {
                Write-Output "Snapshot failed for volume $volumeName. Aborting backup and resuming database(s)"
                $SQLParams["Action"] = "resume"
                Suspend-DatabasesForSnapshot @SQLParams
                exit 1

            }

        }

    #Create metadata backup on SQL server

    $metabackup = $snapshot+'.bkm'
    if($backup_type -eq 'DATABASE') {
      $sqlbackupquery = "BACKUP DATABASE "+$databaseList+" TO DISK = '"+$metabackup+"' WITH METADATA_ONLY, FORMAT;"
    } elseif($backup_type -eq 'GROUP') {
        $sqlbackupquery = "BACKUP GROUP "+$databaseList+" TO DISK = '"+$metabackup+"' WITH METADATA_ONLY, FORMAT;"
    } else{
        $sqlbackupquery = "BACKUP SERVER TO DISK = '"+$metabackup+"' WITH METADATA_ONLY, FORMAT;"
    }
    Write-output $sqlbackupquery
    $Command.CommandText = $sqlbackupquery
    try {
        $sqlbackupresponse = $Command.ExecuteNonQuery();
        Write-output "Successfully backed up database(s) - $databaseName"
    } catch {
          Write-Output "Failed to take metadata backup database(s) $databaseName for snapshot $snapshot!"
          Write-Output "Resuming databases explicitly in case metadata backup failure failed to unfreeze"
          $SQLParams["Action"] = "resume"
          Suspend-DatabasesForSnapshot @SQLParams

          if ($sqlConn.State -eq [System.Data.ConnectionState]::Open) {
                        $sqlConn.Close()
                     }
                    # Dispose of the connection and command objects
                    $sqlConn.Dispose()
                    $Command.Dispose()
    }


    $sqlConn.Close()
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
return $_.Exception.Message
} 
 
