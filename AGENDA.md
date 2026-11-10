# Workshop Agenda: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phase 1 of 8, plan the delivery.** Use this agenda to agree the workshop dates, the lab start time and the participant count with the requester, and share it with participants. Start of the path: [README.md](README.md#delivery-path).

A four-hour, self-paced, hands-on lab in which MSP service desk engineers, automation engineers and solution architects build, govern and audit an AI support agent over a live service desk, each in a dedicated environment of their own.

| | |
|---|---|
| **Format** | Four workshops. Each workshop is one 4-hour lab window (sign-in, seven exercises and close) with no scheduled breaks. The lab is self-paced: there is no instructor, participants check their own work against the expected results in the guide, and CloudLabs support answers by live chat and email |
| **Audience** | Up to 25 participants per workshop, with 2 spare environments: MSP service desk engineers, automation engineers and solution architects |
| **Level** | Advanced (L300). Participants run prepared PowerShell commands, read Python and JSON, and make small changes to the MCP server's Python code |
| **Language** | English |
| **Hands-on time** | 220 minutes across 7 exercises |
| **Environment** | A dedicated Microsoft Entra tenant and Azure subscription per participant for the fictional managed service provider Relecloud Managed Services: a Windows lab VM, a Microsoft Foundry agent with its own Microsoft Entra Agent ID, an MCP server on Azure Container Apps behind Azure API Management, the Service Desk app on Microsoft Dataverse with seeded customers, documents, knowledge articles and ticket history, Azure AI Search, Azure Key Vault, Microsoft Purview and Log Analytics |

## What participants leave with

- **The story:** how an MSP can let an AI agent answer from its own service desk data, triage new incidents and act on tickets while every change is approved, authorized as the person asking and traceable from the answer to the database record.
- **First-hand experience** with Microsoft Foundry Agent Service, Azure AI Search, the Model Context Protocol, Azure API Management, Azure Container Apps and Container Registry, Microsoft Entra Agent ID, Azure Key Vault, Microsoft Dataverse security roles and column security, Microsoft Purview DLP and sensitivity labels, and Log Analytics.
- **Reusable patterns:** the tool contract (description, input and output schema, required permission, input validation, structured errors), read and write tools on separate connections with approval on every write, the identity and token flow from the user to Dataverse, and one correlation ID across every log. Participants record their evidence and their business case in **Lab notes.txt** and export their audit trail during Exercises 6 and 7; the environment, with everything in it, is deleted when the review window ends.

## Session timing

The requester confirms each workshop's date and lab start time in writing at least 15 business days ahead; the dates live in the delivery plan, outside this repository. Times below are offsets from the lab start time. Environments are ready, and have passed the readiness check, at least 30 minutes before the start.

| Window | From | To | Length |
|---|---|---|---|
| Participant lab window | Lab start (00:00) | 04:00 | 4 hours |
| Review of submitted work by the requester's reviewers, with the participants' lab access | 04:00 | 28:00 | 24 hours |
| Environment deletion | 28:00 | | |

> **Note:** Support delays caused by the supplier extend that participant's time. No participant work happens during the review window.

## Agenda

| Time (from lab start) | Activity | Format | Minutes |
|---|---|---|---|
| 00:00 to 00:10 | Sign in, launch the lab and run the readiness check | Self-paced | 10 |
| 00:10 to 00:45 | Exercise 1: Environment Readiness and Grounding the Agent | Hands-on | 35 |
| 00:45 to 01:10 | Exercise 2: Ticket and Incident Intelligence | Hands-on | 25 |
| 01:10 to 01:45 | Exercise 3: Using the MCP Read Tools | Hands-on | 35 |
| 01:45 to 02:35 | Exercise 4: Using the MCP Action Tools | Hands-on | 50 |
| 02:35 to 03:05 | Exercise 5: Identity, Secrets and Authorization | Hands-on | 30 |
| 03:05 to 03:35 | Exercise 6: Data Protection and Auditability | Hands-on | 30 |
| 03:35 to 03:50 | Exercise 7: End-to-End Scenario and Business Case | Hands-on | 15 |
| 03:50 to 04:00 | Close: finish Lab notes.txt and confirm your evidence is saved | Self-paced | 10 |

## Exercise details

### Exercise 1: Environment Readiness and Grounding the Agent

**Stakeholder question:** "Can the agent answer from our own data, and show us where every answer came from?"

- **What you do:** verify that every component of your environment is ready; build an Azure AI Search index over the Service Desk export and connect it to the agent; test retrieval on simple questions; resolve an ambiguous case where two knowledge articles share a symptom; ask the agent to explain its sources.
- **Requested topics covered:** building the search index; grounding the agent in customer documentation, knowledge articles and historical tickets.

### Exercise 2: Ticket and Incident Intelligence

**Stakeholder question:** "Can it triage a new ticket the way our best technician would, and warn us before an SLA breach?"

- **What you do:** match a new incident the agent has never seen to similar historical incidents; summarize a customer's support history; recommend priority, category and assignment, and see the agent ask for missing details; detect the tickets closest to an SLA breach.
- **Requested topics covered:** grounding the agent in historical tickets.

### Exercise 3: Using the MCP Read Tools

**Stakeholder question:** "What exactly can the agent read from the Service Desk, and what happens when a call fails?"

- **What you do:** review the MCP server source on your lab VM and trace a tool to its Dataverse query; call a read tool and find the call in the log by its correlation ID; test structured error handling; change, build and redeploy your copy of the MCP server, with a rollback path.
- **Requested topics covered:** using and extending MCP tools over the ticketing backend (read operations).

### Exercise 4: Using the MCP Action Tools

**Stakeholder question:** "If we let the agent act, how do we stay in control of every change it makes?"

- **What you do:** approve and decline write tool calls; keep an internal note out of a customer-visible reply; chain grounding into an approved action on a new incident; tighten a tool boundary and redeploy; design, build and add a new scoped write tool with approval.
- **Requested topics covered:** using and extending MCP tools over the ticketing backend (controlled write operations).

### Exercise 5: Identity, Secrets and Authorization

**Stakeholder question:** "Whose permissions does the agent use, and can it ever do more than the person asking?"

- **What you do:** map every identity and token in one request; verify that the backend credential lives only in Key Vault; narrow a least-privilege boundary and capture Dataverse's refusal; show that the same agent does less for the Tier 1 Technician than for the Senior Technician.
- **Requested topics covered:** identity boundaries; least privilege; narrowing permissions.

### Exercise 6: Data Protection and Auditability

**Stakeholder question:** "Can we prove what the agent showed, withheld and changed, for any single request?"

- **What you do:** restrict what the agent can return with Dataverse column security; see Microsoft Purview DLP and a sensitivity label withhold content from the agent; trace one approved action end to end with a single correlation ID.
- **Requested topics covered:** data protection; applying data-protection controls; end-to-end auditability; tracing audit evidence.

### Exercise 7: End-to-End Scenario and Business Case

**Stakeholder question:** "Should we offer this agent to our customers, and what makes it safe to deploy?"

- **What you do:** take the second new incident from intake to approved, audited actions in one conversation and export its audit trail; present the business case with evidence from your environment.
- **Requested topics covered:** end-to-end auditability; tracing audit evidence.

## Coverage of the requested topics

| Requested topic | Exercises | Hands-on tasks |
|---|---|---|
| Ground an agent in synthetic customer documentation, knowledge articles and historical tickets | 1, 2 | 1.2 to 1.5, 2.1 to 2.4 |
| Build the search index | 1 | 1.2 |
| Use and extend MCP tools over the ticketing backend, including read and controlled write operations | 3, 4 | 3.1 to 3.4, 4.1 to 4.5 |
| Identity boundaries | 5 | 5.1, 5.4 |
| Least privilege and narrowing permissions | 4, 5 | 4.4, 5.3 |
| Data protection and applying data-protection controls | 4, 6 | 4.2, 6.1, 6.2 |
| End-to-end auditability and tracing audit evidence | 6, 7 | 6.3, 7.1 |

## Participant prerequisites

- A laptop with Microsoft Edge or Google Chrome, a network that allows `wss://*.ms-cloudlabs.ai`, and at least 8 Mbps.
- Outbound HTTPS (port 443) to `*.cloudlabs.ai`, `*.azure.com`, `*.microsoft.com`, `*.powerapps.com` and `*.dynamics.com`.
- Working knowledge of the Azure portal, basic PowerShell, and the ability to read Python and JSON.
- A general understanding of REST APIs, OAuth access tokens and service desk concepts (tickets, priorities, SLAs).
- Nothing to install. Every tool runs on the lab VM, and every license and role is provided in your lab environment.

## Logistics

- Delivered online and self-paced, with no instructor. CloudLabs support answers by live chat (first response within 5 minutes) and email (first response within 60 minutes), and escalates to the delivery manager within 30 minutes. A named contact from the requesting organization is available during each workshop.
- Environments, including 2 spares per workshop, are provisioned the day before, because sensitivity labels can take up to 24 hours to apply. Each passes the automated readiness check before participant access, and the consistency report is shared with the requester.
- A failed environment is replaced with a spare within 15 minutes of the report. Work in the failed environment is not kept, and the participant's lab time is extended by the time lost. An environment can be reset within 60 minutes of a request.
- Participant access ends after the 4-hour window. The requester's reviewers keep access for 24 hours after the workshop ends; then the environment is deleted and cannot be recovered.

---

**Next:** Phase 2, build and publish the template: [setup/README.md](setup/README.md).
