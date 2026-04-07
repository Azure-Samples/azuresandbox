#!/bin/bash

# Clean up terraform temporary files within the repository.
# Scoped to SCRIPT_DIR parent (repo root) to avoid deleting files outside the workspace.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

printf "Removing all files matching 'terraform.tfvars'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfvars' 
find "$REPO_ROOT" -type f -name 'terraform.tfvars' | xargs -r rm

printf "Removing all files matching 'terraform.tfstate'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfstate' 
find "$REPO_ROOT" -type f -name 'terraform.tfstate' | xargs -r rm

printf "Removing all files matching 'terraform.tfstate.backup'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfstate.backup' 
find "$REPO_ROOT" -type f -name 'terraform.tfstate.backup' | xargs -r rm

printf "Removing all files matching 'terraform.tfstate.*.backup'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfstate.*.backup' 
find "$REPO_ROOT" -type f -name 'terraform.tfstate.*.backup' | xargs -r rm

printf "Removing all files and directories matching '.terraform'...\n"

find "$REPO_ROOT" -type d -name '.terraform'
find "$REPO_ROOT" -type d -name '.terraform' | xargs -r rm -r

printf "Removing all files matching '.terraform.tfstate.lock.info'...\n"

find "$REPO_ROOT" -type f -name '.terraform.tfstate.lock.info' 
find "$REPO_ROOT" -type f -name '.terraform.tfstate.lock.info' | xargs -r rm

printf "Removing all files matching '.terraform.lock.hcl'...\n"

find "$REPO_ROOT" -type f -name '.terraform.lock.hcl' 
find "$REPO_ROOT" -type f -name '.terraform.lock.hcl' | xargs -r rm

printf "Removing all files matching 'sshkeytemp*'...\n"

find "$REPO_ROOT" -type f -name 'sshkeytemp*' 
find "$REPO_ROOT" -type f -name 'sshkeytemp*' | xargs -r rm

printf "Removing all files matching '*.pem'...\n"

find "$REPO_ROOT" -type f -name '*.pem' 
find "$REPO_ROOT" -type f -name '*.pem' | xargs -r rm

printf "Removing all files matching '*.pfx'...\n"

find "$REPO_ROOT" -type f -name '*.pfx' 
find "$REPO_ROOT" -type f -name '*.pfx' | xargs -r rm

printf "Removing all files matching '*.log'...\n"

find "$REPO_ROOT" -type f -name '*.log' 
find "$REPO_ROOT" -type f -name '*.log' | xargs -r rm

exit 0
