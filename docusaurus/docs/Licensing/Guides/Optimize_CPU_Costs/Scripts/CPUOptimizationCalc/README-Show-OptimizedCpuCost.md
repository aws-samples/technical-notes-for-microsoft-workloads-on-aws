# Show-OptimizedCpuCost

Calculate the cost savings of running EC2 Windows instances with [Optimize CPUs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html) enabled (ThreadsPerCore = 1).

## Example scenario

A customer running SQL Server Enterprise on an `r6i.16xlarge` (3rd Gen Intel Xeon / Ice Lake) could upgrade to an `r8i.16xlarge` (6th Gen Intel Xeon / Granite Rapids) and enable Optimize CPUs with ThreadsPerCore=1. The newer processors deliver higher per-core performance, so even with SMT disabled, reducing the active vCPU count from 64 to 32 while retaining all 32 physical cores, SQL Server throughput stays comparable or improves. Meanwhile, the monthly cost drops from about $22,900 to $13,100, saving roughly $9,800/month.

```
.\Show-OptimizedCpuCost.ps1 -InstanceType r6i.16xlarge, r8i.16xlarge -LicenseType SQLEnterprise

Region InstanceType LicenseType   Cores TPC vCPUs Hours  Default $   TPC=1 $  Savings $  Savings % Note
------ ------------ -----------   ----- --- ----- ----- ---------- --------- ---------- ---------- ----
use1   r6i.16xlarge SQLEnterprise    32   2    64   730    $22,612   $12,778    -$9,835      43.5%
use1   r8i.16xlarge SQLEnterprise    32   2    64   730    $22,914   $13,080    -$9,835      42.9%
```

## How it works

When you launch a Windows or Windows+SQL Server license-included EC2 instance with Optimize CPUs (ThreadsPerCore = 1), AWS splits the billing into two line items:

1. **Base compute cost** — the Amazon Linux On-Demand rate for the instance type
2. **License fee** — active vCPUs x per-vCPU license rate

With ThreadsPerCore = 1, active vCPUs = number of physical cores (half the default vCPU count on instances that use SMT/hyperthreading). This reduces the license portion of the bill.

### Per-vCPU license rates

| License                            | Rate            |
|------------------------------------|-----------------|
| Windows Server                     | $0.046/vCPU-hr  |
| Windows + SQL Server Web           | $0.063/vCPU-hr  |
| Windows + SQL Server Standard      | $0.166/vCPU-hr  |
| Windows + SQL Server Enterprise    | $0.421/vCPU-hr  |

Instances that don't use SMT by default (e.g. AMD r8a) will show 0% savings since they already run 1 thread per core.

## Getting started

The easiest way to run this script is from [AWS CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html), which comes with PowerShell and AWS modules pre-installed, and credentials are automatically configured.

1. Sign in to the AWS Console
2. Open [CloudShell](https://us-east-2.console.aws.amazon.com/cloudshell/home)
3. [Upload the script file](https://docs.aws.amazon.com/cloudshell/latest/userguide/getting-started.html#folder-upload)
4. Start PowerShell and run:

```powershell
pwsh
.\Show-OptimizedCpuCost.ps1
```

## Requirements

- PowerShell 7+
- AWS Tools for PowerShell modules:
  - `AWS.Tools.EC2`
  - `AWS.Tools.Pricing`
- Valid AWS credentials with `ec2:DescribeInstanceTypes` and `pricing:GetProducts` permissions

```powershell
Install-Module AWS.Tools.EC2, AWS.Tools.Pricing -Scope CurrentUser
```

## Usage

```powershell
# Hourly cost comparison (default)
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge, m8i.32xlarge, m8i.48xlarge, m8a.48xlarge -LicenseType SQLEnterprise

# Compare all license types for an instance
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -LicenseType All

# Compare SQL editions only
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -LicenseType SQL

# Monthly estimate
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge, m8i.32xlarge -LicenseType SQLEnterprise -Hours month

# Annual estimate
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge, m8i.32xlarge -LicenseType SQLEnterprise -Hours year

# Different region, show memory, export to CSV
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -Region us-west-2 -Memory -OutputCsv results.csv

# Sort by absolute dollar savings
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge, m8i.32xlarge -LicenseType Windows -SortBy Savings

# Show all sizes in a family
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i -LicenseType SQLEnterprise

# All options
.\Show-OptimizedCpuCost.ps1 `
    -InstanceType m8i.16xlarge, m8i.32xlarge, m8i.48xlarge, m8a.48xlarge `
    -LicenseType SQLEnterprise `
    -Hours 730 `
    -Region us-east-2 `
    -SortBy Savings `
    -Memory `
    -OutputCsv results.csv
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-InstanceType` | `m8i.16xlarge` | One or more instance type names or family prefixes (e.g. `m8i`) |
| `-LicenseType` | `Windows` | `Windows`, `SQLWeb`, `SQLStandard`, `SQLEnterprise`, `SQL` (all 3 SQL editions), or `All` (all 4) |
| `-Region` | `us-east-1` | AWS region to query pricing for |
| `-Hours` | `730` | Number of hours, or `month` (730) / `year` (8760) |
| `-SortBy` | `SavingsPct` | Sort by `SavingsPct`, `Savings`, `Default`, `TPC1`, `vCPUs`, `Cores`, or `InstanceType` |
| `-Memory` | off | Include a MemoryGiB column in the output |
| `-OutputCsv` | *(none)* | Path to export results as CSV |

## Example output

```
.\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -LicenseType All

Region InstanceType LicenseType   Cores TPC vCPUs Hours  Default $   TPC=1 $  Savings $  Savings % Note
------ ------------ -----------   ----- --- ----- ----- ---------- --------- ---------- ---------- ----
use1   m8i.16xlarge Windows          32   2    64   730     $4,622    $3,547    -$1,075      23.3%
use1   m8i.16xlarge SQLWeb           32   2    64   730     $5,411    $3,944    -$1,467      27.1%
use1   m8i.16xlarge SQLStandard      32   2    64   730    $10,228    $6,350    -$3,878      37.9%
use1   m8i.16xlarge SQLEnterprise    32   2    64   730    $22,142   $12,307    -$9,835      44.4%

Default $ is based on On-Demand pricing.
Savings $ is the same regardless of pricing model (On-Demand, Savings Plans, etc.) since
   per-vCPU license rates are fixed.
Note: Reserved Instances may not apply discounts with Optimize CPUs — use Savings Plans instead.
```

## Notes legend

| Note | Meaning |
|---|---|
| 1 | Instance type defaults to TPC=1 — no SMT to disable, savings = 0% |
| 2 | SQL Server Standard/Enterprise minimum 4-vCPU billing applies |
| 3 | T-series (burstable) — Optimize CPUs not applicable |
| 4 | Instance too small for selected SQL edition |
| 5 | .metal — Optimize CPUs not applicable |

Only notes that apply to instances in the output are shown in the legend.

## Pricing notes

- Default $ is based on On-Demand pricing from the AWS Pricing API.
- Savings $ is the same regardless of pricing model (On-Demand, Savings Plans) since per-vCPU license rates are fixed.
- Optimize CPUs supports On-Demand and Savings Plans. Reserved Instances may not apply discounts correctly — see [AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html) for details.

## General notes

- .metal instances show the Default price but `--` for Optimize CPUs costs.
- The Pricing API is only available in `us-east-1` and `ap-south-1`. The script always queries `us-east-1` for pricing regardless of the `-Region` parameter.
- Pipeline output is supported: `.\Show-OptimizedCpuCost.ps1 ... | Where-Object SavingsPct -gt 20`

## Author

Craig Cooley (coolcrai@amazon.com) — March 2026
Built with [Kiro](https://kiro.dev) IDE + Claude Opus 4.6
