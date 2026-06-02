# Set-ThreadsPerCore — SSM Automation Document

An AWS Systems Manager Automation document that sets ThreadsPerCore=1 on EC2 instances to disable SMT (Simultaneous Multithreading), reducing Windows and SQL Server license-included costs.

## What it does

For each target instance, the document:

1. Checks if the instance is bare metal or doesn't support the requested ThreadsPerCore (skips if so)
2. Checks if ThreadsPerCore already matches the requested value (skips if so)
3. For stopped instances: modifies CPU options directly
4. For running instances (when allowed): stops the instance, modifies CPU options, restarts it
5. Sets CoreCount based on the `CoreCount` parameter (`default` = instance type's full core count, `current` = keep existing)

## Safety checks

The document includes several pre-flight checks that **fail safe** — if an API call errors
(missing permissions, throttling), the automation aborts rather than proceeding with the modification.

| Check | Default | Behavior |
|---|---|---|
| Bare metal | always skip | Bare metal instances don't support Optimize CPUs |
| Platform mismatch | skip | Only modifies instances matching the `Platform` parameter. Set `Platform=All` to override |
| Unsupported TPC | always skip | Instance types that don't support the requested ThreadsPerCore |
| Auto Scaling group | always skip | Instances in an ASG are always skipped. API errors abort (fail-safe). |
| Instance store | skip | Ephemeral data lost on stop. Set `SkipInstanceStore=no` to override |
| Non-EIP public IP | skip | Public IP changes on stop/start. API errors abort (fail-safe). Set `SkipPublicIP=no` to override |
| Running instances | skip | Set `StopStartedInstances=yes` to allow stop/modify/restart |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `InstanceId` | *(required)* | EC2 instance ID (use SSM targeting for multiple instances) |
| `ThreadsPerCore` | `1` | Threads per core to set (`1` to disable SMT, `2` to re-enable) |
| `CoreCount` | `current` | Core count: `default` (instance type's full core count) or `current` (keep existing) |
| `StopStartedInstances` | `no` | Allow stopping running instances to modify CPU options |
| `Platform` | `Windows` | Platform filter: `Windows`, `Linux`, or `All` |
| `SkipPublicIP` | `yes` | Skip running instances with non-EIP public IPs |
| `SkipInstanceStore` | `yes` | Skip running instances on types with instance store |

## Usage

### Install the document

```powershell
New-SSMDocument `
    -Name "Set-ThreadsPerCore" `
    -DocumentType "Automation" `
    -Content (Get-Content -Raw Set-ThreadsPerCore.yaml) `
    -DocumentFormat YAML `
    -Region us-east-1
```

### Run on a single stopped instance

```powershell
Start-SSMAutomationExecution `
    -DocumentName "Set-ThreadsPerCore" `
    -Parameter @{InstanceId=@("i-0abc123def456789a")} `
    -Region us-east-1
```

### Run on a single running instance (stop, modify, restart)

```powershell
Start-SSMAutomationExecution `
    -DocumentName "Set-ThreadsPerCore" `
    -Parameter @{InstanceId=@("i-0abc123def456789a"); StopStartedInstances=@("yes")} `
    -Region us-east-1
```

### Re-enable SMT (set ThreadsPerCore back to 2)

```powershell
Start-SSMAutomationExecution `
    -DocumentName "Set-ThreadsPerCore" `
    -Parameter @{InstanceId=@("i-0abc123def456789a"); ThreadsPerCore=@("2")} `
    -Region us-east-1
```

### Run on multiple instances using tags

```powershell
Start-SSMAutomationExecution `
    -DocumentName "Set-ThreadsPerCore" `
    -Target @{Key="tag:Env"; Values=@("Production")} `
    -TargetParameterName "InstanceId" `
    -MaxConcurrency "5" `
    -MaxError "1" `
    -Region us-east-1
```

### Run on instances with TPC=2 (pre-filtered)

```powershell
$tpc2 = (Get-EC2Instance -Region us-east-1 -Filter @{Name='instance-state-name'; Values=@('running','stopped')}).Instances |
    Where-Object { $_.CpuOptions.ThreadsPerCore -eq 2 } |
    Select-Object -ExpandProperty InstanceId

Start-SSMAutomationExecution `
    -DocumentName "Set-ThreadsPerCore" `
    -Target @{Key="ParameterValues"; Values=$tpc2} `
    -TargetParameterName "InstanceId" `
    -Parameter @{StopStartedInstances=@("yes")} `
    -MaxConcurrency "5" `
    -MaxError "1" `
    -Region us-east-1
```

### Run from the SSM Console

1. Open [Systems Manager > Automation](https://console.aws.amazon.com/systems-manager/automation)
2. Click "Execute automation"
3. Search for "Set-ThreadsPerCore"
4. Choose "Simple execution" for a single instance, or "Rate control" for multiple
5. Fill in parameters and execute

## Permissions required

The caller (IAM user/role) needs:

- `ec2:DescribeInstances`
- `ec2:DescribeInstanceTypes`
- `ec2:DescribeNetworkInterfaces`
- `ec2:ModifyInstanceCpuOptions`
- `ec2:StopInstances` (if StopStartedInstances=yes)
- `ec2:StartInstances` (if StopStartedInstances=yes)
- `autoscaling:DescribeAutoScalingInstances`
- `ssm:StartAutomationExecution`

No IAM assume role is used — the document runs with the caller's permissions.

## Skip reasons

When an instance is skipped, the automation ends with a descriptive step name:

| Step | Reason |
|---|---|
| `AlreadyConfigured` | ThreadsPerCore already matches the requested value |
| `SkippedBareMetal` | Instance is bare metal (Optimize CPUs not supported) |
| `SkippedNonWindows` | Instance platform doesn't match the `Platform` parameter |
| `SkippedUnsupportedTPC` | Requested ThreadsPerCore not supported by the instance type |
| `SkippedRunning` | Instance is running and StopStartedInstances=no |
| `SkippedASG` | Instance is in an Auto Scaling group |
| `SkippedPublicIP` | Instance has a non-EIP public IP |
| `SkippedInstanceStore` | Instance type has instance store volumes |
| `SkippedUnsupportedState` | Instance is not running or stopped |

## Notes

- CPU options can only be modified on stopped instances — the document handles the stop/start cycle.
- CoreCount is always set to the instance type's default (all physical cores). Only ThreadsPerCore is changed.
- Instances already configured with ThreadsPerCore=1 are detected and skipped immediately.
- Use `ThreadsPerCore=2` to re-enable SMT if needed.
- SSM Automation is regional — the document must be installed in each region where you want to target instances. Use `-Region` to specify the target region when running from the command line.

## Author

Craig Cooley (coolcrai@amazon.com) — May 2026
Built with [Kiro](https://kiro.dev) IDE + Claude Opus 4.6
