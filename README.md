# Migrate ADX schema to Fabric RTI
This repo contains a PowerShell script to migrate the full schema from an ADX database to a Fabric RTI KQL database.

## Prerequisites
1.  [Create an Azure Service Principal](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal)
2.  In Entra, add API Permissions for the Power BI Service:
    - Workspace.ReadWrite.All
    - Eventhouse.ReadWrite.All
    - KQLDatabase.ReadWrite.All
4.  Give the service principal Reader access on the ADX Clusters that will be migrated.
5.  Add your service principal to a Security Group (no permissions need to be added to the group).
6.  In the Fabric admin portal, set the "Service Principals can use Fabric APIs" to enabled for specific security groups, and add the security group.
7.  Install the [Kusto .NET client libraries from PowerShell](https://learn.microsoft.com/en-us/kusto/api/powershell/powershell?view=microsoft-fabric&tabs=user).
8.  Update the powershell script to be able to find the Kusto .NET client libraries installed on your workstation.
9.  Update the powershell script with you client_id (service principal id), client-secret, and tenant_id.
10.  Provide the following variables:
    -  **$workspaceName** - the Fabric Workspace that will host your RTI Eventhouse
    -  **$eventhouseName** - the name of the Fabric Eventhouse that will host your KQL Database (if it doesn't exist the script will create it)
    -  **$ADXClusterUri** - the ClusterURI of the ADX instance to migrate
    -  **$databaseName** - the name of the ADX database to migrate (the same name will be used for your KQL Database)
    

