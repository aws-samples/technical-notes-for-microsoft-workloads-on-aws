---
sidebar_position: 4
title: Optimize CPU Costs for Windows Licensing
description: Reduce Microsoft per-core licensing costs on EC2 by adjusting ThreadsPerCore settings
---

# Optimize CPU Costs for Windows Licensing

Reduce Microsoft per-core licensing costs on Amazon EC2 and SQL Server instances by disabling hyperthreading (setting ThreadsPerCore = 1). This PowerShell script calculates potential savings and helps you understand the cost impact across instance types.

## Why This Matters

Windows Server and SQL Server are licensed **per physical core** on AWS. By default, most EC2 instance types enable 2 threads per core (hyperthreading). If your workload doesn't benefit from hyperthreading, you're paying for twice the licensing you need.

Setting `ThreadsPerCore = 1` at launch:
- **Halves your Windows/SQL licensing cost** (License Included pricing is per-vCPU)
- May be appropriate for memory-bound or I/O-bound workloads
- Does not affect the on-demand compute cost — only the license component

## Script

The `Show-OptimizeCPUCosts` script demonstrates cost savings across instance types by querying the AWS Pricing API and comparing License Included costs with and without hyperthreading.

**Repository:** [gitlab.aws.dev/coolcrai/Show-OptimizeCPUCosts](https://gitlab.aws.dev/coolcrai/Show-OptimizeCPUCosts)

### Requirements

- PowerShell 7+ (pre-installed in AWS CloudShell)
- AWS.Tools.EC2 and AWS.Tools.Pricing modules (pre-installed in AWS CloudShell)
- AWS credentials with EC2 and Pricing API permissions

### Quick Start (AWS CloudShell)

```powershell
pwsh
.\Show-OptimizeCPUCosts.ps1 -InstanceType m7a.4xlarge -Region us-east-1
```

## How ThreadsPerCore Works

When launching an EC2 instance, you can specify CPU options:

```powershell
New-EC2Instance -InstanceType m7a.4xlarge `
    -CpuOption_ThreadsPerCore 1 `
    -CpuOption_CoreCount 8
```

This launches with 8 cores × 1 thread = 8 vCPUs instead of the default 8 cores × 2 threads = 16 vCPUs. Windows licensing is charged per vCPU, so you pay for 8 licenses instead of 16.

## Applies To

- **EC2 Windows** — Windows Server License Included instances
- **SQL Server on EC2** — SQL Server License Included instances (Standard and Enterprise)
- **RDS for SQL Server** — Understanding vCPU-based licensing costs

## Related Resources

- [AWS EC2 CPU Options Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-optimize-cpu.html)
- [Microsoft Licensing on AWS](https://aws.amazon.com/windows/resources/licensing/)
- [EC2 Pricing and Availability Script](/Code%20Repo/EC2_Pricing_and_Availability/) — Find instance availability across regions

## Author

Craig Cooley (coolcrai@) — Built with Kiro IDE
