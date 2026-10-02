# Research: APIM as MCP gateway, Python MCP server on Azure Container Apps, MCP protocol and Python SDK

Research date: 2026-10-01. Sources: Microsoft Learn (Learn MCP search/fetch), modelcontextprotocol.io, MCP Python SDK docs site, GitHub and PyPI.
Every bullet ends with its source URL. "Derived" or "Inference" marks my own reasoning or examples assembled from several documented snippets; risky items are repeated in the last section.

## A1. API Management: expose an existing MCP server (passthrough)

- "Expose and govern an existing MCP server" applies to Developer, Basic, Basic v2, Standard, Standard v2, Premium, Premium v2. Consumption is not listed. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Availability section: classic tiers Developer, Basic, Standard, Premium; v2 tiers Basic v2, Standard v2, Premium v2; the self-hosted gateway can also manage MCP servers. https://learn.microsoft.com/azure/api-management/mcp-server-overview
- MCP server capabilities are not supported in APIM workspaces. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- The external server must conform to MCP version 2025-06-18 or later, use Streamable HTTP or SSE, and use either no authorization or 2025-06-18 standards-compliant authorization. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- For external servers APIM supports tools and resources but not prompts (this page); the overview page says tools only (see last section). https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Prerequisite: if Application Insights or Azure Monitor logging is enabled at the global (All APIs) scope, set "Number of payload bytes to log" for Frontend Response to 0, otherwise MCP streaming can break. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Portal steps and labels: APIM instance > under APIs select "MCP servers" > "+ Create MCP server" > "Expose an existing MCP server" > section "Backend MCP server": "MCP server base URL" (example `https://learn.microsoft.com/api/mcp`) and "Transport type" ("Streamable HTTP" selected by default) > section "New MCP server": "Name", "Base path" (route prefix, example `mytools`), optional "Description" > "Products" (optional) > "Create". https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- After creation the "MCP Servers" pane lists the server and its "Server URL" column holds the URL for clients; which operations become tools can be chosen later in the "Tools" blade. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Documented client URL example: `https://<apim-service-name>.azure-api.net/<api-name>-mcp/mcp`. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Derived: an API with `path` `team01-mcp` and streamable endpoint `uriTemplate` `/mcp` should answer at `https://<apim>.azure-api.net/team01-mcp/mcp`; always copy the portal "Server URL". https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- Policy editor location: APIs > MCP Servers > select server > under "MCP" select "Policies"; global (All APIs) policies run before MCP-scope policies. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Known issues table: backend 401 because Authorization was not forwarded (fix with set-header); streaming fails when response bodies are logged or read by policy. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Doc tip: when testing an APIM-managed MCP server with MCP Inspector, use version 0.9.0. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- MCP servers can be bound to products from the server "Settings" > "Products" tab; consumers then send `Ocp-Apim-Subscription-Key`. https://learn.microsoft.com/azure/api-management/govern-mcp-server-products

## A2. API Management: ARM / REST representation

- Resource model: an MCP server is a `Microsoft.ApiManagement/service/apis` resource with `properties.type` = `mcp`; a passthrough server declares backend URL and transport; tools are `apis/tools` sub-resources (REST-backed servers); policies are `apis/policies`; product binding is `products/{productId}/apis/{mcpServerId}`. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- MCP management requires REST API version 2025-09-01-preview or later; pin it in every request. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- The ARM template reference "Latest" for service/apis is 2025-09-01-preview; `type`/`apiType` enums include `mcp`; `McpProperties.transportType` is `sse` or `streamable`; `McpEndpoint.uriTemplate` must match `^/.*$`. No GA api-version in the list carries `mcpProperties`. https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis
- Validation errors: 400 if `transportType` is not `streamable`/`sse` or a `uriTemplate` does not start with `/`; streamable requires exactly one endpoint (`message`), SSE exactly two (`sse`, `message`). https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- PUT is async (`provisioningState: InProgress`, poll `Azure-AsyncOperation`); use `If-Match: *` for idempotent PUT/DELETE; DELETE without If-Match returns 412. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- No separate backend entity is used in the documented passthrough templates; `serviceUrl` carries the backend base URL. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- Azure CLI has no native MCP command (docs use `az rest`); Terraform AzureRM has no native resource (use `azapi_resource`). https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api

Documented ARM template (passthrough, streamable, policy attached), source https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api

```json
{
  "type": "Microsoft.ApiManagement/service/apis",
  "apiVersion": "2025-09-01-preview",
  "name": "[concat(parameters('serviceName'), '/', parameters('mcpServerId'))]",
  "properties": {
    "type": "mcp",
    "displayName": "External MCP Server",
    "description": "Passthrough MCP server using streamable HTTP transport",
    "path": "[parameters('mcpServerId')]",
    "protocols": [ "https" ],
    "serviceUrl": "[parameters('backendUrl')]",
    "subscriptionRequired": true,
    "mcpProperties": {
      "transportType": "streamable",
      "endpoints": [ { "name": "message", "uriTemplate": "/mcp" } ]
    }
  }
},
{
  "type": "Microsoft.ApiManagement/service/apis/policies",
  "apiVersion": "2025-09-01-preview",
  "name": "[concat(parameters('serviceName'), '/', parameters('mcpServerId'), '/policy')]",
  "dependsOn": [ "[resourceId('Microsoft.ApiManagement/service/apis', parameters('serviceName'), parameters('mcpServerId'))]" ],
  "properties": {
    "format": "rawxml",
    "value": "<policies><inbound><base /><rate-limit calls=\"100\" renewal-period=\"60\" /></inbound><backend><forward-request /></backend><outbound><base /></outbound></policies>"
  }
}
```

- Product binding resource is `Microsoft.ApiManagement/service/products/apis` named `<service>/<productId>/<mcpServerId>` with no properties. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- REST policy attach: `PUT .../apis/{mcpServerId}/policies/policy?api-version=2025-09-01-preview` with body `{"properties":{"format":"rawxml","value":"<policies>...</policies>"}}`. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- Key Vault named value ARM shape: `Microsoft.ApiManagement/service/namedValues` with `properties.displayName`, `properties.secret: true`, `properties.keyVault.secretIdentifier`, `properties.keyVault.identityClientId` (null for system-assigned, client ID for user-assigned); a versioned identifier prevents auto-refresh. https://learn.microsoft.com/azure/templates/microsoft.apimanagement/2024-05-01/service/namedvalues

## A3. API Management: policies for MCP servers

- MCP-scope policies apply to all tools of the server; documented uses: rate limiting and quotas, JWT validation with Entra ID, IP filtering, caching. https://learn.microsoft.com/azure/api-management/mcp-server-overview
- Never read `context.Response.Body` in MCP-scope policies (triggers buffering, breaks streaming); the same warning applies to products with bound MCP servers. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- validate-azure-ad-token: all tiers; section inbound; scopes global, workspace, product, API, operation; gateways classic, v2, consumption, self-hosted, workspace; elements `client-application-ids`, `audiences`, `required-claims`, `backend-application-ids`; attribute `output-token-variable-name`; default header `Authorization`; default failure code 401. https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy
- The MCP security article shows validate-azure-ad-token with `tenant-id`, `header-name="Authorization"`, `failed-validation-httpcode="401"` and a client application ID. https://learn.microsoft.com/azure/api-management/secure-mcp-servers
- Request headers are automatically forwarded (with certain exclusions) to MCP tool invocations; to forward `Authorization` explicitly, the doc shows a set-header with `@(context.Request.Headers.GetValueOrDefault("Authorization"))`. https://learn.microsoft.com/azure/api-management/secure-mcp-servers
- rate-limit-by-key: applies to Developer, Basic, Basic v2, Standard, Standard v2, Premium, Premium v2; inbound; `renewal-period` max 300 s; returns 429; v2 tiers use a token bucket algorithm; counts are per gateway, not aggregated. https://learn.microsoft.com/azure/api-management/rate-limit-by-key-policy
- Per-tool throttling: a documented quota-by-key example keys on the context variable `gen_ai.tool.name` (example text contains a doubled comma, see last section). https://learn.microsoft.com/azure/api-management/govern-mcp-server-products
- set-header: sections inbound, outbound, backend, on-error; all gateways; `Connection`, `Content-Length`, `Keep-Alive`, `Transfer-Encoding` cannot be changed. https://learn.microsoft.com/azure/api-management/set-header-policy
- trace: writes an App Insights trace and a resource-log property when severity >= diagnostic verbosity; not affected by App Insights sampling; `metadata` adds custom properties. https://learn.microsoft.com/azure/api-management/trace-policy
- Named value types: Plain, Secret, Key vault. Key vault values need an APIM system- or user-assigned managed identity with Key Vault Secrets User (RBAC) or Get and List (access policy); enter the identifier without version for rotation; refresh within four hours; secret length 1 to 4096 characters; not available in workspaces. https://learn.microsoft.com/azure/api-management/api-management-howto-properties
- If the Key Vault firewall is on, APIM must use its system-assigned identity and "Allow trusted Microsoft services to bypass this firewall" must be enabled. https://learn.microsoft.com/azure/api-management/api-management-howto-properties
- Security caveat: anyone allowed to edit policies can read any named value through `{{name}}`, and Key Vault values are visible to users with API request tracing access. https://learn.microsoft.com/azure/api-management/api-management-howto-properties
- forward-request: default `timeout` 300 s, but values above 240 s may not be honored; `buffer-response="false"` for SSE-style backends. https://learn.microsoft.com/azure/api-management/forward-request-policy
- SSE guidance: keep idle connections alive within the 4-minute Azure Load Balancer idle timeout, avoid buffering policies such as validate-content, do not cache responses. https://learn.microsoft.com/azure/api-management/how-to-server-sent-events
- Foundry Agent Service MCP auth choices: key-based, Microsoft Entra agent identity, Microsoft Entra project managed identity, OAuth identity passthrough, unauthenticated; identity connections require an `audience`. https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication
- Before publishing, all agents in a project share one agent identity; a published agent gets its own identity. https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication
- Foundry managed OAuth refuses to send tokens for known Microsoft audiences to custom MCP servers ("Cannot pass Microsoft token to untrusted MCP endpoint"); register an audience you control. https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication

Derived policy for the lab (each element is a documented policy; the combination is untested), sources https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy and https://learn.microsoft.com/azure/api-management/api-management-howto-properties

```xml
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{tenant-id}}" header-name="Authorization"
        failed-validation-httpcode="401" failed-validation-error-message="Unauthorized"
        output-token-variable-name="jwt">
      <client-application-ids>
        <application-id>{{foundry-caller-client-id}}</application-id>
      </client-application-ids>
      <audiences>
        <audience>{{mcp-gateway-audience}}</audience>
      </audiences>
    </validate-azure-ad-token>
    <rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
    <!-- backend credential from a Key Vault backed named value -->
    <set-header name="x-backend-key" exists-action="override">
      <value>{{backend-key-kv}}</value>
    </set-header>
    <!-- do not leak the Entra token to the container app -->
    <set-header name="Authorization" exists-action="delete" />
    <trace source="mcp-gateway" severity="information">
      <message>@(context.Request.Headers.GetValueOrDefault("Mcp-Session-Id", "none"))</message>
      <metadata name="mcp-session-id" value="@(context.Request.Headers.GetValueOrDefault("Mcp-Session-Id", "none"))" />
    </trace>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
```

## A4. API Management: monitoring MCP traffic

Application Insights path (monitor-mcp-servers, read in full):

- Prerequisite: an Application Insights resource linked to APIM (logger). For every MCP request APIM writes an Application Insights `requests` row with MCP dimensions and `duration`; dimensions follow OpenTelemetry GenAI semantic conventions (`gen_ai.*`). https://learn.microsoft.com/azure/api-management/monitor-mcp-servers
- Tool arguments and results are not captured by default; enable via APIs > MCP servers > (server) > Settings > Diagnostic Logs > Frontend and Backend payload logging > Save (may capture secrets). https://learn.microsoft.com/azure/api-management/monitor-mcp-servers
- Dimensions on every MCP request: `gen_ai.operation.name` (JSON-RPC method, tools/list or tools/call), `gen_ai.conversation.id` (MCP session ID), `network.protocol.name` (MCP), `network.protocol.version`, `auth.type`, `user_agent.name` (MCP client name), `user_agent.version`, `service.name` (MCP server name), `service.version`, `api.type` (Mcp), `error.message`, `error.type`. tools/list adds `ToolCount`; tools/call adds `gen_ai.tool.name`, `gen_ai.tool.type`, and with payload logging `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`. https://learn.microsoft.com/azure/api-management/monitor-mcp-servers
- Custom data (agent ID header, JWT claim, correlation ID): use the trace policy at MCP scope. https://learn.microsoft.com/azure/api-management/monitor-mcp-servers
- Workspace-based App Insights: the Log Analytics table for `requests` is `AppRequests`; custom properties are in `Properties` (`customDimensions` in the classic schema); duration is `DurationMs`. https://learn.microsoft.com/azure/azure-monitor/app/data-model-complete
- AppRequests columns include `OperationId`, `ParentId`, `Id`, `Properties`, `Success`, `ResultCode`, `DurationMs`. https://learn.microsoft.com/azure/azure-monitor/reference/tables/apprequests
- The portal connects App Insights by instrumentation key only; for connection string with managed identity use REST/Bicep/ARM (`Microsoft.ApiManagement/service/loggers`, `credentials.connectionString`, `credentials.identityClientId`) and grant Monitoring Metrics Publisher. https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights
- APIM emits dependency telemetry automatically for forward-request, validate-jwt and other listed policies; logging at high request rates can cut throughput 40 to 50 percent. https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights
- Correlation to the backend: diagnostic property `httpCorrelationProtocol` = `None` (no headers), `Legacy` (inject `Request-Id` and `Request-Context`), `W3C` (inject Trace Context headers). https://learn.microsoft.com/rest/api/apimanagement/diagnostic/create-or-update
- The same enum (`Legacy`, `None`, `W3C`) exists on `service/diagnostics` and `service/apis/diagnostics` ARM types. https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/diagnostics

Documented KQL (App Insights `requests` schema), source https://learn.microsoft.com/azure/api-management/monitor-mcp-servers

```kusto
requests
| where customDimensions["api.type"] == "Mcp"
  and customDimensions["service.name"] == "sales-mcp"
  and customDimensions["gen_ai.operation.name"] == "tools/call"
| project timestamp,
          tool       = customDimensions["gen_ai.tool.name"],
          session    = customDimensions["gen_ai.conversation.id"],
          client     = strcat(customDimensions["user_agent.name"], "/", customDimensions["user_agent.version"]),
          durationMs = duration,
          success
| order by timestamp desc
| take 50
```

Resource logs path (Log Analytics):

- Resource log categories for Microsoft.ApiManagement/service: `GatewayLogs` -> `ApiManagementGatewayLogs`; `GatewayMCPLogs` -> `ApiManagementGatewayMCPLog` ("Gateway Logs related to MCP requests"); `GatewayLlmLogs`; `WebSocketConnectionLogs`; `DeveloperPortalAuditLogs`. https://learn.microsoft.com/azure/api-management/monitor-api-management-reference
- Choose "Resource specific" as destination table (recommended over AzureDiagnostics). https://learn.microsoft.com/azure/api-management/monitor-api-management
- ARM: `Microsoft.Insights/diagnosticSettings` (api 2021-05-01-preview) with `logAnalyticsDestinationType: "Dedicated"` gives resource-specific tables; null default means AzureDiagnostics. https://learn.microsoft.com/azure/templates/microsoft.insights/diagnosticsettings
- Consumption tier cannot collect resource logs. https://learn.microsoft.com/azure/api-management/api-management-howto-use-azure-monitor
- Latency: a new Log Analytics workspace can take up to 2 hours to receive data; an existing one about 15 minutes. https://learn.microsoft.com/azure/api-management/monitor-api-management
- Size limits: 32 KB per entry; logged request/response payloads up to 8,192 bytes each; oversize entries lose body and trace content. https://learn.microsoft.com/azure/api-management/monitor-api-management
- `ApiManagementGatewayMCPLog` columns: ApiType (passthrough or mcp backend), AuthenticationMethod (oauth2, api_key, cert, none), ClientName, ClientVersion, CorrelationId ("corresponding with the same field in ApiManagementGatewayLogs"), Error, ErrorType, McpServerEndpoint, Method (tools/call, notification...), OperationName, ProtocolVersion, Region, ServerName, ServerVersion, SessionId ("id from AI conversation / agent chat session"), TimeGenerated, ToolCount, ToolName, TransportType, _ResourceId. Basic log plan supported; no DCR transformation. https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaymcplog
- `ApiManagementGatewayLogs` useful columns: CorrelationId, ApiId, OperationId, Method, Url, ResponseCode, BackendResponseCode, BackendUrl, BackendTime, TotalTime, CallerIpAddress, RequestHeaders, BackendRequestHeaders, ResponseHeaders, TraceRecords, LastErrorReason. https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaylogs
- Headers are logged only if named in the diagnostic entity (`frontend`/`backend` > `request`/`response` > `headers` array; `body.bytes` max 8192). https://learn.microsoft.com/rest/api/apimanagement/diagnostic/create-or-update
- Overview guidance: include correlation IDs in request headers to track requests across systems. https://learn.microsoft.com/azure/api-management/mcp-server-overview

Derived KQL (not in docs; table and column names from the table references above), sources https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaymcplog and https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaylogs

```kusto
// Find one tool call with its MCP session id, then join to the gateway request record
ApiManagementGatewayMCPLog
| where TimeGenerated > ago(4h)
| where Method == "tools/call" and ToolName == "<tool_name>"
| project TimeGenerated, CorrelationId, SessionId, ToolName, ClientName, ClientVersion,
          ServerName, ProtocolVersion, TransportType, AuthenticationMethod, Error, ErrorType
| join kind=leftouter (
    ApiManagementGatewayLogs
    | where TimeGenerated > ago(4h)
    | project CorrelationId, ResponseCode, BackendResponseCode, BackendUrl, TotalTime,
              BackendTime, CallerIpAddress, RequestHeaders, BackendRequestHeaders, TraceRecords
  ) on CorrelationId
| order by TimeGenerated desc

// Same data from workspace-based App Insights
AppRequests
| where tostring(Properties["api.type"]) == "Mcp"
| where tostring(Properties["gen_ai.operation.name"]) == "tools/call"
| project TimeGenerated, OperationId, Id, DurationMs, Success, ResultCode,
          Tool = tostring(Properties["gen_ai.tool.name"]),
          Session = tostring(Properties["gen_ai.conversation.id"])
```

## A5. Developer vs Basic v2 (provisioning and pricing-relevant facts)

- Developer tier: creating and activating takes 30 to 40 minutes. https://learn.microsoft.com/azure/api-management/get-started-create-service-instance-cli
- Basic v2: "an economical choice for development and testing scenarios and is deployed in a few minutes". https://learn.microsoft.com/azure/api-management/get-started-create-service-instance
- v2 tiers deploy in minutes; Basic v2 and Standard v2 scale to 10 units. https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview
- MCP server features exist in both Developer and Basic v2. https://learn.microsoft.com/azure/api-management/mcp-server-overview
- Feature table: Developer has no SLA, 1 scale unit, 10 MB cache, VNet injection, static IP, self-hosted gateway, no workspaces; Basic v2 has 10 units, 250 MB cache, no static IP, no VNet support, workspaces; both have Log Analytics request logs and App Insights request logs. https://learn.microsoft.com/azure/api-management/api-management-features
- Pricing page facts: Basic v2 includes 10M API requests per month with per-1M overage and a 99.95% SLA; footnote says Basic v2 is free for up to 100,000 requests when created as an AI Gateway in Azure AI Foundry; Developer has no SLA and an estimated 500 requests/sec per unit. Dollar amounts render client side and were not retrievable; use the pricing calculator. https://azure.microsoft.com/en-us/pricing/details/api-management/
- v2 unavailable features include multi-region, backup and restore, self-hosted gateway, upgrade from classic tiers, resource move. https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview
- Infrastructure changes can take 15 minutes or longer; only the Developer tier has gateway downtime during them. https://learn.microsoft.com/azure/api-management/upgrade-and-scale
- Soft-delete: a deleted instance stays soft-deleted for 48 hours; its name cannot be reused meanwhile and cannot be reused in another subscription for days after purge; purge with `az apim deletedservice purge`. https://learn.microsoft.com/azure/api-management/soft-delete

## B1. Azure Container Apps hosting an MCP server

- Two models: standalone container app (Container Apps has no MCP awareness) and dynamic sessions (platform-managed MCP, preview, protocol 2025-03-26, `x-ms-apikey`). https://learn.microsoft.com/azure/container-apps/mcp-overview
- Scale to zero is supported, but a minimum of one replica is recommended for interactive MCP use. https://learn.microsoft.com/azure/container-apps/mcp-overview
- Ingress `transport` should be `auto` or `http`; there is no special MCP transport value; CORS is needed only for browser-based clients. https://learn.microsoft.com/azure/container-apps/mcp-overview
- Security guidance: prefer stateless MCP servers to avoid session hijacking (Python `stateless_http=True`); put health probes on a separate endpoint, not the MCP endpoint; rate limit in code or front with APIM. https://learn.microsoft.com/azure/container-apps/mcp-authentication
- CORS allow-list example includes `Mcp-Session-Id` ("used by MCP clients for stateful sessions"). https://learn.microsoft.com/azure/container-apps/mcp-authentication
- Python tutorial pattern: `FastMCP("TasksMCP", stateless_http=True)`, FastAPI app mounting `mcp.streamable_http_app()` at `/`, lifespan entering `mcp.session_manager.run()`, endpoint `/mcp`, separate `/health`, `requirements.txt` with `mcp[cli]>=1.2.0`, uvicorn on 8080, `az containerapp up --ingress external --target-port 8080`, then `--min-replicas 1`. https://learn.microsoft.com/azure/container-apps/tutorial-mcp-server-python
- Troubleshooting: mounting the SDK app at `/mcp` yields `/mcp/mcp` (404); probes against the MCP endpoint fail; port mismatch gives 502; cold start 10 to 30 s. https://learn.microsoft.com/azure/container-apps/mcp-troubleshooting
- HTTP ingress request timeout is 240 seconds. https://learn.microsoft.com/azure/container-apps/ingress-overview
- Premium ingress (workload profile) exposes "Idle request timeout" 4 to 30 minutes (default 4). https://learn.microsoft.com/azure/container-apps/ingress-environment-configuration
- Session affinity uses HTTP cookies, needs single revision mode and HTTP ingress (`ingress.stickySessions.affinity: sticky`). https://learn.microsoft.com/azure/container-apps/sticky-sessions
- Probes: Startup, Liveness, Readiness; HTTP success is 200 to 399; one of each per container; when ingress is enabled the portal adds TCP default probes on the target port; in single revision mode traffic shifts once readiness passes. https://learn.microsoft.com/azure/container-apps/health-probes
- Single revision mode keeps the old revision serving until the new one is provisioned, scaled and passing probes. https://learn.microsoft.com/azure/container-apps/revisions
- Foundry constraints for ACA-hosted MCP: Linux amd64 only, stateless only, custom auth required; non-streaming MCP tool calls time out after 100 seconds; "Invalid tool schema" if the definition includes `anyOf`/`allOf` or multi-type parameters. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

## B2. Container Apps ARM schema essentials

- Current GA api-version (template reference "Latest"): `Microsoft.App/containerApps` 2026-07-01 and `Microsoft.App/managedEnvironments` 2026-07-01. https://learn.microsoft.com/azure/templates/microsoft.app/containerapps
- `configuration.registries[].identity`: full user-assigned identity resource ID or `system`; `passwordSecretRef` is the credential alternative. https://learn.microsoft.com/azure/templates/microsoft.app/containerapps
- `configuration.secrets[]`: `name`, `keyVaultUrl`, `identity` (UAMI resource ID or system). https://learn.microsoft.com/azure/templates/microsoft.app/containerapps
- Key Vault references need the app identity to hold Key Vault Secrets User; a versionless URI is refreshed within 30 minutes and revisions that use it in env vars restart; CLI form `name=keyvaultref:<uri>,identityref:<uami-id>`; system identity cannot be used with the create command. https://learn.microsoft.com/azure/container-apps/manage-secrets
- Env vars reference secrets with `secretRef` (CLI `secretref:<name>`); secret changes do not create a revision, restart or redeploy instead. https://learn.microsoft.com/azure/container-apps/manage-secrets
- Image pull with MI: the registry must allow ARM audience tokens (`az acr config authentication-as-arm show/update`); the identity needs AcrPull (role ID 7f951dda-4ed3-4680-a7ca-43fe172d538d); CLI `--user-assigned`, `--registry-identity`, `--registry-server`; pull policy is always. https://learn.microsoft.com/azure/container-apps/managed-identity-image-pull
- `configuration.identitySettings[].lifecycle` (`None`, `Init`, `Main`, `All`) limits where an identity can be used, for example an ACR-pull-only identity with `None`. https://learn.microsoft.com/azure/container-apps/managed-identity
- Ingress properties: `external`, `targetPort`, `transport`, `stickySessions.affinity`, `ipSecurityRestrictions`, `corsPolicy`, `traffic`. https://learn.microsoft.com/azure/container-apps/ingress-how-to
- Probe schema: `type` Liveness/Readiness/Startup, `httpGet.path/port`, `initialDelaySeconds` 1 to 60, `successThreshold` must be 1 for liveness and startup. https://learn.microsoft.com/azure/templates/microsoft.app/containerapps
- Environment `appLogsConfiguration.destination`: `log-analytics`, `azure-monitor` or `none`; `logAnalyticsConfiguration` (customerId, sharedKey) only with `log-analytics`; `appInsightsConfiguration.connectionString` and `openTelemetryConfiguration` also exist. https://learn.microsoft.com/azure/templates/microsoft.app/managedenvironments
- Legacy `log-analytics` destination writes `ContainerAppConsoleLogs_CL`/`ContainerAppSystemLogs_CL` through the HTTP Data Collector API, whose support ended September 14, 2026 (critical fixes only); move to `azure-monitor` plus a diagnostic setting, which writes `ContainerAppConsoleLogs`/`ContainerAppSystemLogs` with unsuffixed columns (`Log`, `ContainerAppName`, `RevisionName`, `ContainerName`, `Stream`). https://learn.microsoft.com/azure/container-apps/migrate-logs-azure-monitor
- A diagnostic setting can take up to 90 minutes to start; max five per resource; Azure Monitor destination is unavailable for Express environments; `dynamicJsonColumns` is not supported, so parse JSON with `parse_json(Log)`. https://learn.microsoft.com/azure/container-apps/migrate-logs-azure-monitor
- Managed environment log categories: ContainerAppConsoleLogs, ContainerAppSystemLogs, ContainerAppHTTPLogs (no table listed), plus session pool categories. https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-app-managedenvironments-logs

Assembled ARM snippet (property names from the schema references above; values illustrative), sources https://learn.microsoft.com/azure/templates/microsoft.app/containerapps and https://learn.microsoft.com/azure/container-apps/migrate-logs-azure-monitor

```json
{
  "type": "Microsoft.App/managedEnvironments",
  "apiVersion": "2026-07-01",
  "name": "[parameters('envName')]",
  "location": "[parameters('location')]",
  "properties": { "appLogsConfiguration": { "destination": "azure-monitor" } }
},
{
  "type": "Microsoft.Insights/diagnosticSettings",
  "apiVersion": "2021-05-01-preview",
  "scope": "[format('Microsoft.App/managedEnvironments/{0}', parameters('envName'))]",
  "name": "env-to-law",
  "properties": {
    "workspaceId": "[parameters('lawId')]",
    "logs": [
      { "category": "ContainerAppConsoleLogs", "enabled": true },
      { "category": "ContainerAppSystemLogs", "enabled": true }
    ]
  }
},
{
  "type": "Microsoft.App/containerApps",
  "apiVersion": "2026-07-01",
  "name": "[parameters('appName')]",
  "location": "[parameters('location')]",
  "identity": { "type": "UserAssigned", "userAssignedIdentities": { "[parameters('uamiId')]": {} } },
  "properties": {
    "environmentId": "[resourceId('Microsoft.App/managedEnvironments', parameters('envName'))]",
    "configuration": {
      "activeRevisionsMode": "Single",
      "ingress": { "external": true, "targetPort": 8000, "transport": "auto" },
      "registries": [ { "server": "[concat(parameters('acrName'), '.azurecr.io')]", "identity": "[parameters('uamiId')]" } ],
      "secrets": [ { "name": "backend-api-key", "keyVaultUrl": "[parameters('kvSecretUri')]", "identity": "[parameters('uamiId')]" } ]
    },
    "template": {
      "containers": [ {
        "name": "mcp-server",
        "image": "[parameters('image')]",
        "env": [
          { "name": "AZURE_CLIENT_ID", "value": "[parameters('uamiClientId')]" },
          { "name": "BACKEND_API_KEY", "secretRef": "backend-api-key" }
        ],
        "probes": [
          { "type": "Startup",   "httpGet": { "path": "/health", "port": 8000 }, "initialDelaySeconds": 3, "periodSeconds": 3 },
          { "type": "Liveness",  "httpGet": { "path": "/health", "port": 8000 }, "periodSeconds": 30 },
          { "type": "Readiness", "httpGet": { "path": "/health", "port": 8000 }, "periodSeconds": 10 }
        ]
      } ],
      "scale": { "minReplicas": 1, "maxReplicas": 1 }
    }
  }
}
```

## B3. az acr build, revision deployment and RBAC

- `az acr build` runs an ACR Tasks quick task: packs the local context, uploads it, builds in Azure, pushes by default; no local Docker engine needed; default platform Linux/AMD64. https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview
- Syntax: `az acr build --registry $ACR_NAME --image helloacrtasks:v1 --file /path/to/Dockerfile /path/to/build/context`. https://learn.microsoft.com/azure/container-registry/container-registry-tutorial-quick-task
- Official notice: "Azure Container Registry task runs are temporarily paused from Azure free credits." https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview
- Community answers describe the symptom: context uploads, then `TasksOperationsNotAllowed` on Free Trial, Azure for Students or credit-funded subscriptions; workaround is local docker build and push. https://learn.microsoft.com/answers/a/12837857
- If registry public network access is disabled, `az acr build` fails unless you use a dedicated agent pool or allow the AzureContainerRegistry service tag IPs. https://learn.microsoft.com/azure/container-registry/container-registry-private-endpoints
- Command-line values can appear in ACR diagnostic tracing; do not pass secrets as build arguments. https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview
- RBAC: Container Registry Tasks Contributor (fb382eab-e894-4461-af04-94435c366c3f) covers quick builds and includes `registries/read`, `scheduleRun/action`, `listBuildSourceUploadUrl/action`, `runs/listLogSasUrl/action`. https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/containers
- Recommended role for identities that orchestrate ACR tasks including `az acr build`: Container Registry Tasks Contributor; AcrPush grants data-plane push and pull with no control-plane permissions. https://learn.microsoft.com/azure/container-registry/container-registry-rbac-built-in-roles-overview
- AcrPush (8311e382-0749-4cb8-b61a-304f252e45ec) contains only `registries/pull/read` and `registries/push/write`, so it cannot schedule a run (Inference from the role definition). https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/containers
- ABAC-enabled registries: quick builds get no default data-plane access; use `--source-acr-auth-id [caller]`. https://learn.microsoft.com/azure/container-registry/container-registry-rbac-abac-repository-permissions
- Deploy: `az containerapp update --name <APP> --resource-group <RG> --image <IMAGE>`; revision-scope changes create a new revision. https://learn.microsoft.com/azure/container-apps/revisions-manage
- List and inspect: `az containerapp revision list --name <APP> --resource-group <RG> -o table` (add `--all` for inactive), `az containerapp revision show --revision <REV>`, plus `restart`, `activate`, `deactivate`. https://learn.microsoft.com/cli/azure/containerapp/revision
- Confirm health through revision provisioning state (Provisioning, Provisioned, Provisioning failed) and running state (Running, Degraded, Failed, Activation failed). https://learn.microsoft.com/azure/container-apps/revisions
- Container Apps Contributor (358470bc-b998-42bd-ab17-a7e34c199c0f): "Full management of Container Apps, including creation, deletion, and updates"; Container Apps Operator (f3bd1b5c-91fa-40e7-afe7-0c11d331232c): read, log stream, exec, no write. https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/containers
- Both Container Apps Contributor and Operator can read secret values through the wildcard that matches `listSecrets/action`. https://learn.microsoft.com/azure/container-apps/manage-secrets

## B4. Managed identity from Python in Container Apps

- The app gets `IDENTITY_ENDPOINT` and `IDENTITY_HEADER`; token GET takes `resource`, `api-version=2019-08-01` and header `X-IDENTITY-HEADER`; for a user-assigned identity pass `client_id`, `principal_id` or `mi_res_id`, otherwise the system identity is attempted. https://learn.microsoft.com/azure/container-apps/managed-identity
- With the Azure Identity library you must explicitly specify the user-assigned client ID. https://learn.microsoft.com/azure/container-apps/managed-identity
- Managed identity back ends cache tokens per resource URI for about 24 hours; forced refresh is not supported, so assign roles before first use. https://learn.microsoft.com/azure/container-apps/managed-identity
- Adding or changing an identity does not restart the app or create a revision. https://learn.microsoft.com/azure/container-apps/managed-identity
- `ManagedIdentityCredential(client_id="<client-id>")` or `identity_config={"resource_id": "<id>"}` for user-assigned identities. https://learn.microsoft.com/azure/developer/python/sdk/authentication/user-assigned-managed-identity
- `DefaultAzureCredential()` without `managed_identity_client_id` falls back to the `AZURE_CLIENT_ID` environment variable; without it the system identity is used. https://learn.microsoft.com/azure/developer/python/tutorial-python-managed-identity-user-assigned-cli
- Microsoft recommends replacing DefaultAzureCredential with a specific credential once deployed; `AZURE_TOKEN_CREDENTIALS=ManagedIdentityCredential` narrows the chain (azure-identity 1.24.0+). https://learn.microsoft.com/azure/developer/python/sdk/authentication/credential-chains

Documented Key Vault sample, source https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview-for-developers

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import os

client_id = os.getenv("Managed_Identity_Client_ID")   # lab: use AZURE_CLIENT_ID
credential = DefaultAzureCredential(managed_identity_client_id=client_id)
client = SecretClient(vault_url="https://<your-key-vault-name>.vault.azure.net/", credential=credential)
secret_value = client.get_secret("<your-secret-name>").value
```

## C1. MCP protocol: revision, sessions, structured output, errors

- The current protocol revision is 2026-07-28 (newer than both 2025-06-18 and 2025-11-25). https://modelcontextprotocol.io/specification/versioning
- 2026-07-28 removes protocol-level sessions and the `Mcp-Session-Id` header, removes the `initialize` handshake (version, client info and capabilities travel in each request `_meta`), adds mandatory `server/discover`, replaces the GET stream with `subscriptions/listen`, removes resumability, adds required `resultType`, requires `Mcp-Method`/`Mcp-Name` headers, and documents `traceparent`/`tracestate`/`baggage` in `_meta`. https://modelcontextprotocol.io/specification/2026-07-28/changelog
- 2026-07-28 transport: every POST MUST carry `MCP-Protocol-Version` matching `_meta`; a server that only speaks this revision SHOULD ignore an incoming `Mcp-Session-Id` and not mint one, and answer GET/DELETE with 405. https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
- Backward compatibility: a dual-era client MAY send a modern request first and fall back to `initialize` on a 400 without a recognized modern error; servers supporting pre-2025-06-18 clients MAY treat a missing header as 2025-03-26. https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
- Legacy (2025-11-25) session rules: the server MAY assign `MCP-Session-Id` on the HTTP response that carries `InitializeResult`; it SHOULD be globally unique and cryptographically secure and MUST be visible ASCII 0x21 to 0x7E; clients MUST send it on all subsequent requests; servers that require it SHOULD return 400 when missing; a terminated session returns 404 and the client MUST re-initialize; clients SHOULD DELETE to end a session (server MAY answer 405). https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- Legacy rules also: clients MUST send `MCP-Protocol-Version` after initialization (missing means assume 2025-03-26; invalid means 400); POST `Accept` must list `application/json` and `text/event-stream`; notifications get 202. https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- Transport security: servers MUST validate `Origin` (403 if invalid), SHOULD bind to localhost when local and SHOULD authenticate. https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- Structured output: `structuredContent` (a JSON object in 2025-11-25; any JSON value in 2026-07-28); a tool returning structured content SHOULD also return serialized JSON in a TextContent block; with `outputSchema`, servers MUST conform and clients SHOULD validate. https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- 2026-07-28 keeps those rules and allows array output schemas. https://modelcontextprotocol.io/specification/2026-07-28/server/tools
- Errors: protocol errors (JSON-RPC, for example -32602 "Unknown tool") for unknown tools, malformed requests and server errors; tool execution errors as results with `isError: true` for API failures, input validation errors and business logic errors, which clients SHOULD pass to the model. https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- In 2025-06-18 "Invalid arguments" was listed under protocol errors; later revisions moved input validation to `isError`. https://modelcontextprotocol.io/specification/2025-06-18/server/tools
- 2026-07-28 stateful tool guidance: no protocol session, so return an explicit handle from a creation tool and accept it as an argument later. https://modelcontextprotocol.io/specification/2026-07-28/server/tools
- Tool names SHOULD be 1 to 128 characters using A-Z, a-z, 0-9, underscore, hyphen, dot. https://modelcontextprotocol.io/specification/2025-11-25/server/tools

## C2. MCP Python SDK (package `mcp`)

- Latest release 2.2.0 (Sep 7, 2026); 2.0.0 shipped Jul 28, 2026 as a major rework supporting 2026-07-28 "and every earlier revision"; Python 3.10+. https://pypi.org/project/mcp/
- Newest 1.x release 1.30.0 (Sep 7, 2026); the v1.x branch still gets bug fixes; to stay on v1 pin `mcp>=1.28,<2`. https://pypi.org/project/mcp/
- v2 renames `FastMCP` to `MCPServer`; importing `mcp.server.fastmcp` raises `ModuleNotFoundError`; ToolError lives in `mcp.server.mcpserver.exceptions`. https://py.sdk.modelcontextprotocol.io/migration/
- v2 moves host, port, stateless_http, json_response off the constructor to `run()`/`streamable_http_app()`; `MCPServer("x", port=9000)` raises TypeError. https://py.sdk.modelcontextprotocol.io/whats-new/
- v2 `run(transport="streamable-http")` defaults: host 127.0.0.1, port 8000, path `/mcp`; options `json_response=True` (single JSON instead of SSE), `stateless_http=True`, `max_request_body_size` (4 MiB), `session_idle_timeout` (1800 s), `max_sessions` (10,000). https://py.sdk.modelcontextprotocol.io/run/
- v2 `streamable_http_app()` takes the same kwargs except port; when mounted, the host lifespan must enter `mcp.session_manager.run()` or requests fail with "Task group is not initialized"; `@mcp.custom_route()` adds plain HTTP routes that are never authenticated. https://py.sdk.modelcontextprotocol.io/run/asgi/
- v2 DNS rebinding protection: non-localhost deployments get `421 Misdirected Request` until `TransportSecuritySettings(allowed_hosts=[...])` is set; behind a proxy that controls Host use `enable_dns_rebinding_protection=False`; behind TLS-terminating proxies run uvicorn with `--proxy-headers`. https://py.sdk.modelcontextprotocol.io/run/deploy/
- Eras in v2: 2026-07-28 requests never get `Mcp-Session-Id`; legacy clients get stateful in-memory sessions by default (404 "Session not found" across workers without sticky routing); `stateless_http` affects only the legacy leg; there is no option to restrict protocol versions; the docs show no way to read the session ID from the tool context. https://py.sdk.modelcontextprotocol.io/run/legacy-clients/
- v2 errors: `ToolError` becomes `is_error=True` with its message; other exceptions become `is_error=True` with sanitized text "Error executing tool <name>" and a full traceback in server logs; argument validation failures return `is_error=True` before the function runs; `MCPError` becomes a JSON-RPC error. https://py.sdk.modelcontextprotocol.io/servers/handling-errors/
- v2 structured output: the return annotation becomes the output schema; scalars wrap as `{"result": ...}`; BaseModel, TypedDict, dataclass and `dict[str, ...]` stay unwrapped; results are validated; opt out with `structured_output=False`; Optional and Union generate `anyOf`. https://py.sdk.modelcontextprotocol.io/servers/structured-output/
- v1.x `FastMCP` defaults: host 127.0.0.1, port 8000, `streamable_http_path` `/mcp`, `stateless_http` False, `json_response` False; when host is 127.0.0.1, localhost or ::1 and no `transport_security` is given it auto-creates a localhost-only allow list; `custom_route(path, methods, ...)` routes are appended to the streamable app. https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/v1.x/src/mcp/server/fastmcp/server.py
- v1.x transport security: invalid Host gives 421, invalid Origin 403, `host:*` port wildcards allowed; with no settings object, protection is disabled. https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/v1.x/src/mcp/server/transport_security.py
- v1.x errors: tool exceptions are re-raised as `ToolError("Error executing tool <name>: <original>")` and returned as `CallToolResult(isError=True)`; JSON Schema input failures return "Input validation error: ..." with `isError=True`. https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/v1.x/src/mcp/server/fastmcp/tools/base.py and https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/v1.x/src/mcp/server/lowlevel/server.py
- v1.x docs: constructor options `stateless_http=True, json_response=True`; mounted pattern with `mcp.session_manager.run()`; `mcp.settings.streamable_http_path = "/"`; CORS must expose `Mcp-Session-Id`. https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/v1.x/docs/server.md

Official v2 README quickstart, source https://pypi.org/project/mcp/

```python
from mcp.server import MCPServer

mcp = MCPServer("Demo")

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b
# run: uv run mcp run server.py --transport streamable-http   -> http://localhost:8000/mcp
```

v2 container entry point assembled from the /run/asgi and /run/deploy snippets, sources https://py.sdk.modelcontextprotocol.io/run/asgi/ and https://py.sdk.modelcontextprotocol.io/run/deploy/

```python
from contextlib import asynccontextmanager
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Mount
from mcp.server import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

mcp = MCPServer("TeamTools")

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

@mcp.custom_route("/health", methods=["GET"])
async def health(request: Request) -> Response:
    return JSONResponse({"status": "ok"})

security = TransportSecuritySettings(allowed_hosts=["<app-fqdn>", "<app-fqdn>:*"])

@asynccontextmanager
async def lifespan(app: Starlette):
    async with mcp.session_manager.run():
        yield

app = Starlette(routes=[Mount("/", app=mcp.streamable_http_app(transport_security=security))],
                lifespan=lifespan)
# uvicorn server:app --host 0.0.0.0 --port 8000   (MCP endpoint /mcp)
```

v1.x pinned variant (FastMCP), assembled from v1.x source and docs, source https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/v1.x/src/mcp/server/fastmcp/server.py

```python
# requirements: mcp[cli]>=1.28,<2
from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse

# host="0.0.0.0" binds all interfaces and skips the localhost-only Host allow list
mcp = FastMCP("TeamTools", host="0.0.0.0", port=8000, stateless_http=False, json_response=False)

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

@mcp.custom_route("/health", methods=["GET"])
async def health(request: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})

if __name__ == "__main__":
    mcp.run(transport="streamable-http")   # http://0.0.0.0:8000/mcp
```

## Recommendations for the lab design

1. Decide the "session ID" exercise first. The Mcp-Session-Id only exists in the handshake era (2025-11-25 and earlier) with a stateful server; protocol 2026-07-28 has no sessions, and the v2 SDK never mints a session for modern clients. Pilot with the real Foundry agent through APIM and confirm that `ApiManagementGatewayMCPLog.SessionId` and `gen_ai.conversation.id` are populated before writing lab steps. If they are empty, rewrite the task around `CorrelationId` (APIM) and `OperationId` (App Insights). https://modelcontextprotocol.io/specification/2026-07-28/changelog
2. Keep the server stateful only if the session exercise needs it (`stateless_http=False`), and then pin `maxReplicas: 1`: sessions live in process memory and ACA sticky sessions rely on cookies that an agent behind APIM is unlikely to carry. Expect sessions to reset on every new revision (clients must re-initialize on 404). https://py.sdk.modelcontextprotocol.io/run/legacy-clients/
3. Pin the SDK explicitly. The Microsoft ACA tutorial's `mcp[cli]>=1.2.0` now resolves to 2.x, where `from mcp.server.fastmcp import FastMCP` fails. Either pin `mcp==1.30.0` (FastMCP API, matches Learn tutorials) or write v2 code (`MCPServer`). Bake the lock file into the repo participants clone. https://py.sdk.modelcontextprotocol.io/migration/
4. Configure Host validation. Behind ACA ingress and APIM the Host header is the container app FQDN (Inference: APIM forwards to the `serviceUrl` host), so set `allowed_hosts` to that FQDN, or construct v1 FastMCP with `host="0.0.0.0"`, or disable rebinding protection and rely on the gateway key. Otherwise every request returns 421. https://py.sdk.modelcontextprotocol.io/run/deploy/
5. Expose `/health` with `@mcp.custom_route` and point HTTP startup, liveness and readiness probes at it; do not probe `/mcp`. https://learn.microsoft.com/azure/container-apps/mcp-troubleshooting
6. Tool design for Foundry: avoid Optional/Union parameters (they emit `anyOf`, which Foundry rejects as "Invalid tool schema"); use concrete types with defaults; keep each tool call well under 100 seconds; return structured results plus text. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
7. Raise `ToolError` (v2: `mcp.server.mcpserver.exceptions`) with an actionable message for expected failures so the model sees it; unhandled exceptions reach the model only as a sanitized message in v2. https://py.sdk.modelcontextprotocol.io/servers/handling-errors/
8. APIM tier: Basic v2 for a multi-team lab (minutes to provision, SLA, MCP supported, resource logs supported). Developer takes 30 to 40 minutes and has no SLA. Basic v2 has no static IP, so do not plan ACA IP restrictions to APIM; protect the backend with a gateway-injected key header that the server checks. Use unique APIM names per deployment because of 48-hour soft-delete. https://learn.microsoft.com/azure/api-management/api-management-features
9. Deploy the MCP API with ARM `Microsoft.ApiManagement/service/apis@2025-09-01-preview` (`type: mcp`, `mcpProperties.transportType: streamable`, endpoint `/mcp`, `serviceUrl` = `https://<app-fqdn>`). If Foundry authenticates with Entra (project managed identity or agent identity), set `subscriptionRequired: false` and enforce `validate-azure-ad-token` (audience = the App ID URI configured in the Foundry connection, client application = the calling identity). Configure `require_approval` deliberately on the agent tool (default is "always"). https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
10. Keep MCP-safe logging: frontend response body bytes = 0 at All APIs; enable payload logging only on the MCP server if the lab needs arguments; never read `context.Response.Body`. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
11. APIM logs: one diagnostic setting to the team Log Analytics workspace with `GatewayLogs` and `GatewayMCPLogs`, `logAnalyticsDestinationType: Dedicated`. Also list `Mcp-Session-Id`, `MCP-Protocol-Version` and `traceparent` in the Azure Monitor diagnostic `frontend.request.headers` so `ApiManagementGatewayLogs.RequestHeaders` shows them. Join MCP log to gateway log on `CorrelationId` (documented). https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaymcplog
12. App Insights: link APIM with a connection-string logger and set `httpCorrelationProtocol: W3C` so a `traceparent` reaches the backend; instrument the server with `azure-monitor-opentelemetry` (bundles FastAPI instrumentation, not Starlette), import order matters; then APIM and server requests share `OperationId`. https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-collect-detect
13. Server logging: write one JSON line per tool call to stdout with `mcp_session_id` (read from the request header in an ASGI middleware), tool name, JSON-RPC id and `traceparent`, then join `ContainerAppConsoleLogs | extend j = parse_json(Log)` to `ApiManagementGatewayMCPLog` on session ID and time window. https://learn.microsoft.com/azure/container-apps/migrate-logs-azure-monitor
14. ACA logging: environment `appLogsConfiguration.destination: azure-monitor` plus a diagnostic setting (ContainerAppConsoleLogs, ContainerAppSystemLogs) created at provisioning time; teach the unsuffixed table and column names; pre-provision at least 2 hours before class because of the 90-minute and 2-hour first-data delays. https://learn.microsoft.com/azure/container-apps/migrate-logs-azure-monitor
15. Identities: one UAMI on the container app with AcrPull on the ACR and Key Vault Secrets User on the vault, `AZURE_CLIENT_ID` env var set to its client ID, ACR `authentication-as-arm` enabled; APIM identity with Key Vault Secrets User for the named value. Assign roles before first token use (24-hour token cache). https://learn.microsoft.com/azure/container-apps/managed-identity-image-pull
16. Participant RBAC: Container Registry Tasks Contributor on the team ACR (AcrPush is not enough for `az acr build`), Container Apps Contributor (or Contributor) on the team container app for `az containerapp update --image`, Log Analytics Reader on the workspace. Note both Container Apps roles expose secret values. Validate in a pilot that the chosen roles succeed end to end. https://learn.microsoft.com/azure/container-registry/container-registry-rbac-built-in-roles-overview
17. Confirm the CloudLabs subscription is not funded by free credits (ACR Tasks paused) and keep ACR public network access enabled; keep a fallback lab path (local Docker build and push) in the instructor guide. https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview
18. Revision check commands for the lab: `az containerapp revision list -n <app> -g <rg> -o table`, `az containerapp show -n <app> -g <rg> --query properties.latestReadyRevisionName` (Inference: property name from the ARM model; verify output). https://learn.microsoft.com/azure/container-apps/revisions-manage

## Unverified or contradictory

- Which MCP protocol revision the Foundry Agent Service client uses (2026-07-28 or a handshake-era revision), whether it calls `initialize`, and whether it echoes `Mcp-Session-Id`. Not documented; must pilot. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Whether APIM MCP passthrough handles 2026-07-28 (sessionless) traffic and what `SessionId` / `gen_ai.conversation.id` contain for sessionless requests; APIM docs only state "2025-06-18 or later". https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Contradiction: expose-existing page says external servers support tools and resources; overview says APIM supports tools only, not resources or prompts. https://learn.microsoft.com/azure/api-management/mcp-server-overview
- Portal display name of the `GatewayMCPLogs` category and whether it is emitted for every tier (Developer, Basic v2) is not documented. https://learn.microsoft.com/azure/api-management/monitor-api-management-reference
- Whether the portal "MCP server base URL" should include `/mcp` (example uses `https://learn.microsoft.com/api/mcp`) versus the REST split of `serviceUrl` plus `uriTemplate` `/mcp`; inspect the created API with GET to confirm. https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api
- Whether `httpCorrelationProtocol` set on an MCP-type API diagnostic actually injects `traceparent` into passthrough backend calls; the enum is documented generically and AVM modules default it to `Legacy`. https://learn.microsoft.com/rest/api/apimanagement/diagnostic/create-or-update
- Whether the built-in `azuremonitor` logger and diagnostic exist automatically when APIM is deployed by ARM (REST sample references `/loggers/azuremonitor`). https://learn.microsoft.com/rest/api/apimanagement/diagnostic/create-or-update
- Whether `context.Variables` exposes MCP values other than `gen_ai.tool.name`; the documented example also contains a typo (`GetValueOrDefault<string>("gen_ai.tool.name",,"")`). https://learn.microsoft.com/azure/api-management/govern-mcp-server-products
- The expose-existing policy example omits the closing `</trace>` tag; do not copy it verbatim. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
- Container Apps Contributor lists `Microsoft.App/containerApps/*/write`, not `Microsoft.App/containerApps/write`; whether the wildcard covers updating the app itself is not stated. Also unverified whether updates of an app with a user-assigned identity require `Microsoft.ManagedIdentity/userAssignedIdentities/*/assign/action` (Managed Identity Operator). Test in pilot. https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/containers
- Microsoft ACA Python tutorial issues (Inference): the unpinned `mcp[cli]>=1.2.0` now installs 2.x (FastMCP import fails); FastMCP with default host 127.0.0.1 enables a localhost-only Host allow list on current 1.x (421 behind ACA); the FastAPI `/health` route is registered after `app.mount("/")`, so Starlette routing likely sends `/health` into the MCP sub-app (404). https://learn.microsoft.com/azure/container-apps/tutorial-mcp-server-python
- ACA troubleshooting curl samples omit the `Accept: application/json, text/event-stream` header that the spec requires; they may be rejected. https://learn.microsoft.com/azure/container-apps/mcp-troubleshooting
- Python SDK v2 docs disagree on the import path (`from mcp.server import MCPServer` on PyPI and What's New, `from mcp.server.mcpserver import MCPServer` in the migration guide) and on error shape (handling-errors says unhandled tool exceptions return `isError` results; What's New mentions sanitized `-32603` protocol errors). https://py.sdk.modelcontextprotocol.io/whats-new/
- Whether v1.30.0 implements any 2026-07-28 behavior (which would remove sessions for modern clients) is not documented. https://pypi.org/project/mcp/
- Community claim that ACR Tasks need Standard or Premium SKU is not in official docs (the official quick task tutorial uses Standard; no SKU restriction found). https://learn.microsoft.com/answers/a/12673159
- PyPI shows 2.0.1 dated Aug 26, 2026, after 2.1.0 (Aug 24); treat dates as reported. https://pypi.org/project/mcp/
- Dollar prices for Developer and Basic v2 were not retrievable from the pricing page (client-rendered). https://azure.microsoft.com/en-us/pricing/details/api-management/
- The MCP Inspector 0.9.0 tip in APIM docs may be stale relative to current Inspector releases. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
