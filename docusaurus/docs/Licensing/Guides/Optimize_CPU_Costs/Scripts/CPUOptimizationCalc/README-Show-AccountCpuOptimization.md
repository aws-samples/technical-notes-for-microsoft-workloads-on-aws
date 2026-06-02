# AWS Account — Windows EC2 Optimize CPUs Scanner

Scans your AWS account for Windows and Windows+SQL Server license-included EC2 instances, then calculates the potential cost savings if [Optimize CPUs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html) (ThreadsPerCore = 1) were enabled.

## Use case

Windows and SQL Server license-included EC2 instances are billed per vCPU. On instances with SMT (Simultaneous Multithreading), each physical core presents as 2 vCPUs — doubling the license cost. Disabling SMT cuts the active vCPU count in half, which can reduce licensing costs by 20-45% depending on the license type.

This script scans your running and stopped instances, identifies which ones are Microsoft License Included, and shows you the dollar impact of enabling Optimize CPUs per instance and across your account.

It also identifies:
- Instances that already have SMT disabled
- Dedicated Host instances (license-only costs, no compute)
- T-series (burstable) and .metal instances where Optimize CPUs doesn't apply
- Instances that don't use SMT, such as AMD or T2 (no savings possible)
- SQL Server instances subject to the 4-vCPU minimum billing

## Getting started

1. Sign in to the AWS Console
2. Download the [Show-AccountCpuOptimization.ps1](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/2ebc1a9e4db9b9e311f5b60e152b7f38810dd840/docusaurus/docs/Licensing/Guides/Optimize_CPU_Costs/Scripts/CPUOptimizationCalc/Show-AccountCpuOptimization.ps1) script to your desktop.
3. Open [CloudShell](https://us-east-2.console.aws.amazon.com/cloudshell/home)
4. [Upload the script](https://docs.aws.amazon.com/cloudshell/latest/userguide/getting-started.html#folder-upload)
5. Run:

```powershell
pwsh
.\Show-AccountCpuOptimization.ps1
```

## Requirements

- PowerShell 7+ (pre-installed in CloudShell)
- AWS Tools for PowerShell: `AWS.Tools.EC2`, `AWS.Tools.Pricing` (pre-installed in CloudShell)
- IAM permissions: `ec2:DescribeInstances`, `ec2:DescribeInstanceTypes`, `ec2:DescribeRegions`, `pricing:GetProducts`

## Usage

```powershell
# Scan current region (default: 730 hours)
.\Show-AccountCpuOptimization.ps1

# Scan all US regions
.\Show-AccountCpuOptimization.ps1 -Region us

# Scan all enabled regions with annual estimate
.\Show-AccountCpuOptimization.ps1 -Hours year

# Only SQL Standard and Enterprise instances
.\Show-AccountCpuOptimization.ps1 -Region us -LicenseType SQLStandard,SQLEnterprise

# Filter by tag
.\Show-AccountCpuOptimization.ps1 -Region us-east-1 -Tag 'Env:Production'

# Multiple tags (AND logic across keys)
.\Show-AccountCpuOptimization.ps1 -Tag 'Env:Production', 'Team:DBA'

# Multiple values for same tag (OR logic within key)
.\Show-AccountCpuOptimization.ps1 -Tag 'Env:Production,Staging'

# Export to CSV (auto-generated filename)
.\Show-AccountCpuOptimization.ps1 -OutputCsv

# Export to HTML (can be opened in Excel, auto-generated filename)
.\Show-AccountCpuOptimization.ps1 -OutputHtml

# All options
.\Show-AccountCpuOptimization.ps1 `
    -Region us-east-1, us-east-2 `
    -LicenseType SQLEnterprise `
    -Tag 'Env:Production' `
    -Hours year `
    -OutputCsv `
    -OutputHtml
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Region` | all regions | One or more regions, prefixes (e.g. `us`, `eu-west`), or `all` |
| `-Hours` | `730` | Number of hours, or `month` (730) / `year` (8760) |
| `-LicenseType` | `All` | Filter: `All`, `Windows`, `SQL` (all SQL editions), `SQLWeb`, `SQLStandard`, `SQLEnterprise` |
| `-Tag` | *(none)* | Filter by tag in `Key:Value` format. Comma-separated values for OR (`Env:Prod,Staging`). Multiple `-Tag` entries use AND logic |
| `-OutputCsv` | off | Export to CSV with auto-generated filename |
| `-OutputHtml` | off | Export to HTML with auto-generated filename (can be opened in Excel). TPC=2 rows are highlighted |
| `-IncludeBYOL` | off | Include BYOL Windows instances (shown with `--` pricing) |

## Example output

```
Region InstanceId          Name         InstanceType LicenseType   Cores TPC vCPUs Hours  Default $   TPC=1 $  Savings $  Savings % Note
------ ----------          ----         ------------ -----------   ----- --- ----- ----- ---------- --------- ---------- ---------- ----
use1   i-0abc123def456789a SQL-Prod     c6i.16xlarge SQLEnterprise    32   1    32   730    $49,617   $28,798   -$20,819      42.0% 3
use1   i-0bcd234ef5678901b Web-App      c8a.xlarge   Windows           4   1     4   730       $292      $292         $0       0.0% 2
use2   i-0cde345fg6789012c Dev-SQL      m8i.2xlarge  SQLStandard       4   2     8   730     $1,278      $794      -$485      37.9%
use2   i-0def456gh7890123d DH-SQL       c5.4xlarge   SQLEnterprise     8   1     8   730     $2,459    $1,229    -$1,229      50.0% 1,3
use2   i-0efg567hi8901234e Legacy       t3.2xlarge   Windows           4   2     8   730         --        --         --         -- 5

Total Default TPC Setting:      $53,646
Total if TPC set to 1:          $31,113
Total Difference:              -$22,533
Total Savings:                    42.0%

Already saving (TPC=1):        -$22,048
Potential new savings:            -$485

  1 = Dedicated Host — only licensing costs were calculated (no instance compute cost)
  2 = Instance type defaults to TPC=1 — no SMT to disable, savings = 0%
  3 = Already running with TPC=1 (SMT disabled)
  5 = T-series (burstable) — Optimize CPUs not applicable

Scanned 2 region(s). Found 5 Windows instance(s).

Default $ is based on On-Demand pricing.
Savings $ is the same regardless of pricing model (On-Demand, Savings Plans, etc.) since
   per-vCPU license rates are fixed.
Note: Reserved Instances may not apply discounts with Optimize CPUs — use Savings Plans instead.
```

## Output columns

| Column | Description |
|---|---|
| Region | Short region code (e.g. `use1`, `euw1`) |
| InstanceId | EC2 instance ID |
| Name | Instance Name tag (truncated to 19 chars) |
| InstanceType | EC2 instance type |
| LicenseType | Windows, SQLWeb, SQLStandard, or SQLEnterprise |
| Cores | Default physical core count for the instance type (DescribeInstanceTypes API) |
| TPC | Current ThreadsPerCore on the instance (DescribeInstances API) |
| vCPUs | Current active vCPU count on the instance (DescribeInstances API: CoreCount × TPC) |
| Hours | Hours used for cost calculation |
| Default $ | On-Demand combined rate for the instance type, or license-only for Dedicated Hosts |
| TPC=1 $ | Calculated: Linux base rate + (Cores × per-vCPU license rate), or license-only for Dedicated Hosts |
| Savings $ | Cost difference (negative = savings) |
| Savings % | Percentage savings |
| Note | Numbered notes indicating special conditions (see legend below output) |

## Notes legend

| Note | Meaning |
|---|---|
| 1 | Dedicated Host — only licensing costs were calculated (no instance compute cost) |
| 2 | Instance type defaults to TPC=1 — no SMT to disable, savings = 0% |
| 3 | Already running with TPC=1 (SMT disabled) |
| 4 | SQL Server Standard/Enterprise minimum 4-vCPU billing applies |
| 5 | T-series (burstable) — Optimize CPUs not applicable |
| 6 | .metal — Optimize CPUs not applicable |

Only notes that apply to instances in the scan are shown in the output legend.

## Pricing notes

- Default $ is based on On-Demand pricing from the AWS Pricing API.
- Savings $ is the same regardless of pricing model (On-Demand, Savings Plans) since per-vCPU license rates are fixed.
- Optimize CPUs supports On-Demand and Savings Plans. Reserved Instances may not apply discounts correctly — see [AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html) for details.
- For Dedicated Host instances, only the license portion is calculated since there is no per-instance compute cost.

## General notes

- Scans running, stopped, stopping, and pending instances.
- Includes shared, dedicated, and host tenancy instances.
- T-series (burstable) and .metal instances show `--` for Optimize CPUs costs.
- AMD instances that don't use SMT will show 0% savings.
- The Pricing API always queries `us-east-1` regardless of the instance's region.
- Price and CPU info are cached per instance type to minimize API calls.

## Author

Craig Cooley — February 2026
Built with [Kiro](https://kiro.dev) IDE + Claude Opus 4.6
