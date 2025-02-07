# Install-Module -Name Microsoft.Azure.Kusto.Tools -Force
# Import-Module Microsoft.Azure.Kusto.Tools

# Use Kusto .NET client libraries from PowerShell to run management commands
[System.Reflection.Assembly]::LoadFrom("C:\Users\jeetzler\.nuget\packages\microsoft.azure.kusto.tools\13.0.0\tools\net8.0\Kusto.Data.dll")

# Set environment variables in the current session
$env:CLIENT_ID = "your-client-id"
$env:CLIENT_SECRET = "your-client-secret"
$env:TENANT_ID = "your-tenant-id"

# Define additional variables
$ADXclusterUri = "https://myadxcluster7.westus3.kusto.windows.net"
$databaseName = "ContosoSales"
$workspaceName = "Migration to RTI"
$eventhouseName = "Eventhouse"

# Retrieve service principal credentials from environment variables
$clientId = $env:CLIENT_ID
$clientSecret = $env:CLIENT_SECRET
$tenantId = $env:TENANT_ID

# Function to get access token
function Get-AccessToken {
    param (
        [string]$clientId,
        [string]$clientSecret,
        [string]$tenantId,
        [string]$resource
    )
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $clientId
        client_secret = $clientSecret
        resource      = $resource
    }
    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Body $body
    return $response.access_token
}

# Get the Fabric access token
$fabricToken = Get-AccessToken -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId -resource "https://api.fabric.microsoft.com"

$fabricHeaders = @{
    "Authorization" = "Bearer $fabricToken"
    "Content-Type"  = "application/json"
}

# Connect to source cluster and database
$kcsbAdx = New-Object Kusto.Data.KustoConnectionStringBuilder($ADXclusterUri, $databaseName)
$kcsbAdx = $kcsbadx.WithAadApplicationKeyAuthentication($clientId, $clientSecret, $tenantId)
$adminProviderAdx = [Kusto.Data.Net.Client.KustoClientFactory]::CreateCslAdminProvider($kcsbAdx)
$queryProviderAdx = [Kusto.Data.Net.Client.KustoClientFactory]::CreateCslQueryProvider($kcsbAdx)

# Get the workspace ID from the workspace name
$workspacesAPI = "https://api.fabric.microsoft.com/v1/workspaces"
$workspacesResponse = Invoke-RestMethod -Uri $workspacesAPI -Headers $fabricHeaders -Method Get

$workspace = $workspacesResponse.value | Where-Object { $_.displayName -eq $workspaceName }

if ($workspace) {
    $workspaceId = $workspace.id
    Write-Output "Workspace ID for '$workspaceName' is $workspaceId"
} else {
    Write-Error "Workspace '$workspaceName' not found."
    return
}

# Add service principal as admin to source database
$addAdminQuery = ".add database $databaseName admins ('aadapp=$clientId')"
$reader = $adminProviderAdx.ExecuteControlCommand($addAdminQuery)
Write-Output "Added admin to source database"

# Create an Eventhouse
$eventhouseBody = @{
    'displayName' = $eventhouseName
} | ConvertTo-Json -Depth 1

$eventhouseAPI = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/eventhouses"
$eventhouseResponse = Invoke-RestMethod -Uri $eventhouseAPI -Headers $fabricHeaders -Method Get

# Check if the eventhouse exists
$response = $eventhouseResponse.value | Where-Object { $_.displayName -eq $eventhouseName }

if ($response) {
    Write-Output "Eventhouse '$eventhouseName' exists in your workspace."
    
} else {
    Write-Output "Eventhouse '$eventhouseName' does not exist in your workspace."
    Write-Output "Creating Eventhouse $eventhouseName"
    $response = Invoke-RestMethod -Uri $eventhouseAPI -Method POST -Headers $fabricHeaders -Body $eventhouseBody   
}

$eventhouseId = $response.id
$queryServiceURI = $response.properties.queryServiceUri

# Create KQL Database in above Eventhouse
Write-Output "Creating KQL Database"

$kqlDBBody = @{
    'displayName' = $databaseName
    'creationPayload' = @{
        'databaseType' = "ReadWrite"
        'parentEventhouseItemId' = $eventhouseId
    }
} | ConvertTo-Json -Depth 2

$kqlDBAPI = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/kqlDatabases"
$kqlDbResponse = Invoke-RestMethod -Uri $kqlDBAPI -Headers $fabricHeaders -Method Get 

$response = $kqlDbResponse.value | Where-Object { $_.displayName -eq $databaseName }

if ($response) {
    Write-Output "KQL database '$databaseName' exists in your workspace."
} else {
    Write-Output "KQL database '$databaseName' does not exist in your workspace."
    Write-Output "Creating database $databaseName"
    $response = Invoke-RestMethod -Uri $kqlDBAPI -Method POST -Body $kqlDBBody -Headers $fabricHeaders    
}

Start-Sleep -Seconds 20  # Give time for the database to be created

# Re-fetch the database list to get the latest state
$kqlDbResponse = Invoke-RestMethod -Uri $kqlDBAPI -Headers $fabricHeaders -Method Get
$response = $kqlDbResponse.value | Where-Object { $_.displayName -eq $databaseName }
$databaseId = $response.id

# Ensure the database ID is correctly assigned
if ($databaseId) {
    Write-Output "Database ID: $databaseId"
} else {
    Write-Output "Failed to retrieve the database ID."
}

 # Connect to fabric rti cluster and database
 $kcsbRti = New-Object Kusto.Data.KustoConnectionStringBuilder($queryServiceURI, $databaseName)
 $adminProviderRti = [Kusto.Data.Net.Client.KustoClientFactory]::CreateCslAdminProvider($kcsbRti)

 # Add service principal as admin to rti database
 $reader = $adminProviderRti.ExecuteControlCommand($addAdminQuery)
 Write-Output "Added admin to target database"         

# Get the schema from ADX
$cslQuery = ".show database schema as csl script"
$reader = $queryProviderAdx.ExecuteControlCommand($cslQuery)
$reader.Read()

$adxSchemaResponse = [Kusto.Cloud.Platform.Data.ExtendedDataReader]::ToDataSet($reader).Tables[0]
Write-Ouput $adxSchemaResponse

# Execute each row (query) individually
$adxSchemaResponse.Rows | ForEach-Object {
    $individualQuery = $_[0]
    $executeScript = $individualQuery

    try {        
        $reader = $adminProviderAdx.ExecuteControlCommand($executeScript)        
        Write-Output "Executed script: $individualQuery"
        Write-Output $reader.Read()
        
    } catch {
        Write-Error "Failed to execute script: $individualQuery. Error: $_"
    }
}
