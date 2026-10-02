# Research: Foundry agents, Entra Agent ID, MCP, Azure AI Search knowledge, tracing

Researched 2026-10-01 from Microsoft Learn only (Microsoft Learn MCP search and fetch). Every bullet ends with its source. Code blocks are copied from the cited page unless marked "lab design, not from docs".

Coverage note: all key pages were fetched in full. Three very long pages were read partially: the MCP tool page (TypeScript and Java samples skimmed, all prose, REST, limits, and Python read), the model region availability page (Global Standard section for Americas and Europe read; provisioned, batch, data zone sections not needed), and the voice agent page (only the portal Tools and Knowledge sections read).

## 1. Foundry resource model in ARM

API versions

- Latest GA api-version for `Microsoft.CognitiveServices/accounts` is `2026-07-01`. GA versions in order: 2025-06-01, 2025-09-01, 2025-12-01, 2026-03-01, 2026-05-01, 2026-07-01. Latest preview is `2026-07-15-preview` (adds `capabilitySettings`, `agentHostingConfigurations`, `a365LoggingEnabled`, `foundryAutoUpgrade`). https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/change-log/accounts
- `allowProjectManagement`, `associatedProjects`, `defaultProject`, `networkInjections` were introduced in 2025-04-01-preview and are present in all later GA versions. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/change-log/accounts
- `allowProjectManagement`: "Specifies whether this resource support project management as child resources, used as containers for access management, data isolation and cost in AI Foundry." https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-07-01/accounts
- `accounts/deployments` latest GA is also `2026-07-01` (2026-07-15-preview adds speculative decoding). https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/change-log/accounts/deployments
- `accounts/projects` has a `2026-07-01` GA schema: `identity` (None, SystemAssigned, UserAssigned), `location`, `properties.displayName`, `properties.description`; name 2 to 64 chars, pattern `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-07-01/accounts/projects
- The preview projects schema (2026-07-15-preview) adds `properties.capabilitySettings` (blobStore, documentStore, vectorStore) that is "Settable only at create time". https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/projects
- `accounts/projects/connections` GA `2026-07-01`; its deployable schema has not changed since 2025-04-01-preview. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/change-log/accounts/projects/connections
- Connection name pattern `^[a-zA-Z0-9][a-zA-Z0-9_-]{2,32}$`. Properties: `authType` (AAD, AccessKey, AccountKey, ApiKey, CustomKeys, ManagedIdentity, None, OAuth2, PAT, SAS, ServicePrincipal, UsernamePassword), `category` (includes `CognitiveSearch`, `AppInsights`, `CustomKeys`, `ApiKey`, `ApiManagement`, `RemoteTool`, `RemoteA2A`), `target`, `metadata`, `isSharedToAll`, `sharedUserList`, `expiryTime`, `useWorkspaceManagedIdentity`, `peRequirement`, `credentials`. The published ARM schema does not list `AgenticIdentityToken`, `ProjectManagedIdentity`, `UserEntraToken` or an `audience` property. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-07-01/accounts/projects/connections

Account, project, deployment shapes

- Account Bicep from the docs (note the comments): https://learn.microsoft.com/azure/foundry/how-to/upgrade-azure-openai

```bicep
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
    name: foundryName // Your existing resource name
    location: location
    identity: {
        type: 'SystemAssigned'
    }
    sku: {
        name: 'S0'
    }
    kind: 'AIServices' // Update from 'OpenAI'
    properties: {
        // required to work in Foundry
        allowProjectManagement: true 

        // Needed for capabilities that require EntraID authentication
        customSubDomainName: foundryName
        disableLocalAuth: true
    }
}
```

- CLI equivalent: `az cognitiveservices account create --name my-foundry-resource --resource-group my-foundry-rg --kind AIServices --sku S0 --location eastus --custom-domain my-foundry-resource --assign-identity --allow-project-management true`. https://learn.microsoft.com/azure/foundry/how-to/create-projects
- Model deployment Bicep from the docs (sample pins 2024-04-01-preview; GA 2026-07-01 exists): https://learn.microsoft.com/azure/foundry/foundry-models/how-to/create-model-deployments

```bicep
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  name: '${accountName}/${modelName}'
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    model: {
      format: modelPublisherFormat
      name: modelName
      version: modelVersion
    }
    raiPolicyName: contentFilterPolicyName == null ? 'Microsoft.Nill' : contentFilterPolicyName
  }
}
```

Connection to Azure AI Search

- Keyless (`AAD`) and key (`ApiKey`) bodies, created with ARM REST `api-version=2025-06-01`: https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search

```bash
curl -X PUT "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.CognitiveServices/accounts/{foundryResourceName}/projects/{projectName}/connections/{connectionName}?api-version=2025-06-01" \
  -H "Authorization: Bearer $MGMT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "category": "CognitiveSearch",
      "target": "https://{searchServiceName}.search.windows.net",
      "authType": "AAD"
    }
  }'
```

```json
{
  "properties": {
    "category": "CognitiveSearch",
    "target": "https://{searchServiceName}.search.windows.net",
    "authType": "ApiKey",
    "credentials": {
      "key": "{searchAdminKey}"
    }
  }
}
```

- azd variant: `azd ai connection create my-search-connection --project-endpoint "$PROJECT_ENDPOINT" --kind cognitive-search --target "$SEARCH_ENDPOINT" --auth-type project-managed-identity` (or `--auth-type api-key --key "$SEARCH_ADMIN_KEY"`). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Python mgmt SDK uses `AADAuthTypeConnectionProperties(category="CognitiveSearch", target=SEARCH_ENDPOINT)` via `client.project_connections.create(...)` in `azure-mgmt-cognitiveservices`. The `az ml` CLI and `azure-ai-ml` SDK do not work for new Foundry projects ("Workspace not found"). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Connections referenced by capability hosts must also carry `metadata.ResourceId` (full ARM ID); example uses `"authType": "AAD"`, `"category": "AzureStorageAccount"`. https://learn.microsoft.com/azure/foundry/agents/concepts/capability-hosts

Connection for MCP (RemoteTool) and custom keys

- Auth type value for agent identity on MCP is `AgenticIdentityToken` with category `RemoteTool` (A2A uses `RemoteA2A`). https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity
- Documented RemoteTool body with project managed identity and `audience`, created through ARM REST `api-version=2025-10-01-preview` (Foundry IQ example; the `type` value is copied as the docs show it): https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect

```http
PUT https://management.azure.com/{project_resource_id}/connections/{project_connection_name}?api-version=2025-10-01-preview
Authorization: Bearer {management_access_token}
Content-Type: application/json

{
  "name": "{project_connection_name}",
  "type": "Microsoft.MachineLearningServices/workspaces/connections",
  "properties": {
    "authType": "ProjectManagedIdentity",
    "category": "RemoteTool",
    "target": "{search_service_endpoint}/knowledgebases/{knowledge_base_name}/mcp?api-version=2026-08-01-preview",
    "isSharedToAll": true,
    "audience": "https://search.azure.com/",
    "metadata": {
      "ApiType": "Azure"
    }
  }
}
```

- Another documented RemoteTool body uses `"authType": "UserEntraToken"` plus `"audience"` and `"isSharedToAll": true` at `api-version=2025-10-01-preview`. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric-iq
- azd auth types for `--kind remote-tool`: `none`, `custom-keys` (`--custom-key "Header=Value"`, repeatable), `oauth2`, `user-entra-token` (`--audience`), `project-managed-identity` (`--audience` optional), `agentic-identity` (`--audience` required). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

```bash
azd ai connection create my-mcp-connection \
  --kind remote-tool \
  --target https://<mcp-server-endpoint> \
  --auth-type agentic-identity \
  --audience "<entra-audience>"
```
Source: https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication

- CustomKeys body shape (Fabric example, `api-version=2025-04-01-preview`): `{"properties": {"category": "CustomKeys", "authType": "CustomKeys", "credentials": {"keys": {"workspace_id": "...", "artifact_id": "..."}}}}`. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric
- Portal custom keys connection for MCP: Manage > Project details > Connected resources > Custom keys, key `Authorization`, value `Bearer your_github_token`. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

Connection to Application Insights

- Category `AppInsights` exists in the ARM enum. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-07-01/accounts/projects/connections
- Only one Application Insights connection per project: error "Multiple connection with same category (AppInsights) created, we only allow to have 1 connection for category". https://learn.microsoft.com/azure/foundry/observability/how-to/trace-ingestion-entra-authentication
- Portal connection can set Auth type `Project Managed Identity`; the portal then assigns Monitoring Metrics Publisher to the project managed identity. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-ingestion-entra-authentication
- Learn does not print the AppInsights connection JSON; it points to Bicep templates in the foundry-samples repo (`infrastructure-setup-bicep/01-connections`). https://learn.microsoft.com/azure/foundry/how-to/connections-add

Basic vs standard setup

- "Creating capability hosts isn't required. ... If you don't create capability hosts, Agent Service automatically uses Microsoft-managed Azure resources." https://learn.microsoft.com/azure/foundry/agents/concepts/capability-hosts
- Capability hosts article is now "retained for reference"; resources are declared through capability settings. Recommendation to not mix basic and standard setup in the same account. https://learn.microsoft.com/azure/foundry/agents/concepts/capability-hosts
- Basic setup creates only account, project, model deployment. Creating account and project needs Foundry Account Owner; creating and editing agents needs Foundry User. https://learn.microsoft.com/azure/foundry/agents/environment-setup
- MCP tool: supported in Basic and Standard setup; public endpoints work with both; private MCP requires Standard setup with private networking (BYO VNet). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Azure AI Search tool: supported in Basic and Standard setup; basic does not support private AI Search or AI Search with public network access disabled. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search

## 2. Agents in the current (new) Foundry experience

Object model

- Agent types: prompt agents, voice-based prompt agents, hosted agents (containers). https://learn.microsoft.com/azure/foundry/agents/overview
- Agent version is an immutable snapshot; any change creates a new version. Agent name cannot be changed after creation. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent and https://learn.microsoft.com/azure/foundry/agents/concepts/development-lifecycle
- Agent object properties: `object`, `id`, `name` (max 63 chars), `versions`, `agent_endpoint` (`version_selector`, `protocol_configuration`, `authorization_schemes`), `instance_identity` (`principal_id`, `client_id`, read-only), `blueprint`/`blueprint_reference`, `agent_card`, `status`. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent
- The agent endpoint "is live the moment you create the agent, with no separate publish step". Defaults: Always use latest, Responses protocol, authorization `Entra`. API key auth is not supported on agent endpoints. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent
- Endpoint patterns: Responses `https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/openai/responses`; Activity `.../endpoint/protocols/activityprotocol`; Invocations `.../endpoint/protocols/invocations`; A2A `.../endpoint/protocols/a2a`; MCP (preview) `.../endpoint/protocols/mcp`. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent
- New model: "Newly created agents receive a unique Entra Agent Blueprint and Entra Agent Identity by default." `agent.identity` null means legacy agent. "Creating an agent is the only step needed to get a stable endpoint and unique agent identity." https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-agent-applications
- Limits: 128 tools per agent, 1,000 versions per agent (fixed, cannot be raised). https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions

Create an agent programmatically

- REST: `POST {endpoint}/agents?api-version=v1`; `POST {endpoint}/agents/{agent_name}/versions?api-version=v1` creates a new version; OAuth scope `https://ai.azure.com/.default`; `Foundry-Features` header only for preview operations (`ContainerAgents=V1Preview`, `HostedAgents=V1Preview`, `WorkflowAgents=V1Preview`). https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject

```console
curl -X POST https://YOUR-FOUNDRY-RESOURCE-NAME.services.ai.azure.com/api/projects/YOUR-PROJECT-NAME/agents?api-version=v1 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AZURE_AI_AUTH_TOKEN" \
  -d '{
    "name": "MyAgent",
    "definition": {
      "kind": "prompt",
      "model": "gpt-5-mini",
      "instructions": "You are a helpful assistant that answers general questions"
    }
  }'
```
Source: https://learn.microsoft.com/azure/foundry/agents/quickstarts/prompt-agent

- Token for REST: `az account get-access-token --scope https://ai.azure.com/.default`. https://learn.microsoft.com/azure/foundry/agents/quickstarts/prompt-agent
- Python: `pip install "azure-ai-projects>=2.3.0" azure-identity`; Azure AI Projects 2.x is incompatible with 1.x (classic). https://learn.microsoft.com/azure/foundry/agents/quickstarts/prompt-agent

```python
agent = project.agents.create_version(
    agent_name=FOUNDRY_AGENT_NAME,
    definition=PromptAgentDefinition(
        model="gpt-5-mini",  # supports all Foundry direct models
        instructions="You are a helpful assistant that answers general questions",
    ),
)
```
Source: https://learn.microsoft.com/azure/foundry/agents/quickstarts/prompt-agent

- Other current pages require newer minimums: `azure-ai-projects>=2.5.0` (optimizer quickstart), `>=2.7.0` (voice telephony). https://learn.microsoft.com/azure/foundry/agents/quickstarts/quickstart-optimize-hosted-agent and https://learn.microsoft.com/azure/foundry/agents/how-to/voice-agent-telephony-channels
- Invoke: `openai = project.get_openai_client(agent_name=...)` then `openai.responses.create(...)`, or REST `POST .../agents/{name}/endpoint/protocols/openai/responses?api-version=v1`. https://learn.microsoft.com/azure/foundry/agents/quickstarts/prompt-agent
- Project-level Responses call with agent reference: `POST $FOUNDRY_PROJECT_ENDPOINT/openai/v1/responses` with `"agent": {"type": "agent_reference", "name": "<AGENT_NAME>"}`. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Read an agent (identity, protocols, auth): `GET {endpoint}/agents/{agent_name}?api-version=v1`. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent
- Pin a version: https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent

```http
PATCH {{endpoint}}/agents/{{agent_name}}?api-version=v1
Authorization: Bearer {{token}}
Content-Type: application/merge-patch+json

{
  "agent_endpoint": {
    "version_selector": {
      "version_selection_rules": [
        {
          "type": "FixedRatio",
          "agent_version": "2",
          "traffic_percentage": 100
        }
      ]
    }
  }
}
```

- There is no ARM resource type for new-model agents; Terraform manages agents with `azapi_data_plane_resource` type `Microsoft.Foundry/agents@v1` against the project data plane (documented for hosted agents). https://learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent-terraform

Publishing now

- Legacy model: publishing created an Agent Application ARM resource plus a Deployment, each with its own identity and endpoint. New model collapses these into the Agent object; publishing now means (1) choosing which version the stable endpoint serves and (2) publishing to M365/Teams. https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-agent-applications
- Legacy Agent Application resource type: `Microsoft.CognitiveServices/accounts/projects/applications` with child `agentDeployments`; read-only `agentIdentityBlueprint` and `defaultInstanceIdentity`; "Foundry Agent Applications are not registered in the Microsoft Entra agent registry." https://learn.microsoft.com/azure/foundry/agents/how-to/agent-applications
- Publishing to Teams/M365 (new model) creates an Azure Bot Service resource, compiles a Teams app manifest, enables the `activity` protocol and a `BotServiceRbac` or `BotServiceTenant` authorization scheme. Needs `Microsoft.BotService` provider and Azure Bot Service Contributor (or Contributor/Owner) plus Foundry User. https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot
- REST publish exists: get `instance_identity.client_id` from `GET {{endpoint}}/agents/{{agent_name}}?api-version=v1`, deploy `Microsoft.BotService/botServices@2022-09-15` (kind `azurebot`, location `global`, sku `F0`, `msaAppId` = agent identity client ID, `msaAppType: 'SingleTenant'`), then `POST {{endpoint}}/agents/<agent-name>/microsoft365/publish?api-version=v1` with `botServiceArmId`, `publishScope` (`Shared` or `Tenant`), `appVersion`, descriptions; `.../microsoft365/zip?api-version=v1` downloads the package. https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network

Where the agent identity appears and how a learner finds the object ID

- REST: `instance_identity` in the Get agent response: https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network

```json
"instance_identity": {
  "principal_id": "aaaaaaaa-bbbb-cccc-1111-222222222222",
  "client_id":    "00001111-aaaa-2222-bbbb-3333cccc4444"
}
```

- Entra admin center: Entra ID > Agents > Agent identities; search by name or object ID, add the Blueprint App ID filter; columns include Object ID and Blueprint App ID (Choose columns). https://learn.microsoft.com/entra/agent-id/agent-lists
- Foundry concept page gives a different path: Entra ID > Agent ID > All agent identities. https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity
- Foundry portal (documented for hosted agents): Agents > select agent > Identity shows the agent identity object ID. https://learn.microsoft.com/azure/foundry/agents/quickstarts/quickstart-foundry-iq-hosted-agent
- Azure portal JSON view (legacy model only): project Overview > JSON View (shared project identity) or Agent Application Overview > JSON View (`agentIdentityId`). https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity
- Graph: `GET /servicePrincipals/{id}/microsoft.graph.agentIdentity`. https://learn.microsoft.com/graph/api/agentidentity-get?view=graph-rest-1.0
- Role assignments to the identity use the object ID, for example `az role assignment create --assignee-object-id <agent-identity-object-id> --assignee-principal-type ServicePrincipal --role "Search Index Data Reader" --scope $searchId`. https://learn.microsoft.com/azure/foundry/agents/quickstarts/quickstart-foundry-iq-hosted-agent
- Agent-scope RBAC path: `/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>/agents/<agentName>`; evaluated only for agent endpoint access. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Migration note: role assignments made for Agent Application identities do not transfer; reassign for the new agent identity. https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-agent-applications

## 3. Microsoft Entra Agent ID

- Agent identity is a special service principal created from an agent identity blueprint; it has no credentials of its own; the blueprint acquires tokens for it. https://learn.microsoft.com/entra/agent-id/agent-identities
- In Foundry, the blueprint has a federated credential trust with the project managed identity; the agent identity (not the managed identity) is the principal that needs RBAC on targets. https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity
- Only MCP and A2A tools currently support agent identity authentication. https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity

Viewing permissions

- Entra admin center view: "A Microsoft Entra user account ... No admin role is required for viewing." Manage: Agent ID Administrator or Cloud Application Administrator, or owner of the agent identity. https://learn.microsoft.com/entra/agent-id/agent-lists
- Same in the admin guide table ("View agent identities | Microsoft Entra user account | No admin role needed"). https://learn.microsoft.com/entra/agent-id/manage-agent-identities-admin
- Agent 365 / M365 admin center inventory: "users need the AI Reader role"; viewing there "doesn't require a specific license". https://learn.microsoft.com/entra/agent-id/agent-registry-convergence
- Graph `GET /servicePrincipals/microsoft.graph.agentIdentity`: least privilege `AgentIdentity.Read.All` (delegated or application); "For nonowners to call this API in delegated scenarios ... Agent ID Administrator". https://learn.microsoft.com/graph/api/agentidentity-list?view=graph-rest-1.0
- `AgentIdentity.Read.All` requires admin consent for both delegated and application. https://learn.microsoft.com/graph/permissions-reference
- Sign-in logs for agents need at least Reports Reader; filter Agent type = Agent Identity. https://learn.microsoft.com/entra/agent-id/manage-agent-identities-admin

Licensing

- "Agent ID is available for all Microsoft Entra customers." Microsoft Agent 365 needs a per-user license; "Extending Microsoft Entra security features to agents requires Microsoft Agent 365" (included in M365 E7, add-on to E5/A5/Business Premium). https://learn.microsoft.com/entra/agent-id/what-is-microsoft-entra-agent-id
- Admin guide: Conditional Access for agents "Requires Microsoft Entra ID P1"; ID Protection risk reports "Requires Microsoft Entra ID P2 license during preview". https://learn.microsoft.com/entra/agent-id/manage-agent-identities-admin
- Licensing page: "Starting soon, ID Protection for agents will require a Microsoft Agent 365 license". https://learn.microsoft.com/entra/fundamentals/licensing
- ID Governance for agents requires M365 E7, or Agent 365 plus Entra P1 or M365 E3. https://learn.microsoft.com/entra/id-governance/agent-id-governance-overview
- Foundry docs do not state any license requirement for Foundry-created agent identities (docs silent). https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity

Token claims relevant to an API gateway

- Agent acting autonomously (app-only, which is the MCP agent-identity case): `idtyp` = `app`, `xms_idrel` = `7`, `azp`/`appid` = application ID of the agent identity, `roles` = permissions granted, `oid` = object ID of the agent identity, `xms_act_fct` = `11`, `xms_sub_fct` = `11`, `aud` = resource audience, `scp` empty or `/`. https://learn.microsoft.com/entra/agent-id/agent-token-claims
- v1 tokens carry `appid`, v2 carry `azp`. Facet claims are multivalued, space separated; ignore unknown values and do not assume order. https://learn.microsoft.com/entra/agent-id/agent-token-claims
- `xms_par_app_azp` = parent application (blueprint) of the authorized party; log it, but "It isn't recommended to use the parent application ID for authorization decisions". https://learn.microsoft.com/entra/agent-id/agent-token-claims
- Downstream checks: signature (JWKS `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`), issuer (`https://sts.windows.net/<tenant>/` or `https://login.microsoftonline.com/<tenant>/v2.0`), audience, and agent marker `xms_par_app_azp` present. https://learn.microsoft.com/entra/agent-id/how-to-validate-agent-tokens-downstream-api
- MCP server as resource: validate signature, `iss`, `tid`, `aud` (application ID of the MCP server), expiry, then `roles`; use v2 tokens (`requestedAccessTokenVersion: 2`); for app-only callers define app roles (Allowed member types: Applications) and assign them to the agent identity. https://learn.microsoft.com/entra/agent-id/secure-mcp-server-with-entra-id
- With v1 tokens `aud` is nondeterministic (App ID URI or client ID) unless the `aud` optional claim with `use_guid` is set; v2 `aud` is consistently the resource client ID. https://learn.microsoft.com/entra/agent-id/secure-mcp-server-with-entra-id
- Tenant risk: Conditional Access "Block agent identity authentication" policies block token issuance for all agent identities. https://learn.microsoft.com/entra/agent-id/disable-agent-identities

## 4. MCP tool in Foundry agents

Portal steps (new Foundry)

- Text agent path documented by Azure Functions: Foundry portal (new) > Build > select agent > Playground tab > Tools dropdown > Add > Custom tab in Select a tool > Model Context Protocol (MCP) > Create > Add Model Context Protocol tool: Name, Remote MCP Server endpoint, Authentication (`Key-based` with Credential key/value; `Microsoft Entra` with Type `Agent Identity` or `Project Managed Identity` and Audience; `OAuth Identity Passthrough` with Client ID, Client secret, Token URL, Auth URL, Refresh URL, Scopes; `Unauthenticated`) > Connect > Save. Test: prompt, then Approve the tool call (Open Consent for OAuth). https://learn.microsoft.com/azure/azure-functions/functions-mcp-foundry-tools
- Alternative label set: Build > Tools or Agent Builder > Connect a tool > Custom tab > MCP > Connect. https://learn.microsoft.com/azure/foundry/mcp/build-your-own-mcp-server
- Voice agent playground labels: Tools section offers Add a MCP tool and Add a toolbox. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent
- Connecting in the portal creates the project connection automatically (credential name and value for key-based). https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication

Tool definition

- Fields: `type: "mcp"`, `server_label` (required, unique per agent), `server_url`, `allowed_tools` (default all tools), `require_approval` (default `always`; `never`; `{"never":[...]}`; `{"always":[...]}`), `project_connection_id`, `headers`, `server_description`, `authorization`, `connector_id`. https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject and https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- If the connection endpoint differs from `server_url`, the connection endpoint is used. https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication
- Direct MCP tool on a prompt agent via REST (Foundry IQ example, same shape for any MCP server): https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect

```HTTP
POST {project_endpoint}/agents?api-version=v1
Authorization: Bearer {foundry_access_token}
Content-Type: application/json

{
  "name": "{agent_name}",
  "definition": {
    "model": "{deployed_llm}",
    "instructions": "...",
    "tools": [
      {
        "server_label": "knowledge-base",
        "server_url": "{search_service_endpoint}/knowledgebases/{knowledge_base_name}/mcp?api-version=2026-08-01-preview",
        "require_approval": "never",
        "allowed_tools": [
          "knowledge_base_retrieve"
        ],
        "project_connection_id": "{project_connection_name}",
        "type": "mcp"
      }
    ],
    "kind": "prompt"
  }
}
```

- Python declaration: `MCPTool(server_label="api-specs", server_url="https://api.githubcopilot.com/mcp", require_approval="always", project_connection_id=MCP_CONNECTION_NAME)` inside `PromptAgentDefinition(tools=[tool])`. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Approval loop: response item `mcp_approval_request`; continue with `previous_response_id` and: https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

```json
{
  "previous_response_id": "<PREVIOUS_RESPONSE_ID>",
  "input": [
    {
      "type": "mcp_approval_response",
      "approval_request_id": "<APPROVAL_REQUEST_ID>",
      "approve": true
    }
  ]
}
```

- Toolbox alternative is recommended by the docs (single MCP endpoint, central auth, versioning); consumer endpoint `{project_endpoint}/toolboxes/{name}/mcp?api-version=v1`. Direct `mcp` tools on agents remain supported. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

Authentication options

- Key-based, Microsoft Entra agent identity, Microsoft Entra project managed identity, OAuth identity passthrough, unauthenticated. Only OAuth passthrough keeps per-user context. https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication
- Agent identity: "Agent Service uses the available agent identity to request an authorization token and passes it to the MCP server." https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication
- For `agentic-identity` connections "The system intentionally rejects a user token. Assign the agent identity access on the target resource." https://learn.microsoft.com/azure/foundry/agents/how-to/tools/tool-authentication
- Audience: "The audience must match the resource identifier of the downstream service, not the URL of the MCP server itself." Examples: Storage `https://storage.azure.com`, Key Vault `https://vault.azure.net`, Graph `https://graph.microsoft.com`. https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity
- For a custom API protected by Entra, audience = Application ID URI of the app registration, for example `api://aaaabbbb-0000-cccc-1111-dddd2222eeee`. https://learn.microsoft.com/azure/azure-functions/functions-mcp-foundry-tools
- OAuth passthrough: users need Foundry Agent Consumer; same tenant only; with managed OAuth, Microsoft-audience tokens are refused to custom servers ("Cannot pass Microsoft token to untrusted MCP endpoint."); use custom OAuth with your own app registration and add the returned redirect URL. https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication

What APIM must validate

- Policy elements: `tenant-id` (required), `header-name` (default Authorization), `client-application-ids`, `audiences`, `required-claims` (`match` all or any, `separator` for multivalued claims), `output-token-variable-name`. "If a client application ID isn't provided, one or more audience claims should be specified." https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy
- Documented MCP inbound example: https://learn.microsoft.com/azure/api-management/secure-mcp-servers

```xml
<validate-azure-ad-token tenant-id="your-entra-tenant-id" header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Access token is missing or invalid.">     
    <client-application-ids>
        <application-id>your-client-application-id</application-id>
    </client-application-ids> 
</validate-azure-ad-token>
```

- Lab design, not from docs: put the agent identity `instance_identity.client_id` (the token `appid`/`azp`) in `client-application-ids`, and the API app registration client ID and App ID URI in `audiences`; optionally require `roles` contains your app role. Sources for the claim mapping: https://learn.microsoft.com/entra/agent-id/agent-token-claims
- APIM MCP servers: available in Developer, Basic, Basic v2, Standard, Standard v2, Premium, Premium v2. https://learn.microsoft.com/azure/api-management/secure-mcp-servers
- APIM fronting an existing MCP server: backend must conform to MCP `2025-06-18` or later, Streamable HTTP or SSE, tools and resources only (no prompts), not in workspaces; do not read `context.Response.Body` in MCP policies; set Frontend Response payload bytes to log to 0 at global scope. https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server

Limits and protocol behavior

- Non-streaming MCP tool call timeout 100 seconds; longer work needs background mode plus MCP tasks on the server (preview, models such as gpt-5.4 or gpt-5.5). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- "Invalid tool schema" if the MCP tool schema uses `anyOf`/`allOf` or multi-type parameters. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Only remote endpoints; hosting on Container Apps needs HTTP POST/GET endpoints, Functions needs streamable HTTP; State: "Stateless only". https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Max 128 tools registered per agent. https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions
- Catalog example (Azure DevOps MCP) is exposed "over streamable HTTP". https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- Mcp-Session-Id persistence across calls in a run, supported MCP protocol versions, and SSE (legacy) transport support for Agent Service are not documented (docs silent). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

## 5. Knowledge from Azure AI Search

- Two current paths: the Azure AI Search tool (`azure_ai_search`, direct index query) and a Foundry IQ knowledge base exposed over MCP (`knowledge_base_retrieve`). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search and https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- Foundry IQ: "Some Foundry IQ features are now generally available, while others remain in preview ... The Microsoft Foundry portal and Azure portal continue to provide preview-only access to all agentic retrieval features." https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq

Azure AI Search tool

- Parameters: `project_connection_id` (required), `index_name` (required), `top_k` (default 5), `query_type` (default `vector_semantic_hybrid`; values `simple`, `vector`, `semantic`, `vector_simple_hybrid`, `vector_semantic_hybrid`), `filter`. One index per tool; same tenant. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Index requirements: searchable and retrievable `Edm.String` fields, searchable `Collection(Edm.Single)` vector fields, a retrievable content field, "A retrievable field that contains a source URL (and optionally a title) so citations can include a link". https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Sample index fields `embedding`, `token`, `category`, `title`, `url`: "The last two fields are needed to get citation title and URL". Citations render as `[message_idx:search_idx†source]` and stream as `url_citation` annotations. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search

```python
AzureAISearchTool(
    azure_ai_search=AzureAISearchToolResource(
        indexes=[
            AISearchIndexResource(
                project_connection_id=connection_id,
                index_name=SEARCH_INDEX_NAME,
                query_type=AzureAISearchQueryType.SIMPLE,
            ),
        ]
    )
)
```
Source: https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search

- REST toolbox form of the tool: https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search

```json
{
  "type": "azure_ai_search",
  "azure_ai_search": {
    "indexes": [
      {
        "project_connection_id": "<connection ARM id>",
        "index_name": "<index>",
        "query_type": "semantic",
        "top_k": 5
      }
    ]
  }
}
```

- Connection ID format for REST: `/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroupName}}/providers/Microsoft.CognitiveServices/accounts/{{foundryAccountName}}/projects/{{foundryProjectName}}/connections/{{connectionName}}`. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Portal connection: Manage > Project details > Connected resources > Add connection > Azure AI Search > select service and Authentication > Add connection. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Portal add to agent (new playground, documented via toolbox): Add a toolbox > Create a toolbox > Basic info > Included: Add > Add tool > Azure AI Search > Description > select Azure AI Search connection > select one index > Add > Publish, then Save the agent. The tool starts with Simple query type and 5 results (1 to 50 configurable). https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent
- Auth: API key or keyless. Keyless roles per tool page: Search Index Data Contributor and Search Service Contributor on the search service for the Foundry managed identity. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- Playground page: "the Foundry project managed identity needs the Search Index Data Reader role ... Creating an index also requires Search Service Contributor." https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent
- Private VNet requires project managed identity (keyless); key auth unsupported there. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
- The AI Search tool does not support agent identity auth (only MCP and A2A do). https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity
- Vectorizer: Foundry tool docs do not state whether a vectorizer is required. Azure AI Search requires "a vectorizer configured and assigned to a vector field" to convert a text query into a vector at query time. https://learn.microsoft.com/azure/search/vector-search-how-to-query

Foundry IQ knowledge base path

- Knowledge base MCP endpoint `{search}/knowledgebases/{kb}/mcp?api-version=2026-08-01-preview`, connection `RemoteTool` with `ProjectManagedIdentity` and audience `https://search.azure.com/` (snippet in section 1), agent tool `allowed_tools: ["knowledge_base_retrieve"]` (snippet in section 4). https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- Roles: project managed identity gets Search Index Data Reader (plus Contributor if writing); search service managed identity gets Cognitive Services User on the Foundry account only if the KB uses an LLM; creating the connection needs Foundry Project Manager. https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- Citation URL for search index knowledge sources "fall back to the MCP endpoint of your knowledge base". https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- Hosted quickstart uses an `agentic-identity` KB connection and grants the agent identity Search Index Data Reader. https://learn.microsoft.com/azure/foundry/agents/quickstarts/quickstart-foundry-iq-hosted-agent
- Search index knowledge source over an existing index: index needs "plain text or vector content with a semantic configuration"; `semanticConfigurationName` optional from 2026-05-01-preview; GA REST is 2026-04-01. https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-search-index
- Portal flow: Build > Knowledge tab (connect search service, create knowledge base) > Agents tab (connect to knowledge base). https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq

## 6. Tracing

- Connect: Foundry (new) > project > Agents > Traces > Connect (existing or Create new). Fallback: Manage > Project details > Connected resources > Add connection > Application Insights. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup
- Entra ingestion: set Auth type Project Managed Identity; portal assigns Monitoring Metrics Publisher to the project MI; disable local auth on App Insights to enforce Entra-only. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-ingestion-entra-authentication
- Server-side traces are automatic for prompt agents, hosted agents, and workflows after connecting; portal shows 90 days; tracing GA for prompt and hosted agents. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup
- "Tracing is off by default. No trace data is collected or stored unless explicitly enabled by Foundry Account Owner or Foundry Owner." https://learn.microsoft.com/azure/foundry/observability/concepts/trace-data
- Captured: user inputs and outputs, tool calls and results, token use, latency. Conventions: spans `invoke_agent`, `execute_tool`; attributes `gen_ai.tool.definitions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`. https://learn.microsoft.com/azure/foundry/observability/concepts/trace-agent-concept
- MCP-specific span attributes (server label, MCP server URL) are not documented for server-side traces (docs silent). https://learn.microsoft.com/azure/foundry/observability/concepts/trace-agent-concept
- View: agent Traces tab; Conversation view searchable by Response ID or Trace ID with ordered tool calls. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup
- Verify tool spans: open the conversation in Traces and check tool-call span, arguments, result, status, duration. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent
- App Insights portal: Investigate > Agents (Preview). https://learn.microsoft.com/azure/foundry/how-to/develop/langchain-agents
- Tables: GenAI attributes go to `AppDependencies`, `AppTraces`, `AppEvents` and `AppGenAIContent`. From 2026-09-30, newly ingested values of `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.definitions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`, `gen_ai.evaluation.explanation` are only in `AppGenAIContent` (keys remain elsewhere as pointers); opt-out flag `optOutProtectGenAISensitiveData` until 2027-09-30. https://learn.microsoft.com/azure/foundry/observability/how-to/traces-sensitive-content
- `AppGenAIContent` columns include `TraceId`, `SpanId`, `ParentSpanId`, `AgentId`, `AgentName`, `ToolCallArguments`, `ToolCallResult`, `ToolDefinitions`, `InputMessages`, `OutputMessages`, `TimeGenerated`. https://learn.microsoft.com/azure/azure-monitor/reference/tables/appgenaicontent
- Viewer roles: Log Analytics Reader on the App Insights resource; Privileged Monitoring Data Reader if tables are protected. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup
- Suggested KQL, not from docs (verify column names in a spike): `AppGenAIContent | where TimeGenerated > ago(1h) | where isnotempty(ToolCallArguments) | project TimeGenerated, TraceId, SpanId, AgentName, ToolCallArguments, ToolCallResult` then join `AppDependencies` on the trace and span IDs. Column source: https://learn.microsoft.com/azure/azure-monitor/reference/tables/appgenaicontent

W3C trace context to a remote MCP server

- Client-side: the Python SDK injects `traceparent`/`tracestate` into requests from `get_openai_client()` clients (to Azure services), enabled by default when tracing is on. https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-client-side
- Agent Framework injects trace context into MCP `params._meta` only for client-opened sessions; it "does not apply to hosted/provider-managed MCP tool configurations ... or Foundry hosted-agent toolboxes ... propagating traceparent/tracestate across that hosted-service boundary is the responsibility of the service runtime". https://learn.microsoft.com/agent-framework/agents/observability
- Whether Foundry Agent Service itself propagates W3C context (HTTP header or `_meta`) to a remote MCP server for prompt-agent MCP tools is not documented (docs silent). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol

## 7. Foundry RBAC

- Renamed roles: Foundry User (was Azure AI User) `53ca6127-db72-4b80-b1b0-d745d6d5456d`, Foundry Owner `c883944f-8b7b-4483-af10-35834be79c4a`, Foundry Account Owner `e47c6f54-e4a2-4754-9501-8e0985b135e1`, Foundry Project Manager `eadc314b-1a2d-4efa-be10-5d325db5065e`, Foundry Agent Consumer `eed3b665-ab3a-47b6-8f48-c9382fb1dad6`. Use GUIDs in code. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Matrix: Foundry User = data actions + reader + interact with endpoints, no publish, no role assignment; Project Manager = adds publish and can assign Foundry User only; Account Owner = create accounts/projects and manage models but no data actions; Owner/Contributor (Azure) = no data actions. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Enterprise mapping for developers: Foundry User on project scope plus Reader on the Foundry resource. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Do not use Cognitive Services roles (except Cognitive Services Usages Reader at subscription for quota views) or Azure AI Developer for Foundry projects. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Foundry User definition: `Microsoft.CognitiveServices/*/read`, `accounts/listkeys/action`, `Microsoft.Resources/deployments/*`, DataActions `Microsoft.CognitiveServices/*` (no connections write). Project Manager adds `Microsoft.CognitiveServices/accounts/projects/*` and conditional `roleAssignments/write` for Foundry User. https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning
- Connection creation: MCP doc requires Foundry Project Manager for creating a project connection for MCP auth; Foundry IQ requires Project Manager on the parent resource. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol and https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- Foundry Agent Consumer: Azure portal assigns it only at account scope; use CLI for project or agent scope. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Foundry User is auto-assigned only when the resource or project is created in the portal UI by someone who can assign roles, not via SDK or CLI. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- Assigning roles to the agent identity on downstream resources needs Owner, User Access Administrator, or another role with `Microsoft.Authorization/roleAssignments/write`. https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- Observability scenario: "Foundry User (minimum)" and "Add Azure Monitor Reader on Application Insights". https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry

## 8. Models and region

Tool support by model (Agent Service table)

- `gpt-5-mini`: Azure AI Search No, MCP Yes. `gpt-5.4-mini`: Azure AI Search Yes, MCP Yes. `gpt-5.4-nano`: Yes, Yes. `gpt-4.1-mini`: Yes, Yes. `gpt-4.1`: Yes, Yes. `gpt-5.1`: Yes, Yes. `gpt-5.2`: Yes, Yes. https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions

Lifecycle (versions and retirement)

- `gpt-5.4-mini` 2026-03-17 GA, retires 2027-09-21; `gpt-5.4-nano` 2026-03-17 GA, 2027-09-21; `gpt-5-mini` 2025-08-07 GA, 2027-02-09; `gpt-5.1` 2025-11-13 GA, 2027-05-15; `gpt-4.1` and `gpt-4.1-mini` 2025-04-14 Deprecated, 2027-04-14; `gpt-4.1-nano` 2025-04-14 Deprecated, 2026-10-14; `text-embedding-3-small` version 1 GA, 2028-02-09. https://learn.microsoft.com/azure/foundry/openai/concepts/model-retirement-schedule
- `gpt-5.4-mini`: no access request needed; context 400,000 (input 272,000, output 128,000); Responses API and tools supported. https://learn.microsoft.com/azure/foundry/openai/how-to/reasoning and https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure
- Global Standard availability (eastus, eastus2, swedencentral all ticked): gpt-5.4-mini 2026-03-17, gpt-5-mini 2025-08-07, gpt-5.1 2025-11-13, gpt-4.1-mini 2025-04-14, text-embedding-3-small 1. https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability
- Quota tiers (Global Standard): Tier 1 gpt-5.4-mini 1,000 RPM / 1,000,000 TPM; text-embedding-3-small 1,000,000 TPM. Free tier table lists only gpt-4.1-mini, gpt-5-mini, o4-mini, text-embedding-3-small. https://learn.microsoft.com/azure/foundry/openai/quotas-limits
- Default autodeploy environment template still uses gpt-4.1 2025-04-14 GlobalStandard (now Deprecated). https://learn.microsoft.com/azure/foundry/agents/environment-setup

Region

- Agents and Responses API: East US, East US 2, Sweden Central all Yes; tool table: Azure AI Search and MCP yes in all three. https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions
- Azure AI Search: East US and East US 2 carry footnote 2 "This region is in high demand, which prevents the creation of new search services. Please choose a different region." Sweden Central supports AI enrichment, agentic retrieval, semantic ranker (also on free tier), serverless, availability zones, query rewrite. https://learn.microsoft.com/azure/search/search-region-support
- Recommendation: one chat model `gpt-5.4-mini`, version `2026-03-17`, SKU `GlobalStandard`; embeddings `text-embedding-3-small` version `1` GlobalStandard; region Sweden Central. Basis: tool table, lifecycle, availability and Search region sources above. https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions

## Recommendations for the lab design

1. Region: deploy everything per team in Sweden Central. East US and East US 2 currently block new Azure AI Search services, which breaks step (1) of the lab. https://learn.microsoft.com/azure/search/search-region-support
2. Model: `gpt-5.4-mini` `2026-03-17` GlobalStandard (supports both AI Search tool and MCP, GA to 2027-09-21, no access request). Avoid `gpt-5-mini` (no AI Search tool support) and the gpt-4.1 family (Deprecated). Check the subscription quota tier before the event: Tier 1 gives 1M TPM per subscription and region for gpt-5.4-mini, shared by all team deployments; a Free tier subscription has no gpt-5.4-mini quota. https://learn.microsoft.com/azure/foundry/openai/quotas-limits
3. ARM: account `2026-07-01` (kind AIServices, S0, SystemAssigned, `allowProjectManagement: true`, `customSubDomainName`), project `2026-07-01` with SystemAssigned identity, deployments `2026-07-01`, AI Search connection (`CognitiveSearch`, `AAD`) and Application Insights connection. Basic setup only; no capability host. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/change-log/accounts
4. Create the RemoteTool (MCP) connection with `AgenticIdentityToken` and `audience` in the post-deployment script through ARM REST (`2025-10-01-preview`, documented shape) or `azd ai connection create --auth-type agentic-identity`, not in the ARM template, because the template schema does not document these properties. Or let learners create it in the portal (they then need Foundry Project Manager). https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
5. Pre-create the empty agent in the post-deployment script: `POST {project}/agents?api-version=v1` (kind prompt, model deployment name, instructions, no tools) as a principal with Foundry User on the project; then `GET /agents/{name}?api-version=v1` and assert `instance_identity` is non-null; persist `principal_id` (object ID) and `client_id` (app ID) into lab outputs and an APIM named value. https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent
6. MCP security: register one Entra app per lab (or per team) for the MCP API, v2 tokens, App ID URI as the Foundry audience, an app role for tools, assigned to each agent identity; APIM `validate-azure-ad-token` with `tenant-id`, `audiences` (client ID and App ID URI), `client-application-ids` (that team's agent `client_id`), optional `required-claims` on `roles`. Keep a key-based fallback (custom header via connection) in case agent identity tokens fail in the hosting tenant. https://learn.microsoft.com/entra/agent-id/secure-mcp-server-with-entra-id
7. MCP server design: stateless streamable HTTP, respond well under 100 s, no `anyOf`/`allOf` in tool schemas, few tools, `allowed_tools` set, and `require_approval: {"always":["<write_tool>"]}` so learners see an approval for the write tool and none for reads. Behind APIM, target MCP 2025-06-18 or later and avoid response-body policies. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
8. Knowledge: teach the Azure AI Search tool as the main path (Basic setup, GA tool); build an index with `id`, `title`, `url`, `content`, a `Collection(Edm.Single)` vector field with a vectorizer bound to text-embedding-3-small, and a semantic configuration so every `query_type` works. Grant both the project MI and the account MI (docs disagree) Search Index Data Reader, plus the Contributor roles listed by the tool page. Offer Foundry IQ as an optional extension (preview in portal). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
9. Tracing: pre-connect a workspace-based Application Insights per project during provisioning (trace enablement is described as an Account Owner or Owner action); give learners Log Analytics Reader (and Privileged Monitoring Data Reader if `AppGenAIContent` is protected). Teach the Foundry Traces tab first, then KQL on `AppGenAIContent` and `AppDependencies`; send APIM and Container Apps telemetry to the same App Insights. Do not promise automatic W3C parent-child linking from Agent Service into the MCP server; prove it in a spike by logging inbound `traceparent` headers and MCP `params._meta` at APIM and in the server. https://learn.microsoft.com/azure/foundry/observability/how-to/traces-sensitive-content
10. Learner RBAC per team RG: Foundry User on the project, Reader on the account, Foundry Project Manager on the account if learners create connections in the portal, Search Service Contributor plus Search Index Data Contributor on their search service (index creation), Log Analytics Reader on App Insights. No Entra admin role is needed to view the agent identity in the Entra admin center. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
11. Tenant pre-checks: no Conditional Access policy blocking agent identities; agent identity creation not disabled. https://learn.microsoft.com/entra/agent-id/disable-agent-identities
12. Agent identity lookup for learners: primary method is the Foundry REST `GET /agents/{name}` (works with Foundry User), secondary is Entra admin center Entra ID > Agents > Agent identities, searching by the object ID that the lab guide prints. https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network

## Unverified or contradictory

1. Identity timing conflict: the migration guide says new agents get a unique identity and blueprint at creation, while the agent identity concept page, MCP auth page and A2A auth page still say unpublished agents share a project identity until published. Verify `instance_identity` on the pre-created agent. https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-agent-applications vs https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication
2. Publish API conflict: the migration guide says "You can only publish through the Foundry portal - there's no public publish API", but a REST publish flow (`POST /agents/<name>/microsoft365/publish?api-version=v1`) is documented. https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-agent-applications vs https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
3. The migration guide shows `api-version=2025-11-15-preview` with header `Foundry-Features: AgentEndpoints=V1Preview`; current pages and the REST reference use `api-version=v1` without that flag. https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-agent-applications vs https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject
4. ARM template schema for connections omits `AgenticIdentityToken`, `ProjectManagedIdentity`, `UserEntraToken` and `audience`, yet docs create such connections with ARM REST 2025-10-01-preview. Deploying them through an ARM template is untested. https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-07-01/accounts/projects/connections
5. Exact Application Insights connection JSON (which value goes in `target` and `credentials`) is not on Learn; only GitHub templates are referenced. https://learn.microsoft.com/azure/foundry/how-to/connections-add
6. AI Search keyless identity: the tool page assigns roles to the Foundry account system-assigned identity in setup but tells you to assign them to the project managed identity in troubleshooting; other pages say project MI. Role names also differ (Search Index Data Contributor plus Search Service Contributor vs Search Index Data Reader). https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search vs https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent
7. Connection creation role: connections-add says Foundry User, Foundry Owner or Contributor; MCP and Foundry IQ pages say Foundry Project Manager; the Foundry User definition has no write action on connections. https://learn.microsoft.com/azure/foundry/how-to/connections-add vs https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning
8. Tracing enablement actor: "explicitly enabled by Foundry Account Owner or Foundry Owner" vs connection pages allowing other roles. https://learn.microsoft.com/azure/foundry/observability/concepts/trace-data
9. Entra admin center navigation differs: "Entra ID > Agent ID > All agent identities" (Foundry page) vs "Entra ID > Agents > Agent identities" (Entra pages). https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity vs https://learn.microsoft.com/entra/agent-id/agent-lists
10. Viewing rights differ: no admin role (Entra admin center) vs AI Reader (Agent 365 inventory) vs Agent ID Administrator for non-owner delegated Graph list calls. https://learn.microsoft.com/entra/agent-id/agent-registry-convergence
11. Licensing for agent security features differs: Entra P1 (Conditional Access) and P2 (ID Protection, during preview) vs Agent 365 required. https://learn.microsoft.com/entra/agent-id/manage-agent-identities-admin vs https://learn.microsoft.com/entra/agent-id/what-is-microsoft-entra-agent-id
12. The Foundry portal location of a prompt agent's identity is not documented (only hosted agents: Agents > agent > Identity). The display name used for a Foundry agent identity in Entra is not documented. https://learn.microsoft.com/azure/foundry/agents/quickstarts/quickstart-foundry-iq-hosted-agent
13. Not documented for Agent Service MCP: `Mcp-Session-Id` reuse within a run, supported MCP protocol versions, legacy SSE transport support, MCP-specific span attributes, and W3C context propagation to the MCP server. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
14. Whether the agent identity can obtain a token for a custom API without an app role assignment, and which Graph permissions the provisioning principal needs to create that assignment, were not confirmed. https://learn.microsoft.com/entra/agent-id/secure-mcp-server-with-entra-id
15. `xms_par_app_azp` is described as an optional claim in one page and as always present in agent identity tokens in another. https://learn.microsoft.com/entra/agent-id/agent-token-claims vs https://learn.microsoft.com/entra/agent-id/how-to-validate-agent-tokens-downstream-api
16. Portal UI labels drift between pages ("Tools > Add > Custom > Model Context Protocol (MCP) > Create", "Connect a tool > Custom > MCP", "Add a MCP tool"); configuring `allowed_tools` and `require_approval` for a custom MCP tool in the portal is not documented. https://learn.microsoft.com/azure/azure-functions/functions-mcp-foundry-tools vs https://learn.microsoft.com/azure/foundry/mcp/build-your-own-mcp-server
17. Vectorizer requirement for `vector`/hybrid query types of the AI Search tool is not stated in Foundry docs. https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search
18. gpt-5.4-mini parallel tool calls: the reasoning feature table shows not supported, while the model catalog lists "parallel tool calling". https://learn.microsoft.com/azure/foundry/openai/how-to/reasoning vs https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure
19. Minimum `azure-ai-projects` version differs across pages (2.0.0, 2.3.0, 2.5.0, 2.7.0); pin one tested version in the lab. https://learn.microsoft.com/azure/foundry/agents/quickstarts/prompt-agent
20. The KQL in section 6 and the APIM claim mapping in section 4 are lab designs derived from documented columns and claims, not documented queries or policies. https://learn.microsoft.com/azure/azure-monitor/reference/tables/appgenaicontent
21. Foundry Project Manager and model deployments: the RBAC matrix shows "Manage models" not allowed and deployments read-only, while the authentication overview says Project Manager "Includes model deployment creation and update". Pre-deploy models in ARM. https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry vs https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry
22. Toolbox general availability status is not stated clearly (several toolbox sub-features are preview); the lab design above uses a direct `mcp` tool on the agent. https://learn.microsoft.com/azure/foundry/agents/concepts/toolbox-overview
