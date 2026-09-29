# Windows Server 2016 to 2022 Upgrade Guide

> **Note:** This is sample code, for non-production usage. You should work with your security and legal teams to meet your organizational security, regulatory and compliance requirements before deployment.

## Overview

This automation uses SSM to orchestrate an in-place upgrade from Windows Server 2016 to 2022 directly on the existing EC2 instance.

**Why in-place on the same instance?**

- Instance ID, tags, network config (IPs, subnets, security groups), and instance profile all remain unchanged
- No Active Directory conflicts (machine SID, computer account, domain trust)
- No need to update references in load balancers, DNS, monitoring, or scripts
- Instance store volumes are preserved (reboot only, no stop/start)
- CloudWatch metrics and logs remain continuous, no gap in monitoring history
- Operationally similar to applying monthly patches: the instance reboots and comes back upgraded

**The automation handles:**

- Pre-flight checks (OS version, SSM agent, disk space, partition layout)
- AMI backup with configurable retention
- Automatic disk expansion when the root volume needs more space: extends the partition into unallocated space, or grows the EBS volume and then the partition, as needed
- Driver updates (ENA, PV, NVMe)
- Windows in-place upgrade using AWS-provided installation media
- Multi-language aware: auto-detects the OS language and selects the matching 2022 installation media (17 languages)
- Deterministic OS + .NET cumulative updates so the box isn't left at the 2022 media baseline (optional)
- Optional automatic rollback: on upgrade failure or boot loop, restores the pre-upgrade root volume from the backup (via EC2 Replace Root Volume)
- Automatic cleanup

## Supported Upgrade Path (Microsoft Reference)

Microsoft confirms that Windows Server 2016 can upgrade directly to Windows Server 2022 via installation media (two-version jump: 2016 → 2022). Non-clustered systems running Server 2022 and earlier support up to a two-version jump. No intermediate upgrade to 2019 is required.

- Standard upgrades to Standard; Datacenter upgrades to Datacenter (by default).
- You can change from Standard to Datacenter during the upgrade (not downgrade).
- Cross-language upgrades are not supported (source and target must match).

Source: [Plan your Windows Server upgrade](https://learn.microsoft.com/en-us/windows-server/get-started/install-upgrade-migrate?tabs=media)

## Prerequisites

- Windows Server 2016 EC2 instance (Standard or Datacenter edition; Windows Storage Server editions are not supported for in-place upgrade)
- License-included Windows (BYOL / Bring Your Own License instances are not supported)
- SSM Agent installed and running
- The instance must **not** be an Active Directory domain controller. Microsoft recommends clean-install promotion for AD DS servers rather than in-place upgrade ([reference](https://learn.microsoft.com/en-us/windows-server/get-started/install-upgrade-migrate)).
- If the instance uses NIC Teaming, disable NIC Teaming before running the upgrade. Re-enable it after upgrade completes ([reference](https://learn.microsoft.com/en-us/windows-server/get-started/install-upgrade-migrate)).
- Xen PV or ENA networking (SR-IOV/Intel 82599 not supported). If using a 4th-generation instance (m4, c4, etc.) with the Intel 82599 ENI, migrate to a current-generation instance type (m5, c5, or newer) before running this automation.
- SSM connectivity (internet or SSM VPC endpoints) so the automation can manage the instance
- Outbound internet (HTTPS 443) to the Microsoft Update Catalog CDN if cumulative-update patching is enabled (the default). The pinned CUs download directly from Microsoft; SSM VPC endpoints alone are not sufficient. If the instance has no internet egress, set `InstallCumulativeUpdates=false` and apply patches with your own process.
- No minimum patch level required on the source Windows Server 2016 for media-based in-place upgrade. The automation uses installation media (setup.exe), not Windows Update feature update, so no prerequisite CU is needed on the source OS.
- C: drive must be the last partition if disk expansion is needed
- **Tag the target instance `WindowsUpgrade=true`.** The automation role's instance state-change permissions (stop, start, reboot, replace root volume) are scoped by this tag, so an untagged instance is denied those actions. Apply the tag before starting: `aws ec2 create-tags --resources <instance-id> --tags Key=WindowsUpgrade,Value=true --no-cli-pager`

## Application Availability During the Upgrade

The instance reboots several times and is unavailable for the duration (similar to a larger-than-usual patch window). Treat this like routine OS patching (monthly cumulative updates): use whatever process you already run before patching that instance to stop it from serving traffic and to protect your application. For example, draining and deregistering it from the load balancer / target group, pausing health checks, enabling maintenance mode, quiescing the application or services, or scheduling a maintenance window. The automation does not modify your application, load balancer, or DNS; managing traffic and application state before and after is the owner's responsibility, just as it is for normal patching.

The instance is only rebooted, never stopped/started (this holds for the rollback path too, which uses Replace Root Volume in place). So instance-store volumes and an auto-assigned (dynamic) public IP are preserved across the upgrade.

## Supported Languages

The automation auto-detects the OS language and selects matching Windows 2022 installation media:

Chinese (Traditional), Czech, Dutch, English, French, German, Hungarian, Italian, Japanese, Korean, Polish, Portuguese (Brazil), Portuguese (Portugal), Russian, Spanish, Swedish, Turkish

> **Note:** Microsoft does not support cross-language in-place upgrades (source and target must be the same language). The automation enforces this by auto-detecting the OS language and selecting matching media.

## Quick Setup

### Option A: CloudFormation for roles + direct deploy for documents (Recommended)

**Architecture note:** Deploy the IAM roles with the CloudFormation template, then deploy the two SSM documents directly with `aws ssm create-document`. The documents cannot be embedded in the CloudFormation template: CloudFormation re-serializes the inline document content, which pushes the upgrade document past the 64 KiB SSM document limit and fails with `Invalid request provided: 64 KiB`.

**Step 1: Deploy the IAM roles stack.** The template is small, so it deploys inline with `--template-body` (no S3 staging needed).

**AWS CLI (macOS/Linux/CloudShell):**

```bash
aws cloudformation create-stack \
    --stack-name Windows2016to2022Upgrade \
    --template-body file://windows-2016-to-2022-roles-cfn.json \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-cli-pager

aws cloudformation wait stack-create-complete \
    --stack-name Windows2016to2022Upgrade --no-cli-pager

ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name Windows2016to2022Upgrade \
    --query 'Stacks[0].Outputs[?OutputKey==`AutomationRoleArn`].OutputValue' \
    --output text --no-cli-pager)

echo "Automation Role ARN: $ROLE_ARN"
```

**PowerShell (Windows):**

```powershell
aws cloudformation create-stack `
    --stack-name Windows2016to2022Upgrade `
    --template-body file://windows-2016-to-2022-roles-cfn.json `
    --capabilities CAPABILITY_NAMED_IAM `
    --no-cli-pager

aws cloudformation wait stack-create-complete `
    --stack-name Windows2016to2022Upgrade --no-cli-pager

$RoleArn = aws cloudformation describe-stacks `
    --stack-name Windows2016to2022Upgrade `
    --query 'Stacks[0].Outputs[?OutputKey==`AutomationRoleArn`].OutputValue' `
    --output text --no-cli-pager

Write-Output "Automation Role ARN: $RoleArn"
```

**Step 2: Deploy the two SSM documents directly.** The document name is case-sensitive.

**AWS CLI (macOS/Linux/CloudShell):**

```bash
aws ssm create-document \
    --name 'Windows-2016-to-2022-PreCheck' \
    --document-type 'Automation' --document-format 'JSON' \
    --content file://windows-2016-to-2022-precheck.json \
    --no-cli-pager

aws ssm create-document \
    --name 'Windows-2016-to-2022-Upgrade' \
    --document-type 'Automation' --document-format 'JSON' \
    --content file://Windows-2016-to-2022-Upgrade.json \
    --no-cli-pager
```

**PowerShell (Windows):**

```powershell
aws ssm create-document `
    --name 'Windows-2016-to-2022-PreCheck' `
    --document-type 'Automation' --document-format 'JSON' `
    --content file://windows-2016-to-2022-precheck.json `
    --no-cli-pager

aws ssm create-document `
    --name 'Windows-2016-to-2022-Upgrade' `
    --document-type 'Automation' --document-format 'JSON' `
    --content file://Windows-2016-to-2022-Upgrade.json `
    --no-cli-pager
```

**Cleanup after all upgrades are complete** (remove documents first, then the roles stack):

**AWS CLI (macOS/Linux/CloudShell):**

```bash
aws ssm delete-document --name 'Windows-2016-to-2022-Upgrade' --no-cli-pager
aws ssm delete-document --name 'Windows-2016-to-2022-PreCheck' --no-cli-pager
aws cloudformation delete-stack --stack-name Windows2016to2022Upgrade --no-cli-pager
```

**PowerShell (Windows):**

```powershell
aws ssm delete-document --name 'Windows-2016-to-2022-Upgrade' --no-cli-pager
aws ssm delete-document --name 'Windows-2016-to-2022-PreCheck' --no-cli-pager
aws cloudformation delete-stack --stack-name Windows2016to2022Upgrade --no-cli-pager
```

> **Updating a document later:** `aws ssm update-document --name '<name>' --document-version '$LATEST' --content file://<file>` creates a new version. If you keep the documents in CloudFormation instead, every `AWS::SSM::Document` with a custom `Name` must set `"UpdateMethod": "NewVersion"`, or stack updates fail with "cannot update a stack when a custom-named resource requires replacing".

Skip to [Run PreCheck or Start Upgrade](#run-precheck-or-start-upgrade) once the roles stack and both documents are deployed.

### Option B: Manual Setup

#### 1. Create IAM Roles

The automation requires two IAM roles:

1. **Automation Service Role** (WindowsUpgradeAutomationRole): assumed by SSM Automation to orchestrate the upgrade (calls EC2, SSM, IAM, and SNS APIs on your behalf).
2. **Instance Role** (WindowsUpgradeInstanceRole + WindowsUpgradeInstanceProfile): temporarily attached to instances that don't have SSM permissions. The automation attaches it before the upgrade and removes it afterward. If your instances already have an instance profile with `AmazonSSMManagedInstanceCore`, this role is not used.

**AWS CLI (macOS/Linux/CloudShell):**

Run these from the `ssm-documents/` directory (it contains `windows-2016-to-2022-automation-policy.json`). The commands substitute your account ID into the policy automatically.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)

# --- 1. Automation Service Role ---
aws iam create-role \
    --role-name WindowsUpgradeAutomationRole \
    --assume-role-policy-document '{
        "Version":"2012-10-17",
        "Statement":[{
            "Effect":"Allow",
            "Principal":{"Service":"ssm.amazonaws.com"},
            "Action":"sts:AssumeRole"
        }]
    }' --no-cli-pager

# Substitute your account ID into the scoped policy, then attach it
sed "s/YOUR_ACCOUNT_ID/${ACCOUNT_ID}/g" \
    windows-2016-to-2022-automation-policy.json > /tmp/windows-upgrade-policy.json

aws iam put-role-policy \
    --role-name WindowsUpgradeAutomationRole \
    --policy-name WindowsUpgradeAutomationPolicy \
    --policy-document file:///tmp/windows-upgrade-policy.json \
    --no-cli-pager

# --- 2. Instance Role (temporary SSM access) ---
aws iam create-role \
    --role-name WindowsUpgradeInstanceRole \
    --assume-role-policy-document '{
        "Version":"2012-10-17",
        "Statement":[{
            "Effect":"Allow",
            "Principal":{"Service":"ec2.amazonaws.com"},
            "Action":"sts:AssumeRole"
        }]
    }' --no-cli-pager

aws iam attach-role-policy \
    --role-name WindowsUpgradeInstanceRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
    --no-cli-pager

aws iam create-instance-profile \
    --instance-profile-name WindowsUpgradeInstanceProfile \
    --no-cli-pager

aws iam add-role-to-instance-profile \
    --instance-profile-name WindowsUpgradeInstanceProfile \
    --role-name WindowsUpgradeInstanceRole \
    --no-cli-pager
```

**PowerShell (Windows):**

Run these from the `ssm-documents/` directory (it contains `windows-2016-to-2022-automation-policy.json`). The commands substitute your account ID into the policy automatically.

```powershell
# --- 1. Automation Service Role ---
New-IAMRole `
    -RoleName 'WindowsUpgradeAutomationRole' `
    -AssumeRolePolicyDocument '{
        "Version":"2012-10-17",
        "Statement":[{
            "Effect":"Allow",
            "Principal":{"Service":"ssm.amazonaws.com"},
            "Action":"sts:AssumeRole"
        }]
    }'

$AccountId = (Get-STSCallerIdentity).Account
$policy = (Get-Content windows-2016-to-2022-automation-policy.json -Raw).Replace('YOUR_ACCOUNT_ID', $AccountId)

Write-IAMRolePolicy `
    -RoleName 'WindowsUpgradeAutomationRole' `
    -PolicyName 'WindowsUpgradeAutomationPolicy' `
    -PolicyDocument $policy

# --- 2. Instance Role (temporary SSM access) ---
New-IAMRole `
    -RoleName 'WindowsUpgradeInstanceRole' `
    -AssumeRolePolicyDocument '{
        "Version":"2012-10-17",
        "Statement":[{
            "Effect":"Allow",
            "Principal":{"Service":"ec2.amazonaws.com"},
            "Action":"sts:AssumeRole"
        }]
    }'

Register-IAMRolePolicy `
    -RoleName 'WindowsUpgradeInstanceRole' `
    -PolicyArn 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'

New-IAMInstanceProfile `
    -InstanceProfileName 'WindowsUpgradeInstanceProfile'

Add-IAMRoleToInstanceProfile `
    -InstanceProfileName 'WindowsUpgradeInstanceProfile' `
    -RoleName 'WindowsUpgradeInstanceRole'
```

#### 2. Deploy SSM Automation Documents

Download the SSM documents (and, if you used the manual role setup above, the policy file):

- `Windows-2016-to-2022-Upgrade.json`
- `windows-2016-to-2022-precheck.json`
- `windows-2016-to-2022-automation-policy.json` (only for Option B manual role setup)

Upload to CloudShell and run:

**AWS CLI (macOS/Linux/CloudShell):**

> **Important:** The document name is case-sensitive. The upgrade automation references `Windows-2016-to-2022-PreCheck` (capital P, capital C). Make sure the `--name` parameter matches exactly.

```bash
aws ssm create-document \
    --name 'Windows-2016-to-2022-PreCheck' \
    --document-type 'Automation' --document-format 'JSON' \
    --content file://windows-2016-to-2022-precheck.json \
    --no-cli-pager

aws ssm create-document \
    --name 'Windows-2016-to-2022-Upgrade' \
    --document-type 'Automation' --document-format 'JSON' \
    --content file://Windows-2016-to-2022-Upgrade.json \
    --no-cli-pager
```

**PowerShell (Windows):**

```powershell
aws ssm create-document `
    --name 'Windows-2016-to-2022-PreCheck' `
    --document-type 'Automation' --document-format 'JSON' `
    --content file://windows-2016-to-2022-precheck.json `
    --no-cli-pager

aws ssm create-document `
    --name 'Windows-2016-to-2022-Upgrade' `
    --document-type 'Automation' --document-format 'JSON' `
    --content file://Windows-2016-to-2022-Upgrade.json `
    --no-cli-pager
```

See the [SSM Automation User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html) for more on creating and managing automation documents.

## Run PreCheck or Start Upgrade

**AWS CLI (macOS/Linux/CloudShell):**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

EXEC_ID=$(aws ssm start-automation-execution \
    --document-name 'Windows-2016-to-2022-Upgrade' \
    --parameters "{
        \"InstanceId\": [\"i-0123456789abcdef0\"],
        \"AutomationAssumeRole\": [\"arn:aws:iam::${ACCOUNT_ID}:role/WindowsUpgradeAutomationRole\"]
    }" \
    --query 'AutomationExecutionId' --output text --no-cli-pager)

echo "Execution ID: $EXEC_ID"
# Add \"DryRun\": [\"true\"] to the parameters to run pre-flight checks only
```

**PowerShell (Windows):**

```powershell
# Run from CloudShell (region auto-detected)
$AccountId = (Get-STSCallerIdentity).Account

Start-SSMAutomationExecution -DocumentName 'Windows-2016-to-2022-Upgrade' -Parameter @{
    InstanceId = 'i-0123456789abcdef0'
    AutomationAssumeRole = "arn:aws:iam::${AccountId}:role/WindowsUpgradeAutomationRole"
    # DryRun = 'true'  # Uncomment to run pre-flight checks only
}
```

### From the Systems Manager Console

You can also run it from the web console instead of CloudShell:

1. Open the [Systems Manager Automation console](https://console.aws.amazon.com/systems-manager/automation) (top-right region selector must be the instance's region).
2. Choose **Execute automation**.
3. Under **Choose document**, open the **Owned by me** tab and select `Windows-2016-to-2022-Upgrade` (or `Windows-2016-to-2022-PreCheck`), then **Next**.
4. Leave **Simple execution** selected and fill in the parameters (at minimum `InstanceId` and `AutomationAssumeRole`; set `DryRun = true` for pre-flight checks only).
5. Choose **Execute**, then watch step-by-step progress on the execution detail page.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| InstanceId | (required) | EC2 instance to upgrade |
| AutomationAssumeRole | (required) | ARN of WindowsUpgradeAutomationRole |
| DryRun | false | Run pre-flight checks only, no changes |
| AutoRollback | false | Automatically rollback if upgrade fails |
| BackupRetentionDays | 30 | Days to retain backup AMI |
| WaitForBackupAMI | false | Wait for AMI to complete before proceeding |
| InstallCumulativeUpdates | true | Install pinned OS + .NET CUs after upgrade; false skips patching |
| PinnedCumulativeUpdateUrl | Sept 2026 KB5122882 | Catalog .msu URL of the OS cumulative update (SSU+LCU) |
| PinnedDotNetUpdateUrl | KB5126050 | Catalog .msu URL of the .NET Framework CU |
| UpgradeInstanceProfileName | WindowsUpgradeInstanceProfile | Instance profile to attach if the instance has no instance profile (removed afterward) |
| NotificationTopicArn | "" | SNS topic for completion notification |

## Monitor Progress

### List All Running Upgrades

**AWS CLI (macOS/Linux/CloudShell):**

```bash
aws ssm describe-automation-executions \
    --filters "Key=DocumentNamePrefix,Values=Windows-2016-to-2022-Upgrade" \
    --query "AutomationExecutionMetadataList[?AutomationExecutionStatus=='InProgress' || AutomationExecutionStatus=='Success' || AutomationExecutionStatus=='Failed' || AutomationExecutionStatus=='TimedOut'].{ExecId:AutomationExecutionId,Status:AutomationExecutionStatus,Step:CurrentStepName}" \
    --output table --no-cli-pager
```

**PowerShell (Windows):**

```powershell
Get-SSMAutomationExecutionList -Filter @{
    Key='DocumentNamePrefix';Values='Windows-2016-to-2022-Upgrade'
} |
  Where-Object { $_.AutomationExecutionStatus -in @('InProgress','Success','Failed','TimedOut') } |
  ForEach-Object {
    $d = Get-SSMAutomationExecution -AutomationExecutionId $_.AutomationExecutionId
    if (-not $d.Parameters.ContainsKey('InstanceId')) { return }
    $id = $d.Parameters['InstanceId'][0]
    $name = try { ((Get-EC2Instance $id).Instances[0].Tags |
        Where-Object Key -eq Name).Value } catch {''}
    [PSCustomObject]@{
        Name=$name; Instance=$id;
        Status=$_.AutomationExecutionStatus;
        Step=$_.CurrentStepName;
        ExecId=$_.AutomationExecutionId
    }
  } | Format-Table
```

### View Step-by-Step Progress

**AWS CLI (macOS/Linux/CloudShell):**

Uses `$EXEC_ID` from the start command above:

```bash
aws ssm get-automation-execution \
    --automation-execution-id "$EXEC_ID" \
    --query "AutomationExecution.StepExecutions[?StepStatus!='Pending'].{Step:StepName,Status:StepStatus}" \
    --output table --no-cli-pager
```

**PowerShell (Windows):**

```powershell
$ExecId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
(Get-SSMAutomationExecution -AutomationExecutionId $ExecId).StepExecutions |
    Where-Object { $_.StepStatus -ne 'Pending' } |
    Select-Object StepName, StepStatus | Format-Table -AutoSize
```

## Automation Steps

See the [Automation Flowchart](./flowchart) for a visual diagram of all execution paths (happy path, rollback, and failure cleanup).

### Temporary Upgrade Profile (IAM)

If the instance has no instance profile, the automation attaches a temporary one (`UpgradeInstanceProfileName`, default `WindowsUpgradeInstanceProfile`) so SSM can drive the upgrade, and removes it when finished. Removal behavior:

- **On success:** always removed (RemoveTempProfile).
- **On upgrade failure / rollback:** removed (FailRemoveTempProfile / RollbackRemoveTempProfile).
- **On any other step abort:** the failing step routes to a cleanup path that removes the temp profile and then fails loud. Steps that run after the upgrade EBS volume is created (volume attach/mount) route through FailCleanupUpgradeVolume first, so that volume is deleted before the profile is removed and the automation fails (no orphaned volume). Earlier steps (no volume yet) route straight to CleanupTempProfileOnFailure. EnsureSsmAccess also self-cleans if it attaches the profile but SSM never comes online.

When the default profile (`WindowsUpgradeInstanceProfile`) is used, it is removed in every path. If you set the `UpgradeInstanceProfileName` parameter to a different profile of your own, removal is best-effort on failure: it is always attempted and is reliably removed on success, but if the cleanup call itself fails (throttling, transient API error), the automation aborts loudly and that profile may stay attached for manual cleanup. In all cases the automation never modifies an instance profile the instance already had.

### DryRun=true (Pre-Flight Checks Only)

Runs the PreCheck document and reports results. Never modifies the instance. If the instance lacks SSM permissions, API-based checks run and OS-level checks are skipped.

### DryRun=false (Full Upgrade)

 1. **EnsureSsmAccess** — If the instance has an instance profile granting SSM permissions, use it. If it has an instance profile without SSM permissions, fail with guidance (the automation does not modify the instance's existing profile). If it has no instance profile, attach a temporary WindowsUpgradeInstanceProfile (removed at the end).
 2. **RunPreflightChecks** — Call PreCheck document (instance now has SSM permissions)
 3. **CreateBackupImage** — Create AMI (reboots instance for filesystem consistency)
 4. **DeprecateBackupImage** — Set AMI deprecation date based on BackupRetentionDays
 5. **WaitForInstanceAfterReboot** — Poll SSM agent: wait for offline (reboot started) then online (reboot complete)
 6. **UpdateSSMAgent** — Update SSM Agent to latest version
 7. **CheckDiskSpaceAndExpand** — If under 20 GB free, expand EBS volume and extend C: to max
 8. **FindWindows2022Snapshot** — Detect OS language, find matching AWS installation media snapshot
 9. **CreateUpgradeVolume** — Create GP3 volume from snapshot (initializes during driver installs)
10. **Install drivers** — Update ENA, PV, NVMe drivers
11. **MigrateToEC2Launchv2** — Install or update EC2Launch v2 (AWSEC2Launch-Agent) via AWS-ConfigureAWSPackage. EC2Launch v2 supports Server 2016+, so installing it before the upgrade ensures the agent is already in place when the OS transitions to 2022. Best-effort: failure does not abort the run.
12. **AttachUpgradeVolume** — Find available device (/dev/sdf-sdp) and attach volume
13. **InitializeAndMountVolume** — Bring disk online, assign drive letter, mount ISO if needed, verify setup.exe
14. **PerformUpgrade** — Run `setup.exe /auto upgrade /dynamicupdate disable`
15. **Verification chain (InitialUpgradeWait + VerifyUpgrade1–8 + Sleep1–7)** — A multi-step verification chain giving a ~90-minute window. `InitialUpgradeWait` is an `aws:sleep` of PT10M, then up to 8 `VerifyUpgrade` steps each poll for SSM agent online + OS reporting Windows Server 2022 with IMAGE_STATE_COMPLETE, separated by `aws:sleep` PT10M cycles. **Why a chain and not one step:** `aws:executeScript` has a hard 600-second (10-minute) handler cap that overrides the step's `timeoutSeconds`, so a single long-polling step is killed at 10 minutes while the OS is still mid-upgrade. The long waits therefore use `aws:sleep` (no cap) and each verify step stays under its 480s timeout. Cycles 1–7 branch: UPGRADE_COMPLETE → CleanupUpgradeVolume, otherwise → next Sleep. Cycle 8 is the final gate: it raises on still-incomplete → AutoRollback. Any cycle detecting IMAGE_STATE_UNDEPLOYABLE raises immediately → AutoRollback.
16. **CleanupUpgradeVolume** — Detach and delete upgrade EBS volume
17. **InstallPinnedUpdates** — Download the pinned OS CU (SSU+LCU) and .NET CU .msus, extract, and install via DISM (SSU first, then LCUs); single reboot finalizes all three. Skipped if `InstallCumulativeUpdates=false`. Best-effort: patch failures do not fail the run (the OS upgrade already succeeded).
18. **VerifyPatchLevel** — Poll until the pinned OS CU shows installed (Get-HotFix); activity-aware: waits only while servicing is active (RebootPending / TiWorker), fails fast if it settles without the CU; also confirms the .NET CU. Best-effort (does not abort the run).
19. **RemoveRecoveryPartition** — Delete recovery partition created by upgrade, extend C: to reclaim space
20. **RemoveTempProfile** — Remove the temporary WindowsUpgradeInstanceProfile if the automation attached one (no-op if the instance already had its own instance profile)
21. **SendSuccessNotification** — Publish to SNS topic (if NotificationTopicArn provided)

Defender platform and definition updates self-update independently, so they are not installed here. Customers who skip patching (`InstallCumulativeUpdates=false`) or want absolute-latest should run their own patch process after the upgrade.

## Patching Behavior and Updating the Pinned CUs

The 2022 installation media is static: it always lands the OS at the initial 2022 baseline (build 20348.x) and includes .NET 4.8 in-box. Windows Update does not reliably surface the current OS cumulative for ~30 minutes after an in-place upgrade, so the automation installs pinned cumulative updates by direct Microsoft Update Catalog URL instead of relying on Windows Update. This is deterministic and reproducible.

Patching is best-effort and non-fatal. The mission is the 2016→2022 upgrade (2016 is approaching end of support); patching is a follow-up. The patch steps (InstallPinnedUpdates → RebootAfterUpdates → WaitForInstanceAfterUpdates → VerifyPatchLevel) run with `onFailure: Continue`, so if the pinned CU can't be downloaded or installed (bad/expired URL, transient error), the automation logs the failure on those steps but still completes successfully. The instance is left upgraded, the recovery partition reclaimed, and the temp profile removed. Apply the CU afterward with your own patch process. Check the InstallPinnedUpdates/VerifyPatchLevel step status to see whether the pinned CU actually applied.

The box lands at the pinned patch level (a known floor), not necessarily absolute-latest. That's intentional: your normal patch process (Patch Manager, WSUS, etc.) brings it fully current afterward. Two supported modes:

- **Default** (`InstallCumulativeUpdates=true`): installs the pinned Sept 2026 OS CU (KB5122882) + .NET CU (KB5126050), then your process trues up.
- **Skip** (`InstallCumulativeUpdates=false`): no patching for a faster run; your process handles everything.

Either way the box is not silently left thinking it's patched at 2022 media-baseline levels.

### Raising the Floor (Getting a Newer CU URL)

The operative parameters are the URLs (`PinnedCumulativeUpdateUrl`, `PinnedDotNetUpdateUrl`); the KB id is parsed from each URL automatically for log messages. To pin a newer CU, open the [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/), search the KB (e.g. the latest "Cumulative Update for Windows Server 2022 ... x64"), click Download, and copy the .msu link.

Notes:

- **OS CU** = the combined SSU+LCU x64 .msu (language/edition-neutral). The automation extracts it and installs the SSU cab before the LCU cab.
- **.NET CU** = the .NET 4.8 x64 .msu for Server 2022. Windows Server 2022 ships with .NET 4.8 in-box (unlike 2019 which shipped 4.7.2), so the .NET CU targets 4.8 directly.
- Update the Url parameter. The KB id is parsed from the URL automatically and used both to label logs and to verify (via Get-HotFix) that the exact pinned CU installed.

## Rollback

If `AutoRollback=true` and the upgrade fails or a boot loop is detected:

1. The upgrade volume is cleaned up
2. The backup snapshot is retrieved from the pre-upgrade AMI
3. EC2 Replace Root Volume restores the original root volume
4. The temporary upgrade profile is removed (if the automation attached one)
5. A failure notification is sent (if SNS topic configured)

If `AutoRollback=false` (default), the automation fails and leaves the instance in its current state for investigation.

### Manual Rollback

If automatic rollback is disabled or fails:

**AWS CLI (macOS/Linux/CloudShell):**

```bash
INSTANCE_ID='i-0123456789abcdef0'
EXEC_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Get backup AMI ID from automation outputs
AMI_ID=$(aws ssm get-automation-execution \
    --automation-execution-id "$EXEC_ID" \
    --query "AutomationExecution.Outputs.\"CreateBackupImage.BackupImageId\"[0]" \
    --output text --no-cli-pager)

# Get the snapshot ID from the AMI (required if the root volume was expanded during upgrade)
SNAPSHOT_ID=$(aws ec2 describe-images \
    --image-ids "$AMI_ID" \
    --query "Images[0].BlockDeviceMappings[?DeviceName=='/dev/sda1'].Ebs.SnapshotId" \
    --output text --no-cli-pager)

# Replace root volume from snapshot
aws ec2 create-replace-root-volume-task \
    --instance-id "$INSTANCE_ID" \
    --snapshot-id "$SNAPSHOT_ID" \
    --volume-initialization-rate 300 \
    --delete-replaced-root-volume \
    --no-cli-pager
```

**PowerShell (Windows):**

```powershell
# Run from CloudShell (region auto-detected)
$InstanceId = 'i-0123456789abcdef0'
$execId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Get backup AMI ID from automation outputs
$exec = Get-SSMAutomationExecution -AutomationExecutionId $execId
$amiId = $exec.Outputs['CreateBackupImage.BackupImageId']

# Get the snapshot ID from the AMI (required if root volume was expanded)
$ami = Get-EC2Image -ImageId $amiId
$snapshotId = ($ami.BlockDeviceMappings |
    Where-Object { $_.DeviceName -eq '/dev/sda1' }).Ebs.SnapshotId

# Replace root volume from snapshot
# Note: Use snapshot (not AMI) if root volume size was increased during upgrade,
# because EC2 Replace Root Volume requires matching volume size when using AMI directly
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/replace-root.html
New-EC2ReplaceRootVolumeTask `
    -InstanceId $InstanceId `
    -SnapshotId $snapshotId `
    -VolumeInitializationRate 300 `
    -DeleteReplacedRootVolume $true
```

## Troubleshooting

### Manual in-place upgrade (fallback)

If the automation fails for any reason and you need to proceed, AWS documents the manual in-place upgrade procedure here: [Perform an in-place upgrade of the Windows OS on your EC2 instance](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/os-inplaceupgrade.html). This automation implements the same overall flow (backup, drivers, installation-media volume, `setup.exe /auto upgrade`); the AWS guide is the authoritative manual reference if you need to run the steps by hand or diagnose a specific stage.

### PreUpgradeCheck fails with EC2Config error

EC2Config is not supported on Windows 2022. Migrate to EC2Launch first: [EC2Launch docs](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch.html)

### CheckWindowsBYOL fails

This automation supports license-included Windows only. BYOL (Bring Your Own License) instances use customer-provided media and licensing, which is incompatible with the AWS-provided installation media used by this automation. If you need to upgrade a BYOL instance, use the manual in-place upgrade procedure with your own installation media, or use AWS License Manager to convert from BYOL to license-included before running this automation.

### CheckXenSriovCompatibility fails

C3, C4, D2, I2, M4 (except m4.16xlarge), R3 with SR-IOV are not supported. Migrate to a newer instance type (e.g. C5, M5, R4/R5, I3, D3) before upgrading.

### Upgrade times out

Check SSM Automation execution details for step outputs. Check Windows Setup logs on instance: `C:\$WINDOWS.~BT\Sources\Panther\`

If a verify step fails with `TimeoutError: Function handler_with_timeout timed out after 600.0 seconds`, that is the hard `aws:executeScript` handler cap, not the upgrade itself. Do not raise the step's `timeoutSeconds` (it is ignored above 600s). Keep each verify step short (≤480s) and use `aws:sleep` for the long inter-cycle waits; the shipped document already does this across the 8-cycle chain.

### PreCheck or verify sub-automation times out on t2 instances

On burstable t2 instances, repeated upgrade/rollback cycles can exhaust CPU credits, throttling the box to baseline so SSM commands run slowly enough to time out the PreCheck (or a verify) sub-automation, even though the checks themselves pass. Standard t2 credits reset on stop/start, so stopping and starting the instance restores a fresh credit balance and clears the timeout. For a clean test record, prefer launching a fresh instance rather than reusing one that has been through prior upgrade/rollback churn.

### Deploy fails with "Invalid request provided: 64 KiB"

SSM automation documents have a hard 64 KiB content limit. Deploy the documents directly with `aws ssm create-document --content file://...` from the minified JSON (do not embed them in a CloudFormation template — CloudFormation re-serializes the inline `Content` object with indentation, pushing it back over 64 KiB even if your file is minified). See Quick Setup Option A.

### Disk expansion fails

C: must be the last partition on the disk to auto-expand. MBR disks cannot exceed 2TB.

## Observed Upgrade Times

30GB root volume, gp3:

| Instance Type | Platform | Upgrade | Total |
|---------------|----------|---------|-------|
| c8id.xlarge | Nitro | ~15 min | ~52 min |
| m8a.2xlarge | Nitro AMD | ~15 min | ~40 min |
| m8a.xlarge | Nitro AMD | ~20 min | ~44 min |
| t3.large | Nitro | ~21 min | ~58 min |
| m8i.2xlarge | Nitro Intel | ~23 min | ~50 min |
| t3a.large | Nitro AMD | ~25 min | ~67 min |
| t2.2xlarge | Xen | ~27 min | ~63 min |
| t2.xlarge | Xen | ~27 min | ~62 min |
| t2.large | Xen | ~29 min | ~64 min |

Total time includes pre-upgrade steps (backup AMI, reboot, disk expansion, driver updates) and post-upgrade Windows Updates. Actual times vary depending on Windows Update availability.
