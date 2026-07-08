# Show-RdsSqlPricing.ps1

Compares RDS for SQL Server instance pricing across families and sizes, with accurate total cost calculations for both bundled (older gen) and unbundled (newer gen) pricing models.

## What it does

- Pulls On-Demand instance pricing from the AWS Pricing API
- Adds separate SQL Server and Windows license fees for unbundled instances (m7i, m8i, m8a, r7i, r8i, r8a, etc.)
- Supports License Included (default) or Bring Your Own Media (`-License BYOM`); BYOM limits results to BYOM-eligible instances and waives the SQL Server fee
- Applies the Microsoft 4-vCPU minimum for SQL Server licensing
- Shows physical core counts (default and max) from RDS Orderable Instance Options
- Includes network bandwidth (Pricing API) and per-instance max EBS throughput/IOPS (EC2, matching the RDS hardware spec docs)
- Optionally shows 1-year commitment pricing (Database Savings Plan / Reserved Instance) with `-DBSP_RI_1y`

## Quick start (AWS CloudShell)

1. Open [AWS CloudShell](https://console.aws.amazon.com/cloudshell/)
2. [Upload](https://docs.aws.amazon.com/cloudshell/latest/userguide/getting-started.html#folder-upload) `Show-RdsSqlPricing.ps1` (Actions → Upload file)
3. Start PowerShell:
   ```
   pwsh
   ```
4. Run:
   ```powershell
   ./Show-RdsSqlPricing.ps1 -Family r -Size 4xlarge -Edition Standard
   ```

## Prerequisites

AWS CloudShell is recommended — PowerShell and AWS modules are pre-installed. For local use, see [Setting up the AWS Tools for PowerShell](https://docs.aws.amazon.com/powershell/v5/userguide/pstools-getting-set-up.html).

Modules required: `AWS.Tools.Pricing`, `AWS.Tools.RDS`, `AWS.Tools.EC2`

Optional (for `-DBSP_RI_1y`): `AWS.Tools.SavingsPlans`

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Edition` | Standard | SQL Server edition: `Standard`, `Enterprise`, `Web`, `Developer` |
| `-License` | LI | Licensing model: `LI` (License Included) or `BYOM` (Bring Your Own Media). Under BYOM the output is limited to BYOM-eligible instances (m7i, m8i, r7i, r8i today) and the SQL Server license fee is waived; Windows OS fee and compute still apply. Standard/Enterprise only |
| `-Region` | us-east-1 | AWS region code (e.g. `us-east-1`, `eu-west-1`) |
| `-Deployment` | Single-AZ | Deployment option: `Single-AZ`, `Multi-AZ` |
| `-Size` | 8xlarge | Instance size filter (e.g. `large`, `xlarge`, `2xlarge`, `4xlarge`). Use `all` for all sizes |
| `-Family` | (all) | Instance family filter. Accepts multiple values (e.g. `m`, `r`, `m7i`, `m8`). Prefix match by default (`r5` also matches `r5b`/`r5d`); append a trailing dot for an exact match (`r5.` matches only `r5`) |
| `-ShowBreakdown` | off | Show individual cost components (Compute, SQL, Win) for unbundled instances |
| `-DBSP_RI_1y` | off | Add a `DBSP_RI_1y` column: Database Savings Plan (unbundled) or Reserved Instance (bundled), 1-year No Upfront. Requires `AWS.Tools.SavingsPlans` |
| `-Hours` | 1 | Multiplier for all price columns. Use 730 for monthly estimates. Precision scales with the period: hourly shows 3 decimals, up to 24h shows cents, above 24h rounds to whole dollars |
| `-PassThru` | off | Emit result objects to the pipeline instead of a formatted table (for `Export-Csv`, `ConvertTo-Json`, etc.) |

## Example output

```powershell
./Show-RdsSqlPricing.ps1 -Region us-east-1 -Family r -Size 16xlarge -Edition Enterprise -Deployment Multi-AZ -DBSP_RI_1y -ShowBreakdown
```

![Show-RdsSqlPricing sample output](Show-RdsSqlPricing-sample.png)

## Usage

```powershell
# Default: Standard edition, 8xlarge, all families, us-east-1
./Show-RdsSqlPricing.ps1

# Compare m-series 2xlarge instances
./Show-RdsSqlPricing.ps1 -Family m -Size 2xlarge

# All sizes for m8i family
./Show-RdsSqlPricing.ps1 -Family m8i -Size all

# Exact family match: only r5, excluding r5b/r5d (note the trailing dot)
./Show-RdsSqlPricing.ps1 -Family r5. -Size all

# Enterprise edition, 4xlarge, r family in eu-west-1
./Show-RdsSqlPricing.ps1 -Edition Enterprise -Size 4xlarge -Family r -Region eu-west-1

# Multi-AZ deployment
./Show-RdsSqlPricing.ps1 -Deployment Multi-AZ -Size 8xlarge

# Developer edition (free SQL license, Windows only)
./Show-RdsSqlPricing.ps1 -Edition Developer -Size 2xlarge

# Show cost breakdown for unbundled instances
./Show-RdsSqlPricing.ps1 -Family m8i -Size 4xlarge -ShowBreakdown

# BYOM: bring your own SQL Server license (no SQL fee on unbundled; Windows still charged)
./Show-RdsSqlPricing.ps1 -Edition Enterprise -Family m8i,r8i -Size 4xlarge -License BYOM -ShowBreakdown

# Include 1-year commitment pricing (Database Savings Plan for unbundled, Reserved Instance for bundled)
./Show-RdsSqlPricing.ps1 -Family r -Size 8xlarge -DBSP_RI_1y

# Combine breakdown and savings plans
./Show-RdsSqlPricing.ps1 -Family m8i -Size 4xlarge -ShowBreakdown -DBSP_RI_1y

# Export monthly estimates to CSV instead of printing a table
./Show-RdsSqlPricing.ps1 -Family m -Size all -Hours 730 -PassThru | Export-Csv monthly.csv -NoTypeInformation

# Sort by price, cheapest first (-PassThru emits objects you can sort/filter/export)
./Show-RdsSqlPricing.ps1 -Deployment Multi-AZ -Size 8xlarge -PassThru | Sort-Object Price_OD | Format-Table -AutoSize

# Only instances under $15/hr, sorted by price
./Show-RdsSqlPricing.ps1 -Size 8xlarge -PassThru | Where-Object Price_OD -lt 15 | Sort-Object Price_OD | Format-Table -AutoSize
```

> Note: `-PassThru` returns result objects instead of the formatted table, so you can `Sort-Object`, `Where-Object`, or `Export-Csv` (e.g. `Sort-Object DBSP_RI_1y`). Only the two columns whose names contain a `/` need quotes when referenced: `'Network_Gb/s'` and `'Max_MB/s'`. The memory property is `RAM` (shown as `RAM_GiB` in the table), and there is no `Hrs` property (it is display-only).

## Output columns

| Column | Source | Description |
|--------|--------|-------------|
| Instance | Pricing API | RDS instance type |
| Cores | RDS Orderable Options | Default physical core count (with Optimize CPU applied) |
| MaxCores | RDS Orderable Options | Maximum configurable cores (shown only when different from default) |
| vCPUs | Pricing API | Virtual CPUs (underlying instance, before Optimize CPU) |
| RAM_GiB | Pricing API | Memory in GiB |
| Network_Gb/s | Pricing API | Network bandwidth (normalized to Gb/s) |
| Max_MB/s | EC2 DescribeInstanceTypes | Max EBS throughput in MB/s (matches RDS hardware spec docs; blank for RDS-exclusive types) |
| Max_IOPS | EC2 DescribeInstanceTypes | Max EBS IOPS (scales by instance size; blank for RDS-exclusive types) |
| Compute | Pricing API | Compute (instance) cost; shown with `-ShowBreakdown` |
| SQL | Calculated | SQL Server license fee (unbundled); `0` under `-License BYOM`, blank for bundled; shown with `-ShowBreakdown` |
| Win | Calculated | Windows OS license fee (unbundled; doubled for Multi-AZ); blank for bundled; shown with `-ShowBreakdown` |
| Price_OD | Calculated | Total On-Demand cost including all license fees (hourly by default; scaled by `-Hours`) |
| DBSP_RI_1y | Savings Plans / RI API | Price at the 1-year commitment rate: Database Savings Plan (DBSP) for unbundled, Reserved Instance (RI) for bundled. Shown with `-DBSP_RI_1y`. Per-period like `Price_OD` and scaled by `-Hours` — the `1yr` is the commitment term, not a 12-month total |
| Hrs | — | The `-Hours` multiplier applied to all price columns (1 = hourly). Shown by default |

## Pricing logic

- **Bundled instances** (m4, m5, m6i, r4, r5, r6i, etc.): Price comes directly from the Pricing API — SQL Server and Windows licenses are included.
- **Unbundled instances** (m7i, m8i, m8a, r7i, r8i, r8a, etc.): Total = instance price + SQL Server license (per vCPU) + Windows license (per vCPU). Detected via the `unbundledLicensing` attribute.
- **4-vCPU minimum**: SQL Server licensing uses `Max(4, vCPUs)` per Microsoft licensing requirements. Windows licensing uses actual vCPUs.
- **License model** (`-License`): With `LI` (License Included, default) AWS provides the SQL Server license. With `BYOM` (Bring Your Own Media) you supply the SQL Server license via Microsoft License Mobility, so the SQL Server license fee is waived while the Windows OS fee and compute still apply. BYOM isn't offered on every unbundled family, so under `-License BYOM` the output is filtered to instances that actually carry a BYOM price for the chosen edition/region (m7i, m8i, r7i, r8i today) — queried live from the pricing catalog, so families like m8a/r8a/x2m are correctly excluded. BYOM is offered for Standard and Enterprise editions. See the [BYOM guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/sqlserver-byom.html).
- **Multi-AZ licensing**: For unbundled instances, SQL Server is charged for only the active node (passive failover rights). Windows OS is charged for both nodes. See [AWS announcement](https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-rds-sql-server-optimized-cpu-lower-prices/).
- **License rates** are pulled dynamically from the `AmazonRDSOCPULicenseFees` pricing service.
- **Commitment pricing** (`-DBSP_RI_1y`): Adds a `DBSP_RI_1y` column. For unbundled instances, the 1-year No Upfront **Database Savings Plan** rate applies to the compute portion — SQL Server and Windows license fees are added at full price on top (under `-License BYOM` the SQL Server fee is likewise dropped). For bundled instances, the 1-year No Upfront **Reserved Instance** price is shown (licenses included). RDS does not use Compute Savings Plans.

## Notes

- The Pricing API is hosted in us-east-1 only. The script queries it there regardless of the target region.
- Core counts for older instances (m4, m5, m6i) that don't support Optimize CPU fall back to `vCPUs / 2`.
- Instance availability varies by region — some families may not appear in all regions.
- **Developer edition**: Pulls both "Developer" (bundled, older gen) and "Enterprise Developer" (unbundled, newer gen) from the API. The Pricing API may list instances (e.g. m5, r5) that are not actually orderable for Developer — refer to the [DB instance class support page](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.InstanceClasses.html) for actual availability.
- **EBS specs**: `Max_MB/s` and `Max_IOPS` come from EC2 `DescribeInstanceTypes` (the same data the RDS hardware spec docs publish) and scale by instance size. RDS-exclusive types with no EC2 equivalent (e.g. db.x2m) show blank for these columns.

---

Craig Cooley
July 2026 - built with Kiro IDE
