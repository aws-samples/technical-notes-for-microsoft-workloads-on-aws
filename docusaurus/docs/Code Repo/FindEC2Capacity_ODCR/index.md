---
title: Find EC2 Capacity (ODCR)
description: Create On-Demand Capacity Reservations across regions and AZs to find and reserve EC2 capacity for scarce instance types.
sidebar_position: 2
---

# Find EC2 Capacity with On-Demand Capacity Reservations
by Craig Cooley

## The Problem

When launching GPU or other high-demand EC2 instance types, you may see `InsufficientInstanceCapacity` errors when capacity simply isn't available in the Availability Zone you tried. Manually checking each region and AZ one-by-one is time-consuming, especially when you need instances urgently for a customer POC, benchmark, or migration.

## The Solution

**FindEC2Capacity_ODCR.ps1** automates the capacity hunt by creating [On-Demand Capacity Reservations](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html) (ODCRs) across all supported AZs simultaneously. If capacity exists anywhere, the script finds it and reserves it for you - and provides the command to cancel the reservation if needed.  

### What It Does

- **Scans all regions and AZs** for a given instance type in parallel
- **Creates ODCRs** wherever capacity is available
- **Shows on-demand pricing** per hour for each successful reservation
- **Lets you choose** which reservations to keep — automatically cancels the rest
- **Accumulates capacity** over time for scarce instance types (TargetQuantity mode) into an existing ODCR.

### Use Cases

| Scenario | Mode |
|----------|------|
| Need to quickly find a specific instance type (g6e, p5, etc.) in any region | Parallel (default) |
| Customer needs 10 instances and capacity becomes available over time | TargetQuantity (`-TargetQuantity`) |
| Reserving capacity in a specific AZ | Zone mode (`-Zone`) |

### Supported Platforms

- **All EC2 capacity-reservation platforms** — Windows, Linux, Ubuntu Pro, Red Hat Enterprise Linux, SUSE Linux, and the SQL Server / RHEL HA variants (matches the AWS API, queried dynamically). `Linux` is a friendly alias for `Linux/UNIX`.
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

📖 **[Full documentation and examples →](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/Code%20Repo/FindEC2Capacity_ODCR/Scripts/README.md)**

📥 **[Download FindEC2Capacity_ODCR.ps1](https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/docs/Code%20Repo/FindEC2Capacity_ODCR/Scripts/FindEC2Capacity_ODCR.ps1)**

---

