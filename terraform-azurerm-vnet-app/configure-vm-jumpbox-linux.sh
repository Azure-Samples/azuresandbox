#!/bin/bash

# Note: This code has been tested on Ubuntu 20.04 LTS (Focal Fossa) and will not work on other Linux distros

# Initialize constants
log_file='/run/cloud-init/tmp/configure-vm-jumpbox-linux.log'

printdiv() {
    printf  '=%.0s' {1..100} >> $log_file
    printf  '\n' >> $log_file
}

# Startup
printdiv
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n" >> $log_file
printf "Starting '$0'...\n" >> $log_file

# Get key vault from tags
tag_name='keyvault'
printf "Getting tag name '$tag_name'...\n" >> $log_file
key_vault_name=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "Key vault name is '$key_vault_name'...\n" >> $log_file

# Get domain name from tags
tag_name='adds_domain_name'
printf "Getting tag name '$tag_name'...\n" >> $log_file
adds_domain_name=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "Domain name is '$adds_domain_name'...\n" >> $log_file
adds_realm_name=$(echo $adds_domain_name | tr '[:lower:]' '[:upper:]')
printf "Realm name is '$adds_realm_name'...\n" >> $log_file

# Get managed identity access token for key vault
printf "Getting managed identity access token...\n" >> $log_file
response=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true -s)
access_token=$(echo $response |  jp -u 'access_token')
printf "Access token length is '${#access_token}'...\n" >> $log_file

# Get adminuser secret from key vault
secret_name="adminuser"
printf "Getting '$secret_name' secret from key vault...\n" >> $log_file
secret_uri="https://$key_vault_name.vault.azure.net/secrets/$secret_name?api-version=7.2"
admin_username=$(curl -X GET -H "Authorization: Bearer $access_token" -H "Content-Type:appplication/json" "$secret_uri" | jp -u 'value')
printf "Value of '$secret_name' secret is '$admin_username'...\n" >> $log_file

# Get adminpassword secret from key vault
secret_name="adminpassword"
printf "Getting '$secret_name' secret from key vault...\n" >> $log_file
secret_uri="https://$key_vault_name.vault.azure.net/secrets/$secret_name?api-version=7.2"
admin_password=$(curl -X GET -H "Authorization: Bearer $access_token" -H "Content-Type:appplication/json" "$secret_uri" | jp -u 'value')
printf "Length of '$secret_name' secret is '${#admin_password}'...\n" >> $log_file
printdiv

# Update hosts file
filename=/etc/hosts
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "s/127.0.0.1 localhost/127.0.0.1 `hostname`.$adds_domain_name `hostname`/" $filename
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Update DHCP configuration
filename=/etc/dhcp/dhclient.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "s/#supersede domain-name \"fugue.com home.vix.com\";/supersede domain-name \"$adds_domain_name\";/" $filename
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Update NTP configuration
filename=/etc/ntp.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "$ a server $adds_domain_name" $filename
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Update Kerberos configuration
filename=/etc/krb5.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i '/^\[libdefaults\]/a \        rdns=false' $filename
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Renew DHCP 
printf "Renewing DHCP...\n" >> $log_file
sudo dhclient eth0 -v &>> $log_file
printdiv

# Join domain
printf "Joining domain...\n" >> $log_file
echo $admin_password | sudo realm join --verbose $adds_realm_name -U "$admin_username@$adds_realm_name" --install=/ &>> $log_file
printdiv

# Create keytab file then authenticate with AD
filename="/etc/$admin_username.keytab"
printf "Creating keytab file '$filename'...\n" >> $log_file
printf "%b" "addent -password -p $admin_username@$adds_realm_name -k 1 -e RC4-HMAC\n$admin_password\nwkt $filename\nq\n" | sudo ktutil &>> $log_file
printf "Authenticating using keytab file '$filename'...\n" >> $log_file
sudo kinit -V -k -t /etc/$admin_username.keytab $admin_username@$adds_realm_name &>> $log_file
printdiv

# Register with DNS server
commands="update add `hostname`.$adds_domain_name 3600 a `hostname -I`\nsend\n"
printf "Registering with DNS server...\n" >> $log_file
printf "%b" "nsgupdate -g\n$commands" >> $log_file
printf "%b" "$commands" | sudo nsupdate -g
printdiv

# Configure dynamic DNS registration
filename='/etc/dhcp/dhclient-exit-hooks.d/hook-ddns'
printf "Creating DHCP client exit hook '$filename'...\n" >> $log_file
sudo bash -c "cat > $filename" <<EOF
#!/bin/sh
adds_realm_name=\$(echo \$new_domain_name | tr "[:lower:]" "[:upper:]")
host=\`hostname\`
admin_username=$admin_username
if [ "\$interface" != "eth0" ]
then
  return
fi
if [ "\$reason" = BOUND ] || [ "\$reason" = RENEW ] ||
   [ "\$reason" = REBIND ] || [ "\$reason" = REBOOT ]
then
  sudo kinit -k -t "/etc/\$admin_username.keytab" "\$admin_username@\$adds_realm_name"
  printf "%b" "update delete \$host.\$new_domain_name a\nupdate add \$host.\$new_domain_name 3600 a \$new_ip_address\nsend\n" | nsupdate -g
fi
EOF
sudo chmod 755 $filename &>> $log_file
sudo cat $filename >> $log_file
printdiv

# Configure privileged access management
printf "Configuring privileged access management...\n" >> $log_file
sudo pam-auth-update --enable 'mkhomedir' --force &>> $log_file
servicename='sssd'
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
username="$admin_username@$adds_domain_name"
printf "Permit logins for user '$username'...\n" >> $log_file
sudo realm permit -v $username &>> $log_file
groupname='sudo'
printf "Adding user '$username' to group '$groupname'...\n" >> $log_file
sudo usermod -aG $groupname $username &>> $log_file
printf "Checking id '$username'...\n"  >> $log_file
id "$username" >> $log_file
printdiv

# Update ssh configuration 
filename=/etc/ssh/sshd_config
printf "Backing up file '$filename'...\n" >> $log_file
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" $filename
sudo sed -i "s/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/" $filename
diff "$filename.bak" "$filename" >> $log_file
servicename='sshd'
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
printdiv

# Exit
printf "Exiting '$0'...\n" >> $log_file
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n" >> $log_file
printdiv
exit 0
