---
sidebar_position: 10
sidebar_label: Install Kiro CLI on Windows Subsystem for Linux
---

# Install Kiro CLI on Windows Subsystem for Linux
by Craig Cooley

### Introduction
Amazon Kiro CLI is currently available for Linux and macOS, however a native version for Windows is not available. Microsoft includes 'Windows Subsystem for Linux' on Windows 11, Server 2022, and Server 2025 which can run the Linux distributions supported by Kiro CLI.

Below are the basic instructions for installing Kiro CLI on Windows which offers customers a way to use Amazon Kiro CLI and interact directly with the Windows OS. To use Kiro CLI to interact with AWS commands, kiro-cli is preinstalled in Amazon CloudShell. 

### Here are two Examples of using Kiro CLI to interact with Windows from WSL:

#### Example 1: Ask Kiro to check when Windows was last updated: 

```
User> When was my Windows operating system last updated?
Kiro > I can help you check when your Windows operating system was last updated, but I notice from the system context that you're
currently running on a Linux system.

If you want to check Windows update history on a different machine or if you have access to a Windows system, you can use these
methods:

Method 1: PowerShell command
powershell
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10
```

**Notice Kiro reports it's runing on Linux. When this happens, simply tell Kiro CLI that it's running on Windows.**. 

From WSL, any command that ends in `.exe`, executes in Windows, so Kiro can run PowerShell commands from the linux bash prompt using the syntax `powershell.exe "Get-HotFix" `

```
User> Kiro is running on WSL.  You can access Windows by running powershell.exe and any .exe command.

> Got it! I'm running on WSL (Windows Subsystem for Linux), so I have access to both Linux commands natively and Windows commands via powershell.exe or direct .exe calls.

For example:
- Linux: ls, cat, grep, etc.
- Windows: powershell.exe Get-Process, notepad.exe, explorer.exe .

Let me know what you'd like to do - I can work with both environments.

🛠️  Using tool: shell
 ⋮
 ● I will run the following shell command:
powershell.exe "Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10"
 ⋮
 ↳ Purpose: Check Windows update history using PowerShell from WSL

Kiro> Your Windows operating system was last updated on September 13, 2025. The most recent updates installed were:

• KB5064531 (Update)
• KB5065426 (Security Update)
• KB5064401 (Update)
```

#### Example 2: Check Windows Event Log: 
```
User> how do I query windows system event log for event ID 6009

Kiro> You can query the Windows System Event Log for event ID 6009 from WSL using PowerShell. Here are several approaches:
## Using Get-WinEvent (recommended)
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

## Steps to install Kiro CLI on Windows: 

**Kiro CLI - [Get started](https://kiro.dev/docs/cli/)**:
- Amazon Kiro CLI integrates with Windows using [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/) either WSLv1 or WSLv2
- Platform requirements: Recent distributions of Fedora and Ubuntu.
- Architecture: x86_64 or aarch64
- *Note*: Desktop functionality is not available on for Amazon Kiro running on WSL.

**Install Windows Subsystem for Linux**:
- Install Windows Subsystem for Linux https://learn.microsoft.com/en-us/windows/wsl/install
- If you're running Windows on AWS EC2, follow the instructions in the EC2 User Guide: [Install WSL on EC2 Windows](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-wsl-on-ec2-windows-instance.html)
- Install a supported Linux distribution on WSL. For example `wsl.exe --install Ubuntu-24.04`
- Reboot as needed

 **Install Kiro CLI in WSL:**
- Open a WSL Linux console and follow the instructions to [install Kiro CLI using a zip file](https://kiro.dev/docs/cli/installation/#with-a-zip-file).
- The most common steps will be:
```
sudo apt -y install zip
curl --proto '=https' --tlsv1.2 -sSf 'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' -o 'kirocli.zip'
unzip kirocli.zip
./kirocli/install.sh
```
- You can select 'no' when asked to modify the shell config.
- Specify a Builder ID or IAM Identity Center ID to login.

After Kiro is installed and activated, run `kiro-cli` to start interacting with Kiro CLI.

```
cc@WS-26CVSGUREALG:~$ kiro-cli
⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀     ⢀⣴⣶⣶⣦⡀⠀⠀⠀⢀⣴⣶⣦⣄⡀⠀⠀⢀⣴⣶⣶⣦⡀⠀⠀⢀⣴⣶⣶⣶⣶⣶⣶⣶⣶⣶⣦⣄⡀⠀⠀⠀⠀⠀⠀⢀⣠⣴⣶⣶⣶⣶⣶⣦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀    ⢰⣿⠋⠁⠈⠙⣿⡆⠀⢀⣾⡿⠁⠀⠈⢻⡆⢰⣿⠋⠁⠈⠙⣿⡆⢰⣿⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⣦⠀⠀⠀⠀⣴⡿⠟⠋⠁⠀⠀⠀⠈⠙⠻⢿⣦⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⣿⣇⣴⡿⠋⠀⠀⠀⢀⣼⠇⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⢠⣤⣤⣤⣤⣄⠀⠀⠀⠀⣿⡆⠀⠀⣼⡟⠀⠀⠀⠀⣀⣀⣀⠀⠀⠀⠀⢻⣧⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⣿⡿⠋⠀⠀⠀⢀⣾⡿⠁⠀⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⢸⣿⠉⠉⠉⣿⡇⠀⠀⠀⣿⡇⠀⣼⡟⠀⠀⠀⣰⡿⠟⠛⠻⢿⣆⠀⠀⠀⢻⣧⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⠙⠁⠀⠀⢀⣼⡟⠁⠀⠀⠀⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⢸⣿⣶⣶⡶⠋⠀⠀⠀⠀⣿⠇⢰⣿⠀⠀⠀⢰⣿⠀⠀⠀⠀⠀⣿⡆⠀⠀⠀⣿⡆
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠹⣷⡀⠀⠀⠀⠀⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣼⠟⠀⢸⣿⠀⠀⠀⢸⣿⠀⠀⠀⠀⠀⣿⡇⠀⠀⠀⣿⡇
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⠀⣠⡀⠀⠀⠹⣷⡄⠀⠀⠀⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⠀⣤⣄⠀⠀⠀⠀⠹⣿⡅⠀⠀⠸⣿⠀⠀⠀⠸⣿⠀⠀⠀⠀⠀⣿⠇⠀⠀⠀⣿⠇
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⣾⡟⣷⡀⠀⠀⠘⣿⣆⠀⠀⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⠀⣿⡟⣷⡀⠀⠀⠀⠘⣿⣆⠀⠀⢻⣧⠀⠀⠀⠹⣷⣦⣤⣤⣾⠏⠀⠀⠀⣼⡟
⠀⠀⠀⠀⠀⠀⠀    ⢸⣿⠀⠀⠀⠀⣿⡇⠹⣷⡀⠀⠀⠈⢻⡇⠀⢸⣿⠀⠀⠀⠀⣿⡇⢸⣿⠀⠀⠀⠀⣿⡇⠹⣷⡀⠀⠀⠀⠈⢻⡇⠀⠀⢻⣧⠀⠀⠀⠀⠉⠉⠉⠀⠀⠀⠀⣼⡟
⠀⠀⠀⠀⠀⠀⠀    ⠸⣿⣄⡀⢀⣠⣿⠇⠀⠙⣷⡀⠀⢀⣼⠇⠀⠸⣿⣄⡀⢀⣠⣿⠇⠸⣿⣄⡀⢀⣠⣿⠇⠀⠙⣷⡀⠀⠀⢀⣼⠇⠀⠀⠀⠻⣷⣦⣄⡀⠀⠀⠀⢀⣠⣴⣾⠟
⠀⠀⠀⠀⠀⠀⠀    ⠀⠈⠻⠿⠿⠟⠁⠀⠀⠀⠈⠻⠿⠿⠟⠁⠀⠀⠈⠻⠿⠿⠟⠁⠀⠀⠈⠻⠿⠿⠟⠁⠀⠀⠀⠈⠻⠿⠿⠟⠁⠀⠀⠀⠀⠀⠈⠙⠻⠿⠿⠿⠿⠟⠋⠁

╭─────────────────────────────── Did you know? ────────────────────────────────╮
│                                                                              │
│         Get notified whenever Kiro CLI finishes responding. Just run         │
│               kiro-cli settings chat.enableNotifications true                │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

Model: Auto (/model to change)

>
```
