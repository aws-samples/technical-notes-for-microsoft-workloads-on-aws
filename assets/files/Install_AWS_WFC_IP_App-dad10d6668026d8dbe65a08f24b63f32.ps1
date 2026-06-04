<#
.SYNOPSIS
    Deploys the AWS WFC IP Address script to cluster nodes and creates Generic Application resources.

.DESCRIPTION
    This script automates the setup of AWS ENI floating IP management in a Windows Failover Cluster.
    It performs two main tasks:
    1. Copies the AWS_WFC_IP_Address.ps1 script to all online cluster nodes via SMB admin shares.
    2. Creates a WFC Generic Application resource for each IP Address in the selected cluster group,
       configured to run the IP management script during failover.

.NOTES
    - Must be run with cluster administrator privileges.
    - The AWS_WFC_IP_Address.ps1 script must exist in the same directory as this installer.
    - Requires the FailoverClusters PowerShell module.
    - Requires AWS.Tools.EC2 or AWSPowerShell module on all cluster nodes (AWS.Tools.EC2 recommended).
      https://docs.aws.amazon.com/powershell/v5/userguide/pstools-welcome.html#pwsh_structure_pstools
    - Can be run multiple times to update the script or reconfigure resources.
#>

# Script configuration
$WFCScriptName = "AWS_WFC_IP_Address.ps1"
$WFCScriptPath = "C:\Scripts"
$WFCScriptSharePath = $WFCScriptPath.Replace(':', '$')

# Verify FailoverClusters module is available
if (-not (Get-Module -ListAvailable -Name FailoverClusters)) {
    throw "FailoverClusters module not installed. Install the Failover Clustering Tools feature."
}

# Verify AWS EC2 cmdlets are available
if (-not (Test-Path "${env:ProgramFiles}\WindowsPowerShell\Modules\AWS.Tools.EC2") -and
    -not (Test-Path "${env:ProgramFiles}\WindowsPowerShell\Modules\AWSPowerShell")) {
    Write-Warning "AWS PowerShell module not installed on this node. This is required for failover IP management to succeed."
}

# Verify source script exists
if (-not (Test-Path "$PSScriptRoot\$WFCScriptName")) {
    throw "Source script not found: $PSScriptRoot\$WFCScriptName"
}

# Query cluster nodes names and deploy script to all nodes via SMB Admin Share (c$) using UNC Path
$clusterNodes = Get-ClusterNode | Where-Object {$_.State -eq 'Up'}
if (-not $clusterNodes) {
    throw "No online cluster nodes found"
}

# Verify AWS EC2 cmdlets are available on all cluster nodes
Write-Host "Checking AWS PowerShell module paths:" -ForegroundColor Green
foreach ($node in $clusterNodes) {
    $awsModule = Invoke-Command -ComputerName $node.Name -ScriptBlock {
        if (Test-Path "${env:ProgramFiles}\WindowsPowerShell\Modules\AWS.Tools.EC2") { return "AWS.Tools.EC2" }
        if (Test-Path "${env:ProgramFiles}\WindowsPowerShell\Modules\AWSPowerShell") { return "AWSPowerShell" }
        return $null
    } -ErrorAction SilentlyContinue
    if (-not $awsModule) {
        Write-Warning " AWS PowerShell module not found on node: $($node.Name). Verify with: Invoke-Command -ComputerName $($node.Name) -ScriptBlock { Get-Command Register-EC2PrivateIpAddress }"
    } else {
        Write-Host " $awsModule " -ForegroundColor Green -NoNewline
        Write-Host "found on: $($node.Name)" -ForegroundColor Cyan
        if ($awsModule -eq "AWSPowerShell") {
            Write-Host "  Modular AWS.Tools for PowerShell recommended for faster failover." -ForegroundColor Yellow
        }
    }
}

Write-Host "Deploying " -ForegroundColor Green -NoNewline
Write-Host "$WFCScriptName" -ForegroundColor Cyan -NoNewline
Write-Host " to cluster nodes:" -ForegroundColor Green
foreach ($node in $clusterNodes) {
    try {
        # Create directory if needed
        if (-not (Test-Path "\\$($node.Name)\$WFCScriptSharePath")) {
            New-Item -Path "\\$($node.Name)\$WFCScriptSharePath" -ItemType Directory -Force | Out-Null
            Write-Host " Created directory: " -ForegroundColor Green -NoNewline
            Write-Host "\\$($node.Name)\$WFCScriptSharePath" -ForegroundColor Cyan
        }
        
        # Copy script
        Copy-Item -Path "$PSScriptRoot\$WFCScriptName" -Destination "\\$($node.Name)\$WFCScriptSharePath\$WFCScriptName" -Force
        Write-Host " Copied " -ForegroundColor Green -NoNewline
        Write-Host "$WFCScriptName" -ForegroundColor Cyan -NoNewline
        Write-Host " to ClusterNode: " -ForegroundColor Green -NoNewline
        Write-Host "\\$($node.Name)\$WFCScriptSharePath" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to deploy to $($node.Name): $($_.Exception.Message)"
    }
}

Write-Host ""

# Create Cluster resource (Generic Application) to manage a role's floating IP address

# Display available cluster groups
$groups = Get-ClusterGroup
Write-Host "Available Cluster Groups:" -ForegroundColor Green
for ($i = 0; $i -lt $groups.Count; $i++) {
    Write-Host "$($i + 1). $($groups[$i].Name)"
}

# Prompt user to select a group
$selectionInput = Read-Host "Select a group to add the $WFCScriptName script to (1-$($groups.Count))"
$selection = 0
if (-not [int]::TryParse($selectionInput, [ref]$selection) -or $selection -lt 1 -or $selection -gt $groups.Count) {
    throw "Invalid selection: '$selectionInput'. Enter a number between 1 and $($groups.Count)"
}
$Group = $groups[$selection - 1].Name

Write-Host "Selected group: " -ForegroundColor Green -NoNewline
Write-Host "$Group" -ForegroundColor Cyan
Write-Host ""

# Get IP Address resources from the selected cluster group
$ipResources = Get-ClusterGroup -Name $Group | Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"}

# Check if any IP resources exist
if (-not $ipResources) {
    Write-Warning "No IP Address resources found in group '$Group'"
    return
}

# Configure the WFC 'Generic Application' which will manage the IP Address assigned the AWS ENI 
foreach ($ipResource in $ipResources) {
    # Query the IP address value
    $ipAddress = ($ipResource | Get-ClusterParameter -Name "Address").Value

    # Create a name for the WFC 'Generic Application' which shows the IP being managed
    $appName = "Move AWS IP $ipAddress"

    # Check for existing resource and remove if found
    $existingResource = Get-ClusterResource -Name $appName -ErrorAction SilentlyContinue
    if ($existingResource) {
        $response = Read-Host "Resource '$appName' exists. Remove and recreate? (y/n)"
        if ($response -eq 'y') {
            Write-Host "Stopping resource " -ForegroundColor Green -NoNewline
            Write-Host "'$appName'" -ForegroundColor Cyan -NoNewline
            Write-Host "..." -ForegroundColor Green
            Stop-ClusterResource -Name $appName -ErrorAction SilentlyContinue | Out-Null
            Remove-ClusterResource -Name $appName -Force
            Write-Host "Removed existing resource " -ForegroundColor Green -NoNewline
            Write-Host "'$appName'" -ForegroundColor Cyan
        } else {
            continue
        }
    }
    # Create the WFC 'Generic Application'
    Add-ClusterResource -Name $appName -ResourceType "Generic Application" -Group $Group | Out-Null
        
    # Set parameters for the WFC 'Generic Application'
    Get-ClusterResource $appName | Set-ClusterParameter -Multiple @{
        CommandLine             = "powershell.exe -ExecutionPolicy Bypass -File $WFCScriptName -ipAddress `"$ipAddress`""
        CurrentDirectory        = $WFCScriptPath
        UseNetworkName          = 0
        AppInstanceRegistration = 1
    }

    # Bring the resource online
    Write-Host "Added resource " -ForegroundColor Green -NoNewline
    Write-Host "'$appName'" -ForegroundColor Cyan -NoNewline
    Write-Host " to group " -ForegroundColor Green -NoNewline
    Write-Host "'$Group'" -ForegroundColor Cyan
    Start-ClusterResource -Name $appName
}

# Done
Write-Host "Installation complete" -ForegroundColor Cyan