# Azure Sandbox Modules

The following modules are included in this configuration:

Name | Required | Description
--- | --- | ---
[vnet-shared](./vnet-shared/) | Yes | Includes a shared services virtual network including a Bastion Host, Azure Firewall and an AD domain controller/DNS server VM.
[vnet-app](./vnet-app/) | No | Includes an application virtual network, a network isolated Azure Files share and a preconfigured Windows jumpbox VM.
[vm-jumpbox-linux](./vm-jumpbox-linux/) | No | Includes a preconfigured Linux jumpbox VM in the application virtual network.
[vm-mssql-win](./vm-mssql-win/) | No | Includes a preconfigured Windows VM with SQL Server in the application virtual network.
[mssql](./mssql/) | No | Includes a network isolated Azure SQL Database in the application virtual network.
[mysql](./mysql/) | No | Creates a network isolated Azure MySQL Database in the application virtual network.
[vwan](./vwan/) | No | Creates a Point-to-Site VPN gateway to securely connect to your sandbox environment from your local machine.
