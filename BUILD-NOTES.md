# Build notes: Agentic MSP Support Agent Guided Lab

First built on 2026-10-01 with the CloudLabs Lab Builder (profile `cloudlabs-step-by-step`). Updated on 2026-10-02 to the detailed table of contents v2.2, treated as fixed scope: seven exercises, 27 tasks and 104 steps in a 6-hour session. These notes record the decisions, what was verified, and what still needs a live pilot.

## Deliverables

| Deliverable | Location |
|---|---|
| Participant guide (getting started, seven exercises) | `Instructions/`, listed in `masterdoc.json` |
| README with licences, schedule and task timings | `README.md` |
| Seed data specification (volumes and the records each exercise depends on) | `setup/DATA-SPEC.md` |
| Reference solution for Exercise 4 Task 5 (not in the guide pages; copied to `C:\LabFiles\solutions` on the VM) | `solutions/exercise-4-task-5/` |
| Deployment package: ARM, bootstrap, logon task, lab files, governance, tenant preparation | `setup/` (handoff, pilot checklist and setup TODO in `setup/README.md`) |
| Lab readiness check (desktop shortcut on the VM; provisioning runs it last) | `setup/assets/labfiles/tools/Test-LabReadiness.ps1` |
| Validation scripts and registration checklist (14 checks) | `validation-scripts/` |
| MCP server source (separate private repository) | `CloudLabsAI-Azure/agentic-msp-mcp-server`, tag `v2.0.0`, shipped to the VMs inside the lab files archive |
| Screenshot capture list (58 markers) | `SCREENSHOT-TODO.md` |
| Cost and effort estimates | `estimates/` (pre-sales; not listed in the masterdoc) |
| Research notes with sources, and the Azure Retail Prices API data behind the cost estimate | `research/` (internal reference; not listed in the masterdoc) |

## Design decisions

### Platform

- **Region Sweden Central.** East US and East US 2 currently block new Azure AI Search services; Sweden Central supports Agents, the Azure AI Search tool, the MCP tool, semantic ranker and the chosen models.
- **Model `gpt-5.4-mini` (2026-03-17, Global Standard).** It supports both the Azure AI Search tool and MCP in Agent Service, is GA until 2027-09-21 and needs no access request. `gpt-5-mini` doesn't support the Azure AI Search tool.
- **Dataverse is the only ticketing backend.** The Service Desk is a custom Power Apps model-driven app that Spektra builds over `spk_` tables; the guide says so the first time it appears. Permissions are enforced by Dataverse security roles, so a denied action is denied by the platform.
- **API Management Basic v2.** It deploys in minutes, supports MCP passthrough and resource logs. Two MCP APIs: `servicedesk-mcp` (path `servicedesk`) for the agent, and `servicedesk-mcp-diag` (path `servicedesk-diag`) for diagnostics from the lab VM with a subscription key. Both add the gateway key, so the Container App can't be called around the gateway.
- **MCP Python SDK 2.2.0, stateless.** Foundry requires stateless MCP servers. Tool schemas avoid `anyOf` and `allOf`, tools return structured JSON, and every expected failure is a structured error with code, message, source, retryable flag and hint. Dataverse errors pass through verbatim under `error.dataverse`.

### Safe by default

Every control is on from the first minute; no exercise asks participants to fix an exposure.

- **Two identities per team.** The **Senior Technician** (default) and the **Tier 1 Technician**, read-only on tickets. The Tier 1 values reach the VM as `msplab-*` tags read through the instance metadata service, which avoids quoting problems in user data for values that may be empty or contain spaces.
- **OAuth identity passthrough.** One tenant-wide gateway app registration defines the delegated scope `ServiceDesk.Access` with admin consent. The Foundry project connection `servicedesk-mcp` (category `RemoteTool`, `authType` `OAuth2`) is created by the ARM template. API Management validates the technician's token (audience, client app, `scp`), forwards `x-user-oid`, `x-user-name` and `x-client-app-id`, sets `x-correlation-id` from `context.RequestId`, adds `x-backend-key` from its Key Vault named value, and removes `Authorization`. The diagnostics API strips the user headers, so write tools refuse calls made through it (`USER_CONTEXT_REQUIRED`).
- **Least privilege, read and write separated.** The MCP server's managed identity is a Dataverse application user with **Service Desk Agent Read**, **Service Desk Agent Write** and **Service Desk Delegate**; the technicians hold **Service Desk Senior Technician** or **Service Desk Tier 1 Technician**. The server acts on behalf of the technician with the `CallerObjectId` header, and Dataverse allows a call only when both the application user's and the technician's roles allow it (Microsoft Learn: effective privileges are the intersection; field security is evaluated for both). Append is granted on the note and Append To on the ticket, as Learn requires.
- **Business-unit boundary.** Lamna Healthcare's 71 records are owned by the **Relecloud Regulated Accounts** team. Exercise 5 Task 3 narrows **Service Desk Agent Write** to Business Unit depth, and Dataverse then refuses writes on TCK-10479 and TCK-10491.
- **Secrets in Key Vault.** The gateway key is generated from a secure parameter and stored only in Key Vault; API Management reads it through a Key Vault named value, and the MCP server reads it at startup through the Key Vault REST API with its managed identity. The Container App holds no secret. Key Vault audit events go to `AZKVAuditLogs`, and the team user has Key Vault Reader to inspect secret metadata.
- **Approval on writes.** The agent's MCP tool sets `require_approval` to `never` only for the nine read tools, so every write tool asks for approval in the playground. Write tools publish `relecloud/approval: required`, their sensitivity and the Dataverse permissions they need in `_meta`.
- **Input validation on every tool.** Typed arguments with patterns, enumerations and ranges. A schema failure returns `INVALID_ARGUMENT` with the violations, and the log records it with received values summarized, never echoed.
- **Correlation logging.** One correlation ID from API Management's request ID travels through the MCP server's log line, the Dataverse request (`x-ms-client-request-id`), the ticket's **Last Correlation ID** column and the audit note. `Get-ActionTrail.ps1` assembles the whole trail from that one ID, so Exercise 6 Task 3 needs no manual join.
- **Microsoft Purview.** Ticket descriptions, notes and customer documents pass through `processContent` before they reach the agent; a block withholds the content, and the server fails closed (`PURVIEW_UNAVAILABLE`). The labelled configuration document is never returned (`CONTENT_BLOCKED_BY_LABEL`); its label is read from the document's custom properties.

### Content and environment

- **Pre-provisioned, identical teams.** The agent `msp-support-agent` exists with its Entra Agent ID, the baseline MCP tool and no knowledge source. The MCP server source is in place at `C:\LabFiles\mcp-server` as a local Git repository of the release with no remote; nothing on the VM needs GitHub access. `Build-LabFilesZip.ps1` packs the release tag into the lab files archive with `git archive`.
- **Readiness check.** `Test-LabReadiness.ps1` checks eight components (resources, app and data, Tier 1 identity, agent, MCP connection, MCP server, a baseline read tool through API Management, search content). Provisioning runs it last and fails on any component that is Not ready; participants run it from the desktop in Exercise 1 Task 1 and contact support if anything isn't ready.
- **Search index design.** Participants build the index in Exercise 1 Task 2 from an export provisioning prepares: 50 articles, 12 runbooks, 474 tickets, 24 customer profiles (with procedures and open tickets) and one SLA snapshot, 561 documents. Ticket notes, contact details, customer documents and the two new incidents are never indexed; the new incidents are loaded after the export, so the agent first meets them through the tools.
- **Seed data.** A deterministic generator (seed 20261001) builds the data against a fixed reference anchor (2026-10-07 14:00 UTC) and shifts every timestamp by whole weeks to the provisioning time, so ticket numbers, notes, counts and SLA figures, and therefore every Expected results block, are identical for every team on every day. SLA figures are business hours (Monday to Friday, 08:00 to 18:00 UTC). `setup/DATA-SPEC.md` lists the volumes and the records each exercise depends on.
- **Mandatory MFA.** Provisioning runs Resource Manager work as a user-assigned managed identity on the VM, `id-prov-<DID>`, with roles scoped to the team's resources; Power Platform and Dataverse work runs as the team account, with tokens requested in-process. Participants sign in with the Temporary Access Pass that the CloudLabs TAP tenant shows as the password.
- **Self-checked delivery.** No presenter role: every task ends with Expected results drawn from the seed, every validated task has a Validate button, and the guide points to CloudLabs support for help.
- **Durations.** 305 minutes of exercises (50 + 35 + 45 + 60 + 45 + 45 + 25) inside a 6-hour wall-clock session with sign-in, three breaks and a close, exactly as the TOC schedule. README and getting started state both figures, so the lint duration check reconciles.

## Verification performed in this build

- **TOC conformance.** 7 exercises, 27 tasks and 104 numbered steps; every exercise duration, task title, task step count and per-task time matches the TOC, every guide step opens with its TOC step, and the schedule tables in README and getting started equal the TOC table.
- **Expected results against the seed.** Every ticket, customer, article, runbook, procedure, technician and SLA target named in the guides, README, data specification and solution exists and matches the seed; 33 aggregate facts (history patterns, SLA ranking, escalations, card numbers, business-unit records) and the Exercise 1 row counts match. The seed fixture in the MCP server repository equals a fresh generator run.
- **Readiness check, offline.** The real MCP server (fixture backend, gateway key read from a mock Key Vault) with mocks for Resource Manager, Dataverse, Foundry and the API Management diagnostics API: the baseline reports all eight components Ready and the read tool runs through the gateway. Six injected faults (missing seeded data, a Tier 1 user that also holds a Senior role, an agent without an Entra Agent ID, a connection without OAuth, no Tier 1 user, a gateway key outside Key Vault) are each reported as Not ready, or Not configured for the missing Tier 1 user, and an agent with its Exercise 1 knowledge source still reports Ready. The real search export against the same mock produced 561 documents, left out the new incidents and ranked the SLA snapshot as Exercise 2 expects.
- **MCP server.** 57 automated tests pass against the fixture backend; 61 pass with the Exercise 4 Task 5 reference solution applied.
- **Seed generator.** `setup/tests/test_seed_determinism.py`: 256 tests pass across a year of anchors.
- **ARM template.** 70 resources, 18 parameters, 53 variables and 33 outputs; every reference and dependency resolves. The policy allow-list covers every resource type, and the OAuth connection's target equals the gateway URL provisioning writes.
- **Static checks.** All 37 PowerShell scripts and 24 JSON files in both repositories parse. No em or en dashes anywhere; double hyphens appear only as command-line flags, Markdown table syntax and Mermaid arrows. None of the retired terms named in the TOC v2 brief remains, and no end-customer name appears in either repository or its history.
- **Diagrams.** `Instructions/media/architecture.mmd` and `identity-token-flow.mmd` rendered with Mermaid CLI and checked visually.
- **Lint gate** (`lint-lab.ps1 -Profile cloudlabs-step-by-step`): PASS with 0 blockers, 72 warnings and 0 hygiene items; the warnings are the accepted ones below.

Not verified (needs the pilot): a live deployment end to end. `setup/README.md` section 9 lists the behaviors to confirm and the tenant, licence and manual setup to complete first.

## Accepted lint warnings

- **ScreenshotPending (58).** Every screenshot is a pending marker until the pilot capture pass; `SCREENSHOT-TODO.md` lists them. Getting-started markers use `GS` IDs, which the current lint regex reports as malformed; this is a known lint defect, not a marker error.
- **ValidationPlaceholder (14).** `REPLACE-WITH-VALIDATION-GUID` stays until the steps are registered (`validation-scripts/README.md`).

## Fixes from the first build that still apply

- The MCP server uses synchronous `azure-identity` credentials in a worker thread (no `aiohttp` dependency); a regression test covers it.
- Both API Management policies delete the Origin header before forwarding, which the MCP SDK's transport security would otherwise reject.
- Revision suffixes carry a timestamp, and the deploy script waits for the new version on `/health`; `Deploy-McpServer.ps1 -Rollback` reactivates an earlier image.
- Search Index Data Contributor is granted to the Foundry account and project identities for keyless Azure AI Search.
- The Service Desk app is built with all its tables as app components, and app validation errors stop the step.

## Known content risks

- **Power Platform sign-in in a TAP tenant (pilot-critical).** Creating the developer environment and loading Dataverse as the team account uses the password grant. If the deployment receives a TAP rather than a password, those steps fail. `setup/README.md` section 1 lists the options to settle before the pilot.
- **OAuth connection metadata.** The metadata keys of the `OAuth2` project connection aren't documented; compare with a reference connection on the pilot and confirm whether the redirect URL is per connection or regional.
- **Tier 1 access.** The Tier 1 user is added to the developer environment by provisioning and holds Foundry User on the project; confirm on the pilot that it can use the agent and the app.
- **Latency of evidence.** Purview DLP events and Foundry agent traces can take several minutes to appear; the guide checks the MCP server's result first and the portals last.
- **The provisioning identity stays on the VM.** Any process on the VM can request tokens for `id-prov-<DID>`. Its roles are a subset of the participant's own, scoped to the team's resources, so this grants nothing new.
- **VM and trainer passwords in deployment outputs.** The accepted CloudLabs pattern; exclude the trainer outputs from the Environment tab (`setup/README.md` section 6).
- Foundry portal labels drift between Learn pages; the guide offers script fallbacks for the portal-heavy steps.
- Dataverse audit display names for application users may show a `#` prefix; the guide says so.
- Licensing for one account per role per team needs Microsoft confirmation (`setup/README.md`).
- The Dataverse daily request allowance for non-licensed identities is pooled per tenant; repeated `-ResetData` runs across many teams can exhaust it.
