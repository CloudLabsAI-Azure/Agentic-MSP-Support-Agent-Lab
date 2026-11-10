// ====
// Azure role assignments that ARM can make (BUILD-SPEC 3.1). All are direct assignments, never
// through groups. Assignments that need a principal created after deployment are made by
// provisioning: the Tier 1 Technician's Foundry role (through id-prov's conditional role below).
// The Key Vault Secrets User roles of id-mcp and id-apim live in keyvault.bicep and the AcrPull role
// of id-mcp in registry.bicep, because API Management and the Container App depend on them.
//
// id-prov (the lab VM's identity) holds two sets of roles:
//   permanent          the same reads and redeploy rights the participant holds, used by the
//                      readiness check and support re-runs
//   provisioning-only  API Management Service Contributor, Key Vault Secrets Officer, Storage Blob
//                      Data Contributor, Foundry Project Manager and a conditional Role Based Access
//                      Control Administrator. The last step of provisioning deletes all five, so any
//                      process on the VM can never do more than the participant can.
// The conditional role allows id-prov to grant only Foundry Agent Consumer or Foundry User, only to
// users, and to delete only those user assignments and its own provisioning-only assignments.
// ====

@description('Principal ID of the participant (Senior Technician, the CloudLabs ODL user).')
param seniorPrincipalId string

@description('Principal ID of the provisioning identity (id-prov).')
param provisioningPrincipalId string

@description('Principal ID of the search service system identity.')
param searchPrincipalId string

@description('Principal ID of the Foundry project system identity.')
param projectPrincipalId string

@description('Principal ID of the Foundry resource system identity.')
param accountPrincipalId string

@description('Object ID of the CloudLabs validation service principal, or empty.')
param validationPrincipalId string

@description('Also give the Foundry resource identity Search Service Contributor and Search Index Data Contributor (documented fallback for the keyless search tool).')
param foundrySearchFallbackRoles bool

param storageAccountName string
param searchServiceName string
param foundryAccountName string
param foundryProjectName string
param registryName string
param containerAppName string
param mcpIdentityName string
param keyVaultName string
param logAnalyticsName string
param apimName string

var roleIds = {
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
  registryTasksContributor: 'fb382eab-e894-4461-af04-94435c366c3f'
  keyVaultReader: '21090545-7ca7-4776-b22c-e363652d74d2'
  keyVaultSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  cognitiveServicesOpenAIUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  foundryUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
  foundryProjectManager: 'eadc314b-1a2d-4efa-be10-5d325db5065e'
  foundryAgentConsumer: 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6'
  logAnalyticsReader: '73c42c96-874c-492b-b04d-ab87d138a893'
  containerAppsContributor: '358470bc-b998-42bd-ab17-a7e34c199c0f'
  managedIdentityOperator: 'f1a07417-d97a-45cb-824c-7a7467783830'
  apiManagementServiceContributor: '312a565d-c81f-4fd8-895a-4e21e48d571c'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  rbacAdministrator: 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
}

var validationEnabled = !empty(validationPrincipalId)

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource searchService 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: searchServiceName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-09-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2026-09-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' existing = {
  name: registryName
}

resource containerApp 'Microsoft.App/containerApps@2026-07-01' existing = {
  name: containerAppName
}

resource mcpIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: mcpIdentityName
}

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsName
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// ==== Storage account

var storageRoles = concat([
  { principalId: searchPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.storageBlobDataReader, description: 'Search indexer reads the export container.' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.storageBlobDataReader, description: 'id-prov (permanent): readiness check reads the export manifest.' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.storageBlobDataContributor, description: 'id-prov (provisioning only, removed at the end): writes the search export.' }
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.reader, description: 'Senior Technician: sees the storage account.' }
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.storageBlobDataReader, description: 'Senior Technician: reviews the exported documents.' }
], validationEnabled ? [
  { principalId: validationPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.storageBlobDataReader, description: 'CloudLabs validation: reads the export manifest and the consistency report.' }
] : [])

resource storageAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in storageRoles: {
  scope: storageAccount
  name: guid(storageAccount.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

// ==== Azure AI Search

var searchRoles = concat([
  { principalId: projectPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.searchIndexDataReader, description: 'Foundry project identity: the agent queries the knowledge index.' }
  { principalId: accountPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.searchIndexDataReader, description: 'Foundry resource identity: keyless search tool (pilot keeps whichever identity works).' }
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.searchServiceContributor, description: 'Senior Technician: creates the index, data source, skillset and indexer (Exercise 1).' }
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.searchIndexDataReader, description: 'Senior Technician: queries the index in Search explorer.' }
], foundrySearchFallbackRoles ? [
  { principalId: accountPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.searchServiceContributor, description: 'Fallback: Foundry resource identity as documented on the search tool page.' }
  { principalId: accountPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.searchIndexDataContributor, description: 'Fallback: Foundry resource identity as documented on the search tool page.' }
] : [], validationEnabled ? [
  { principalId: validationPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.searchIndexDataReader, description: 'CloudLabs validation: counts the index documents (the service accepts no API keys).' }
] : [])

resource searchAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in searchRoles: {
  scope: searchService
  name: guid(searchService.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

// ==== Foundry resource and project

var accountRoles = [
  { principalId: searchPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.cognitiveServicesOpenAIUser, description: 'Search skillset and vectorizer call the embedding deployment.' }
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.reader, description: 'Senior Technician: sees the Foundry resource and its deployments.' }
]

resource accountAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in accountRoles: {
  scope: foundryAccount
  name: guid(foundryAccount.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

var projectRoles = [
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.foundryUser, description: 'Senior Technician: builds and runs the agent in the project.' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.foundryUser, description: 'id-prov (permanent): creates the agent and reads it for the readiness check.' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.foundryProjectManager, description: 'id-prov (provisioning only, removed at the end): creates the MCP connections.' }
]

resource projectAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in projectRoles: {
  scope: foundryProject
  name: guid(foundryProject.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

// ==== Container Registry, Container App and the MCP server identity (redeploy rights)

var registryRoles = [
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.registryTasksContributor, description: 'id-prov (permanent): builds the MCP server image with ACR Tasks.' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.acrPush, description: 'id-prov (permanent): pushes the MCP server image.' }
]

resource registryAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in registryRoles: {
  scope: registry
  name: guid(registry.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

resource containerAppAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerApp
  name: guid(containerApp.id, provisioningPrincipalId, roleIds.containerAppsContributor)
  properties: {
    description: 'id-prov (permanent): deploys the MCP server revision.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.containerAppsContributor)
    principalId: provisioningPrincipalId
    principalType: 'ServicePrincipal'
  }
}

var mcpIdentityRoles = [
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.managedIdentityOperator, description: 'id-prov (permanent): updates the Container App, which uses id-mcp.' }
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.managedIdentityOperator, description: 'Senior Technician: redeploys the Container App, which uses id-mcp (Exercises 3 and 4).' }
]

resource mcpIdentityAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in mcpIdentityRoles: {
  scope: mcpIdentity
  name: guid(mcpIdentity.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

// ==== Key Vault (metadata reads; secret values only through managed identities)

var keyVaultRoles = [
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.keyVaultReader, description: 'Senior Technician: sees that the secrets exist, never their values (Exercise 5).' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.keyVaultReader, description: 'id-prov (permanent): readiness check confirms the secrets exist.' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.keyVaultSecretsOfficer, description: 'id-prov (provisioning only, removed at the end): stores the Purview client secret and deletes the bootstrap secret.' }
]

resource keyVaultAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in keyVaultRoles: {
  scope: keyVault
  name: guid(keyVault.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

// ==== Log Analytics

var workspaceRoles = [
  { principalId: seniorPrincipalId, principalType: 'User', roleId: roleIds.logAnalyticsReader, description: 'Senior Technician: queries the correlated logs (Exercises 5 to 7).' }
  { principalId: provisioningPrincipalId, principalType: 'ServicePrincipal', roleId: roleIds.logAnalyticsReader, description: 'id-prov (permanent): support checks of the logs.' }
]

resource workspaceAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for item in workspaceRoles: {
  scope: logAnalytics
  name: guid(logAnalytics.id, item.principalId, item.roleId)
  properties: {
    description: item.description
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', item.roleId)
    principalId: item.principalId
    principalType: item.principalType
  }
}]

// ==== API Management (provisioning only: named values set after the tenant objects exist)

resource apimAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: apim
  name: guid(apim.id, provisioningPrincipalId, roleIds.apiManagementServiceContributor)
  properties: {
    description: 'id-prov (provisioning only, removed at the end): sets the mcp-gateway-app-id and agent-id named values.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.apiManagementServiceContributor)
    principalId: provisioningPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ==== Resource group

resource provisioningReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, provisioningPrincipalId, roleIds.reader)
  properties: {
    description: 'id-prov (permanent): readiness check reads every resource of the environment.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.reader)
    principalId: provisioningPrincipalId
    principalType: 'ServicePrincipal'
  }
}

var assignableRoles = '${roleIds.foundryAgentConsumer}, ${roleIds.foundryUser}'
var provisioningOnlyRoles = '${roleIds.apiManagementServiceContributor}, ${roleIds.keyVaultSecretsOfficer}, ${roleIds.storageBlobDataContributor}, ${roleIds.foundryProjectManager}, ${roleIds.rbacAdministrator}'
var writeCondition = '((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/write\'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${assignableRoles}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {\'User\'}))'
var deleteCondition = '((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/delete\'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${assignableRoles}} AND @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {\'User\'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${provisioningOnlyRoles}} AND @Resource[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {${provisioningPrincipalId}}))'

resource provisioningRoleAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, provisioningPrincipalId, roleIds.rbacAdministrator)
  properties: {
    description: 'id-prov (provisioning only, removed at the end): grants the Tier 1 Technician its Foundry role and removes its own provisioning-only roles.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.rbacAdministrator)
    principalId: provisioningPrincipalId
    principalType: 'ServicePrincipal'
    condition: '${writeCondition} AND ${deleteCondition}'
    conditionVersion: '2.0'
  }
}

output provisioningOnlyRoleIds array = [
  roleIds.apiManagementServiceContributor
  roleIds.keyVaultSecretsOfficer
  roleIds.storageBlobDataContributor
  roleIds.foundryProjectManager
  roleIds.rbacAdministrator
]
