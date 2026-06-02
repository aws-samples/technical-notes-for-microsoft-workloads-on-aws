---
sidebar_position: 4
title: Optimize CPU Costs for Windows Licensing
description: Reduce Microsoft license included costs on EC2 by adjusting ThreadsPerCore settings
---

# Optimize CPU Costs for Windows Licensing

Reduce Microsoft licensing costs on Amazon EC2 and SQL Server instances by disabling hyperthreading (setting `ThreadsPerCore = 1`). This PowerShell script calculates potential savings and helps you understand the cost impact across instance types.

## Why This Matters

Windows Server and SQL Server are licensed **per active vCPU** on AWS. By default, most EC2 instance types have 2 vCPUs per physical core (also known as hyperthreading). If your workload doesn't benefit from hyperthreading, you're paying for twice the licensing you need.

Setting `ThreadsPerCore = 1`:
- **Halves your Windows/SQL licensing cost** (AWS License Included pricing is per active vCPU)
- Does not affect the compute cost — only the license component
- see [Optimize CPUs for License-Included instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize-cpu.html) for details

## Scripts

The 2 PowerShell scripts in the [Scripts](./Scripts/) folder demonstrate cost savings across instance types by querying the AWS Pricing API and comparing License costs with and without hyperthreading.  The SSM Automation (Set-ThreadsPerCore.yaml) can be used to configure `ThreadsPerCore = 1` on multiple instances at once.  Individual instances can be configured from the AWS console or Command Line.  

| Script | Description |
|--------|-------------
| [Show-OptimizedCpuCost.ps1](https://github.com/HP-85/technical-notes-for-microsoft-workloads-on-aws/blob/2ebc1a9e4db9b9e311f5b60e152b7f38810dd840/docusaurus/docs/Licensing/Guides/Optimize_CPU_Costs/Scripts/CPUOptimizationCalc/README-Show-OptimizedCpuCost.md) | Shows per-instance cost savings when setting [ThreadsPerCore](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_CpuOptionsRequest.html)=1 |
| [Show-AccountCpuOptimization.ps1](https://github.com/HP-85/technical-notes-for-microsoft-workloads-on-aws/blob/2ebc1a9e4db9b9e311f5b60e152b7f38810dd840/docusaurus/docs/Licensing/Guides/Optimize_CPU_Costs/Scripts/CPUOptimizationCalc/Show-AccountCpuOptimization.ps1) | Scans instances in your account and shows optimization opportunities |
| [Set-ThreadsPerCore.yaml](https://github.com/HP-85/technical-notes-for-microsoft-workloads-on-aws/blob/2ebc1a9e4db9b9e311f5b60e152b7f38810dd840/docusaurus/docs/Licensing/Guides/Optimize_CPU_Costs/Scripts/SetThreadsPerCore_SSM/README.md) | SSM Automation document to set [ThreadsPerCore](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_CpuOptionsRequest.html) on existing instances |

### Requirements

- PowerShell 7+ (pre-installed in AWS CloudShell)
- AWS.Tools.EC2 and AWS.Tools.Pricing modules (pre-installed in AWS CloudShell)
- AWS credentials with EC2 and Pricing API permissions


## How ThreadsPerCore Works

When launching an EC2 instance, you can specify CPU options:

```powershell
New-EC2Instance -InstanceType m8i.4xlarge `
    -CpuOption_ThreadsPerCore 1 `
    -CpuOption_CoreCount 8
```

This launches with 8 cores × 1 thread = 8 vCPUs instead of the default 8 cores × 2 threads = 16 vCPUs. Windows licensing is charged per vCPU, so you pay for 8 licenses instead of 16.

## Applies To

- **EC2 Windows** — Windows Server License Included instances
- **SQL Server on EC2** — SQL Server License Included instances 
- **RDS for SQL Server** — Latest RDS instance have `ThreadsPerCore = 1` set by default
  
## Author
Craig Cooley (coolcrai@) — Built with Kiro IDE
