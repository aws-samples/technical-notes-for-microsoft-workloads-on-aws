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
    Default: m8a.xlarge

.PARAMETER SortBy
    Sort results by Region, LinuxPrice, or WindowsPrice.
    Default: WindowsPrice

.PARAMETER ZoneId
    Display AZ IDs (e.g., use2-az1) instead of AZ names (e.g., us-east-2a).

.PARAMETER Debug
    Show detailed pricing API responses for troubleshooting.

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
    
    RECOMMENDED: Run this script from AWS CloudShell for the best experience.
    CloudShell comes with PowerShell and AWS modules pre-installed, and credentials
    are automatically configured. Simply upload the script and run it.
    
    Requirements:
    - AWS PowerShell modules: AWS.Tools.EC2, AWS.Tools.Pricing
    - Valid AWS credentials configured
    - Pricing API access (queries us-east-1 region)
    
    Pricing Information:
    - Linux pricing is for standard Linux/Unix instances
    - Windows pricing includes license costs (License Included model)
    - All prices are hourly on-demand rates in USD
#>

param(
    [string[]]$InstanceType = 'm8a.xlarge',
    [ValidateSet('Region', 'LinuxPrice', 'WindowsPrice')]
    [string]$SortBy = 'WindowsPrice',
    [switch]$ZoneId,
    [switch]$Debug
)

# Handle comma-separated string input
if ($InstanceType.Count -eq 1 -and $InstanceType[0] -match ',') {
    $InstanceType = $InstanceType[0] -split ',' | ForEach-Object { $_.Trim() }
}

$InstanceType | ForEach-Object {
    $type = $_
    Write-Host "InstanceType: $type"
    
    # Get region mapping once
    $awsRegions = Get-AWSRegion
    
    # Get availability by region (only enabled regions)
    $results = Get-EC2Region | ForEach-Object { 
        $regionCode = $_.RegionName
        $regionName = ($awsRegions | Where-Object { $_.Region -eq $regionCode }).Name
        
        $offerings = Get-EC2InstanceTypeOffering -LocationType availability-zone -Filter @{Name='instance-type'; Values=$type} -Region $regionCode -ErrorAction SilentlyContinue
        
        if ($offerings) {
            # Get AZ details including Zone IDs
            $azDetails = Get-EC2AvailabilityZone -Region $regionCode -ErrorAction SilentlyContinue
            $azInfo = $offerings.Location | Sort-Object | ForEach-Object {
                $azName = $_
                $azId = ($azDetails | Where-Object { $_.ZoneName -eq $azName }).ZoneId
                if ($ZoneId) { $azId } else { $azName }
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
            
            [PSCustomObject]@{ 
                Region = $regionName
                RegionCode = $regionCode
                AvailabilityZones = $azInfo
                LinuxPrice = if ($linuxPrice -ne 'N/A') { [decimal]$linuxPrice } else { $linuxPrice }
                WindowsPrice = if ($windowsPrice -ne 'N/A') { [decimal]$windowsPrice } else { $windowsPrice }
            }
        } 
    }
    
    $results | Sort-Object $SortBy | Format-Table -Property Region, @{Name='AvailabilityZones';Expression={$_.AvailabilityZones -join ', '};Width=50}, @{Name='LinuxPrice';Expression={if ($_.LinuxPrice -is [decimal]) {$_.LinuxPrice.ToString('C3')} else {$_.LinuxPrice}}}, @{Name='WindowsPrice';Expression={if ($_.WindowsPrice -is [decimal]) {$_.WindowsPrice.ToString('C3')} else {$_.WindowsPrice}}} -Wrap
    Write-Host ""
}
