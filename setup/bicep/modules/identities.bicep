// ====
// User-assigned managed identities of the environment.
//   id-mcp-<DID>   the MCP server (Container App): reads its secrets from Key Vault, pulls its image,
//                  and is the Dataverse application user that acts on behalf of the signed-in user.
//   id-prov-<DID>  the lab VM: runs provisioning and the readiness check. Its provisioning-only roles
//                  are removed by provisioning itself at the end (setup/bicep/modules/roles.bicep).
//   id-apim-<DID>  API Management: reads the backend key for the mcp-backend-key named value. A
//                  user-assigned identity is used so its Key Vault role exists long before the
//                  30 to 40-minute gateway creation ends; a system-assigned identity's role could
//                  only be created after it and would race the named value.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the MCP server identity (id-mcp-<DeploymentID>).')
param mcpIdentityName string

@description('Name of the provisioning identity (id-prov-<DeploymentID>).')
param provisioningIdentityName string

@description('Name of the API Management identity (id-apim-<DeploymentID>).')
param apimIdentityName string

resource mcpIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: mcpIdentityName
  location: location
  tags: union(tags, { purpose: 'MCP server: Key Vault reader, image pull, Dataverse application user' })
}

resource provisioningIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: provisioningIdentityName
  location: location
  tags: union(tags, { purpose: 'Lab VM: provisioning and readiness check; provisioning-only roles are removed when provisioning ends' })
}

resource apimIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: apimIdentityName
  location: location
  tags: union(tags, { purpose: 'API Management: reads the mcp-backend-key secret for its Key Vault named value' })
}

output mcpIdentityId string = mcpIdentity.id
output mcpIdentityName string = mcpIdentity.name
output mcpPrincipalId string = mcpIdentity.properties.principalId
output mcpClientId string = mcpIdentity.properties.clientId
output provisioningIdentityId string = provisioningIdentity.id
output provisioningPrincipalId string = provisioningIdentity.properties.principalId
output provisioningClientId string = provisioningIdentity.properties.clientId
output apimIdentityId string = apimIdentity.id
output apimPrincipalId string = apimIdentity.properties.principalId
output apimClientId string = apimIdentity.properties.clientId
