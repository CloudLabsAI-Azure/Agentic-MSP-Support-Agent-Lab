# Agentic MSP Support Agent Guided Lab

- **Lab Type:** Step-by-step guided lab
- **Audience:** Cloud solution architects, AI and agent developers, service desk and MSP platform engineers, and security engineers who govern agent access
- **Audience Level:** Advanced (L300)
- **Total Duration:** 305 minutes of exercises, in a 6-hour session

## Lab Overview

Teams build an AI agent that acts as a workplace intelligence layer over a live ticketing and support environment for Relecloud Managed Services, a fictional managed service provider. Each team has an identical, pre-validated environment: a dedicated Azure resource group, a Microsoft Foundry agent registered under its own Microsoft Entra Agent ID, a Service Desk app on Microsoft Dataverse with seeded customer documentation, procedures, knowledge articles, runbooks and ticket history, a working MCP server with a baseline catalogue of read tools and approval-gated write tools, and the identity, secret storage, gateway, data protection and logging services around them.

The Service Desk is a custom Power Apps model-driven app that Spektra builds over Dataverse tables with the `spk_` prefix. Dataverse is the only ticketing backend, and its security roles enforce every permission. The environment is safe by default: least-privileged identities with read and write separated, the MCP server's backend credential in Azure Key Vault, approval on sensitive write tools, input validation on every tool, and a correlation identifier on every request. Each team signs in with two identities, a Senior Technician and a Tier 1 Technician who is read-only on tickets, and every tool call runs on behalf of the technician who asks. The MCP server source is already cloned on each lab VM; teams change it and redeploy it to their own Container App, with no GitHub account.

The six-hour session is wall-clock, including 15 minutes of sign-in and readiness, three 10-minute breaks and 10 minutes of close and float; hands-on exercises total 305 minutes. The lab is self-paced: participants check their work against the expected results in the guide and contact support for environment failures.

---

## Prerequisites

### Attendee knowledge

- Working knowledge of the Azure portal and resource groups
- Basic PowerShell, and the ability to read Python and JSON
- A general understanding of REST APIs and OAuth access tokens
- Familiarity with service desk concepts (tickets, priorities, SLAs); Power Apps or Dataverse experience helps but isn't required

### Required licences and entitlements

| Licence or entitlement | Entitles | Scope | Provisioned by |
|---|---|---|---|
| **Microsoft Power Apps for Developer** (Power Apps Developer Plan, SKU `POWERAPPS_DEV`) | A Power Platform developer environment with Dataverse, and the right to use the Service Desk app in it (development and test use only) | Per identity: the Senior Technician and the Tier 1 Technician of each team | CloudLabs assigns it to both team accounts before provisioning |
| **Microsoft 365 E5** or **Microsoft 365 E5 Compliance** | Microsoft Purview data loss prevention and sensitivity labels for the agent's interactions | Per identity: both team accounts | CloudLabs assigns it to both team accounts |
| **Microsoft Purview pay-as-you-go** | Purview data security for AI apps through the `processContent` API | Per tenant | Enabled once in the lab tenant (`setup/README.md`) |
| **Microsoft Entra ID Free** (included with the tenant's Microsoft cloud subscription) | Team accounts, the gateway and Purview app registrations, and the Microsoft Entra Agent ID of each agent | Per tenant | The CloudLabs lab tenant |
| **Azure subscription, consumption billing** | Microsoft Foundry models (`gpt-5.4-mini`, `text-embedding-3-small`, billed per token), Azure AI Search Basic, API Management Basic v2, Azure Container Apps, Azure Container Registry Basic, Key Vault, Log Analytics, Application Insights and the lab VM | Per team resource group | CloudLabs (see the cost estimate) |
| **Foundry Models quota (Global Standard, Sweden Central)** | `gpt-5.4-mini`: 30,000 tokens per minute (TPM) per team deployment, which also sets about 30 requests per minute; `text-embedding-3-small`: 30,000 TPM per team deployment | Capacity, shared by every team in the subscription and region | CloudLabs confirms Tier 1 or higher before the event (25 teams use 750,000 of the 1,000,000 TPM Tier 1 quota for each model) |

Not required: Microsoft Agent 365, Microsoft Entra ID P1 or P2, Dynamics 365 licences, Managed Environments, and GitHub accounts (the MCP server source is on the lab VM).

### Azure resources and configuration

The following are pre-provisioned in the CloudLabs environment before the session:

- A team resource group in **Sweden Central** with a lab VM (Windows Server, Visual Studio Code, PowerShell 7, Python 3.12, Azure CLI and Git) and a **Lab readiness check** on its desktop
- A **Microsoft Foundry** resource and project with `gpt-5.4-mini` and `text-embedding-3-small` deployments, an Application Insights connection, the OAuth identity passthrough connection `servicedesk-mcp`, and the prompt agent `msp-support-agent` with its own **Microsoft Entra Agent ID**, the baseline Service Desk MCP tools and no knowledge source
- **Azure AI Search** Basic, with no index (teams create and load it from a provisioned export)
- **Azure API Management** Basic v2 with two MCP APIs: one accepting only a signed-in technician's token for the `ServiceDesk.Access` scope, and one diagnostics API behind a subscription key that carries no user
- **Azure Container Apps** running the MCP server (release `v2.0.0`), which reads its gateway key from **Azure Key Vault** through its managed identity, with **Azure Container Registry** and the vault's audit log in Log Analytics
- A **Power Platform developer environment** with the Service Desk app and its seeded data (24 customers with 63 agreed procedures, 72 contacts, 50 knowledge articles, 12 runbooks, 12 technicians, 16 SLA definitions, 476 tickets including 45 open and two new, unindexed incidents, 1,203 ticket notes, and one labelled customer configuration document), Dataverse auditing on, least-privileged security roles with read and write separated, both technician identities, and a regulated-accounts business unit
- **Log Analytics** and workspace-based **Application Insights** receiving API Management, Container Apps, Key Vault and Foundry telemetry
- A **Temporary Access Pass** for each team account, shown on the **Environment** tab, because Azure requires multifactor authentication for Azure portal sign-in and for every Azure Resource Manager change the exercises make (see `setup/README.md`)

## Schedule

| Time | Activity | Duration |
|---|---|---|
| 00:00 | Sign in, launch your assigned lab and verify readiness | 15 min |
| 00:15 | Exercise 1: Environment Readiness and Grounding the Agent | 50 min |
| 01:05 | Break | 10 min |
| 01:15 | Exercise 2: Ticket and Incident Intelligence | 35 min |
| 01:50 | Exercise 3: Using the MCP Read Tools | 45 min |
| 02:35 | Break | 10 min |
| 02:45 | Exercise 4: Using the MCP Action Tools | 60 min |
| 03:45 | Break | 10 min |
| 03:55 | Exercise 5: Identity, Secrets and Authorization | 45 min |
| 04:40 | Exercise 6: Data Protection and Auditability | 45 min |
| 05:25 | Exercise 7: End-to-End Scenario and Business Case | 25 min |
| 05:50 | Close, with schedule float retained | 10 min |

## Lab Exercises

### [Exercise 1: Environment Readiness and Grounding the Agent](Instructions/exercise-1.md)

**Estimated Duration: 50 minutes**

Confirm with the readiness check that every component responds, build and load an Azure AI Search index over the Service Desk content with the fields a citation needs, and connect it to the agent as its knowledge source. Test simple retrieval, an ambiguous case where two articles share a symptom but split on product version, and the agent's ability to explain its sources.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Verify Readiness | 8 min |
| Task 2 | Connect the Agent to the Knowledge Base | 20 min |
| Task 3 | Test Retrieval on Simple Questions | 8 min |
| Task 4 | Resolve an Ambiguous Case | 8 min |
| Task 5 | Explain the Reasoning | 6 min |

### [Exercise 2: Ticket and Incident Intelligence](Instructions/exercise-2.md)

**Estimated Duration: 35 minutes**

Match a new incident that the agent has never seen to its historical tickets and tell the decoys apart, summarise a customer's support history and escalations, recommend priority, category and assignment, see the agent ask for missing details, and find the tickets closest to breaching their SLA in business hours.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Identify Similar Historical Incidents | 10 min |
| Task 2 | Summarise a Customer's Support History | 8 min |
| Task 3 | Recommend Priority, Category and Assignment | 8 min |
| Task 4 | Detect an SLA Risk | 9 min |

### [Exercise 3: Using the MCP Read Tools](Instructions/exercise-3.md)

**Estimated Duration: 45 minutes**

Review the MCP server already cloned on the lab VM, read its tool catalogue with input and output schemas, and trace a tool to its Dataverse Web API query. Call a read tool from the agent and find it in the tool invocation log by its correlation identifier, test structured error handling, and redeploy a change with a rollback path.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Review the MCP Server on Your Lab VM | 10 min |
| Task 2 | Call an Existing Read Tool | 8 min |
| Task 3 | Test Tool Error Handling | 10 min |
| Task 4 | Redeploy Your Copy of the MCP Server | 17 min |

### [Exercise 4: Using the MCP Action Tools](Instructions/exercise-4.md)

**Estimated Duration: 60 minutes**

Approve and decline write tool calls, keep internal notes out of a customer reply, chain grounding into an approved action on the new incident, tighten a tool boundary and redeploy, and design, build and deploy a new scoped tool.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Call a Write Tool with Approval | 12 min |
| Task 2 | Separate a Public Reply from an Internal Note | 12 min |
| Task 3 | Chain Grounding into Action | 14 min |
| Task 4 | Tighten a Tool Boundary | 10 min |
| Task 5 | Design and Add a Scoped Tool | 12 min |

### [Exercise 5: Identity, Secrets and Authorization](Instructions/exercise-5.md)

**Estimated Duration: 45 minutes**

Map every identity and token in a request and separate delegated from application permissions, verify that the backend credential lives only in Key Vault, narrow a least-privilege boundary and capture Dataverse's refusal, and show that the same agent does less for the Tier 1 Technician than for the Senior Technician.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Map the Identities and Token Flow | 10 min |
| Task 2 | Verify Secure Secret Handling | 10 min |
| Task 3 | Enforce a Least-Privilege Boundary | 12 min |
| Task 4 | Apply User-Level Authorization | 13 min |

### [Exercise 6: Data Protection and Auditability](Instructions/exercise-6.md)

**Estimated Duration: 45 minutes**

Restrict what the agent can return with Dataverse column security, apply Microsoft Purview DLP and a sensitivity label to the agent's interactions and find the DLP event, and follow one approved action through every log with a single correlation identifier.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Restrict What the Agent Can Return | 12 min |
| Task 2 | Apply Microsoft Purview Data Protection | 18 min |
| Task 3 | Trace a Single Action End to End | 15 min |

### [Exercise 7: End-to-End Scenario and Business Case](Instructions/exercise-7.md)

**Estimated Duration: 25 minutes**

Run the second new incident from intake to an authorized, audited action in one exchange, capture its audit trail, and present a business case for the agent backed by evidence from the environment.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Run the End-to-End Scenario | 15 min |
| Task 2 | Present the Business Case | 10 min |

---

## Solution Architecture

![Architecture of the lab: the technician signs in to the support agent in Microsoft Foundry, which is grounded in Azure AI Search and calls the MCP server in Azure Container Apps through API Management with the technician's token; the MCP server reads its key from Key Vault and acts in Dataverse on behalf of the technician, with Purview and Log Analytics alongside](Instructions/media/architecture.png)

| Component | Role in this lab |
|-----------|------------------|
| Microsoft Foundry Agent Service | Hosts the prompt agent `msp-support-agent` on `gpt-5.4-mini`, with the Service Desk MCP tool and the Azure AI Search knowledge source added in Exercise 1 |
| Microsoft Entra Agent ID | The agent's own identity, recorded in every tool call |
| Microsoft Entra ID | The Senior and Tier 1 Technician accounts, the agent identity, the gateway app registration with its `ServiceDesk.Access` scope, and the Purview app registration |
| MCP server (Azure Container Apps) | Nine read tools and five approval-gated write tools over the Service Desk tables, in Python on the MCP Python SDK; it runs every Dataverse call on behalf of the signed-in technician |
| Azure API Management | MCP gateway: validates the technician's token, forwards who the user is, adds the gateway key and a correlation identifier, and logs every MCP call |
| Microsoft Dataverse | The Service Desk system of record in a Power Platform developer environment; its security roles, business units, column security and auditing are the permission model |
| Power Apps model-driven app | The Service Desk console where teams verify every answer and change |
| Azure AI Search | The `servicedesk-knowledge` index, with vector, semantic and keyword search and citation fields |
| Azure Key Vault | Holds the gateway key that API Management and the MCP server read through their managed identities, with an audit log of every read |
| Microsoft Purview | DLP and sensitivity labels applied to tool results before they reach the agent |
| Azure Container Registry | Builds MCP server images from source with ACR Tasks |
| Azure Monitor (Log Analytics, Application Insights) | Agent traces, gateway, Key Vault and MCP logs, and the MCP server's tool invocation log |
| Git (on the lab VM) | The team's local copy of the MCP server source at release `v2.0.0` |

---

## Repository Structure

```text
├── README.md
├── .gitignore
├── masterdoc.json
├── BUILD-NOTES.md
├── SCREENSHOT-TODO.md
├── Instructions/
│   ├── getting-started.md
│   ├── exercise-1.md ... exercise-7.md
│   └── media/
│       ├── architecture.mmd and architecture.png
│       └── identity-token-flow.mmd and identity-token-flow.png
├── solutions/
│   └── exercise-4-task-5/      (reference escalate_ticket tool, shipped to C:\LabFiles\solutions)
├── validation-scripts/
│   ├── README.md
│   └── ex*-task*-*.ps1
├── estimates/                  (pre-sales cost and effort workbooks with their input specs)
├── research/                   (Microsoft Learn notes with sources, and the pricing data behind the estimate)
└── setup/
    ├── README.md               (deployment package and support runbook)
    ├── DATA-SPEC.md            (seeded data and minimum volumes)
    ├── deploy-01.json
    ├── deploy-01.parameters.json
    ├── Build-LabFilesZip.ps1
    ├── policy/
    ├── scripts/
    │   ├── psscript-01.ps1
    │   └── logontask-01.ps1
    ├── tenant/
    │   └── Initialize-LabTenant.ps1
    ├── tests/
    │   └── test_seed_determinism.py
    └── assets/
        ├── msp-labfiles.zip      (build output, not committed)
        └── labfiles/
            ├── agent/
            ├── provision/
            ├── search/
            ├── seed/
            └── tools/
```

The MCP server source is a separate private repository, `CloudLabsAI-Azure/agentic-msp-mcp-server`. `setup/Build-LabFilesZip.ps1` packs its tag `v2.0.0` into `setup/assets/msp-labfiles.zip`, so lab VMs never need GitHub access. That archive contains the private source, so it is uploaded to the CloudLabs template library and kept out of this repository by `.gitignore`.

---

## Key Technologies Covered

| Technology | Description |
|------------|-------------|
| Microsoft Foundry Agent Service | Build, ground and test a prompt agent; connect knowledge and MCP tools with approval; read its traces |
| OAuth identity passthrough | Carry the signed-in technician's identity from the agent through the MCP gateway to the system of record |
| Model Context Protocol | Read and write tools with validated inputs, structured results and errors, served over streamable HTTP |
| Azure API Management | Expose an MCP server, validate Entra tokens, forward user context and correlation identifiers, and log MCP traffic |
| Azure Key Vault and managed identities | Keep the backend credential out of code and configuration, and audit every read |
| Azure Container Apps and Container Registry | Build from source with ACR Tasks, roll out new revisions and roll back |
| Microsoft Dataverse | Web API queries, impersonation, least-privileged security roles, business units, column security and auditing |
| Microsoft Purview | DLP and sensitivity labels on AI interactions through the `processContent` API |
| Azure AI Search | Hybrid vector and semantic index designed for citations |
| Azure Monitor | KQL across Log Analytics and Application Insights to trace one action end to end |

---

## Additional Resources

- [Connect an Azure AI Search index to Foundry agents](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search)
- [Connect to Model Context Protocol servers from Foundry agents](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol)
- [Set up authentication for MCP tools, including OAuth identity passthrough](https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication)
- [What is Microsoft Entra Agent ID?](https://learn.microsoft.com/entra/agent-id/what-is-microsoft-entra-agent-id)
- [Expose and govern an existing MCP server in API Management](https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server)
- [Impersonate another user in Dataverse](https://learn.microsoft.com/power-apps/developer/data-platform/impersonate-another-user)
- [Security roles and privileges in Dataverse](https://learn.microsoft.com/power-platform/admin/security-roles-privileges)
- [Column-level security to control access](https://learn.microsoft.com/power-platform/admin/field-level-security)
- [Azure Key Vault logging](https://learn.microsoft.com/azure/key-vault/general/logging)
- [Manage Dataverse auditing](https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing)
- [Set up tracing for Foundry agents](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup)

---

## Support Contact

The CloudLabs support team is available 24/7, 365 days a year, via email and live chat.

- Email Support: cloudlabs-support@spektrasystems.com
- Live Chat Support: https://cloudlabs.ai/labs-support
