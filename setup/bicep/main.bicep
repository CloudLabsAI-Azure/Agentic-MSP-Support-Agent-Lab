// ====
// Agentic MSP Support Agent Guided Lab: one participant's environment (Golden Environment v1.0).
//
// CloudLabs deploys the compiled form of this file, setup/deploy-01.json, into a resource group of the
// participant's own Azure subscription, in the participant's own Microsoft Entra tenant
// (Dedicated Tenant). Build it with setup/bicep/Build-Template.ps1, which uses the Bicep version pinned
// in bicepconfig.json and fails when deploy-01.json is out of date. Never edit deploy-01.json by hand.
//
// What ARM creates here: the lab VM, Foundry resource and project with gpt-5.1 and
// text-embedding-3-small (Global Standard), the search and Application Insights project connections,
// Azure AI Search (Basic, role-based access only), the export storage account, API Management
// (Developer) with the read, write and diagnostics MCP APIs, the Container Apps environment and the MCP
// server app, Container Registry, Key Vault with its audit log, Log Analytics and Application Insights,
// three managed identities and every role assignment ARM can make.
// What provisioning creates afterwards, inside the tenant (setup/assets/labfiles/provision): the setup
// app, the gateway and Purview app registrations, the two MCP OAuth connections, the Purview label and
// policies, the managed developer environment with the Service Desk app and data, the search export,
// the MCP server image and the agent. Its last step removes the participant's Global Administrator
// role and the setup app's and id-prov's provisioning-only privileges.
// ====

targetScope = 'resourceGroup'

metadata lab = 'Agentic MSP Support Agent Guided Lab'
metadata goldenEnvironmentVersion = 'v1.0'
metadata source = 'setup/bicep/main.bicep, compiled by setup/bicep/Build-Template.ps1'

// ==== CloudLabs platform parameters (the standard eight)

@description('Local administrator of the lab VM. Parameters file: azureuser.')
param adminUsername string

@description('Lab VM password. Parameters file: GEN-PASSWORD.')
@secure()
param adminPassword string

@description('Participant (Senior Technician, the CloudLabs ODL user) UPN. Parameters file: GET-AZUSER-UPN.')
param AzureUserName string

@description('Participant credential. Parameters file: GET-AZUSER-PASSWORD. Used by provisioning only when no bootstrap service principal is supplied.')
@secure()
param AzurePassword string

@description('ODL instance ID for CloudLabs callbacks. Parameters file: GET-ODL-ID.')
param ODLID string

@description('Per-deployment unique suffix, the naming primitive. Parameters file: GET-DEPLOYMENT-ID.')
param DeploymentID string

@description('CloudLabs support shadow account on the lab VM. Parameters file: trainer.')
param trainerUserName string

@description('Support shadow account password. Parameters file: GEN-PASSWORD.')
@secure()
param trainerUserPassword string

// ==== Lab parameters

@description('Object ID of the participant, for direct role assignments. Parameters file: GET-AZUSER-OBJECTID.')
param azuserobjectid string

@description('Application ID of a per-tenant bootstrap service principal supplied by CloudLabs (GET-SERVICEPRINCIPAL-APPLICATION-ID), or empty. Preferred bootstrap: see setup/README.md.')
param bootstrapAppId string = ''

@description('Secret of that service principal (GET-SERVICEPRINCIPAL-SECRET), or empty. Stored only in Key Vault; the last provisioning step deletes it.')
@secure()
param bootstrapAppSecret string = ''

@description('Object ID of the CloudLabs validation service principal, or empty. Gets read-only data roles on search and storage.')
param validationPrincipalObjectId string = ''

@description('Redirect URL(s) of the Foundry OAuth connections, comma separated, when Foundry does not return them (pilot). Provisioning registers them on the gateway app.')
param oauthRedirectUris string = ''

@description('Power Platform region of the managed developer environment.')
param dataverseLocation string = 'canada'

@description('Host suffix of Dataverse URLs in that region.')
param dataverseUrlSuffix string = 'crm3.dynamics.com'

@description('gpt-5.1 Global Standard capacity, in thousands of tokens per minute.')
@minValue(10)
param chatModelCapacity int = 100

@description('text-embedding-3-small Global Standard capacity, in thousands of tokens per minute.')
@minValue(10)
param embeddingModelCapacity int = 150

@description('Refuse to remove the participant\'s Global Administrator role unless another user holds it (keeps the tenant manageable).')
param requireSupplierGlobalAdmin bool = true

@description('Foundry role of the Tier 1 Technician on the project. Foundry User is the pilot fallback for the portal playground.')
@allowed([
  'Foundry Agent Consumer'
  'Foundry User'
])
param tier1FoundryRole string = 'Foundry Agent Consumer'

@description('Pilot fallback: the Senior Technician also holds System Administrator in the Dataverse environment only.')
param seniorDataverseSystemAdministrator bool = false

@description('Also give the Foundry resource identity Search Service Contributor and Search Index Data Contributor (documented fallback).')
param foundrySearchFallbackRoles bool = false

@description('Do not set. Seeds the per-deployment backend key; secure so deployment history never shows it.')
@secure()
param mcpBackendKeySeed string = newGuid()

// ==== Names and constants

var location = resourceGroup().location
var did = DeploymentID
var uniq = take(uniqueString(resourceGroup().id), 4)
var goldenEnvironmentVersion = 'v1.0'
var tenantId = tenant().tenantId
var tenantDomain = last(split(AzureUserName, '@'))

var names = {
  vm: 'labvm-${did}'
  nsg: 'labvm-${did}-nsg'
  vnet: 'labvm-${did}-vnet'
  nic: 'labvm-${did}-nic'
  publicIp: 'labvmip${uniqueString(resourceGroup().id)}'
  foundry: 'aif-msp-${did}'
  project: 'proj-msp-${did}'
  search: 'srch-msp-${did}'
  storage: 'stmsp${did}${uniq}'
  apim: 'apim-msp-${did}'
  environment: 'cae-msp-${did}'
  app: 'ca-mcp-${did}'
  registry: 'acrmsp${did}${uniq}'
  keyVault: 'kv-msp-${did}-${uniq}'
  logAnalytics: 'log-msp-${did}'
  appInsights: 'appi-msp-${did}'
  mcpIdentity: 'id-mcp-${did}'
  provisioningIdentity: 'id-prov-${did}'
  apimIdentity: 'id-apim-${did}'
}

var agentName = 'msp-support-agent'
var chatDeploymentName = 'gpt-5.1'
var embeddingDeploymentName = 'text-embedding-3-small'
var exportContainerName = 'servicedesk-export'
var exportMetaContainerName = 'servicedesk-export-meta'
var readConnectionName = 'servicedesk-read'
var writeConnectionName = 'servicedesk-write'
var gatewayScope = 'ServiceDesk.Access'
var gatewayAudience = 'https://${tenantDomain}/servicedesk-mcp'
var restrictedLabelName = 'Relecloud Confidential'
var dataverseDomain = 'mspdesk${did}'
var dataverseUrl = 'https://${dataverseDomain}.${dataverseUrlSuffix}'
var serviceDeskAppUrl = '${dataverseUrl}/main.aspx?appname=spk_ServiceDesk'
var tier1Upn = 'tier1.technician@${tenantDomain}'

var bootstrapAppIdValue = startsWith(bootstrapAppId, 'GET-') ? '' : bootstrapAppId
var bootstrapSecretEnabled = !empty(bootstrapAppIdValue) && !empty(bootstrapAppSecret) && !startsWith(bootstrapAppSecret, 'GET-')
var validationPrincipalId = startsWith(validationPrincipalObjectId, 'GET-') ? '' : validationPrincipalObjectId
var backendKey = '${uniqueString(mcpBackendKeySeed, 'a')}${uniqueString(mcpBackendKeySeed, 'b')}${uniqueString(mcpBackendKeySeed, 'c')}'

var tags = {
  lab: 'agentic-msp-support-agent'
  'golden-environment': goldenEnvironmentVersion
  'deployment-id': did
}

// Golden Environment facts that the validation steps read from the resource group's tags. They must
// equal the seed manifest (searchable_documents.total and new_incidents) and the MCP server release in
// LabConfig.psd1; the readiness check compares them and reports any difference.
var validationTags = {
  'lab-golden-environment': goldenEnvironmentVersion
  'lab-searchable-documents': '753'
  'lab-new-incident-1': 'TCK-10561'
  'lab-new-incident-2': 'TCK-10562'
  'lab-mcp-release': '3.0.0'
}

// ==== Resource group tags: merged with the tags the resource group already has (CloudLabs adds its own),
// because a tags resource replaces the whole set.
resource resourceGroupTags 'Microsoft.Resources/tags@2024-03-01' = {
  name: 'default'
  properties: {
    tags: union(resourceGroup().?tags ?? {}, validationTags)
  }
}

// ==== Shared services

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
  }
}

module identities 'modules/identities.bicep' = {
  name: 'identities'
  params: {
    location: location
    tags: tags
    mcpIdentityName: names.mcpIdentity
    provisioningIdentityName: names.provisioningIdentity
    apimIdentityName: names.apimIdentity
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    tags: tags
    name: names.keyVault
    tenantId: tenantId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    backendKey: backendKey
    bootstrapSecretEnabled: bootstrapSecretEnabled
    bootstrapSecret: bootstrapAppSecret
    mcpPrincipalId: identities.outputs.mcpPrincipalId
    apimPrincipalId: identities.outputs.apimPrincipalId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    tags: tags
    name: names.storage
    exportContainerName: exportContainerName
    metaContainerName: exportMetaContainerName
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    location: location
    tags: tags
    name: names.registry
    mcpPrincipalId: identities.outputs.mcpPrincipalId
  }
}

module search 'modules/search.bicep' = {
  name: 'search'
  params: {
    location: location
    tags: tags
    name: names.search
  }
}

module foundry 'modules/foundry.bicep' = {
  name: 'foundry'
  params: {
    location: location
    tags: tags
    accountName: names.foundry
    projectName: names.project
    chatDeploymentName: chatDeploymentName
    chatModelName: 'gpt-5.1'
    chatModelVersion: '2025-11-13'
    chatCapacity: chatModelCapacity
    embeddingDeploymentName: embeddingDeploymentName
    embeddingModelName: 'text-embedding-3-small'
    embeddingModelVersion: '1'
    embeddingCapacity: embeddingModelCapacity
    searchServiceId: search.outputs.id
    searchEndpoint: search.outputs.endpoint
    searchConnectionName: 'search'
    appInsightsName: monitoring.outputs.appInsightsName
    appInsightsConnectionName: 'appinsights'
  }
}

module containerApps 'modules/containerapps.bicep' = {
  name: 'containerapps'
  params: {
    location: location
    tags: tags
    environmentName: names.environment
    appName: names.app
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    registryLoginServer: registry.outputs.loginServer
    mcpIdentityId: identities.outputs.mcpIdentityId
    mcpClientId: identities.outputs.mcpClientId
    keyVaultUri: keyVault.outputs.uri
    dataverseUrl: dataverseUrl
    tenantId: tenantId
    agentName: agentName
    goldenEnvironmentVersion: goldenEnvironmentVersion
    restrictedLabelName: restrictedLabelName
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    location: location
    tags: tags
    name: names.apim
    apimIdentityId: identities.outputs.apimIdentityId
    apimClientId: identities.outputs.apimClientId
    backendKeySecretUri: keyVault.outputs.backendKeySecretUri
    tenantId: tenantId
    gatewayAudience: gatewayAudience
    gatewayScope: gatewayScope
    backendBaseUrl: containerApps.outputs.appUrl
    logAnalyticsId: monitoring.outputs.logAnalyticsId
  }
}

module roles 'modules/roles.bicep' = {
  name: 'roles'
  params: {
    seniorPrincipalId: azuserobjectid
    provisioningPrincipalId: identities.outputs.provisioningPrincipalId
    searchPrincipalId: search.outputs.principalId
    projectPrincipalId: foundry.outputs.projectPrincipalId
    accountPrincipalId: foundry.outputs.accountPrincipalId
    validationPrincipalId: validationPrincipalId
    foundrySearchFallbackRoles: foundrySearchFallbackRoles
    storageAccountName: storage.outputs.name
    searchServiceName: search.outputs.name
    foundryAccountName: foundry.outputs.accountName
    foundryProjectName: foundry.outputs.projectName
    registryName: registry.outputs.name
    containerAppName: containerApps.outputs.appName
    mcpIdentityName: identities.outputs.mcpIdentityName
    keyVaultName: keyVault.outputs.name
    logAnalyticsName: monitoring.outputs.logAnalyticsName
    apimName: apim.outputs.name
  }
}

module diagnosticsKey 'modules/diagnosticskey.bicep' = {
  name: 'diagnosticskey'
  params: {
    keyVaultName: keyVault.outputs.name
    apimName: apim.outputs.name
    subscriptionName: apim.outputs.diagnosticsSubscriptionName
    provisioningPrincipalId: identities.outputs.provisioningPrincipalId
  }
}

// ==== Lab VM: created last, so its first-boot provisioning finds every resource and role in place

// The CloudLabs template library blob (a published path: never rename the project folder or script).
var scriptUrl = 'https://experienceazure.blob.${environment().suffixes.storage}/templates/agentic-msp-support-agent/scripts/psscript-01.ps1'
var arg1 = ' -AzureUserName ${AzureUserName} -AzurePassword ${AzurePassword}'
var arg2 = ' -AzureTenantID ${tenantId} -AzureSubscriptionID ${subscription().subscriptionId}'
var arg3 = ' -ODLID ${ODLID} -DeploymentID ${DeploymentID}'
var arg4 = ' -vmAdminUsername ${adminUsername} -vmAdminPassword ${adminPassword}'
var arg5 = ' -trainerUserName ${trainerUserName} -trainerUserPassword ${trainerUserPassword}'
var arg6 = ' -ProvisioningIdentityClientId ${identities.outputs.provisioningClientId}'
var userDataPointer = '$url = "${scriptUrl}"; $arg = "${arg1}${arg2}${arg3}${arg4}${arg5}${arg6}"'

var vmTags = {
  'msplab-golden-version': goldenEnvironmentVersion
  'msplab-provisioning-client-id': identities.outputs.provisioningClientId
  'msplab-senior-oid': azuserobjectid
  'msplab-tier1-upn': tier1Upn
  'msplab-tier1-foundry-role': tier1FoundryRole
  'msplab-bootstrap-app-id': bootstrapAppIdValue
  'msplab-bootstrap-secret': bootstrapSecretEnabled ? 'key-vault' : 'none'
  'msplab-dataverse-location': dataverseLocation
  'msplab-dataverse-domain': dataverseDomain
  'msplab-dataverse-url': dataverseUrl
  'msplab-oauth-redirect-uris': oauthRedirectUris
  'msplab-require-supplier-ga': requireSupplierGlobalAdmin ? 'true' : 'false'
  'msplab-senior-dataverse-sysadmin': seniorDataverseSystemAdministrator ? 'true' : 'false'
}

module labVm 'modules/labvm.bicep' = {
  name: 'labvm'
  dependsOn: [
    roles
    foundry
    apim
    diagnosticsKey
  ]
  params: {
    location: location
    tags: tags
    vmTags: vmTags
    vmName: names.vm
    nsgName: names.nsg
    vnetName: names.vnet
    nicName: names.nic
    publicIpName: names.publicIp
    vmSize: 'Standard_D2s_v5'
    adminUsername: adminUsername
    adminPassword: adminPassword
    userData: base64(userDataPointer)
    provisioningIdentityId: identities.outputs.provisioningIdentityId
  }
}

// ==== Outputs: the Environment tab fields and the guide's inject keys (BUILD-SPEC 3.2). Never rename.
// Bicep identifiers cannot contain spaces, so every underscore below stands for a space:
// Build-Template.ps1 renames the outputs of the compiled template (Resource_Group_Name becomes
// Resource Group Name) and checks the result against the BUILD-SPEC list before it writes
// deploy-01.json. Hide Trainer Username and Trainer Password with Excluding Output Parameters.

output DeploymentID string = DeploymentID
output Region string = location
output Resource_Group_Name string = resourceGroup().name
output LabVM_DNS_Name string = labVm.outputs.dnsName
output LabVM_Admin_Username string = adminUsername
output LabVM_Admin_Password string = adminPassword
output Trainer_Username string = trainerUserName
output Trainer_Password string = trainerUserPassword
output Foundry_Resource_Name string = foundry.outputs.accountName
output Foundry_Project_Name string = foundry.outputs.projectName
output Foundry_Project_Endpoint string = foundry.outputs.projectEndpoint
output Chat_Model_Deployment string = foundry.outputs.chatDeploymentName
output Embedding_Model_Deployment string = foundry.outputs.embeddingDeploymentName
output Agent_Name string = agentName
output AI_Search_Service_Name string = search.outputs.name
output AI_Search_Endpoint string = search.outputs.endpoint
output Storage_Account_Name string = storage.outputs.name
output Export_Container string = exportContainerName
output API_Management_Name string = apim.outputs.name
output MCP_Read_Gateway_URL string = '${apim.outputs.gatewayUrl}/servicedesk-read/mcp'
output MCP_Write_Gateway_URL string = '${apim.outputs.gatewayUrl}/servicedesk-write/mcp'
output MCP_Diagnostics_URL string = '${apim.outputs.gatewayUrl}/servicedesk-diag/mcp'
output MCP_Gateway_Audience string = gatewayAudience
output MCP_Read_Connection string = readConnectionName
output MCP_Write_Connection string = writeConnectionName
output MCP_Server_URL string = containerApps.outputs.appUrl
output Container_App_Name string = containerApps.outputs.appName
output Container_Registry_Name string = registry.outputs.name
output Key_Vault_Name string = keyVault.outputs.name
output Key_Vault_URL string = keyVault.outputs.uri
output Log_Analytics_Workspace string = monitoring.outputs.logAnalyticsName
output Application_Insights_Name string = monitoring.outputs.appInsightsName
output MCP_Backend_Identity_Name string = identities.outputs.mcpIdentityName
output MCP_Backend_Identity_Client_ID string = identities.outputs.mcpClientId
output Dataverse_Environment_URL string = dataverseUrl
output Service_Desk_App_URL string = serviceDeskAppUrl
output Tier_1_Technician_Username string = tier1Upn
output Golden_Environment_Version string = goldenEnvironmentVersion
