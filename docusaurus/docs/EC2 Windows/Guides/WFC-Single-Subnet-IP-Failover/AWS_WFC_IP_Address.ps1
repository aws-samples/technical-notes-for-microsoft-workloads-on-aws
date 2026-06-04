param(
    [Parameter(Mandatory=$true)]
    [string]$ipAddress
)

# Ensure event source exists
if (-not [System.Diagnostics.EventLog]::SourceExists("AWSClusterIPScript")) {
    New-EventLog -LogName System -Source "AWSClusterIPScript"
}

try {
    try {
        # Get session token for Instance Metadata v2 (IMDSv2) and ENI ID
        $token = Invoke-RestMethod -Uri "http://169.254.169.254/latest/api/token" -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"}
        $mac = (Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/" -Headers @{"X-aws-ec2-metadata-token" = $token}).Trim()
        $eniId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/$mac/interface-id" -Headers @{"X-aws-ec2-metadata-token" = $token}
    }
    catch {
        # Fallback to IMDSv1 if needed and get ENI ID
        $mac = (Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/").Trim()
        $eniId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/$mac/interface-id"
    } 

    # Register IP using and AWS API - requires the EC2 Instance have an IAM role attached with necessary permissions.   
    Register-EC2PrivateIpAddress -NetworkInterfaceId $eniId -PrivateIpAddress $ipAddress -AllowReassignment $true


    # Confirm initial registration with retries
    $ENI_IPFound = $false
    $maxRetries = 5
    for ($i = 1; $i -le $maxRetries; $i++) {
         # If the IP address is found on the ENI, set $ENI_IPFound to true and break out of the retry loop
        try {
            if ((Get-EC2NetworkInterface -NetworkInterfaceId $eniId).PrivateIpAddresses | Where-Object { $_.PrivateIpAddress -eq $ipAddress }) {
                $ENI_IPFound = $true
                # After $ENI_IPFound is set to true, the loop breaks and control moves to the if($ENI_IPFound) block
                # which logs success and starts continuous monitoring of the IP registration
                break
            }
        } catch {
            # Continue retrying on API errors
            Write-EventLog -LogName System -Source "AWSClusterIPScript" -EventId 1003 -Message "Retry $i failed for IP $ipAddress - $($_.Exception.Message)" -EntryType Warning -ErrorAction SilentlyContinue
        }
        if ($i -lt $maxRetries) {
            Start-Sleep -Seconds 2 
        }
    }
    if ($ENI_IPFound) {
        Write-EventLog -LogName System -Source "AWSClusterIPScript" -EventId 1001 -Message "IP $ipAddress assigned to AWS ENI successfully" -EntryType Information -ErrorAction SilentlyContinue
        # Monitor IP registration
        while ($true) {
            try {
                if (-not ((Get-EC2NetworkInterface -NetworkInterfaceId $eniId).PrivateIpAddresses | Where-Object { $_.PrivateIpAddress -eq $ipAddress })) {
                    Write-EventLog -LogName System -Source "AWSClusterIPScript" -EventId 1002 -Message "ERROR - IP $ipAddress not detected on ENI $eniId" -EntryType Error -ErrorAction SilentlyContinue
                    exit 1
                }
            } catch {
                # AWS API unavailable - exit since we can't verify IP status
                Write-EventLog -LogName System -Source "AWSClusterIPScript" -EventId 1007 -Message "AWS API unavailable for IP $ipAddress - exiting" -EntryType Error -ErrorAction SilentlyContinue
                exit 1
            }
            Start-Sleep -Seconds 120
        }
    } else {
        Write-EventLog -LogName System -Source "AWSClusterIPScript" -EventId 1005 -Message "FAILED - IP $ipAddress not confirmed via AWS API after $maxRetries retries" -EntryType Error -ErrorAction SilentlyContinue
        exit 1
    }
} catch {
    Write-EventLog -LogName System -Source "AWSClusterIPScript" -EventId 1006 -Message "ERROR with IP $ipAddress - $($_.Exception.Message)" -EntryType Error -ErrorAction SilentlyContinue
    exit 1
}