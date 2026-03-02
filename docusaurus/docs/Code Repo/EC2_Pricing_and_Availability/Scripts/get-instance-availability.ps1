<#
.SYNOPSIS
    Get EC2 instance type availability and pricing across all enabled AWS regions.

.DESCRIPTION
    Queries all enabled AWS regions to find where specified EC2 instance types are available,
    including availability zones and on-demand pricing for Linux and Windows operating systems.
    
    The script retrieves real-time pricing data from the AWS Pricing API and displays results
    in a formatted table showing regional availability and hourly costs.

.PARAMETER InstanceType
    One or more EC2 instance types to query. Accepts comma-separated values.
    Default: m8i.4xlarge

.PARAMETER Region
    One or more AWS regions, region prefixes (e.g. 'us', 'eu-west'), or 'all'.
    Supports arrays: -Region us-east-1, us-east-2
    Prefix matching: -Region us (matches all us-* regions)
    Defaults to all enabled regions.

.PARAMETER SortBy
    Sort results by Region or Price.
    Default: Region

.PARAMETER ZoneId
    Display AZ IDs (e.g., use2-az1) instead of AZ names (e.g., us-east-2a).

.PARAMETER TPC1
    Show an additional Windows TPC=1 pricing column (Optimize CPUs with ThreadsPerCore=1).

.PARAMETER Hours
    Number of hours for cost calculation, or 'month' (730) / 'year' (8760).
    Default: 1 (hourly rate)

.PARAMETER Debug
    Show detailed pricing API responses for troubleshooting.

.EXAMPLE
    pwsh -File get-instance-availability.ps1
    Run with default parameters (m8i.4xlarge, sorted by Region).

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -InstanceType m8a.2xlarge
    Query availability and pricing for m8a.2xlarge instances across all regions.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -InstanceType "m7i.2xlarge,m8i.2xlarge" -SortBy Price
    Query multiple instance types and sort results by price.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -InstanceType m8i.xlarge -TPC1
    Show Windows TPC=1 pricing column.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -Region us
    Query default instance type across all US regions only.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -Region us-east-1,eu-west-1 -InstanceType m7i.xlarge
    Query m7i.xlarge in specific regions.

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -ZoneId
    Display results with AZ IDs (use2-az1) instead of AZ names (us-east-2a).

.EXAMPLE
    pwsh -File get-instance-availability.ps1 -Region us -Hours month
    Query US regions with monthly (730 hours) cost estimates.

.NOTES
    Author: coolcrai@amazon.com
    Version: 1.1
    Last Updated: February 27, 2026
    
    RECOMMENDED: Run this script from AWS CloudShell for the best experience.
    CloudShell comes with PowerShell and AWS modules pre-installed, and credentials
    are automatically configured. Simply upload the script and run it.
    
    Requirements:
    - AWS PowerShell modules: AWS.Tools.EC2, AWS.Tools.Pricing
    - Valid AWS credentials configured
    - Pricing API access (queries us-east-1 region)
    
    Pricing Information:
    - Linux pricing is for standard Linux/Unix instances
    - Windows Default pricing includes license costs (License Included model)
    - Windows TPC=1 pricing is Linux base + (cores x $0.046/vCPU-hr Windows license rate)
    - Windows TPC=1 shows N/A for t3/t3a burstable and bare metal instances
    - All prices are hourly on-demand rates in USD
#>

param(
    [string[]]$InstanceType = 'm8i.4xlarge',
    [string[]]$Region,
    [ValidateSet('Region', 'Price')]
    [string]$SortBy = 'Region',
    [switch]$ZoneId,
    [switch]$TPC1,
    [string]$Hours = '1',
    [switch]$Debug
)

Import-Module AWS.Tools.EC2 -ErrorAction Stop
Import-Module AWS.Tools.Pricing -ErrorAction Stop

# ── Resolve hours ──
$HoursNum = switch ($Hours.ToLower()) {
    'month'  { 730 }
    'year'   { 8760 }
    default  {
        if ($Hours -as [int]) { [int]$Hours }
        else { throw "Invalid -Hours value '$Hours'. Use a number, 'month', or 'year'." }
    }
}

# Handle comma-separated string input
if ($InstanceType.Count -eq 1 -and $InstanceType[0] -match ',') {
    $InstanceType = $InstanceType[0] -split ',' | ForEach-Object { $_.Trim() }
}
if ($Region -and $Region.Count -eq 1 -and $Region[0] -match ',') {
    $Region = $Region[0] -split ',' | ForEach-Object { $_.Trim() }
}

# ── Determine regions to scan ──
$allRegions = (Get-EC2Region -ErrorAction SilentlyContinue).RegionName
if (-not $Region -or ($Region.Count -eq 1 -and $Region[0] -eq 'all')) {
    $regionsToScan = $allRegions
} else {
    $regionsToScan = @()
    foreach ($r in $Region) {
        if ($r -in $allRegions) {
            $regionsToScan += $r
        } else {
            $matched = $allRegions | Where-Object { $_ -like "${r}*" }
            if ($matched) {
                $regionsToScan += $matched
            } else {
                Write-Warning "No regions matched '$r'."
            }
        }
    }
    $regionsToScan = $regionsToScan | Sort-Object -Unique
}

# Get region mapping once
$awsRegions = Get-AWSRegion

$InstanceType | ForEach-Object {
    $type = $_

    # Cache CPU info once per instance type (same across all regions)
    $skipTpc1 = $type -match '^t3'
    $cpuInfo = $null
    $isBareMetalType = $false
    $defaultCores = 0
    $defaultThreads = 0
    foreach ($tryRegion in @('us-east-1') + $regionsToScan) {
        try {
            $cpuInfo = Get-EC2InstanceType -InstanceType $type -Region $tryRegion -ErrorAction SilentlyContinue
            if ($cpuInfo) {
                $isBareMetalType = $cpuInfo.BareMetal
                $defaultCores = $cpuInfo.VCpuInfo.DefaultCores
                $defaultThreads = $cpuInfo.VCpuInfo.DefaultThreadsPerCore
                break
            }
        } catch {}
    }

    Write-Host "InstanceType: $type" -ForegroundColor Yellow
    if (-not $cpuInfo) {
        Write-Warning "Instance type '$type' not found. Skipping."
        Write-Host ""
        return
    }
    $vcpus = $cpuInfo.VCpuInfo.DefaultVCpus
    $memGiB = [math]::Round($cpuInfo.MemoryInfo.SizeInMiB / 1024, 0)
    $ghz = if ($cpuInfo.ProcessorInfo.SustainedClockSpeedInGhz) { $cpuInfo.ProcessorInfo.SustainedClockSpeedInGhz } else { $null }
    $specLine = "vCPUs: $vcpus, Cores: $defaultCores"
    if ($ghz) { $specLine += ", GHz: $ghz" }
    $specLine += ", RAM: ${memGiB}GB"
    Write-Host $specLine -ForegroundColor Yellow
    
    # Get availability by region (only specified/enabled regions)
    $results = $regionsToScan | ForEach-Object { 
        $regionCode = $_
        $regionName = ($awsRegions | Where-Object { $_.Region -eq $regionCode }).Name
        
        $offerings = Get-EC2InstanceTypeOffering -LocationType availability-zone -Filter @{Name='instance-type'; Values=$type} -Region $regionCode -ErrorAction SilentlyContinue
        
        if ($offerings) {
            # Get AZ details (only needed for ZoneId mapping)
            $azInfo = if ($ZoneId) {
                $azDetails = Get-EC2AvailabilityZone -Region $regionCode -ErrorAction SilentlyContinue
                $offerings.Location | Sort-Object | ForEach-Object {
                    $azName = $_
                    ($azDetails | Where-Object { $_.ZoneName -eq $azName }).ZoneId
                }
            } else {
                $offerings.Location | Sort-Object
            }
            # Build pricing filters
            $baseFilters = @(
                @{Type='TERM_MATCH'; Field='instanceType'; Value=$type}
                @{Type='TERM_MATCH'; Field='tenancy'; Value='Shared'}
                @{Type='TERM_MATCH'; Field='preInstalledSw'; Value='NA'}
                @{Type='TERM_MATCH'; Field='regionCode'; Value=$regionCode}
            )
            
            $linuxPrice = 'N/A'
            $windowsPrice = 'N/A'
            
            # Get Linux pricing - collect all "Used" prices and take the highest non-zero value
            $linuxFilters = $baseFilters + @{Type='TERM_MATCH'; Field='operatingSystem'; Value='Linux'}
            $linuxPriceList = Get-PLSProduct -ServiceCode AmazonEC2 -Filter $linuxFilters -Region us-east-1 -ErrorAction SilentlyContinue
            if ($Debug) { Write-Host "  Linux results for ${regionCode}: $($linuxPriceList.Count) items" -ForegroundColor Cyan }
            $linuxPrices = @()
            foreach ($item in $linuxPriceList) {
                $priceData = $item | ConvertFrom-Json
                if ($Debug) { 
                    Write-Host "    capacitystatus: $($priceData.product.attributes.capacitystatus)" -ForegroundColor Yellow
                    Write-Host "    Raw price data: $($priceData.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1)" -ForegroundColor Yellow
                }
                if ($priceData.product.attributes.capacitystatus -eq 'Used') {
                    $onDemand = $priceData.terms.OnDemand.PSObject.Properties.Value | Select-Object -First 1
                    $price = $onDemand.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1
                    if ([decimal]$price -gt 0) {
                        $linuxPrices += [decimal]$price
                    }
                }
            }
            if ($linuxPrices.Count -gt 0) {
                $linuxPrice = ($linuxPrices | Measure-Object -Maximum).Maximum
            }
            
            # Get Windows pricing (License Included) - collect all "Used" prices and take the highest non-zero value
            $windowsFilters = $baseFilters + @{Type='TERM_MATCH'; Field='operatingSystem'; Value='Windows'}
            $windowsPriceList = Get-PLSProduct -ServiceCode AmazonEC2 -Filter $windowsFilters -Region us-east-1 -ErrorAction SilentlyContinue
            if ($Debug) { Write-Host "  Windows results for ${regionCode}: $($windowsPriceList.Count) items" -ForegroundColor Cyan }
            $windowsPrices = @()
            foreach ($item in $windowsPriceList) {
                $priceData = $item | ConvertFrom-Json
                if ($Debug) { 
                    Write-Host "    capacitystatus: $($priceData.product.attributes.capacitystatus), licenseModel: $($priceData.product.attributes.licenseModel)" -ForegroundColor Yellow
                    Write-Host "    Raw price data: $($priceData.terms.OnDemand.PSObject.Properties.Value.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1)" -ForegroundColor Yellow
                }
                if ($priceData.product.attributes.capacitystatus -eq 'Used' -and $priceData.product.attributes.licenseModel -eq 'No License required') {
                    $onDemand = $priceData.terms.OnDemand.PSObject.Properties.Value | Select-Object -First 1
                    $price = $onDemand.priceDimensions.PSObject.Properties.Value.pricePerUnit.USD | Select-Object -First 1
                    if ([decimal]$price -gt 0) {
                        $windowsPrices += [decimal]$price
                    }
                }
            }
            if ($windowsPrices.Count -gt 0) {
                $windowsPrice = ($windowsPrices | Measure-Object -Maximum).Maximum
            }
            
            # Calculate Windows TPC=1 price using cached CPU info
            # Skip t3/t3a (Optimize CPUs not applicable) and bare metal instances
            $windowsTpc1Price = 'N/A'
            if ($TPC1 -and -not $skipTpc1 -and -not $isBareMetalType -and $cpuInfo -and $linuxPrice -ne 'N/A' -and $windowsPrice -ne 'N/A') {
                if ($defaultThreads -gt 1) {
                    $windowsTpc1Price = [decimal]$linuxPrice + ($defaultCores * 0.046)
                } else {
                    # Already TPC=1 by default, same as Windows default
                    $windowsTpc1Price = [decimal]$windowsPrice
                }
            }

            [PSCustomObject]@{ 
                Region = $regionName
                RegionCode = $regionCode
                AvailabilityZones = $azInfo
                LinuxPrice = if ($linuxPrice -ne 'N/A') { [decimal]$linuxPrice * $HoursNum } else { $linuxPrice }
                WindowsPrice = if ($windowsPrice -ne 'N/A') { [decimal]$windowsPrice * $HoursNum } else { $windowsPrice }
                WindowsTpc1Price = if ($windowsTpc1Price -ne 'N/A') { [decimal]$windowsTpc1Price * $HoursNum } else { $windowsTpc1Price }
            }
        } 
    }
    
    $sortProp = switch ($SortBy) {
        'Price'   { 'LinuxPrice' }
        default   { 'Region' }
    }
    $priceFmt = if ($HoursNum -eq 1) { 'C3' } else { 'C0' }
    $cols = @(
        'Region',
        @{Name='AvailabilityZones';Expression={$_.AvailabilityZones -join ', '};Width=50},
        @{Name='Hours';Expression={$HoursNum};Align='Right'},
        @{Name='     Linux';Expression={if ($_.LinuxPrice -is [decimal]) {$_.LinuxPrice.ToString($priceFmt)} else {$_.LinuxPrice}};Align='Right'},
        @{Name='   Windows';Expression={if ($_.WindowsPrice -is [decimal]) {$_.WindowsPrice.ToString($priceFmt)} else {$_.WindowsPrice}};Align='Right'}
    )
    if ($TPC1) {
        $cols += @{Name='Windows TPC=1';Expression={if ($_.WindowsTpc1Price -is [decimal]) {$_.WindowsTpc1Price.ToString($priceFmt)} else {$_.WindowsTpc1Price}};Align='Right'}
    }
    $results | Sort-Object $sortProp | Format-Table -Property $cols -Wrap
    Write-Host ""
}
