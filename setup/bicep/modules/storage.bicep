// ====
// Storage account for the search export (BUILD-SPEC 3.7). Shared key access is off from creation, so
// only Microsoft Entra identities with a data role can read or write blobs:
//   servicedesk-export       one JSON file per searchable document; the Exercise 1 indexer reads it
//                            with the search service's system identity (Storage Blob Data Reader)
//   servicedesk-export-meta  export-manifest.json and the provisioning consistency report, kept out of
//                            the indexed container
// Public network access stays on (Entra-only authorization) so the lab VM and the indexer reach it.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the storage account (stmsp<DeploymentID><suffix>).')
param name string

@description('Name of the indexed export container.')
param exportContainerName string

@description('Name of the container for the export manifest and reports.')
param metaContainerName string

resource account 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: account
  name: 'default'
}

resource exportContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: exportContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource metaContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: metaContainerName
  properties: {
    publicAccess: 'None'
  }
}

output id string = account.id
output name string = account.name
output blobEndpoint string = account.properties.primaryEndpoints.blob
output exportContainerId string = exportContainer.id
output metaContainerId string = metaContainer.id
