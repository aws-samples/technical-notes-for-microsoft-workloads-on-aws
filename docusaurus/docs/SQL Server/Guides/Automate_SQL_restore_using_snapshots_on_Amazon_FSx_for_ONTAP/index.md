---
sidebar_position: 30
sidebar_label: Automate SQL restore using snapshots on Amazon FSx for ONTAP
---

# Amazon FSx for ONTAP: SQL Server Snapshot-Based Restore Automation Script

[This PowerShell script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/SQL%20Server/Guides/Automate_SQL_restore_using_snapshots_on_Amazon_FSx_for_ONTAP/Scripts/TSQL_Restore.ps1) will automate the T-SQL restore flow from the application-consistent backup created using snapshots on FSx for ONTAP filesystem and TSQL metadata backup. This will also restore transaction logs The script fetches the disks assigned to SQL instance/databases and maps that back to LUN and volume on FSx for ONTAP.

# Script Location

Get the script here: [TSQL_Restore.ps1](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/SQL%20Server/Guides/Automate_SQL_restore_using_snapshots_on_Amazon_FSx_for_ONTAP/Scripts/TSQL_Restore.ps1)

# Pre-requisites: 

Some of the pre-requisites are as follows:
1. Store the Amazon FSx credentials as an AWS Systems Manager Parameter Store parameter for secure storage and retrieval
	a. [Create a SecureString parameter](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-su-create.html) named `/tsql/filesystem/<FSxN filesystem ID>`. Replaced `<FSxN filesystem ID>` with Amazon FSxN ID.

	b. Set its value to a JSON object with your FSx username and password. Example:
    ```json
    {
        fsx: {
            username: 'fsxadmin',
            password: 'password'
        }
    }
    ```
2. [Install](https://docs.aws.amazon.com/powershell/v4/userguide/pstools-getting-set-up-windows.html#ps-installing-awstools) AWS.Tools.SimpleSystemsManagement PowerShell module on the system where script is running.
3. The script expects the backups were taken using [SQL Server Snapshot-Based Backup Automation Script](https://aws-samples.github.io/technical-notes-for-microsoft-workloads-on-aws/SQL%20Server/Guides/Automate_SQL_backup_using_snapshots_on_Amazon_FSx_for_ONTAP/). Expectation is that ONTAP snapshot and SQL metadata backup have the same naming to map.
4. If you have automatic backups enabled or have manually created backups from the AWS FSx for ONTAP console, here's what you need to do first: Check for newer backups – Look for any backups that were created after the snapshot you want to restore. Delete those newer backups – Remove all backups that are more recent than your target snapshot. Why? FSxN won't allow you to restore a snapshot if there are newer snapshots linked to existing backups. Deleting them clears the way for a successful restore.

# Usage:

# To restore a single database that has failed to previous full state of volume snapshot
```powershell
TSQL_Restore.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name> -databaseName <database name> -isClustered <$True if cluster and $False if standalone> -snapshot <snapshot name>
```

Example for FCI:
```powershell
TSQL_Restore.ps1 -FSxID fs-07a22f282fd4f5a20 -FSxRegion eu-south-2 -serverInstanceName 'ENGINEERING' -databaseName 'Payments' -isClustered $True -snapshot 'Payments_20250514111905'
```

Example for Standalone:
```powershell
TSQL_Restore.ps1 -FSxID fs-07a22f282fd4f5a20 -FSxRegion eu-south-2 -serverInstanceName 'MSSQLSERVER' -databaseName 'Finance' -isClustered $False -snapshot 'Finance_20250524140920'
```
# To restore database to a snapshot backup and all transaction logs available after that
```powershell
TSQL_Restore.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name> -databaseName <comma-separated database names> -isClustered <$True if cluster and $False if standalone> -snapshot <snapshot name> -transactionRestore <$True to restore transaction logs, $False or skip to exclude>
```
Example:
```powershell
TSQL_Restore.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'ENGINEERING' -databaseName 'Payments' -isClustered $True -snapshot 'Payments_20250521083504' -transactionRestore $True
```
# To restore database to a previous snapshot backup and upto a specified transaction log backup
```powershell
TSQL_Restore.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name> -databaseName <comma-separated database names> -isClustered <$True if cluster and $False if standalone> -snapshot <snapshot name> -transactionRestore <$True to restore transaction logs, $False or skip to exclude> -tlogbackup_lastfile -transaction_date 
```
Example:
```powershell
TSQL_Restore.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'ENGINEERING' -databaseName 'Payments' -isClustered $True -snapshot 'Payments_20250521083504' -transactionRestore $True -tlogbackup_lastfile 'Payments_20250521091525.trn' -transaction_date '2025-05-21T09:10:31
```
# To restore backup for a database and restore a point-in-time from transaction log backup
```powershell
TSQL_Restore.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name> -databaseName <comma-separated database names> -isClustered <$True if cluster and $False if standalone> -snapshot <snapshot name> -transactionRestore <$True to restore transaction logs, $False or skip to exclude> -tlogbackup_lastfile <transaction log> -transaction_date <transaction timestamp>
```
Example:
```powershell
TSQL_Restore.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'ENGINEERING' -databaseName 'Payments' -isClustered $True -snapshot 'Payments_20250521083504' -transactionRestore $True -tlogbackup_lastfile 'Payments_20250521091525.trn' -transaction_date '2025-05-21T09:10:31'
```