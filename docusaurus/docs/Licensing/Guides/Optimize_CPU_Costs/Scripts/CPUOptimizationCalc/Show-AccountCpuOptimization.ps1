<#
.SYNOPSIS
    Scans EC2 instances for Microsoft License-Included workloads and calculates
    potential Optimize CPUs savings by disabling SMT / hyperthreading (ThreadsPerCore = 1).

.DESCRIPTION
    Queries all running and stopped EC2 instances in the specified region(s),
    identifies Windows and Windows+SQL Server license-included instances by their
    UsageOperation, retrieves CPU topology and pricing, then calculates the cost
    difference if ThreadsPerCore were set to 1.

    Supports shared, dedicated, and host tenancy instances. For Dedicated Host
    instances, only licensing costs are calculated (no instance compute cost).

    Data sources:
      Cores:     DescribeInstanceTypes API (default core count for the instance type)
      TPC:       DescribeInstances API (current ThreadsPerCore on the specific InstanceID)
      vCPUs:     DescribeInstances API (current CoreCount x current ThreadsPerCore for the specific InstanceID)
      Default $: Pricing API (On-Demand combined rate), or license-only for Dedicated Hosts
      TPC=1 $:   Calculated (Linux base rate + Cores x per-vCPU license rate), or license-only for Dedicated Hosts

    Per-vCPU license rates (from AWS Optimize CPUs docs):
      Windows Server:                       $0.046/vCPU-hr
      Windows Server with SQL Server Web:   $0.063/vCPU-hr
      Windows Server with SQL Server Std:   $0.166/vCPU-hr
      Windows Server with SQL Server Ent:   $0.421/vCPU-hr

    Default $ is based on On-Demand pricing. Savings $ is the same regardless of
    pricing model (On-Demand, Savings Plans) since per-vCPU license rates are fixed.
    Reserved Instances may not apply discounts with Optimize CPUs — use Savings Plans.

.PARAMETER Region
    One or more AWS regions, region prefixes (e.g. 'us', 'eu-west'), or 'all'.
    Supports arrays: -Region us-east-1, us-east-2
    Defaults to all enabled regions.

.PARAMETER Hours
    Number of hours for cost calculation, or 'month' (730) / 'year' (8760).
    Defaults to 730.

.PARAMETER OutputCsv
    Export results to CSV. Filename is auto-generated:
    CPULicenseOptimize-<account>-<MMdd-HHmm>.csv

.PARAMETER OutputHtml
    Export results to HTML. Filename is auto-generated:
    CPULicenseOptimize-<account>-<MMdd-HHmm>.html
    The HTML file can be opened in Excel. Rows with TPC=2 are highlighted.

.PARAMETER IncludeBYOL
    Include BYOL (Bring Your Own License) Windows instances in the output.
    These show pricing as -- since BYOL licensing is managed externally.

.PARAMETER Tag
    Filter instances by tag in 'Key:Value' format. Multiple tags use AND logic.

.PARAMETER LicenseType
    Filter by license type. Accepts one or more of:
      All, Windows, SQL (all SQL editions), SQLWeb, SQLStandard, SQLEnterprise
    Defaults to All.

.EXAMPLE
    .\Show-AccountCpuOptimization.ps1
    Scan current region for all Windows LI instances (730 hours).

.EXAMPLE
    .\Show-AccountCpuOptimization.ps1 -Hours year
    Scan all enabled regions with annual cost estimate.

.EXAMPLE
    .\Show-AccountCpuOptimization.ps1 -Region us -LicenseType SQLStandard,SQLEnterprise
    Scan all US regions for SQL Standard and Enterprise instances only.

.EXAMPLE
    .\Show-AccountCpuOptimization.ps1 -Region us-east-1 -Tag 'Env:Production' -OutputCsv
    Scan us-east-1 filtered by tag, export to CSV.

.EXAMPLE
    .\Show-AccountCpuOptimization.ps1 -Region us -OutputHtml
    Scan all US regions, export HTML report (can be opened in Excel).

.EXAMPLE
    .\Show-AccountCpuOptimization.ps1 -Region us-east -Tag 'auto-delete:no' -LicenseType SQLEnterprise -Hours year

.NOTES
    Author: Craig Cooley (coolcrai@amazon.com)
    Built with: Kiro IDE + Claude Opus 4.6
    Date: February 2026

    Requires AWS Tools for PowerShell:
      - AWS.Tools.EC2
      - AWS.Tools.Pricing
    Requires permissions: ec2:DescribeInstances, ec2:DescribeInstanceTypes,
                          ec2:DescribeRegions, pricing:GetProducts
#>

[CmdletBinding()]
param(
    [string[]]$Region,

    [string]$Hours = "730",

    [switch]$OutputCsv,

    [switch]$OutputHtml,

    [switch]$IncludeBYOL,

    [switch]$ShowState,

    [string[]]$Tag,

    [ValidateSet("All", "Windows", "SQL", "SQLWeb", "SQLStandard", "SQLEnterprise")]
    [string[]]$LicenseType = @("All")
)

# ── Resolve hours ──
$HoursNum = switch ($Hours.ToLower()) {
    'month'  { 730 }
    'year'   { 8760 }
    default  {
        if ($Hours -as [int]) { [int]$Hours }
        else { throw "Invalid -Hours value '$Hours'. Use a number, 'month', or 'year'." }
    }
}

# ── UsageOperation → License type mapping ──
$OpToLicense = @{
    'RunInstances:0002' = 'Windows'
    'RunInstances:0006' = 'SQLStandard'
    'RunInstances:0102' = 'SQLEnterprise'
    'RunInstances:0202' = 'SQLWeb'
    'RunInstances:0800' = 'Windows BYOL'
}

# ── Per-vCPU license rates ──
$LicenseRates = @{
    'Windows'        = 0.046
    'SQLWeb'         = 0.063
    'SQLStandard'    = 0.166
    'SQLEnterprise'  = 0.421
}

# ── Pricing API filter values per license type ──
$LicenseFilterMap = @{
    'Windows'        = @{ OS = 'Windows'; SW = 'NA';      Op = 'RunInstances:0002' }
    'SQLWeb'         = @{ OS = 'Windows'; SW = 'SQL Web'; Op = 'RunInstances:0202' }
    'SQLStandard'    = @{ OS = 'Windows'; SW = 'SQL Std'; Op = 'RunInstances:0006' }
    'SQLEnterprise'  = @{ OS = 'Windows'; SW = 'SQL Ent'; Op = 'RunInstances:0102' }
}

# ── Microsoft 4-core billing minimum ──
$MinBillableVcpus = @{
    'Windows'        = 1
    'SQLWeb'         = 1
    'SQLStandard'    = 4
    'SQLEnterprise'  = 4
}

$PricingRegion = 'us-east-1'

# ── Price cache to avoid repeated API calls for the same instance type + license ──
$priceCache = @{}

# ── Helper: query Pricing API for On-Demand hourly rate ──
function Get-OnDemandPrice {
    param(
        [string]$InstanceTypeName,
        [string]$OS,
        [string]$PreInstalledSw,
        [string]$Operation,
        [string]$RegionCode,
        [string]$PricingRgn
    )

    $cacheKey = "${InstanceTypeName}|${Operation}|${RegionCode}"
    if ($priceCache.ContainsKey($cacheKey)) { return $priceCache[$cacheKey] }

    $filters = @(
        @{ Type = 'TERM_MATCH'; Field = 'instanceType';   Value = $InstanceTypeName },
        @{ Type = 'TERM_MATCH'; Field = 'regionCode';     Value = $RegionCode },
        @{ Type = 'TERM_MATCH'; Field = 'operatingSystem'; Value = $OS },
        @{ Type = 'TERM_MATCH'; Field = 'preInstalledSw'; Value = $PreInstalledSw },
        @{ Type = 'TERM_MATCH'; Field = 'tenancy';        Value = 'Shared' },
        @{ Type = 'TERM_MATCH'; Field = 'operation';      Value = $Operation }
    )

    $raw = Get-PLSProduct -ServiceCode AmazonEC2 -Filter $filters -Region $PricingRgn -ErrorAction SilentlyContinue
    $prices = @()

    foreach ($jsonStr in $raw) {
        $product = $jsonStr | ConvertFrom-Json
        if ($product.product.attributes.capacitystatus -ne 'Used') { continue }
        $onDemand = $product.terms.OnDemand
        if (-not $onDemand) { continue }
        $skuTerm = $onDemand.PSObject.Properties.Value | Select-Object -First 1
        $usd = $skuTerm.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1
        if ($usd -and [decimal]$usd -gt 0) { $prices += [decimal]$usd }
    }

    $result = if ($prices.Count -gt 0) { ($prices | Measure-Object -Maximum).Maximum } else { $null }
    $priceCache[$cacheKey] = $result
    return $result
}

# ── CPU info cache ──
$cpuCache = @{}
function Get-CpuInfo {
    param([string]$InstanceTypeName, [string]$Rgn)
    if ($cpuCache.ContainsKey($InstanceTypeName)) { return $cpuCache[$InstanceTypeName] }
    $info = Get-EC2InstanceType -InstanceType $InstanceTypeName -Region $Rgn
    $cpuCache[$InstanceTypeName] = $info
    return $info
}

# ── Generate default output filenames ──
$acctId = try { (Get-STSCallerIdentity).Account } catch { '00000' }
$acctSuffix = $acctId.Substring($acctId.Length - 5)
$timestamp = Get-Date -Format 'MMdd-HHmm'
$baseFilename = "CPULicenseOptimize-${acctSuffix}-${timestamp}"

$csvPath  = if ($OutputCsv)  { "${baseFilename}.csv" }  else { $null }
$htmlPath = if ($OutputHtml) { "${baseFilename}.html" } else { $null }

# ── Determine regions to scan ──
if ($Region -and $Region.Count -eq 1 -and $Region[0] -eq 'all') {
    $regions = (Get-EC2Region -ErrorAction SilentlyContinue).RegionName
} elseif ($Region) {
    # Get all valid regions for prefix matching
    $allRegions = (Get-EC2Region -ErrorAction SilentlyContinue).RegionName
    $regions = @()
    foreach ($r in $Region) {
        # Exact match
        if ($r -in $allRegions) {
            $regions += $r
        } else {
            # Prefix match (e.g. "us-" matches us-east-1, us-east-2, us-west-1, us-west-2)
            $matched = $allRegions | Where-Object { $_ -like "${r}*" }
            if ($matched) {
                $regions += $matched
            } else {
                Write-Warning "No regions matched '$r'."
            }
        }
    }
    $regions = $regions | Sort-Object -Unique
    if ($regions.Count -gt 1) { }
} else {
    # Default to all enabled regions
    $regions = (Get-EC2Region -ErrorAction SilentlyContinue).RegionName
}

# ── Windows LI usage operations we care about ──
$windowsOps = @('RunInstances:0002', 'RunInstances:0006', 'RunInstances:0102', 'RunInstances:0202')
$byolOps    = @('RunInstances:0800')

$results = [System.Collections.Generic.List[PSObject]]::new()

foreach ($rgn in $regions) {
    Write-Verbose "Scanning $rgn ..."

    # Build filters
    $filters = @(
        @{Name='instance-state-name'; Values=@('running','stopped','stopping','pending')}
    )
    # Add tag filters (format: "Key:Value" or "Key:Value1,Value2" for OR)
    foreach ($t in $Tag) {
        if ($t -match '^([^:]+):(.+)$') {
            $tagKey = $Matches[1]
            $tagValues = $Matches[2] -split ',' | ForEach-Object { $_.Trim() }
            $filters += @{Name="tag:$tagKey"; Values=$tagValues}
        }
    }

    # Get all non-terminated instances
    try {
        $reservations = Get-EC2Instance -Region $rgn -Filter $filters -ErrorAction Stop
    } catch {
        Write-Warning "Could not query instances in $rgn : $_"
        continue
    }

    foreach ($reservation in $reservations) {
        foreach ($inst in $reservation.Instances) {
            $usageOp = $inst.UsageOperation

            # Filter to Windows LI (and optionally BYOL)
            $isLI   = $usageOp -in $windowsOps
            $isBYOL = $usageOp -in $byolOps

            if (-not $isLI -and -not ($IncludeBYOL -and $isBYOL)) { continue }

            $instLicense = $OpToLicense[$usageOp]
            if (-not $instLicense) { continue }

            # Filter by LicenseType param
            $effectiveLicenseTypes = @()
            foreach ($lt in $LicenseType) {
                if ($lt -eq 'SQL') { $effectiveLicenseTypes += @('SQLWeb', 'SQLStandard', 'SQLEnterprise') }
                else { $effectiveLicenseTypes += $lt }
            }
            if ('All' -notin $effectiveLicenseTypes -and $instLicense -notin $effectiveLicenseTypes) { continue }

            $instanceType = $inst.InstanceType
            $instanceId   = $inst.InstanceId
            $state        = $inst.State.Name
            $tenancy      = $inst.Placement.Tenancy.Value
            $currentCores = $inst.CpuOptions.CoreCount
            $currentThreads = $inst.CpuOptions.ThreadsPerCore
            $currentVcpus = $currentCores * $currentThreads
            $isBurstable  = $instanceType -match '^t\d'
            $isHost       = $tenancy -eq 'host'

            # Instance name from tags
            $nameTag = ($inst.Tags | Where-Object { $_.Key -eq 'Name' }).Value
            if (-not $nameTag) { $nameTag = '--' }

            # Get CPU topology for the instance type
            try {
                $cpuInfo = Get-CpuInfo -InstanceTypeName $instanceType -Rgn $rgn
            } catch {
                Write-Warning "Could not get CPU info for $instanceType : $_"
                continue
            }

            $defaultVcpus  = $cpuInfo.VCpuInfo.DefaultVCpus
            $defaultCores  = $cpuInfo.VCpuInfo.DefaultCores
            $defaultThreads = $cpuInfo.VCpuInfo.DefaultThreadsPerCore
            $noSmtVcpus    = $defaultCores  # instance type's default core count at TPC=1
            $isMetal       = $cpuInfo.BareMetal

            # Already has SMT disabled?
            $smtDisabled = $currentThreads -eq 1 -and $defaultThreads -gt 1

            # ── Calculate costs ──
            $defaultCost  = $null
            $noSmtCost    = $null
            $difference   = $null
            $savingsPct   = $null

            if ($isLI -and -not $isBurstable -and -not $isMetal) {
                $perVcpu = $LicenseRates[$instLicense]
                $minBillable = $MinBillableVcpus[$instLicense]
                $noSmtBillableVcpus = [math]::Max($noSmtVcpus, $minBillable)

                if ($isHost) {
                    # Host tenancy: no compute cost, license only (vCPUs × rate)
                    $defaultCost = [math]::Round($defaultVcpus * $perVcpu * $HoursNum, 2)
                    $noSmtCost   = [math]::Round($noSmtBillableVcpus * $perVcpu * $HoursNum, 2)

                    if ($defaultThreads -eq 1) {
                        $noSmtCost  = $defaultCost
                        $difference = 0
                        $savingsPct = 0
                    } else {
                        $difference = [math]::Round($noSmtCost - $defaultCost, 2)
                        $savingsPct = if ($defaultCost -gt 0) {
                            [math]::Round((($defaultCost - $noSmtCost) / $defaultCost) * 100, 1)
                        } else { 0 }
                    }
                    $linuxRate = 0
                } else {
                    # Shared/dedicated tenancy: compute + license
                    $wf = $LicenseFilterMap[$instLicense]
                    if ($wf) {
                        $windowsRate = Get-OnDemandPrice -InstanceTypeName $instanceType `
                                                          -OS $wf.OS -PreInstalledSw $wf.SW `
                                                          -Operation $wf.Op `
                                                          -RegionCode $rgn -PricingRgn $PricingRegion

                        $linuxRate = Get-OnDemandPrice -InstanceTypeName $instanceType `
                                                        -OS 'Linux' -PreInstalledSw 'NA' `
                                                        -Operation 'RunInstances' `
                                                        -RegionCode $rgn -PricingRgn $PricingRegion

                        if ($windowsRate -and $linuxRate) {
                            $defaultCost = [math]::Round($windowsRate * $HoursNum, 2)

                            $noSmtHourly = $linuxRate + ($noSmtBillableVcpus * $perVcpu)
                            $noSmtCost   = [math]::Round($noSmtHourly * $HoursNum, 2)

                            if ($defaultThreads -eq 1) {
                                $noSmtCost  = $defaultCost
                                $difference = 0
                                $savingsPct = 0
                            } else {
                                $difference = [math]::Round($noSmtCost - $defaultCost, 2)
                                $savingsPct = if ($windowsRate -gt 0) {
                                    [math]::Round((($windowsRate - $noSmtHourly) / $windowsRate) * 100, 1)
                                } else { 0 }
                            }
                        }
                    }
                }
            }

            # ── Build notes for this instance ──
            $notes = @()
            if ($isHost)                                          { $notes += '1' }
            if ($defaultThreads -eq 1)                            { $notes += '2' }
            if ($smtDisabled)                                     { $notes += '3' }
            $minBillableCheck = if ($isBurstable) { $MinBillableVcpus[$instLicense] } else { $MinBillableVcpus[$instLicense] }
            if ($noSmtVcpus -lt $minBillableCheck -and $minBillableCheck -gt 1) { $notes += '4' }
            if ($isBurstable)                                     { $notes += '5' }
            if ($isMetal)                                         { $notes += '6' }

            $row = [PSCustomObject]@{
                Region           = $rgn
                InstanceId       = $instanceId
                Name             = $nameTag
                InstanceType     = $instanceType
                State            = $state
                PlatformDetails  = $inst.PlatformDetails
                LicenseType      = $instLicense
                DefaultVCpus     = $defaultVcpus
                CurrentVCpus     = $currentVcpus
                NoSMTvCpus       = $noSmtVcpus
                ThreadsPerCore   = $currentThreads
                SMTDisabled      = $smtDisabled
                DefaultCost      = $defaultCost
                NoSMTCost        = $noSmtCost
                Difference       = $difference
                SavingsPct       = $savingsPct
                Hours            = $HoursNum
                IsBurstable      = $isBurstable
                IsMetal          = $isMetal
                IsHost           = $isHost
                DefaultThreadsPerCore = $defaultThreads
                PerVcpuRate      = if ($isLI -and $LicenseRates[$instLicense]) { $LicenseRates[$instLicense] } else { 0 }
                LinuxRate        = if ($linuxRate) { $linuxRate } else { 0 }
                Notes            = if ($notes.Count -gt 0) { $notes -join ',' } else { '' }
            }
            $results.Add($row)
        }
    }
}

# ── Output ──
Write-Host ""
Write-Host "====================================================================================================" -ForegroundColor Yellow
Write-Host " CPU Threads Per Core (TPC) License Optimization Report for Microsoft License Included EC2 Instances" -ForegroundColor Yellow
Write-Host "====================================================================================================" -ForegroundColor Yellow

if ($results.Count -eq 0) {
    Write-Host "No Windows license-included instances found."
    return
}

Write-Host ""

# Money format
if ($HoursNum -eq 1) {
    $fmtDefault = { if ($null -eq $_.DefaultCost) { '--' } else { '${0:N2}' -f $_.DefaultCost } }
    $fmtNoSMT   = { if ($null -eq $_.NoSMTCost)  { '--' } else { '${0:N2}' -f $_.NoSMTCost } }
    $fmtDiff    = { if ($null -eq $_.Difference) { '--' } elseif ($_.Difference -lt 0) { '-${0:N2}' -f [math]::Abs($_.Difference) } elseif ($_.Difference -eq 0) { '$0.00' } else { '${0:N2}' -f $_.Difference } }
} else {
    $fmtDefault = { if ($null -eq $_.DefaultCost) { '--' } else { '${0:N0}' -f $_.DefaultCost } }
    $fmtNoSMT   = { if ($null -eq $_.NoSMTCost)  { '--' } else { '${0:N0}' -f $_.NoSMTCost } }
    $fmtDiff    = { if ($null -eq $_.Difference) { '--' } elseif ($_.Difference -lt 0) { '-${0:N0}' -f [math]::Abs($_.Difference) } elseif ($_.Difference -eq 0) { '$0' } else { '${0:N0}' -f $_.Difference } }
}

$cols = @(
    @{N='Region'; E={
        $r = $_.Region
        $r = $r -replace 'us-east-',   'use'
        $r = $r -replace 'us-west-',   'usw'
        $r = $r -replace 'eu-west-',   'euw'
        $r = $r -replace 'eu-central-','euc'
        $r = $r -replace 'eu-north-',  'eun'
        $r = $r -replace 'eu-south-',  'eus'
        $r = $r -replace 'ap-northeast-','apne'
        $r = $r -replace 'ap-southeast-','apse'
        $r = $r -replace 'ap-south-',  'aps'
        $r = $r -replace 'ca-central-','cac'
        $r = $r -replace 'sa-east-',   'sae'
        $r = $r -replace 'me-south-',  'mes'
        $r = $r -replace 'af-south-',  'afs'
        $r
    }},
    'InstanceId',
    @{N='Name'; E={ if ($_.Name.Length -gt 19) { $_.Name.Substring(0,19) } else { $_.Name } }},
    'InstanceType'
)
if ($ShowState) { $cols += 'State' }
$cols += @(
    'LicenseType',
    @{N='Cores'; E={$_.NoSMTvCpus}; Align='Right'},
    @{N='TPC'; E={$_.ThreadsPerCore}; Align='Right'},
    @{N='vCPUs'; E={$_.CurrentVCpus}; Align='Right'},
    @{N='Hours'; E={$_.Hours}; Align='Right'},
    @{N=' Default $'; E=$fmtDefault; Align='Right'},
    @{N='  TPC=1 $'; E=$fmtNoSMT;  Align='Right'},
    @{N=' Savings $'; E=$fmtDiff;   Align='Right'},
    @{N=' Savings %';  E={ if ($null -eq $_.SavingsPct) { '--' } else { '{0:N1}%' -f $_.SavingsPct } }; Align='Right'},
    @{N='Note'; E={$_.Notes}}
)

$results | Sort-Object Region, LicenseType, { $_.DefaultCost } -Descending | Format-Table -Property $cols

# Summary
$potential   = $results | Where-Object { -not $_.SMTDisabled -and $_.Difference -and $_.Difference -lt 0 }

$totalDefault = ($results | Where-Object { $_.DefaultCost } | Measure-Object -Property DefaultCost -Sum).Sum
$totalNoSMT   = ($results | Where-Object { $_.NoSMTCost }  | Measure-Object -Property NoSMTCost -Sum).Sum
$totalDiff    = $totalNoSMT - $totalDefault

# Calculate "already saving" for instances at TPC=1 where TPC=2 is valid
$alreadySaving = 0
foreach ($r in $results) {
    if ($r.SMTDisabled -and $r.DefaultThreadsPerCore -eq 2 -and $r.LinuxRate -gt 0) {
        $minBillable = $MinBillableVcpus[$r.LicenseType]
        $tpc2Vcpus = [math]::Max($r.NoSMTvCpus * 2, $minBillable)
        $tpc2Hourly = $r.LinuxRate + ($tpc2Vcpus * $r.PerVcpuRate)
        $tpc1Hourly = $r.LinuxRate + ([math]::Max($r.NoSMTvCpus, $minBillable) * $r.PerVcpuRate)
        $alreadySaving += ($tpc1Hourly - $tpc2Hourly) * $HoursNum
    }
}
$alreadySaving = [math]::Round($alreadySaving, 0)
$newSavings    = if ($potential) { ($potential | Measure-Object -Property Difference -Sum).Sum } else { 0 }

Write-Host ("Total cost with Default TPC Setting: {0,12:C0}" -f $totalDefault)
Write-Host ("Total cost if TPC set to 1:          {0,12:C0}" -f $totalNoSMT)
Write-Host ("Cost Difference:                     {0,12:C0}" -f $totalDiff)
if ($totalDefault -gt 0) {
    Write-Host ("Percent Savings:                     {0,11:N1}%" -f ((($totalDefault - $totalNoSMT) / $totalDefault) * 100))
}
Write-Host ""
Write-Host ("Already saving with TPC=1:           {0,12:C0}" -f $alreadySaving)
Write-Host ("Potential new savings:               {0,12:C0}" -f $newSavings)
Write-Host ("* All figures are per $HoursNum hours.")

# Footnotes — only show notes that appear in the results
$allNotes = ($results | Where-Object { $_.Notes } | ForEach-Object { $_.Notes -split ',' }) | Sort-Object -Unique
$noteDescriptions = @{
    '1' = 'Dedicated Host — only licensing costs were calculated (no instance compute cost)'
    '2' = 'Instance type defaults to TPC=1 — no SMT to disable, savings = 0%'
    '3' = 'Already running with TPC=1 (SMT disabled)'
    '4' = 'SQL Server Standard/Enterprise minimum 4-vCPU billing applies'
    '5' = 'T-series (burstable) — Optimize CPUs not applicable'
    '6' = '.metal — Optimize CPUs not applicable'
}
if ($allNotes.Count -gt 0) {
    Write-Host ""
    foreach ($n in $allNotes) {
        if ($noteDescriptions.ContainsKey($n)) {
            Write-Host "  $n = $($noteDescriptions[$n])" -ForegroundColor Yellow
        }
    }
}

# CSV export
if ($csvPath) {
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Force
    Write-Host ""
    Write-Host "Results exported to $csvPath"
}

# HTML export
if ($htmlPath) {
    $css = @"
<style>
    body { font-family: Consolas, monospace; background: #1e1e1e; color: #d4d4d4; padding: 20px; }
    h1 { color: #dcdcaa; }
    table { border-collapse: collapse; width: 100%; }
    th { background: #264f78; color: #fff; padding: 6px 10px; text-align: left; }
    td { padding: 4px 10px; border-bottom: 1px solid #333; }
    tr:hover { background: #2a2d2e; }
    .tpc2 { background: #4e3a1a; }
    .savings { color: #4ec9b0; }
    .summary { margin-top: 20px; font-size: 14px; width: auto; }
    .summary td { border: none; padding: 2px 6px; white-space: nowrap; }
    .disclaimer { margin-top: 20px; font-size: 14px; color: #d4d4d4; line-height: 1.6; }
</style>
"@

    $htmlRows = foreach ($r in ($results | Sort-Object Region, LicenseType, { $_.DefaultCost } -Descending)) {
        $rowClass = if ($r.ThreadsPerCore -eq 2) { ' class="tpc2"' } else { '' }
        $defaultFmt = if ($null -eq $r.DefaultCost) { '--' } else { '${0:N0}' -f $r.DefaultCost }
        $noSmtFmt   = if ($null -eq $r.NoSMTCost)  { '--' } else { '${0:N0}' -f $r.NoSMTCost }
        $diffFmt    = if ($null -eq $r.Difference) { '--' } elseif ($r.Difference -lt 0) { '-${0:N0}' -f [math]::Abs($r.Difference) } elseif ($r.Difference -eq 0) { '$0' } else { '${0:N0}' -f $r.Difference }
        $savFmt     = if ($null -eq $r.SavingsPct) { '--' } else { '{0:N1}%' -f $r.SavingsPct }
        $name       = if ($r.Name.Length -gt 19) { $r.Name.Substring(0,19) } else { $r.Name }
        $noteFmt    = if ($r.Notes) { $r.Notes } else { '' }
        "<tr$rowClass><td>$($r.Region)</td><td>$($r.InstanceId)</td><td>$name</td><td>$($r.InstanceType)</td><td>$($r.State)</td><td>$($r.LicenseType)</td><td align='right'>$($r.NoSMTvCpus)</td><td align='right'>$($r.ThreadsPerCore)</td><td align='right'>$($r.CurrentVCpus)</td><td align='right'>$($r.Hours)</td><td align='right'>$defaultFmt</td><td align='right'>$noSmtFmt</td><td align='right'>$diffFmt</td><td align='right'>$savFmt</td><td>$noteFmt</td></tr>"
    }

    $noteRows = foreach ($n in $allNotes) {
        if ($noteDescriptions.ContainsKey($n)) { "<tr><td>$n</td><td>$($noteDescriptions[$n])</td></tr>" }
    }

    $html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>TPC Licensing Report</title>$css</head><body>
<h1>CPU Threads Per Core (TPC) Licensing Report for Microsoft License Included EC2 Instances</h1>
<table>
<tr><th>Region</th><th>InstanceId</th><th>Name</th><th>InstanceType</th><th>State</th><th>LicenseType</th><th>Cores</th><th>TPC</th><th>vCPUs</th><th>Hours</th><th>Default $</th><th>TPC=1 $</th><th>Savings $</th><th>Savings %</th><th>Note</th></tr>
$($htmlRows -join "`n")
</table>
<table class="summary">
<tr><td>Total cost with Default TPC Setting:</td><td>$("{0:C0}" -f $totalDefault)</td></tr>
<tr><td>Total cost if TPC set to 1:</td><td>$("{0:C0}" -f $totalNoSMT)</td></tr>
<tr><td>Cost Difference:</td><td>$("{0:C0}" -f $totalDiff)</td></tr>
<tr><td>Percent Savings:</td><td>$("{0:N1}%" -f ((($totalDefault - $totalNoSMT) / $totalDefault) * 100))</td></tr>
<tr><td>&nbsp;</td><td></td></tr>
<tr><td>Already saving with TPC=1:</td><td>$("{0:C0}" -f $alreadySaving)</td></tr>
<tr><td>Potential new savings:</td><td>$("{0:C0}" -f $newSavings)</td></tr>
<tr><td>All figures are per $HoursNum hours.</td><td></td></tr>
</table>
$(if ($noteRows) { "<table class='summary'><tr><th>Note</th><th>Description</th></tr>`n$($noteRows -join "`n")`n</table>" })
<div class="disclaimer">
Default $ and TPC=1 $ are based on On-Demand pricing.<br>
Savings $ is the same regardless of pricing model (On-Demand, Savings Plans, etc.) since per-vCPU license rates are fixed.<br>
Note: Reserved Instances may not apply discounts with Optimize CPUs &mdash; use Savings Plans instead.<br>
See: <a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html" style="color:#569cd6;">https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html</a><br><br>
Scanned $($regions.Count) region(s). Found $($results.Count) Windows instance(s).
</div>
</body></html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding utf8 -Force
    Write-Host ""
    Write-Host "HTML report exported to $htmlPath"
}

Write-Host ""
Write-Host "Scanned $($regions.Count) region(s). Found $($results.Count) Windows instance(s)."
Write-Host ""
Write-Host "Default $ and TPC=1 $ are based on On-Demand pricing." -ForegroundColor Cyan
Write-Host "Savings $ is the same regardless of pricing model (On-Demand, Savings Plans, etc.) since" -ForegroundColor Cyan
Write-Host "   per-vCPU license rates are fixed." -ForegroundColor Cyan
Write-Host "Note: Reserved Instances may not apply discounts with Optimize CPUs — use Savings Plans instead." -ForegroundColor Cyan
Write-Host "See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html" -ForegroundColor Cyan
Write-Host "====================================================================================================" -ForegroundColor Yellow
