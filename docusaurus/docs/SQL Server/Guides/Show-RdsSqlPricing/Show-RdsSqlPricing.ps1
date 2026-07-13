<#
.SYNOPSIS
    Compares RDS for SQL Server instance pricing across families and sizes.

.DESCRIPTION
    Pulls instance pricing from the AWS Pricing API (AmazonRDS), adds unbundled
    SQL Server and Windows license fees for newer generation instances (m7i, m8i, m8a, etc.),
    and displays a consolidated view with physical core counts, network bandwidth, EBS
    throughput, and IOPS (EBS specs match the RDS hardware spec docs).

    Modules required: AWS.Tools.Pricing, AWS.Tools.RDS, AWS.Tools.EC2

.PARAMETER Edition
    SQL Server edition. Valid: Standard, Enterprise, Web, Developer. Default: Standard

.PARAMETER License
    SQL Server licensing model. Valid: LI (License Included, default), BYOM (Bring Your Own Media).
    Under BYOM the output is restricted to BYOM-eligible instances (queried live from the pricing
    catalog for the chosen edition/region — not every unbundled family qualifies) and the SQL Server
    license fee is waived; the Windows OS fee and compute still apply. BYOM is offered for Standard
    and Enterprise editions. See:
    https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/sqlserver-byom.html

.PARAMETER Region
    AWS region code. Default: us-east-1

.PARAMETER Deployment
    Deployment option. Valid: Single-AZ, Multi-AZ. Default: Single-AZ

.PARAMETER Size
    Instance size to filter (e.g. large, xlarge, 2xlarge, 4xlarge, 8xlarge).
    Use 'all' to show all sizes. Default: 8xlarge

.PARAMETER Family
    Instance family filter (e.g. m, r, m7i, m8). Accepts multiple values.
    Matching is prefix-based, so 'r' matches all r-families and 'r5' also matches
    r5b/r5d. Append a trailing dot for an exact family match: 'r5.' matches only
    db.r5.* (not r5b/r5d), and 'r6i.' matches only db.r6i.* (not a hypothetical r6id).
    Omit to show all families.

.PARAMETER ShowBreakdown
    Show individual cost components (Compute, SQL, Win) for unbundled instances.

.PARAMETER DBSP_RI_1y
    Include a 'DBSP_RI_1y' column showing 1-year commitment pricing: Database Savings Plan
    (No Upfront) for unbundled instances, Reserved Instance (1yr No Upfront) for bundled.
    The value is the committed rate scaled by -Hours (per-period, like Price_OD); '1yr' is
    the commitment term, not a 12-month total.

.PARAMETER Hours
    Multiplier for all price columns. Default: 1 (hourly). Use 730 for monthly estimates.
    Display precision scales with the period: hourly = 3 decimals, up to 24h = cents (2 dp),
    above 24h = whole dollars.

.PARAMETER PassThru
    Emit the result objects to the pipeline instead of rendering a formatted table.
    Useful for exporting, e.g. ... -PassThru | Export-Csv pricing.csv -NoTypeInformation

.NOTES
    Recommended: Open AWS CloudShell in the AWS Console and run 'pwsh'.
    All required modules and credentials are pre-configured.
    Modules required: AWS.Tools.Pricing, AWS.Tools.RDS, AWS.Tools.EC2
    Optional (for -DBSP_RI_1y): AWS.Tools.SavingsPlans

    Author: Craig Cooley
    July 2026 - built with Kiro IDE

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Edition Standard -Size 2xlarge -Family m

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Family m8i -Size all

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Edition Enterprise -Size 4xlarge -Family r

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Edition Developer -Size 2xlarge

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Family m8i -Size 4xlarge -ShowBreakdown

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Family r -Size 8xlarge -DBSP_RI_1y

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Family m -Size all -Hours 730 -PassThru | Export-Csv monthly.csv -NoTypeInformation

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Edition Enterprise -Family m8i,r8i -Size 4xlarge -License BYOM -ShowBreakdown

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Deployment Multi-AZ -Size 8xlarge -PassThru | Sort-Object Price_OD | Format-Table -AutoSize
    Sort results by On-Demand price (cheapest first). -PassThru emits objects, so you can also
    Where-Object/Export-Csv. Quote property names with special characters, e.g. Sort-Object 'Max_MB/s'.

.EXAMPLE
    ./Show-RdsSqlPricing.ps1 -Size 8xlarge -PassThru | Where-Object Price_OD -lt 15 | Sort-Object Price_OD | Format-Table -AutoSize
    Filter to instances under $15/hr, sorted by price.
#>
param(
    [ValidateSet('Standard','Enterprise','Web','Developer')]
    [string]$Edition = 'Standard',

    [ValidateSet('LI','BYOM')]
    [string]$License = 'LI',

    [string]$Region = 'us-east-1',

    [ValidateSet('Single-AZ','Multi-AZ')]
    [string]$Deployment = 'Single-AZ',

    [string]$Size = '8xlarge',

    [string[]]$Family,

    [switch]$ShowBreakdown,

    [switch]$DBSP_RI_1y,

    [int]$Hours = 1,

    [switch]$PassThru
)

#region Preflight (modules + credentials)
$requiredModules = @('AWS.Tools.Pricing','AWS.Tools.RDS','AWS.Tools.EC2')
if ($DBSP_RI_1y) { $requiredModules += 'AWS.Tools.SavingsPlans' }
$missingModules = $requiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
if ($missingModules) {
    Write-Error ("Missing required module(s): {0}. Install with: Install-Module {0} -Scope CurrentUser. Note: AWS CloudShell has these preinstalled." -f ($missingModules -join ', '))
    return
}
if ($License -eq 'BYOM' -and $Edition -notin @('Standard','Enterprise')) {
    Write-Warning "BYOM is offered for Standard and Enterprise editions only; '$Edition' figures assume the same SQL-license waiver and may not reflect an orderable configuration."
}
#endregion

#region Instance Pricing
$licenseModel = switch ($Edition) {
    'Developer' { 'NA' }
    default     { 'License included' }
}
try {
    $allProducts = Get-PLSProduct -ServiceCode AmazonRDS -Region us-east-1 `
    -Filter @(
        @{Field='databaseEngine';Type='TERM_MATCH';Value='SQL Server'},
        @{Field='databaseEdition';Type='TERM_MATCH';Value=$Edition},
        @{Field='licenseModel';Type='TERM_MATCH';Value=$licenseModel},
        @{Field='deploymentOption';Type='TERM_MATCH';Value=$Deployment},
        @{Field='regionCode';Type='TERM_MATCH';Value=$Region}
    ) `
    -FormatVersion aws_v1 -ErrorAction Stop |
        ConvertFrom-Json
} catch {
    Write-Error ("Failed to query the AWS Pricing API: {0}`nEnsure AWS credentials are configured (AWS CloudShell provides them automatically) and that '$Region' is a valid region code." -f $_.Exception.Message)
    return
}

# Developer edition: also pull 'Enterprise Developer' (unbundled instances) and merge
if ($Edition -eq 'Developer') {
    $entDevProducts = Get-PLSProduct -ServiceCode AmazonRDS -Region us-east-1 `
    -Filter @(
        @{Field='databaseEngine';Type='TERM_MATCH';Value='SQL Server'},
        @{Field='databaseEdition';Type='TERM_MATCH';Value='Enterprise Developer'},
        @{Field='licenseModel';Type='TERM_MATCH';Value='Bring your own license'},
        @{Field='deploymentOption';Type='TERM_MATCH';Value=$Deployment},
        @{Field='regionCode';Type='TERM_MATCH';Value=$Region}
    ) `
    -FormatVersion aws_v1 |
        ConvertFrom-Json
    $allProducts = @($allProducts) + @($entDevProducts)
}

# Deduplicate by instance type (keep the one with the lower price)
$allProducts = $allProducts | Group-Object { $_.product.attributes.instanceType } | ForEach-Object {
    $_.Group | Sort-Object { [decimal]($_.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1) } | Select-Object -First 1
}

# Families available for this edition/region (before size/family filters) — used to validate -Family.
$availableFamilies = @($allProducts | ForEach-Object { ($_.product.attributes.instanceType -replace 'db\.','') -replace '\.[^.]+$','' } | Sort-Object -Unique)

if ($Size -ne 'all') {
    $allProducts = $allProducts | Where-Object { $_.product.attributes.instanceType -match "\.$Size$" }
}

if ($Family) {
    # Validate each token against real families. A trailing dot = exact family (r5. -> r5 only);
    # otherwise it's a prefix (r -> r4/r5/..., m8 -> m8i/m8a). Anything matching nothing (a typo,
    # or 'all') is rejected with the list of valid families, rather than a misleading empty result.
    $unmatched = @($Family | Where-Object {
        $tok = $_
        if ($tok -match '\.$') { $availableFamilies -notcontains $tok.TrimEnd('.') }
        else                   { -not ($availableFamilies | Where-Object { $_ -like "$tok*" }) }
    })
    if ($unmatched) {
        $allHint = if ($unmatched -contains 'all') { " ('all' is not a family — omit -Family for all families; 'all' is only valid for -Size.)" } else { '' }
        $familyPrefixes = ($availableFamilies | ForEach-Object { $_.Substring(0,1) } | Sort-Object -Unique) -join ', '
        Write-Warning "-Family value(s) not found for $Edition in ${Region}: $($unmatched -join ', ').$allHint`nAvailable family prefixes: $familyPrefixes."
        return
    }
    $familyPattern = ($Family | ForEach-Object {
        if ($_ -match '\.$') {
            # Trailing dot = exact family (e.g. 'r5.' matches db.r5.* but not db.r5b.*)
            "db\.$([regex]::Escape($_.TrimEnd('.')))\."
        } else {
            # Prefix match (e.g. 'r' matches all r-families, 'm8' matches m8i/m8a)
            "db\.$([regex]::Escape($_))"
        }
    }) -join '|'
    $allProducts = $allProducts | Where-Object { $_.product.attributes.instanceType -match $familyPattern }
}

if ($License -eq 'BYOM') {
    # BYOM is only offered on specific instance types (currently m7i, m8i, r7i, r8i) — not on every
    # unbundled family (m8a, r8a, x2m, ...). Restrict to types that actually carry a 'Bring your own
    # media' price for this edition/region so we never show a waiver for a non-orderable configuration.
    $byomSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    (Get-PLSProduct -ServiceCode AmazonRDS -Region us-east-1 -FormatVersion aws_v1 -Filter @(
        @{Field='databaseEngine';Type='TERM_MATCH';Value='SQL Server'},
        @{Field='databaseEdition';Type='TERM_MATCH';Value=$Edition},
        @{Field='licenseModel';Type='TERM_MATCH';Value='Bring your own media'},
        @{Field='regionCode';Type='TERM_MATCH';Value=$Region}
    ) | ConvertFrom-Json).product.attributes.instanceType | ForEach-Object { [void]$byomSet.Add($_) }
    $allProducts = $allProducts | Where-Object { $byomSet.Contains($_.product.attributes.instanceType) }
}

$instances = $allProducts | ForEach-Object { $_.product.attributes.instanceType } | Sort-Object -Unique

if (-not $instances) {
    $filterDesc = "Edition=$Edition, Deployment=$Deployment, Region=$Region"
    if ($Size -ne 'all')   { $filterDesc += ", Size=$Size" }
    if ($Family)           { $filterDesc += ", Family=$($Family -join ',')" }
    if ($License -ne 'LI') { $filterDesc += ", License=$License" }
    $byomHint = ''
    if ($License -eq 'BYOM') {
        $byomFams = @($byomSet | ForEach-Object { ($_ -replace 'db\.','') -replace '\.[^.]+$','' } | Sort-Object -Unique)
        $byomHint = if ($byomFams) { " Under -License BYOM only BYOM-eligible instances are shown; eligible families in $Edition/${Region}: $($byomFams -join ', ')." }
                    else { " No BYOM-eligible instances were found for $Edition in $Region." }
    }
    $msg = "No RDS SQL Server instances matched:`n$filterDesc`nCheck the region code and filters (region availability varies by family/size)."
    if ($byomHint) { $msg += "`n$($byomHint.Trim())" }
    Write-Warning $msg
    return
}
#endregion

#region Core Counts (RDS Orderable Options)
$engineCode = switch ($Edition) {
    'Standard'  { 'sqlserver-se' }
    'Enterprise'{ 'sqlserver-ee' }
    'Developer' { 'sqlserver-ee' }
    'Web'       { 'sqlserver-web' }
}
$coreMap = @{}
$maxCoreMap = @{}
# Query per instance class. A bulk call without -DBInstanceClass returns an enormous
# result set (every class x engine version x AZ group) and can exhaust memory, so we
# scope each call to a single class.
foreach ($cls in $instances) {
    $opts = Get-RDSOrderableDBInstanceOption -Engine $engineCode -DBInstanceClass $cls -Region $Region -ErrorAction SilentlyContinue
    $coreInfo = ($opts | Select-Object -First 1).AvailableProcessorFeatures | Where-Object Name -eq 'coreCount'
    if ($coreInfo) {
        $coreMap[$cls] = [int]$coreInfo.DefaultValue
        $maxCoreMap[$cls] = [int](($coreInfo.AllowedValues -split ',') | Measure-Object -Maximum).Maximum
    }
}
#endregion

#region Unbundled License Fees
# Only unbundled instances carry separate SQL/Windows fees, so skip this lookup entirely
# (one fewer API call) when the result set is all bundled/older-gen.
$sqlLic = 0
$winLic = 0
$hasUnbundled = @($allProducts | Where-Object { $_.product.attributes.unbundledLicensing -eq 'TRUE' }).Count -gt 0
if ($hasUnbundled) {
    $licEdition = if ($Edition -eq 'Developer') { 'Enterprise Developer' } else { $Edition }
    $licFees = Get-PLSProduct -ServiceCode AmazonRDSOCPULicenseFees -Region us-east-1 `
    -Filter @(
        @{Field='databaseEdition';Type='TERM_MATCH';Value=$licEdition},
        @{Field='regionCode';Type='TERM_MATCH';Value=$Region}
    ) -FormatVersion aws_v1 |
        ConvertFrom-Json

    $sqlLic = [decimal]($licFees |
        Where-Object { ($_.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.description) -match 'SQLServer' } |
        ForEach-Object { $_.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD } |
        Select-Object -First 1)

    $winLic = [decimal]($licFees |
        Where-Object { ($_.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.description) -match 'WindowsOS' } |
        ForEach-Object { $_.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD } |
        Select-Object -First 1)

    # License rates came back empty for an edition that has unbundled instances — totals would be understated.
    if ($sqlLic -le 0 -or $winLic -le 0) {
        Write-Warning "Unbundled instances are present but license rates came back empty (SQL=$sqlLic/vCPU-hr, Win=$winLic/vCPU-hr) for edition '$licEdition' in $Region. Price_OD for unbundled instances may be understated."
    }
}
#endregion

#region EC2 EBS Specs (per-instance max bandwidth & IOPS — matches RDS hardware spec docs)
# RDS-exclusive types (e.g. db.x2m) have no EC2 equivalent; their EBS columns stay blank.
$ec2Map = @{}
$ec2Types = @($instances | ForEach-Object { $_ -replace 'db\.','' })
if ($ec2Types) {
    try {
        # Fast path: one call for all types.
        $ec2Results = Get-EC2InstanceType -InstanceType $ec2Types -Region $Region -ErrorAction Stop
        foreach ($ec2 in $ec2Results) { $ec2Map["db.$($ec2.InstanceType.Value)"] = $ec2 }
    } catch {
        # An RDS-exclusive type (no EC2 equivalent) makes the batch call fail as a whole.
        # Fall back to per-type lookups so the valid ones still resolve.
        foreach ($t in $ec2Types) {
            try {
                $ec2 = Get-EC2InstanceType -InstanceType $t -Region $Region -ErrorAction Stop
                $ec2Map["db.$($ec2.InstanceType.Value)"] = $ec2
            } catch {
                # RDS-only instance type with no EC2 equivalent
            }
        }
    }
}
#endregion

#region Savings Plans Rates
$spRateMap = @{}
if ($DBSP_RI_1y) {
    # Build instanceType filter values from the instances we're showing
    $spInstanceFilter = @{ Name = 'instanceType'; Values = @($instances) }
    $spRegionFilter = @{ Name = 'region'; Values = @($Region) }
    $spDescFilter = @{ Name = 'productDescription'; Values = @('SQL Server') }

    $allSpRates = Get-SPSavingsPlansOfferingRate `
        -Product @('RDS') `
        -ServiceCode @('AmazonRDS') `
        -SavingsPlanType @('Database') `
        -SavingsPlanPaymentOption @('No Upfront') `
        -Filter @($spInstanceFilter, $spRegionFilter, $spDescFilter) `
        -Region us-east-1

    # Match usage type pattern by deployment option
    $usagePattern = switch ($Deployment) {
        'Single-AZ' { '^([\w-]*?)InstanceUsage:' }
        'Multi-AZ'  { '^([\w-]*?)MirrorUsage:' }
    }

    foreach ($r in $allSpRates) {
        if ($r.UsageType -match $usagePattern) {
            # Extract instance type from properties (full name with 'xlarge')
            $instType = ($r.Properties | Where-Object Name -eq 'instanceType').Value
            if ($instType -and -not $spRateMap.ContainsKey($instType)) {
                $spRateMap[$instType] = [decimal]$r.Rate
            }
        }
    }
}
#endregion

#region Output
Write-Host ""
Write-Host "Engine: SQL Server | Edition: $Edition | License: $License | Deployment: $Deployment | Region: $Region" -ForegroundColor Cyan
if ($License -eq 'BYOM') {
    Write-Host "BYOM: showing only BYOM-eligible instances - SQL Server license fee waived (Windows OS still charged)." -ForegroundColor DarkGray
}

# Precision by scale: hourly needs sub-cent (3 dp); up to a day (<=24h) shows cents (2 dp);
# larger multipliers (e.g. -Hours 730 for monthly) round to whole dollars (0 dp).
$priceDp = if ($Hours -eq 1) { 3 } elseif ($Hours -le 24) { 2 } else { 0 }

$results = $allProducts | ForEach-Object {
        $vcpu = [int]$_.product.attributes.vcpu
        $instancePrice = [decimal]($_.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1)
        $instance = $_.product.attributes.instanceType
        $isUnbundled = $_.product.attributes.unbundledLicensing -eq 'TRUE'
        $cores = if ($coreMap.ContainsKey($instance)) { $coreMap[$instance] } else { [int]($vcpu / 2) }
        $maxCores = if ($maxCoreMap.ContainsKey($instance)) { $maxCoreMap[$instance] } else { $null }
        $ec2 = $ec2Map[$instance]
        $winMultiplier = if ($Deployment -eq 'Multi-AZ') { 2 } else { 1 }
        $computeHr = $instancePrice
        # BYOM: the customer supplies the SQL Server license, so AWS charges no SQL fee.
        # The Windows OS fee is still charged. Only unbundled instances have separate license fees.
        $sqlLicHr = if ($isUnbundled -and $License -ne 'BYOM') { [Math]::Max(4,$vcpu) * $sqlLic } else { 0 }
        $winLicHr = if ($isUnbundled) { $vcpu * $winLic * $winMultiplier } else { 0 }
        # Unbundled: show the SQL fee (LI) or 0 (BYOM — you bring the license). Bundled: blank (SQL is bundled into compute).
        $sqlHr = if ($isUnbundled) { if ($License -eq 'BYOM') { 0 } else { [Math]::Round($sqlLicHr, 3) } } else { $null }
        $winHr = if ($isUnbundled) { [Math]::Round($winLicHr, 3) } else { $null }

        $obj = [ordered]@{
            Instance     = $instance
            Cores        = $cores
            MaxCores     = if ($maxCores -and $maxCores -ne $cores) { $maxCores } else { $null }
            vCPUs        = $vcpu
            RAM          = [double]($_.product.attributes.memory -replace '[^\d.]','')
            'Network_Gb/s' = $(
                $np = $_.product.attributes.networkPerformance
                # AWS reports this inconsistently: "12.5 Gbps", "10 Gigabit", "15000 Megabit", "15000 Mbps".
                if ($np -match '([\d.]+)\s*(?:Gbps|Gigabit)') {
                    [double]$matches[1]
                } elseif ($np -match '([\d.]+)\s*(?:Mbps|Megabit)') {
                    [double]$matches[1] / 1000
                } else { $null }
            )
            'Max_MB/s'   = if ($ec2) { $ec2.EbsInfo.EbsOptimizedInfo.MaximumThroughputInMBps -as [int] } else { $null }
            Max_IOPS     = if ($ec2) { $ec2.EbsInfo.EbsOptimizedInfo.MaximumIops -as [int] } else { $null }
        }
        if ($ShowBreakdown) {
            # Breakdown only applies to unbundled instances. Bundled/older-gen have a single all-in
            # price (license included) shown in Price_OD, so leave all component columns blank rather
            # than repeat the total under "Compute".
            $obj['Compute'] = if ($isUnbundled) { [Math]::Round($computeHr * $Hours, $priceDp) } else { $null }
            # Use ($null -ne ...) not truthiness: a BYOM SQL charge of 0 is a real value, not "no value".
            $obj['SQL']     = if ($null -ne $sqlHr) { [Math]::Round($sqlHr * $Hours, $priceDp) } else { $null }
            $obj['Win']     = if ($null -ne $winHr) { [Math]::Round($winHr * $Hours, $priceDp) } else { $null }
        }
        $obj['Price_OD'] = if ($isUnbundled) {
            # Multi-AZ: Windows is charged for both nodes, SQL Server only for active node (passive failover rights)
            # https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-rds-sql-server-optimized-cpu-lower-prices/
            [Math]::Round(($computeHr + $sqlLicHr + $winLicHr) * $Hours, $priceDp)
        } else { [Math]::Round($instancePrice * $Hours, $priceDp) }
        if ($DBSP_RI_1y) {
            if ($isUnbundled) {
                # Unbundled: use Database Savings Plan rate (compute only) + licenses
                $spCompute = if ($spRateMap.ContainsKey($instance)) { $spRateMap[$instance] } else { $null }
                $obj['DBSP_RI_1y'] = if ($null -ne $spCompute) {
                    [Math]::Round(($spCompute + $sqlLicHr + $winLicHr) * $Hours, $priceDp)
                } else { $null }
            } else {
                # Bundled: use 1-year No Upfront Reserved Instance price from Pricing API
                $riTerms = $_.terms.Reserved
                $riPrice = $null
                if ($riTerms) {
                    $riTerms.PSObject.Properties.Value | ForEach-Object {
                        $attrs = $_.termAttributes
                        if ($attrs.LeaseContractLength -eq '1yr' -and $attrs.PurchaseOption -eq 'No Upfront') {
                            $dims = $_.priceDimensions.PSObject.Properties.Value
                            $hrDim = $dims | Where-Object { $_.unit -match 'Hrs|Hour' -and [decimal]$_.pricePerUnit.USD -gt 0 }
                            if ($hrDim) { $riPrice = [decimal]$hrDim.pricePerUnit.USD }
                        }
                    }
                }
                $obj['DBSP_RI_1y'] = if ($null -ne $riPrice) { [Math]::Round($riPrice * $Hours, $priceDp) } else { $null }
            }
        }
        # Full family (e.g. r5, r5b, r6i) — everything between 'db.' and the size — so
        # each family groups on its own instead of collapsing to a single letter.
        $obj['Family'] = ($instance -replace 'db\.','') -replace '\.[^.]+$',''

        [PSCustomObject]$obj
    }

# Whole-dollar mode (0 dp): cast price columns to integer so they render as "2009", not "2009.00".
if ($priceDp -eq 0) {
    foreach ($row in $results) {
        foreach ($pc in @('Compute','SQL','Win','Price_OD','DBSP_RI_1y')) {
            if (($row.PSObject.Properties.Name -contains $pc) -and ($null -ne $row.$pc)) {
                $row.$pc = [long]$row.$pc
            }
        }
    }
}

# Sort by family first (keeps each family's rows together for -GroupBy), then by size, then name.
# Rank is derived from the size token so any N-xlarge (incl. 96xlarge) and the small
# t-series sizes (nano/micro/small/medium) order correctly without a hardcoded list.
$sorted = $results | Sort-Object Family, @{Expression={
        $s = ($_.Instance -replace 'db\.\w+\.','')
        switch -Regex ($s) {
            '^nano$'        { 1; break }
            '^micro$'       { 2; break }
            '^small$'       { 3; break }
            '^medium$'      { 4; break }
            '^large$'       { 5; break }
            '^xlarge$'      { 6; break }
            '^(\d+)xlarge$' { 6 + [int]$matches[1]; break }
            default         { 999 }
        }
    }}, Instance

if ($PassThru) {
    # Emit objects to the pipeline for export/further processing.
    $sorted
    return
}

# Right-align every numeric column explicitly. Relying on type inference misaligns columns
# whose first row is $null (e.g. DBSP_RI_1y for a bundled instance, SQL/Win for bundled).
$cols = @(
    'Instance',
    @{N='Cores';        E={$_.Cores};        Alignment='Right'},
    @{N='MaxCores';     E={$_.MaxCores};     Alignment='Right'},
    @{N='vCPUs';        E={$_.vCPUs};        Alignment='Right'},
    @{N='RAM_GiB';      E={$_.RAM};          Alignment='Right'},
    @{N='Network_Gb/s'; E={$_.'Network_Gb/s'}; Alignment='Right'},
    @{N='Max_MB/s';     E={$_.'Max_MB/s'};     Alignment='Right'},
    @{N='Max_IOPS';     E={$_.Max_IOPS};       Alignment='Right'}
)
if ($ShowBreakdown) {
    $cols += @{N='Compute'; E={$_.Compute}; Alignment='Right'}
    $cols += @{N='SQL';     E={$_.SQL};     Alignment='Right'}
    $cols += @{N='Win';     E={$_.Win};     Alignment='Right'}
}
$cols += @{N='Price_OD'; E={$_.Price_OD}; Alignment='Right'}
if ($DBSP_RI_1y) { $cols += @{N='DBSP_RI_1y'; E={$_.DBSP_RI_1y}; Alignment='Right'} }
# Always show the Hrs multiplier so the period is explicit (columns no longer carry an _hr suffix).
$cols += @{N='Hrs'; E={ $Hours }; Alignment='Right'}

# Group by family only for -Size all (many sizes per family). For a specific size each
# family is a single row, so grouping just repeats headers — show one flat table instead.
if ($Size -eq 'all') {
    $sorted | Format-Table -Property $cols -AutoSize -GroupBy Family
} else {
    $sorted | Format-Table -Property $cols -AutoSize
}
#endregion
