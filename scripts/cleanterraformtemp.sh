#!/bin/bash

# Clean up terraform temporary files within the repository.
# Scoped to SCRIPT_DIR parent (repo root) to avoid deleting files outside the workspace.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

printf "Removing all files matching 'terraform.tfvars'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfvars' 
find "$REPO_ROOT" -type f -name 'terraform.tfvars' -print0 | xargs -0 -r rm

printf "Removing all files matching 'terraform.tfstate'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfstate' 
find "$REPO_ROOT" -type f -name 'terraform.tfstate' -print0 | xargs -0 -r rm

printf "Removing all files matching 'terraform.tfstate.backup'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfstate.backup' 
find "$REPO_ROOT" -type f -name 'terraform.tfstate.backup' -print0 | xargs -0 -r rm

printf "Removing all files matching 'terraform.tfstate.*.backup'...\n"

find "$REPO_ROOT" -type f -name 'terraform.tfstate.*.backup' 
find "$REPO_ROOT" -type f -name 'terraform.tfstate.*.backup' -print0 | xargs -0 -r rm

printf "Removing all files and directories matching '.terraform'...\n"

find "$REPO_ROOT" -type d -name '.terraform'
find "$REPO_ROOT" -type d -name '.terraform' -print0 | xargs -0 -r rm -r

printf "Removing all files matching '.terraform.tfstate.lock.info'...\n"

find "$REPO_ROOT" -type f -name '.terraform.tfstate.lock.info' 
find "$REPO_ROOT" -type f -name '.terraform.tfstate.lock.info' -print0 | xargs -0 -r rm

printf "Removing all files matching '.terraform.lock.hcl'...\n"

find "$REPO_ROOT" -type f -name '.terraform.lock.hcl' 
find "$REPO_ROOT" -type f -name '.terraform.lock.hcl' -print0 | xargs -0 -r rm

printf "Removing all files matching 'sshkeytemp*'...\n"

find "$REPO_ROOT" -type f -name 'sshkeytemp*' 
find "$REPO_ROOT" -type f -name 'sshkeytemp*' -print0 | xargs -0 -r rm

printf "Removing all files matching '*.pem'...\n"

find "$REPO_ROOT" -type f -name '*.pem' 
find "$REPO_ROOT" -type f -name '*.pem' -print0 | xargs -0 -r rm

printf "Removing all files matching '*.pfx'...\n"

find "$REPO_ROOT" -type f -name '*.pfx' 
find "$REPO_ROOT" -type f -name '*.pfx' -print0 | xargs -0 -r rm

printf "Removing all files matching '*.log'...\n"

find "$REPO_ROOT" -type f -name '*.log' 
find "$REPO_ROOT" -type f -name '*.log' -print0 | xargs -0 -r rm

printf "Removing all files matching '*.tfplan'...\n"

find "$REPO_ROOT" -type f -name '*.tfplan' 
find "$REPO_ROOT" -type f -name '*.tfplan' -print0 | xargs -0 -r rm

exit 0
