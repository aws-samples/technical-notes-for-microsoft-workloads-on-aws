---
sidebar_position: 40
---

# Convert Office LTSC 64-bit to 32-bit on EC2 Windows

:::tip Get Started Today
Office LTSC Professional Plus 32-bit is now available on AWS Marketplace. [Launch an instance →](https://aws.amazon.com/marketplace/pp/prodview-bh46d5p2hapns)

For extra customization or manual installation, follow this guide.
:::

by Ali Alzand

This guide walks you through converting a 64-bit Office installation to 32-bit Office LTSC Professional Plus 2021 on an EC2 Windows instance and activating it using AWS License Manager.

> **Note:** This guide is specifically for instances launched from the [Office LTSC Professional Plus 2021 AWS Marketplace offering](https://aws.amazon.com/marketplace/pp/prodview-bh46d5p2hapns). It uses AWS License Manager for activation and requires the appropriate VPC endpoint configuration.

## Why 32-bit Office?

While 64-bit Office is recommended for most scenarios, you may need 32-bit Office for:
- Compatibility with legacy 32-bit add-ins or ActiveX controls
- Integration with older 32-bit applications
- Specific business requirements that depend on 32-bit COM objects

## Prerequisites
- [License Manager user-based subscriptions](https://docs.aws.amazon.com/license-manager/latest/userguide/user-based-subscriptions.html#user-subs-ms-office) configured for Microsoft Office. See this [blog post](https://aws.amazon.com/blogs/modernizing-with-aws/how-to-set-up-microsoft-office-on-amazon-ec2/) for detailed setup instructions.
- EC2 Windows instance launched from the [Office LTSC Professional Plus 2021 AWS Marketplace AMI](https://aws.amazon.com/marketplace/pp/prodview-bh46d5p2hapns) with 64-bit Office installed
- Instance deployed in a subnet with internet connectivity (required for downloading Office installation files)
- RDP access to the instance configured and tested
- User associated with administrative privileges on the instance

## Workflow
### Step 1: Uninstall 64-bit Office
1. RDP to the instance
2. Open **Programs and Features** (Control Panel)
3. Uninstall the current Office installation (64-bit version)
4. Reboot the instance

### Step 2: Prepare Office Deployment Tool
1. Download the [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117)
2. Run the executable and accept the license agreement
3. Select a folder to extract the tool (e.g., `C:\ODT`)
4. Download the [configuration.xml](/Files/Convert_Office_to_32-bit/configuration.xml)
5. Place the configuration.xml file in the ODT folder from step 3 above

### Step 3: Download and Install 32-bit Office
1. Open Command Prompt as administrator
2. Navigate to your ODT folder: `cd C:\ODT`
3. Download Office files: `setup.exe /download configuration.xml`
4. Install Office: `setup.exe /configure configuration.xml`
5. Open any Office application (e.g., Word) and accept the license agreement
6. Verify 32-bit installation by opening Word → **File** → **Account** → **About Word** (should show "32-bit")

### Step 4: Activate Office with AWS License Manager
1. In the AWS Console, go to **VPC** → **Endpoints**
2. Locate the endpoint: `com.amazonaws.<region>.activation-license-manager`
3. Copy the first DNS name (e.g., `vpce-xxxxx.activation-license-manager.us-east-1.vpce.amazonaws.com`)
4. Open PowerShell as administrator and run the following script (replace `UpdateMe` with your DNS name):

    ```powershell
    $Endpoint="UpdateMe"
    $dnsResult = Resolve-DnsName "$Endpoint" -Server "169.254.169.253" -ErrorAction Stop
    $ipv4Address = $dnsResult | Where-Object { $_.Type -eq "A" } | Select-Object -First 1
    $ServerIPAddress = $ipv4Address.IPAddress

    $Path = 'C:\Program Files (x86)\Microsoft Office\Office16'
    Set-Location -Path $Path
    Write-Output "Running the activation script with the license manager: $ServerIPAddress"
    cscript ospp.vbs /sethst:$ServerIPAddress
    cscript ospp.vbs /act
    ```
5. You should see output similar to:

    ```text
    ---Processing--------------------------
    ---------------------------------------
    Installed product key detected - attempting to activate the following product:
    SKU ID: fbdb3e18-a8ef-4fb3-9183-dffd60bd0984
    LICENSE NAME: Office 21, Office21ProPlus2021VL_KMS_Client_AE edition
    LICENSE DESCRIPTION: Office 21, VOLUME_KMSCLIENT channel
    Last 5 characters of installed product key: 6F7TH
    <Product activation successful>
    ---------------------------------------
    ---------------------------------------
    ---Exiting-----------------------------
    ```
6. Verify activation status:

    ```powershell
    cscript ospp.vbs /dstatus
    ```