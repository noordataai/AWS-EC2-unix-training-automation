#!/bin/bash

set -e

LOG_FILE="mission-deh-hof-ec2-setup-$(date +%Y%m%d-%H%M%S).log"
CREATED_RESOURCES=()

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "ERROR: Setup failed. Starting cleanup..."
    
    if [[ ${#CREATED_RESOURCES[@]} -gt 0 ]]; then
        for resource in "${CREATED_RESOURCES[@]}"; do
            IFS=':' read -r type id <<< "$resource"
            case $type in
                "instance")
                    log "Terminating EC2 instance: $id"
                    aws ec2 terminate-instances --instance-ids "$id" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    ;;
                "sg")
                    log "Waiting for instance termination before deleting security group..."
                    sleep 30
                    log "Deleting security group: $id"
                    aws ec2 delete-security-group --group-id "$id" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    ;;
                "key")
                    log "Deleting key pair: $id"
                    aws ec2 delete-key-pair --key-name "$id" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    rm -f "${id}.pem" 2>&1 | tee -a "$LOG_FILE" || true
                    ;;
                "profile")
                    log "Deleting instance profile: $id"
                    aws iam remove-role-from-instance-profile --instance-profile-name "$id" --role-name "$ROLE_NAME" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    aws iam delete-instance-profile --instance-profile-name "$id" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    ;;
                "role")
                    log "Detaching policies and deleting role: $id"
                    aws iam detach-role-policy --role-name "$id" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    aws iam delete-role --role-name "$id" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || true
                    ;;
            esac
        done
    fi
    
    log "Cleanup completed. Check log file: $LOG_FILE"
    exit 1
}

trap cleanup ERR

log "Starting EC2 setup for Unix training..."

# Get account number
log "Retrieving AWS account number..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
log "Account ID: $ACCOUNT_ID"

# Variables
KEY_NAME="mission-deh-hof-unix-key"
SG_NAME="mission-deh-hof-unix-sg"
INSTANCE_NAME="mission-deh-hof-unix-training"
ROLE_NAME="mission-deh-hof-unix-role"
INSTANCE_PROFILE_NAME="mission-deh-hof-unix-profile"

# Get default VPC
log "Getting default VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --no-cli-pager)
log "Default VPC ID: $VPC_ID"

# Create key pair
log "Creating key pair: $KEY_NAME"
aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text --no-cli-pager > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"
CREATED_RESOURCES+=("key:$KEY_NAME")
log "Key pair created and saved to ${KEY_NAME}.pem"

# Create security group
log "Creating security group: $SG_NAME"
SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for Unix training EC2" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text \
    --no-cli-pager)
CREATED_RESOURCES+=("sg:$SG_ID")
log "Security group created: $SG_ID"

# Add SSH rule
log "Adding SSH ingress rule to security group..."
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --no-cli-pager 2>&1 | tee -a "$LOG_FILE"

# Create IAM role for SSM
log "Creating IAM role for SSM access..."
aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --no-cli-pager 2>&1 | tee -a "$LOG_FILE"
CREATED_RESOURCES+=("role:$ROLE_NAME")
log "IAM role created: $ROLE_NAME"

# Attach SSM policy
log "Attaching SSM policy to role..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
    --no-cli-pager 2>&1 | tee -a "$LOG_FILE"

# Create instance profile
log "Creating instance profile..."
aws iam create-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --no-cli-pager 2>&1 | tee -a "$LOG_FILE"
CREATED_RESOURCES+=("profile:$INSTANCE_PROFILE_NAME")
log "Instance profile created: $INSTANCE_PROFILE_NAME"

# Add role to instance profile
log "Adding role to instance profile..."
aws iam add-role-to-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --role-name "$ROLE_NAME" \
    --no-cli-pager 2>&1 | tee -a "$LOG_FILE"

log "Waiting for IAM role to propagate..."
sleep 10

# Get latest Amazon Linux 2023 AMI
log "Finding latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text \
    --no-cli-pager)
log "AMI ID: $AMI_ID"

# Launch EC2 instance (t3.micro - cheapest)
log "Launching EC2 instance (t3.micro)..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile "Name=$INSTANCE_PROFILE_NAME" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' \
    --output text \
    --no-cli-pager)
CREATED_RESOURCES+=("instance:$INSTANCE_ID")
log "EC2 instance launched: $INSTANCE_ID"

# Wait for instance to be running
log "Waiting for instance to be in running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --no-cli-pager
log "Instance is now running"

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --no-cli-pager)
log "Public IP: $PUBLIC_IP"

# Wait for status checks
log "Waiting for instance status checks to pass (this may take a few minutes)..."
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --no-cli-pager
log "Instance status checks passed"

log "=========================================="
log "EC2 Setup Complete!"
log "=========================================="
log "Instance ID: $INSTANCE_ID"
log "Public IP: $PUBLIC_IP"
log "Key File: ${KEY_NAME}.pem"
log ""
log "To connect via SSH:"
log "  ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
log ""
log "To connect via EC2 Instance Connect (from AWS Console):"
log "  1. Go to EC2 Console"
log "  2. Select instance: $INSTANCE_ID"
log "  3. Click 'Connect' button"
log "  4. Choose 'EC2 Instance Connect' tab"
log "  5. Click 'Connect'"
log ""
log "Log file: $LOG_FILE"
log "=========================================="

# Save instance details
cat > mission-deh-hof-ec2-details.txt <<EOF
INSTANCE_ID=$INSTANCE_ID
PUBLIC_IP=$PUBLIC_IP
KEY_NAME=$KEY_NAME
SG_ID=$SG_ID
ROLE_NAME=$ROLE_NAME
INSTANCE_PROFILE_NAME=$INSTANCE_PROFILE_NAME
ACCOUNT_ID=$ACCOUNT_ID
EOF

log "Instance details saved to mission-deh-hof-ec2-details.txt"




# What Does This Script Do Overall?

# It automatically sets up an EC2 instance, (a virtual computer in AWS) for Unix training.
# Instead of clicking through the AWS Console manually, this script does everything in one go!
# It's a fully automated, safe and self-cleaning script that sets up a complete EC2 environment.
# for Unix training in one single command!

# What Does This Script Actually Do? (Step by Step)?

# Creates an SSH key pair to securely connect to the EC2 instance.
# Creates a Security Group (firewall) that opens port 22 for SSH access.
# Creates an IAM Role with SSM permissions so AWS can manage the instance.
# Creates an Instance Profile and attaches the IAM role to it.
# Finds the latest Amazon Linux 2023 AMI automatically (no hardcoded IDs).
# Launches a t3.micro EC2 instance with all the above attached.
# Waits for the instance to be fully ready and health checks to pass.
# Prints the exact SSH command to connect to the instance.
# Saves all resource details to a text file for reference.
# If anything fails → auto deletes everything created so far (no orphaned resources).
# Logs every single step with timestamps to a log file for debugging.

# How Was This Script Created? What Prompt Was Used?

# This script was most likely created using a prompt along these lines:
# The Core Prompt Structure:
# Create a bash shell script that sets up an EC2 instance on AWS for 
# Unix training with the following requirements:

# Infrastructure:
   #- t3.micro instance (cheapest)
   #- Latest Amazon Linux 2023 AMI (auto-detect, don't hardcode)
   #- SSH key pair saved as .pem file
   #- Security group with port 22 open
   #- IAM role with AmazonSSMManagedInstanceCore policy
   #- Instance profile attached to the EC2

# Safety & Reliability:
   #- Use set -e to stop on any error
   #- Track all created resources in an array
   #- If any step fails, automatically clean up ALL created resources
   #- Use trap to catch errors and trigger cleanup

# Logging:
   #- Log every step with timestamps
   #- Write logs to both screen and a log file
   #- Include the date/time in the log filename

# Output:
   #- Print SSH connection command at the end
   #- Save all resource details (instance ID, IP, key name etc.) to a text file

#Naming convention: prefix everything with "mission-deh-hof-unix-"

###Prompt - If You Want to Create a Similar Script in Future, Use This Prompt Template:
### Create a production-ready bash script that automates [WHAT YOU WANT TO CREATE] on AWS with the following:

#1. RESOURCES TO CREATE:
   #- [list the AWS resources you need e.g. EC2, S3, RDS, Lambda]
   #- [instance type / size / configuration]
   #- [any specific settings]

#2. SAFETY REQUIREMENTS:
   #- Stop immediately if any command fails (set -e)
   #- Track all created resources
   #- Auto cleanup everything if script fails halfway
   #- Use trap to catch errors

#3. LOGGING:
   #- Timestamp every log message
   #- Save logs to a file with date in filename
   #- Print progress to screen as well

#4. OUTPUT:
   #- Print connection/access details at the end
   #- Save resource IDs and details to a text file

#5. NAMING:
   #- Prefix all resources with "[your-prefix]-"

#6. DYNAMIC VALUES:
   #- Auto-detect AWS account ID (don't hardcode)
   #- Auto-detect latest AMI (don't hardcode AMI IDs)
   #- Auto-detect default VPC


###Key Ingredients That Make a Great Infrastructure Script:
#set -e — always include this, stops script on first failure

#trap cleanup ERR — always have a cleanup function for rollback

#CREATED_RESOURCES array — track what you create so you can undo it

#log() function — reusable logging with timestamps

#aws ... wait — always wait for resources to be ready before moving to next step

#Dynamic values — never hardcode account IDs, AMI IDs, or VPC IDs — always fetch them automatically

#Save output to file — always save resource details at the end so you don't lose them


### Big Picture Summary

# Script Starts
    #  ↓
# Get AWS Account ID
    #  ↓
# Create Key Pair (SSH access)
     # ↓
# Create Security Group (firewall - open port 22)
     # ↓
# Create IAM Role + Instance Profile (permissions)
     # ↓
# Find Latest Amazon Linux 2023 AMI
     # ↓
# Launch t3.micro EC2 Instance
     # ↓
# Wait for it to be ready
     # ↓
# Print SSH connection command + Save details to file
     # ↓
# If ANYTHING fails → Auto cleanup all created resources!

#!/bin/bash - tells the computer "run this file using the Bash shell (command line)"
# set -e :- very important! means "if ANY command fails, stop immediately". Like a safety switch — prevents half-finished setups.
