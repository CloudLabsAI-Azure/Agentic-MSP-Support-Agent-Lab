// ====
// API Management (Developer tier, 30 to 40 minutes to create) in front of the MCP server.
//   servicedesk-read   /servicedesk-read/mcp  -> <app>/read/mcp   user token required, read tools
//   servicedesk-write  /servicedesk-write/mcp -> <app>/write/mcp  user token required, write tools
//   servicedesk-diag   /servicedesk-diag/mcp  -> <app>/mcp        subscription key (lab VM), no user
// The policies are the files in setup/apim, loaded verbatim. MCP APIs exist only in the preview API
// version 2025-09-01-preview; pin it and re-test before each workshop.
// Named values set to a placeholder here are filled by provisioning once the objects exist in the
// tenant: mcp-gateway-app-id (gateway app registration) and agent-id (the agent's Entra Agent ID).
// Until then the placeholder app ID makes the token check refuse every call (safe by default).
// Resource logs go to Log Analytics (resource-specific tables), and the Azure Monitor diagnostic
// logs the x-correlation-id request and response headers, never a body.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Name of the API Management instance (apim-msp-<DeploymentID>).')
param name string

@description('Resource ID of the API Management identity (id-apim).')
param apimIdentityId string

@description('Client ID of the API Management identity (id-apim).')
param apimClientId string

@description('Versionless identifier of the mcp-backend-key secret.')
param backendKeySecretUri string

@description('Microsoft Entra tenant whose tokens the gateway accepts.')
param tenantId string

@description('Application ID URI of the gateway app registration (deterministic, set by provisioning on the app).')
param gatewayAudience string

@description('Delegated scope the gateway requires.')
param gatewayScope string

@description('Base URL of the MCP server Container App.')
param backendBaseUrl string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsId string

var placeholderAppId = '00000000-0000-0000-0000-000000000000'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${apimIdentityId}': {}
    }
  }
  properties: {
    publisherEmail: 'noreply@relecloud.example'
    publisherName: 'Relecloud Managed Services'
  }
}

// ==== Named values

resource tenantIdValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'tenant-id'
  properties: {
    displayName: 'tenant-id'
    value: tenantId
    secret: false
  }
}

resource gatewayAppIdValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'mcp-gateway-app-id'
  properties: {
    displayName: 'mcp-gateway-app-id'
    value: placeholderAppId
    secret: false
    tags: [
      'set-by-provisioning'
    ]
  }
}

resource gatewayAudienceValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'mcp-gateway-audience'
  properties: {
    displayName: 'mcp-gateway-audience'
    value: gatewayAudience
    secret: false
  }
}

resource gatewayScopeValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'mcp-gateway-scope'
  properties: {
    displayName: 'mcp-gateway-scope'
    value: gatewayScope
    secret: false
  }
}

resource agentIdValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'agent-id'
  properties: {
    displayName: 'agent-id'
    value: 'not-set'
    secret: false
    tags: [
      'set-by-provisioning'
    ]
  }
}

resource backendKeyValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'mcp-backend-key'
  properties: {
    displayName: 'mcp-backend-key'
    secret: true
    keyVault: {
      secretIdentifier: backendKeySecretUri
      identityClientId: apimClientId
    }
  }
}

// ==== Gateway request logs: correlation header only, no bodies (bodies would break MCP streaming)

resource azureMonitorLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'azuremonitor'
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: true
  }
}

resource azureMonitorDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'azuremonitor'
  properties: {
    loggerId: azureMonitorLogger.id
    alwaysLog: 'allErrors'
    verbosity: 'information'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: [
          'x-correlation-id'
        ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: [
          'x-correlation-id'
        ]
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: [
          'x-correlation-id'
          'x-gateway-api'
        ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
  }
}

resource gatewayLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: apim
  name: 'apim-to-log-analytics'
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

// ==== MCP APIs and their policies

resource readApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'servicedesk-read'
  properties: {
    type: 'mcp'
    displayName: 'Service Desk MCP (read)'
    description: 'Read tools of the Relecloud Service Desk MCP server for the agent. Accepts only a signed-in technician\'s token for the gateway audience with the ServiceDesk.Access scope.'
    path: 'servicedesk-read'
    protocols: [
      'https'
    ]
    serviceUrl: '${backendBaseUrl}/read'
    subscriptionRequired: false
    mcpProperties: {
      transportType: 'streamable'
      endpoints: [
        {
          name: 'message'
          uriTemplate: '/mcp'
        }
      ]
    }
  }
}

resource writeApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'servicedesk-write'
  properties: {
    type: 'mcp'
    displayName: 'Service Desk MCP (write)'
    description: 'Controlled write tools of the Relecloud Service Desk MCP server for the agent. Accepts only a signed-in technician\'s token for the gateway audience with the ServiceDesk.Access scope; every call also needs the user\'s approval in the agent chat.'
    path: 'servicedesk-write'
    protocols: [
      'https'
    ]
    serviceUrl: '${backendBaseUrl}/write'
    subscriptionRequired: false
    mcpProperties: {
      transportType: 'streamable'
      endpoints: [
        {
          name: 'message'
          uriTemplate: '/mcp'
        }
      ]
    }
  }
}

resource diagApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'servicedesk-diag'
  properties: {
    type: 'mcp'
    displayName: 'Service Desk MCP (diagnostics)'
    description: 'Diagnostics access to every tool from the lab VM with the lab-diagnostics subscription key. Carries no signed-in user, so the server refuses every write tool called through it.'
    path: 'servicedesk-diag'
    protocols: [
      'https'
    ]
    serviceUrl: backendBaseUrl
    subscriptionRequired: true
    mcpProperties: {
      transportType: 'streamable'
      endpoints: [
        {
          name: 'message'
          uriTemplate: '/mcp'
        }
      ]
    }
  }
}

resource readPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: readApi
  name: 'policy'
  dependsOn: [
    tenantIdValue
    gatewayAppIdValue
    gatewayAudienceValue
    gatewayScopeValue
    agentIdValue
    backendKeyValue
  ]
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/servicedesk-read.policy.xml')
  }
}

resource writePolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: writeApi
  name: 'policy'
  dependsOn: [
    tenantIdValue
    gatewayAppIdValue
    gatewayAudienceValue
    gatewayScopeValue
    agentIdValue
    backendKeyValue
  ]
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/servicedesk-write.policy.xml')
  }
}

resource diagPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: diagApi
  name: 'policy'
  dependsOn: [
    backendKeyValue
  ]
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/servicedesk-diag.policy.xml')
  }
}

// ==== Diagnostics product and the lab VM's subscription

resource diagnosticsProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: 'servicedesk-diagnostics'
  properties: {
    displayName: 'Service Desk diagnostics'
    description: 'Lab VM access to the Service Desk MCP diagnostics API. No user context: write tools refuse every call.'
    subscriptionRequired: true
    approvalRequired: false
    subscriptionsLimit: 1
    state: 'published'
  }
}

resource diagnosticsProductApi 'Microsoft.ApiManagement/service/products/apis@2025-09-01-preview' = {
  parent: diagnosticsProduct
  name: diagApi.name
}

resource diagnosticsSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'lab-diagnostics'
  dependsOn: [
    diagnosticsProductApi
  ]
  properties: {
    displayName: 'Lab VM diagnostics'
    scope: '/products/${diagnosticsProduct.name}'
    state: 'active'
  }
}

output id string = apim.id
output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output readPolicyId string = readPolicy.id
output writePolicyId string = writePolicy.id
output diagPolicyId string = diagPolicy.id
output diagnosticsSubscriptionName string = diagnosticsSubscription.name
