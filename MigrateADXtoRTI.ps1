# Set environment variables in the current session
$env:CLIENT_ID = "your-client-id"
$env:CLIENT_SECRET = "your-client-secret"
$env:TENANT_ID = "your-tenant-id"

# Retrieve service principal credentials from environment variables
$clientId = $env:CLIENT_ID
$clientSecret = $env:CLIENT_SECRET
$tenantId = $env:TENANT_ID
   
# Get the ADX access token
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    resource      = $ADXclusterUri
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Body $body
$adxToken = $tokenResponse.access_token

$adxHeaders = @{
    "Authorization" = "Bearer $adxToken"
    "Content-Type"  = "application/json"
}

# Get the Fabric access token
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    resource      = "https://api.fabric.microsoft.com"
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Body $body
$fabricToken = $tokenResponse.access_token

$fabricHeaders = @{
    "Authorization" = "Bearer $fabricToken"
    "Content-Type"  = "application/json"
}

# Add service principal as admin to source database
$addAdminQuery = ".add database $databaseName admins ('aadapp=$clientId')"

$body = @{
    "db"  = $databaseName
    "csl" = $addAdminQuery
} | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$ADXclusterUri/v1/rest/mgmt" -Method Post -Headers $adxHeaders -Body $body
Write-Output "Added admin to target database: $($response | ConvertTo-Json -Depth 10)"

# Create an Eventhouse    
$ehbody = @{
'displayName' = $eventhouseName
} | ConvertTo-Json -Depth 1

$eventhouseAPI = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/eventhouses" 

# Make the API request to get the list of eventhouses
$response = Invoke-RestMethod -Uri $eventhouseAPI -Headers $fabricHeaders -Method Get

# Check if the eventhouse exists
$eventhouseExists = $response.value | Where-Object { $_.displayName -eq $eventhouseName }

if ($eventhouseExists) {
    Write-Output "Eventhouse '$eventhouseName' exists in your workspace."   
    $eventhouseId= ($eventhouseExists.id).ToString()
    $queryServiceURI = ($eventhouseExists.properties.queryServiceUri).ToString()
} else {
    Write-Output "Eventhouse '$eventhouseName' does not exist in your workspace."
    Write-Output "Creating Eventhouse $eventhouseName"
    $eventhouseCreate = Invoke-RestMethod -Uri $eventhouseAPI -Method POST -Headers $fabricHeaders -Body $ehbody 
    $eventhouseId= ($eventhouseCreate.id).ToString()    
    $queryServiceURI = ($eventhouseCreate.properties.queryServiceUri).ToString()
}

# Create KQL Database in above Eventhouse
Write-Output "Creating KQL Database"
$kqlDBName = $databaseName

# Create body of request
$kqlbody = @{       
            'displayName' = $kqlDBName;
            'creationPayload'= @{
            'databaseType' = "ReadWrite";
            'parentEventhouseItemId' = $eventhouseId}
             } | ConvertTo-Json -Depth 2

$kqlDBAPI = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/kqlDatabases"

# Check if the kql db exists
$kqlDbExists = $response.value | Where-Object { $_.displayName -eq $kqlDBName }

if ($kqlDbExists) {
    Write-Output "KQL database '$kqlDBName' exists in your workspace."       
} else {
    Write-Output "KQL database '$kqlDBName' does not exist in your workspace."
    Write-Output "Creating database $kqlDBName"
    Invoke-RestMethod -Uri $kqlDBAPI -Method POST -Body $kqlbody -Headers $fabricHeaders -verbose   
}

# Get the schema from ADX
$cslQuery = ".show database schema as csl script"
$body = @{
    "db"  = $databaseName
    "csl" = $cslQuery
} | ConvertTo-Json

$adxResponse = Invoke-RestMethod -Uri "$ADXclusterUri/v1/rest/query" -Method Post -Headers $adxHeaders -Body $body
# Write-Output "Query response: $($response | ConvertTo-Json -Depth 10)"


# Authenticating to KQL DB data plane to avoid 401 unauthorized error
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    resource      = "https://api.kusto.windows.net"
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Body $body
$kustoToken = $tokenResponse.access_token

$kustoHeaders = @{
    "Authorization" = "Bearer $kustoToken"
    "Content-Type"  = "application/json"
}

# Add service principal as admin to kql database - Must be none manually for now this isn't working
# $addAdminQuery = ".add database $kqlDBName admins ('aadapp=$clientId')"

# $body = @{ 
#     "db"  = $kqlDBName
#     "csl" = $addAdminQuery
# } | ConvertTo-Json
# $response = Invoke-RestMethod -Uri "$queryServiceURI/v1/rest/mgmt" -Method POST -Headers $kustoHeaders -Body $body
# Write-Output "Added admin to target database: $($response | ConvertTo-Json -Depth 10)"

# Execute each row (query) individually
$adxResponse.Tables[0].Rows | ForEach-Object {
    $individualQuery = $_[0]
    $executeScript = $individualQuery

    # Construct the JSON for the execute body
    $executeBody = @{
        "db"  = $databaseName
        "csl" = $executeScript
    } | ConvertTo-Json 

    # Write-Output "Execute body: $executeBody"

    try {
        $executeResponse = Invoke-RestMethod -Uri "$queryServiceURI/v1/rest/mgmt" -Method Post -Headers $kustoHeaders -Body $executeBody
        Write-Output "Executed script: $individualQuery"
        Write-Output "Query response: $($executeResponse | ConvertTo-Json -Depth 10)"
    }
    catch {
        Write-Error "Failed to execute script: $individualQuery. Error: $_"
    }
}
     





