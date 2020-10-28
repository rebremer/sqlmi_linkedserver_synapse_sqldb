# 0a. Paramaters
$SQLDB_user = "<<your SQLDB user>>"
$SQLDB_logicalserver_name = "<<your SQLDB logical server name>>"
$SQLDB_name = "<<your SQLDB name>>"
$SQLMI_user = "<<your SQLMI user>>"
$SQLMI_name = "<<your SQLMI name>>"
$AKV_name = "<<your key vault name>>"
$RG = "<<your resource group name>>"
$LOC = "westeurope"

#0b. Helper function to create a strong password
Function GenerateStrongPassword ([Parameter(Mandatory=$true)][int]$PasswordLenght)
{
    Add-Type -AssemblyName System.Web
    $PassComplexCheck = $false
    do {
        $newPassword=[System.Web.Security.Membership]::GeneratePassword($PasswordLenght,1)
        If ( ($newPassword -cmatch "[A-Z\p{Lu}\s]") `
            -and ($newPassword -cmatch "[a-z\p{Ll}\s]") `
            -and ($newPassword -match "[\d]") `
            -and ($newPassword -match "[^\w]")
        )
        {
            $PassComplexCheck=$True
        }
    } While ($PassComplexCheck -eq $false)
    return $newPassword
}

# 1. Create SQLMI instance
# 1a. Create strong password and store password in keyvault
$SQLMI_password = GenerateStrongPassword(20)
# 1b. Store
New-AzKeyVault -Name $AKV_name -ResourceGroupName $RG -Location $LOC
$SQLMI_password = GenerateStrongPassword(20)
$SQLMI_password_secure_string = ConvertTo-SecureString $SQLMI_password -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $AKV_name  -Name 'Synapse-password' -SecretValue $SQLMI_password_secure_string
# 1c. Create SQLMI instance
# See this script how to create a SQLMI using PowerShell
# https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/scripts/create-configure-managed-instance-powershell

# 2. Create SQLDB instance
# 2a. Create strong password and store password in keyvault
$SQLDB_password = GenerateStrongPassword(20)
# 2b. Store
$SQLDB_password_secure_string = ConvertTo-SecureString $SQLDB_password -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $AKV_name  -Name 'SQLDB-password' -SecretValue $SQLDB_password_secure_string
# 2c. Create SQLDB instance (az cli, todo change to PowerShell)
az sql server create -l $LOC -g $RG -n $SQLDB_logicalserver_name -u $SQLDB_user -p $SQLDB_password                       
az sql db create -g $RG -s $SQLDB_logicalserver_name -n $SQLDB_name --service-objective Basic --sample-name AdventureWorksLT    

# 3. Create linked server in SQLMI to SQLDB
$SQLMI_Connection='Server=tcp:{0}.database.windows.net,3342;Persist Security Info=False;User ID={1};Password={2};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;' -f $SQLMI_name, $SQLMI_user, $SQLMI_password
Invoke-Sqlcmd -Query "EXEC sp_addlinkedserver @server='coldpath2', @srvproduct='', @provider='SQLNCLI11', @datasrc='tcp:$Synapse_name.azuresynapse.net,1433', @location='', @provstr='', @catalog='colddata_ondemand'" -ConnectionString $SQLMI_Connection
Invoke-Sqlcmd -Query "EXEC sp_addlinkedsrvlogin @rmtsrvname = 'coldpath2', @useself = 'false', @rmtuser = '$Synapse_user', @rmtpassword = '$Synapse_password'" -ConnectionString $SQLMI_Connection
Invoke-Sqlcmd -Query "EXEC sp_serveroption 'coldpath2', 'rpc out', true;" -ConnectionString $SQLMI_Connection
# 3b. Query database from SQLMI to SQLDB
# Below an example of Synapse on demand, todo create SQLDB example
#Invoke-Sqlcmd -Query "SET QUOTED_IDENTIFIER OFF; EXEC(""select * from openrowset(bulk '$Synapse_parquet', format='parquet') as testrb"") AT coldpath2" -ConnectionString $SQLMI_Connection