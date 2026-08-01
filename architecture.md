# Architecture Documentation

## Overview

This project automates the creation and deletion of an AWS EC2 environment
specifically designed for Unix/Shell scripting training sessions.

---

## AWS Resources Created

### 1. EC2 Instance
- **Name**: mission-deh-hof-unix-training
- **Instance Type**: t3.micro (2 vCPU, 1GB RAM)
- **AMI**: Latest Amazon Linux 2023 (auto-detected)
- **Purpose**: The actual training server where Unix commands are practiced

### 2. Key Pair
- **Name**: mission-deh-hof-unix-key
- **File**: mission-deh-hof-unix-key.pem (saved locally)
- **Purpose**: Secure SSH access to the EC2 instance

### 3. Security Group
- **Name**: mission-deh-hof-unix-sg
- **Inbound Rules**: TCP port 22 (SSH) open to 0.0.0.0/0
- **Purpose**: Acts as a firewall controlling access to the EC2 instance

### 4. IAM Role
- **Name**: mission-deh-hof-unix-role
- **Policy Attached**: AmazonSSMManagedInstanceCore
- **Purpose**: Grants the EC2 instance permission to communicate with AWS Systems Manager

### 5. IAM Instance Profile
- **Name**: mission-deh-hof-unix-profile
- **Purpose**: Container that attaches the IAM role to the EC2 instance

---

## Resource Dependency Order

```
IAM Role
    └── IAM Instance Profile (wraps the role)
            └── EC2 Instance (uses the profile)
                    └── Security Group (attached to EC2)
                    └── Key Pair (attached to EC2)
```

> Resources must be deleted in reverse order during teardown.
> You cannot delete a Security Group while an EC2 instance is still using it.

---

## Setup Flow

```
Start
  │
  ├── Get AWS Account ID
  ├── Get Default VPC ID
  ├── Create Key Pair → Save .pem file locally
  ├── Create Security Group → Open port 22
  ├── Create IAM Role → Attach SSM policy
  ├── Create Instance Profile → Add role to profile
  ├── Find latest Amazon Linux 2023 AMI
  ├── Launch t3.micro EC2 Instance
  ├── Wait for instance to be running
  ├── Wait for status checks to pass
  ├── Print SSH connection command
  └── Save resource details to ec2-details.txt
```

---

## Teardown Flow

```
Start
  │
  ├── Load resource IDs from ec2-details.txt
  │     └── If file missing → search by name/tag
  ├── Terminate EC2 Instance
  ├── Wait for instance to be fully terminated
  ├── Delete Security Group
  ├── Remove role from Instance Profile → Delete Instance Profile
  ├── Detach SSM policy from IAM Role → Delete IAM Role
  ├── Delete Key Pair from AWS
  ├── Delete local .pem file
  └── Delete ec2-details.txt
```

---

## Networking

- Uses the **Default VPC** in your AWS account (auto-detected)
- EC2 instance gets a **public IP** automatically
- SSH access via port 22 from any IP (0.0.0.0/0)

---

## Cost Breakdown

| Resource | Cost |
|---|---|
| t3.micro EC2 | ~$0.0104/hour |
| Key Pair | Free |
| Security Group | Free |
| IAM Role/Profile | Free |
| **Total per hour** | **~$0.01/hour** |

> A 2-hour training session costs approximately $0.02.
> Always run the teardown script to stop all charges!
