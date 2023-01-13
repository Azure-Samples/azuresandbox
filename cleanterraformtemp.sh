#!/bin/bash

printf "Removing all files matching 'terraform.*'...\n"

find . -type f -name 'terraform.*' 
find . -type f -name 'terraform.*' | xargs -r rm

printf "Removing all files and directories matching '.terraform'...\n"

find . -type d -name '.terraform'
find . -type d -name '.terraform' | xargs -r rm -r

printf "Removing all files matching '.terraform.tfstate.lock.info'...\n"

find . -type f -name '.terraform.tfstate.lock.info' 
find . -type f -name '.terraform.tfstate.lock.info' | xargs -r rm

printf "Removing all files matching '.terraform.lock.hcl'...\n"

find . -type f -name '.terraform.lock.hcl' 
find . -type f -name '.terraform.lock.hcl' | xargs -r rm

printf "Removing all files matching 'sshkeytemp*'...\n"

find . -type f -name 'sshkeytemp*' 
find . -type f -name 'sshkeytemp*' | xargs -r rm

printf "Removing all files matching '*.mim'...\n"

find . -type f -name '*.mim' 
find . -type f -name '*.mim' | xargs -r rm

printf "Removing all files matching '*.cer'...\n"

find . -type f -name '*.cer' 
find . -type f -name '*.cer' | xargs -r rm

exit 0
