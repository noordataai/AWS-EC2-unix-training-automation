#!/bin/bash

set -e

LOG_FILE="mission-deh-hof-ec2-teardown-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting EC2 teardown..."

# Check if details file exists
if [ ! -f "mission-deh-hof-ec2-details.txt" ]; then
    log "WARNING: mission-deh-hof-ec2-details.txt not found. Will search for resources by name/tag."
    INSTANCE_ID=""
    SG_ID=""
    KEY_NAME="mission-deh-hof-unix-key"
    ROLE_NAME="mission-deh-hof-unix-role"
    INSTANCE_PROFILE_NAME="mission-deh-hof-unix-profile"
else
    log "Loading instance details from mission-deh-hof-ec2-details.txt"
    . ./mission-deh-hof-ec2-details.txt
fi

# Find instance if not in details file
if [ -z "$INSTANCE_ID" ]; then
    log "Searching for EC2 instance with tag Name=mission-deh-hof-unix-training..."
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=mission-deh-hof-unix-training" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text \
        --no-cli-pager 2>/dev/null || echo "")
fi

# Terminate EC2 instance
if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    log "Terminating EC2 instance: $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --no-cli-pager 2>&1 | tee -a "$LOG_FILE"
    
    log "Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --no-cli-pager
    log "Instance terminated successfully"
else
    log "No instance found to terminate"
fi

# Find security group if not in details file
if [ -z "$SG_ID" ]; then
    log "Searching for security group: mission-deh-hof-unix-sg..."
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=mission-deh-hof-unix-sg" \
        --query "SecurityGroups[0].GroupId" \
        --output text \
        --no-cli-pager 2>/dev/null || echo "")
fi

# Delete security group
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    log "Deleting security group: $SG_ID"
    aws ec2 delete-security-group --group-id "$SG_ID" --no-cli-pager 2>&1 | tee -a "$LOG_FILE"
    log "Security group deleted successfully"
else
    log "No security group found to delete"
fi

# Delete instance profile and role
if [ -n "$INSTANCE_PROFILE_NAME" ]; then
    log "Removing role from instance profile..."
    aws iam remove-role-from-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "${ROLE_NAME:-mission-deh-hof-unix-role}" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || log "Instance profile not found"
    
    log "Deleting instance profile: $INSTANCE_PROFILE_NAME"
    aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || log "Instance profile not found"
fi

if [ -n "$ROLE_NAME" ]; then
    log "Detaching SSM policy from role..."
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || log "Policy not attached"
    
    log "Deleting IAM role: $ROLE_NAME"
    aws iam delete-role --role-name "$ROLE_NAME" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || log "Role not found"
fi

# Delete key pair
if [ -n "$KEY_NAME" ]; then
    log "Deleting key pair: $KEY_NAME"
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --no-cli-pager 2>&1 | tee -a "$LOG_FILE" || log "Key pair not found in AWS"
    
    if [ -f "${KEY_NAME}.pem" ]; then
        log "Removing local key file: ${KEY_NAME}.pem"
        rm -f "${KEY_NAME}.pem"
    fi
    log "Key pair cleanup completed"
else
    log "No key pair specified"
fi

# Remove details file
if [ -f "mission-deh-hof-ec2-details.txt" ]; then
    log "Removing details file: mission-deh-hof-ec2-details.txt"
    rm -f mission-deh-hof-ec2-details.txt
fi

log "=========================================="
log "EC2 Teardown Complete!"
log "=========================================="
log "All resources have been cleaned up."
log "Log file: $LOG_FILE"
log "=========================================="

### What is This Script & Why Does it Exist?

# This is the opposite of the setup script you saw earlier. 
# If the setup script is like building a house, this teardown script is like demolishing it cleanly when you're done.
# The main purpose is to delete all AWS resources, created by the setup script so you stop getting charged for them after your training session is over.

###
#SETUP SCRIPT                    TEARDOWN SCRIPT
#─────────────────────────────────────────────────
#Create Key Pair          →      Delete Key Pair + .pem file
#Create Security Group    →      Delete Security Group
#Create IAM Role          →      Detach Policy → Delete Role
#Create Instance Profile  →      Remove Role → Delete Profile
#Launch EC2 Instance      →      Terminate EC2 Instance
#Save details to file     →      Delete details file

### Notice the teardown does everything in reverse order — 

# This is intentional! You can't delete a security group while an instance is still using it.
# Just like you can't remove a foundation while the house is still standing.

### Why is This Script So Important?

# -Saves Money — EC2 instances cost money every hour they run. Running this after training stops all charges immediately.
# -Clean AWS Account — No leftover resources cluttering your account.
# -Works Even Without the Details File — Smart fallback to search by tags/names.
# -Handles Already-Deleted Resources Gracefully — Uses || log "not found" so it doesn't crash if something was already manually deleted.
# -Paired with Setup Script — Together they form a complete spin up → train → spin down workflow, perfect for training sessions!

### What is the Main Motive Behind This Script?

#Cost Saving — The #1 reason! 
           # - EC2 instances charge you every hour they run. 
           # - This script kills everything instantly after training so you don't pay for idle resources.

#Clean Up After Training — After a Unix training session is done. 
                       # - There's no reason to keep the EC2 instance running. 
                       # - This script removes everything in one command.

#Prevent Forgotten Resources — It's very common for people to forget to delete AWS resources manually. 
                           # - This script ensures nothing is left behind.

#Reverse of the Setup Script — It's the "undo button" for mission-deh-hof-ec2-setup.sh. 
                           # - Every resource the setup script creates, this script destroys.

#Smart Resource Discovery — Even if you lost the details file. 
                        # - The script is smart enough to find resources by their name/tag and still delete them.

#Audit Trail — Logs every deletion step with timestamps. 
           # - So you have proof of what was deleted and when.

#Graceful Handling — If a resource was already manually deleted. 
                 # - The script doesn't crash — it just logs a warning and moves on.

#Complete Cleanup — Deletes not just the EC2 instance. 
                # - But ALL associated resources — key pair, security group, IAM role, instance profile, local .pem file and the details text file.

### What Does This Script Actually Do? (Step by Step)?

#- Checks if the mission-deh-hof-ec2-details.txt file exists — if yes, loads resource IDs from it directly.
#- If the details file is missing, searches AWS by resource names and tags to find everything.
#- Terminates the EC2 instance and waits until it is fully gone before proceeding.
#- Deletes the Security Group (firewall) — only possible after instance is terminated.
#- Removes the IAM Role from the Instance Profile then deletes the instance profile.
#- Detaches the SSM policy from the IAM role then deletes the role.
#- Deletes the Key Pair from AWS and also removes the .pem file from your local computer.
#- Deletes the details text file since all resources are now gone.
#- Logs every single step with timestamps to a log file.
#- Prints a final confirmation summary when everything is cleaned up.

### How Was This Script Created? What Prompt Was Used?
# This script was most likely created using a prompt along these lines:

# The Core Prompt:
# Create a bash teardown script that deletes all AWS resources.
# created by my EC2 setup script with the following requirements:

# Resources to delete (in this order):

#1. Terminate EC2 instance (wait until fully terminated).
#2. Delete Security Group.
#3. Remove role from instance profile, then delete instance profile.
#4. Detach SSM policy from IAM role, then delete the role.
#5. Delete key pair from AWS and remove local .pem file.
#6. Delete the saved details text file.

# Smart Resource Discovery:

#- First try to load resource IDs from "ec2-details.txt" file.
#- If that file doesn't exist, search for resources by name/tag as fallback.
#- If a resource is already deleted, log a warning and continue (don't crash).

# Safety & Logging:

#- Use set -e to stop on errors.
#- Log every step with timestamps.
#- Write logs to both screen and a timestamped log file.
#- Wait for instance to fully terminate before deleting security group.

# Naming convention: prefix everything with "mission-deh-hof-unix-"

### If You Want to Create a Similar Teardown Script in Future, Use This Prompt Template:

#Create a production-ready bash teardown/cleanup script that,
#deletes all AWS resources created by my [setup script name],
#with the following:

#1. RESOURCES TO DELETE (in correct dependency order):
   #- [list resources in reverse order of creation].
   #- e.g. EC2 instance first, then security group, then IAM role.
   #- Always wait for EC2 to terminate before deleting security group.

#2. SMART RESOURCE DISCOVERY:
   #- Try to load resource IDs from a saved details file first.
   #- If details file is missing, search by resource name/tag.
   #- Handle "None" or empty responses from AWS gracefully.

#3. ERROR HANDLING:
   #- If a resource is already deleted, log warning and continue.
   #- Use || to catch errors without crashing the script.
   #- Use set -e for overall safety.

#4. LOGGING:
   #- Timestamp every log message.
   #- Save logs to a file with date/time in filename.
   #- Print progress to screen as well.

#5. CLEANUP:
   #- Delete the details file at the end.
   #- Delete any local files created (e.g. .pem files).

#6. NAMING:
  #- Prefix all resource names with "[your-prefix]-"

### Setup Script vs Teardown Script — Key Differences:

              ### Setup Script	                                        Teardown Script
#Purpose      | Build everything	                                | Destroy everything.
#Order        | Create in dependency order	                        | Delete in REVERSE dependency order.
#Error handling | Rollback everything	                            | Log warning and keep going.
#Resource tracking | Saves IDs to details file	                    | Reads IDs from details file.
#End result	       | Running EC2 instance	                        | Empty AWS account.
#When to run	   | Before training session	                    | After training session.

### The Golden Rule of Teardown Scripts:

# 1. Always delete resources in reverse order of how they were created.
# 2. You can't delete a security group while an EC2 instance is still using it.
# 3. You can't delete an IAM role while it still has policies attached.
# 4. You can't delete an instance profile while a role is still inside it.
# 5. Think of it like undoing a knot — you have to pull the threads in the right order or it gets tighter!

### Setup + Teardown Together = Complete Workflow:

# Before Training:          After Training:
# ─────────────────         ─────────────────
# Run setup script    →     Do your training   →   Run teardown script
# (5 min to build)          (learn Unix)            (3 min to destroy)
                                                   
# 💰 Cost: ~$0.01/hr        💰 Cost: ~$0.01/hr      💰 Cost: $0.00/hr
# while training            while training           everything deleted!

#SETUP SCRIPT                    TEARDOWN SCRIPT
#─────────────────────────────────────────────────
#Create Key Pair          →      Delete Key Pair + .pem file
#Create Security Group    →      Delete Security Group
#Create IAM Role          →      Detach Policy → Delete Role
#Create Instance Profile  →      Remove Role → Delete Profile
#Launch EC2 Instance      →      Terminate EC2 Instance
#Save details to file     →      Delete details file