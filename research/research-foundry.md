# Research: Foundry Agent Service, gpt-5.1, MCP tool approvals and identity, Entra Agent ID, knowledge and tracing

Research notes for the lab "Agentic MSP Support Agent Guided Lab". Researched on 2026-11-06 from Microsoft Learn (read through the Microsoft Learn MCP search and fetch tools), official azure.microsoft.com pricing pages and the Azure Retail Prices API only. No blogs, lab repos or third-party sites were used as sources.

This note replaces the version dated 2026-10-01. Every fact kept from that version was checked again today. Two of its decisions no longer hold: the model is now bound to gpt-5.1 by the requirements [SOW], and Sweden Central now blocks new Azure AI Search services [S27].

Conventions:

- **Bold** text is a UI label (node, tab, filter, column, button, pane section) exactly as written in the cited page. Where pages disagree on a label, both spellings are given and the conflict is listed under OPEN QUESTIONS, the last section.
- [Sxx] is a source ID from section 0. Every statement carries at least one source ID.
- [SOW] points to the binding requirements summary for this lab (SOW revision of 2026-11-06, sanitized). It states requirements, not product facts.
- [TOC] points to the task list in the lab repo (`Instructions/exercise-1.md` to `exercise-7.md`, branch `toc-v3`), used only to name the tasks in section 14.3.
- "Derived from" marks a design judgment that follows from the cited facts. "Lab design" marks code assembled from documented field names rather than copied from a page.
- Status: **GA** means the page carries no preview label. **Preview** means the page labels it preview. **Retiring** means the page announces a retirement date.
- Page text is paraphrased. One short direct quote is used (section 8).
- Coverage: pages marked "partial" in section 0 were too long to read whole; the sections named there were read in full, and code samples in other languages were skimmed.

## 0. Sources

| ID | URL | Page title | Read on |
| - | - | - | - |
| S01 | https://learn.microsoft.com/azure/foundry/openai/concepts/model-retirement-schedule | Model retirement schedule | 2026-11-06 |
| S02 | https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions | Foundry Agent Service limits, quotas, and regional support | 2026-11-06 |
| S03 | https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability | Region availability for Foundry Models sold by Azure (partial: introduction, Global Standard Americas and Europe tables, Data Zone Standard Americas and Europe headers) | 2026-11-06 |
| S04 | https://learn.microsoft.com/azure/foundry/openai/how-to/reasoning | Azure OpenAI reasoning models (partial: all prose and tables; language samples skimmed) | 2026-11-06 |
| S05 | https://learn.microsoft.com/azure/foundry/openai/quotas-limits | Azure OpenAI in Microsoft Foundry Models quotas and limits | 2026-11-06 |
| S06 | https://learn.microsoft.com/azure/foundry/foundry-models/quotas-limits | Microsoft Foundry Models quotas and limits | 2026-11-06 |
| S07 | https://learn.microsoft.com/entra/fundamentals/how-subscriptions-associated-directory | Associate or add an Azure subscription to your Microsoft Entra tenant | 2026-11-06 |
| S08 | https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol | Connect agents to Model Context Protocol servers (partial: all prose, Python, C#, REST; TypeScript and Java samples skimmed) | 2026-11-06 |
| S09 | https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication | Set up authentication for Model Context Protocol (MCP) tools | 2026-11-06 |
| S10 | https://learn.microsoft.com/azure/foundry/agents/how-to/configure-user-delegation | Configure user delegation for tools in Microsoft Foundry | 2026-11-06 |
| S11 | https://learn.microsoft.com/azure/foundry/agents/concepts/user-delegation | User delegation for tools in Microsoft Foundry | 2026-11-06 |
| S12 | https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent-endpoint-authorization | Configure agent endpoint authorization in Microsoft Foundry | 2026-11-06 |
| S13 | https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity | Agent identity concepts in Microsoft Foundry | 2026-11-06 |
| S14 | https://learn.microsoft.com/entra/agent-id/agent-token-claims | Token claims reference for agents | 2026-11-06 |
| S15 | https://learn.microsoft.com/entra/agent-id/agent-on-behalf-of-oauth-flow | Agent OAuth flows: On behalf of flow | 2026-11-06 |
| S16 | https://learn.microsoft.com/rest/api/microsoft-foundry/azureopenai/responses | Azure OpenAI responses, REST reference (partial: MCP tool, MCP tool filter, approval request, approval response and MCP call components) | 2026-11-06 |
| S17 | https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject | Microsoft Foundry REST reference (partial: Conversations operations, MCPTool, MCPToolFilter, MCPToolRequireApproval, MCP output items, PromptAgentDefinition, Reasoning, AzureAISearchTool, AISearchIndexResource, AgentObject) | 2026-11-06 |
| S18 | https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent | Configure and share your agent | 2026-11-06 |
| S19 | https://learn.microsoft.com/entra/agent-id/agent-lists | View and filter agent identities in your tenant | 2026-11-06 |
| S20 | https://learn.microsoft.com/entra/agent-id/manage-agent-identities-admin | Manage agent identities in your organization | 2026-11-06 |
| S21 | https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search | Connect an Azure AI Search index to Foundry agents (partial: all prose, setup tabs, Python and C# samples; Java skimmed) | 2026-11-06 |
| S22 | https://learn.microsoft.com/azure/foundry/agents/concepts/toolbox-overview | What is Toolbox in Foundry? | 2026-11-06 |
| S23 | https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox | Create and manage a toolbox in Foundry (partial: prerequisites, feature support, approval, configure tools, troubleshooting, region) | 2026-11-06 |
| S24 | https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq | What is Foundry IQ? | 2026-11-06 |
| S25 | https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect | Connect a Foundry IQ knowledge base to Foundry Agent Service | 2026-11-06 |
| S26 | https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-search-index | Create a search index knowledge source | 2026-11-06 |
| S27 | https://learn.microsoft.com/azure/search/search-region-support | Supported regions for Azure AI Search | 2026-11-06 |
| S28 | https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup | Set up tracing in Microsoft Foundry | 2026-11-06 |
| S29 | https://learn.microsoft.com/azure/foundry/observability/concepts/trace-agent-concept | Agent tracing overview | 2026-11-06 |
| S30 | https://learn.microsoft.com/azure/foundry/observability/how-to/traces-sensitive-content | Restrict access to sensitive content in Microsoft Foundry traces (preview) | 2026-11-06 |
| S31 | https://learn.microsoft.com/azure/azure-monitor/reference/tables/appgenaicontent | AppGenAIContent | 2026-11-06 |
| S32 | https://learn.microsoft.com/azure/foundry/mcp/build-your-own-mcp-server | Build and register a Model Context Protocol (MCP) server | 2026-11-06 |
| S33 | https://learn.microsoft.com/azure/azure-functions/functions-mcp-foundry-tools | Connect an MCP server on Azure Functions to a Foundry Agent Service agent | 2026-11-06 |
| S34 | https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry | Role-based access control for Microsoft Foundry | 2026-11-06 |
| S35 | https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning | AI + machine learning built-in roles (partial: Foundry Agent Consumer, Foundry Project Manager, Foundry Project Runtime User, Foundry User) | 2026-11-06 |
| S36 | https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview with three `$filter` queries: `serviceName eq 'Foundry Models' and contains(meterName, '5.1')`; `serviceName eq 'Foundry Models' and contains(meterName, 'embedding')`; `armRegionName eq 'canadacentral' and serviceName eq 'Foundry Models'` | Azure Retail Prices API (all pages followed) | 2026-11-06 |
| S37 | https://learn.microsoft.com/azure/foundry/agents/faq | Foundry Agent Service frequently asked questions | 2026-11-06 |
| S38 | https://learn.microsoft.com/azure/foundry/openai/how-to/responses | Use the Azure OpenAI Responses API (partial: "Using remote MCP servers" section and "Delete a response") | 2026-11-06 |
| S39 | https://azure.microsoft.com/en-us/pricing/details/ai-foundry/ | Microsoft Foundry pricing (read through WebFetch) | 2026-11-06 |
| S40 | https://azure.microsoft.com/en-us/pricing/details/foundry-agent-service/ | Foundry Agent Service pricing (read through WebFetch; the page showed placeholder amounts) | 2026-11-06 |
| S41 | https://learn.microsoft.com/azure/foundry/agents/concepts/agent-endpoint-authorization | Agent endpoint authorization in Microsoft Foundry | 2026-11-06 |
| S42 | https://learn.microsoft.com/azure/foundry/agents/how-to/tools/tool-authentication | How toolbox authentication works in Microsoft Foundry | 2026-11-06 |
| S43 | https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-client-side | Add client-side tracing to Foundry agents (preview) | 2026-11-06 |
| S44 | https://learn.microsoft.com/entra/agent-id/disable-agent-identities | Disable agent identities in your tenant | 2026-11-06 |
| S45 | https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/change-log/accounts/projects/connections | API version change log for Microsoft.CognitiveServices/accounts/projects/connections | 2026-11-06 |
| S46 | https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-09-01/accounts/projects/connections | Microsoft.CognitiveServices accounts/projects/connections 2026-09-01 | 2026-11-06 |
| S47 | https://learn.microsoft.com/entra/identity-platform/access-token-claims-reference | Access token claims reference | 2026-11-06 |
| S48 | https://learn.microsoft.com/entra/agent-id/secure-mcp-server-with-entra-id | Secure a Model Context Protocol (MCP) server with Microsoft Entra ID | 2026-11-06 |
| S49 | https://learn.microsoft.com/azure/foundry/observability/how-to/trace-ingestion-entra-authentication | Configure Microsoft Entra authentication for Foundry agent trace ingestion (preview) | 2026-11-06 |
| S50 | https://learn.microsoft.com/azure/foundry/openai/how-to/quota | Manage Azure OpenAI in Microsoft Foundry Models quota | 2026-11-06 |
| S51 | https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent | Configure a voice agent (partial: "Configure in the agent playground" section) | 2026-11-06 |
| S52 | https://learn.microsoft.com/entra/agent-id/what-is-microsoft-entra-agent-id | What is Microsoft Entra Agent ID? | 2026-11-06 |
| S53 | https://learn.microsoft.com/azure/foundry/observability/concepts/trace-data | Tracing and data handling | 2026-11-06 |

## 1. Status at a glance

| Feature | Status | Date or condition | Source |
| - | - | - | - |
| gpt-5.1, version 2025-11-13 | GA, Retiring | Retirement date 2027-07-13; access no longer restricted | S01, S04 |
| text-embedding-3-small, version 1 | GA, Retiring | Retirement date 2028-02-09 | S01 |
| Foundry Agent Service | GA | Some sub-features are public preview | S02 |
| Agent endpoint with the `AzureRbac` scheme (alias `Entra`) and Responses protocol | GA | Default scheme; API keys aren't supported on agent endpoints | S18, S41 |
| Agent endpoint MCP protocol | Preview | | S18 |
| `AgentBlueprint` endpoint authorization scheme | Preview | Changes authorization only for direct runtime clients | S12, S41 |
| MCP tool attached to a prompt agent | GA on the MCP page (no label); another page links it as "(preview)" | Conflict in OPEN QUESTIONS | S08, S32 |
| `RemoteTool` connection category | Labelled "(preview)" on the Foundry IQ page | Conflict in OPEN QUESTIONS | S25 |
| MCP long-running operations (background mode) | Preview | Needs a model that supports background mode, such as gpt-5.4 or gpt-5.5 | S08 |
| MCP authentication: key-based, agent identity, project managed identity, OAuth identity passthrough, unauthenticated | GA (no label) | | S09 |
| Microsoft Entra client user delegation with `UserEntraToken` | GA (no label) | Only for listed Microsoft targets, not custom MCP servers | S09, S10 |
| Agent identity acting on behalf of the user (`AgentOnBehalfOfUser`) | Preview | Requires the `AgentBlueprint` scheme | S10, S11 |
| Toolbox | No status label on the overview; skills inside a toolbox are preview | | S22, S23 |
| Azure AI Search tool | GA (no label) | One index per tool | S17, S21 |
| Foundry IQ | Mixed | GA or preview depends on the Search REST version; the Foundry portal and Azure portal give preview-only access to agentic retrieval features | S24 |
| Foundry IQ knowledge base MCP endpoint | Preview API | `api-version=2026-08-01-preview` | S25 |
| Search index knowledge source | GA in Search REST `2026-04-01`; additions in `2026-05-01-preview` and `2026-08-01-preview` | | S26 |
| Server-side tracing for prompt agents | GA | Off by default; on when an Application Insights resource is connected | S28, S53 |
| Client-side GenAI tracing instrumentation | Preview | | S43 |
| Microsoft Entra authentication for trace ingestion | Preview | | S49 |
| Sensitive trace content only in `AppGenAIContent` | In effect for data ingested from 2026-09-30 | Opt-out flag works until 2027-09-30; early-enablement flag is preview | S30 |
| Subscription-level quota management | Started after 2026-05-07, rolling to all models | | S05, S06 |
| Opt-out of automatic quota tier upgrades | Preview | | S05, S06 |
| Microsoft Entra Agent ID | Available to all Microsoft Entra customers | Extending Entra security features to agents requires Microsoft Agent 365 | S52 |
| Conditional Access for agent identities | GA (no label) | Requires Microsoft Entra ID P1 | S20, S44 |
| ID Protection for agents | Preview | Requires Microsoft Entra ID P2 during preview | S20 |

## 2. Navigation and exact click paths

All Foundry paths are in the Microsoft Foundry portal (new Foundry) at `https://ai.azure.com`; Entra paths are in the Microsoft Entra admin center at `https://entra.microsoft.com` [S19, S28, S33].

| Page or task | Click path | What the page shows | Source |
| - | - | - | - |
| Agent playground | **Build** > select the agent > **Playground** tab | Agent configuration and the test chat | S33 |
| Add a custom MCP tool to an agent | **Build** > select the agent > **Playground** tab > expand **Tools** > **Add** > **Custom** tab in **Select a tool** > **Model Context Protocol (MCP)** > **Create** > in **Add Model Context Protocol tool** enter **Name**, **Remote MCP Server endpoint**, **Authentication** > **Connect** > **Save** | The server appears under **Tools**; Foundry creates the project connection | S09, S33 |
| Authentication choices in that form | **Key-based** (**Credential** key and value); **Microsoft Entra** (**Type**: **Agent Identity** or **Project Managed Identity**, plus **Audience**); **OAuth Identity Passthrough** (**Client ID**, **Client secret**, **Token URL**, **Auth URL**, **Refresh URL**, **Scopes**; copy the **Redirect URL** before **Close**); **Unauthenticated** | No user delegation choice is documented in this form | S33 |
| Same task, alternate labels | **Build** > **Tools** (or Agent Builder) > **Connect a tool** > **Custom** tab > **MCP** > **Name**, **Remote MCP Server endpoint**, **Authentication** (**Key-based**, **Microsoft Entra ID** with **Project managed identity** and **Audience**, **OAuth identity passthrough**) > **Connect** | | S32 |
| Test an MCP tool | Playground chat > send a prompt > for OAuth select **Open Consent** and sign in > review the tool name and arguments > **Approve** | Tool result in the chat | S33 |
| Azure AI Search project connection | **Manage** > **Project details** > **Connected resources** tab > **Add connection** > **Azure AI Search** > select the service and **Authentication** > **Add connection** | Connection listed under connected resources | S21 |
| Attach an Azure AI Search index through a toolbox (documented for voice agents) | Playground **Tools** > **Add a toolbox** > **Create a toolbox** > **Basic info** (**Name**, description) > **Included**: **Add** > **Add tool** > **Azure AI Search** > **Description** > **Azure AI Search connection** (or **Connect to new resource**) > select one index > **Add** > optional **Tool search** > **Publish** > confirm under **Tools** > **Save** | Toolbox attached to the agent; search starts with **Simple** query type and five results | S51 |
| Foundry IQ knowledge base | **Build** > **Knowledge** tab (create or connect a search service, create a knowledge base) > **Agents** tab (select the agent, connect to the knowledge base) > playground | Knowledge base connected as an MCP tool | S24 |
| Connect Application Insights (turn tracing on) | Open the project > left navigation **Agents** > **Traces** at the top > **Connect** on the right > select a resource and **Connect**, or **Create new** | Confirmation message; traces start | S28 |
| Same, alternate path | **Manage** > **Project details** > **Connected resources** tab > **Add connection** > **Application Insights** | | S28 |
| Entra-authenticated trace ingestion | In the connection creation experience set **Auth type** to **Project Managed Identity**; for an existing connection: **Manage** > **Project details** > select the connection > **Edit authentication** > **Project managed identity** > **Save** | Portal assigns **Monitoring Metrics Publisher** to the project managed identity | S49 |
| Find one run | Agent **Traces** tab > search by Response ID or Trace ID > select a **Conversation ID** | Conversation history, tokens, ordered run steps and tool calls, inputs and outputs | S28 |
| Pin the served agent version | Expand **Publish** > version selector arrow > choose a version | Endpoint routes 100% of traffic to that version | S18 |
| Agent identities | **Entra ID** > **Agents** > **Agent identities** > search by **name** or **object ID**; add the **Blueprint App ID** filter; **Choose columns** | List with **Name**, **Created On**, **Status**, **Object ID**, **View Access**, **Blueprint App ID**, **Owners and Sponsors**, **Uses agent identity** | S19, S20 |
| Agent blueprints | **Entra ID** > **Agents** > **Agent blueprints** | Linked agent identities, access, owners and sponsors, audit and sign-in logs | S20 |
| Agent sign-in logs | **Entra ID** > **Monitoring & health** > **Sign-in logs** > filter **Agent type** (**Agent ID user**, **Agent Identity**, **Agent Identity Blueprint**, **Not Agentic**) and **Is Agent** | Sign-ins by agent identities (needs Reports Reader) | S20 |
| Quota | **Manage** > **Quota** > **Token per minute** tab > select a deployment > **Affiliated deployments using shared quota** | Allocation and usage; **Request quota** | S50 |
| Project access | **Manage** > **Project details** > **Users** tab > **Add user** | Only for users who can assign roles | S34 |
| Keyless Azure AI Search setup | Azure portal > search service > **Settings** > **Keys** > **Both**; Foundry account > **Identity** > copy **Object (principal) ID**; search service > **Access control (IAM)** > **Add** > **Add role assignment** | Roles for the Foundry identity | S21 |

Older or alternate names still found: the previous version of this note and the current lab guide use **Entra ID** > **Agent ID** > **All agent identities**, and the Entra admin page still calls the list page **All agent identities** when describing multi-select disable [S20]. Treat **Entra ID** > **Agents** > **Agent identities** as current, because both Entra pages read today give that path [S19, S20]. Updating protocols and authorization schemes isn't configurable in the Foundry portal; use REST or the SDK [S18].

## 3. Models: gpt-5.1 and text-embedding-3-small

- gpt-5.1 version 2025-11-13 is GA and retires on 2027-07-13; text-embedding-3-small version 1 is GA and retires on 2028-02-09 [S01]. All four workshops (December 2026 to April 2027) fall before both dates [S01, SOW].
- Access to gpt-5.1 is no longer restricted [S04]. The Agent Service troubleshooting section still says gpt-5 models need registration; this conflict is in OPEN QUESTIONS [S02, S04].
- Agent Service tool support for gpt-5.1: Azure AI Search Yes, MCP Yes, Functions Yes, File Search Yes, Code Interpreter Yes, OpenAPI Yes, SharePoint Yes, Web Search Yes, Fabric Data Agent Yes, Grounding with Bing Search Yes; Agent2Agent, Browser Automation, Computer Use, Image Generation and Grounding with Bing Custom Search No [S02].
- Context window 400,000 tokens (input 272,000, output 128,000); Responses API, functions and tools, and parallel tool calls are supported [S04]. The feature table shows streaming as not supported for gpt-5.1, which is listed in OPEN QUESTIONS [S04].
- Reasoning effort: gpt-5.1 defaults to `none`, which performs no reasoning; the supported values are `none`, `low`, `medium` and `high`, and tool calls work at every value [S17]. `minimal` doesn't work with gpt-5.1 or later; `xhigh` and `max` don't apply to gpt-5.1 [S04].
- In a prompt agent the setting is `definition.reasoning.effort`; `reasoning.summary` and `generate_summary` accept `auto`, `concise` or `detailed` [S17].
- Unsupported parameters on reasoning models other than GPT-6 Astra: `temperature`, `top_p`, `presence_penalty`, `frequency_penalty`, `logprobs`, `top_logprobs`, `logit_bias`, `max_tokens` [S04]. The prompt agent definition still exposes `temperature` and `top_p` (default 1) [S17]; derived from S04 and S17, leave both unset for gpt-5.1.
- Reasoning tokens occupy the context window and are billed as output tokens; `max_output_tokens` caps reasoning plus visible output [S04]. The docs suggest `low` for tool use, planning, search and multistep decisions where speed and cost matter, and `none` for latency-critical retrieval [S04]. Derived from S04 and the 0.4 million output token budget [SOW]: start with `none` or `low` and measure output tokens in the pilot.
- gpt-5.1 with Chat Completions and tools has no restriction in the tables; the tools restriction on Chat Completions applies to gpt-5.6 models [S04]. Agents use the Responses API [S08].

## 4. Region and quota for 27 isolated environments

### 4.1 Region comparison

| Check | Canada Central | Canada East | East US 2 | Sweden Central | Source |
| - | - | - | - | - | - |
| Agent Service: Responses API and agents | Yes | Yes | Yes | Yes | S02 |
| Azure AI Search tool and MCP tool offered in the region | Yes, Yes | Yes, Yes | Yes, Yes | Yes, Yes | S02 |
| gpt-5.1 2025-11-13 Global Standard | Yes | Yes | Yes | Yes | S03 |
| text-embedding-3-small 1 Global Standard | Yes | Yes | Yes | Yes | S03 |
| Data Zone Standard offered | No | No | Yes (US zone) | Yes (EU zone) | S03 |
| New Azure AI Search services can be created | Yes | Yes | No (region in high demand) | No (region in high demand) | S27 |
| Search agentic retrieval, semantic ranker | Yes, Yes | Yes, Yes | Yes, Yes | Yes, Yes | S27 |
| Search AI enrichment, query rewrite, availability zones | Yes, Yes, Yes | No, No, No | Yes, Yes, Yes | Yes, Yes, Yes | S27 |
| Retail Prices API row for the gpt-5.1 Global meters | Not listed | Listed | Listed | Listed | S36 |
| Region that stores agent data (Basic setup) | Canada Central | Canada East | East US 2 | Sweden Central | S02, S37 |

- Recommendation, derived from the table: deploy every Foundry resource in **Canada Central**, with **Canada East** as the fallback. East US 2 and Sweden Central (the previous build's region) can't create new Azure AI Search services today [S27], and the lab needs one search service per participant [SOW].
- Global Standard prompts can be processed in any Azure region where the model is deployed, while data at rest stays in the designated geography [S03]. Agent Service endpoints are regional and store agent data in the endpoint's region [S02, S37]. Data Zone Standard isn't offered for Canada regions [S03].
- Azure AI Search capacity can change; a preview management call (`POST https://management.azure.com/providers/Microsoft.Search/fetchOfferings?api-version=2026-09-01-preview`) lists regional features and SKUs [S27].
- Region checks for API Management Developer, Container Apps and the Power Platform environment, which the requirements also place in each environment [SOW], belong to the other research notes (OPEN QUESTIONS).

### 4.2 One subscription per environment, and its quota

- A subscription trusts exactly one Microsoft Entra tenant, while a tenant can trust many subscriptions [S07]. Derived from S07 and the isolation requirement [SOW]: each participant tenant needs its own subscription, so a workshop needs 27 subscriptions (25 plus 2 spares), and each reset needs another.
- Moving a subscription to another directory removes its Azure role assignments, breaks key vaults until their tenant ID is changed and requires managed identities to be re-enabled or recreated; CSP subscriptions can't be moved [S07]. Derived from S07: give each reset a fresh subscription rather than moving one.
- Quotas aren't enforced at the tenant level; the subscription is the highest scope [S05, S06]. Since 2026-05-07, Global Standard deployments of the same model and version share one quota pool across all regions of a subscription, rolling out to all models [S05, S06].
- Default quota comes from the subscription's quota tier (Free Tier and Tiers 1 to 6); the tier depends on usage, payment history, the Azure offer and enterprise agreements [S05, S06].

| Tier | gpt-5.1 GlobalStandard RPM | gpt-5.1 GlobalStandard TPM | text-embedding-3-small GlobalStandard TPM | Source |
| - | - | - | - | - |
| Free Tier (Tier 0) | none listed | none listed | 1,000,000 | S05 |
| Tier 1 | 2,500 | 250,000 | 1,000,000 | S05 |
| Tier 2 | 10,000 | 1,000,000 | 2,000,000 | S05 |
| Tier 3 | 25,000 | 2,500,000 | 4,000,000 | S05 |
| Tier 4 | 70,000 | 7,000,000 | 7,000,000 | S05 |
| Tier 5 | 100,000 | 10,000,000 | 10,000,000 | S05 |
| Tier 6 | 150,000 | 15,000,000 | 15,000,000 | S05 |

- A Free Tier subscription has no gpt-5.1 quota and isn't eligible for quota increases [S05]. An approved increase adds quota without changing the tier [S05, S06].
- Check the tier with `GET https://management.azure.com/subscriptions/{id}/providers/Microsoft.CognitiveServices/quotaTiers/default?api-version=2025-10-01-preview` (response field `currentTierName`, for example `Free-Tier` or `Tier 1`) [S05, S06]. Check usage with the Usages API (`.../locations/{location}/usages?api-version=2024-10-01`, quota names `{Provider}.{DeploymentType}.{Model}`) and capacity with the Model Capacities API [S50].
- Rate limits count actual input and generated tokens, not the configured maximum output [S50]. Derived from S05, S50 and the budget [SOW]: 4 million input tokens over a 240-minute window average about 16,700 input tokens per minute per environment, well inside Tier 1 (250,000 TPM) for one participant per subscription.
- Quota edits take up to 15 minutes to propagate [S50]. A Foundry resource deleted through REST keeps its quota for 48 hours unless it's purged [S50].
- Resource limits per subscription and region: 100 Foundry resources, 250 projects per resource, 32 model deployments per resource [S06]; 30 Azure OpenAI resources per region [S05].

## 5. The MCP tool definition and the two-connection design

### 5.1 Fields

| Field | Meaning | Source |
| - | - | - |
| `type` | Always `mcp` | S17 |
| `server_label` | Required; unique within one agent; identifies the server in tool calls and approval items | S08, S17 |
| `server_url` | Remote MCP endpoint; when the project connection's endpoint differs, the connection's endpoint is used | S08, S09 |
| `project_connection_id` | Project connection that stores the endpoint and authentication | S08, S09, S17 |
| `allowed_tools` | Optional; omitted or `[]` exposes every tool on the server; a nonempty list restricts the tools | S08 |
| `require_approval` | Default `always`; `never`; `{"never":[<tools>]}`; `{"always":[<tools>]}` | S08, S09 |
| `headers`, `server_description`, `authorization`, `connector_id` | Optional; `headers` can reference structured inputs such as `{{search_auth_token}}` | S17, S25 |

- The REST references type `allowed_tools` as a list of names or an `MCPToolFilter` object (`tool_names`, `read_only`), and `require_approval` as an object whose `always` and `never` members are `MCPToolFilter` objects; `read_only` matches tools annotated with `readOnlyHint` [S16, S17]. The Foundry how-to pages show plain name lists instead [S08, S09]. Which shape Agent Service accepts is in OPEN QUESTIONS.
- Limits: 128 tools and 1,000 versions per agent, fixed [S02]; non-streaming MCP tool calls time out after 100 seconds [S08]; tool schemas with `anyOf`, `allOf` or multi-type parameters fail with "Invalid tool schema" [S08]; Agent Service accepts only remote endpoints, Container Apps hosting needs HTTP POST and GET endpoints, and servers must be stateless [S08].
- Agent versions are immutable; any change creates a version, and by default the endpoint serves the latest version [S18].

### 5.2 Two MCP tools on one agent

- An agent can carry several MCP servers as tools, each with a unique `server_label` and its own `server_url` [S08]; each tool references its own `project_connection_id` [S08, S09]. No page read today forbids two tools whose connections point at the same server, and none confirms it (OPEN QUESTIONS).
- The user delegation page advises against exposing both connections for the same tool in one agent version (written for migrations) [S10]. Derived from S08 and S10: keep the two `allowed_tools` sets disjoint so that no tool name is reachable through both connections.
- Derived from S08 and S09: give each tool its own gateway path through its own connection, so the gateway and the MCP server can tell read traffic from write traffic.

Lab design, assembled from the documented fields [S08, S17, S21]; tool names come from the requirements [SOW]:

```json
{
  "name": "msp-support-agent",
  "definition": {
    "kind": "prompt",
    "model": "<gpt-5.1 deployment name>",
    "instructions": "<agent instructions>",
    "reasoning": { "effort": "<none or low, decided in the pilot>" },
    "tools": [
      {
        "type": "mcp",
        "server_label": "servicedesk-read",
        "server_url": "https://<apim-name>.azure-api.net/servicedesk-read/mcp",
        "project_connection_id": "<read connection name>",
        "allowed_tools": ["get_customer", "search_customers", "search_tickets", "get_ticket",
          "get_open_tickets", "get_ticket_history", "search_kb_articles", "get_kb_article",
          "get_sla_status", "get_assignment", "list_technicians", "get_similar_tickets",
          "get_ticket_notes"],
        "require_approval": "never"
      },
      {
        "type": "mcp",
        "server_label": "servicedesk-write",
        "server_url": "https://<apim-name>.azure-api.net/servicedesk-write/mcp",
        "project_connection_id": "<write connection name>",
        "require_approval": "always"
      },
      {
        "type": "azure_ai_search",
        "azure_ai_search": {
          "indexes": [
            {
              "project_connection_id": "<search connection ARM ID>",
              "index_name": "<index name>",
              "query_type": "vector_semantic_hybrid",
              "top_k": 5
            }
          ]
        }
      }
    ]
  }
}
```

- The write tool omits `allowed_tools`, so every tool the write path exposes, including a tool a participant adds, appears with approval required; this relies on the write path exposing only write tools (derived from S08 and the approval rule [SOW]). The read tool lists its tools explicitly, so a new tool never appears there without approval (derived from S08).
- Create the agent with `POST {project_endpoint}/agents?api-version=v1` and new versions with `POST {project_endpoint}/agents/{agent_name}/versions?api-version=v1`, using a token for `https://ai.azure.com/.default` [S08].
- Toolbox alternative: the docs recommend toolboxes for reuse [S08], but a toolbox MCP endpoint doesn't block `tools/call` when approval is required; the agent runtime must enforce it [S23]. Inside a toolbox, MCP tool names are prefixed with `server_label` [S23], and a prompt agent's identity needs **Foundry User** on the project to use a toolbox [S23]. Derived from S08 and S23: attach the two MCP tools directly to the agent so that Agent Service raises `mcp_approval_request` itself.

## 6. Tool approvals

### 6.1 Items

| Item | Fields | Source |
| - | - | - |
| `mcp_approval_request` (output) | `id`, `type`, `server_label`, `name` (tool), `arguments` (JSON string); output items also carry `response_id` and `agent_reference` (`name`, `type`, `version`) | S16, S17 |
| `mcp_approval_response` (input) | `approval_request_id`, `approve` (true or false), optional `reason`, optional `id` | S16, S17 |
| `mcp_call` (output) | `id`, `name`, `server_label`, `arguments`, `output`, `error`, `status` (`in_progress`, `completed`, `incomplete`, `calling`, `failed`), `approval_request_id`, `response_id` | S16, S17 |
| `oauth_consent_request` (output) | `id`, `consent_link` | S09 |

Continue after a decision by sending the response item in the same conversation (copied from S08):

```bash
curl -X POST "$AGENT_OPENAI_ENDPOINT/responses?api-version=v1" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d '{
    "conversation": "'$CONVERSATION_ID'",
    "input": [
      {
        "type": "mcp_approval_response",
        "approval_request_id": "'$APPROVAL_REQUEST_ID'",
        "approve": true
      }
    ]
  }'
```

### 6.2 Behavior

- With `require_approval` set to `always`, every call needs its own approval [S08]. Approval exists so that no data reaches a remote MCP server before the user agrees [S38].
- If the agent doesn't continue after approval, the follow-up wasn't sent in the same conversation or used the wrong `approval_request_id` [S08]. With the Copilot harness, use the conversation, not `previous_response_id` [S08].
- Deny: the samples send `approve` set to false (the C# sample denies any call from an unexpected `server_label`) [S08]. No page read today describes what the model receives after a denial or how `reason` is used (OPEN QUESTIONS); the requirement that the agent says the call wasn't approved [SOW] must come from the agent instructions and be verified in the pilot.
- Expiry: no page read today documents a timeout for a pending approval (OPEN QUESTIONS). Stored responses are kept 30 days by default in the Responses API [S38], and Agent Service data persists until deleted [S37], so a pending approval may stay answerable for a long time (derived).
- Portal playground: the tool name and arguments are shown for review, and **Approve** allows the call [S32, S33]. No page read today states whether the playground shows the server label or names the deny control (OPEN QUESTIONS). Derived from S16 and S17: a custom client can show `server_label`, `name` and the full `arguments` because the item carries all three.
- Best practice from the docs: require approval for tools that write data, review the tool name and arguments, treat tool descriptions and results as untrusted input, and log approvals and tool calls [S08].

## 7. MCP authentication options and the token the gateway receives

| Method | Portal label | Connection type (REST or azd) | Who is presented at the gateway | Token claims the gateway receives | Carries the signed-in user | Works from the Foundry playground | Status | Source |
| - | - | - | - | - | - | - | - | - |
| Key-based | **Key-based** | `CustomKeys` (REST), `custom-keys` (azd) | Shared secret in the connection | No Entra token; the stored header value (for example `Authorization`) | No | Yes | GA | S09, S33, S42, S46 |
| Agent identity | **Microsoft Entra**, Type **Agent Identity** | `agentic-identity` (azd); REST value not shown on pages read today | Agent identity, app-only | `idtyp` `app`; `oid` agent identity object ID; `azp` or `appid` agent identity application ID; `roles` granted; `xms_act_fct` and `xms_sub_fct` `11`; `scp` empty or `/`; `aud` the configured audience | No; user tokens are rejected for this type | Yes | GA | S09, S13, S14, S33, S42 |
| Project managed identity | **Microsoft Entra**, Type **Project Managed Identity** | `ProjectManagedIdentity` (REST), `project-managed-identity` (azd) | Project managed identity, app-only | App-only token for the configured audience | No | Yes | GA | S09, S25, S33, S42 |
| User Entra token | Not in the portal form | `UserEntraToken` | Foundry (Foundry-audience callers) or the agent identity (blueprint-audience callers), for the user | Only for listed Microsoft targets; not for custom MCP servers | Yes | Not for custom servers | GA | S09, S10, S11 |
| Agent on behalf of user | Not in the portal form | `AgentOnBehalfOfUser` (REST connection) | Agent identity acting for the signed-in user | `idtyp` `user`; `oid` the user; `scp` the delegated scopes set on the connection; `azp` or `appid` the agent identity application ID; `xms_act_fct` `11`; `aud` the downstream API | Yes | No | Preview | S10, S11, S12, S14 |
| OAuth identity passthrough (custom OAuth) | **OAuth Identity Passthrough** | `OAuth2` (REST), `oauth2` (azd) | Signed-in user, through the OAuth client app you register | Delegated user token: `aud` your API, `scp` granted scopes, `azp` or `appid` your client app ID, `oid` the user; no agent identity facets (derived from S14, S47) | Yes | Yes (**Open Consent**) | GA | S09, S33, S42, S47 |
| Unauthenticated | **Unauthenticated** | `none` | Nobody | None | No | Yes | GA | S09, S33 |

Details by method:

- Agent identity: Agent Service runs a four-stage exchange (blueprint credential, agent identity token, token scoped to the downstream audience, call) [S13]. The audience identifies the resource that accepts the token, which need not be the tool endpoint's URL; for a custom API protected by Entra it is the Application ID URI of its app registration [S13, S33]. An MCP server may also register its own HTTPS URL as an Application ID URI when it issues v2 tokens [S48]. For app-only callers, define app roles (allowed member type Applications) on the API and assign them to the agent identity; they arrive in `roles` [S48].
- Project managed identity: every agent in the project shares that identity's access [S09].
- `UserEntraToken`: Foundry acts for the user only for a limited set of Microsoft-owned tools, never for custom servers [S11]; for a custom MCP server use `AgentOnBehalfOfUser` [S10].
- `AgentOnBehalfOfUser`: the endpoint must use the `AgentBlueprint` scheme and the incoming token must target the agent blueprint [S10, S11]; in the Entra flow, the user token presented for the exchange must be audienced to the blueprint client ID, otherwise `AADSTS50013` [S15]. The connection needs exact, fully qualified scopes of one downstream resource [S10]. Consent comes from interactive consent, preauthorization of the agent blueprint in the downstream app's `api.preAuthorizedApplications`, or tenant administrator consent [S10]. Conditional Access can govern these calls [S11].
- OAuth identity passthrough: Agent Service shows a consent link (`oauth_consent_request`) the first time each user uses each connection, then stores and refreshes that user's credentials [S09, S11]. Consent is per tool connection per project [S09]. Custom MCP servers need custom OAuth with your own app registration: managed OAuth refuses to pass Microsoft-audience tokens to untrusted endpoints [S09]. Required fields: Client ID, optional client secret, Auth URL, Token URL, Refresh URL, Scopes (space-separated, include `offline_access`); then add the returned redirect URL to the app [S09]. The user's tenant must match the project's tenant [S09].
- The Azure OpenAI MCP client needs TLS 1.2 or later, doesn't support mutual TLS, and doesn't support Azure service tags for MCP client traffic [S38]. Whether these Responses API statements also bind Agent Service is in OPEN QUESTIONS.

What the gateway should validate (derived from S14, S47, S48): v2 tokens (`requestedAccessTokenVersion` 2) [S48]; signature, `iss` (v2 issuer), `tid`, `aud` equal to the MCP API client ID, expiry, then `scp` for delegated tokens or `roles` for app tokens [S48]; for agent callers, `azp` equal to the agent's `instance_identity.client_id` and `xms_act_fct` containing `11` [S14, S18]. Log `xms_par_app_azp` (the blueprint) but don't authorize on it [S14].

## 8. Recommended identity and token design

The requirements say the agent calls tools as its Agent ID, the gateway validates the call, and the MCP server acts in Dataverse for the signed-in user [SOW]. Only one documented path presents both the agent identity and the user to a custom gateway: `AgentOnBehalfOfUser` [S10, S14]. The concept page limits it: "This behavior currently applies to direct runtime clients." [S11]

### 8.1 Recommended: agent identity on behalf of the user (preview), with a lab chat client

1. Provisioning, per tenant, by the supplier's administrator (derived from S10, S12, S18, S48):
   1. Register the MCP gateway API: v2 tokens, an Application ID URI, delegated scopes such as `Tickets.Read` and `Tickets.Write` [S48].
   2. Create the agent; read `instance_identity.client_id` and `blueprint.client_id` with `GET {project_endpoint}/agents/{agent_name}?api-version=v1` [S12, S18].
   3. Add the `AgentBlueprint` scheme next to `AzureRbac` (keep both during preview) [S10, S12].
   4. Create two `RemoteTool` connections with `authType` `AgentOnBehalfOfUser`, one with the read scope and one with the write scope, each targeting its gateway path [S10].
   5. Record the permissions on the blueprint (`requiredResourceAccess`, `inheritablePermissions`) through Microsoft Graph or the Foundry `managedAgentIdentityBlueprints` API [S10].
   6. Preauthorize the blueprint on the API app, or grant tenant administrator consent [S10, S15].
   7. Register a client app for the chat client with the delegated permission `api://<blueprint client id>/access_agent`, preauthorized on the blueprint so users aren't prompted [S12, S41].
2. Runtime: the participant signs in to the chat client, which requests `api://<blueprint client id>/access_agent` and calls the agent's Responses endpoint; Agent Service exchanges that token for one addressed to the gateway API, carrying the user and the agent [S10, S12, S14]. The gateway validates it (section 7) and the MCP server uses the user's `oid` for its Dataverse call (the method belongs to the Dataverse note).
3. The chat client renders each `mcp_approval_request` with `server_label`, `name` and the full `arguments`, sends `mcp_approval_response`, and can deny automatically after a timeout and write every request and decision to Log Analytics (derived from S16, S17).
4. Tier 1 needs no Foundry role to chat, because the `AgentBlueprint` scheme authorizes runtime access without Foundry RBAC [S41].

Endpoint configuration (copied from S12; placeholders unchanged):

```http
PATCH {{project_endpoint}}/agents/{{agent_name}}?api-version=v1
Authorization: ******
Content-Type: application/merge-patch+json

{
  "agent_endpoint": {
    "authorization_schemes": [
      {
        "type": "AzureRbac",
        "isolation_key_source": {
          "kind": "Entra"
        }
      },
      {
        "type": "AgentBlueprint",
        "isolation_key_source": {
          "kind": "Entra"
        },
        "token_validation_rules": {
          "allowed_clients": [
            "<client-application-id>"
          ]
        }
      }
    ]
  }
}
```

Connection properties (copied from S10):

```json
{
  "properties": {
    "category": "RemoteTool",
    "target": "<tool-endpoint>",
    "authType": "AgentOnBehalfOfUser",
    "scopes": [
      "<fully-qualified-delegated-scope>"
    ],
    "metadata": {
      "type": "generic_mcp"
    }
  }
}
```

Preview and risk list for this design: the `AgentBlueprint` scheme [S12, S41] and `AgentOnBehalfOfUser` [S10, S11] are preview; the Foundry playground can't drive these tool calls [S11, S12], so participants chat in a lab-built client; Conditional Access "Block users signing into agents" would block the flow [S44]; whether the MCP server can run a further on-behalf-of exchange with this token is undocumented (OPEN QUESTIONS).

### 8.2 Fallback: OAuth identity passthrough in the playground

- Both connections use custom OAuth with the lab's API app registration; each user selects **Open Consent** once per connection [S09, S33]. The gateway receives the user's delegated token issued to the OAuth client app; the agent identity isn't in that token (derived from S14, S47).
- Record it as the closest working equivalent under the platform-dependency clause [SOW]. Users need at least **Foundry Agent Consumer** [S09, S42]; whether that is enough for the portal playground is in OPEN QUESTIONS.

### 8.3 Rejected: agent identity, app-only

- The gateway receives only the agent identity, with no user context [S09, S14]. Derived from S09 and S14: the MCP server would have to trust a user name supplied by the model, which can't enforce the user's Dataverse role.

## 9. Entra Agent ID for Foundry agents

- Creating an agent provisions a unique agent identity blueprint and an agent identity for its default instance; the identity starts with no permissions [S13]. Legacy agents use a shared project identity [S13]; `agent.identity` null marks an agent without a unique identity [S18].
- Agent object properties: `instance_identity` (`principal_id`, `client_id`) and `blueprint` or `blueprint_reference`, both read-only and not shown in the portal [S18]. Read them with `GET {endpoint}/agents/{agent_name}?api-version=v1` [S18].
- Foundry places a federated identity credential on the blueprint that trusts the first-party application `0736f41a-0425-4b46-bdb5-1563eff02385` in your tenant; no secret or certificate is involved [S13].
- An agent identity is a special service principal created under a blueprint, which can impersonate it [S13]. Foundry agent identities appear in the tenant-wide inventory in the Microsoft Entra admin center [S13].
- In the admin center: **Entra ID** > **Agents** > **Agent identities**; search by name or object ID or filter by **Blueprint App ID**; the details show the parent blueprint, owners and sponsors, granted permissions and roles, and audit and sign-in logs [S19, S20].
- Viewing needs only a Microsoft Entra user account, no admin role; managing needs Agent ID Administrator or Cloud Application Administrator, or ownership of the agent identity [S19, S20]. Agent sign-in logs need at least Reports Reader [S20].
- Audit logs record agent identity creation under the base type (for example "add service principal"); the `agentType` property identifies agent events [S20, S44].
- Tenant pre-checks: Conditional Access policies can block agent identity authentication (Policy 1), agent user accounts (Policy 2) and users signing into agents (Policy 3) [S44]. Foundry agent identity creation can be blocked by withholding the roles that create projects and agents [S44].
- The Foundry portal location of a prompt agent's identity and the display name Entra gives a Foundry agent identity aren't documented on pages read today [S13, S18, S19] (OPEN QUESTIONS).

## 10. Knowledge: Azure AI Search tool and Foundry IQ

### 10.1 Azure AI Search tool

- Parameters: `project_connection_id` (required), `index_name` (required), `top_k` (default 5), `query_type` (default `vector_semantic_hybrid`; also `simple`, `vector`, `semantic`, `vector_simple_hybrid`), `filter` [S21]. One index per tool (`indexes` maxItems 1) [S17, S21]; the search resource and the agent must be in the same tenant [S21].
- Index requirements: searchable and retrievable `Edm.String` fields, searchable `Collection(Edm.Single)` vector fields, a retrievable content field, and a retrievable source URL field (title optional) so citations can link [S21]. The C# sample notes that its `title` and `url` fields provide the citation title and URL [S21].
- Citations: instruct the agent to cite as `[message_idx:search_idx†source]`; streamed responses carry `url_citation` annotations with `url` and `title` [S21]. Missing citations usually mean the instructions don't ask for them [S21].
- Connections: key-based or keyless; keyless needs RBAC enabled on the search service (**Keys** > **Both**) [S21]. Creation options: portal, `azd ai connection create --kind cognitive-search --auth-type project-managed-identity` (or `api-key`), `az cognitiveservices account project connection create` with `category` `CognitiveSearch` and `authType` `AAD` or `ApiKey`, the management SDK, ARM REST `2025-06-01`, or Bicep [S21]. The Bicep schema supports `CognitiveSearch` with `AAD` or `ApiKey` [S46].
- Keyless roles conflict: the tool page assigns **Search Index Data Contributor** and **Search Service Contributor** to the Foundry account's system-assigned identity, but its troubleshooting table names the project managed identity [S21]; the playground toolbox note and the Foundry IQ page require **Search Index Data Reader** for the project managed identity [S25, S51] (OPEN QUESTIONS).
- Portal: the documented playground path attaches the index through a toolbox; the search starts with **Simple** and five results, adjustable from 1 to 50 [S51]. Verify retrieval in **Traces** (tool-call span, arguments, result, status, duration) [S51].
- A basic agent setup can't use a private search service or one with public network access disabled [S21].

### 10.2 Foundry IQ

- A knowledge base groups knowledge sources and uses agentic retrieval with permission-aware, cited results; several agents can share it [S24]. The portal flow is **Build** > **Knowledge**, then **Agents** [S24]; the portals offer agentic retrieval features as preview only [S24].
- Agent connection: a `RemoteTool` connection (labelled preview) with `ProjectManagedIdentity` and audience `https://search.azure.com/` to `{search}/knowledgebases/{kb}/mcp?api-version=2026-08-01-preview`, and an MCP tool with `allowed_tools` `["knowledge_base_retrieve"]` and `require_approval` `never`; `knowledge_base_retrieve` is the only supported tool [S25].
- Roles: the project managed identity needs **Search Index Data Reader**; the search service identity needs **Cognitive Services User** only if the knowledge base uses an LLM; creating the connection needs **Foundry Project Manager** [S25].
- Citations: blob knowledge sources return the original document URL, while search index knowledge sources return the knowledge base MCP endpoint [S25].
- Per-user filtering: when the caller is a user, Agent Service sets `x-ms-query-source-authorization` from that user's context [S11, S25].
- Relation to an existing index: a search index knowledge source wraps an existing index on the same service; GA REST `2026-04-01` needs a semantic configuration, optional from `2026-05-01-preview`; deleting the knowledge source never deletes an existing index; retrieve requests ignore scoring profiles [S26]. Agentic retrieval is available in Canada Central [S27].
- Recommendation, derived from S21, S24, S25: teach the Azure AI Search tool as the main path. It carries no preview label, and its citations carry each document's own URL and title, which the grounded-retrieval acceptance check needs [SOW]. Foundry IQ search-index sources would cite the knowledge base endpoint instead [S25]. No page read today calls the Azure AI Search tool deprecated; the tool page refers readers who want a managed knowledge base to Foundry IQ [S21]. Offer Foundry IQ as an optional extension.

## 11. Tracing, observability and approval audit

### 11.1 Connect and capture

- Tracing is off by default; connecting an Application Insights resource turns it on, and the docs say a **Foundry Account Owner** or **Foundry Owner** enables it [S53]. A project allows one Application Insights connection [S49].
- Server-side traces are automatic for prompt agents after the connection, and the portal shows the past 90 days [S28]. Entra-only ingestion (preview) uses **Project Managed Identity**, needs local authentication disabled on Application Insights and gives the project identity **Monitoring Metrics Publisher** [S49].
- Captured: user inputs and agent outputs, tool calls and results, token use, durations [S29, S53]. Conventions: spans `invoke_agent` and `execute_tool`; attributes `gen_ai.tool.definitions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result` [S29]. The OpenTelemetry GenAI conventions are in Development status [S29].
- Since 2026-09-30, new values of `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.definitions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result` and `gen_ai.evaluation.explanation` go only to `AppGenAIContent`; `AppDependencies`, `AppTraces` and `AppEvents` keep the keys with a pointer [S30].
- `AppGenAIContent` columns include `TraceId`, `SpanId`, `ParentSpanId`, `AgentId`, `AgentName`, `ModelName`, `InputMessages`, `OutputMessages`, `SystemInstructions`, `ToolDefinitions`, `ToolCallArguments`, `ToolCallResult`, `TimeGenerated` [S31]. Protecting the table makes it readable only with **Privileged Monitoring Data Reader** [S30].
- Latency: traces appear within minutes; client-side and ingestion pages say typically 2 to 5 minutes [S28, S43, S49]. Retention follows the Application Insights and Log Analytics settings [S28].
- Find one run: **Traces** tab, search by Response ID or Trace ID, then open the **Conversation ID** [S28]. Users in the same project or tenant may see trace data, depending on configuration [S53].

### 11.2 Approvals in the audit trail

- No page read today says whether approval requests or decisions produce spans, and MCP-specific span attributes aren't documented [S29] (OPEN QUESTIONS). Approvals are conversation items [S16, S17].
- A script with a Foundry token (`https://ai.azure.com/.default`) can read them [S08, S17]:
  - `GET {project_endpoint}/openai/v1/conversations?agent_name=<agent>` lists conversations (filter by `agent_name` or `agent_id`, pages of up to 100) [S17].
  - `GET {project_endpoint}/openai/v1/conversations/{conversation_id}/items?item_type=mcp_approval_request` (also `mcp_approval_response`, `mcp_call`, `oauth_consent_request`) lists the items [S17].
  - Join `mcp_call.approval_request_id` to the approval items [S16, S17].
- Derived from S17 and S29: have the MCP server return the gateway's correlation ID inside every tool result, so it lands in `mcp_call.output` and `gen_ai.tool.call.result` and joins the conversation to API Management and MCP server logs. A rejected call never reaches the gateway (section 6), so its audit record must come from the conversation items or from the lab chat client.
- W3C trace context: the Python SDK injects `traceparent` and `tracestate` into requests made by clients from `get_openai_client()` [S43]. Whether Agent Service forwards trace context or any conversation or response ID to the MCP server isn't documented (OPEN QUESTIONS).

## 12. Roles: view versus manage

| Role | View | Manage (create, change, delete, approve) | Source |
| - | - | - | - |
| Foundry Agent Consumer (`eed3b665-ab3a-47b6-8f48-c9382fb1dad6`) | No read actions | Interact with agent endpoints only (`accounts/AIServices/endpoints/interact/action`) | S34, S35 |
| Foundry Project Runtime User (`142bfaed-a13f-4c2d-bed2-6db62c4a1009`) | Responses read | Responses write and delete | S35 |
| Foundry User (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) | Read on projects and accounts, metrics | All `Microsoft.CognitiveServices/*` data actions (agents, versions, toolboxes, conversations); no role assignment, no publishing, no control-plane writes such as connections | S34, S35, S51 |
| Foundry Project Manager (`eadc314b-1a2d-4efa-be10-5d325db5065e`) | Yes | Data actions plus `accounts/projects/*` (including connections), publish agents, assign Foundry User only | S34, S35 |
| Foundry Account Owner (`e47c6f54-e4a2-4754-9501-8e0985b135e1`) | Yes | Create accounts and projects, manage models; no data actions | S34 |
| Foundry Owner (`c883944f-8b7b-4483-af10-35834be79c4a`) | Yes | Everything above, including data actions | S34 |
| Log Analytics Reader (or Monitoring Reader or Reader) on Application Insights | Traces and queries | None | S28, S53 |
| Privileged Monitoring Data Reader | Protected `AppGenAIContent` content | None | S30 |
| Cognitive Services Usages Reader (subscription scope) | Quota | None | S34, S50 |
| Microsoft Entra user, no admin role | Agent identities list and details | None | S19, S20 |
| Agent ID Administrator or Cloud Application Administrator | Yes | Manage or disable agent identities | S19, S20, S44 |
| Reports Reader | Agent sign-in logs | None | S20 |

Page-level exceptions:

| Page or task | Roles that can view | Roles that can manage | Source |
| - | - | - | - |
| Create a project connection for MCP authentication | n/a | Foundry Project Manager | S08, S25 |
| Create or update a toolbox from the playground | n/a | Foundry User | S51 |
| Connect Application Insights (enable tracing) | n/a | Foundry Account Owner or Foundry Owner | S53 |
| Assign Foundry Agent Consumer at project or agent scope | n/a | Owner-level role holders, through Azure CLI (the Azure portal offers account scope only) | S34 |
| Change endpoint authorization schemes | n/a | Foundry User or another role that can update the agent (REST or SDK only) | S12, S18 |
| Record permissions on an agent blueprint | n/a | Blueprint owner in Entra, or `managedAgentIdentityBlueprints/write` through Foundry | S10 |
| Call an agent through the `AgentBlueprint` scheme | n/a | Any principal whose token passes the validation rules; no Foundry role | S41 |
| Use an agent with OAuth identity passthrough | n/a | Foundry Agent Consumer minimum (troubleshooting text says Foundry User) | S09, S42 |
| Model deployments | Foundry User and Project Manager read deployments, capacities and usages | Foundry Account Owner, Foundry Owner, Contributor | S34 |

- Least-privilege role to do every Foundry task a participant performs: **Foundry User** at project scope, plus **Reader** on the Foundry resource in the enterprise mapping [S34], plus **Log Analytics Reader** on the connected Application Insights resource [S28].
- Participants can view their agent identity in the Entra admin center without any admin role [S19, S20]; agent sign-in logs need Reports Reader, a directory role the requirements don't allow participants to hold [S20, SOW].

## 13. Licensing and pricing

| Capability | Without an extra license | With an extra license | Source |
| - | - | - | - |
| Create Foundry agents and their agent identities | Yes (Azure consumption only) | Not applicable | S13, S40, S52 |
| View agent identities in Entra | Yes | Not applicable | S19, S52 |
| Conditional Access for agents | No | Microsoft Entra ID P1 | S20, S44 |
| ID Protection for agents | No | Microsoft Entra ID P2 during preview | S20 |
| Extend Entra security features to agents | No | Microsoft Agent 365 (in Microsoft 365 E7, or an add-on) | S52 |

Retail prices (USD, Azure Retail Prices API, `api-version=2023-01-01-preview`, retrieved 2026-11-06) [S36]:

| Model and meter | Product | Price | Unit | Effective | Regions with a row | Source |
| - | - | - | - | - | - | - |
| gpt-5.1 input, meter `GPT 5.1 inp Gl 1M Tokens` | Azure OpenAI GPT5 | 1.25 | 1M tokens | 2025-11-01 | 25 regions including canadaeast, eastus2, swedencentral; not canadacentral | S36 |
| gpt-5.1 cached input, meter `GPT 5.1 cd inp Gl 1M Tokens` | Azure OpenAI GPT5 | 0.125 | 1M tokens | 2025-11-01 | Same | S36 |
| gpt-5.1 output, meter `GPT 5.1 opt Gl 1M Tokens` | Azure OpenAI GPT5 | 10.00 | 1M tokens | 2025-11-01 | Same | S36 |
| text-embedding-3-small Global, meter `text-embedding-3-small-glbl Tokens` | Azure OpenAI | 0.00002 (0.02 per 1M) | 1K tokens | 2024-06-01 | canadaeast, eastus, eastus2, swedencentral; not canadacentral | S36 |

- Example meter IDs (canadaeast): gpt-5.1 input `28319d20-7d1d-5dd4-90fe-70cecabb2d80`, output `539eb0c7-2eb4-5b25-a102-5a01587f1450`, cached input `24b91e3b-3070-5186-926b-025051e7872d`; text-embedding-3-small Global `ab6ba671-b013-534b-a51b-55434cb3b21b` [S36].
- Agent Service: creating or running prompt agents and workflows carries no additional charge; model tokens bill through Foundry Models [S40]. The FAQ lists model inference, Code Interpreter sessions and File Search storage as the charges [S37]. With the MCP tool you pay only for tokens used for tool definitions and calls [S38]. Foundry IQ bills through Azure AI Search [S40]. Tracing bills through Application Insights and Log Analytics [S28, S53]. The Foundry overview page says each product bills at its own rates [S39].
- Reasoning tokens bill as output tokens [S04].
- Budget check, derived from S36 and the included usage [SOW]: 4 million input tokens cost 5.00 USD and 0.4 million output tokens cost 4.00 USD, so 9.00 USD per environment per workshop at list price before cached-input savings; 27 environments across 4 workshops (108 environment-workshops) come to 972.00 USD.

## 14. LAB FEASIBILITY (27 environments per workshop, one Entra tenant and one Azure subscription per participant)

### 14.1 Constraints that drive the design

- Per-tenant isolation means one subscription per environment, each with its own quota tier; a Free Tier subscription can't deploy gpt-5.1 and can't request more [S05, S07, SOW].
- Region: Canada Central supports every Foundry piece the lab uses and still accepts new Azure AI Search services; East US 2 and Sweden Central don't accept new search services [S02, S03, S27].
- The approval display, approval expiry and approval audit that the requirements ask for are fully under the lab's control only in a custom chat client; the playground documents only tool name, arguments and **Approve** [S16, S17, S33, SOW].
- Presenting the Agent ID and the user together at the gateway needs two preview features and a direct runtime client [S10, S11, S12].
- The Bicep schema (`2026-09-01`, unchanged since `2025-04-01-preview`) has no `AgentOnBehalfOfUser`, `ProjectManagedIdentity`, `UserEntraToken` or agent identity auth type and no `audience` or `scopes` property, so the MCP connections need a post-deployment script (ARM REST or `azd ai connection create`) [S09, S10, S45, S46]. Search and Application Insights connections fit the schema (`CognitiveSearch`, `AppInsights` categories) [S46].
- Basic setup keeps agent state in Microsoft-managed storage in the endpoint's region [S02].
- MCP server constraints: remote and stateless, 100-second limit, no `anyOf` or `allOf` in tool schemas [S08]; MCP client traffic can't be filtered by Azure service tags or mutual TLS (Responses API page) [S38].
- Tracing appears 2 to 5 minutes after the action [S43, S49].
- A Conditional Access policy that blocks agent identities or users signing into agents would break the agent's tool calls [S44].

### 14.2 Recommended role set

- Participants (Senior Technician): **Foundry User** on the project, **Reader** on the Foundry resource, **Log Analytics Reader** on the connected Application Insights resource; add **Privileged Monitoring Data Reader** only if `AppGenAIContent` is protected [S28, S30, S34]. No Entra directory role [S19, SOW].
- Tier 1 Technician: with the recommended design, no Foundry role at all [S41]; with the fallback, **Foundry Agent Consumer** at project scope (assigned with Azure CLI) at minimum, and possibly **Foundry User** for the portal playground (OPEN QUESTIONS) [S09, S34].
- The one write role a task could need: **Foundry Project Manager**, only if participants must create connections themselves [S08, S35]. Derived from S08 and S35: pre-create all connections and don't hand this role out.
- No instructor: delivery is self-paced with support by chat and email [SOW]. Supplier administrators provision each tenant from a separate account [SOW].
- Never hand out: Foundry Owner or Foundry Account Owner (full resource control, model management) [S34]; Agent ID Administrator, Cloud Application Administrator or Reports Reader (tenant directory roles) [S19, S20, SOW].

### 14.3 Task classification

| Task | Mode | Role needed | Why | Source |
| - | - | - | - | - |
| 1.1 Verify readiness | Hands-on, read-only | Foundry User; Entra user | Views the agent, its tools and its identity in the participant's own tenant | S18, S19, TOC |
| 1.2 Connect the agent to the knowledge base | Hands-on, write | Foundry User | Creates an agent version or toolbox in the participant's own project; the search connection is pre-created because connections need Project Manager | S08, S35, S51, TOC |
| 1.3 Test retrieval on simple questions | Hands-on, read-only | Foundry User | Chat and citations only | S21, TOC |
| 1.4 Resolve an ambiguous case | Hands-on, read-only | Foundry User | Chat only | S21, TOC |
| 1.5 Explain the reasoning | Hands-on, read-only | Foundry User | Chat; reasoning summaries are supported for gpt-5.1 | S04, TOC |
| 2.1 Identify similar historical incidents | Hands-on, read-only | Foundry User (playground) or none (lab client) | Read tools without approval | S08, S41, TOC |
| 2.2 Summarise a customer's support history | Hands-on, read-only | As 2.1 | Read tools | S08, TOC |
| 2.3 Recommend priority, category and assignment | Hands-on, read-only | As 2.1 | Read tools and grounding | S08, TOC |
| 2.4 Detect an SLA risk | Hands-on, read-only | As 2.1 | Read tools | S08, TOC |
| 3.1 Review the MCP server on the lab VM | Hands-on, read-only | No Foundry role | No Foundry surface | TOC |
| 3.2 Call an existing read tool | Hands-on, read-only | As 2.1 | Read tool, no approval | S08, TOC |
| 3.3 Test tool error handling | Hands-on, read-only | As 2.1 | Errors surface on `mcp_call` (`error`, `status`) | S16, TOC |
| 3.4 Redeploy the MCP server | Hands-on, write | No Foundry role | Only the participant's own server changes | TOC |
| 4.1 Call a write tool with approval | Hands-on, write | As 2.1 | Approval through `mcp_approval_request`; changes only the participant's Dataverse data | S08, TOC |
| 4.2 Separate a public reply from an internal note | Hands-on, write | As 2.1 | Two approvals | S08, TOC |
| 4.3 Chain grounding into action | Hands-on, write | As 2.1 | Search tool plus write tool | S08, S21, TOC |
| 4.4 Tighten a tool boundary | Hands-on, write | No Foundry role | Server-side validation; schemas must avoid `anyOf` | S08, TOC |
| 4.5 Design and add a scoped tool | Hands-on, write | As 2.1 | New tool appears on the write connection with approval when that tool omits `allowed_tools` | S08, TOC |
| 5.1 Map the identities and token flow | Hands-on, read-only | Foundry User; Entra user | `instance_identity` by REST and the Entra list need no admin role; agent sign-in logs need Reports Reader, so that view is screenshots only | S18, S19, S20, TOC |
| 5.2 Verify secure secret handling | Hands-on, read-only | No Foundry role | No Foundry surface | TOC |
| 5.3 Enforce a least-privilege boundary | Hands-on, read-only | Foundry User | Shows that the agent identity starts without permissions | S13, TOC |
| 5.4 Apply user-level authorization | Hands-on, write | Tier 1: none (lab client) or Agent Consumer (fallback) | Second identity in the participant's own tenant | S09, S41, TOC |
| 6.1 Restrict what the agent can return | Hands-on, write | Foundry User | Instruction change creates a new agent version | S18, TOC |
| 6.2 Apply Microsoft Purview data protection | Hands-on, write | No Foundry role | Purview belongs to its own note | TOC |
| 6.3 Trace a single action end to end | Hands-on, read-only | Log Analytics Reader (plus Privileged Monitoring Data Reader if protected) | Traces arrive 2 to 5 minutes later; approvals come from conversation items | S17, S28, S30, S43, TOC |
| 7.1 Run the end-to-end scenario | Hands-on, write | As 2.1 | Same tools in the participant's own tenant | S08, TOC |
| 7.2 Present the business case | Hands-on, read-only | No Foundry role | No Foundry surface | TOC |

### 14.4 Pre-seeding checklist

1. Seven or more days before each workshop: for each of the 27 subscriptions, read the quota tier and swap out any `Free-Tier` subscription; read gpt-5.1 and text-embedding-3-small GlobalStandard usage in Canada Central [S05, S06, S50]. In each tenant, confirm no Conditional Access policy blocks agent identities or users signing into agents [S44].
2. Golden template (Bicep), per environment, in Canada Central: Foundry account and project (Basic setup), deployments of gpt-5.1 `2025-11-13` and text-embedding-3-small `1` as GlobalStandard, the search connection (`CognitiveSearch`, `AAD`) and its roles, the Application Insights connection [S21, S27, S46].
3. Post-deployment script: create the agent; read `instance_identity` and `blueprint`; for the recommended design, add the `AgentBlueprint` scheme, create both `AgentOnBehalfOfUser` connections, record blueprint permissions and preauthorize or consent; create the agent version with both MCP tools and the search tool; assign participant roles (Azure CLI for project-scope Foundry Agent Consumer) [S08, S10, S12, S18, S34].
4. One day before: smoke-test each environment with one read call, one approved write, one denied write, then check that conversation items list the approvals and that a trace appears within 5 minutes [S17, S43].
5. Event day: participants change only objects in their own tenant; nothing is shared [SOW].

### 14.5 Data latency

| Signal or change | Documented latency | Source |
| - | - | - |
| Trace visible in the Foundry portal and Azure Monitor | Within minutes; typically 2 to 5 minutes | S28, S43, S49 |
| Quota allocation change | Up to 15 minutes | S50 |
| New agent version served | Immediate with the default **Always use latest** routing | S18 |
| Toolbox tools after creating a version | Retry after 10 seconds if `tools/list` is empty | S23 |
| Subscription moved to another directory | Several hours before the portal shows everything | S07 |
| Conversation items readable after a response | Not documented | none |
| Agent identity listed in Entra after agent creation | Not documented | none |
| Blueprint consent or preauthorization taking effect | Not documented | none |
| Azure role assignment propagation | Not documented on pages read today | none |
| Time to provision one full Foundry environment | Not documented | none |

### 14.6 Timing and fallbacks

- Run the write that Exercise 6 traces during Exercise 4, so its trace has long arrived before Task 6.3 (derived from S43 and the exercise timings [SOW]).
- If the `AgentBlueprint` scheme or `AgentOnBehalfOfUser` fails in the pilot, switch both connections to OAuth identity passthrough and use the playground (section 8.2) [S09, S33].
- If a subscription lands in Free Tier on the day, swap in a spare environment [S05, SOW].
- If the Foundry IQ portal flow changes, keep the Azure AI Search tool path [S21, S24].
- Expect occasional HTTP 429 responses on shared Global Standard capacity; honor `retry-after-ms` [S50].

## 15. SCREENSHOT SOURCES

All URLs below returned HTTP 200 on 2026-11-06; relative media paths were resolved against each page URL.

- https://learn.microsoft.com/azure/foundry/media/mcp/foundry-open-consent.png : OAuth consent dialog in the Foundry portal [S09]
- https://learn.microsoft.com/azure/foundry/media/mcp/foundry-close-me.png : confirmation after OAuth consent [S09]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/traces-connect.png : Agents tab, Traces, Connect button [S28]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/project-details.png : Manage menu with Project details [S28]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/connected-resources-add-connection.png : Connected resources tab with Add connection [S28]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/choose-connection.png : Choose a connection with Application Insights [S28]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/conversation.png : conversation details pane with trace timeline [S28]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/trace-sensitive-content-on.png : trace with sensitive content hidden [S30]
- https://learn.microsoft.com/azure/foundry/media/observability/tracing/trace-authentication-type-project-managed-identity.png : Auth type Project Managed Identity for trace ingestion [S49]
- https://learn.microsoft.com/azure/foundry/agents/media/tools/ai-search/connection-endpoint.png : search service Overview with the endpoint [S21]
- https://learn.microsoft.com/azure/foundry/agents/media/tools/ai-search/azure-portal.png : search service Keys with Both selected [S21]
- https://learn.microsoft.com/azure/foundry/agents/media/tools/toolbox/toolbox-architecture.png : toolbox architecture diagram [S22]
- https://learn.microsoft.com/azure/foundry/agents/media/agent-object-model.png : projects, agents, versions and endpoint [S18]
- https://learn.microsoft.com/azure/foundry/media/rbac-foundry/foundry-user.png : Foundry User access diagram [S34]
- https://learn.microsoft.com/azure/foundry/media/rbac-foundry/foundry-project-manager.png : Foundry Project Manager access diagram [S34]
- https://learn.microsoft.com/entra/agent-id/media/agent-on-behalf-of-oauth-flow/on-behalf-of-flow.png : agent on-behalf-of token flow [S15]
- https://learn.microsoft.com/entra/agent-id/media/agent-on-behalf-of-oauth-flow/on-behalf-of-flow-token-sequence.png : agent on-behalf-of token sequence [S15]
- https://learn.microsoft.com/entra/fundamentals/media/how-subscriptions-associated-directory/trust-relationship.png : subscription to tenant trust relationship [S07]

None of the pages that describe them (S08, S19, S33) include an image of the playground approval prompt, the playground MCP tool form, the Entra **Agent identities** list or a prompt agent's identity; capture these live in the pilot.

## 16. OPEN QUESTIONS

1. Two MCP tools that reach the same server through two connections on one agent aren't documented either way [S08]; the user delegation page warns against exposing both connections for the same tool in one version [S10]. Test with disjoint `allowed_tools` and separate gateway paths.
2. Shape of `require_approval` and `allowed_tools`: the Foundry how-to pages show name lists such as `{"never":[...]}` [S08, S09], while both REST references use `MCPToolFilter` objects (`tool_names`, `read_only`) [S16, S17]. Test which shape Agent Service accepts, and whether `read_only` honors `readOnlyHint`.
3. What the playground approval prompt shows: the docs mention the tool name and arguments and **Approve** [S32, S33], not the server label or the deny control's name. The requirements need the server, the tool and the full arguments [SOW]. Capture the prompt in the pilot.
4. Approval expiry isn't documented [S08]. Test a pending approval after 10, 30 and 60 minutes, and a new message sent while one is pending.
5. Denial: what the model receives after `approve` false and whether `reason` reaches it aren't documented [S08, S16]. Test the agent's wording with the lab instructions.
6. Whether approvals produce spans or attributes in traces, and which MCP attributes (server label, URL) server-side spans carry, isn't documented [S29]. Query `AppDependencies`, `AppTraces` and `AppGenAIContent` after an approved and a denied call.
7. Whether one user (or a script with the Senior's token) can list another user's conversations isn't documented; the `AzureRbac` scheme derives an isolation key from the Entra token [S17, S18]. This decides whether one script can audit Tier 1 approvals.
8. Whether Agent Service forwards `traceparent`, a response ID or a conversation ID to the MCP server isn't documented [S43]. Log all inbound headers at API Management in the pilot.
9. Playground versus `AgentBlueprint`: the concept page says the Foundry portal, CLI and VS Code are preauthorized first-party clients for blueprint tokens [S41], while two pages say development clients keep the Foundry audience [S11, S12]. Test whether Azure CLI can get `api://<blueprint client id>/access_agent` for a console client, and what the playground does when the agent has `AgentOnBehalfOfUser` connections.
10. Whether the MCP server can run a further on-behalf-of exchange with an agent on-behalf-of token (`aud` the MCP API, `azp` the agent identity) to reach Dataverse isn't documented [S14, S15]. Settle the Dataverse call method in the Dataverse note.
11. Consent for `AgentOnBehalfOfUser`: Foundry documents interactive consent, preauthorization and administrator consent [S10], while the Entra flow says agent identities can't take interactive consent (`AADSTS82014`) and need inheritable permissions with administrator consent [S15]. Use preauthorization or administrator consent at provisioning and verify.
12. Required role for OAuth passthrough users: **Foundry Agent Consumer** minimum in one section, **Foundry User** in the troubleshooting table [S09]; whether Agent Consumer can use the portal playground at all isn't documented [S34, S41].
13. gpt-5.1 streaming: the feature table shows streaming as not supported for gpt-5.1 [S04]. Confirm playground and client streaming behavior.
14. gpt-5 registration: Agent Service troubleshooting says gpt-5 models need registration [S02]; the reasoning page says gpt-5.1 access is no longer restricted [S04]. Confirm a deployment in a fresh subscription.
15. The quota tier of the provisioned subscriptions depends on offer, payment history and agreements [S05]. Check every subscription; arrange quota for any below Tier 1.
16. The Retail Prices API lists no gpt-5.1 Global or text-embedding-3-small Global row for canadacentral [S36]. Confirm the meter and price that Canada Central deployments bill under (expected to match the other regions).
17. "Invalid tool schema" covers `anyOf`, `allOf` and multi-type parameters [S08]; whether MCP output schemas with nullable fields trigger it isn't stated. Test with the server's output schemas.
18. Service tags and mutual TLS: the Responses API page says neither is supported for MCP client traffic [S38]. Confirm for Agent Service before designing gateway network rules.
19. Status labels conflict: the MCP tool page carries no preview label [S08], one page links it as "(preview)" [S32], and the Foundry IQ page labels the `RemoteTool` connection preview [S25].
20. Knowledge label for text agents: the previous guide used **Playground** > **Knowledge** > **Add** > **Azure AI Search**; pages read today document only the toolbox path (voice agents) and the Foundry IQ path [S24, S51]. Capture the current text-agent labels in the pilot.
21. Keyless search roles: the account identity with Search Index Data Contributor and Search Service Contributor [S21] versus the project identity with Search Index Data Reader [S25, S51]. Assign the reader role to both identities in the pilot and keep what works.
22. Whether **Connect to new resource** inside the playground toolbox flow needs Foundry Project Manager, given that Foundry User lacks connection writes [S35, S51].
23. The Foundry portal location of a prompt agent's identity and the Entra display name of a Foundry agent identity aren't documented [S13, S18, S19].
24. Whether an ARM or Bicep resource type exists for prompt agents wasn't checked today; the pages read create agents through the project REST API or SDKs [S08, S18].
25. Approver identity: `mcp_approval_response` carries no user field [S16, S17]. For approved calls the user comes from the gateway token; for denied calls only the conversation (fallback design) or the lab client (recommended design) can supply it.
26. Whether the playground still runs evaluators by default (seen in the previous build) isn't covered by the tracing and playground pages read today [S28, S51]; check token use in the pilot.
27. Time to provision a full environment (Foundry, deployments, agent identity, connections) isn't documented; measure it against the 60-minute reset and 15-minute spare criteria [SOW].
28. Global Standard may process prompts in any region, and Data Zone isn't offered in Canada [S03]. Confirm that this data handling is acceptable for Canadian participants (the requirements bind Global Standard [SOW]).
29. Regional availability of API Management Developer, Container Apps and the Power Platform environment in Canada [SOW] wasn't checked here; confirm in the gateway, MCP server and Dataverse notes.
30. Duplicate submission: the gateway's correlation ID is new for each request, so a repeated identical write from the model would carry a new ID; whether Agent Service retries tool calls or passes a stable call ID to the server isn't documented [S08, S16]. Settle the idempotency key in the MCP server note.
31. The `AppInsights` connection category exists in the Bicep schema [S46], but no page read today gives the `authType`, `target` and `credentials` values for an Application Insights connection; the portal creates it with key or project managed identity authentication [S28, S49]. Capture the connection JSON from a portal-created connection in the pilot.
