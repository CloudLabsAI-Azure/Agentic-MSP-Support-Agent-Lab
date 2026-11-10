# Design Pack: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phase 1 of 8, plan the delivery.** This is the Milestone 1 design pack of the statement of work: the architecture, the tool catalog, the data specification and the identity and token-flow design, with the adjustments made under the platform-dependency clause. The requester approves it in writing. Start of the path: [README.md](README.md#delivery-path).

**Who:** the delivery lead shares it and records the approval; the requester's technical approver reviews it; the lab author keeps it current. **Time:** about 45 minutes to review.

| | |
|---|---|
| **Pack version** | 1.0, 2026-11-10 |
| **Describes** | Lab version 3.0 (table of contents v3), Golden Environment v1.0, MCP server release 3.0.0, seed data version 3.0 |
| **Status** | Ready for review. Values marked **Pilot** are measured in the pilot and filled in here before Workshop 1 |
| **Coverage** | [SOW-COVERAGE.md](SOW-COVERAGE.md) maps every point of the statement of work to the file that delivers it |

## How to read this pack

- It summarizes the binding design of Exhibits B, C and D as built, and names the file that holds each detail. If this pack and a detailed file ever differ, the detailed file is right and this pack is corrected.
- [Section 8](#8-adjustments-under-the-platform-dependency-clause) lists where a Microsoft service behaves differently from the statement of work, and what the build does instead. Sharing this pack is the written notice for those adjustments; the sign-off confirms them.
- `<DID>` stands for the deployment ID that ends every resource name, and `<tenant domain>` for the participant tenant's domain.

## 1. Architecture (Figure B1)

![Figure B1: one lab environment in its own tenant. The prompt goes from the lab VM to the agent, which grounds on Azure AI Search and calls tools through API Management, the MCP server and Dataverse on behalf of the signed-in technician, with every hop logged under one correlation ID](Instructions/media/architecture.svg)

Every participant gets an identical, isolated copy of this environment in a Microsoft Entra tenant and Azure subscription of their own, in Canada Central.

| Layer | Statement of work (Exhibit B) | As built | Defined in |
|---|---|---|---|
| Agent platform and runtime | Microsoft Foundry Agent Service, GPT-5.1 (Global Standard) and text-embedding-3-small; each agent has its own Microsoft Entra Agent ID | Foundry resource `aif-msp-<DID>` and project `proj-msp-<DID>`; deployments `gpt-5.1` (version 2025-11-13, Global Standard, 100,000 tokens per minute) and `text-embedding-3-small` (Global Standard, 150,000 tokens per minute); the prompt agent `msp-support-agent` with its own Microsoft Entra Agent ID | `setup/bicep/modules/foundry.bicep`, `setup/assets/labfiles/provision/foundry/` |
| Authoritative ticketing backend | Microsoft Dataverse in a Power Platform developer environment, with a custom Service Desk model-driven app | The managed developer environment `Relecloud Service Desk <DID>` (Power Platform region `canada`) with the app **Service Desk**, built into the unmanaged solution `RelecloudServiceDesk`; security roles, the business unit and the column security profile come from `security.json` | `setup/assets/labfiles/provision/powerplatform/`, `setup/assets/labfiles/provision/dataverse/` |
| GLPI | Not used | Not used; Dataverse is the only ticketing backend | |
| MCP server | Azure Container Apps (Consumption), one per participant | `ca-mcp-<DID>` in `cae-msp-<DID>`, single revision mode, image `mcp-server:3.0.0` from the environment's container registry | `setup/bicep/modules/containerapps.bicep` and `registry.bicep`; the MCP server repository |
| Gateway | Azure API Management (Developer tier), one per participant | `apim-msp-<DID>` with the MCP APIs `servicedesk-read`, `servicedesk-write` and `servicedesk-diag` and their policies | `setup/bicep/modules/apim.bicep`, `setup/apim/` |
| Search service | Azure AI Search (Basic), one per participant | `srch-msp-<DID>`, role-based access only; it holds no index until the participant builds `servicedesk-knowledge` in Exercise 1 | `setup/bicep/modules/search.bicep`, `setup/assets/labfiles/search/` |
| Identities | Microsoft Entra ID (a dedicated tenant per environment), Entra Agent ID, managed identities, Dataverse application user | See [section 4](#4-identity-and-token-flow-design) | |
| Secret store | Azure Key Vault, one per participant | `kv-msp-<DID>-<4 characters>` with `mcp-backend-key`, `purview-client-secret` and `apim-diagnostics-key`; its audit log goes to Log Analytics | `setup/bicep/modules/keyvault.bicep` |
| Logging | Log Analytics, Application Insights, Dataverse auditing | `log-msp-<DID>` and `appi-msp-<DID>` (agent tracing through the project connection `appinsights`); Dataverse auditing on for the environment and the Service Desk tables | `setup/bicep/modules/monitoring.bicep`, `schema.json` |
| Data protection | Microsoft Purview (DLP, sensitive information types, sensitivity labels) in each tenant; Dataverse column security | The label `Relecloud Confidential`, the DLP policy `Relecloud Service Desk card numbers` (sensitive information type Credit Card Number) and the column security profile `Contact Phone Protection` | `setup/assets/labfiles/provision/purview/`, [setup/tenant/PURVIEW-RUNBOOK.md](setup/tenant/PURVIEW-RUNBOOK.md) |
| Participant access | Browser access through CloudLabs; Windows lab VM (Standard_D2s_v5) with remote access over HTTPS | `labvm-<DID>`, Standard_D2s_v5 with a Premium SSD P10 OS disk, opened in the browser through CloudLabs | `setup/bicep/modules/labvm.bicep` |

### The numbered path of one request

| Step in Figure B1 | In this build | Where a reviewer finds it |
|---|---|---|
| (1) Prompt from the lab VM | The technician uses the agent in the Foundry portal playground on the lab VM, signed in as themselves | The agent run in Application Insights, and the Foundry conversation |
| (2) Grounding on AI Search | The agent's Azure AI Search tool queries the participant's index through the project connection `search` (Microsoft Entra ID) | The citations in the answer, and the search call in the agent run |
| (3) Tool call through API Management with a correlation ID | The agent calls the MCP tool `servicedesk-read` or `servicedesk-write` with the technician's token. API Management validates it, sets `x-correlation-id` and the user and agent headers, and adds the backend key | `ApiManagementGatewayLogs` and `ApiManagementGatewayMCPLog` |
| (4) MCP server validation, approval and Key Vault secret | A write was approved in the agent before it was sent. The server checks the backend key, which it read from Key Vault at startup through its managed identity, validates every argument and applies the duplicate guard | The MCP server's log line (`ContainerAppConsoleLogs`, event `tool_call`) and the Key Vault audit log |
| (5) Dataverse call on behalf of the signed-in user, audited | The server calls the Dataverse Web API with its managed identity and `CallerObjectId` set to the technician, so Dataverse decides with the technician's role and the server's. A change is audited, and every write attempt adds an **Agent Action** row | The Dataverse audit history and the **Agent Action** table |
| (6) Every hop logged with the same correlation ID | The same ID is in the gateway logs, the MCP log line, the tool result, the Agent Action row, the audit note, and the ticket's **Last Correlation ID** after a field change | `C:\LabFiles\tools\Get-ActionTrail.ps1` joins them with the agent run into one exported trail |

### Flows

- **Data flow.** Provisioning exports 753 searchable documents, one JSON file each, to the storage account's container `servicedesk-export`. The participant builds the index from it in Exercise 1, and the agent retrieves from that index. Ticket reads and writes go from the agent to API Management, the MCP server and the Dataverse Web API. The two new incidents are loaded after the export, so they are never indexed.
- **Identity and authorization flow.** See [section 4](#4-identity-and-token-flow-design).
- **Network flow.** All participant traffic is HTTPS through CloudLabs. The services use Azure public endpoints restricted by authentication: Microsoft Entra ID only on Foundry and AI Search (local authentication off), no shared keys on Storage, TLS 1.2 and HTTPS only, and HTTPS-only ingress on the Container App, whose MCP paths answer only calls that carry the backend key that only API Management holds. There are no IP allow lists ([adjustment 10](#8-adjustments-under-the-platform-dependency-clause)).

### Isolation boundary

- One tenant and one subscription per participant hold the resource group, the Dataverse environment, the agent, the search service, the MCP server, the gateway, the key vault, the logging workspace, the identities and the lab VM. Purview policies, licenses, administrative roles and data exist only in that tenant.
- The participant, the CloudLabs lab user, is a Global Administrator only while provisioning runs. The last provisioning step removes that role, and only when a supplier Global Administrator remains (template parameter `requireSupplierGlobalAdmin`). The Tier 1 Technician never holds a directory role. Supplier administrator accounts are never issued to participants.
- Acceptance criterion 2 tests the boundary negatively in both directions (`tests/acceptance/Test-Isolation.ps1`). A reset gives the participant an environment in a new tenant ([adjustment 7](#8-adjustments-under-the-platform-dependency-clause)).

### Golden Environment v1.0

Every environment is built from the same template (`setup/deploy-01.json`, compiled from `setup/bicep/` with a pinned Bicep version), the same lab files archive with MCP server release 3.0.0, and seed data version 3.0. The readiness check reports the version and a consistency fingerprint for every environment, and the consistency report is shared before each workshop. Any change to the template, the lab files or the MCP server release is released as a new version with a change note in [CHANGELOG.md](CHANGELOG.md).

## 2. MCP server and tool catalog (Exhibit C)

### Hosting and security model

| Requirement (Exhibit C, Part 1) | As built |
|---|---|
| Hosting | One Container App per environment in single revision mode, with its images in the environment's Azure Container Registry, built with ACR Tasks |
| Transport | MCP streamable HTTP (stateless, JSON responses) on `/read/mcp` (read tools only), `/write/mcp` (write tools only) and `/mcp` (every tool, for the diagnostics API, which carries no user), behind the API Management MCP APIs |
| Connectivity | Dataverse Web API over HTTPS |
| Microsoft Entra ID authentication at the gateway | `validate-azure-ad-token` checks the tenant, the client application, the audience (`https://<tenant domain>/servicedesk-mcp`) and the scope `ServiceDesk.Access`; then a rate limit of 120 calls a minute per user |
| Tool-level authorization in the MCP server | Read tools only on the read endpoint and write tools only on the write endpoint (`TOOL_NOT_ON_THIS_ENDPOINT`); write tools refuse a call without a signed-in user (`USER_CONTEXT_REQUIRED`); every argument is validated; business rules such as `PRIORITY_NOT_ALLOWED` for P1 |
| On-behalf-of access to Dataverse | The server's managed identity is a Dataverse application user that holds **Delegate**, and every call carries `CallerObjectId` for the signed-in technician |
| Backend credential in Key Vault through managed identity | Dataverse needs no stored credential, because the managed identity signs in. Key Vault holds the backend key that API Management presents to the server (`mcp-backend-key`: the server reads it at startup, API Management as a named value) and the Purview integration app's secret (`purview-client-secret`) |
| No secrets in code or configuration | The Container App's settings hold names and URLs only. Acceptance criterion 9 scans both repositories, the lab files and the app's configuration |

### Tool catalog

The statement of work sets the baseline; release 3.0.0 publishes every baseline tool under its baseline name, plus four read tools that Exercises 3, 4 and 6 use: 16 read tools and 7 write tools in all.

| Scenario | Read tools (`/read/mcp`, no approval) | Write tools (`/write/mcp`, approval on every call) |
|---|---|---|
| Customer | `get_customer`, `search_customers`, `get_customer_contacts` (added) | |
| Ticket | `search_tickets`, `get_ticket`, `get_open_tickets`, `get_ticket_history` | `update_ticket_status`, `update_ticket_priority`, `update_ticket_category` |
| Knowledge | `search_kb_articles`, `get_kb_article` | `link_kb_article` |
| SLA | `get_sla_status` | |
| Assignment | `get_assignment`, `list_technicians` | `assign_ticket` |
| Historical incidents | `get_similar_tickets` | |
| Communication | `get_ticket_notes` (added) | `add_internal_note`, `add_public_reply` (customer-visible reply) |
| Customer documents (added) | `search_customer_documents`, `get_customer_document` | |

Required permission of each tool, as Dataverse table privileges. Both the signed-in technician's role and the server's application user must hold them:

| Tool | Required permission |
|---|---|
| `get_customer` | Read on account, spk_customerprocedure, spk_customerdocument, annotation, spk_ticket, spk_slapolicy |
| `search_customers` | Read on account |
| `get_customer_contacts` | Read on account, contact (column security applies) |
| `search_tickets`, `get_ticket`, `get_open_tickets` | Read on spk_ticket, account, contact, spk_technician, spk_knowledgearticle |
| `get_ticket_history` | Read on spk_ticket, spk_ticketnote, spk_agentaction |
| `search_kb_articles`, `get_kb_article` | Read on spk_knowledgearticle |
| `get_sla_status` | Read on spk_ticket, account, spk_slapolicy |
| `get_assignment` | Read on spk_ticket, spk_technician, spk_knowledgearticle |
| `list_technicians` | Read on spk_technician |
| `get_similar_tickets` | Read on spk_ticket, account, spk_technician, spk_knowledgearticle |
| `get_ticket_notes` | Read on spk_ticket, spk_ticketnote |
| `search_customer_documents` | Read on account, spk_customerdocument, annotation |
| `get_customer_document` | Read on account, spk_customerdocument, annotation (the sensitivity label applies) |
| `update_ticket_status`, `update_ticket_priority`, `update_ticket_category` | Write on spk_ticket; Create and Append on spk_ticketnote and Append To on spk_ticket (audit note); Create on spk_agentaction (Agent Action row, application user only) |
| `link_kb_article` | Write and Append on spk_ticket, Append To on spk_knowledgearticle; the audit note and Agent Action privileges above |
| `assign_ticket` | Write and Append on spk_ticket, Append To on spk_technician; the audit note and Agent Action privileges above |
| `add_internal_note` | Create and Append on spk_ticketnote, Append To on spk_ticket; Create on spk_agentaction (application user only) |
| `add_public_reply` | Read, Create and Append on spk_ticketnote, Append To on spk_ticket; Create on spk_agentaction (application user only) |

The full catalog, with every input limit, output field and Dataverse call, is `TOOLS.md` in the MCP server repository; `tests/test_catalogue.py` there fails when a tool has no section in it.

### Tool contract (Exhibit C, Part 3)

- Every tool publishes a description, a JSON input schema with a limit on every value, an output schema (the result is `structuredContent` that follows it), its required permission and whether it needs approval (`_meta`: `relecloud/kind`, `relecloud/approval`, `relecloud/permission`).
- Read and write operations are separate tools on separate endpoints and connections, and the server's application user holds two separate Dataverse roles for them.
- Every failure is a structured error (`code`, `message`, `source`, `retryable`, `hint` and, where it applies, `details` and the platform's own `dataverse` answer). Stack traces never reach the agent: an unexpected failure returns `INTERNAL_ERROR`, and the trace stays in the server log under the correlation ID. Results never contain null.

Every invocation writes one JSON line to the server log, with each field Exhibit C asks for:

| Exhibit C field | Log field |
|---|---|
| Correlation ID | `correlation_id`, with `correlation_source` (`gateway` or `generated`) |
| User | `user` (`oid`, `upn`, `name`) from the validated token |
| Agent ID | `agent` (`id`, `name`): the Entra Agent ID that API Management names in `x-agent-id` |
| Tool | `tool`, and `kind` (`read` or `write`) |
| Argument summary | `arguments`: note and reply bodies only as their length, other text shortened to 120 characters, card-like numbers withheld |
| Authorization result | `authorization` (`result`, `decided_by`, `acting_as`) and `authorization_result` |
| Backend call | `backend_calls`: system, method, entity set, status, request ID, duration and whether it ran on behalf of the user |
| Outcome | `outcome` and `error_code` |
| Duration | `duration_ms` |
| Any failure | `error_code`, and the events `tool_exception`, `agent_action_failed` and `audit_note_failed` |

### Approval model for write tools (Exhibit C, Part 6)

| Point | As built |
|---|---|
| Scope | Every tool on `/write/mcp` needs approval, including a write tool a participant adds in Exercise 4 Task 5, because the agent's MCP tool `servicedesk-write` requires approval for every tool it serves. Read tools need none |
| Approver | The signed-in participant approves or declines each call in the playground chat. No second approver |
| Presentation | The playground shows the request with the server label, the tool and the full arguments of that call, and controls to approve or decline it. **Pilot:** record the exact labels here ([BUILD-NOTES.md](BUILD-NOTES.md#open-questions-to-settle-in-the-pilot), question 12) |
| Configuration | Two MCP tools on two project connections: `servicedesk-read` (approval never) and `servicedesk-write` (approval always). A participant can change this only in their own environment |
| Rejection | The tool isn't called and nothing changes; the agent tells the user the action wasn't approved (Exercise 4 Task 1) |
| Timeout | A request without a decision is never executed. Microsoft doesn't document how long a request stays open. **Pilot:** the measured expiry is ______ (acceptance criterion 6, manual check) |
| Duplicate submission | A repeated identical write within 10 minutes isn't executed again, and it returns the first call's result: the same tool and arguments with the same correlation ID, or from the same user after a successful first call ([adjustment 4](#8-adjustments-under-the-platform-dependency-clause)) |
| Audit | The agent run records every approval request and decision with the user and the tool. An approved call also appears in the gateway logs, the MCP log, the Dataverse audit and the Agent Action table under one correlation ID; a declined or expired request appears in the agent run only ([adjustment 5](#8-adjustments-under-the-platform-dependency-clause)) |

### Source and procedures (Exhibit C, Part 4)

- Two private repositories: `CloudLabsAI-Azure/agentic-msp-mcp-server` (the MCP server) and `CloudLabsAI-Azure/Agentic-MSP-Support-Agent-Lab` (the guide, the templates, the provisioning and the tests). The requester's named people get read access in Phase 1. Both hold generic code, configuration templates and synthetic data only: no customer information, participant data or credential.
- On the lab VM, provisioning places a Git repository of the release at `C:\LabFiles\mcp-server`, built from the release tag that the lab files archive carries, with `origin` naming the private repository. Participants need no GitHub account.
- Build, test, deploy, roll back and recover: the section of that name in the MCP server's README. Participants change, test and redeploy their own server with `Deploy-McpServer.ps1` (Exercise 3 Task 4, Exercise 4 Tasks 4 and 5), and nothing they do reaches another environment.

## 3. Data specification (Exhibit D, Part 1)

Generated by `setup/assets/labfiles/seed/generate_seed.py` and loaded into every environment by `load_seed.py`. Generation is deterministic: every environment gets the same records, numbers and answers. The details, the scenario records and the expected results are in [setup/DATA-SPEC.md](setup/DATA-SPEC.md).

| Data set | Minimum | Seeded | Required fields as columns |
|---|---|---|---|
| Customers | 12 | 24 | Name; profile (industry, seats, sites, account manager); products and services (**Services in Scope**); SLA tier; contract type; product versions (backup agent, remote access client, gateway firmware, endpoint agent); configuration notes |
| Contacts | 60 | 72 | Name, customer, role, email and phone; the phone columns are under column security from the start |
| Customer documentation | 36 documents | 36 documents, plus 63 customer procedures and 12 runbooks | 24 support policies, 6 escalation procedures and 6 configuration notes; procedures with escalation contacts and change rules; runbooks |
| Knowledge articles | 120 | 120 (117 Published, 2 Draft, 1 Retired) | Title, symptom, cause, resolution, product, applicability (products, versions, SLA tiers, contract types), related articles |
| Technicians and teams | 15 technicians, 4 teams | 15 technicians in 4 teams, 1 unavailable | Name, team, tier, skills, availability |
| SLA definitions | 4 tiers | 4 tiers by 4 priorities (16 definitions) and 1 business calendar | Response and resolution targets in business hours; the calendar runs Monday to Friday, 08:00 to 18:00 UTC |
| Historical tickets | 500 | 500 | Subject, description, customer, category, subcategory, priority, status, opened, resolved, technician, resolution summary, notes with the internal flag, related article, outcome, SLA fields, tags |
| Open tickets | 60, plus 2 unindexed new incidents | 60, plus TCK-10561 and TCK-10562, loaded after the search export | The same columns, without a resolution yet |
| Communication history | 800 entries | 1,436 notes, 418 of them internal | Customer-visible replies and internal notes, with the internal flag |

All eight scenario types of Exhibit D are seeded, each with its records and expected result in [setup/DATA-SPEC.md](setup/DATA-SPEC.md#scenario-types): ambiguous articles resolved by customer context, incomplete tickets, recurring issues, escalation patterns, technician-specific tickets, similar symptoms across customers, similar issues with different resolutions, and SLA breached and near-breach tickets. The generator's 279 tests check the counts, every scenario and the determinism; acceptance criterion 4 checks the counts and the scenario records in a deployed environment.

## 4. Identity and token-flow design

### Identities (Exhibit D, Part 2)

| Identity | Type | In this build | Permissions |
|---|---|---|---|
| Senior Technician | Entra ID user in the environment's own tenant | The CloudLabs lab user | Dataverse **Service Desk Senior Technician** (read and write on tickets) and **Service Desk Security Steward**; Foundry User on the project; the custom lab role on the resource group, and the search, storage, monitoring and Key Vault roles the exercises need (Key Vault metadata only, never a secret value); no directory role after provisioning. The full list is in [setup/README.md](setup/README.md#identities-and-their-rights) |
| Tier 1 Technician | Entra ID user in the environment's own tenant | `tier1.technician@<tenant domain>`, created from the user-creation JSON | Dataverse **Service Desk Tier 1 Technician** (read-only on tickets); Foundry Agent Consumer on the project |
| Agent | Microsoft Entra Agent ID | The agent ID of `msp-support-agent` | No Dataverse permission. API Management names it in every tool call (`x-agent-id`) |
| Gateway | API Management managed identity | `id-apim-<DID>` | Key Vault Secrets User, to read `mcp-backend-key` as a named value |
| MCP server | Container Apps managed identity | `id-mcp-<DID>` | Key Vault Secrets User and AcrPull |
| Backend | Dataverse application user | `id-mcp-<DID>`, registered as the application user | **Service Desk Agent Read**, **Service Desk Agent Write** and **Delegate**, never System Administrator; it acts on behalf of the signed-in technician |

Supporting identities that Exhibit D doesn't list: `id-prov-<DID>` (the lab VM; its provisioning-only roles are removed at the end, leaving the roles the lab tools on the VM need), the setup app (stripped of every right at the end), the app registration `Relecloud Service Desk MCP Gateway` (the token audience and the OAuth client of both connections), and `Relecloud Service Desk Purview Integration` (which calls the Purview APIs).

### Token flow for one write (Exhibit D, Part 3)

| Hop | What is presented | Scoped to | Delegated or application |
|---|---|---|---|
| Technician to Foundry | The technician's Microsoft Entra ID sign-in on the lab VM | The Foundry portal and the project | Delegated |
| Agent to API Management | The technician's access token, obtained by the connection `servicedesk-write` through OAuth identity passthrough (each user consents once per connection) | Audience `https://<tenant domain>/servicedesk-mcp`, scope `ServiceDesk.Access` | Delegated |
| API Management to the MCP server | No user token. Headers name the user (object ID and name), the client application, the agent and the correlation ID, and the backend key `mcp-backend-key` proves the call came through the gateway | The MCP endpoints | Application (backend key) |
| MCP server to Key Vault, at startup | A token for `id-mcp` | The vault's secrets | Application |
| MCP server to Dataverse | A token for `id-mcp`, with `CallerObjectId` set to the technician | The environment's Web API | Both: the application user calls, and Dataverse authorizes the call with the technician's role and the application user's |

The agent holds no permission on Dataverse, the MCP server never sees the technician's token, and Dataverse makes every authorization decision (Exercise 5 Tasks 3 and 4, acceptance criterion 8).

### Roles, least privilege and secrets (Exhibit D, Part 4)

- Read and write are separated at every layer: two connections, two endpoints, two Dataverse roles for the server and two technician roles. Every identity starts least privileged; participants extend controls that already work.
- Secrets live in Key Vault and are read through managed identity: `mcp-backend-key`, `purview-client-secret` and `apim-diagnostics-key`. When CloudLabs supplies a bootstrap service principal, its secret is stored only in Key Vault and the last provisioning step deletes it. Two credentials are held outside the environment's vault by design; [adjustment 11](#8-adjustments-under-the-platform-dependency-clause) names them.

## 5. Data protection design (Exhibit D, Part 5)

- **Column security on contact fields.** The profile `Contact Phone Protection` secures the contact phone columns from the start. The server's application user is never a member, so `get_customer_contacts` leaves those columns out and names them in `withheld_fields`, and the agent says the detail is restricted instead of guessing it. Exercise 6 Task 1 extends the profile to the email column.
- **Internal flag on notes.** Every note carries the column **Internal Note** (**Internal** or **Customer visible**). `get_ticket_notes` withholds internal notes unless a caller asks for them, the tool descriptions tell the agent never to put them in customer communication, and `add_public_reply` refuses a reply that repeats an internal note (`INTERNAL_CONTENT_IN_REPLY`) or carries a card number (`SENSITIVE_DATA_IN_REPLY`).
- **Microsoft Purview applied to agent interactions.** This is the agreement the statement of work leaves to the design pack: Purview is applied where Service Desk content reaches the agent. Before `get_ticket`, `get_ticket_notes` or `get_customer_document` returns free text, the MCP server, registered in Entra ID as an AI app integrated with the Purview APIs, asks Purview for the signed-in technician (protection scopes for the `uploadText` activity, then `processContent`). The DLP policy `Relecloud Service Desk card numbers` (Credit Card Number, block, scoped to the app) withholds a matching note or description (`withheld_by_policy`) and blocks a whole document (`CONTENT_BLOCKED_BY_POLICY`). When Purview can't answer, nothing is returned (`PURVIEW_UNAVAILABLE`). The sensitivity label `Relecloud Confidential` on the Woodgrove Bank configuration file makes the server refuse that file before Purview is asked (`CONTENT_BLOCKED_BY_LABEL`). The DLP event appears in Purview's Activity explorer after 60 to 90 minutes; the MCP log line records the decision at once.
- **Approval and validation.** Approval is required for every write tool, and every tool validates its input.

## 6. Logging, retention and correlation (Exhibit D, Part 6)

| Source | Where it lands |
|---|---|
| Application Insights (agent) | `appi-msp-<DID>`: the agent run, the tool decisions and the answers |
| API Management | `ApiManagementGatewayLogs` and `ApiManagementGatewayMCPLog` in `log-msp-<DID>` |
| MCP server log | `ContainerAppConsoleLogs` in `log-msp-<DID>`, one line per tool call |
| Key Vault diagnostics | `AZKVAuditLogs` or `AzureDiagnostics` in `log-msp-<DID>` |
| Dataverse audit | The audit history of the Service Desk tables, and the **Agent Action** table for every write attempt |
| Purview events | Activity explorer in the Microsoft Purview portal of the environment's tenant |

- **Retention.** Logs and audit records live in the environment's workspace and tenant and are deleted with the environment when the review window ends. The supplier keeps no participant data, logs or builds after teardown, with one exception the statement of work allows: each subscription's activity log is exported before deletion and kept for 30 days in case the requester asks for it ([setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md#phase-7-close-the-event)).
- **Access.** Each participant sees only their own tenant's logs. The requester's reviewers use the participants' lab access during the 24-hour review window; no participant work is done then.
- **Evidence export.** Participants export their correlated audit trail with `Get-ActionTrail.ps1 -OutFile` to `C:\LabFiles\evidence` in Exercises 6 and 7. Reviewers can export logs and audit records from any environment until the review window ends ([SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#at-the-end-of-the-window)).
- **Correlation.** One correlation ID links the user's request, the agent, the MCP tool, the authorization result, the backend call, the change and the result returned; acceptance criterion 11 proves it.

## 7. Environments, capacity and support (Exhibit E)

- Environments and 2 spares per workshop are deployed at least 24 hours ahead (48 recommended), because a new sensitivity label can take 24 hours. Each passes the readiness check, and the consistency report is shared before access. Everything is ready 30 minutes before the start.
- A failed environment is replaced by a readiness-checked spare within 15 minutes of the report, and the participant's time is extended by the time lost. A reset completes within 60 minutes ([adjustment 7](#8-adjustments-under-the-platform-dependency-clause)).
- Support: CloudLabs live chat (first response within 5 minutes) and email (within 60 minutes), escalation to the delivery manager within 30 minutes ([SUPPORT-GUIDE.md](SUPPORT-GUIDE.md)).
- Model usage: up to 4 million input and 0.4 million output tokens per environment per workshop. Support checks each environment's token use during the window, and the delivery manager tells the requester when an environment reaches 80 percent (3.2 million input or 320,000 output tokens), before any overage.

## 8. Adjustments under the platform-dependency clause

Exhibit H lets the build deliver the closest working equivalent when a Microsoft service doesn't work as a task needs. Each adjustment keeps the exercise's learning outcome, timing and acceptance criteria.

| # | Statement of work | This build | Why | Status |
|---|---|---|---|---|
| 1 | The agent calls tools as its Agent ID and obtains a token for the gateway (Exhibit B flows, Exhibit D Part 3) | OAuth identity passthrough: the connection presents the signed-in technician's token, and API Management names the agent from its configured Agent ID (`x-agent-id`) | The agent's own on-behalf-of-user flow is preview and doesn't run in the portal playground; identity passthrough is generally available. Dataverse still enforces the user's role, and every log names the user and the agent | Confirm |
| 2 | Grounding on AI Search, step (2) of Figure B1 | Authorized by the project connection's Microsoft Entra identity, not by the Agent ID | The Azure AI Search tool isn't among the tools that use the Agent ID | Confirm |
| 3 | Both attempts appear in the Dataverse audit (acceptance criterion 8) | Dataverse audits successful changes only. The MCP server writes an **Agent Action** row in Dataverse for every write attempt, allowed or denied, so the denied attempt is in Dataverse as that row | Platform behavior | Confirm |
| 4 | A repeated identical write with the same correlation ID within 10 minutes returns the first result (Exhibit C Part 6) | The same rule, plus a repeat from the same user after a successful first call within the same 10 minutes | API Management gives every request a new correlation ID, so a repeated approval through the agent would otherwise run twice | Confirm |
| 5 | Every approval request and decision is in the correlated audit trail with the correlation ID, user and tool | A declined or expired request never leaves the agent, so it has no gateway correlation ID. The agent run records the request, the decision, the user and the tool, and `Get-ActionTrail.ps1` lists it in the same trail as **Not called** | Platform behavior | Confirm |
| 6 | The approval expiry is confirmed in the Milestone 1 design pack | Measured in the pilot and recorded in [section 2](#approval-model-for-write-tools-exhibit-c-part-6) | Microsoft doesn't document it | Pilot |
| 7 | A reset deletes the environment and provisions a new one in a new tenant from the current Golden Environment within 60 minutes (acceptance criterion 12) | The participant gets a prepared spare at once: a new tenant, built from the current Golden Environment version and readiness-checked. A replacement spare is deployed straight away, and the old environment is deleted with the others | Building a new environment takes 95 to 140 minutes, and a new sensitivity label up to 24 hours | Confirm |
| 8 | Purview events are a log source (Exhibit D Part 6) | Purview records the DLP decisions on the MCP server's app. Dataverse activity reaches Purview only from production environments, so the Dataverse evidence is its own audit and the Agent Action table | Platform behavior | Confirm |
| 9 | A Power Platform developer environment (Exhibit B) | A managed developer environment, with Power Apps Premium for both technicians | Unmanaged developer environments can't be created from 2026-11-15 | Confirm |
| 10 | Public endpoints restricted by authentication and network rules (Exhibit B network flow) | Authentication restricts every public endpoint ([section 1](#flows)); no IP allow lists | CloudLabs browser access and the CloudLabs validation service reach the environment from addresses that aren't fixed. IP rules on the Container App ingress can be added as a change | Confirm |
| 11 | Secrets and certificates only in Azure Key Vault, read through managed identity (Exhibit D Part 4) | Two credentials are held elsewhere: Foundry keeps the OAuth client secret of the two MCP connections in its Microsoft-managed key vault, outside the subscription; and the setup app's certificate sits in the lab VM's machine certificate store while provisioning runs, and is deleted at the end. Neither is in code or configuration, and no participant can read either | Foundry uses a customer key vault only through a Key Vault connection created before every other connection, which version 1.0 doesn't do yet; the setup app needs its credential on the VM while it provisions | Confirm; a Key Vault connection to `kv-msp-<DID>` is an option for the next version, after a pilot test |
| 12 | GPT-5.1 Global Standard (Exhibit B) | As bound. Global Standard may process prompts in any Azure region, and Data Zone isn't offered in Canada | Recorded so the requester can confirm the data processing location | Confirm |
| 13 | Table of contents wording "your team's" | "your": one participant per environment | The environments are per participant | Done |

## 9. Decisions for the requester

1. Approve the architecture, the tool catalog, the data specification and the identity and token-flow design above.
2. Confirm the adjustments in section 8, or name the ones to change.
3. Confirm that Global Standard data processing is acceptable (adjustment 12).
4. Name the people who get read access to the two private repositories.
5. Agree the workshop report as the completion and participant count evidence for each workshop ([SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#workshop-report)).

## Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Requester's technical approver | | Approved, approved with changes, or returned | |
| Supplier delivery lead | | Submitted | |

The requester reviews this pack within 3 business days of submission (Exhibit A, Part 3).

## Phase checklist

- [ ] This pack, [SOW-COVERAGE.md](SOW-COVERAGE.md) and the acceptance test plan ([tests/acceptance/README.md](tests/acceptance/README.md)) were shared with the requester
- [ ] The requester approved the pack in writing, or the requested changes are recorded in [BUILD-NOTES.md](BUILD-NOTES.md)
- [ ] After the pilot, the **Pilot** values (the approval prompt labels and the approval expiry) are filled in, and the pack was shared again
- [ ] The requester's named people have read access to the two private repositories

---

**Next:** Phase 2, build and publish the template: [setup/README.md](setup/README.md).
