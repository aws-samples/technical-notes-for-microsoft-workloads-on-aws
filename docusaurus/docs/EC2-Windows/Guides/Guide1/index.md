---
sidebar_position: 10
sidebar_label: Restrict IAM permission to specific Windows users for AWS Systems Manager
---
# Restrict EC2 IAM role permission to specific Windows users for AWS Systems Manager. 
by Siavash Irani

## Background
A customer in consulting segment wants to use AWS Systems manager session manager for managing their ec2 instances.

## Challenge
One of the requirement of AWS systems manager is to have an IAM role attached to the instance. This allows ssm-user to interact with AWS using the AWS role permissions. The problem customer had was if they attach an IAM role to the Windows instance, not only it allows ssm-user to interact with AWS, but also any other Windows user which logs in to the instance will have access based on the IAM role. 

## Solution
The proposed solution was to use Windows firewall to block traffic to IMDS(instance meta-data service) to the specific windows user. 

## Solution diagram
![Solution diagram](img/Picture3.png)

## Workflow
1. Use WF.msc to create a new oubound rule. Add 169.254.169.254 as remote address. 
![Step1](img/Picture1.png)

2. Block the connection
![Step2](img/Picture4.png)

3. Apply the rule to everyone and exclude the rule for other users, like System, ssm-user,administrator. 
![Step3](img/Picture2.png)

## Benefits
With this method, customer is able to grant permissions to ssm-user and then block access to other Windows users.

## Potential Cost
There is no cost to create this solution, it’s just a configuration in windows. 
