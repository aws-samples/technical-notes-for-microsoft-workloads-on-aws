---
sidebar_position: 10
sidebar_label: Install Q CLI on Windows Subsystem for Linux
---

# Install Q CLI on Windows Subsystem for Linux
by Craig Cooley

### Introduction
 Amazon Q CLI is currently available for Linux and macOS, however there is not a native Windows version available. Microsoft offers 'Windows Subsystem for Linux' on Windows 10 and 11, and Window Server 2022 and 2025 which can run Linux distributions supports by Q CLI. (Ubuntu 22 and 24).

If we add basic instructions for installing Q CLI on Windows, it offers customers running Windows a way to make use of Q CLI.

### Example of Q CLI interaction with Windows OS from WSL:
```
> how do I query windows system event log for event ID 6009

> You can query the Windows System Event Log for event ID 6009 from WSL using PowerShell. Here are several approaches:
## Using Get-WinEvent (recommended)
bash
powershell.exe -Command "Get-WinEvent -FilterHashtable @{LogName='System'; ID=6009}"

 ● I will run the following shell command:
powershell.exe -Command "Get-WinEvent -FilterHashtable @{LogName='System'; ID=6009}"
 ⋮
 ↳ Purpose: Query Windows System Event Log for event ID 6009 using PowerShell Get-WinEvent
Allow this action? Use 't' to trust (always allow) this tool for the session. [y/n/t]:
> y
   ProviderName: EventLog

TimeCreated                      Id LevelDisplayName Message
-----------                      -- ---------------- -------
8/7/2025 9:41:26 AM            6009 Information      Microsoft (R) Windows (R) 10.00. 22631  Multiprocessor Free.
8/6/2025 12:13:42 PM           6009 Information      Microsoft (R) Windows (R) 10.00. 22631  Multiprocessor Free.
8/5/2025 8:07:40 AM            6009 Information      Microsoft (R) Windows (R) 10.00. 22631  Multiprocessor Free.
```

**User Guide Page**: [Supported environments](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-supported-envs.html)


**Q CLI - Windows Subsystem for Linux (WSL) Supported environments**:
- Amazon Q for command line integrates with Windows using [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/).
- Platform requirements: Amazon Q for command line for Linux supports Ubuntu 22 and 24, and compatibility for a subset of features on Ubuntu 20.
- Architecture: x86_64 or aarch64
- *Note*: Desktop functionality is not available on for Amazon Q running on WSL.

**User Guide Page**: [Installation](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-installing.html)


**Q CLI - Installation on Windows Subsystem for Linux**:
- Install Windows Subsystem for Linux https://learn.microsoft.com/en-us/windows/wsl/install
* If you're running Windows on AWS EC2, follow the instructions in the EC2 User Guide: [Install WSL on Windows](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-wsl-on-ec2-windows-instance.html)
- Install a supported Linux distribution on WSL. For example `wsl.exe --install Ubuntu-24.04`
- Open a WSL Linux console and follow the instructions to [install Q CLI using a zip file](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-installing-ssh-setup-autocomplete.html).