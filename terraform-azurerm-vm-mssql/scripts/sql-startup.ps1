$path = "D:\SQLTEMP"

if ( -not ( Test-Path $path ) ) {
    New-Item -ItemType Directory -Path $path -Force 
}

Start-Service -Name MSSQLSERVER
Start-Service -Name SQLSERVERAGENT
