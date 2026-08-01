# AWS EC2 Unix Training Automation

Automated Bash scripts to spin up and tear down an AWS EC2 instance for Unix/Shell scripting training sessions.

---

## Project Overview

This project provides two shell scripts that automate the complete lifecycle of an EC2 training environment:

- **Setup Script** — Creates all required AWS resources in under 5 minutes
- **Teardown Script** — Destroys all resources after training to avoid unnecessary AWS charges

No more clicking through the AWS Console manually — one command builds everything, one command destroys everything!

---

## Architecture

The setup script provisions the following AWS resources:

| Resource | Name | Purpose |
|---|---|---|
| EC2 Instance | mission-deh-hof-unix-training | Training server (t3.micro) |
| Key Pair | mission-deh-hof-unix-key | SSH access |
| Security Group | mission-deh-hof-unix-sg | Firewall (port 22 open) |
| IAM Role | mission-deh-hof-unix-role | SSM permissions |
| Instance Profile | mission-deh-hof-unix-profile | Attaches IAM role to EC2 |

---

## Prerequisites

Before running these scripts, make sure you have:

- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] AWS account with permissions to create EC2 and IAM resources
- [ ] Bash shell (Linux / Mac / WSL on Windows)
- [ ] Default VPC exists in your AWS account

---

## Folder Structure

```
aws-ec2-unix-training-automation/
│
├── README.md
├── .gitignore
├── scripts/
│   ├── mission-deh-hof-ec2-setup.sh
│   └── mission-deh-hof-ec2-teardown.sh
└── docs/
    └── architecture.md
```

---

## Usage

### Step 1 — Setup (Before Training Session)

```bash
chmod +x scripts/mission-deh-hof-ec2-setup.sh
./scripts/mission-deh-hof-ec2-setup.sh
```

### Step 2 — Connect to EC2

```bash
ssh -i mission-deh-hof-unix-key.pem ec2-user@<PUBLIC_IP>
```

> The Public IP is printed at the end of the setup script output.

### Step 3 — Teardown (After Training Session)

```bash
chmod +x scripts/mission-deh-hof-ec2-teardown.sh
./scripts/mission-deh-hof-ec2-teardown.sh
```

---

## Key Features

- **Fully Automated** — Single command to build or destroy the entire environment
- **Cost Optimized** — Uses t3.micro (cheapest instance type), teardown prevents idle charges
- **Auto Cleanup on Failure** — If setup fails halfway, automatically rolls back all created resources
- **Smart Resource Discovery** — Teardown finds resources by name/tag even if the details file is missing
- **Timestamped Logging** — Every step is logged to a file for debugging and audit trail
- **Dynamic Configuration** — Auto-detects AWS account ID, latest Amazon Linux 2023 AMI and default VPC

---

## Workflow

```
Before Training            During Training          After Training
─────────────────          ───────────────          ──────────────
Run setup script    →      SSH into EC2      →      Run teardown script
(~5 minutes)               Practice Unix            (~3 minutes)
                           commands                 All resources deleted
                                                    Zero ongoing cost
```

---

## Cost Estimate

| Phase | Duration | Estimated Cost |
|---|---|---|
| Setup + Training (2 hrs) | ~2 hours | ~$0.02 |
| Idle (not torn down) | Per day | ~$0.24/day |
| After Teardown | — | $0.00 |

> Always run the teardown script after your session to avoid unnecessary charges!

---

## Log Files

Both scripts generate timestamped log files in the directory where they are run:

- `mission-deh-hof-ec2-setup-YYYYMMDD-HHMMSS.log`
- `mission-deh-hof-ec2-teardown-YYYYMMDD-HHMMSS.log`

---

## Security Notes

- SSH is open to `0.0.0.0/0` (all IPs) — suitable for short training sessions only
- For production use, restrict the CIDR block to your specific IP address
- The `.pem` key file is automatically deleted by the teardown script
- Never commit `.pem` files to GitHub (already handled by `.gitignore`)

---

## Author

**Noor** | [github.com/noordataai](https://github.com/noordataai)

---

## Disclaimer

These scripts are for educational and training purposes only.
Always review scripts before running them in your AWS account.
