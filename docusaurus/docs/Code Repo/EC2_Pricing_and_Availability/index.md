# EC2 Pricing and Availability 

Find which AWS Regions and AZs an EC2 instance type is available in, plus the on-demand price for Windows and Linux.

## Use case:

When a new AWS EC2 Instance type is released, it may initially be limited to a few AWS Regions and Availability Zones (AZs). Additionally, the hourly instance price may differ between Regions.

[This PowerShell script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/30fcc982928f8911ce5ec5a6d662e1c11d31e7c1/docusaurus/docs/Code%20Repo/EC2_Pricing_and_Availability/Scripts/get-instance-availability.ps1) generates a consolidated table showing the Region, Availability Zone, and On-Demand Price for specified instance sizes.  This can be helpful when selecting the best locaction to launch EC2 Instances. 


Example: `m8a` instances are available in 3 of the 6 AZs in us-east-1.
```
Region                   AvailabilityZones
------                   ----------------- 
US East (N. Virginia)    use1-az2, use1-az4, use1-az6
```

Example: the `m8a.xlarge` instance hourly, on-demand price compared by OS and Region:
```
Region                   LinuxPrice WindowsPrice
------                   ---------- ------------
US East (N. Virginia)    $0.243     $0.427
Asia Pacific (Tokyo)     $0.314     $0.498
```

[The `get-instance-availability.ps1` script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/30fcc982928f8911ce5ec5a6d662e1c11d31e7c1/docusaurus/docs/Code%20Repo/EC2_Pricing_and_Availability/Scripts/get-instance-availability.ps1) queries all enabled AWS Regions to find where the specified EC2 instance types are available, and shows the Availability Zones or ZoneIDs, plus the on-demand pricing for Linux and Windows.  

Use the `-ZoneID` switch to show AZ IDs (e.g., use2-az1) instead of AZ names (e.g., us-east-2a)
 
[The PowerShell script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/30fcc982928f8911ce5ec5a6d662e1c11d31e7c1/docusaurus/docs/Code%20Repo/EC2_Pricing_and_Availability/Scripts/get-instance-availability.ps1) retrieves real-time pricing data from the AWS Pricing API and displays results
in a formatted table showing regional availability and hourly costs.

RECOMMENDED: Run [this PowerShell script](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/30fcc982928f8911ce5ec5a6d662e1c11d31e7c1/docusaurus/docs/Code%20Repo/EC2_Pricing_and_Availability/Scripts/get-instance-availability.ps1) from AWS [CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html) for the best experience. CloudShell comes with [PowerShell and AWS modules pre-installed](https://docs.aws.amazon.com/powershell/v5/userguide/pstools-getting-set-up-cloudshell.html), and credentials are automatically configured. Simply [upload](https://docs.aws.amazon.com/cloudshell/latest/userguide/getting-started.html#folder-upload) the script and run it.
    

Examples Syntax:

```bash
.PARAMETER InstanceType
    One or more EC2 instance types to query. Accepts comma-separated values.
    Default: m8a.xlarge

.PARAMETER SortBy
    Sort results by Region, LinuxPrice, or WindowsPrice.
    Default: WindowsPrice

.PARAMETER ZoneId
    Display AZ IDs (e.g., use2-az1) instead of AZ names (e.g., us-east-2a).

.EXAMPLE
    pwsh -File get-instance-availability.ps1
    Run with default parameters (m8a.xlarge, sorted by WindowsPrice).

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -InstanceType m8a.2xlarge
    Query availability and pricing for m8a.2xlarge instances across all regions.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -InstanceType "m7i.2xlarge,m8i.2xlarge" -SortBy WindowsPrice
    Query multiple instance types and sort results by Windows pricing.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -InstanceType m8a.xlarge -SortBy Region
    Query m8a.xlarge instances and sort results alphabetically by region name.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -ZoneId
    Display results with AZ IDs (use2-az1) instead of AZ names (us-east-2a).

.NOTES
    Author: coolcrai@amazon.com
    Version: 1.0
    Last Updated: October 23, 2025
    
    
Requirements:
    - AWS PowerShell modules: AWS.Tools.EC2, AWS.Tools.Pricing (preconfigured in AWS CloudShell)
    - Valid AWS credentials configured (preconfigured in AWS CloudShell)
    - Pricing API access (queries us-east-1 region)

Pricing Information:
    - Linux pricing is for standard Linux instances
    - Windows pricing includes license costs (License Included model)
    - All prices are hourly, on-demand rates in USD

```

Example output from [CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html)

`$ pwsh -File get-instance-availability.ps1 -InstanceType "m7a.xlarge, m8a.xlarge"`
![](images/m7a-m8a_example.png)

`$ pwsh -File get-instance-availability.ps1 -InstanceType p5.4xlarge`
![](images/p5.4xlarge.png)