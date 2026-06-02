<#
.SYNOPSIS
    Calculates EC2 Windows instance costs when using Optimize CPUs (ThreadsPerCore = 1).

.DESCRIPTION
    Compares the standard Windows/SQL On-Demand hourly cost against the Optimize CPUs
    cost when ThreadsPerCore is set to 1 (hyperthreading disabled).

    Standard billing (no Optimize CPUs):
      Single combined rate = Windows or Windows+SQL On-Demand price per hour

    Optimize CPUs billing (ThreadsPerCore = 1):
      Line 1: Amazon Linux On-Demand rate (base compute cost)
      Line 2: Active vCPUs x per-vCPU license rate

    With ThreadsPerCore = 1, active vCPUs = DefaultCores (typically half the
    default vCPU count on instances that default to 2 threads per core).

    Per-vCPU license rates (from AWS docs):
      Windows Server:                       $0.046/vCPU-hr
      Windows Server with SQL Server Web:   $0.063/vCPU-hr
      Windows Server with SQL Server Std:   $0.166/vCPU-hr
      Windows Server with SQL Server Ent:   $0.421/vCPU-hr

    Default $ is based on On-Demand pricing. Savings $ is the same regardless of
    pricing model (On-Demand, Savings Plans) since per-vCPU license rates are fixed.
    Reserved Instances may not apply discounts with Optimize CPUs — use Savings Plans.

.PARAMETER Region
    AWS region to query pricing for. Defaults to us-east-1.

.PARAMETER InstanceType
    One or more EC2 instance type names (e.g. m8i.16xlarge) or family prefixes
    (e.g. m8i) to expand all sizes in the family. Accepts pipeline input.
    Default: m8i.16xlarge

.PARAMETER Size
    Filter expanded results to a specific size (e.g. 16xlarge, 4xlarge, xlarge).
    Use with family prefixes to compare across families at a given size.
    Example: -InstanceType m,r -Size 16xlarge

.PARAMETER LicenseType
    Which Windows license(s) to calculate. Accepts one or more of:
      Windows, SQLWeb, SQLStandard, SQLEnterprise, SQL (all 3 SQL editions), All (all 4)
    Defaults to Windows.

.PARAMETER Hours
    Number of hours to calculate costs for, or 'month' (730) / 'year' (8760).
    Defaults to 730.

.PARAMETER OutputCsv
    Optional path to export results as CSV.

.EXAMPLE
    .\Show-OptimizedCpuCost.ps1
    Run with defaults (m8i.16xlarge, Windows, 730 hours).

.EXAMPLE
    .\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge, m8i.32xlarge -LicenseType SQLEnterprise

.EXAMPLE
    .\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -LicenseType All
    Compare all four license types for a single instance type.

.EXAMPLE
    .\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -LicenseType SQL
    Compare SQL Web, Standard, and Enterprise for a single instance type.

.EXAMPLE
    .\Show-OptimizedCpuCost.ps1 -InstanceType m8i -LicenseType SQLEnterprise
    Show all m8i family sizes with SQL Server Enterprise pricing.

.EXAMPLE
    .\Show-OptimizedCpuCost.ps1 -InstanceType m8i.16xlarge -Region us-west-2 -Memory -OutputCsv results.csv

.NOTES
    Author: Craig Cooley (coolcrai@amazon.com)
    Built with: Kiro IDE + Claude Opus 4.6
    Date: March 2026

    Requires AWS Tools for PowerShell:
      - AWS.Tools.EC2
      - AWS.Tools.Pricing
    The Pricing API is only available in us-east-1 and ap-south-1.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string[]]$InstanceType = @('m8i.16xlarge'),

    [string]$Size,

    [ValidateSet("Windows", "SQLWeb", "SQLStandard", "SQLEnterprise", "SQL", "All")]
    [string[]]$LicenseType = @("Windows"),

    [string]$Region = "us-east-1",

    [string]$Hours = "730",

    [string]$OutputCsv,

    [switch]$Memory,

    [ValidateSet("SavingsPct", "Savings", "Default", "TPC1", "InstanceType", "vCPUs", "Cores")]
    [string[]]$SortBy = @("SavingsPct")
)

begin {
    # ── Resolve -Hours shorthand ──
    $HoursNum = switch ($Hours.ToLower()) {
        'month'  { 730 }
        'year'   { 8760 }
        default  {
            if ($Hours -as [int]) { [int]$Hours }
            else { throw "Invalid -Hours value '$Hours'. Use a number, 'month', or 'year'." }
        }
    }

    # ── Per-vCPU license rates (from AWS Optimize CPUs docs) ──
    $LicenseRates = @{
        "Windows"        = 0.046
        "SQLWeb"         = 0.063
        "SQLStandard"    = 0.166
        "SQLEnterprise"  = 0.421
    }

    # ── Pricing API filter values per license type ──
    # Operation codes identify the exact license-included SKU
    $LicenseFilterMap = @{
        "Windows"        = @{ OS = "Windows"; SW = "NA";      Op = "RunInstances:0002" }
        "SQLWeb"         = @{ OS = "Windows"; SW = "SQL Web"; Op = "RunInstances:0202" }
        "SQLStandard"    = @{ OS = "Windows"; SW = "SQL Std"; Op = "RunInstances:0006" }
        "SQLEnterprise"  = @{ OS = "Windows"; SW = "SQL Ent"; Op = "RunInstances:0102" }
    }

    # ── Minimum default vCPUs required to launch per license type ──
    # Enterprise: 4 vCPU minimum on all families
    # Standard: 4 vCPU minimum on T-series only
    # Web/Windows: no restriction
    $MinVcpuMap = @{
        "Windows"        = 1
        "SQLWeb"         = 1
        "SQLStandard"    = 1
        "SQLEnterprise"  = 4
    }
    $MinVcpuTseriesMap = @{
        "Windows"        = 1
        "SQLWeb"         = 1
        "SQLStandard"    = 4
        "SQLEnterprise"  = 4
    }

    # ── Expand license type shortcuts ──
    $expandedLicenseTypes = @()
    foreach ($lt in $LicenseType) {
        switch ($lt) {
            'All' { $expandedLicenseTypes += @('Windows', 'SQLWeb', 'SQLStandard', 'SQLEnterprise') }
            'SQL' { $expandedLicenseTypes += @('SQLWeb', 'SQLStandard', 'SQLEnterprise') }
            default { $expandedLicenseTypes += $lt }
        }
    }
    # Preserve intended order: Windows first, then SQL Web → Standard → Enterprise
    $licenseOrder = @('Windows', 'SQLWeb', 'SQLStandard', 'SQLEnterprise')
    $expandedLicenseTypes = $licenseOrder | Where-Object { $_ -in $expandedLicenseTypes }

    # Pricing API only works from us-east-1 or ap-south-1
    $PricingRegion = "us-east-1"

    $results = [System.Collections.Generic.List[PSObject]]::new()
    $isFamilyQuery = $false

    # ── Helper: query Pricing API for On-Demand hourly rate ──
    # Uses regionCode filter (works for any region, no location name mapping needed).
    # Filters on capacitystatus=Used, then takes the max non-zero price.
    function Get-OnDemandPrice {
        param(
            [string]$InstanceTypeName,
            [string]$OS,
            [string]$PreInstalledSw,
            [string]$Operation,
            [string]$RegionCode,
            [string]$PricingRgn
        )

        $filters = @(
            @{ Type = "TERM_MATCH"; Field = "instanceType";    Value = $InstanceTypeName },
            @{ Type = "TERM_MATCH"; Field = "regionCode";      Value = $RegionCode },
            @{ Type = "TERM_MATCH"; Field = "operatingSystem";  Value = $OS },
            @{ Type = "TERM_MATCH"; Field = "preInstalledSw";  Value = $PreInstalledSw },
            @{ Type = "TERM_MATCH"; Field = "tenancy";         Value = "Shared" },
            @{ Type = "TERM_MATCH"; Field = "operation";       Value = $Operation }
        )

        $raw = Get-PLSProduct -ServiceCode AmazonEC2 -Filter $filters -Region $PricingRgn -ErrorAction SilentlyContinue
        $prices = @()

        foreach ($jsonStr in $raw) {
            $product = $jsonStr | ConvertFrom-Json

            # Only consider "Used" capacity (skip "AllocatedCapacityReservation" etc.)
            if ($product.product.attributes.capacitystatus -ne 'Used') { continue }

            $onDemand = $product.terms.OnDemand
            if (-not $onDemand) { continue }

            $skuTerm = $onDemand.PSObject.Properties.Value | Select-Object -First 1
            $usd = $skuTerm.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1
            if ($usd -and [decimal]$usd -gt 0) {
                $prices += [decimal]$usd
            }
        }

        if ($prices.Count -gt 0) {
            return ($prices | Measure-Object -Maximum).Maximum
        }
        return $null
    }
}

process {
    # ── Expand family prefixes (e.g. "m8i" → all m8i.* sizes) ──
    $expandedTypes = @()
    foreach ($type in $InstanceType) {
        if ($type -notmatch '\.' -or $type -match '[\*\?]') {
            $isFamilyQuery = $true
            $prefix = $type -replace '[\.\*\?]+$',''
            Write-Verbose "Expanding family prefix '$prefix' ..."
            try {
                $filters = @(@{Name='instance-type'; Values="${prefix}*.*"})
                $filters += @{Name='processor-info.supported-architecture'; Values='x86_64'}
                $familyTypes = Get-EC2InstanceType -Filter $filters -Region $Region |
                    Where-Object { $prefix.Length -le 1 -or $_.InstanceType.Value -match "^${prefix}[\.\-]" } |
                    Select-Object -ExpandProperty InstanceType |
                    Sort-Object { [regex]::Match($_, '\.(\d+)').Groups[1].Value -as [int] }
                if ($familyTypes) {
                    $expandedTypes += $familyTypes
                } else {
                    Write-Warning "No instance types found for family '$type' in $Region."
                }
            }
            catch {
                Write-Warning "Could not expand family '$type' in $Region : $_"
            }
        } else {
            $expandedTypes += $type
        }
    }

    # ── Filter by -Size if specified ──
    if ($Size) {
        $expandedTypes = $expandedTypes | Where-Object { $_ -match "\.$Size$" }
        if ($expandedTypes.Count -eq 0) {
            Write-Warning "No instance types match size '$Size'."
            return
        }
    }

    foreach ($type in $expandedTypes) {
        Write-Verbose "Processing $type ..."

        # Flag burstable (T-series) instances — Optimize CPUs billing doesn't apply
        $isBurstable = $type -match '^t\d'

        # ── 1. Get CPU info from EC2 DescribeInstanceTypes ──
        try {
            $info = Get-EC2InstanceType -InstanceType $type -Region $Region
        }
        catch {
            Write-Warning "Could not describe instance type '$type' in $Region : $_"
            continue
        }

        $defaultVcpus       = $info.VCpuInfo.DefaultVCpus
        $defaultCores       = $info.VCpuInfo.DefaultCores
        $defaultThreads     = $info.VCpuInfo.DefaultThreadsPerCore
        $validThreads       = $info.VCpuInfo.ValidThreadsPerCore
        $memoryMiB          = $info.MemoryInfo.SizeInMiB
        $isMetal            = $info.BareMetal

        # Check if ThreadsPerCore = 1 is supported
        if ($validThreads -and $validThreads -notcontains 1) {
            Write-Warning "$type does not support ThreadsPerCore = 1. Skipping."
            continue
        }

        # Active vCPUs when ThreadsPerCore = 1
        $optimizedVcpus = $defaultCores

        # ── 2. Get the Amazon Linux base rate (same for all license types) ──
        $linuxRate = $null
        if (-not $isBurstable -and -not $isMetal) {
            $linuxRate = Get-OnDemandPrice -InstanceTypeName $type `
                                            -OS "Linux" `
                                            -PreInstalledSw "NA" `
                                            -Operation "RunInstances" `
                                            -RegionCode $Region `
                                            -PricingRgn $PricingRegion
            if ($null -eq $linuxRate) {
                Write-Warning "No Linux pricing found for $type in $Region. Skipping."
                continue
            }
        }

        # ── 3. Loop over each license type ──
        foreach ($licType in $expandedLicenseTypes) {
            $PerVcpuRate     = $LicenseRates[$licType]
            $WinFilter       = $LicenseFilterMap[$licType]
            $MinVcpus        = $MinVcpuMap[$licType]
            $MinVcpusTseries = $MinVcpuTseriesMap[$licType]

            $effectiveMinVcpus = if ($isBurstable) { $MinVcpusTseries } else { $MinVcpus }
            $isTooSmall = $defaultVcpus -lt $effectiveMinVcpus

            if ($isTooSmall) {
                $tooSmallNotes = @('4')
                if ($isBurstable) { $tooSmallNotes += '3' }
                if ($isMetal) { $tooSmallNotes += '5' }
                $results.Add([PSCustomObject]@{
                    InstanceType = $type; MemoryGiB = [math]::Round($memoryMiB / 1024, 1)
                    DefaultVCpus = $defaultVcpus; NoSMTvCpus = $defaultCores; DefaultTPC = $defaultThreads
                    LicenseType = $licType; DefaultCost = $null; NoSMTCost = $null
                    Difference = $null; SavingsPct = $null; Hours = $HoursNum
                    IsBurstable = $isBurstable; IsTooSmall = $true
                    Notes = ($tooSmallNotes | Sort-Object) -join ','
                })
                continue
            }

            $billableVcpus = [math]::Max($optimizedVcpus, $effectiveMinVcpus)
            $hasMinBilling = $optimizedVcpus -lt $effectiveMinVcpus -and $effectiveMinVcpus -gt 1

            # Get the standard Windows/SQL combined On-Demand rate
            $windowsRate = Get-OnDemandPrice -InstanceTypeName $type `
                                              -OS $WinFilter.OS `
                                              -PreInstalledSw $WinFilter.SW `
                                              -Operation $WinFilter.Op `
                                              -RegionCode $Region `
                                              -PricingRgn $PricingRegion

            if ($null -eq $windowsRate) {
                Write-Warning "No $licType pricing found for $type in $Region. Skipping."
                continue
            }

            $standardHourly = $windowsRate
            $standardTotal  = $standardHourly * $HoursNum

            # Burstable or .metal: show Default cost only, NoSMT not applicable
            if ($isBurstable -or $isMetal) {
                $note = if ($isBurstable) { '3' } else { '5' }
                $results.Add([PSCustomObject]@{
                    InstanceType = $type; MemoryGiB = [math]::Round($memoryMiB / 1024, 1)
                    DefaultVCpus = $defaultVcpus; NoSMTvCpus = $defaultCores; DefaultTPC = $defaultThreads
                    LicenseType = $licType; DefaultCost = [math]::Round($standardTotal, 2)
                    NoSMTCost = $null; Difference = $null; SavingsPct = $null
                    Hours = $HoursNum; IsBurstable = $isBurstable; IsTooSmall = $false; Notes = $note
                })
                continue
            }

            # ── 4. Calculate costs ──
            $licenseFeeHourly = $billableVcpus * $PerVcpuRate
            $optimizedHourly  = $linuxRate + $licenseFeeHourly
            $optimizedTotal   = $optimizedHourly * $HoursNum

            $diffTotal  = $optimizedTotal - $standardTotal
            $savingsPct = if ($standardHourly -gt 0) { (($standardHourly - $optimizedHourly) / $standardHourly) * 100 } else { 0 }

            # No SMT to disable — force zero difference
            if ($defaultVcpus -eq $optimizedVcpus) {
                $optimizedTotal = $standardTotal
                $diffTotal  = 0
                $savingsPct = 0
            }

            $results.Add([PSCustomObject]@{
                InstanceType = $type; MemoryGiB = [math]::Round($memoryMiB / 1024, 1)
                DefaultVCpus = $defaultVcpus; NoSMTvCpus = $optimizedVcpus
                DefaultTPC = $defaultThreads; LicenseType = $licType
                DefaultCost = [math]::Round($standardTotal, 2)
                NoSMTCost = [math]::Round($optimizedTotal, 2)
                Difference = [math]::Round($diffTotal, 2)
                SavingsPct = [math]::Round($savingsPct, 1)
                Hours = $HoursNum; IsBurstable = $false; IsTooSmall = $false
                Notes = $(
                    $n = @()
                    if ($defaultThreads -eq 1) { $n += '1' }
                    if ($hasMinBilling) { $n += '2' }
                    if ($n.Count -gt 0) { $n -join ',' } else { '' }
                )
            })
            Write-Verbose ("{0}/{1}: Standard={2:C4}/hr  Optimized={3:C4}/hr  Savings={4:P1}" -f $type, $licType, $standardHourly, $optimizedHourly, ($savingsPct / 100))
        }
    }
}

end {
    if ($results.Count -eq 0) {
        Write-Warning "No results to display."
        return
    }

    # Sort results — default to NoSMTvCpus ascending for family queries
    $effectiveSortBy = $SortBy
    $propMap = @{
        'SavingsPct'   = 'SavingsPct'
        'Savings'      = 'Difference'
        'Default'      = 'DefaultCost'
        'TPC1'         = 'NoSMTCost'
        'Cores'        = 'NoSMTvCpus'
        'vCPUs'        = 'DefaultVCpus'
        'InstanceType' = 'InstanceType'
    }
    $ascendingKeys = @('InstanceType', 'Cores', 'vCPUs')

    $isMultiLicense = $expandedLicenseTypes.Count -gt 1

    if ($isFamilyQuery -and -not $PSBoundParameters.ContainsKey('SortBy')) {
        # Family query: sort by family prefix, vCPU count, then license order
        $sorted = $results | Sort-Object { ($_.InstanceType -split '\.')[0] }, DefaultVCpus, { $licenseOrder.IndexOf($_.LicenseType) }
    } elseif ($isMultiLicense -and -not $PSBoundParameters.ContainsKey('SortBy')) {
        # Multi-license: sort by instance type, then license order
        $sorted = $results | Sort-Object InstanceType, { $licenseOrder.IndexOf($_.LicenseType) }
    } else {
        $sortExpressions = foreach ($key in $effectiveSortBy) {
            $prop = $propMap[$key]
            $desc = $key -notin $ascendingKeys
            @{ Expression = $prop; Descending = $desc }
        }
        $sorted = $results | Sort-Object $sortExpressions
    }

    # Money format: show cents for hourly, whole dollars otherwise
    if ($HoursNum -eq 1) {
        $fmtDefault = { if ($null -eq $_.DefaultCost) { '--' } else { '${0:N2}' -f $_.DefaultCost } }
        $fmtNoSMT   = { if ($null -eq $_.NoSMTCost) { '--' } else { '${0:N2}' -f $_.NoSMTCost } }
        $fmtDiff    = { if ($null -eq $_.Difference) { '--' } elseif ($_.Difference -lt 0) { '-${0:N2}' -f [math]::Abs($_.Difference) } elseif ($_.Difference -eq 0) { '$0.00' } else { '${0:N2}' -f $_.Difference } }
    } else {
        $fmtDefault = { if ($null -eq $_.DefaultCost) { '--' } else { '${0:N0}' -f $_.DefaultCost } }
        $fmtNoSMT   = { if ($null -eq $_.NoSMTCost) { '--' } else { '${0:N0}' -f $_.NoSMTCost } }
        $fmtDiff    = { if ($null -eq $_.Difference) { '--' } elseif ($_.Difference -lt 0) { '-${0:N0}' -f [math]::Abs($_.Difference) } elseif ($_.Difference -eq 0) { '$0' } else { '${0:N0}' -f $_.Difference } }
    }

    # Console output
    $shortRegion = $Region -replace 'us-east-','use' -replace 'us-west-','usw' -replace 'eu-west-','euw' -replace 'eu-central-','euc' -replace 'eu-north-','eun' -replace 'eu-south-','eus' -replace 'ap-northeast-','apne' -replace 'ap-southeast-','apse' -replace 'ap-south-','aps' -replace 'ca-central-','cac' -replace 'sa-east-','sae' -replace 'me-south-','mes' -replace 'af-south-','afs'
    $cols = @(
        @{N='Region'; E={$shortRegion}},
        'InstanceType'
    )
    $cols += @(
        @{N='LicenseType';   E={$_.LicenseType}},
        @{N='Cores';   E={ if ($null -eq $_.NoSMTvCpus) { '--' } else { $_.NoSMTvCpus } }; Align='Right'},
        @{N='TPC';    E={$_.DefaultTPC}; Align='Right'},
        @{N='vCPUs';  E={$_.DefaultVCpus}; Align='Right'}
    )
    if ($Memory) { $cols += @{N='MemoryGiB'; E={[int]$_.MemoryGiB}; Align='Right'} }
    $cols += @(
        @{N='Hours';         E={$_.Hours};         Align='Right'},
        @{N=' Default $';   E=$fmtDefault;        Align='Right'},
        @{N='  TPC=1 $';   E=$fmtNoSMT;         Align='Right'},
        @{N=' Savings $';  E=$fmtDiff;           Align='Right'},
        @{N='  Savings %';   E={ if ($null -eq $_.SavingsPct) { '--' } else { '{0:N1}%' -f $_.SavingsPct } }; Align='Right'},
        @{N='Note'; E={$_.Notes}}
    )
    $sorted | Format-Table -Property $cols

    # Footnotes — only show notes that appear in the results
    $allNotes = ($results | Where-Object { $_.Notes } | ForEach-Object { $_.Notes -split ',' }) | Sort-Object -Unique
    $noteDescriptions = @{
        '1' = 'Instance type defaults to TPC=1 — no SMT to disable, savings = 0%'
        '2' = 'SQL Server Standard/Enterprise minimum 4-vCPU billing applies'
        '3' = 'T-series (burstable) — Optimize CPUs not applicable'
        '4' = 'Instance too small for selected SQL edition'
        '5' = '.metal — Optimize CPUs not applicable'
    }
    if ($allNotes.Count -gt 0) {
        foreach ($n in $allNotes) {
            if ($noteDescriptions.ContainsKey($n)) {
                Write-Host "  $n = $($noteDescriptions[$n])" -ForegroundColor Yellow
            }
        }
    }

    # CSV export
    if ($OutputCsv) {
        $sorted | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
        Write-Host "Results exported to $OutputCsv"
    }

    # Pricing footnotes
    Write-Host ""
    Write-Host "Default $ is based on On-Demand pricing. " -ForegroundColor Cyan
    Write-Host "Savings $ is the same regardless of pricing model (On-Demand, Savings Plans, etc.) since" -ForegroundColor Cyan
    Write-Host "   per-vCPU license rates are fixed." -ForegroundColor Cyan
    Write-Host "Note: Reserved Instances may not apply discounts with Optimize CPUs — use Savings Plans instead." -ForegroundColor Cyan

    if ($MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) {
        $sorted
    }
}
