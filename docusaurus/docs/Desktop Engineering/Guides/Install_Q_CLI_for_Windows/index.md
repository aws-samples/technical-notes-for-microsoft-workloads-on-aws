---
sidebar_position: 10
sidebar_label: Install Q CLI on Windows Subsystem for Linux
---

# Install Q CLI on Windows Subsystem for Linux
by Craig Cooley

### Introduction
Amazon Q CLI is currently available for Linux and macOS, however there is not a native Windows version available. Microsoft offers 'Windows Subsystem for Linux' on Windows 11 plus Window Server 2022 and 2025 which can run the Linux distributions supports by Q CLI. (Ubuntu 22 and 24).

Below are the basic instructions for installing Q CLI on Windows which offers customers a way to use Amazon Q CLI and interact directly with the Windows OS.

### Here are two Examples of Q CLI interaction with Windows OS from WSL:
Q will initially detect that it's running on Linux and may not offer to run command directly on Windows.  Simply tell Q that's it's running in WSL.  


#### Example 1: Ask Q to check when Windows was last updated: 

```
User> When was my Windows operating system last updated?
Q > I can help you check when your Windows operating system was last updated, but I notice from the system context that you're
currently running on a Linux system.

If you want to check Windows update history on a different machine or if you have access to a Windows system, you can use these
methods:

Method 1: PowerShell command
powershell
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10
```

**Notice Q reports it's runing on Linux.  In this case, simply tell Q CLI that it's running on WSL.**
```
User> Q is running on WSL.  Please run Method 1 on this system.
Q> I'll run the PowerShell command to check your Windows update history from WSL.

🛠️  Using tool: execute_bash
 ⋮
 ● I will run the following shell command:
powershell.exe "Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10"
 ⋮
 ↳ Purpose: Check Windows update history using PowerShell from WSL

Q> Your Windows operating system was last updated on September 13, 2025. The most recent updates installed were:

• KB5064531 (Update)
• KB5065426 (Security Update)
• KB5064401 (Update)
```

From WSL, any command that ends in .exe, executes in Windows, so Q can run PowerShell commands from bash using the syntax `powershell.exe "Get-HotFix" `

#### Example 2: Check Windows Event Log: 
```
User> how do I query windows system event log for event ID 6009

Q> You can query the Windows System Event Log for event ID 6009 from WSL using PowerShell. Here are several approaches:
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

## Steps to install Q CLI on Windows: 

**Q CLI - [Supported environments](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-supported-envs.html)**:
- Amazon Q CLI integrates with Windows using [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/) both WSLv1 and WSLv2
- Platform requirements: Amazon Q for command line for Linux supports Ubuntu 22 and 24.
- Architecture: x86_64 or aarch64
- *Note*: Desktop functionality is not available on for Amazon Q running on WSL.

**Install Windows Subsystem for Linux**:
- Install Windows Subsystem for Linux https://learn.microsoft.com/en-us/windows/wsl/install
- If you're running Windows on AWS EC2, follow the instructions in the EC2 User Guide: [Install WSL on EC2 Windows](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-wsl-on-ec2-windows-instance.html)
- Install a supported Linux distribution on WSL. For example `wsl.exe --install Ubuntu-24.04`
- Reboot as needed

 **Install Q CLI in WSL:**
- Open a WSL Linux console and follow the instructions to [install Q CLI using a zip file](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-installing-ssh-setup-autocomplete.html).
- The most common steps will be:
```
curl --proto '=https' --tlsv1.2 -sSf "https://desktop-release.q.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip" -o "q.zip"
unzip q.zip
./q/install.sh
```
- You can answer 'n' when asked to modify the shell config.
- Specify a Builder ID or IAM Identity Center ID to login.

After Q is installed and activated, you can run `qchat` to start interacting with Q CLI.

```
cc@WS-2:~$ qchat

    ⢠⣶⣶⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣶⣿⣿⣿⣶⣦⡀⠀
 ⠀⠀⠀⣾⡿⢻⣿⡆⠀⠀⠀⢀⣄⡄⢀⣠⣤⣤⡀⢀⣠⣤⣤⡀⠀⠀⢀⣠⣤⣤⣤⣄⠀⠀⢀⣤⣤⣤⣤⣤⣤⡀⠀⠀⣀⣤⣤⣤⣀⠀⠀⠀⢠⣤⡀⣀⣤⣤⣄⡀⠀⠀⠀⠀⠀⠀⢠⣿⣿⠋⠀⠀⠀⠙⣿⣿⡆
 ⠀⠀⣼⣿⠇⠀⣿⣿⡄⠀⠀⢸⣿⣿⠛⠉⠻⣿⣿⠛⠉⠛⣿⣿⠀⠀⠘⠛⠉⠉⠻⣿⣧⠀⠈⠛⠛⠛⣻⣿⡿⠀⢀⣾⣿⠛⠉⠻⣿⣷⡀⠀⢸⣿⡟⠛⠉⢻⣿⣷⠀⠀⠀⠀⠀⠀⣼⣿⡏⠀⠀⠀⠀⠀⢸⣿⣿
 ⠀⢰⣿⣿⣤⣤⣼⣿⣷⠀⠀⢸⣿⣿⠀⠀⠀⣿⣿⠀⠀⠀⣿⣿⠀⠀⢀⣴⣶⣶⣶⣿⣿⠀⠀⠀⣠⣾⡿⠋⠀⠀⢸⣿⣿⠀⠀⠀⣿⣿⡇⠀⢸⣿⡇⠀⠀⢸⣿⣿⠀⠀⠀⠀⠀⠀⢹⣿⣇⠀⠀⠀⠀⠀⢸⣿⡿
 ⢀⣿⣿⠋⠉⠉⠉⢻⣿⣇⠀⢸⣿⣿⠀⠀⠀⣿⣿⠀⠀⠀⣿⣿⠀⠀⣿⣿⡀⠀⣠⣿⣿⠀⢀⣴⣿⣋⣀⣀⣀⡀⠘⣿⣿⣄⣀⣠⣿⣿⠃⠀⢸⣿⡇⠀⠀⢸⣿⣿⠀⠀⠀⠀⠀⠀⠈⢿⣿⣦⣀⣀⣀⣴⣿⡿⠃
 ⠚⠛⠋⠀⠀⠀⠀⠘⠛⠛⠀⠘⠛⠛⠀⠀⠀⠛⠛⠀⠀⠀⠛⠛⠀⠀⠙⠻⠿⠟⠋⠛⠛⠀⠘⠛⠛⠛⠛⠛⠛⠃⠀⠈⠛⠿⠿⠿⠛⠁⠀⠀⠘⠛⠃⠀⠀⠘⠛⠛⠀⠀⠀⠀⠀⠀⠀⠀⠙⠛⠿⢿⣿⣿⣋⠀⠀
 ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⠿⢿⡧

╭─────────────────────────────── Did you know? ────────────────────────────────╮
│                                                                              │
│      /usage shows you a visual breakdown of your current context window      │
│                                    usage                                     │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

/help all commands  •  ctrl + j new lines  •  ctrl + s fuzzy search
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 You are chatting with claude-sonnet-4
```
