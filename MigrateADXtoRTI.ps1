# Install-Module Az

$ADXclusterUri = "https://myadxcluster7.westus3.kusto.windows.net"
$databaseName = "ContosoSales"
$workspaceName = "Migration to RTI"
$workspaceId = "e81e1d6b-a097-4939-b3b5-bdef977b318f"
$eventhouseName = "Eventhouse"

$tenantId = "2f250fde-b995-4c3b-a347-79dab0d3311b"
Connect-AzAccount -TenantId $tenantId | Out-Null

#  Get the token to authenticate to Fabric
$baseFabricUrl = "https://api.fabric.microsoft.com"
    $fabricToken = (Get-AzAccessToken -ResourceUrl $baseFabricUrl).Token
    $headerParams = @{'Authorization'="Bearer {0}" -f $fabricToken}
    $contentType = @{'Content-Type' = "application/json"}

# Create an Eventhouse    
$eventhouseName = "EH_PSTest11"

$body = @{
'displayName' = $eventhouseName
} | ConvertTo-Json -Depth 1

$eventhouseAPI = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/eventhouses" 
$eventhouseCreate = Invoke-RestMethod -Headers $headerParams -Method POST -Uri $eventhouseAPI -Body ($body) -ContentType "application/json"
$eventhouseId= ($eventhouseCreate.id).ToString()

# Create KQL Database in above Eventhouse
$kqlDBName = $databaseName

# Create body of request
$body = @{       
            'displayName' = $kqlDBName;
            'creationPayload'= @{
            'databaseType' = "ReadWrite";
            'parentEventhouseItemId' = $eventhouseId}
             } | ConvertTo-Json -Depth 2

$kqlDBAPI = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/kqlDatabases"

# Call KQL DB create API
Invoke-RestMethod -Headers $headerParams -Method GET -Uri $kqlDBAPI -ContentType "application/json" -verbose