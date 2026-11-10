// ====
// Azure AI Search (Basic) for the Exercise 1 knowledge index. Data-plane access is role-based only
// (API keys disabled), and the system-assigned identity reads the export container and calls the
// embedding deployment (roles in roles.bicep). Participants build the index, data source, skillset
// and indexer themselves in Exercise 1 Task 2; nothing else is created here.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the search service (srch-msp-<DeploymentID>).')
param name string

resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'
    disableLocalAuth: true
  }
}

output id string = search.id
output name string = search.name
output principalId string = search.identity.principalId
output endpoint string = 'https://${search.name}.search.windows.net'
