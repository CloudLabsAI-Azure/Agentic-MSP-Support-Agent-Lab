# Research: API Management (Developer tier) as the MCP gateway, Container Apps hosting, Container Registry builds, Key Vault, logging, Blob export and Bicep

Research notes for the lab "Agentic MSP Support Agent Guided Lab" (Relecloud Managed Services). Researched on 2026-11-06 from Microsoft Learn (Learn MCP tools `microsoft_docs_search` and `microsoft_docs_fetch`, plus full-page fetches of Learn URLs), the Azure Retail Prices API and the official MCP specification site only. No blogs, forums, lab repos or third-party sites were used as sources of product facts.

This note replaces the note of 2026-10-01, which was written for API Management Basic v2. Every fact kept from it was re-read today. Sections of the old note on the MCP Python SDK and on Foundry Agent Service MCP connections were not re-verified and are dropped here; they belong to the MCP server and identity notes.

Conventions:

- **Bold** text is a UI label exactly as written in the cited page. Where pages disagree on a label, both spellings are given and the conflict is listed under OPEN QUESTIONS, the last section.
- [Sxx] is a source ID from section 0. Every statement carries at least one source ID. "Derived from" marks a design judgment built from cited facts; it is not a documented statement.
- [Pxx] is a project input (requirements or the previous build). Project inputs describe the plan, never product behavior.
- Status: **GA** means the page carries no preview label. **Preview** means the page labels it preview. **Retiring** means the page announces a retirement date.
- Page text is paraphrased. One short direct quote is used.

## 0. Sources

| ID | URL | Page title | Read on |
| - | - | - | - |
| S01 | https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server | Expose and govern an existing MCP server | 2026-11-06 |
| S02 | https://learn.microsoft.com/azure/api-management/mcp-server-overview | About MCP servers in Azure API Management | 2026-11-06 |
| S03 | https://learn.microsoft.com/azure/api-management/manage-mcp-servers-rest-api | Manage MCP servers programmatically in API Management | 2026-11-06 |
| S04 | https://learn.microsoft.com/azure/api-management/api-management-features | Feature-based comparison of the Azure API Management tiers | 2026-11-06 |
| S05 | https://learn.microsoft.com/azure/api-management/get-started-create-service-instance-cli | Quickstart: Create a new Azure API Management instance by using the Azure CLI | 2026-11-06 |
| S06 | https://learn.microsoft.com/azure/api-management/get-started-create-service-instance | Quickstart: Create a new Azure API Management instance by using the Azure portal | 2026-11-06 |
| S07 | https://learn.microsoft.com/azure/api-management/quickstart-bicep | Quickstart: Create a new Azure API Management instance by using Bicep | 2026-11-06 |
| S08 | https://learn.microsoft.com/azure/api-management/api-management-gateways-overview | API gateway in Azure API Management | 2026-11-06 |
| S09 | https://learn.microsoft.com/azure/api-management/service-limits | Understanding Azure API Management service limits | 2026-11-06 |
| S10 | https://learn.microsoft.com/azure/api-management/upgrade-and-scale | Upgrade and scale an Azure API Management instance | 2026-11-06 |
| S11 | https://learn.microsoft.com/azure/api-management/soft-delete | API Management soft-delete | 2026-11-06 |
| S12 | https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy | Validate Microsoft Entra token | 2026-11-06 |
| S13 | https://learn.microsoft.com/azure/api-management/validate-jwt-policy | Validate JWT | 2026-11-06 |
| S14 | https://learn.microsoft.com/azure/api-management/secure-mcp-servers | Secure access to MCP servers in API Management | 2026-11-06 |
| S15 | https://learn.microsoft.com/azure/api-management/monitor-mcp-servers | Monitor MCP server traffic in Azure API Management | 2026-11-06 |
| S16 | https://learn.microsoft.com/azure/api-management/how-to-server-sent-events | Configure API for server-sent events | 2026-11-06 |
| S17 | https://learn.microsoft.com/azure/api-management/set-header-policy | Set header | 2026-11-06 |
| S18 | https://learn.microsoft.com/azure/api-management/api-management-policy-expressions | API Management policy expressions | 2026-11-06 |
| S19 | https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaylogs | ApiManagementGatewayLogs | 2026-11-06 |
| S20 | https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaymcplog | ApiManagementGatewayMCPLog | 2026-11-06 |
| S21 | https://learn.microsoft.com/azure/api-management/monitor-api-management-reference | API Management monitoring data reference | 2026-11-06 |
| S22 | https://learn.microsoft.com/azure/api-management/monitor-api-management | Monitor API Management | 2026-11-06 |
| S23 | https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights | How to integrate Azure API Management with Azure Application Insights | 2026-11-06 |
| S24 | https://learn.microsoft.com/azure/api-management/diagnostic-logs-reference (this link now serves the REST reference "Diagnostic - Create Or Update", API version 2024-05-01) | Diagnostic - Create Or Update | 2026-11-06 |
| S25 | https://learn.microsoft.com/azure/api-management/trace-policy | Trace | 2026-11-06 |
| S26 | https://learn.microsoft.com/azure/api-management/api-management-howto-properties | Use named values in Azure API Management policies | 2026-11-06 |
| S27 | https://learn.microsoft.com/azure/api-management/api-management-howto-use-managed-service-identity | Use managed identities in Azure API Management | 2026-11-06 |
| S28 | https://learn.microsoft.com/azure/container-apps/revisions | Update and deploy changes in Azure Container Apps | 2026-11-06 |
| S29 | https://learn.microsoft.com/azure/container-apps/revisions-manage | Manage revisions in Azure Container Apps | 2026-11-06 |
| S30 | https://learn.microsoft.com/cli/azure/containerapp/revision | az containerapp revision | 2026-11-06 |
| S31 | https://learn.microsoft.com/azure/container-apps/traffic-splitting | Traffic splitting in Azure Container Apps | 2026-11-06 |
| S32 | https://learn.microsoft.com/azure/container-apps/blue-green-deployment?pivots=azure-cli | Blue-green deployment in Azure Container Apps | 2026-11-06 |
| S33 | https://learn.microsoft.com/azure/container-apps/billing | Billing in Azure Container Apps | 2026-11-06 |
| S34 | https://learn.microsoft.com/azure/container-apps/manage-secrets | Manage secrets in Azure Container Apps | 2026-11-06 |
| S35 | https://learn.microsoft.com/azure/container-apps/log-streaming | View log streams in Azure Container Apps | 2026-11-06 |
| S36 | https://learn.microsoft.com/azure/container-apps/migrate-logs-azure-monitor | Change Azure Container Apps logging from Log Analytics to Azure Monitor | 2026-11-06 |
| S37 | https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappconsolelogs | ContainerAppConsoleLogs | 2026-11-06 |
| S38 | https://learn.microsoft.com/azure/container-apps/log-options | Log storage and monitoring options in Azure Container Apps | 2026-11-06 |
| S39 | https://learn.microsoft.com/azure/container-apps/managed-identity | Managed identities in Azure Container Apps | 2026-11-06 |
| S40 | https://learn.microsoft.com/azure/container-apps/mcp-troubleshooting | Troubleshoot MCP servers on Azure Container Apps | 2026-11-06 |
| S41 | https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview | Automate container image builds and maintenance with Azure Container Registry tasks | 2026-11-06 |
| S42 | https://learn.microsoft.com/azure/container-registry/container-registry-skus | Azure Container Registry SKU features and limits | 2026-11-06 |
| S43 | https://learn.microsoft.com/azure/container-registry/container-registry-rbac-built-in-roles-overview | Azure Container Registry Microsoft Entra permissions and role assignments overview | 2026-11-06 |
| S44 | https://learn.microsoft.com/azure/key-vault/general/rbac-guide | Provide access to Key Vault keys, certificates, and secrets with Azure role-based access control | 2026-11-06 |
| S45 | https://learn.microsoft.com/azure/key-vault/general/logging | Azure Key Vault logging | 2026-11-06 |
| S46 | https://learn.microsoft.com/azure/azure-monitor/reference/tables/azkvauditlogs | AZKVAuditLogs | 2026-11-06 |
| S47 | https://learn.microsoft.com/azure/key-vault/general/monitor-key-vault | Monitor Azure Key Vault | 2026-11-06 |
| S48 | https://learn.microsoft.com/azure/key-vault/general/monitor-key-vault-reference | Azure Key Vault monitoring data reference | 2026-11-06 |
| S49 | https://learn.microsoft.com/azure/azure-monitor/reference/tables/azurediagnostics | AzureDiagnostics | 2026-11-06 |
| S50 | https://learn.microsoft.com/azure/key-vault/general/howto-logging | Enable Key Vault logging | 2026-11-06 |
| S51 | https://learn.microsoft.com/azure/azure-monitor/reference/queries/azkvauditlogs | Queries for the AZKVAuditLogs table | 2026-11-06 |
| S52 | https://learn.microsoft.com/azure/azure-monitor/platform/resource-logs | Resource logs in Azure Monitor | 2026-11-06 |
| S53 | https://learn.microsoft.com/azure/azure-monitor/logs/data-ingestion-time | Log data ingestion time in Azure Monitor | 2026-11-06 |
| S54 | https://learn.microsoft.com/azure/search/search-howto-managed-identities-storage | Connect to Azure Storage using a managed identity (Azure AI Search) | 2026-11-06 |
| S55 | https://learn.microsoft.com/azure/search/search-indexer-howto-access-trusted-service-exception | Make indexer connections to Azure Storage as a trusted service | 2026-11-06 |
| S56 | https://learn.microsoft.com/azure/storage/common/shared-key-authorization-prevent | Prevent Shared Key authorization for an Azure Storage account | 2026-11-06 |
| S57 | https://learn.microsoft.com/azure/storage/common/storage-network-security | Firewall rules and network access control for Azure Blob, Data Lake, Queue, and Table Storage | 2026-11-06 |
| S58 | https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-cli | Bicep CLI commands | 2026-11-06 |
| S59 | https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-config | Configure your Bicep environment | 2026-11-06 |
| S60 | https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-config-version | Configure Bicep compiler version requirements | 2026-11-06 |
| S61 | https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis?pivots=deployment-language-bicep | Microsoft.ApiManagement service/apis (template reference) | 2026-11-06 |
| S62 | https://learn.microsoft.com/azure/templates/microsoft.app/2026-07-01/containerapps?pivots=deployment-language-bicep (read the first 100,000 of 106,838 characters) | Microsoft.App containerApps 2026-07-01 (template reference) | 2026-11-06 |
| S63 | https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/projects/connections | Microsoft.CognitiveServices/accounts/projects/connections (template reference) | 2026-11-06 |
| S64 | https://learn.microsoft.com/azure/container-apps/environment | Azure Container Apps environments | 2026-11-06 |
| S65 | https://learn.microsoft.com/entra/identity-platform/access-token-claims-reference | Access token claims reference | 2026-11-06 |
| S66 | https://learn.microsoft.com/azure/container-registry/container-registry-quickstart-task-cli | Quickstart: Build and run a container image using Azure Container Registry Tasks | 2026-11-06 |
| S67 | https://learn.microsoft.com/azure/container-registry/container-registry-rbac-abac-repository-permissions | Azure ABAC repository permissions in Azure Container Registry | 2026-11-06 |
| S68 | https://learn.microsoft.com/azure/container-apps/managed-identity-image-pull | Azure Container Apps image pull from Azure Container Registry with managed identity | 2026-11-06 |
| S69 | https://learn.microsoft.com/azure/key-vault/general/access-control-default | Plan for Azure RBAC as the default access control model in Key Vault | 2026-11-06 |
| S70 | https://learn.microsoft.com/azure/api-management/api-management-howto-ip-addresses | IP Addresses of Azure API Management | 2026-11-06 |
| S71 | https://learn.microsoft.com/azure/container-apps/ip-restrictions | Set up IP ingress restrictions in Azure Container Apps | 2026-11-06 |
| S72 | https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs | Azure Monitor Logs cost calculations and options | 2026-11-06 |
| S73 | https://learn.microsoft.com/azure/templates/microsoft.insights/diagnosticsettings | Microsoft.Insights/diagnosticSettings (template reference) | 2026-11-06 |
| S74 | https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/namedvalues | Microsoft.ApiManagement/service/namedValues (template reference) | 2026-11-06 |
| S75 | https://modelcontextprotocol.io/specification/versioning | Versioning (Model Context Protocol specification) | 2026-11-06 |
| S76 | https://prices.azure.com/api/retail/prices (filters per service and region, currencyCode USD; raw JSON kept in the session scratchpad) | Azure Retail Prices API | 2026-11-06 |

Project inputs (plan, not product facts):

| ID | Location | What it is |
| - | - | - |
| P01 | SOW-v3-requirements.md (session scratchpad, sanitized SOW revision of 2026-11-06) | Binding requirements: Developer tier, per-participant tenant, logging and approval rules |
| P02 | setup/deploy-01.json | Previous build's ARM template (API Management Basic v2, single revision Container App, policies `agentPolicy` and `diagPolicy`) |
| P03 | research/research-apim-aca-mcp.md as of 2026-10-01 | The note this file replaces |
| P04 | Instructions/exercise-3.md, exercise-5.md, exercise-6.md | Current guide text for redeploy, secret handling and the end-to-end trace |

## 1. Status at a glance

| Feature | Status | Date or condition | Source |
| - | - | - | - |
| Expose an existing MCP server (pass-through) in API Management | GA | Applies to Developer, Basic, Basic v2, Standard, Standard v2, Premium, Premium v2; not Consumption; not in workspaces | S01, S02, S08 |
| Pass-through MCP server on the classic gateway (Developer runs the classic gateway) | GA | Classic gateway column is checked for pass-through MCP | S08 |
| MCP resources and prompts through API Management | Not supported (conflict on resources) | S01 says tools and resources are supported for external servers; S02 says tools only | S01, S02 |
| Managing MCP servers through REST, ARM or Bicep | Requires preview API version | API version 2025-09-01-preview or later; no GA API version of `service/apis` carries `mcpProperties` | S03, S61 |
| AI Gateway release channel (early MCP features) | Early access channel | Chosen in the instance's service update settings | S02 |
| `GatewayMCPLogs` category and `ApiManagementGatewayMCPLog` table | GA (no label) | Tier coverage not stated | S20, S21 |
| MCP telemetry in Application Insights (`gen_ai.*` dimensions) | GA (no label) | Needs an Application Insights logger | S15 |
| `emit-metric` custom metrics to Application Insights | Preview | Azure Monitor custom metrics are preview | S23 |
| API Management classic analytics dashboard | Retiring | March 2027 | S22 |
| Trusted service connectivity from the API Management gateway | Retired for the gateway | March 2026; control plane use continues | S27 |
| New service limits for Developer tier | Announced | Expected rollout date March 15, 2026 for Consumption, Developer, Basic, Basic v2 | S09 |
| Container Apps single and multiple revision modes | GA | GA API version 2026-07-01 allows `Single` and `Multiple` | S28, S62 |
| Container Apps deployment labels revision mode | Preview | Available only in preview API versions and the CLI extension (`--target-label` is preview) | S28, S30, S62 |
| `--max-inactive-revisions` | Preview | Container Apps CLI extension with preview features | S28 |
| Container Apps `log-analytics` log destination (HTTP Data Collector API) | Retired | Support ended September 14, 2026; critical security fixes only | S36 |
| Container Apps environment types | GA | Workload profiles is the default; Consumption only is legacy | S64 |
| ACR task runs on Azure free credits | Paused | Temporarily paused; no end date given | S41 |
| ACR ABAC-enabled role assignment mode | GA, becoming default | Will become the default mode in the future; not dated | S67 |
| `az acr pack build` | Preview | Not needed for this lab | S41 |
| Key Vault control plane API 2026-02-01 (Azure RBAC by default on create) | GA | API versions before 2026-02-01 retire February 27, 2027 | S69 |
| Key Vault ABAC conditions on secret data actions | Preview | Not needed for this lab | S44 |
| Bicep `bicep.version` compiler constraint | GA (no label) | Minimum compiler version not stated | S60 |
| `bicep snapshot` | GA (no label) | Bicep CLI v0.41.2 or newer | S58 |
| Cognitive Services `accounts/projects/connections` | GA and preview versions | Newest GA 2026-09-01; Latest is 2026-09-15-preview | S63 |
| MCP protocol current revision | Current | 2026-07-28; per-request version negotiation, no handshake; 2025-11-25 and earlier are handshake based | S75 |

Volatile facts checked today: API Management MCP support per tier (S01, S02, S08), the MCP management API version (S03, S61), the Key Vault API retirement date (S69), the Container Apps log destination retirement (S36), prices (S76) and the MCP protocol revision (S75).

## 2. Navigation and exact click paths

All paths start in the Azure portal.

| Page or task | Click path | What the page shows | Source |
| - | - | - | - |
| Create the MCP server in API Management | API Management instance > under **APIs** select **MCP servers** > **+ Create MCP server** > **Expose an existing MCP server** > **Backend MCP server**: **MCP server base URL**, **Transport type** (**Streamable HTTP** is the default) > **New MCP server**: **Name**, **Base path**, optional **Description** > **Products** (optional) > **Create** | The server appears in the **MCP Servers** pane; the **Server URL** column holds the client URL | S01 |
| Choose exposed tools | **MCP servers** > server > **Tools** blade | Operations exposed as tools | S01 |
| Edit MCP policies | **APIs** > **MCP Servers** > server > under **MCP** select **Policies** | XML policy editor; global (All APIs) policies run first | S01 |
| Log tool arguments and results | **APIs** > **MCP servers** > server > **Settings** > **Diagnostic Logs** > enable Frontend and Backend payload logging > **Save** | Adds `gen_ai.tool.call.arguments` and `gen_ai.tool.call.result` | S15 |
| Logging settings for all APIs | **APIs** > **APIs** > **All APIs** > **Settings** tab > **Diagnostic Logs** > **Azure Monitor** tab > **Save** | Sampling, verbosity, headers and payload bytes; set Frontend Response **Number of payload bytes to log** to 0 for MCP | S22, S01 |
| Send gateway logs to Log Analytics | **Monitoring** > **Diagnostic settings** > **+ Add diagnostic setting** > name > **Logs related to ApiManagement Gateway** > **Send to Log Analytics** > workspace > **Resource specific** > **Save** | The portal label of the MCP category is not documented | S22 |
| Query API Management logs | **Monitoring** > **Logs** | KQL editor scoped to the instance | S22 |
| Analytics dashboard | **Monitoring** > **Analytics** | Azure Monitor based dashboard; needs a workspace | S22 |
| Connect Application Insights | **Monitoring** > **Application Insights** > **+ Add** > instance > optional **Add availability monitor** > **Create** | The portal creates an instrumentation-key logger only | S23 |
| Enable Application Insights for an API | **APIs** > **APIs** > API or **All APIs** > **Settings** > **Diagnostics Logs** > **Enable** > **Destination** > **Sampling (%)** 100 > **Always log errors** > **Save** | Creates the `applicationinsights` diagnostic | S23 |
| Add a Key Vault named value | **APIs** > **Named values** > **+ Add** > **Name**, **Display name** > **Type** = **Key vault** > secret identifier without version, or **Select** > **Client identity** > **Save** > **Create** | Named value refreshed from Key Vault | S26 |
| Turn on the gateway identity | **Security** > **Managed identities** > **System assigned** tab > **Status** **On** > **Save**, or **User assigned** tab > **Add** | Identity used for Key Vault | S27 |
| Find the gateway public IP | Instance **Overview** | Public IP addresses | S70 |
| Create an instance (reference only) | **Create a resource** > **Integration** > **API Management** > **Basics** (**Pricing tier**, **Units**) > **Monitor + secure** > **Networking** > **Managed identity** > **Tags** > **Review + create** > **Create** | Creation time depends on tier | S06 |
| Revisions of a container app | Container app > **Revision management** (S31, S68); or **Application** > **Revisions and replicas** (S34) | Revision list, traffic and labels; conflict listed in OPEN QUESTIONS | S31, S34, S68 |
| Change the revision mode | **Revision management** > **Choose revision mode** > **Multiple: Several revisions active simultaneously** > **Apply** | **Revision Mode** shows **Multiple** | S31 |
| Split or move traffic | **Revision management** > **Show inactive revisions** > **Active** > **Traffic** percentages > **Save** | Traffic must total 100% | S31 |
| Create a revision in the portal | **Revision management** > **Create new revision** > **Name/Suffix** > **Create** | New revision | S31 |
| Stream container logs | Container app > **Monitoring** > **Log stream** > **Console** (or **System**) | Live stdout and stderr | S35 |
| Route environment logs to Azure Monitor | Environment > **Monitoring** > **Logging options** > **Logs Destination** = **Azure Monitor** > **Save**; refresh; **Monitoring** > **Diagnostic settings** > **Add diagnostic setting** > **Container App console logs** and **Container App system logs** (or **allLogs**) > **Send to Log Analytics workspace** > **Save** | `ContainerAppConsoleLogs` and `ContainerAppSystemLogs` | S36, S38 |
| Add a Key Vault reference secret | Container app > **Security** > **Secrets** > **Add** > **Type** = **Key Vault reference** > **Key Vault secret URL** > **Identity** > **Add** | App-level secret | S34 |
| Container app identity | **Security** > **Identity** (S34) or **Settings** > **Identity** (S39) | System and user-assigned tabs | S34, S39 |
| Restrict ingress to known IPs | Container app > **Networking** > **Ingress** > **IP Restrictions** > **Allow traffic from IPs configured below, deny all other traffic** > **Add** > **IPv4 address or range**, **Name**, **Description** > **Add** > **Save** | Allow rules | S71 |
| Diagnose a container app | Container app > **Diagnose and solve problems** | Detectors | S40 |
| Key Vault permission model | Key vault > **Settings** > **Access configuration** | **Permission model** | S26 |
| Key Vault role assignment | Key vault > **Access control (IAM)** > **Add role assignment** > **Role** > **Members** > **Managed identity** > **+ Select members** > **Review + assign** | Role assignments | S26 |
| Key Vault diagnostic setting | Key vault > **Diagnostic settings** > **Add diagnostic setting** > **Category groups** **audit** and **allLogs** > **Send to Log Analytics workspace** > **Save** | AuditEvent routing | S50 |
| Disable shared key access | Storage account > **Settings** > **Configuration** > **Allow storage account key access** = **Disabled** | Only Entra ID requests succeed | S56 |
| Storage network rules for the indexer | Storage account > **Security + networking** > **Networking** > **Public access** tab > **Manage** > **Public network access scope** = **Enable from selected networks** > **Exceptions** > **Allow trusted Microsoft services to access this resource** | Trusted service exception | S55 |
| AI Search system identity | Search service > **Settings** > **Identity** | System-assigned identity | S55 |
| Test the indexer connection | Search service > **Import data** > **Azure Blob Storage** > connection > **Authenticate using managed identity** > **System-assigned** > **Next** | Connection test | S55 |
| ACR role assignment mode | Registry > **Settings** > **Properties** > **Role assignment permissions mode** | RBAC only or RBAC plus ABAC | S67 |
| Query container logs | Log Analytics workspace > **Logs** (the environment's **Logs** menu is disabled when the destination is Azure Monitor) | `ContainerAppConsoleLogs` | S38 |

Older or alternate names still found in the documentation: **Revision management** (S31, S68) and **Revisions and replicas** (S34); **Security** > **Identity** (S34) and **Settings** > **Identity** (S39); **Diagnostic Logs** (S15, S22) and **Diagnostics Logs** (S23); **MCP servers** and **MCP Servers** (S01). Treat **Revision management** as current for traffic and modes because the traffic-splitting and image-pull pages, which describe those controls, both use it (S31, S68); confirm both labels in the pilot.

## 3. API Management Developer tier as the MCP gateway

### 3.1 Verdict: the Developer tier can host the MCP API

- The pages on exposing an existing MCP server, on MCP support in general and on securing MCP servers all list Developer in their APPLIES TO line [S01, S02, S14]. The availability section names the classic tiers Developer, Basic, Standard and Premium and the v2 tiers [S02].
- The gateway feature table checks pass-through MCP and REST-as-MCP for the classic gateway, which serves the Developer tier [S08].
- Limits that still apply: the external server must follow MCP 2025-06-18 or later, use Streamable HTTP or SSE, and use no authorization or standards-compliant authorization [S01]; MCP server capabilities are not supported in workspaces [S01, S02], and the Developer tier has no workspaces anyway [S04].
- The current MCP revision is 2026-07-28, which negotiates the version per request with no initialize handshake; 2025-11-25 and earlier are handshake based [S75]. The API Management pages only require 2025-06-18 or later [S01], so behavior with sessionless 2026-07-28 traffic must be piloted (OPEN QUESTIONS).
- Closest alternative if the binding architecture ever changed: Basic v2 deploys in a few minutes [S06], has an SLA and scales [S10], but runs on shared infrastructure with no dedicated IP [S70]. The SOW binds the Developer tier [P01], so this is not recommended.

### 3.2 Developer tier facts that shape the lab

| Fact | Value | Source |
| - | - | - |
| Purpose and SLA | For nonproduction use and evaluation; no SLA | S04, S10 |
| Create and activate time | 30 to 40 minutes (CLI, Bicep and ARM quickstarts) | S05, S07 |
| Status while provisioning | `Activating`, then `Online` with gateway address and public IP (`az apim show`) | S05 |
| Scale | 1 unit; cannot add or remove units; no autoscale | S04, S10 |
| Infrastructure changes | 15 minutes or longer; only the Developer tier has gateway downtime during them; scaling to or from Developer has downtime | S10 |
| Built-in cache | 10 MB | S04 |
| Static, exclusive public IP | Yes; static for the life of the service with listed exceptions (delete and re-create, subscription disabled and reinstated, VNet changes) | S70 |
| Outbound source IP to a public backend | The public IP is the origin of the request | S70 |
| Concurrent backend connections per HTTP authority | 1,024 in Developer (2,048 per unit in other classic tiers) | S08 |
| Request payload, buffered payload, total duration | Unlimited, 500 MiB, unlimited (classic gateway) | S08 |
| Request or response payload in diagnostic logs | 8,192 bytes | S08 |
| Named value length | 4,096 characters | S08 |
| Resource limits (2026 update) | 3,000 API operations, 1,500 tags, 5,000 named values, 100 loggers, 100 products, 10,000 subscriptions, 20,000 users, 10 user-assigned identities, 5 self-hosted gateways | S09 |
| Limit increases | Considered only for Standard, Standard v2, Premium, Premium v2 | S09 |
| Gateway capacity throttling | Can return HTTP 429 to protect capacity | S09 |
| Health endpoint | `/status-0123456789abcdef` returns 200 when the gateway is healthy | S08 |
| Name | Must be unique within Azure; cannot be changed; default domain `<name>.azure-api.net` | S05, S06 |
| Soft-delete | Deleted instances stay soft-deleted for 48 hours; the name cannot be reused meanwhile, and cannot be reused in another subscription for several days or longer even after purge; purge with `az apim deletedservice purge` needs subscription-scope permissions | S11 |

### 3.3 MCP API resource model (REST, ARM, Bicep)

- An MCP server is an API Management API with type `mcp`; a pass-through server declares the backend URL and the transport; tools are `apis/tools` sub-resources (REST-backed servers only); policies are `apis/policies`; product binding is a separate `products/{productId}/apis/{mcpServerId}` relationship [S03].
- Pin API version 2025-09-01-preview or later in every request [S03]. The template reference lists 2025-09-01-preview as Latest and 2024-05-01 as the newest GA version; `type` and `apiType` include `mcp`; `mcpProperties.transportType` is `sse` or `streamable`; `McpEndpoint.uriTemplate` must start with `/` [S61].
- Streamable transport needs exactly one endpoint named `message`; SSE needs two (`sse`, `message`); a wrong transport or a `uriTemplate` without a leading `/` returns 400 [S03].
- PUT is asynchronous (`provisioningState: InProgress`, poll `Azure-AsyncOperation`); `If-Match: *` makes PUT and DELETE idempotent; a DELETE without `If-Match` returns 412 [S03].
- The docs show complete ARM and Bicep templates for a pass-through server with a policy and a product binding; the Azure CLI section calls the REST API with `az rest`, and Terraform needs `azapi_resource` because the AzureRM provider has no MCP resource yet [S03].
- Client URL example: `https://<apim-service-name>.azure-api.net/<api-name>-mcp/mcp`; copy the value from the **Server URL** column [S01]. Derived from [S01, S61]: with `path` `servicedesk` and `uriTemplate` `/mcp` the URL is expected to be `https://<apim>.azure-api.net/servicedesk/mcp`; confirm on the first deployment.
- `subscriptionRequired` is a property of the API [S61]; the documented pass-through template sets it to `true` [S03]. Derived: set it to `false` when the gateway authenticates with Entra tokens and no subscription key is used.

Documented pass-through MCP server in Bicep, abbreviated from [S03]:

```bicep
resource mcpServer 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apimService
  name: mcpServerId
  properties: {
    type: 'mcp'
    displayName: 'External MCP Server'
    path: mcpServerId
    protocols: [ 'https' ]
    serviceUrl: backendUrl
    subscriptionRequired: true
    mcpProperties: {
      transportType: 'streamable'
      endpoints: [ { name: 'message', uriTemplate: '/mcp' } ]
    }
  }
}
```

### 3.4 Managed identity and Key Vault named values

- An instance can have one system-assigned and several user-assigned identities [S27]; the Developer tier allows up to 10 user-assigned identities [S09].
- Named value types are **Plain**, **Secret** and **Key vault** [S26]. A Key Vault named value needs an instance identity with **Key Vault Secrets User** (RBAC model) or Get and List (access policy model) [S26].
- Enter the secret identifier without a version so rotation works; updates reach API Management within four hours, or refresh manually; secrets must be 1 to 4,096 characters [S26]. In ARM, `keyVault.identityClientId` is null for the system identity or the client ID of a user-assigned identity, and a versioned `secretIdentifier` prevents auto-refresh [S74].
- With the Key Vault firewall on, only the system-assigned identity works and **Allow trusted Microsoft services to bypass this firewall** must be enabled [S26, S27].
- Whoever can edit policies can read any named value through `{{name}}`, and Key Vault values are visible to users who can trace requests [S26]. Policy editors can also use `authentication-managed-identity` to act as the instance identity [S27].

### 3.5 Token validation: `validate-azure-ad-token` and `validate-jwt`

- `validate-azure-ad-token` validates Entra tokens; use `validate-jwt` for other issuers [S12, S13]. Both apply to all tiers, run in the inbound section at global, workspace, product, API or operation scope, and return 401 by default [S12, S13].
- `validate-azure-ad-token` attributes: `tenant-id` (required, policy expressions allowed), `header-name` (default `Authorization`), `query-parameter-name`, `token-value`, `failed-validation-httpcode`, `failed-validation-error-message`, `output-token-variable-name` [S12].
- Elements: `client-application-ids` (each value tried until one matches; if absent, specify audiences), `audiences`, `required-claims` with `claim` `name`, `match` (`all` default, or `any`) and `separator` for multi-valued claims, `backend-application-ids`, `decryption-keys` [S12].
- `validate-jwt` adds `openid-config` (keys cached one hour, refetched at most every 5 minutes), `issuers`, `require-scheme`, `clock-skew` and `require-expiration-time` [S13]. `validate-jwt` is on the list of policies whose OpenID metadata calls appear as dependency telemetry in Application Insights [S23].
- Claims to check, from the token reference [S65]:
  - `aud`: in v2.0 tokens always the client ID of the API; in v1.0 tokens the client ID or the resource URI the client asked for; always validate it.
  - `azp` (v2.0) or `appid` (v1.0): the client application ID; usable in authorization decisions.
  - `scp`: space-separated delegated scopes, only in user tokens.
  - `roles`: app roles; for application tokens (client credentials) they replace scopes.
  - `oid` (stable object ID of the caller), `tid` (tenant), `ver` (`1.0` or `2.0`), `preferred_username` (v2.0, mutable, never for authorization), `upn` (v1.0 optional claim, display only).
- Derived from [S12, S65]: for the user-delegated path in the SOW token flow [P01], list both audience forms (App ID URI and client ID) because the token version decides which appears, put the calling client in `client-application-ids`, and require the gateway scope in `scp` with `match="any"` and `separator=" "`. For an app-only path, require an app role in `roles` instead, since app tokens carry no `scp`.

### 3.6 Correlation ID: `context.RequestId`, `set-header` and an incoming `x-correlation-id`

- `context.RequestId` is a `Guid` unique request identifier; `context.Request.Headers.GetValueOrDefault(name, default)` returns the comma-separated header values or the default; `context.Variables.GetValueOrDefault<T>` reads variables; `System.Guid` members are allowed in expressions; multi-statement expressions use `@{ ... }` and every path must `return` [S18]. The documented sample uses `TryGetValue(..., out value)` inside a multi-statement expression [S18].
- `set-header` works in inbound, outbound, backend and on-error, on all gateways; `exists-action` is `override` (default), `skip`, `append` or `delete`; `Connection`, `Content-Length`, `Keep-Alive` and `Transfer-Encoding` cannot be changed [S17].
- The MCP overview recommends correlation IDs in request headers to track requests across systems [S02]. API Management also forwards request headers to MCP tool invocations, with unnamed exclusions [S14].
- `trace` writes a property into the resource log entry and a Trace item in Application Insights when its severity is at or above the diagnostic verbosity, and is not affected by Application Insights sampling [S25]; the gateway table stores trace output in `TraceRecords` [S19].
- Nothing in the documentation states that `ApiManagementGatewayLogs.CorrelationId` equals `context.RequestId`. The current guide assumes it [P04]; the pilot must confirm it (OPEN QUESTIONS).

Derived inbound and outbound pattern (each element documented in [S12, S17, S18, S25, S26]; the combination is untested). It honors a well-formed incoming `x-correlation-id`, otherwise uses the gateway request ID, and recomputes the same value in outbound because the expression is deterministic:

```xml
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{tenant-id}}" header-name="Authorization"
        failed-validation-httpcode="401" failed-validation-error-message="Unauthorized"
        output-token-variable-name="jwt">
      <client-application-ids>
        <application-id>{{caller-client-id}}</application-id>
      </client-application-ids>
      <audiences>
        <audience>{{gateway-app-id-uri}}</audience>
        <audience>{{gateway-client-id}}</audience>
      </audiences>
      <required-claims>
        <claim name="scp" match="any" separator=" ">
          <value>{{gateway-scope}}</value>
        </claim>
      </required-claims>
    </validate-azure-ad-token>
    <set-header name="x-correlation-id" exists-action="override">
      <value>@{
        Guid parsed;
        string incoming = context.Request.Headers.GetValueOrDefault("x-correlation-id", "");
        return Guid.TryParse(incoming, out parsed) ? parsed.ToString() : context.RequestId.ToString();
      }</value>
    </set-header>
    <set-header name="x-backend-key" exists-action="override">
      <value>{{mcp-backend-key}}</value>
    </set-header>
    <trace source="mcp-gateway" severity="information">
      <message>@(context.RequestId.ToString())</message>
      <metadata name="caller-oid" value="@(((Jwt)context.Variables["jwt"]).Claims.GetValueOrDefault("oid", ""))" />
    </trace>
  </inbound>
  <backend><base /></backend>
  <outbound>
    <base />
    <set-header name="x-correlation-id" exists-action="override">
      <value>@{
        Guid parsed;
        string incoming = context.Request.Headers.GetValueOrDefault("x-correlation-id", "");
        return Guid.TryParse(incoming, out parsed) ? parsed.ToString() : context.RequestId.ToString();
      }</value>
    </set-header>
  </outbound>
  <on-error><base /></on-error>
</policies>
```

Design notes, derived from [S14, S18, P01]: accept only GUIDs from callers so a client cannot inject arbitrary text into logs; the SOW's 10-minute duplicate suppression keys on the correlation ID [P01], so if the agent does not send its own ID on a retry, every HTTP request gets a new ID and the MCP server needs another idempotency key (OPEN QUESTIONS). If the MCP server exchanges the user's token on behalf of the user, the gateway must keep `Authorization` (the forwarding pattern is in [S14]); if it uses Dataverse impersonation with an application user, the gateway can delete `Authorization` and pass validated claims as headers, as the previous build did [P02]. That choice belongs to the identity note.

### 3.7 Policies to avoid in an MCP API

| Avoid | Why | Source |
| - | - | - |
| Reading `context.Response.Body` in MCP-scope policies | Triggers response buffering and breaks streaming | S01, S15 |
| Logging response bodies at the All APIs scope | Must set Frontend Response **Number of payload bytes to log** to 0; streaming fails otherwise | S01 |
| Policies that buffer responses, for example `validate-content` | Buffering breaks event streams | S16 |
| Response caching | Delays notifications; disable for SSE APIs | S16 |
| `forward-request` with buffering | Use `buffer-response="false"` for SSE backends | S16 |
| Body transformations on the response (for example `set-body`) | Derived: they read the response body, which the first row forbids | S01 |

The one direct quote in this note: "Don't access the response body by using the `context.Response.Body` variable within MCP server policies." [S01]. The overview still lists caching among MCP governance options [S02], which conflicts with [S16] (OPEN QUESTIONS). Documented safe examples at MCP scope: `rate-limit-by-key` keyed on the caller IP and `trace` with metadata [S01], `validate-azure-ad-token` [S14] and `rate-limit` [S03].

### 3.8 Protecting the Container App behind the gateway (derived)

- Developer instances have a static, exclusive public IP that is the origin of requests to public backends [S70], and Container Apps ingress can allow only listed CIDR ranges (all rules must be the same type; no rules means all traffic is allowed) [S71].
- Derived from [S70, S71, P02]: allow only the gateway IP (as a `/32`) on the MCP app's ingress and keep the gateway-injected backend key from Key Vault as a second check. Consequence: the lab VM can no longer open the app URL directly (the current guide opens `/health` in Edge [P04]); either add the VM's public IP as a second allow rule or route that check through the gateway.

## 4. API Management diagnostics in the Developer tier

### 4.1 Resource logs and tables

| Category | Table | Costs to export | Basic plan | DCR transformation | Source |
| - | - | - | - | - | - |
| `GatewayLogs` | `ApiManagementGatewayLogs` | No | Yes | Yes | S21, S19 |
| `GatewayMCPLogs` | `ApiManagementGatewayMCPLog` (gateway logs for MCP requests) | Yes | Yes | No | S21, S20 |
| `GatewayLlmLogs` | `ApiManagementGatewayLlmLog` | Yes | Yes | Yes | S21 |
| `WebSocketConnectionLogs` | `ApiManagementWebSocketConnectionLogs` | Yes | Yes | No | S21 |
| `DeveloperPortalAuditLogs` | `APIMDevPortalAuditDiagnosticLog` | Yes | Yes | Yes | S21 |

- Azure Monitor and Log Analytics request logs are available in the Developer tier (not in Consumption) [S04, S08].
- Choose **Resource specific** as the destination table [S22]; API Management is one of the services that can use either AzureDiagnostics or resource-specific mode depending on the diagnostic setting [S49]. In ARM, `logAnalyticsDestinationType: Dedicated` selects resource-specific tables and null means AzureDiagnostics; the Latest API version of `Microsoft.Insights/diagnosticSettings` is 2021-05-01-preview [S73].
- A diagnostic setting can fail if the instance's `MinApiVersion` is set higher than 2022-09-01-preview [S22].
- Log entries sent to Azure Monitor are limited to 32 KB; logged request or response payloads can be up to 8,192 bytes each; oversize entries lose all body and trace content [S22].
- Latency: a new Log Analytics workspace can take up to 2 hours to start receiving data, an existing one about 15 minutes [S22]. In general, resource logs reach Log Analytics in 3 to 10 minutes end to end [S53], and resource logs are not completely lossless [S52].

### 4.2 Fields that carry the correlation and request IDs

`ApiManagementGatewayLogs` has these fields [S19]: `TimeGenerated`, `CorrelationId`, `ApiId`, `OperationId`, `OperationName`, `Method`, `Url`, `ResponseCode`, `BackendResponseCode`, `BackendUrl`, `BackendTime`, `TotalTime`, `ClientTime`, `CallerIpAddress`, `RequestHeaders`, `BackendRequestHeaders`, `ResponseHeaders`, `BackendResponseHeaders`, `TraceRecords` (records emitted by trace policies), `LastErrorReason`, `LastErrorMessage`, `IsRequestSuccess`, `ProductId`, `UserId`, `ApimSubscriptionId`.

`ApiManagementGatewayMCPLog` has these fields [S20]: `TimeGenerated` (request start), `CorrelationId` (matches the same field in `ApiManagementGatewayLogs`), `SessionId` (AI conversation or agent chat session), `Method` (for example `tools/call`), `ToolName`, `ToolCount`, `ServerName`, `ServerVersion`, `ClientName`, `ClientVersion`, `ProtocolVersion`, `TransportType`, `AuthenticationMethod` (`oauth2`, `api_key`, `cert` or `none`), `ApiType` (pass-through or MCP backend), `McpServerEndpoint`, `Error`, `ErrorType`, `Region`, `OperationName`.

- Headers appear in `RequestHeaders` and `BackendRequestHeaders` only when named in the Azure Monitor diagnostic: `frontend` and `backend`, each with `request` and `response` objects holding a `headers` array and `body.bytes` (maximum 8192); the diagnostic also has `verbosity` (`verbose`, `information`, `error`), `sampling` and `alwaysLog` [S24]. Derived from [S19, S24]: log `x-correlation-id` on the frontend request and the backend request so the ID is visible even if `CorrelationId` turns out to differ from it.
- The REST sample's `loggerId` is `/loggers/azuremonitor` [S24]; whether that logger and diagnostic exist by default after an ARM deployment is not documented (OPEN QUESTIONS).

### 4.3 Application Insights integration

- The portal connects Application Insights only with an instrumentation key; for a connection string with a managed identity, create the `Microsoft.ApiManagement/service/loggers` resource through REST, Bicep or ARM (`credentials.connectionString`, `credentials.identityClientId`) and give the identity **Monitoring Metrics Publisher** on the Application Insights resource [S23].
- Telemetry: a request item per incoming request, dependency items for `forward-request`, `validate-jwt`, `authentication-managed-identity`, `send-request` and other listed policies, exception items for failures, and trace items from `trace` [S23].
- For every MCP request a `requests` row with `gen_ai.*` dimensions is written: `gen_ai.operation.name`, `gen_ai.conversation.id` (MCP session ID), `network.protocol.name`, `network.protocol.version`, `auth.type`, `user_agent.name`, `user_agent.version`, `service.name`, `service.version`, `api.type` (`Mcp`), `error.message`, `error.type`; `tools/list` adds `ToolCount`; `tools/call` adds `gen_ai.tool.name` and `gen_ai.tool.type`, plus arguments and results only when payload logging is on [S15]. Custom data such as a correlation ID goes in through `trace` at MCP scope [S15].
- `httpCorrelationProtocol` is `None`, `Legacy` (injects `Request-Id` and `Request-Context`) or `W3C` (injects Trace Context headers) [S24].
- At more than 1,000 requests per second, logging cut throughput by 40 to 50 percent in internal tests; the guidance is to sample and to skip headers and bodies [S23]. Derived: one participant per instance stays far below that rate.

### 4.4 Correlation query (derived)

Built only from the columns in [S19, S20, S37]; the header test protects against the open question in section 3.6:

```kusto
let id = "<correlation ID>";
union isfuzzy=true
  (ApiManagementGatewayLogs
   | where TimeGenerated > ago(1d)
   | where CorrelationId == id or tostring(BackendRequestHeaders) has id
   | project TimeGenerated, Hop = "gateway", CorrelationId, Method, Url, ResponseCode, BackendResponseCode, TotalTime, BackendTime),
  (ApiManagementGatewayMCPLog
   | where TimeGenerated > ago(1d) and CorrelationId == id
   | project TimeGenerated, Hop = "gateway MCP", CorrelationId, Method, ToolName, ClientName, AuthenticationMethod, Error),
  (ContainerAppConsoleLogs
   | where TimeGenerated > ago(1d) and Log has id
   | project TimeGenerated, Hop = "MCP server", RevisionName, ContainerImage, Log)
| order by TimeGenerated asc
```

## 5. Container Apps (Consumption) hosting the MCP server

### 5.1 Environment, plan and billing

- The default environment type is **Workload profiles**; **Consumption only** is legacy and has no environment cost, while the Dedicated plan adds a fixed management cost [S64]. Features such as private endpoints and planned maintenance carry a Dedicated Plan Management charge on any plan [S33].
- Consumption billing is per second for vCPU and memory plus HTTP requests; per subscription and calendar month, the first 180,000 vCPU-seconds, 360,000 GiB-seconds and 2 million requests are free [S33].
- When a revision has a minimum replica count above zero and runs at that minimum, a replica whose containers are running, that is not processing requests, uses less than 0.01 vCPU and receives under 1,000 bytes per second is billed at the idle rate; replicas above the minimum are billed at the active rate; inactive revisions are not billed [S33, S28]. Health probe requests are not billable [S33].
- Cold start after scale to zero takes 10 to 30 seconds; the fix is `--min-replicas 1` [S40]. `maxReplicas` defaults to 10 when not set [S62].
- A container app name must be lowercase alphanumeric or `-`, start with a letter, end with an alphanumeric character, avoid two consecutive hyphens and be under 32 characters [S30].
- Environments idle for more than 90 days are deleted automatically [S64].

### 5.2 Revisions and revision modes

- Revisions are immutable snapshots; changes under `properties.template` (image, containers, scale, revision suffix) create a revision, changes under `properties.configuration` (secrets, revision mode, ingress, traffic, labels, registries) do not [S28].
- **Single** (default): the new revision is provisioned and scaled; traffic moves only when it is ready; if the update fails, traffic stays on the old revision; old revisions are deprovisioned automatically [S28].
- A revision is ready when it is provisioned, scaled to the previous replica count within its own min and max, and all replicas passed startup and readiness probes [S28]. No duration is documented.
- **Multiple**: several active revisions, traffic weights by revision name or label, and manual activation and deactivation [S28, S31]. With a traffic rule `latestRevision: true`, traffic waits until the latest revision is ready [S28].
- **Deployment labels** is a preview mode [S28]; GA API version 2026-07-01 accepts only `Multiple` and `Single` for `activeRevisionsMode` [S62]; the CLI extension's `set-mode` adds `labels` with a preview `--target-label` [S30].
- Provisioning states: Provisioning, Provisioned, Provisioning failed; running states include Activating, Activation failed, Running, Degraded and Failed [S28].
- Up to 100 inactive revisions are kept; the oldest are purged beyond that [S28].
- Revision name format conflict: [S28] joins the app name and the suffix with one hyphen (`<CONTAINER_APP_NAME>-<REVISION_SUFFIX>`), while the blue-green commands and Bicep [S32] join them with two hyphens. Suffix rules: lowercase alphanumeric or `-`, start with a letter, end alphanumeric, no two consecutive hyphens, 64 characters at most [S28].
- Changing the revision mode does not create a revision [S29].

### 5.3 Rollback methods

| Method | Commands | Effect | Source |
| - | - | - | - |
| A. New revision from the previous one (single mode) | `az containerapp revision copy -n <app> -g <rg> --from-revision <previous-revision>` (default is the latest revision; `--image`, `--revision-suffix`, scale and env flags allowed); or `az containerapp update -n <app> -g <rg> --image <acr>.azurecr.io/mcp-server:<previous-tag>` | A new revision is provisioned; the current one keeps serving until it is ready | S29, S30, S28 |
| B. Move traffic back (multiple mode) | `az containerapp ingress traffic set -n <app> -g <rg> --revision-weight <old-revision>=100` (or `--label-weight blue=100 green=0`) | Application-scope change; no new revision; both revisions stay active and billed | S31, S32, S28, S33 |
| C. Activate an inactive revision | `az containerapp revision activate -g <rg> --revision <name>` | Documented for multiple mode; single-mode behavior not stated | S30, S28 |

- Supporting commands: `az containerapp revision list -n <app> -g <rg> -o table` (`--all` shows inactive revisions), `az containerapp revision show`, `restart`, `deactivate`, `set-mode --mode single|multiple`, `revision label add|remove|swap` [S29, S30].
- Derived recommendation from [S28, S29, S30, S31, S33, P04]: keep **Single** mode and teach method A with `--from-revision`, which matches the current guide and scripts and keeps one billed replica; offer method B only as a demo, because it needs multiple mode, an explicit revision suffix and two active revisions. Do not use the preview labels mode.

### 5.4 Secrets, Key Vault and managed identity at startup

- Container Apps can reference a Key Vault secret (`configuration.secrets[]` with `name`, `keyVaultUrl`, `identity` = user-assigned resource ID or `system`) after the app identity gets **Key Vault Secrets User** [S34, S62]. A versionless URI is refreshed within 30 minutes, and active revisions that use it in environment variables restart [S34]. Secret changes never create a revision; restart or redeploy [S34].
- The system identity cannot be used for a Key Vault reference in `az containerapp create`, because it does not exist yet [S34].
- **Container Apps Contributor** and **Container Apps Operator** can read secret values through `Microsoft.App/containerApps/*/action`, which matches `listSecrets` [S34]. Derived from [S34, P02]: reading the backend credential in code from Key Vault through the managed identity, as the previous build does, keeps it out of the app's secret list that participants can read.
- Identity endpoint: `IDENTITY_ENDPOINT` and `IDENTITY_HEADER`; for a user-assigned identity pass `client_id`, `principal_id` or `mi_res_id`, otherwise the system identity is attempted; with the Azure Identity library the user-assigned client ID must be set explicitly [S39].
- Managed identity back ends cache tokens per resource for about 24 hours and forced refresh is not supported, so role assignments must exist before the first token request [S39].
- Adding, removing or changing an identity on a running app does not restart it or create a revision [S39]. `identitySettings[].lifecycle` (`All`, `Init`, `Main`, `None`) limits where an identity is usable, for example `None` for an image-pull-only identity [S39, S62].
- Image pull with a managed identity: the registry must allow ARM audience tokens (`az acr config authentication-as-arm show|update`), the identity needs `AcrPull`, the registry entry uses `identity` = user-assigned resource ID or `system`, and the image pull policy is always [S68, S62].

### 5.5 Logs

- Live: `az containerapp logs show -n <app> -g <rg> --type console|system --tail <0-300> --follow`, with `--revision`, `--replica` and `--container` for a specific container; the default tail is 20 [S35]. The portal stream is **Monitoring** > **Log stream** [S35].
- Stored: set the environment log destination to `azure-monitor` and add a diagnostic setting; logs then land in `ContainerAppConsoleLogs` and `ContainerAppSystemLogs` with unsuffixed columns [S36, S38]. The `log-analytics` destination uses the HTTP Data Collector API, whose support ended September 14, 2026 [S36].
- A diagnostic setting can take up to 90 minutes to start sending data; a resource can have five settings; Azure Monitor is not available for Express environments; `dynamicJsonColumns` is not supported, so parse JSON with `parse_json(Log)` [S36]. Logs arrive several minutes after they are written; use log streaming for real time [S38].
- With the Azure Monitor destination, the environment's **Logs** menu is disabled; query the workspace [S38].
- `ContainerAppConsoleLogs` columns: `TimeGenerated`, `ContainerAppName`, `RevisionName`, `ContainerName`, `ContainerImage`, `ContainerGroupName`, `ContainerGroupId`, `ContainerId`, `EnvironmentName`, `Stream`, `Log`, `Location` [S37].
- Diagnostic categories at environment level: `ContainerAppConsoleLogs`, `ContainerAppSystemLogs`, or the groups `allLogs` and `audit`; at container app level only `AllMetrics` [S38].

### 5.6 Probes

- Default startup and liveness probes send HTTP GET to the container port, which MCP endpoints usually reject; add a `GET /health` endpoint and point the probes at it [S40]. Probe types are `Liveness`, `Readiness` and `Startup` [S62].
- Port mismatch gives 502; a FastMCP app mounted at `/mcp` ends up at `/mcp/mcp` [S40].

## 6. Container Registry Basic and ACR Tasks

- `az acr build --image <repo>:<tag> --registry <name> --file Dockerfile .` sends the local context to the registry, builds in Azure and pushes the image; no local Docker engine is needed [S41, S66]. Default platform is Linux AMD64 [S41].
- Task runs from Azure free credits are temporarily paused, which can affect existing runs [S41]. Command-line values can appear in ACR diagnostic tracing, so never pass secrets as arguments [S41].
- Documented build time: a one-line `FROM mcr.microsoft.com/hello-world` build and push reported success after 10 seconds [S66]. No time is documented for a Python image with dependency installs (pilot).
- Basic includes 10 GiB storage and 2 webhooks; private endpoints, IP network rules and dedicated agent pools for Tasks are Premium only; no Tasks restriction is listed for Basic [S42].
- Registry role mode: in **RBAC Registry Permissions** mode use `AcrPull`, `AcrPush` and **Container Registry Tasks Contributor** (quick builds with `az acr build`, task logs, no data plane) [S43]. In **RBAC Registry + ABAC Repository Permissions** mode, `AcrPull`, `AcrPush` and `AcrDelete` are not honored; use **Container Registry Repository Reader**, **Writer** or **Contributor**, and quick builds need `--source-acr-auth-id [caller]` because they lose default data plane access [S67, S66].
- ABAC mode will become the default in the future; the mode is set at creation with `az acr create --role-assignment-mode 'rbac-abac'` or changed with `az acr update`; `az acr show --query "roleAssignmentMode"` shows it [S67]. Derived from [S67]: set the mode explicitly in the template so a default change cannot silently break `AcrPull` and quick builds.

## 7. Azure Key Vault

### 7.1 Roles and permission model

| Role | What it allows | ID | Source |
| - | - | - | - |
| Key Vault Secrets User | Read secret contents | 4633458b-17de-408a-b874-0445c86b69e6 | S44 |
| Key Vault Reader | Read metadata of vaults and their secrets, keys and certificates; cannot read secret values | 21090545-7ca7-4776-b22c-e363652d74d2 | S44 |
| Key Vault Secrets Officer | Any action on secrets except managing permissions | b86a8fe4-44ce-4948-aee5-eccb2c155cd7 | S44 |
| Key Vault Data Access Administrator | Add or remove assignments of the Key Vault data roles, with an ABAC condition | 8b54135c-b56d-4d72-a534-26097cfdc8d8 | S44 |

- These data roles work only with the Azure RBAC permission model; `Key Vault Contributor` is control plane only, and a control plane Contributor can grant itself data access through access policies [S44].
- Creating a vault with API version 2026-02-01 or later defaults to Azure RBAC (`enableRbacAuthorization = true`); existing vaults keep their model; all control plane API versions before 2026-02-01 retire February 27, 2027; Azure CLI 2.90.0 or later supports the new version [S69]. The previous build uses 2023-07-01 [P02], so the Bicep must move to 2026-02-01 or later (derived from [S69]).
- Microsoft recommends one vault per application per environment with roles at vault scope [S44]. Allow several minutes for role assignments to take effect in the portal [S44].

### 7.2 Diagnostic logs

- `AuditEvent` is the access logging category [S45, S50]; the monitoring reference also lists `AzurePolicyEvaluationDetails` for vaults [S48]. `AuditEvent` records authenticated requests, failed requests, vault operations and unauthenticated 401s [S50].
- Table conflict: the monitoring reference lists `AZKVAuditLogs` among the Key Vault tables but shows `AzureDiagnostics` as the table of `AuditEvent` [S48]; the AzureDiagnostics page lists Key Vault among services that use Azure diagnostics mode and not among those that support both modes [S49]; yet `AZKVAuditLogs` has its own schema and sample queries [S46, S51]. The resource logs page says most resources write in one mode without a choice and some let you choose [S52]. The current guide queries `AZKVAuditLogs` [P04]; pilot which table fills (OPEN QUESTIONS).
- Caller fields in `AZKVAuditLogs`: `Identity` (dynamic: user, service principal, or user plus app ID), `CallerIpAddress`, `ClientInfo`, `IsRbacAuthorized`, `AppliedAssignmentId`, `OperationName` (for example `SecretGet`), `Id` (secret ID), `RequestUri`, `HttpStatusCode`, `ResultSignature`, `DurationMs`, `CorrelationId` (an optional GUID the client can pass) [S46]. The JSON example shows the identity as claims for `objectidentifier`, `upn` and `appid` [S45]. In AzureDiagnostics mode the columns include `OperationName`, `requestUri_s`, `CallerIPAddress`, `httpStatusCode_d`, `ResourceProvider` and `identity_claim_appid_g` [S49, S48].
- Latency: logs are available within 10 minutes at most in a storage destination [S45]; resource logs reach Log Analytics in 3 to 10 minutes [S53].

Derived fallback query for the guide, built from [S46, S49]:

```kusto
union isfuzzy=true
  (AZKVAuditLogs
   | where TimeGenerated > ago(1d) and OperationName == "SecretGet"
   | project TimeGenerated, OperationName, Id, Identity, CallerIpAddress, HttpStatusCode),
  (AzureDiagnostics
   | where TimeGenerated > ago(1d) and ResourceProvider == "MICROSOFT.KEYVAULT" and OperationName == "SecretGet"
   | project TimeGenerated, OperationName, Id = requestUri_s, Identity = identity_claim_appid_g, CallerIpAddress = CallerIPAddress, HttpStatusCode = toint(httpStatusCode_d))
| order by TimeGenerated desc
```

## 8. Storage account for the seeded export and the AI Search indexer

- Blob indexing with a managed identity needs **Storage Blob Data Reader** for the search identity; write features (knowledge store, enrichment cache, debug sessions) need **Storage Blob Data Contributor** [S54, S55]. The search service must be Basic or higher with a managed identity [S54].
- The data source connection string carries only `ResourceId=/subscriptions/.../storageAccounts/<name>/;` with no key; a user-assigned identity adds an `identity` object; data source API version 2026-04-01 appears in the samples [S54].
- If the storage account is network protected and in the same region as the search service, use the system-assigned identity with either the trusted service exception or a resource instance rule; the trusted service path supports Blob and ADLS Gen2 only and does not support user-assigned identities [S54, S55].
- Disable shared key: `allowSharedKeyAccess: false` in ARM or Bicep, `az storage account update --allow-shared-key-access false`, or the portal toggle; afterwards shared key, account SAS and service SAS requests get 403, user delegation SAS still works [S56]. Tools that support Entra authorization include the portal (when configured), AzCopy, Azure CLI and PowerShell [S56].
- Setting the property needs `Microsoft.Storage/storageAccounts/write` (Owner, Contributor, Storage Account Contributor), roles that also include `listkeys` [S56].
- Network: with network rules in place, only allowed sources reach the public endpoint; rule types are virtual network, IP, resource instance and trusted service exceptions [S57].
- Derived from [S54, S55, S56, S57]: seed the export with an Entra identity that holds **Storage Blob Data Contributor**, keep shared key disabled from creation, give the search system identity **Storage Blob Data Reader**, and choose **Enable from selected networks** with the trusted services exception only if the lab VM never needs direct blob access; otherwise keep public access with Entra-only authorization.

## 9. Bicep authoring compiled to the ARM JSON that CloudLabs deploys

### 9.1 Build and keep the JSON in sync

- `az bicep build --file main.bicep --outfile <path>.json` (or `bicep build`) converts Bicep to an ARM template; `--stdout` prints it; external registry modules are restored automatically unless `--no-restore` [S58].
- `az bicep decompile --file main.json` converts an existing ARM template to Bicep [S58]. Derived: decompile the current `setup/deploy-01.json` [P02] as the starting point.
- `az bicep build-params --file params.bicepparam` builds a JSON parameters file; `az bicep generate-params` creates one [S58]. `bicep lint` reports linter findings; `bicep format` formats [S58].
- Using user-defined types, user-defined functions, compile-time imports or experimental features switches the output to language version 2.0 code generation [S58, S59]. Derived: avoid them unless CloudLabs accepts language version 2.0 templates (OPEN QUESTIONS).
- `bicepconfig.json` sits next to or above the Bicep files; the nearest one wins and merges over the defaults [S59]. `bicep.version` pins an exact compiler version or a range; a mismatch is error BCP456 in the CLI and a warning in the editor; the setting checks, it does not install [S60].
- `bicep snapshot --mode overwrite|validate <file>.bicepparam` (CLI v0.41.2 or later; no `az` equivalent) records and compares a normalized view of the deployment offline [S58].
- Derived from [S58, S60]: pin the compiler in `bicepconfig.json`, commit `main.bicep` and the generated JSON together, and add a check that rebuilds with `az bicep build --outfile` and fails when the committed JSON differs, or that runs `bicep snapshot --mode validate`.

### 9.2 Resource types in scope

| Resource type | API version | Notes | Source |
| - | - | - | - |
| `Microsoft.ApiManagement/service` | Not pinned here; the Bicep quickstart uses 2023-05-01-preview and the MCP sample references the service as `existing` at 2025-09-01-preview | Bicep quickstart defaults to Developer, `skuCount` 1 | S07, S03 |
| `Microsoft.ApiManagement/service/apis` (type `mcp`) | 2025-09-01-preview (Latest; preview) | `mcpProperties` only in preview; newest GA is 2024-05-01 | S61, S03 |
| `service/apis/policies`, `service/products/apis` | 2025-09-01-preview in the documented template | `format: rawxml` | S03 |
| `service/namedValues` | 2024-05-01 GA or later | `keyVault.secretIdentifier`, `keyVault.identityClientId` | S74 |
| `service/loggers` | 2022-08-01 in the documented sample | `loggerType: applicationInsights`, connection string plus identity | S23 |
| `service/diagnostics` | 2024-05-01 (REST reference) | `frontend`, `backend`, `httpCorrelationProtocol`, `verbosity` | S24 |
| `Microsoft.App/containerApps` | 2026-07-01 (newest GA) | `activeRevisionsMode` `Single` or `Multiple`; `template.revisionSuffix`; `secrets[].keyVaultUrl`; `registries[].identity`; `identitySettings[].lifecycle` | S62 |
| `Microsoft.Insights/diagnosticSettings` | 2021-05-01-preview (Latest) | `logAnalyticsDestinationType`, `logs[].category` or `categoryGroup` | S73 |
| `Microsoft.KeyVault/vaults` | 2026-02-01 or later | RBAC by default on create | S69 |
| `Microsoft.CognitiveServices/accounts/projects/connections` | 2026-09-01 (GA) or 2026-09-15-preview (Latest) | `category` includes `RemoteTool` and `ApiManagement`; `authType` `OAuth2` with `credentials` `clientId`, `clientSecret`, `tenantId`, `authUrl` | S63 |
| `Microsoft.Storage/storageAccounts` | not pinned here | `allowSharedKeyAccess` | S56 |

## 10. Roles: view versus manage

| Role | View | Manage (create, change, delete, approve) | Source |
| - | - | - | - |
| API Management Service Contributor | Whole instance | APIs, policies and named values; policy editing grants indirect use of the instance identity and read access to every named value | S27, S26 |
| Container Apps Contributor | Apps and revisions (per its built-in description; action list in OPEN QUESTIONS) | App management per its description; its `*/action` wildcard also lists secrets | S34 |
| Container Apps Operator | Operational tasks per its description | Full action list not read today; its `*/action` wildcard also lists secrets | S34 |
| Container Registry Tasks Contributor | Task runs and logs | Quick builds (`az acr build`), tasks, agent pools; no data plane | S43 |
| AcrPush | Images | Push and pull in RBAC-only registries | S43 |
| AcrPull | Images | Pull in RBAC-only registries | S43, S68 |
| Container Registry Repository Reader or Writer | Images | Pull, or push and pull, in ABAC registries | S67 |
| Key Vault Reader | Secret names, versions and metadata | None | S44 |
| Key Vault Secrets User | Secret values | None | S44 |
| Key Vault Secrets Officer | Secrets | Any secret action except permissions | S44 |
| Storage Blob Data Reader | Blob data | None | S54 |
| Storage Blob Data Contributor | Blob data | Write and delete blobs | S54, S55 |
| Monitoring Metrics Publisher | none | Lets the gateway identity send telemetry | S23 |
| Managed Identity Operator | none | Needed to manage ACR task identities or a registry's user-assigned identity | S43 |

Page-level exceptions:

| Page or task | Roles that can view | Roles that can manage | Source |
| - | - | - | - |
| Add a Key Vault named value | not applicable | The person adding it must be able to list secrets in the vault | S26 |
| Quick build in an ABAC registry | not applicable | Caller with a repository role, passing `--source-acr-auth-id [caller]` | S67 |
| Purge a soft-deleted API Management instance | not applicable | Contributor on the instance plus subscription-scope `deletedservices` permissions | S11 |
| Change the Key Vault permission model | not applicable | Owner, or User Access Administrator with `Microsoft.KeyVault/vaults/write` | S44, S69 |
| Toggle storage shared key access | not applicable | Owner, Contributor, Storage Account Contributor (these also read account keys) | S56 |

- Least-privilege role for seeing that the backend secret exists without reading it: **Key Vault Reader** on the vault [S44].
- The participant who runs `az acr build` needs **Container Registry Tasks Contributor** plus push rights (`AcrPush` in RBAC-only mode, **Container Registry Repository Writer** in ABAC mode) [S43, S67].
- Caveats: both Container Apps roles expose secret values [S34]; API Management policy editors can read every named value and use the instance identity [S26, S27].

## 11. Licensing and pricing

No per-user license is involved in these services; every item is a consumption meter billed per environment (derived from [S76]). Prices are Azure Retail Prices API list prices in USD, retrieved 2026-11-06 [S76]. East US 2 is the reference region; other regions are noted where they differ.

| Service | Meter (product, SKU, meter name) | Price | Unit | Regional notes | Source |
| - | - | - | - | - | - |
| API Management Developer | API Management, Developer, Developer Unit | 0.0658 | 1 hour per unit | Same in East US, East US 2, Central US, West US 3, Canada Central, Sweden Central | S76 |
| API Management Basic v2 (comparison only) | API Management, Basic v2, Basic v2 Unit | 0.20548 | 1 hour | 0.27 in Sweden Central | S76 |
| Container Apps vCPU active | Azure Container Apps, Standard, Standard vCPU Active Usage | 0.000024 | vCPU second | 0.000034 in Canada Central | S76 |
| Container Apps vCPU idle | Azure Container Apps, Standard, Standard vCPU Idle Usage | 0.000003 | vCPU second | 0.000004 in Canada Central | S76 |
| Container Apps memory active and idle | Azure Container Apps, Standard, Standard Memory Active Usage and Standard Memory Idle Usage | 0.000003 each | GiB second | 0.000004 in Canada Central | S76 |
| Container Apps requests | Azure Container Apps, Standard, Standard Requests | 0.40 | 1 million | Same in listed regions | S76 |
| Container Apps environment | Azure Container Apps, Environment, Environment Management Hour (effective 2026-09-01; 2026-11-01 in Sweden Central and Canada Central) | 0.10 | 1 hour | Applicability to Consumption-only use is unclear; see OPEN QUESTIONS | S76, S33, S64 |
| Container Registry Basic | Container Registry, Basic, Basic Registry Unit | 0.1666 | 1 day | Same in listed regions | S76 |
| ACR Tasks | Container Registry, Basic, Task vCPU Duration | 0 for the first 6,000 units, then 0.0001 | vCPU second | Scope of the zero tier not stated | S76 |
| Container Registry storage beyond included | Container Registry, Basic, Data Stored | 0.10 | GB per month | Basic includes 10 GiB | S76, S42 |
| Key Vault Standard operations | Key Vault, Standard, Operations | 0.03 | 10,000 operations | Same in listed regions | S76 |
| Log Analytics ingestion | Log Analytics, Analytics Logs, Analytics Logs Data Ingestion | 0 for the first 5 GB tier, then 2.76 | GB | 2.30 in East US and West US 3; 2.99 in Sweden Central | S76 |
| Log Analytics retention beyond included | Log Analytics, Analytics Logs, Analytics Logs Data Retention | 0.12 | GB per month | Analytics Logs include 31 days | S76, S72 |
| Platform logs processing | Azure Monitor, Platform Logs, Platform Logs Data Processed | 0.25 | GB | Relevant only if a category with export cost bills for a Log Analytics destination | S76, S21 |
| Blob storage hot LRS capacity | General Block Blob v2, Hot LRS, Hot LRS Data Stored | 0.0184 | GB per month | First tier | S76 |
| Blob hot LRS write and read operations | General Block Blob v2, Hot LRS, Hot LRS Write Operations and Hot Read Operations | 0.05 and 0.004 | 10,000 operations | | S76 |

Consumption facts:

- Container Apps free grants are per subscription per month (180,000 vCPU-seconds, 360,000 GiB-seconds, 2 million requests) [S33]. Derived from [S33, P01]: each participant environment sits in its own tenant and therefore its own subscription, and one 0.5 vCPU and 1 GiB replica uses 100 hours of grant before it is billed, so a single environment's MCP app is expected to cost nothing for compute.
- Workspace-based Application Insights bills ingestion and retention through the Log Analytics workspace [S72]. Some tables, such as `AzureActivity`, are free of ingestion charges, and `_IsBillable` shows it per record [S72].
- Derived example, East US 2, one environment kept for 32 hours (2 hours of readiness, 4 hours of lab, 24 hours of review, 2 hours of buffer): API Management 32 x 0.0658 = 2.11 USD; Container Registry about 2 days x 0.1666 = 0.33 USD; Container Apps compute 0 USD inside the free grant (1.73 USD at the active rate without it); Key Vault and Blob under 0.05 USD. For 108 environments (4 workshops x 27), API Management alone is about 227 USD. Log Analytics depends on volume and goes to the cost workbook. Built from [S76, S33].

## 12. LAB FEASIBILITY (25 participants plus 2 spares per workshop, 4 workshops; one tenant, subscription and resource group per participant)

### 12.1 Constraints that drive the design

- API Management Developer takes 30 to 40 minutes to create and activate [S05, S07]. Derived from [S05, P01]: environments must be deployed well before sign-in to meet the 5-minute launch criterion, the reset-within-60-minutes criterion leaves about 20 minutes for everything after the gateway, and the 15-minute spare-recovery criterion works only with pre-deployed spares.
- The MCP API resource needs API version 2025-09-01-preview in ARM and Bicep [S03, S61]. Derived: a preview API version is a template dependency; pin it and re-test before each workshop.
- Developer has no SLA and loses gateway availability during infrastructure changes [S04, S10]. Derived: never change custom domains, CA certificates or networking on a running lab instance.
- Names: API Management names are global and blocked for 48 hours after deletion and for days in another subscription [S11]; a reset creates a new tenant [P01]. Derived: every environment needs a fresh, unique gateway name (DeploymentID plus a unique suffix).
- Logging latency: a new workspace can take up to 2 hours before API Management logs appear [S22], a Container Apps diagnostic setting up to 90 minutes [S36], and resource logs 3 to 10 minutes per event afterwards [S53]. Derived: deploy at least 2 hours before the window and run a readiness call that writes the first rows.
- ACR task runs are paused on Azure free credits [S41]. Derived: confirm the offer type of the per-tenant subscriptions before the pilot; keep a pre-built fallback image.
- ACR Basic has no private endpoints or IP rules [S42]. Derived: the registry stays on its public endpoint with Entra authentication and the admin user disabled [P02].
- Key Vault control plane API versions before 2026-02-01 retire February 27, 2027 [S69]. Derived: the Bicep must use 2026-02-01 or later.
- Container Apps roles that let a participant update the app also expose app secrets [S34]. Derived: no secret values in the Container App configuration.
- Policy editors can read every named value and use the gateway identity [S26, S27]. Derived: if participants edit policies, the exposure is limited to their own isolated environment [P01]; keep the gateway identity's roles to Key Vault Secrets User on one vault.
- Capacity: one participant per instance; Developer concurrency and the 40 to 50 percent logging overhead apply only at high request rates [S08, S23]. Derived: no shared quota collisions between participants.

### 12.2 Recommended role set

- Participants (on their own resources): **Container Apps Contributor** on the MCP app, **Container Registry Tasks Contributor** plus **AcrPush** on the registry (or **Container Registry Repository Writer** if the registry uses ABAC mode), **Key Vault Reader** on the vault, read access to the workspace, and **API Management Service Contributor** only if a task edits policies [S34, S43, S44, S67, S27]. The previous build also gave **Managed Identity Operator** on the app identity and **Log Analytics Reader** on the workspace [P02]; both are pilot items (OPEN QUESTIONS).
- Workload identities: the MCP app identity gets **Key Vault Secrets User** on the vault and `AcrPull` on the registry; the gateway identity gets **Key Vault Secrets User** and, for a connection-string logger, **Monitoring Metrics Publisher** on Application Insights; the search identity gets **Storage Blob Data Reader** [S34, S68, S26, S23, S54].
- Never hand out: Owner, User Access Administrator or Contributor on the vault or storage account, because they can grant themselves data access or read account keys [S44, S56]; **Key Vault Secrets User** to participants, because the SOW has the backend credential read only through managed identity [P01].

### 12.3 Task classification

Tasks of the current guide that touch the services in this note [P04]; Dataverse, Purview and agent tasks are classified in their own notes.

| Task | Mode | Role needed | Why | Source |
| - | - | - | - | - |
| E1 T1 Verify readiness (gateway, MCP app health) | Hands-on, read-only | Reader on own resources | Reads status only | S05, S08, S28 |
| E3 T1 Review the MCP server on the VM | Hands-on, read-only | none in Azure | Local code | P04 |
| E3 T2 Call a read tool through the gateway | Hands-on, read-only | Signed-in technician | Own gateway and app | S01, S12 |
| E3 T3 Test tool error handling | Hands-on, read-only | Signed-in technician | Own gateway and app | S01 |
| E3 T4 Redeploy the MCP server (edit, `az acr build`, new revision, note rollback) | Hands-on, write | Container Registry Tasks Contributor, push rights, Container Apps Contributor | Every participant owns the registry and app; single revision mode keeps the old revision serving until the new one is ready | S41, S43, S28, S29 |
| E3 T4 Rollback (acceptance criterion 7) | Hands-on, write | Container Apps Contributor | `revision copy --from-revision` creates a new revision without a build | S29, S30, P01 |
| E4 T4 and T5 Change or add a tool and redeploy | Hands-on, write | Same as E3 T4 | Same isolation | S41, S28 |
| Extend a gateway policy (for example rate limit or trace metadata) | Hands-on, write, optional | API Management Service Contributor | Own instance; MCP streaming breaks if the body is read | S01, S16, S27 |
| E5 T2 Verify secure secret handling (secret list, role assignment, SecretGet log) | Hands-on, read-only | Key Vault Reader, workspace read | Metadata only; log latency of minutes | S44, S46, S53 |
| E6 T3 Trace one action end to end | Hands-on, read-only | Workspace read | Rows exist only after the readiness and earlier calls; table and field caveats in OPEN QUESTIONS | S19, S20, S37, S53 |
| E7 T1 End-to-end scenario evidence | Hands-on, read-only | Workspace read | Same as E6 T3 | S19, S37 |
| Traffic-split rollback (multiple mode) | Instructor demo | Container Apps Contributor | Needs a revision mode change that the guide does not use | S31, S32 |

### 12.4 Pre-seeding checklist

1. Seven or more days before: confirm the per-tenant subscriptions are not funded by Azure free credits (ACR Tasks) [S41]; register `Microsoft.App`, `Microsoft.OperationalInsights` and `Microsoft.Insights` [S68, S36]; compile the Bicep with the pinned compiler and run the sync check [S58, S60]; pilot one full environment, including the preview MCP API version [S03].
2. At least 2 hours before the window (in practice the day before for 27 environments): deploy all environments and spares (gateway 30 to 40 minutes) [S05]; diagnostic settings for API Management, the Container Apps environment and Key Vault are created by the template [S22, S36, S50]; push the baseline image and a pre-built fallback tag [S41].
3. One hour before: readiness script per environment calls a read tool through the gateway, then checks rows in `ApiManagementGatewayLogs`, `ApiManagementGatewayMCPLog`, `ContainerAppConsoleLogs` and the Key Vault table, the latest revision state, and one small `az acr build` [S19, S20, S37, S46, S28, S66].
4. Event day: participants build, deploy and roll back only their own app; gateway infrastructure is never changed [S10].

### 12.5 Data latency

| Signal or change | Documented latency | Source |
| - | - | - |
| First API Management logs in a new workspace | Up to 2 hours (about 15 minutes for an existing workspace) | S22 |
| Resource logs after each event (API Management, Key Vault) | Usually 3 to 10 minutes end to end | S53 |
| Key Vault logs (storage destination) | 10 minutes at most | S45 |
| Container Apps diagnostic setting activation | Up to 90 minutes | S36 |
| Container console logs in Log Analytics | Several minutes; use the log stream for real time | S38 |
| Key Vault named value after a secret update | Within four hours | S26 |
| Container Apps Key Vault reference after a secret update | Within 30 minutes, with automatic restart of revisions using it in env vars | S34 |
| Managed identity token after a role change | Cached about 24 hours; no forced refresh | S39 |
| Key Vault role assignment in the portal | Several minutes | S44 |
| New Container Apps revision ready | Not documented | none |
| `az acr build` for the Python image | Not documented (hello-world example: 10 seconds) | S66 |
| API Management instance online | 30 to 40 minutes | S05 |

### 12.6 Timing and fallbacks

- Order: the readiness call must run before the workshop so every log table already has rows when E5 and E6 query them [S22, S53].
- If `az acr build` fails (free-credit pause or ABAC change), deploy the pre-built fallback tag with `az containerapp update --image` [S41, S67, S29].
- If `ApiManagementGatewayMCPLog` stays empty in the Developer tier, use `ApiManagementGatewayLogs` with the logged `x-correlation-id` header and the `TraceRecords` column [S19, S24, S25].
- If the Key Vault rows land in `AzureDiagnostics`, use the union query in section 7.2 [S46, S49].
- Record a fallback run of the redeploy and rollback in the pilot, with the measured build and revision times [S66, S28].

## 13. SCREENSHOT SOURCES

All URLs below returned HTTP 200 on 2026-11-06; relative media paths were resolved against each page URL.

- https://learn.microsoft.com/azure/api-management/media/expose-existing-mcp-server/create-mcp-server.png : Create MCP server form [S01]
- https://learn.microsoft.com/azure/api-management/media/expose-existing-mcp-server/mcp-server-list.png : MCP Servers list with the Server URL column [S01]
- https://learn.microsoft.com/azure/api-management/media/export-rest-mcp-server/mcp-server-policies.png : Policy editor of an MCP server [S01]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-properties/named-values.png : Named values list [S26]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-properties/add-property.png : Add a Key Vault named value [S26]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-use-managed-service-identity/enable-system-identity.png : System-assigned identity on [S27]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-use-managed-service-identity/enable-user-assigned-identity.png : User-assigned identity added [S27]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-app-insights/apim-app-insights-logger-1.png : Add an Application Insights connection [S23]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-app-insights/apim-app-insights-api-1.png : Diagnostic Logs settings of an API [S23]
- https://learn.microsoft.com/azure/includes/media/api-management-diagnostic-settings/monitoring-menu.png : Diagnostic settings entry in the Monitoring menu [S22]
- https://learn.microsoft.com/azure/includes/media/api-management-log-analytics/query-resource-logs.png : Querying ApiManagementGatewayLogs [S22]
- https://learn.microsoft.com/azure/api-management/media/api-management-howto-ip-addresses/public-ip.png : Gateway public IP on the Overview page [S70]
- https://learn.microsoft.com/azure/api-management/media/get-started-create-service-instance/create-api-management-instance-1.png : Basics tab of the create form [S06]
- https://learn.microsoft.com/azure/container-apps/media/revisions/screen-shot-revision-mgmt-labels.png : Revision management with labels [S28]
- https://learn.microsoft.com/azure/container-apps/media/revisions/screen-shot-revision-mgmt-revision-details.png : Revision details pane [S28]
- https://learn.microsoft.com/azure/container-apps/media/ingress/screenshot-revision-management-mode.png : Revision mode setting [S31]
- https://learn.microsoft.com/azure/container-apps/media/ingress/screenshot-create-deploy-new-revision.png : Create and deploy new revision [S31]
- https://learn.microsoft.com/azure/container-apps/media/ingress/screenshot-traffic-splitting.png : Traffic splitting in Revision management [S31]
- https://learn.microsoft.com/azure/container-apps/media/blue-green-deployment/azure-container-apps-blue-green-deployment.png : Blue-green concept diagram [S32]
- https://learn.microsoft.com/azure/container-apps/media/ingress/screenshot-ingress-page-ip-restrictions.png : Ingress IP restrictions [S71]
- https://learn.microsoft.com/azure/container-apps/media/managed-identity/screenshot-system-assigned-identity.png : Container app system identity [S39]
- https://learn.microsoft.com/azure/container-apps/media/managed-identity/screenshot-user-assigned-identity.png : Container app user-assigned identity [S39]
- https://learn.microsoft.com/azure/container-apps/media/managed-identity/screenshot-edit-a-container-user-assigned-identity.png : Edit a container with managed identity image pull [S68]
- https://learn.microsoft.com/azure/key-vault/media/diagnostics-portal-1.png : Key Vault Add diagnostic setting [S50]
- https://learn.microsoft.com/azure/key-vault/media/diagnostics-portal-2.png : Key Vault diagnostic categories and destination [S50]
- https://learn.microsoft.com/azure/key-vault/media/diagnostics-portal-3.png : Saving the Key Vault diagnostic setting [S50]
- https://learn.microsoft.com/azure/key-vault/media/rbac/image-12.png : Secret properties visible without a data role on the secret [S44]
- https://learn.microsoft.com/azure/key-vault/media/rbac/image-13.png : Secrets tab error without Key Vault Reader [S44]
- https://learn.microsoft.com/azure/storage/common/media/shared-key-authorization-prevent/shared-key-access-portal.png : Allow storage account key access toggle [S56]
- https://learn.microsoft.com/azure/search/media/search-indexer-howto-secure-access/manage-network-access.png : Manage public network access [S55]
- https://learn.microsoft.com/azure/search/media/search-indexer-howto-secure-access/enable-selected-networks.png : Enable from selected networks [S55]
- https://learn.microsoft.com/azure/search/media/search-indexer-howto-secure-access/exception.png : Trusted services exception [S55]
- https://learn.microsoft.com/azure/search/media/search-managed-identities/system-assigned-identity-object-id.png : Search service system identity [S55]
- https://learn.microsoft.com/azure/container-registry/media/container-registry-get-started-portal/configure-container-registry-options.png : Registry creation with Role assignment permissions mode [S67]
- https://learn.microsoft.com/azure/azure-monitor/platform/media/resource-logs/diagnostic-settings-mode-selector.png : Azure diagnostics versus resource-specific selector [S52]

## 14. OPEN QUESTIONS

1. Gateway correlation: no page states that `ApiManagementGatewayLogs.CorrelationId` equals `context.RequestId` [S18, S19], yet the current guide filters on it with the ID set by the policy [P04]. Pilot: compare both values for one call; if they differ, query the logged `x-correlation-id` header (section 4.4).
2. MCP log in the Developer tier: whether the classic Developer gateway emits `GatewayMCPLogs` rows, and the portal label of that category, are not documented [S21, S22]. Pilot: check rows after the readiness call.
3. MCP 2026-07-28 through the gateway: API Management documents support for MCP 2025-06-18 or later [S01] while the current revision is sessionless 2026-07-28 [S75]. Pilot: confirm the agent's tool calls pass, and what `SessionId`, `ClientName` and `ProtocolVersion` [S20] and `gen_ai.conversation.id` [S15] contain.
4. Key Vault table: [S48] maps `AuditEvent` to `AzureDiagnostics` and [S49] lists Key Vault as diagnostics-mode only, while `AZKVAuditLogs` has a schema and queries [S46, S51]. Pilot: deploy with `logAnalyticsDestinationType: Dedicated` [S73] and see which table fills; keep the union query.
5. Key Vault `CorrelationId` is an optional client GUID [S46]; which request header sets it is not documented. Only matters if the MCP server should stamp its startup read.
6. Header forwarding: [S14] says request headers reach MCP tool invocations automatically, with certain exclusions that it does not list. Pilot: confirm `x-correlation-id`, `x-backend-key` and, if needed, `Authorization` reach the app.
7. Caching conflict: [S02] lists caching as an MCP governance option; [S16] says to disable response caching for streaming APIs. Do not cache in the lab.
8. Tools versus resources: [S01] says external servers support tools and resources; [S02] says tools only.
9. Single-mode rollback: whether `revision copy --from-revision` accepts a deprovisioned revision, and whether `revision activate` works in single mode, are not stated [S28, S30]. Pilot both.
10. Revision name format: one hyphen between app name and suffix [S28] versus two hyphens [S32]. Read the name from `az containerapp revision list` instead of building it.
11. Timings not documented: revision readiness [S28] and `az acr build` for the Python image [S66]. Measure in the pilot against the 35-minute exercise.
12. Container Apps Contributor actions use `Microsoft.App/containerApps/*/write` (seen in a search excerpt of the built-in roles page, not read in full); whether that covers updating the app itself, and whether updates need **Managed Identity Operator** on the user-assigned identity [P02], are not confirmed. Pilot with the participant account.
13. Environment Management Hour (0.10 USD per hour, effective 2026-09-01) [S76]: [S33] ties management charges to Dedicated profiles and premium features, and [S64] says Consumption-only environments cost nothing. Check Cost Management after the pilot.
14. Free tiers: the scope of the zero-priced first 6,000 ACR task units and of the first 5 GB of Log Analytics ingestion [S76] is not stated in the API. Confirm in the cost workbook.
15. Export cost of `GatewayMCPLogs`: the **Costs to export** column shows Yes [S21]; whether this bills when the destination is a Log Analytics workspace is not stated on the pages read.
16. Subscription offer: whether CloudLabs per-tenant subscriptions are funded by Azure free credits, which pauses ACR task runs [S41].
17. ACR role assignment mode in ARM: the CLI flag `--role-assignment-mode` and the `roleAssignmentMode` query are documented [S67]; the template property name and values were not read.
18. API versions not read in full: `Microsoft.App/managedEnvironments`, `Microsoft.CognitiveServices/accounts/projects`, and whether `RemoteTool` is in the 2026-09-01 GA connections schema (it is in Latest [S63]); `Microsoft.Storage/storageAccounts` `publicNetworkAccess` and `networkAcls.bypass` property values.
19. Correlation ID origin for duplicate suppression: the SOW keys the 10-minute rule on the correlation ID [P01]. If the agent cannot send an `x-correlation-id`, each request gets a new gateway ID [S18] and the MCP server needs another idempotency key. Settle in the design pack.
20. Language version 2.0: whether CloudLabs accepts ARM JSON produced with language version 2.0 code generation [S58].
21. `bicep.version`: the minimum compiler version that understands it is not stated [S60].
22. Label drift: **Revision management** versus **Revisions and replicas**; **Security** > **Identity** versus **Settings** > **Identity**; **Diagnostic Logs** versus **Diagnostics Logs** (section 2). The current guide's Key Vault **Objects** > **Secrets** and Container App **Settings** > **Secrets** labels [P04] are not on any page read; [S34] shows **Security** > **Secrets**. Confirm in the pilot capture.
23. Log Analytics Reader: the previous build assigns it for workspace queries [P02]; its definition was seen only in a search excerpt today. Confirm it before writing the role table into the guide.
24. Token shape from the agent: which client ID appears in `azp` or `appid` and whether the token is v1.0 or v2.0 (which decides the `aud` form) [S65]. Decode one token in the pilot before fixing `client-application-ids` and `audiences` [S12].
25. Default Azure Monitor logger and diagnostic: whether `/loggers/azuremonitor` and its diagnostic exist after an ARM deployment, and their exact names [S24].
26. IP restriction side effects: with only the gateway IP allowed [S71], confirm health probes and log streaming still work, and decide how the lab VM checks `/health` [P04].
27. Default probe type: [S40] says default startup and liveness probes are HTTP GET; define explicit `/health` probes anyway.
28. MCP Inspector tip: [S01] recommends version 0.9.0 for testing through API Management, which may be outdated.
