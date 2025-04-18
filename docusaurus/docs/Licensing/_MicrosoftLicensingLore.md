---
sidebar_position: 99
sidebar_label: Microsoft Licensing Lore
---

# :mag::notebook: Microsoft Licensing Lore :notebook::mag: posts!

## Windows 10 is going end-of-support (EOS) - 4/17/2025
Windows 10 is going end-of-support (EOS) on October 14, 2025. It is highly recommended that customers running Windows 10, upgrade to Windows 11 before the EOS date. There are no licensing changes to do this in AWS; customers will continue to bring VDA user subscription licenses, which include the rights to Windows 11.

For customers using Amazon WorkSpaces Personal, check out this blog for guidance on upgrading: [Navigating the Windows 10 to 11 Migration for Amazon WorkSpaces Personal](https://aws.amazon.com/blogs/desktop-and-application-streaming/navigating-the-windows-10-to-11-migration-for-amazon-workspaces-personal/).

While Extended Security Updates (ESU) are available for purchase from Microsoft, the cost doubles in price each year, on top of requiring Year 1 ESU to be purchased in order to be able to purchase Year 2, and so on. There are not any clear details on how ESU will work for remote virtualization (i.e. in non-Azure clouds), but that may come as we get closer to the EOS date.

Call to action: When talking to customers that have Windows 10 in their environment, be sure to mention Windows 10 EOS and ask about the customer's plans to upgrade to Windows 11.

## Office Professional Plus 2021 LTSC & Visual Studio 2022 on EC2 - 1/31/2025
The Office Professional Plus 2021 LTSC & Visual Studio 2022 License Included offerings on EC2 no longer have a limit of 2 concurrent users per EC2 instance! AWS Managed Microsoft AD is still required, as is the purchase of RDS SALs. For more information, see [Get started with user-based subscriptions in License Manager](https://docs.aws.amazon.com/license-manager/latest/userguide/user-based-subscriptions-getting-started.html).

## Bring Windows 10/11 virtual desktops to AWS - 1/16/2025
Customers looking to bring Windows 10/11 virtual desktops to AWS require the following:
- Dedicated infrastructure (BYOL WorkSpaces - 100 seat minimum, EC2 Dedicated Instances, EC2 Dedicated Hosts)
- VDA E3/E5 User Subscription licenses (or VDA Add-Ons if the customer has M365 licenses for the same users already)

This is according to Microsoft's license terms. Microsoft specifically requires VDA user-based licensing, rather than the device option, when deploying in a Listed Provider cloud (Alibaba, Amazon, Google).
It is also important to ask the customer if they are deploying any other Microsoft software on their virtual desktops (such as Office), as there may be additional licensing requirements to consider.
For more information, see the following resources:
- [Amazon Web Services and Microsoft FAQ site](https://aws.amazon.com/windows/faq/)
- [Licensing Windows 365 and Windows 11 Virtual Desktops for Remote Access brief](https://www.microsoft.com/licensing/docs/documents/download/Licensing_brief_PLT_Licensing%20Windows%20365%20and%20Windows%2011%20Virtual%20Desktops%20for%20Remote%20Access.pdf)

## :red_circle: Microsoft licensing terms update! :red_circle: - 10/17/2024
On October 1, 2024 Microsoft updated their [Product Terms for Amazon WorkSpaces deployments](https://www.microsoft.com/licensing/terms/product/AmazonWorkspacesDeployments/EAEAS), to clarify that Microsoft Teams (standalone) is eligible for BYOL in Amazon WorkSpaces. These updates also included a few additional products that are now also eligible for BYOL in Amazon WorkSpaces:
- Microsoft Power Automate (licensed under Microsoft Power Automate Premium)
- Microsoft 365 app (licensed under Microsoft 365 Copilot)

So if you have customers looking to bring Power Automate or Microsoft 365 Copilot, Amazon WorkSpaces is the solution! 