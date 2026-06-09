<#
.SYNOPSIS
    Create an On-Demand Capacity Reservation (ODCR) across regions.

.DESCRIPTION
    Finds available capacity for the specified instance type by attempting to
    create an ODCR in each region/AZ in priority order. Supports three modes:
    - Parallel (default): fires all AZs simultaneously, lets you pick which to keep
    - Sequential (-Sequential): tries AZs one at a time, stops on first success
    - TargetQuantity (-TargetQuantity): accumulates capacity by creating and expanding
      ODCRs across AZs until a target is reached. Expands existing matching CRs
      before creating new ones to minimize total reservations.

.PARAMETER InstanceType
    EC2 instance type to reserve (required).

.PARAMETER OS
    Instance platform for the reservation (required): Windows or Linux.

.PARAMETER Quantity
    Number of instances per ODCR attempt / increment size for -TargetQuantity (default: 1).

.PARAMETER Region
    Optional. One or more specific regions to try (e.g. us-east-1 or us-east-1,us-east-2).
    Overrides -RegionGroup. Cannot be combined with -Zone.

.PARAMETER Zone
    Optional. One or more specific AZs to try. Accepts AZ names (us-east-1a,us-east-2b)
    or zone IDs (use1-az1,use2-az2). Overrides -Region and -RegionGroup.
    Cannot be combined with -Region or -RegionGroup.

.PARAMETER Sequential
    Switch. Tries AZs one at a time instead of simultaneously (default is parallel).
    Stops on first success. No interactive selection.

.PARAMETER TargetQuantity
    Target total number of instances to accumulate across AZs. Creates an ODCR
    in the first available AZ, expands it in increments of -Quantity until
    insufficient capacity, then moves to the next AZ. Expands existing matching
    CRs before creating new ones. Requires -Region or -Zone.

.PARAMETER TargetTimeout
    Maximum seconds to spend accumulating capacity in -TargetQuantity mode (default: 30).
    Retries all AZs at the interval specified by -TargetQuantityInterval.

.PARAMETER TargetQuantityInterval
    Seconds between retry attempts in -TargetQuantity mode (default: 10).

.PARAMETER InstanceMatchCriteria
    open (default): any matching instance in the AZ automatically uses the reservation.
    targeted: only instances that explicitly specify the CR ID use it.

.PARAMETER CapacityReservationId
    Optional. Target a specific existing CR for expansion with -TargetQuantity.
    Skips region/AZ discovery and directly expands the specified CR.
    Requires -TargetQuantity and -Region (to identify the CR's region).

.PARAMETER RegionGroup
    Which region group to try: us, us+, eu, ap, or all (default).
    us  = US regions only
    us+ = US + CA + SA + MX (Americas)
    eu  = EU regions only
    ap  = AP regions only
    all = All regions

.NOTES
    Author: Craig Cooley ([email])
    Built with: Kiro IDE + Claude Opus 4.6
    Requires: AWS.Tools.EC2, AWS.Tools.Pricing (for pricing + Windows validation), PowerShell 7+
    Recommended: Run in AWS CloudShell

    You are billed at the on-demand rate from the moment the ODCR is created,
    even if no instance is running in it. Remember to cancel when done.

    Since VPCs, subnets, AMIs, keys, and security groups are regional, this
    script only reserves capacity. You then launch your instance into the
    ODCR with full control over all regional resources.
    See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html

    To run in AWS CloudShell:
        1. Open AWS CloudShell from the AWS Console
        2. Launch PowerShell 7:
            pwsh
        3. Run the script (use Tab to auto-complete parameters and values):
            .\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType g7e.2xlarge -RegionGroup us
            .\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType g6e.2xlarge -Region us-east-2 -TargetQuantity 10 -TargetTimeout 600

.EXAMPLE
    .\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType g7e.2xlarge -RegionGroup us
    Creates Windows ODCRs for g7e.2xlarge in US regions, prompts which to keep or cancel

.EXAMPLE
    .\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType p5.4xlarge -RegionGroup all
    Creates Windows ODCRs for p5.4xlarge across all regions, prompts which to keep or cancel

.EXAMPLE
    .\FindEC2Capacity_ODCR.ps1 -OS Linux -InstanceType i4i.metal -Quantity 4 -Region us-east-1,us-east-2
    Creates Linux ODCRs for 4x i4i.metal in us-east-1 or us-east-2, prompts which to keep or cancel

.EXAMPLE
    .\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType g6e.4xlarge -RegionGroup all -Sequential
    Tries AZs one at a time, stops on first success

.EXAMPLE
    .\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType g6e.2xlarge -Region us-east-2 -TargetQuantity 10 -TargetTimeout 600
    Accumulates 10 slots by creating and expanding ODCRs across AZs in us-east-2 (10 min timeout)
#>

Param (
    [Parameter(Mandatory)]
    [string]$InstanceType,
    [Parameter(Mandatory)]
    [ValidateSet("Windows", "Linux")]
    [string]$OS,
    [int]$Quantity = 1,
    [int]$TargetQuantity,
    [int]$TargetTimeout = 30,
    [int]$TargetQuantityInterval = 10,
    [switch]$Sequential,
    [string[]]$Region,
    [string[]]$Zone,
    [ValidateSet("open", "targeted")]
    [string]$InstanceMatchCriteria = "open",
    [string]$CapacityReservationId,
    [ValidateSet("us", "us+", "eu", "ap", "all")]
    [string]$RegionGroup = "all"
)

# Validate param combinations
if ($TargetQuantity -and -not $Region -and -not $Zone) {
    Write-Host "-TargetQuantity requires -Region or -Zone. Specify target regions/zones explicitly." -ForegroundColor Red
    exit 1
}
if ($Zone -and $Region) {
    Write-Host "-Zone and -Region cannot be combined. Use one or the other." -ForegroundColor Red
    exit 1
}
if ($Zone -and $RegionGroup -ne "all") {
    Write-Host "-Zone overrides -RegionGroup. Remove -RegionGroup when using -Zone." -ForegroundColor Red
    exit 1
}

Import-Module AWS.Tools.EC2

# Get current account ID (used to filter owned CRs in TargetQuantity mode)
$accountId = (Get-STSCallerIdentity -ErrorAction SilentlyContinue).Account

# Import Pricing module (used for on-demand price display and Windows validation)
$pricingAvailable = $false
try {
    Import-Module AWS.Tools.Pricing -ErrorAction Stop
    $pricingAvailable = $true
} catch {
    Write-Host "AWS.Tools.Pricing module not found. Pricing info will be unavailable." -ForegroundColor DarkYellow
    Write-Host "  Install with: Install-Module AWS.Tools.Pricing -Force" -ForegroundColor DarkYellow
}

# On-demand pricing lookup
$priceCache = @{}
$osFilter = if ($OS -eq "Windows") { "Windows" } else { "Linux" }

function Get-OnDemandPrice([string]$regionCode, [string]$locationName) {
    if ($script:priceCache.ContainsKey($regionCode)) { return $script:priceCache[$regionCode] }
    if (-not $locationName) { return $null }
    # Pricing API uses "EU" for some regions instead of "Europe"
    $locationVariants = @($locationName)
    if ($locationName -like "Europe*") {
        $locationVariants += $locationName -replace '^Europe', 'EU'
    }
    foreach ($loc in $locationVariants) {
        try {
            $products = Get-PLSProduct -ServiceCode AmazonEC2 -Region us-east-1 -Filter @(
                @{Type='TERM_MATCH'; Field='instanceType'; Value=$script:InstanceType},
                @{Type='TERM_MATCH'; Field='location'; Value=$loc},
                @{Type='TERM_MATCH'; Field='operatingSystem'; Value=$script:osFilter},
                @{Type='TERM_MATCH'; Field='tenancy'; Value='Shared'},
                @{Type='TERM_MATCH'; Field='preInstalledSw'; Value='NA'},
                @{Type='TERM_MATCH'; Field='capacitystatus'; Value='Used'}
            ) -ErrorAction SilentlyContinue
            foreach ($p in $products) {
                $json = $p | ConvertFrom-Json
                foreach ($term in $json.terms.OnDemand.PSObject.Properties) {
                    foreach ($dim in $term.Value.priceDimensions.PSObject.Properties) {
                        $price = [decimal]$dim.Value.pricePerUnit.USD
                        if ($price -gt 0 -and $dim.Value.description -notlike "*BYOL*" -and $dim.Value.description -notlike "*Capacity Block*" -and $dim.Value.description -notlike "*without licenses*") {
                            $script:priceCache[$regionCode] = $price
                            return $price
                        }
                    }
                }
            }
        } catch {}
    }
    return $null
}

# Query enabled regions
Write-Host "`nQuerying enabled regions in this account..." -ForegroundColor White
try {
    $enabledRegionData = Get-EC2Region -ErrorAction Stop
    $enabledRegions = @($enabledRegionData.RegionName | ForEach-Object { $_.ToString() })
    # Build country map from region data for display
    $regionCountryMap = @{}
    foreach ($r in $enabledRegionData) {
        if ($r.Geography -and $r.Geography.Name) {
            $regionCountryMap[$r.RegionName] = $r.Geography.Name
        }
    }
} catch {
    Write-Host "Failed to query AWS regions. Check your credentials and try again." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Validate Windows support via Pricing API
if ($OS -eq "Windows" -and $pricingAvailable) {
    try {
        $osCheck = Get-PLSProduct -ServiceCode AmazonEC2 -Region us-east-1 -Filter @(
            @{Type='TERM_MATCH'; Field='instanceType'; Value=$InstanceType},
            @{Type='TERM_MATCH'; Field='operatingSystem'; Value='Windows'},
            @{Type='TERM_MATCH'; Field='tenancy'; Value='Shared'},
            @{Type='TERM_MATCH'; Field='capacitystatus'; Value='Used'}
        ) -ErrorAction SilentlyContinue
        if (-not $osCheck) {
            Write-Host "$InstanceType does not support Windows. Try -OS Linux instead." -ForegroundColor Red
            exit 1
        }
    } catch {}
}

# Build try order (priority: US > CA > SA > MX > EU > AP > other)
$priorityRegions = [System.Collections.Generic.List[string]]::new()
$groupPrefixes = switch ($RegionGroup) {
    "us"  { @("us-") }
    "us+" { @("us-", "ca-", "sa-", "mx-") }
    "eu"  { @("eu-") }
    "ap"  { @("ap-") }
    "all" { @("us-", "ca-", "sa-", "mx-", "eu-", "ap-") }
}
foreach ($prefix in $groupPrefixes) {
    foreach ($r in $enabledRegions) {
        if ($r -like "$prefix*") { $priorityRegions.Add($r) }
    }
}
if ($RegionGroup -eq "all") {
    foreach ($r in $enabledRegions) {
        if ($r -notin $priorityRegions) { $priorityRegions.Add($r) }
    }
}

# Override with specific regions or zones if provided
$targetZones = $null  # Will be set if -Zone is used
if ($Zone) {
    # Handle comma-separated values
    $Zone = @($Zone | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    
    # Determine if these are zone IDs (e.g. use1-az1) or AZ names (e.g. us-east-1a)
    # Zone IDs don't contain the full region name pattern
    $isZoneId = $Zone[0] -notmatch '^\w+-\w+-\d+\w+$'
    
    # Resolve zones to get AZ names and regions
    $resolvedZones = @()
    $zoneRegions = @()
    foreach ($region in $enabledRegions) {
        $azs = Get-EC2AvailabilityZone -Region "$region" -Filter @{ Name = "state"; Values = @("available") } -ErrorAction SilentlyContinue
        foreach ($az in $azs) {
            if ($isZoneId) {
                if ($az.ZoneId -in $Zone) {
                    $resolvedZones += $az
                    if ($region -notin $zoneRegions) { $zoneRegions += $region }
                }
            } else {
                if ($az.ZoneName -in $Zone) {
                    $resolvedZones += $az
                    if ($region -notin $zoneRegions) { $zoneRegions += $region }
                }
            }
        }
        if ($resolvedZones.Count -eq $Zone.Count) { break }
    }
    
    if ($resolvedZones.Count -eq 0) {
        Write-Host "Zone(s) not found: $($Zone -join ', ')" -ForegroundColor Red
        exit 1
    }
    
    $targetZones = $resolvedZones
    [string[]]$tryRegions = $zoneRegions
    Write-Host "  Zone: " -ForegroundColor White -NoNewline
    Write-Host "$($Zone -join ', ')" -ForegroundColor Cyan
} elseif ($Region) {
    # Handle comma-separated values passed as a single string (e.g. via pwsh -File)
    $Region = @($Region | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $invalidRegions = $Region | Where-Object { $_ -notin $enabledRegions }
    if ($invalidRegions) {
        Write-Host "Region(s) not enabled in this account: $($invalidRegions -join ', ')" -ForegroundColor Red
        exit 1
    }
    [string[]]$tryRegions = $Region
    Write-Host "  Region: " -ForegroundColor White -NoNewline
    Write-Host "$($Region -join ', ')" -ForegroundColor Cyan
} else {
    [string[]]$tryRegions = $priorityRegions.ToArray()
    Write-Host "  Region group: " -ForegroundColor White -NoNewline
    Write-Host "$RegionGroup" -ForegroundColor Cyan -NoNewline
    Write-Host " ($($tryRegions.Count) enabled regions to try)" -ForegroundColor White
}

Write-Host "OS: $OS" -ForegroundColor White
Write-Host "Quantity per request: $Quantity" -ForegroundColor White

# Pre-check: filter regions that offer this instance type (parallel)
Write-Host "`nChecking regions which offer $InstanceType..." -ForegroundColor White
$supportedRegions = @($tryRegions | ForEach-Object -Parallel {
    $offerings = Get-EC2InstanceTypeOffering -Region $_ -Filter @{ Name = "instance-type"; Values = @($using:InstanceType) } -ErrorAction SilentlyContinue
    if ($offerings) { $_ }
} -ThrottleLimit 50)

# Get AZ data for supported regions (parallel) - single source for country, city, zone ID
$supportedRegionList = @($tryRegions | Where-Object { $_ -in $supportedRegions })
$azData = @($supportedRegionList | ForEach-Object -Parallel {
    $region = $_
    $azOfferings = Get-EC2InstanceTypeOffering -Region $region -LocationType "availability-zone" -Filter @{ Name = "instance-type"; Values = @($using:InstanceType) } -ErrorAction SilentlyContinue
    $supportedAZNames = @($azOfferings.Location | Sort-Object)
    if (-not $supportedAZNames) { return }
    $allAZs = Get-EC2AvailabilityZone -Region $region -Filter @{ Name = "state"; Values = @("available") }
    foreach ($az in $allAZs) {
        if ($az.ZoneName -in $supportedAZNames) {
            $city = $region
            $gln = $az.GroupLongName
            if ($gln -and $gln -match '\((.+?)\)') { $city = $Matches[1] }
            $country = if ($az.Geography -and $az.Geography.Name) { "$($az.Geography.Name)" } else { "" }
            [PSCustomObject]@{
                Region   = $region
                AZ       = $az.ZoneName
                ZoneId   = $az.ZoneId
                Country  = $country
                City     = $city
                AZLabel  = if ($az.ZoneId) { "$($az.ZoneName) / $($az.ZoneId)" } else { $az.ZoneName }
            }
        }
    }
} -ThrottleLimit 20)

# Display region support (in priority order)
$displayRegions = $tryRegions
foreach ($region in $displayRegions) {
    $entry = $azData | Where-Object { $_.Region -eq $region } | Select-Object -First 1
    if ($entry) {
        $label = if ($entry.Country) { "$($entry.Country) - $($entry.City) - $region" } else { "$($entry.City) - $region" }
        Write-Host "  $label - supported" -ForegroundColor Green
    } else {
        $country = $regionCountryMap[$region]
        $label = if ($country) { "$country - $region" } else { $region }
        Write-Host "  $label - not supported, skipping" -ForegroundColor DarkGray
    }
}

Write-Host "$($supportedRegionList.Count) region(s) to check for $InstanceType" -ForegroundColor White

if ($azData.Count -eq 0) {
    Write-Host "`n$InstanceType is not available in any enabled region." -ForegroundColor Red
    exit 1
}

$platform = if ($OS -eq "Windows") { "Windows" } else { "Linux/UNIX" }
$reserved = $false

# Build AZ targets in priority order (filter by -Zone if specified)
$azTargets = @()
foreach ($region in $supportedRegionList) {
    $regionAZs = $azData | Where-Object { $_.Region -eq $region }
    if ($targetZones) {
        $targetAZNames = $targetZones | ForEach-Object { $_.ZoneName }
        $regionAZs = $regionAZs | Where-Object { $_.AZ -in $targetAZNames }
    }
    foreach ($az in $regionAZs) {
        $azTargets += $az
    }
}

# TargetQuantity mode: accumulate capacity across AZs by creating and expanding ODCRs
if ($TargetQuantity) {
    # If targeting a specific CR, skip discovery and expand directly
    if ($CapacityReservationId) {
        if (-not $Region) {
            Write-Host "-CapacityReservationId requires -Region to identify the CR's region." -ForegroundColor Red
            exit 1
        }
        $targetRegion = $Region[0]
        Write-Host "`nExpanding $CapacityReservationId to $TargetQuantity slot(s) in increments of $Quantity (timeout: ${TargetTimeout}s)..." -ForegroundColor White
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Get current CR state
        $cr = Get-EC2CapacityReservation -CapacityReservationId $CapacityReservationId -Region "$targetRegion" -ErrorAction SilentlyContinue
        if (-not $cr) {
            Write-Host "Capacity Reservation $CapacityReservationId not found in $targetRegion." -ForegroundColor Red
            exit 1
        }
        $currentQty = $cr.TotalInstanceCount
        Write-Host "  Current: $CapacityReservationId qty=$currentQty in $($cr.AvailabilityZone)" -ForegroundColor DarkGray
        
        while ($currentQty -lt $TargetQuantity -and $stopwatch.Elapsed.TotalSeconds -lt $TargetTimeout) {
            $increment = [Math]::Min($Quantity, $TargetQuantity - $currentQty)
            $newQty = $currentQty + $increment
            Write-Host "  Expanding to $newQty... " -ForegroundColor Cyan -NoNewline
            try {
                Edit-EC2CapacityReservation -CapacityReservationId $CapacityReservationId -InstanceCount $newQty -Region "$targetRegion" -ErrorAction Stop | Out-Null
                $currentQty = $newQty
                Write-Host "SUCCESS (qty=$currentQty/$TargetQuantity)" -ForegroundColor Green
            } catch {
                Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Yellow
                $remaining = [Math]::Round($TargetTimeout - $stopwatch.Elapsed.TotalSeconds)
                if ($remaining -gt 0 -and $currentQty -lt $TargetQuantity) {
                    Write-Host "  Retrying in ${TargetQuantityInterval}s... (${remaining}s remaining)" -ForegroundColor DarkGray
                    Start-Sleep -Seconds ([Math]::Min($TargetQuantityInterval, $remaining))
                } else { break }
            }
        }
        $stopwatch.Stop()
        
        $status = if ($currentQty -ge $TargetQuantity) { "Target reached" } else { "Partial ($currentQty/$TargetQuantity)" }
        Write-Host "`n$status in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor $(if ($currentQty -ge $TargetQuantity) { "Green" } else { "Yellow" })
        Write-Host "  $CapacityReservationId qty=$currentQty in $($cr.AvailabilityZone)" -ForegroundColor Cyan
        Write-Host "`nConsole: https://console.aws.amazon.com/ec2/home?region=$targetRegion#CapacityReservations:" -ForegroundColor Cyan
        exit 0
    }

    Write-Host "`nFinding $TargetQuantity slot(s) in increments of $Quantity (timeout: ${TargetTimeout}s)..." -ForegroundColor White
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $totalReserved = 0
    $createdODCRs = @()

    # Check for existing matching CRs in target regions and seed them
    foreach ($region in $supportedRegionList) {
        $existingCRs = Get-EC2CapacityReservation -Region "$region" -Filter @(
            @{Name='state'; Values=@('active')},
            @{Name='instance-type'; Values=@($InstanceType)},
            @{Name='owner-id'; Values=@($accountId)}
        ) -ErrorAction SilentlyContinue
        foreach ($cr in $existingCRs) {
            # Skip Capacity Blocks and non-standard CRs
            if ($cr.ReservationType -and $cr.ReservationType -ne "default") { continue }
            # Match platform
            $crPlatform = $cr.InstancePlatform
            if ($crPlatform -ne $platform) { continue }
            # Only pick up CRs in AZs we're targeting
            $matchingTarget = $azTargets | Where-Object { $_.AZ -eq $cr.AvailabilityZone } | Select-Object -First 1
            if (-not $matchingTarget) { continue }
            $createdODCRs += [PSCustomObject]@{
                Region = $region; AZ = $cr.AvailabilityZone; AZLabel = $matchingTarget.AZLabel
                CrId = $cr.CapacityReservationId; Qty = $cr.TotalInstanceCount
            }
            Write-Host "  Existing: $($matchingTarget.AZLabel) qty=$($cr.TotalInstanceCount) ($($cr.CapacityReservationId))" -ForegroundColor DarkGray
        }
    }

    # Count existing capacity toward target
    $totalReserved = ($createdODCRs | Measure-Object -Property Qty -Sum).Sum
    if ($totalReserved -ge $TargetQuantity) {
        Write-Host "`nTarget already met: $totalReserved/$TargetQuantity slots exist." -ForegroundColor Green
        $stopwatch.Stop()
    }

    while ($totalReserved -lt $TargetQuantity -and $stopwatch.Elapsed.TotalSeconds -lt $TargetTimeout) {
        $madeProgress = $false
        $lastRegion = ""
        $passFailedAZs = @{}

        foreach ($t in $azTargets) {
            if ($totalReserved -ge $TargetQuantity) { break }
            if ($passFailedAZs.ContainsKey($t.AZ)) { continue }

            # Print region header
            if ("$($t.Region)" -ne $lastRegion) {
                $regionHeader = if ($t.Country) { "$($t.Country) - $($t.City) - $($t.Region)" } else { "$($t.City) - $($t.Region)" }
                Write-Host "`n$regionHeader" -ForegroundColor White
                $lastRegion = "$($t.Region)"
            }

            # Check if we already have an ODCR in this AZ
            $existing = $createdODCRs | Where-Object { $_.AZ -eq $t.AZ } | Select-Object -First 1

            if (-not $existing) {
                # Create new ODCR in this AZ
                $needed = [Math]::Min($Quantity, $TargetQuantity - $totalReserved)
                Write-Host "  Trying $($t.AZLabel)... " -ForegroundColor Cyan -NoNewline
                try {
                    $reservation = Add-EC2CapacityReservation `
                        -Region "$($t.Region)" `
                        -InstanceType $InstanceType `
                        -InstancePlatform $platform `
                        -AvailabilityZone "$($t.AZ)" `
                        -InstanceCount $needed `
                        -InstanceMatchCriteria $InstanceMatchCriteria
                    $crId = "$($reservation.CapacityReservationId)"
                    $totalReserved += $needed
                    $madeProgress = $true
                    $createdODCRs += [PSCustomObject]@{
                        Region = $t.Region; AZ = $t.AZ; AZLabel = $t.AZLabel; CrId = $crId; Qty = $needed
                    }
                    Write-Host "$crId CREATED qty=$needed (total: $totalReserved/$TargetQuantity)" -ForegroundColor Green
                    $existing = $createdODCRs | Where-Object { $_.AZ -eq $t.AZ } | Select-Object -First 1
                } catch {
                    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Yellow
                    continue
                }
            }

            # Expand this AZ until maxed or target reached
            while ($totalReserved -lt $TargetQuantity -and $existing) {
                $increment = [Math]::Min($Quantity, $TargetQuantity - $totalReserved)
                $newQty = $existing.Qty + $increment
                Write-Host "  Trying $($t.AZLabel)... " -ForegroundColor Cyan -NoNewline
                try {
                    Edit-EC2CapacityReservation -CapacityReservationId $existing.CrId -InstanceCount $newQty -Region "$($t.Region)" -ErrorAction Stop | Out-Null
                    $totalReserved += $increment
                    $existing.Qty = $newQty
                    $madeProgress = $true
                    Write-Host "$($existing.CrId) EXPANDED to $newQty (total: $totalReserved/$TargetQuantity)" -ForegroundColor Green
                } catch {
                    $passFailedAZs[$t.AZ] = $true
                    Write-Host "$($existing.CrId) Insufficient capacity. Current qty=$($existing.Qty)" -ForegroundColor Yellow
                    break
                }
            }
        }

        # If no progress on this pass and all AZs either exhausted or failed, wait and retry
        if (-not $madeProgress -and $totalReserved -lt $TargetQuantity -and $stopwatch.Elapsed.TotalSeconds -lt $TargetTimeout) {
            $remaining = [Math]::Round($TargetTimeout - $stopwatch.Elapsed.TotalSeconds)
            if ($remaining -gt 0) {
                Write-Host "`n  Retrying in ${TargetQuantityInterval}s... (${remaining}s remaining)" -ForegroundColor DarkGray
                Start-Sleep -Seconds ([Math]::Min($TargetQuantityInterval, $remaining))
            }
        }
    }

    $stopwatch.Stop()
    Write-Host "`n" -NoNewline

    if ($createdODCRs.Count -gt 0) {
        $totalSlots = ($createdODCRs | Measure-Object -Property Qty -Sum).Sum
        $status = if ($totalSlots -ge $TargetQuantity) { "Target reached" } else { "Partial ($totalSlots/$TargetQuantity)" }
        Write-Host "$status in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor $(if ($totalSlots -ge $TargetQuantity) { "Green" } else { "Yellow" })
        Write-Host "`nReservation(s): $($createdODCRs.Count) ODCR(s), $totalSlots total slot(s) — $InstanceType ($OS, $InstanceMatchCriteria)" -ForegroundColor Green
        Write-Host "  $("Region".PadRight(14)) $("AZ".PadRight(24)) $("Qty".PadRight(5)) ODCR ID" -ForegroundColor White
        Write-Host "  $("─" * 14) $("─" * 24) $("─" * 5) $("─" * 26)" -ForegroundColor DarkGray
        foreach ($o in $createdODCRs) {
            Write-Host "  $("$($o.Region)".PadRight(14)) $("$($o.AZLabel)".PadRight(24)) $("$($o.Qty)".PadRight(5)) $($o.CrId)" -ForegroundColor Cyan
        }
        $uniqueRegions = @($createdODCRs | ForEach-Object { $_.Region } | Select-Object -Unique)
        Write-Host "`nConsole:" -ForegroundColor White
        foreach ($reg in $uniqueRegions) {
            Write-Host "  ${reg}: https://console.aws.amazon.com/ec2/home?region=$reg#CapacityReservations:" -ForegroundColor Cyan
        }
        Write-Host "`nTo cancel all:" -ForegroundColor White
        foreach ($o in $createdODCRs) {
            Write-Host "  Remove-EC2CapacityReservation -CapacityReservationId $($o.CrId) -Region $($o.Region) -Force" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Failed to reserve any capacity for $InstanceType." -ForegroundColor Red
    }
    exit 0
}

if (-not $Sequential) {
    Write-Host "`nCreating capacity reservation (parallel - $($azTargets.Count) AZs)..." -ForegroundColor White

    $results = $azTargets | ForEach-Object -Parallel {
        $t = $_
        $regionStr = "$($t.Region)"
        try {
            $reservation = Add-EC2CapacityReservation `
                -Region $regionStr `
                -InstanceType $using:InstanceType `
                -InstancePlatform $using:platform `
                -AvailabilityZone "$($t.AZ)" `
                -InstanceCount $using:Quantity `
                -InstanceMatchCriteria $using:InstanceMatchCriteria
            [PSCustomObject]@{
                Region = $t.Region; City = $t.City; AZ = $t.AZ
                AZLabel = $t.AZLabel; CrId = $reservation.CapacityReservationId; Success = $true
            }
        } catch {
            [PSCustomObject]@{
                Region = $t.Region; City = $t.City; AZ = $t.AZ
                AZLabel = $t.AZLabel; CrId = $null; Success = $false; Error = $_.Exception.Message
            }
        }
    } -ThrottleLimit 50

    # Sort by priority order and display with inline numbering + pricing
    $azOrder = $azTargets | ForEach-Object { $_.AZ }
    $sortedResults = $results | Sort-Object { [array]::IndexOf($azOrder, $_.AZ) }
    $sortedSuccesses = @($sortedResults | Where-Object { $_.Success })

    $successIndex = 0
    $lastRegion = ""
    foreach ($r in $sortedResults) {
        if ("$($r.Region)" -ne $lastRegion) {
            $countryLabel = ($azData | Where-Object { $_.Region -eq "$($r.Region)" } | Select-Object -First 1).Country
            $cityLabel = ($azData | Where-Object { $_.Region -eq "$($r.Region)" } | Select-Object -First 1).City
            $regionHeader = if ($countryLabel) { "$countryLabel - $cityLabel - $($r.Region)" } else { "$cityLabel - $($r.Region)" }
            Write-Host "`n$regionHeader" -ForegroundColor White
            $lastRegion = "$($r.Region)"
        }
        Write-Host "  Trying $($r.AZLabel)... " -ForegroundColor Cyan -NoNewline
        if ($r.Success) {
            $successIndex++
            # Get location name for pricing from GroupLongName
            $azEntry = $azData | Where-Object { $_.AZ -eq $r.AZ } | Select-Object -First 1
            $locName = if ($azEntry) {
                # Reconstruct location name from AZ data for pricing API
                $allAZsForRegion = Get-EC2AvailabilityZone -Region "$($r.Region)" -ZoneName "$($r.AZ)" -ErrorAction SilentlyContinue
                if ($allAZsForRegion -and $allAZsForRegion.GroupLongName) {
                    $gln = $allAZsForRegion.GroupLongName
                    if ($gln -match '^(.+?)\s*\d*$') { $Matches[1].Trim() } else { $gln }
                } else { $null }
            } else { $null }
            $price = Get-OnDemandPrice "$($r.Region)" $locName
            $priceStr = if ($price) { "`$$price/hr" } else { "" }
            $qtyStr = if ($Quantity -gt 1) { " x$Quantity" } else { "" }
            Write-Host "SUCCESS [$successIndex] $priceStr$qtyStr" 
... (truncated at 30,000 chars)