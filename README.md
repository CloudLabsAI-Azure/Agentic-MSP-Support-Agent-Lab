# Agentic MSP Support Agent Guided Lab

- **Lab Type:** Step-by-step guided lab
- **Audience:** Cloud solution architects, AI and agent developers, service desk and MSP platform engineers, and security engineers who govern agent access
- **Audience Level:** Advanced (L300)
- **Total Duration:** 4 hours

## Lab Overview

Teams build an AI agent over a live ticketing environment for Relecloud Managed Services, a fictional managed service provider. Each team has an identical environment: a dedicated Azure resource group, a Microsoft Foundry agent registered under its own Microsoft Entra Agent ID, a Service Desk model-driven app on Microsoft Dataverse with seeded customers, contacts, knowledge articles, technicians and historical tickets, a starter MCP server with reference tools, and the identity, secret storage, gateway and logging around them. Permissions are enforced by Dataverse security roles. The MCP server source arrives on each lab VM as a local Git repository of the release the team's Container App runs; teams change it and redeploy it to their own Container App, with no GitHub account (the source repository itself is private). On arrival, the agent has no knowledge connection, no extended tools and no permission model; teams add each one.

The guide holds 4 hours of hands-on exercises. Delivered live, the session runs 5 hours: 15 minutes of arrival and sign-in, two 10-minute breaks, a 15-minute wrap-up and 10 minutes of close and float.

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
| **Microsoft Power Apps for Developer** (Power Apps Developer Plan, SKU `POWERAPPS_DEV`) | A Power Platform developer environment with Dataverse, and the right to run the Service Desk model-driven app in it (development and test use only) | Per attendee account (one team account per team in this delivery) | CloudLabs assigns it to each team account before provisioning |
| **Microsoft Entra ID Free** (included with the tenant's Microsoft cloud subscription) | Team user accounts, the gateway app registration, and Microsoft Entra Agent ID for the Foundry agent identity; viewing agent identities needs no admin role | Per tenant | The CloudLabs lab tenant |
| **Azure subscription, consumption billing** | Microsoft Foundry models (`gpt-5.4-mini`, `text-embedding-3-small`, billed per token), Azure AI Search Basic, API Management Basic v2, Azure Container Apps, Azure Container Registry Basic, Key Vault, Log Analytics, Application Insights and the lab VM | Per team resource group | CloudLabs (see the cost estimate) |
| **Foundry Models quota (Global Standard, Sweden Central)** | `gpt-5.4-mini`: 30,000 tokens per minute (TPM) per team deployment, which also sets about 30 requests per minute; `text-embedding-3-small`: 30,000 TPM per team deployment | Capacity, shared by every team in the subscription and region | CloudLabs confirms Tier 1 or higher before the event (25 teams use 750,000 of the 1,000,000 TPM Tier 1 quota for each model; Tier 0 has no `gpt-5.4-mini` quota) |

Not required: Microsoft Agent 365 (only needed to extend Entra security features such as Conditional Access and ID Protection to agents, which this lab doesn't use), Microsoft Entra ID P1 or P2, Dynamics 365 licences (developer environments can't install Dynamics 365 apps, and the Service Desk app doesn't need them), Managed Environments (which would require premium licences on top of the Developer Plan), and GitHub accounts (the MCP server source is on the lab VM).

### Azure resources and configuration

The following are pre-provisioned in the CloudLabs environment before the session:

- A team resource group in **Sweden Central** with a lab VM (Windows Server, Visual Studio Code, PowerShell 7, Python 3.12, Azure CLI and git)
- A **Microsoft Foundry** resource and project with `gpt-5.4-mini` and `text-embedding-3-small` deployments, an Application Insights connection, and the prompt agent `msp-support-agent` with its own **Microsoft Entra Agent ID**, no knowledge and no tools
- **Azure AI Search** Basic, with no index (teams create and load it)
- **Azure API Management** Basic v2 with two MCP APIs: one accepting only the agent identity, one diagnostics API behind a subscription key
- **Azure Container Apps** running the starter MCP server image (release `v1.0.0`), with **Azure Container Registry**, **Azure Key Vault** for the gateway key, and a user-assigned managed identity
- A **Power Platform developer environment** with the Service Desk solution, the Service Desk app and its seeded data (24 customers, 72 contacts, 50 knowledge articles, 12 technicians, 473 tickets including 42 open, 1,161 ticket notes), Dataverse auditing on, and the MCP managed identity registered as an application user with the System Administrator role (deliberately over-privileged until Exercise 5)
- **Log Analytics** and workspace-based **Application Insights** receiving API Management, Container Apps and Foundry telemetry
- A **Temporary Access Pass** for each team account, shown on the **Environment** tab, because Azure requires multifactor authentication for Azure portal sign-in and for every Azure Resource Manager change the exercises make (see `setup/README.md`)

## Lab Exercises

### [Exercise 1: Environment Verification and Grounding](Instructions/exercise-1.md)

**Estimated Duration: 65 minutes**

Verify every component of the team environment, build and load an Azure AI Search index over the Dataverse knowledge articles, tickets and customers, and connect it to the agent as its knowledge source. Test simple retrieval, an ambiguous case where two articles share a symptom but split on product version, and the agent's ability to explain its sources.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Verify the team environment | 18 min |
| Task 2 | Connect the agent to the knowledge base | 22 min |
| Task 3 | Test simple retrieval | 9 min |
| Task 4 | Resolve an ambiguous case | 9 min |
| Task 5 | Make the agent explain its reasoning | 7 min |

### [Exercise 2: Ticket and Incident Intelligence](Instructions/exercise-2.md)

**Estimated Duration: 35 minutes**

Use the grounded agent to match an unseen incident to historical tickets, summarize one customer's open issues and spot a recurring problem, recommend triage for an untriaged ticket, and find the tickets closest to breaching their SLA in business hours, verifying each answer in the Service Desk app.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Find similar incidents | 10 min |
| Task 2 | Summarize open issues for a customer | 8 min |
| Task 3 | Recommend a priority and category for a new ticket | 8 min |
| Task 4 | Identify SLA risk | 9 min |

### [Exercise 3: MCP Read Tools](Instructions/exercise-3.md)

**Estimated Duration: 45 minutes**

Open the team's copy of the MCP server source on the lab VM, read its tool manifest, and trace a tool to its Dataverse Web API query. Connect the server to the agent through API Management with the agent identity, call a read tool and find it in the gateway logs, test error handling, and redeploy a change to the Container App.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Explore the MCP server source | 12 min |
| Task 2 | Invoke a read tool from the agent | 13 min |
| Task 3 | Test error handling | 8 min |
| Task 4 | Change and redeploy the server | 12 min |

### [Exercise 4: MCP Action Tools](Instructions/exercise-4.md)

**Estimated Duration: 50 minutes**

Let the agent assign a ticket and confirm the change and its audit record, keep internal notes out of a customer reply, chain grounding into a triage and assignment decision, and apply a guided fix that makes the server reject an argument it previously accepted.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Use a write tool to assign a ticket | 12 min |
| Task 2 | Separate a public reply from an internal note | 12 min |
| Task 3 | Chain grounding into an action | 14 min |
| Task 4 | Apply a guided fix to an argument boundary | 12 min |

### [Exercise 5: Security, Governance, and Audit](Instructions/exercise-5.md)

**Estimated Duration: 45 minutes**

Compare the agent identity with the backend identity it acts through, replace the over-privileged backend role with a least-privilege Dataverse role and capture the platform's denial, protect contact data with column security, and trace one action across the agent trace, gateway log, server log and Dataverse audit record.

| Task | Topic | Duration |
|------|-------|----------|
| Task 1 | Compare the agent identity with the backend identity | 10 min |
| Task 2 | Enforce a least-privilege boundary in Dataverse | 12 min |
| Task 3 | Protect contact data | 11 min |
| Task 4 | Trace one action end to end | 12 min |

---

## Solution Architecture

![Architecture of the lab: the support agent in Microsoft Foundry grounded in Azure AI Search, calling the MCP server in Azure Container Apps through API Management with its agent identity, and the MCP server reading and writing Dataverse as a managed identity](Instructions/media/architecture.png)

| Component | Role in this lab |
|-----------|------------------|
| Microsoft Foundry Agent Service | Hosts the prompt agent `msp-support-agent` on `gpt-5.4-mini`, with the Azure AI Search tool and the MCP tool added during the lab |
| Microsoft Entra Agent ID | The agent's own identity; its token is the only credential the MCP gateway accepts |
| Microsoft Entra ID | Team accounts, the agent identity, and the gateway app registration that defines the token audience |
| MCP server (Azure Container Apps) | Seven read tools and five write tools over the Service Desk tables, in Python on the MCP Python SDK; the only code Spektra supplies |
| Azure API Management | MCP gateway: validates the agent identity token, adds the gateway key, rate limits, and logs every MCP call |
| Microsoft Dataverse | The Service Desk system of record in a Power Platform developer environment; its security roles, column security and auditing are the permission model |
| Power Apps model-driven app | The Service Desk console where teams verify every answer and change |
| Azure AI Search | The `servicedesk-knowledge` index, with vector, semantic and keyword search and citation fields |
| Azure Key Vault | Holds the gateway key shared by API Management and the MCP server |
| Azure Container Registry | Builds MCP server images from source with ACR Tasks |
| Azure Monitor (Log Analytics, Application Insights) | Agent traces, gateway and MCP logs, and the MCP server's structured tool-call log |
| Git (on the lab VM) | The team's local copy of the MCP server source at release `v1.0.0` |

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
│   ├── exercise-1.md
│   ├── exercise-2.md
│   ├── exercise-3.md
│   ├── exercise-4.md
│   ├── exercise-5.md
│   └── media/
│       ├── architecture.mmd
│       └── architecture.png
├── facilitator/
│   └── facilitator-guide.md
├── validation-scripts/
│   ├── README.md
│   └── ex*-task*-*.ps1
├── estimates/                  (pre-sales cost and effort workbooks with their input specs)
│   ├── Cost-Estimation-Agentic-MSP-Support-Agent.xlsx
│   ├── Effort-Estimate-Agentic-MSP-Support-Agent.xlsx
│   └── *-spec.json
├── research/                   (Microsoft Learn notes with sources, and the pricing data behind the estimate)
│   ├── research-*.md
│   └── pricing-raw-swedencentral/
└── setup/
    ├── README.md
    ├── deploy-01.json
    ├── deploy-01.parameters.json
    ├── Build-LabFilesZip.ps1
    ├── policy/
    │   ├── armpolicy-01.json
    │   ├── armrbac-01.json
    │   └── usagepolicy.json
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

The MCP server source is a separate private repository, `CloudLabsAI-Azure/agentic-msp-mcp-server`. `setup/Build-LabFilesZip.ps1` packs its tag `v1.0.0` into `setup/assets/msp-labfiles.zip`, so lab VMs never need GitHub access. That archive contains the private source, so it is uploaded to the CloudLabs template library and kept out of this repository by `.gitignore`.

---

## Key Technologies Covered

| Technology | Description |
|------------|-------------|
| Microsoft Foundry Agent Service | Build, ground and test a prompt agent; add knowledge and MCP tools; read its traces |
| Microsoft Entra Agent ID | Authenticate an agent to an MCP gateway with its own agent identity |
| Model Context Protocol | Read and write tools with structured results and errors, served over streamable HTTP |
| Azure API Management | Expose an MCP server, validate Entra tokens, and log MCP traffic |
| Azure Container Apps and Container Registry | Build from source with ACR Tasks and roll out new revisions |
| Microsoft Dataverse | Web API queries, security roles, application users, column security and auditing |
| Power Apps model-driven apps | Verify agent answers and changes against the system of record |
| Azure AI Search | Hybrid vector and semantic index designed for citations |
| Azure Monitor | KQL across Log Analytics and Application Insights to trace one action end to end |

---

## Additional Resources

- [Connect an Azure AI Search index to Foundry agents](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search)
- [Connect to Model Context Protocol servers from Foundry agents](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol)
- [MCP server authentication in Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication)
- [What is Microsoft Entra Agent ID?](https://learn.microsoft.com/entra/agent-id/what-is-microsoft-entra-agent-id)
- [Expose and govern an existing MCP server in API Management](https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server)
- [Monitor MCP servers in API Management](https://learn.microsoft.com/azure/api-management/monitor-mcp-servers)
- [MCP servers on Azure Container Apps](https://learn.microsoft.com/azure/container-apps/mcp-overview)
- [Security roles and privileges in Dataverse](https://learn.microsoft.com/power-platform/admin/security-roles-privileges)
- [Column-level security to control access](https://learn.microsoft.com/power-platform/admin/field-level-security)
- [Manage Dataverse auditing](https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing)
- [Set up tracing for Foundry agents](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup)

---

## Support Contact

The CloudLabs support team is available 24/7, 365 days a year, via email and live chat.

- Email Support: cloudlabs-support@spektrasystems.com
- Live Chat Support: https://cloudlabs.ai/labs-support
