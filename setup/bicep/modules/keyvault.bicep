// ====
// Key Vault (Azure RBAC only, control plane API 2026-02-01) with its audit log, the backend key that
// API Management sends to the MCP server, and the two workload identities that may read secrets.
//   mcp-backend-key         generated per deployment; read by API Management (named value) and by
//                           the MCP server at startup. After provisioning nobody else holds a role
//                           that reads values (id-prov's Secrets Officer role is provisioning-only).
//   purview-client-secret   written by provisioning (Purview integration app), read by the MCP server.
//   setup-bootstrap-secret  only when CloudLabs supplies a bootstrap service principal; provisioning
//                           reads it and its last step deletes it, so the secret never travels in userData.
// The participant holds Key Vault Reader (metadata only), assigned in roles.bicep.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the vault (kv-msp-<DeploymentID>-<suffix>).')
param name string

@description('Microsoft Entra tenant of the environment.')
param tenantId string

@description('Resource ID of the Log Analytics workspace that receives the AuditEvent log.')
param logAnalyticsId string

@description('Value of the mcp-backend-key secret.')
@secure()
param backendKey string

@description('Whether CloudLabs supplied a bootstrap service principal secret.')
param bootstrapSecretEnabled bool

@description('Secret of the bootstrap service principal, or empty.')
@secure()
param bootstrapSecret string

@description('Principal ID of the MCP server identity (id-mcp).')
param mcpPrincipalId string

@description('Principal ID of the API Management identity (id-apim).')
param apimPrincipalId string

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource backendKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: 'mcp-backend-key'
  properties: {
    value: backendKey
    contentType: 'Shared key that API Management sends to the MCP server as x-backend-key'
  }
}

resource bootstrapSecretValue 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (bootstrapSecretEnabled) {
  parent: vault
  name: 'setup-bootstrap-secret'
  properties: {
    value: bootstrapSecret
    contentType: 'CloudLabs bootstrap service principal secret; the last provisioning step deletes it'
  }
}

resource auditLog 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vault
  name: 'kv-audit-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}

resource mcpSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, mcpPrincipalId, keyVaultSecretsUserRoleId)
  properties: {
    description: 'MCP server reads mcp-backend-key and purview-client-secret at startup.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apimSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, apimPrincipalId, keyVaultSecretsUserRoleId)
  properties: {
    description: 'API Management reads mcp-backend-key for its Key Vault named value.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
#disable-next-line outputs-should-not-contain-secrets
output backendKeySecretUri string = '${vault.properties.vaultUri}secrets/${backendKeySecret.name}'
output apimRoleAssignmentId string = apimSecretsUser.id
output mcpRoleAssignmentId string = mcpSecretsUser.id
