// ====
// Container Apps environment (workload profiles, Consumption profile only) and the MCP server app.
// Logs go through Azure Monitor: the environment's destination is azure-monitor and a diagnostic
// setting sends ContainerAppConsoleLogs and ContainerAppSystemLogs to Log Analytics (the
// log-analytics destination, which used the retired HTTP Data Collector API, is not used).
//
// The app starts with a Microsoft placeholder image on port 80. Provisioning builds the MCP server
// release in the registry and replaces the image, the port (8000), the /health probes and the
// post-deployment environment variables in one update, which becomes the baseline revision
// (revision suffix baseline-<time>). The environment variables below are the configuration contract
// with the MCP server (setup/README.md, "MCP server contract"); none of them is a secret.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the Container Apps environment (cae-msp-<DeploymentID>).')
param environmentName string

@description('Name of the MCP server Container App (ca-mcp-<DeploymentID>).')
param appName string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsId string

@description('Login server of the Container Registry.')
param registryLoginServer string

@description('Resource ID of the MCP server identity (id-mcp).')
param mcpIdentityId string

@description('Client ID of the MCP server identity (id-mcp).')
param mcpClientId string

@description('Key Vault URI that holds mcp-backend-key and purview-client-secret.')
param keyVaultUri string

@description('Dataverse environment URL that provisioning creates (corrected by provisioning if Power Platform assigns another one).')
param dataverseUrl string

@description('Microsoft Entra tenant of the environment.')
param tenantId string

@description('Name of the Foundry agent.')
param agentName string

@description('Golden Environment version recorded by the server.')
param goldenEnvironmentVersion string

@description('Display name of the sensitivity label whose documents the server never returns (provisioning adds the label ID).')
param restrictedLabelName string

resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource environmentLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: environment
  name: 'cae-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

var appHost = '${appName}.${environment.properties.defaultDomain}'

resource mcpApp 'Microsoft.App/containerApps@2026-07-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${mcpIdentityId}': {}
    }
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryLoginServer
          identity: mcpIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp-server'
          // Placeholder until provisioning deploys mcp-server:<release> from the lab registry.
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'DATA_BACKEND', value: 'dataverse' }
            { name: 'DATAVERSE_URL', value: dataverseUrl }
            { name: 'AZURE_CLIENT_ID', value: mcpClientId }
            { name: 'AZURE_TENANT_ID', value: tenantId }
            { name: 'KEY_VAULT_URL', value: keyVaultUri }
            { name: 'BACKEND_KEY_SECRET_NAME', value: 'mcp-backend-key' }
            { name: 'REQUIRE_BACKEND_KEY', value: 'true' }
            { name: 'DATAVERSE_IMPERSONATION', value: 'true' }
            { name: 'REQUIRE_USER_FOR_WRITES', value: 'true' }
            { name: 'AGENT_NAME', value: agentName }
            { name: 'AGENT_ID', value: '' }
            { name: 'PURVIEW_ENABLED', value: 'false' }
            { name: 'PURVIEW_TENANT_ID', value: tenantId }
            { name: 'PURVIEW_CLIENT_ID', value: '' }
            { name: 'PURVIEW_CLIENT_SECRET_NAME', value: 'purview-client-secret' }
            { name: 'PURVIEW_RESTRICTED_LABELS', value: restrictedLabelName }
            { name: 'MCP_ALLOWED_HOSTS', value: appHost }
            { name: 'MCP_STATELESS', value: 'true' }
            { name: 'MCP_READ_PATH', value: '/read/mcp' }
            { name: 'MCP_WRITE_PATH', value: '/write/mcp' }
            { name: 'MCP_DIAGNOSTICS_PATH', value: '/mcp' }
            { name: 'GOLDEN_ENVIRONMENT_VERSION', value: goldenEnvironmentVersion }
            { name: 'LOG_LEVEL', value: 'INFO' }
            { name: 'PORT', value: '8000' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output environmentId string = environment.id
output environmentDefaultDomain string = environment.properties.defaultDomain
output appId string = mcpApp.id
output appName string = mcpApp.name
output appHost string = appHost
output appUrl string = 'https://${appHost}'
