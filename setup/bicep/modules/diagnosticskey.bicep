// ====
// The lab VM's diagnostics key: the primary key of the API Management subscription lab-diagnostics,
// stored in Key Vault as apim-diagnostics-key. The provisioning identity (id-prov) can read this one
// secret and nothing else in the vault (Key Vault Secrets User at secret scope), so the readiness
// check can call the diagnostics API without any API Management right. The participant can read the
// same key with their own listSecrets right on the subscription, so this exposes nothing new; the
// diagnostics API carries no user and the MCP server refuses every write tool through it.
// ====

@description('Name of the Key Vault.')
param keyVaultName string

@description('Name of the API Management instance.')
param apimName string

@description('Name of the API Management subscription of the diagnostics product.')
param subscriptionName string

@description('Principal ID of the provisioning identity (id-prov).')
param provisioningPrincipalId string

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource diagnosticsSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' existing = {
  parent: apim
  name: subscriptionName
}

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource diagnosticsKey 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: 'apim-diagnostics-key'
  properties: {
    value: diagnosticsSubscription.listSecrets().primaryKey
    contentType: 'Subscription key of the API Management diagnostics product (lab VM only; no user context, writes refused)'
  }
}

resource provisioningSecretReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: diagnosticsKey
  name: guid(diagnosticsKey.id, provisioningPrincipalId, keyVaultSecretsUserRoleId)
  properties: {
    description: 'id-prov (permanent): the readiness check reads this one secret to call the diagnostics API.'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: provisioningPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output secretName string = diagnosticsKey.name
