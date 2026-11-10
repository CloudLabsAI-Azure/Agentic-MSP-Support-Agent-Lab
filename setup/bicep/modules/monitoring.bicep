// ====
// Log Analytics workspace and workspace-based Application Insights.
// Every log of the environment lands in the one workspace: API Management resource logs, Container
// Apps console and system logs (the MCP server's tool invocation log), Key Vault audit events, and
// the agent traces that the Foundry project sends to Application Insights.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the Log Analytics workspace (log-msp-<DeploymentID>).')
param logAnalyticsName string

@description('Name of the Application Insights resource (appi-msp-<DeploymentID>).')
param appInsightsName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
  }
}

output logAnalyticsId string = logAnalytics.id
output logAnalyticsName string = logAnalytics.name
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
