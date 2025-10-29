---
sidebar_position: 20
sidebar_label: Automate SQL backup using snapshots on Amazon FSx for ONTAP
---

# Amazon FSx for ONTAP: SQL Server Snapshot-Based Backup Automation Script

[This PowerShell script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/SQL%20Server/Guides/Automate_SQL_backup_using_snapshots_on_Amazon_FSx_for_ONTAP/Scripts/TSQL_Backup.ps1) will automate the T-SQL backup flow utilizing snapshots on Amazon FSx for ONTAP filesystem and TSQL suspend and metadata backup. This will replace the
full and incremental backups of SQL. Recommended to run every 6hrs or at desired frequency. Transaction log backups would continue in the traditional way more frequently at 15min or lesser as needed.

[The PowerShell script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/SQL%20Server/Guides/Automate_SQL_backup_using_snapshots_on_Amazon_FSx_for_ONTAP/Scripts/TSQL_Backup.ps1) fetches the disks assigned to SQL instance/databases and maps that back to LUN and volume on Amazon FSx for ONTAP. You can run at the required schedule using SQL agent or Windows scheduler.

# Script Location

Get the script here: [TSQL_Backup.ps1](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/SQL%20Server/Guides/Automate_SQL_backup_using_snapshots_on_Amazon_FSx_for_ONTAP/Scripts/TSQL_Backup.ps1)

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

# Usage:

# To run backup on a single database:
```powershell
TSQL_Backup.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name> -databaseName <database name>
```

Example:
```powershell
TSQL_Backup.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'MSSQLSERVER' -databaseName 'Finance'
```
```powershell
TSQL_Backup.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'ENGINEERING' -databaseName 'Payments'
```
# To run backup on a group of databases:
```powershell
TSQL_Backup.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name> -databaseName <comma-separated database names>
```
Example:
```powershell
TSQL_Backup.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'ENGINEERING' -databaseName 'Finance,Resources,Accounts'
```
# To run backup on a Server(all databases):
```powershell
TSQL_Backup.ps1 -FSxID <FSx filesystem ID> -FSxRegion <AWS region> -serverInstanceName <SQL Server instance name>
```
Example:
```powershell
TSQL_Backup.ps1 -FSxID 'fs-07a22f282fd4f5a20' -FSxRegion 'eu-south-2' -serverInstanceName 'ENGINEERING'
```