#!/bin/bash

printf "Removing all files matching 'terraform.tfvars'...\n"

find ../. -type f -name 'terraform.tfvars' 
find ../. -type f -name 'terraform.tfvars' -print0 | xargs -0 -r rm

printf "Removing all files matching 'terraform.tfstate'...\n"

find ../. -type f -name 'terraform.tfstate' 
find ../. -type f -name 'terraform.tfstate' -print0 | xargs -0 -r rm

printf "Removing all files matching 'terraform.tfstate.backup'...\n"

find ../. -type f -name 'terraform.tfstate.backup' 
find ../. -type f -name 'terraform.tfstate.backup' -print0 | xargs -0 -r rm

printf "Removing all files matching 'terraform.tfstate.*.backup'...\n"

find ../. -type f -name 'terraform.tfstate.*.backup' 
find ../. -type f -name 'terraform.tfstate.*.backup' -print0 | xargs -0 -r rm

printf "Removing all files and directories matching '.terraform'...\n"

find ../. -type d -name '.terraform'
find ../. -type d -name '.terraform' -print0 | xargs -0 -r rm -r

printf "Removing all files matching '.terraform.tfstate.lock.info'...\n"

find ../. -type f -name '.terraform.tfstate.lock.info' 
find ../. -type f -name '.terraform.tfstate.lock.info' -print0 | xargs -0 -r rm

printf "Removing all files matching '.terraform.lock.hcl'...\n"

find ../. -type f -name '.terraform.lock.hcl' 
find ../. -type f -name '.terraform.lock.hcl' -print0 | xargs -0 -r rm

printf "Removing all files matching 'sshkeytemp*'...\n"

find ../. -type f -name 'sshkeytemp*' 
find ../. -type f -name 'sshkeytemp*' -print0 | xargs -0 -r rm

printf "Removing all files matching '*.pem'...\n"

find ../. -type f -name '*.pem' 
find ../. -type f -name '*.pem' -print0 | xargs -0 -r rm

printf "Removing all files matching '*.pfx'...\n"

find ../. -type f -name '*.pfx' 
find ../. -type f -name '*.pfx' -print0 | xargs -0 -r rm

exit 0
