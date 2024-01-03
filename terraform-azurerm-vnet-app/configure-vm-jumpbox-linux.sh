#!/bin/bash

# Note: This code has been tested on Ubuntu 20.04 LTS (Focal Fossa) and will not work on other Linux distros

# Initialize constants
log_file='/var/log/configure-vm-jumpbox-linux.log'

printdiv() {
    printf  '=%.0s' {1..80} >> $log_file
    printf  '\n' >> $log_file
}

# Startup
printdiv
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n" > $log_file
printf "Starting '$0'...\n" >> $log_file
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n"
printf "Starting '$0'...\n"
printf "See log file '$log_file' for details...\n"
printdiv

# Get variables from tags
tag_name='keyvault'
key_vault_name=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "Key vault name is '$key_vault_name'...\n" >> $log_file

tag_name='adds_domain_name'
printf "Getting tag name '$tag_name'...\n" >> $log_file
adds_domain_name=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "Domain name is '$adds_domain_name'...\n" >> $log_file
adds_realm_name=$(echo $adds_domain_name | tr '[:lower:]' '[:upper:]')
printf "Realm name is '$adds_realm_name'...\n" >> $log_file

tag_name='dns_server'
printf "Getting tag name '$tag_name'...\n" >> $log_file
dns_server=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "DNS server address is '$dns_server'...\n" >> $log_file

tag_name='storage_account_name'
printf "Getting tag name '$tag_name'...\n" >> $log_file
storage_account_name=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "CIFS storage account name is '$storage_account_name'...\n" >> $log_file

tag_name='storage_share_name'
printf "Getting tag name '$tag_name'...\n" >> $log_file
storage_share_name=$(jp -f "/run/cloud-init/instance-data.json" -u "ds.meta_data.imds.compute.tagsList[?name == '$tag_name'] | [0].value")
printf "CIFS share name is '$storage_share_name'...\n" >> $log_file

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

# Update NTP configuration
filename=/etc/ntp.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "$ a server $adds_domain_name" $filename
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Update hosts file
filename=/etc/hosts
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "s/127.0.0.1 localhost/127.0.0.1 `hostname`.$adds_domain_name `hostname`/" $filename
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Update DNS configuration
filename=/etc/netplan/50-cloud-init.yaml
printf "Modifying '$filename'...\n" >> $log_file
sudo cp -f "$filename" "$filename.bak"
sudo sudo sed -i '/set-name:/a \            nameservers:' $filename
sudo sudo sed -i "/nameservers:/a \                addresses: [$dns_server, 168.63.129.16]" $filename
sudo sudo sed -i "/addresses:/a \                search: [$adds_domain_name, reddog.microsoft.com]" $filename
diff "$filename.bak" "$filename" >> $log_file
printf "Generating netplan...\n" >> $log_file
sudo netplan generate &>> $log_file
printf "Applying netplan...\n" >> $log_file
sudo netplan apply &>> $log_file
printf "Checking DNS configuration...\n" >> $log_file
sudo resolvectl status &>> $log_file
printdiv

# Configure dynamic DNS registration
filename='/etc/dhcp/dhclient-exit-hooks.d/hook-ddns'
printf "Creating DHCP client exit hook '$filename'...\n" >> $log_file
sudo bash -c "cat > $filename" <<EOF
#!/bin/sh

if [ "\$interface" != "eth0" ]
then
  return
fi

if [ "\$reason" = BOUND ] || [ "\$reason" = RENEW ] ||
   [ "\$reason" = REBIND ] || [ "\$reason" = REBOOT ]
then
  host=`hostname -f`
  nsupdatecmds=/var/tmp/nsupdatecmds

  echo "update delete \$host a" > \$nsupdatecmds
  echo "update add \$host 3600 a \$new_ip_address" >> \$nsupdatecmds
  echo "send" >> \$nsupdatecmds
 
  nsupdate \$nsupdatecmds
fi
EOF
sudo chmod 755 $filename &>> $log_file
sudo cat $filename >> $log_file
printdiv

# Update Kerberos configuration
filename=/etc/krb5.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
echo "[libdefaults]" | sudo tee $filename > /dev/null
echo "        default_realm = $adds_realm_name" | sudo tee -a $filename > /dev/null
echo "        dns_lookup_realm = false" | sudo tee -a $filename > /dev/null
echo "        dns_lookup_kdc = true" | sudo tee -a $filename > /dev/null
diff "$filename.bak" "$filename" >> $log_file
printdiv

# Update SMB configuration
filename=/etc/samba/smb.conf
workgroup=$(echo $adds_realm_name | sed 's/\.LOCAL$//')
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
echo "[global]" | sudo tee $filename > /dev/null
echo "   workgroup = $workgroup" | sudo tee -a $filename > /dev/null
echo "   security = ADS" | sudo tee -a $filename > /dev/null
echo "   realm = $adds_realm_name" | sudo tee -a $filename > /dev/null
echo "   winbind refresh tickets = Yes" | sudo tee -a $filename > /dev/null
echo "   vfs objects = acl_xattr" | sudo tee -a $filename > /dev/null
echo "   map acl inherit = Yes" | sudo tee -a $filename > /dev/null
echo "   store dos attributes = Yes" | sudo tee -a $filename > /dev/null
echo "   dedicated keytab file = /etc/krb5.keytab" | sudo tee -a $filename > /dev/null
echo "   kerberos method = secrets and keytab" | sudo tee -a $filename > /dev/null
echo "   winbind use default domain = Yes" | sudo tee -a $filename > /dev/null
echo "   load printers = No" | sudo tee -a $filename > /dev/null
echo "   printing = bsd" | sudo tee -a $filename > /dev/null
echo "   printcap name = /dev/null" | sudo tee -a $filename > /dev/null
echo "   disable spoolss = Yes" | sudo tee -a $filename > /dev/null
echo "   log file = /var/log/samba/log.%m" | sudo tee -a $filename > /dev/null
echo "   log level = 1" | sudo tee -a $filename > /dev/null
echo "   idmap config * : backend = tdb" | sudo tee -a $filename > /dev/null
echo "   idmap config * : range = 3000-7999" | sudo tee -a $filename > /dev/null
echo "   idmap config $workgroup : backend = rid" | sudo tee -a $filename > /dev/null
echo "   idmap config $workgroup : range = 10000-999999" | sudo tee -a $filename > /dev/null
echo "   template shell = /bin/bash" | sudo tee -a $filename > /dev/null
echo "   template homedir = /home/%U" | sudo tee -a $filename > /dev/null
diff "$filename.bak" "$filename" >> $log_file
printf "Force windbind to reload the changed config file...\n" >> $log_file
sudo smbcontrol all reload-config &>> $log_file
printdiv

# Join domain
printf "Joining domain...\n" >> $log_file
echo $admin_password | sudo net ads join -U $admin_username &>> $log_file
printdiv

# Configure winbind
filename=/etc/nsswitch.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i 's/passwd:         files systemd/passwd:         compat systemd winbind/g' $filename
sudo sed -i 's/group:          files systemd/group:          compat systemd winbind/g' $filename
diff "$filename.bak" "$filename" >> $log_file
servicename='winbind'
printf "Enabling '$servicename'...\n" >> $log_file
sudo systemctl enable $servicename &>> $log_file
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
sudo systemctl status winbind &>> $log_file
printf "Configuring pluggable authentication (PAM) module for winbind...\n" >> $log_file
sudo pam-auth-update --enable winbind &>> $log_file
sudo pam-auth-update --enable mkhomedir &>> $log_file
groupname='sudo'
printf "Adding user '$admin_username' to group '$groupname'...\n" >> $log_file
sudo usermod -aG $groupname $admin_username &>> $log_file
printdiv

# Mount CIFS file system
# printf 'Configuring dynamic mount of CIFS filesystem...\n' >> $log_file

# cifs_mount_dir="/$storage_account_name/$storage_share_name"
# printf "Creating mount directory '$cifs_mount_dir'...\n" >> $log_file
# sudo mkdir -p $cifs_mount_dir &>> $log_file

# cred_file_dir="/etc/smbcredentials"
# printf "Creating credential files directory '$cred_file_dir'...\n" >> $log_file
# sudo mkdir $cred_file_dir &>> $log_file

# cred_file="$cred_file_dir/$storage_account_name.cred"
# printf "Creating credential file '$cred_file'...\n" >> $log_file
# echo "username=$admin_username" | sudo tee $cred_file > /dev/null
# echo "password=$admin_password" | sudo tee -a $cred_file > /dev/null
# sudo chmod 600 $cred_file &>> $log_file

# filename="/etc/auto.$storage_account_name"
# printf "Creating '$filename'...\n" >> $log_file
# cifs_unc_path="//$storage_account_name.file.core.windows.net/$storage_share_name"
# echo "$storage_share_name -fstype=cifs,nofail,credentials=$cred_file,serverino,nosharesock,actimeo=30,sec=krb5,dir_mode=0777,file_mode=0777 :$cifs_unc_path" | sudo tee $filename > /dev/null
# sudo cat $filename >> $log_file

# filename=/etc/auto.master
# printf "Modifying '$filename'...\n" >> $log_file
# sudo cp -f "$filename" "$filename.bak"
# echo "/$storage_account_name /etc/auto.$storage_account_name --timeout=60" | sudo tee -a $filename > /dev/null
# diff "$filename.bak" "$filename" >> $log_file

# servicename='autofs'
# printf "Restarting '$servicename'...\n" >> $log_file
# sudo systemctl restart $servicename &>> $log_file
# printdiv

# Exit
printf "Exiting '$0'...\n" >> $log_file
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n" >> $log_file
printf "Exiting '$0'...\n"
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n"
printdiv
exit 0
