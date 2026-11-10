// ====
// Microsoft Foundry resource (kind AIServices, keyless) and project (basic agent setup), the two model
// deployments, and the two project connections the Bicep schema can express:
//   search       CognitiveSearch, Microsoft Entra ID (keyless), for the Exercise 1 knowledge tool
//   appinsights  Application Insights, which turns on agent tracing for the project
// The two MCP OAuth identity passthrough connections (servicedesk-read and servicedesk-write) are
// created after deployment by provisioning, because their OAuth client is the gateway app
// registration that provisioning creates inside the tenant.
// Model deployments are created one after the other: parallel deployments on one account fail with
// a conflict.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the Foundry resource (aif-msp-<DeploymentID>), also its custom subdomain.')
param accountName string

@description('Name of the Foundry project (proj-msp-<DeploymentID>).')
param projectName string

@description('Deployment name of the chat model.')
param chatDeploymentName string

@description('Chat model name.')
param chatModelName string

@description('Chat model version.')
param chatModelVersion string

@description('Chat model capacity in thousands of tokens per minute (Global Standard).')
param chatCapacity int

@description('Deployment name of the embedding model.')
param embeddingDeploymentName string

@description('Embedding model name.')
param embeddingModelName string

@description('Embedding model version.')
param embeddingModelVersion string

@description('Embedding model capacity in thousands of tokens per minute (Global Standard).')
param embeddingCapacity int

@description('Resource ID of the Azure AI Search service.')
param searchServiceId string

@description('Endpoint of the Azure AI Search service.')
param searchEndpoint string

@description('Name of the Azure AI Search project connection.')
param searchConnectionName string

@description('Name of the Application Insights resource.')
param appInsightsName string

@description('Name of the Application Insights project connection.')
param appInsightsConnectionName string

resource account 'Microsoft.CognitiveServices/accounts@2026-09-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2026-09-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectName
    description: 'Relecloud Managed Services support agent project (Agentic MSP Support Agent Guided Lab).'
  }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-09-01' = {
  parent: account
  name: chatDeploymentName
  dependsOn: [
    project
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-09-01' = {
  parent: account
  name: embeddingDeploymentName
  dependsOn: [
    chatDeployment
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-09-01' = {
  parent: project
  name: searchConnectionName
  dependsOn: [
    embeddingDeployment
  ]
  properties: {
    category: 'CognitiveSearch'
    target: searchEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchServiceId
      location: location
    }
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-09-01' = {
  parent: project
  name: appInsightsConnectionName
  dependsOn: [
    searchConnection
  ]
  properties: {
    category: 'AppInsights'
    target: appInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: appInsights.properties.ConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsights.id
    }
  }
}

output accountId string = account.id
output accountName string = account.name
output accountPrincipalId string = account.identity.principalId
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output chatDeploymentName string = chatDeployment.name
output embeddingDeploymentName string = embeddingDeployment.name
output searchConnectionName string = searchConnection.name
output appInsightsConnectionName string = appInsightsConnection.name
