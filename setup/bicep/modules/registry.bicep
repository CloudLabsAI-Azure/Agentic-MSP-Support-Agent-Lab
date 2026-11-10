// ====
// Container Registry (Basic) that holds the MCP server images. ACR Tasks builds every image in Azure,
// so the lab VM needs no container engine. The role assignment mode is set explicitly to the RBAC
// registry permissions mode (AcrPull, AcrPush, Container Registry Tasks Contributor), so a future
// change of the service default to the ABAC mode cannot silently break image pulls and quick builds.
// That property exists only in preview API versions; the value is the one the Azure CLI's registry
// models use (LegacyRegistryPermissions).
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the registry (acrmsp<DeploymentID><suffix>).')
param name string

@description('Principal ID of the MCP server identity (id-mcp), which pulls the image.')
param mcpPrincipalId string

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
    roleAssignmentMode: 'LegacyRegistryPermissions'
  }
}

resource mcpPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, mcpPrincipalId, acrPullRoleId)
  properties: {
    description: 'MCP server Container App pulls its image with its managed identity.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output id string = registry.id
output name string = registry.name
output loginServer string = registry.properties.loginServer
output pullRoleAssignmentId string = mcpPull.id
