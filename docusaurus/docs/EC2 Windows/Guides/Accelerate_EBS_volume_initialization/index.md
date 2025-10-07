---
sidebar_position: 30
sidebar_label: EBS Provisioned Rate - Accelerate EBS volume initialization
---

# EBS Provisioned Rate - Accelerate EBS volume initialization
by Craig Cooley

### Introduction
When launching a new EC2 Instance - whether restoring from a backup or creating from an Amazon Machine Image (AMI), the EC2 Instance is launched and accessible after a few minutes.  If an Admin connects via RDP immediately after launch, the instance can seem slow and unresponsive, or the application may not run with the expected performance.  

When an EBS volume is created from a snapshot (or AMI) the storage blocks are downloaded from S3 to EBS. The EBS volume is available as soon as the initial blocks are downloaded, however it's not fully performant until all blocks are downloaded from S3.  

In May 2025, AWS Announced [EBS Provisioned Rate for Volume Initialization](https://aws.amazon.com/about-aws/whats-new/2025/05/ebs-provisioned-rate-volume-initialization/) which  minimizes the amount of time taken to fully restore volumes from S3 to Elastic Block Storage (EBS).  [EBS Provisioned Rate](https://docs.aws.amazon.com/ebs/latest/userguide/initalize-volume.html#volume-initialization-rate) can fully restore the volume at a rate of up to 300 MiB/second to speed this process.  

The [VolumeInitializationRate parameter](https://docs.aws.amazon.com/sdkfornet/v4/apidocs/items/EC2/TEbsBlockDevice.html) is relatively low cost (up to $0.00360/GB in us-east-1) and is 'pay per use'.

To demonstrate the increased deployment speed, I added an EC2 User Data Script to install several Windows features when the Instance is launched.   

```powershell
Install-WindowsFeature `
    -Name Failover-Clustering, RSAT-ADDs, RSAT-DNS-Server `
    -IncludeManagementTools `
    -IncludeAllSubFeature
```

When the instance is launched, the optional Windows features are installed from the root volume which is being created.  Normally, when these commands are issued, the blocks are restored from S3 to the EBS volume on demand. 

To compare the time to deploy with and without **VolumeInitializationRate = 300**, I added `Measure-Command` to the script and wrote the time to a local file.  

Here's the command you can run from Cloudshell which creates a new Windows Instance using the `VolumeInitializationRate = 300` parameter to initialize the C: drive at a rate of 300 MiB/second. so the Windows Features will install quickly.  The User Data script measures the amount of time needed to install the `Failover-Clustering`, `RSAT-ADDs`, and `RSAT-DNS-Server` Windows features after the instance boots and records it to a local file. 

```powershell
Import-Module AWS.Tools.EC2
New-EC2Instance `
-ImageId "resolve:ssm:/aws/service/ami-windows-latest/TPM-Windows_Server-2025-English-Full-Base" `
-InstanceType "c7a.xlarge" `
-Region "us-east-2" `
-KeyName "<keyname>" `
-BlockDeviceMapping ( 
    [Amazon.EC2.Model.BlockDeviceMapping]@{
        DeviceName = '/dev/sda1'
        EBS = [Amazon.EC2.Model.EbsBlockDevice]@{
            VolumeInitializationRate = 300
        }
    }
) `
-EncodeUserData `
-UserData @"
<powershell>
Measure-Command {
    Install-WindowsFeature ``
        -Name Failover-Clustering, RSAT-ADDs, RSAT-DNS-Server ``
        -IncludeManagementTools ``
        -IncludeAllSubFeature
} | 
Format-List TotalMinutes | 
Out-File "C:\ProgramData\Amazon\EC2Launch\log\UserDataOutput.txt"
</powershell>
"@
```

To test without the **VolumeInitializationRate = 300** parameter, remove the `-BlockDeviceMapping` parameter and compare the time to complete the feature installation by checking the `C:\ProgramData\Amazon\EC2Launch\log\UserDataOutput.txt` file saved to the local C: drive. 

### Examples: 

**With** `VolumeInitializationRate = 300`
```
Instance ID: i-abcdef0123456789a   TotalMinutes : 3.24202892666667
Instance ID: i-abcdef0123456789b   TotalMinutes : 3.280395915
```

**Without** `VolumeInitializationRate = 300`
```
Instance ID: i-abcdef0123456789c   TotalMinutes : 4.83370798333333
Instance ID: i-abcdef0123456789d   TotalMinutes : 4.71676925333333
```

The `VolumeInitializationRate = 300` parameter reduced the time needed to install the Windows Features by about 1 min or 33%.  

The EBS Snapshot for Windows 2025 is about 25GB, so given the price of $0.00360/GB. the added cost is a one time charge of $0.09.

EBS Provisioned Rate for Volume Initialization can be specified from the following: 
* AWS EC2 Console
* [EC2 Launch Template](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-templates.html)
* AWS Command line tools (AWS CLI or [AWS.Tools for PowerShell](https://docs.aws.amazon.com/powershell/v5/reference/?page=New-EC2Instance.html&tocid=New-EC2Instance))