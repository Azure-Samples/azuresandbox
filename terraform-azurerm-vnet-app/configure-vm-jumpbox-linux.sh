#!/bin/bash

# Note: This code has been tested on Ubuntu 24.04 LTS (Noble Numbat) and will not work on other Linux distros

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

# Get arguments from config file
config_file=/etc/azuresandbox-conf.json
if [ -f "$config_file" ]
then
    printf "Config file '$config_file' found...\n" >> $log_file
else
    printf "Config file '$config_file' not found...\n" >> $log_file
fi

printf "Getting variables from file '$config_file'...\n" >> $log_file

var_name=adds_domain_name
adds_domain_name=$(jp -f $config_file -u $var_name)
printf "Domain name is '$adds_domain_name'...\n" >> $log_file
adds_realm_name=$(echo $adds_domain_name | tr '[:lower:]' '[:upper:]')
printf "Realm name is '$adds_realm_name'...\n" >> $log_file

var_name=dns_server
dns_server=$(jp -f $config_file -u $var_name)
printf "DNS server address is '$dns_server'...\n" >> $log_file

var_name=key_vault_name
key_vault_name=$(jp -f $config_file -u $var_name)
printf "Key vault name is '$key_vault_name'...\n" >> $log_file

var_name=storage_account_name
storage_account_name=$(jp -f $config_file -u $var_name)
printf "CIFS storage account name is '$storage_account_name'...\n" >> $log_file

var_name='storage_share_name'
storage_share_name=$(jp -f $config_file -u $var_name)
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
sudo sed -i "s/#PasswordAuthentication yes/PasswordAuthentication yes/" $filename
sudo sed -i "s/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/" $filename
diff "$filename.bak" "$filename" >> $log_file
servicename='ssh'
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
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
sudo sudo sed -i '/set-name:/a \      nameservers:' $filename
sudo sudo sed -i "/nameservers:/a \        addresses: [$dns_server, 168.63.129.16]" $filename
sudo sudo sed -i "/addresses:/a \        search: [$adds_domain_name, reddog.microsoft.com]" $filename
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
printf "Configuring pluggable authentication (PAM) module for winbind...\n" >> $log_file
sudo pam-auth-update --enable winbind &>> $log_file
sudo pam-auth-update --enable mkhomedir &>> $log_file
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
sudo systemctl status winbind &>> $log_file
groupname='sudo'
printf "Adding user '$admin_username' to group '$groupname'...\n" >> $log_file
sudo usermod -aG $groupname $admin_username &>> $log_file
printdiv

# Update NTP configuration
filename=/etc/ntpsec/ntp.conf
sudo cp -f "$filename" "$filename.bak"
printf "Modifying '$filename'...\n" >> $log_file
sudo sed -i "s/server ntp.ubuntu.com/server $adds_domain_name/" $filename
diff "$filename.bak" "$filename" >> $log_file
servicename='ntp'
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
sudo systemctl status $servicename &>> $log_file
printdiv

# Mount CIFS file system
printf 'Configuring dynamic mount of CIFS filesystem...\n' >> $log_file

filename="/etc/auto.fileshares"
printf "Creating '$filename'...\n" >> $log_file
cifs_unc_path="//$storage_account_name.file.core.windows.net/$storage_share_name"
echo "/fileshares/$storage_share_name -fstype=cifs,multiuser,sec=krb5,cruid=\${UID},nofail,serverino,nosharesock,actimeo=30,dir_mode=0777,file_mode=0777 :$cifs_unc_path" | sudo tee $filename > /dev/null
sudo cat $filename >> $log_file

filename=/etc/auto.master
printf "Modifying '$filename'...\n" >> $log_file
sudo cp -f "$filename" "$filename.bak"
echo "/- /etc/auto.fileshares --timeout=60" | sudo tee -a $filename > /dev/null
diff "$filename.bak" "$filename" >> $log_file

servicename='autofs'
printf "Restarting '$servicename'...\n" >> $log_file
sudo systemctl restart $servicename &>> $log_file
printdiv

# Manually install powershell due to issue https://github.com/PowerShell/PowerShell/issues/21385
printf "Installing PowerShell...\n" >> $log_file

tmpDir=$(mktemp -d)
curl -sSL 'https://launchpad.net/ubuntu/+archive/primary/+files/libicu72_72.1-3ubuntu3_amd64.deb' -o "$tmpDir/libicu72_72.1-3ubuntu3_amd64.deb"
dpkg -i "$tmpDir"/libicu72_72.1-3ubuntu3_amd64.deb

downloadUrl=$(curl -sSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" |
	jq -r '[.assets[] | select(.name | endswith("_amd64.deb")) | .browser_download_url][0]')
curl -sSL "$downloadUrl" -o "$tmpDir/powershell.deb"
dpkg -i "$tmpDir"/powershell.deb

# Embed and run the PowerShell script
printf "Configuring PowerShell...\n" >> $log_file
pwsh << 'EOF'
#!/usr/bin/env pwsh

function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}
function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    Exit 2
}
$nugetPackage = Get-PackageProvider | Where-Object Name -eq 'NuGet'

if ($null -eq $nugetPackage) {
    Write-Log "Installing NuGet PowerShell package provider..."

    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force 
    }
    catch {
        Exit-WithError $_
    }
}

$nugetPackage = Get-PackageProvider | Where-Object Name -eq 'NuGet'
Write-Log "NuGet Powershell Package Provider version $($nugetPackage.Version.Major).$($nugetPackage.Version.Minor).$($nugetPackage.Version.Build).$($nugetPackage.Version.Revision) is already installed..."

$repo = Get-PSRepository -Name PSGallery
if ( $repo.InstallationPolicy -eq 'Trusted' ) {
    Write-Log "PSGallery installation policy is already set to 'Trusted'..."
}
else {
    Write-Log "Setting PSGallery installation policy to 'Trusted'..."

    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted    
    }
    catch {
        Exit-WithError $_
    }
}

$azModule = Get-Module -ListAvailable -Name Az*
if ($null -eq $azModule ) {
    Write-Log "Installing PowerShell Az module..."

    try {
        Install-Module -Name Az -AllowClobber -Scope AllUsers
    }
    catch {
        Exit-WithError $_
    }
}
else {
    Write-Log "PowerShell Az module is already installed..."
}

$azAutomationModule = Get-Module -ListAvailable -Name Az
Write-Log "PowerShell Az version $($azAutomationModule.Version) is installed..."

Exit 0
EOF

# Exit
printf "Exiting '$0'...\n" >> $log_file
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n" >> $log_file
printf "Exiting '$0'...\n"
printf "Timestamp: $(date +"%Y-%m-%d %H:%M:%S.%N %Z")...\n"
printdiv
exit 0
