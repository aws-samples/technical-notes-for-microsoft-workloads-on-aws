---
title: Find EC2 Capacity (ODCR)
description: Create On-Demand Capacity Reservations across regions and AZs to find and reserve EC2 capacity for scarce instance types.
sidebar_position: 2
---

# Find EC2 Capacity with On-Demand Capacity Reservations

## The Problem

When launching GPU, HPC, or other high-demand EC2 instance types, you often get `InsufficientInstanceCapacity` errors — capacity simply isn't available in the AZ you tried. Manually checking each region and AZ one-by-one is time-consuming, especially when you need instances urgently for a customer POC, benchmark, or migration.

## The Solution

**FindEC2Capacity_ODCR.ps1** automates the capacity hunt by creating [On-Demand Capacity Reservations](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html) (ODCRs) across all supported AZs simultaneously. If capacity exists anywhere, the script finds it and reserves it for you.

### What It Does

- **Scans all regions and AZs** for a given instance type in parallel
- **Creates ODCRs** wherever capacity is available
- **Shows on-demand pricing** per hour for each successful reservation
- **Lets you choose** which reservations to keep — automatically cancels the rest
- **Accumulates capacity** over time for scarce instance types (TargetQuantity mode)

### Use Cases

| Scenario | Mode |
|----------|------|
| Customer needs a specific GPU instance type (g6e, p5, etc.) but can't find capacity | Parallel (default) |
| Need to quickly confirm if an instance type is available anywhere | Sequential (`-Sequential`) |
| Customer needs 10+ instances and capacity is trickling in slowly | TargetQuantity (`-TargetQuantity`) |
| Testing capacity availability before a planned migration | Parallel with `-RegionGroup us` |
| Reserving capacity in a specific AZ for a multi-AZ deployment | Zone mode (`-Zone`) |

### Supported Platforms

- **Windows** and **Linux** instance reservations
- All EC2 instance types (validated against the AWS Pricing API)
- All commercially available AWS regions

### How to Run

The recommended environment is **AWS CloudShell** (PowerShell 7 and AWS modules are pre-installed):

```powershell
pwsh
.\FindEC2Capacity_ODCR.ps1 -OS Windows -InstanceType g7e.2xlarge -RegionGroup us
```

> ⚠️ **Billing:** You are billed at the on-demand rate from the moment an ODCR is created, even if no instance is running in it. Cancel reservations when done.

### Get Started

📖 **[Full documentation and examples →](./README.md)**

📥 **[Download FindEC2Capacity_ODCR.ps1](./FindEC2Capacity_ODCR.ps1)**

---

*Author: Craig Cooley (coolcrai@) — Built with Kiro IDE + Claude Opus 4.6*
