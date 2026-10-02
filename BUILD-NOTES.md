# Build notes: Agentic MSP Support Agent Guided Lab

Built on 2026-10-01 with the CloudLabs Lab Builder (profile `cloudlabs-step-by-step`) from the customer-supplied table of contents, treated as fixed scope. These notes record the decisions, what was verified, and what still needs a live pilot.

## Deliverables

| Deliverable | Location |
|---|---|
| Learner guide (getting started, five exercises) | `Instructions/`, listed in `masterdoc.json` |
| README with licences and task timings | `README.md` |
| Facilitator guide with answer keys, unseen incidents, guided fix, resets | `facilitator/facilitator-guide.md` (not in the masterdoc, not copied to VMs) |
| Deployment package: ARM, bootstrap, logon task, lab files, governance | `setup/` (handoff in `setup/README.md`) |
| Validation scripts and registration checklist | `validation-scripts/` |
| MCP server source (separate private repository) | `CloudLabsAI-Azure/agentic-msp-mcp-server`, tag `v1.0.0`, cloned at `../agentic-msp-mcp-server` in the build workspace; shipped to the VMs inside the lab files archive |
| Cost and effort estimates | `estimates/` (pre-sales; not listed in the masterdoc) |
| Research notes with sources, and the Azure Retail Prices API data behind the cost estimate | `research/` (internal reference; not listed in the masterdoc) |

## Design decisions

- **Region Sweden Central.** East US and East US 2 currently block new Azure AI Search services; Sweden Central supports Agents, the Azure AI Search tool, the MCP tool, semantic ranker and the chosen models.
- **Model `gpt-5.4-mini` (2026-03-17, Global Standard).** It supports both the Azure AI Search tool and MCP in Agent Service, is GA until 2027-09-21 and needs no access request. `gpt-5-mini` doesn't support the Azure AI Search tool.
- **API Management Basic v2.** It deploys in minutes (Developer takes 30 to 40 minutes), supports MCP passthrough and resource logs. Two MCP APIs: `servicedesk-mcp` accepts only the team's agent identity (`validate-azure-ad-token` with the agent client ID and the gateway audience); `servicedesk-mcp-diag` accepts a subscription key for learners' direct calls. Both inject the gateway key that the server checks, so the Container App can't be called around the gateway.
- **Agent identity authentication.** One tenant-wide app registration defines the token audience `api://<app ID>`; each team's gateway accepts only its own agent's client ID. Provisioning reads the agent's `instance_identity` and writes the client ID to the gateway's named value.
- **Stateless MCP.** Foundry requires stateless MCP servers. As a result, API Management's `SessionId` is expected to be empty; the guide teaches `CorrelationId` as the identifier and says why.
- **MCP Python SDK 2.2.0.** Tool schemas avoid `anyOf` and `allOf` (Foundry rejects them), tools return `CallToolResult` with structured JSON, and every expected failure is a structured error with code, message, source, retryable flag and hint. Dataverse errors pass through verbatim under `error.dataverse`.
- **Over-privileged by design.** The MCP managed identity is a Dataverse application user with System Administrator until Exercise 5, so teams see the problem before they fix it. The reference role `Service Desk Integration` holds exactly what the server needs.
- **Denial from Dataverse, not code.** Exercise 5 removes Write on the Ticket table in a copied role; the platform returns 403 with `0x80040220` naming `prvWritemsp_Ticket`. Exercise 4's guided fix shows the code-level boundary (`policy.py`) for contrast.
- **Search index design.** The index holds knowledge articles, tickets and customer profiles, and deliberately excludes ticket notes and contact details. Each customer profile lists the customer's open tickets, and one SLA snapshot document ranks every open ticket by remaining business hours and carries the SLA targets and priority rules. Without these, "all open tickets for a customer" and "closest to breach" are unreliable with a top-k search. Total: 548 documents.
- **Knowledge tool added by script.** Learners create the keyless Azure AI Search connection in the Foundry portal (documented path), then `Update-AgentDefinition.ps1 -Knowledge` creates the agent version with the `azure_ai_search` tool (`vector_semantic_hybrid`, top 10) and the grounded instructions. Learn documents adding Azure AI Search in the new playground only through toolboxes; the script keeps every team's definition identical and checkable.
- **MCP tool added in the portal.** The documented path (Tools > Add > Custom > Model Context Protocol, Microsoft Entra, Agent Identity, audience) is the learning moment; `Update-AgentDefinition.ps1 -Tools` is the fallback.
- **Seed data.** A deterministic generator (seed 20261001). It always builds the data against a fixed reference anchor (2026-10-07 14:00 UTC) and then shifts every timestamp by whole weeks to the provisioning time, so ticket numbers, notes, counts, SLA figures and the facilitator's answer keys are identical for every team on every day. 42 hand-authored open tickets carry the exercise scenarios; 431 historical tickets follow each customer's versions, tier and contract. SLA figures are business hours (Monday to Friday, 08:00 to 18:00 UTC). `setup/tests/test_seed_determinism.py` checks this across a year of anchors.
- **Mandatory MFA: two identities for provisioning.** Azure enforces MFA for portal sign-in and for every Resource Manager create, update or delete made by a user, and the resource owner password grant can't satisfy it. Provisioning therefore runs all Resource Manager work (image build, Container App and API Management changes, the APIM diagnostics key) as a user-assigned managed identity on the VM, `id-prov-<DID>`, which the enforcement doesn't cover; its roles are scoped to the individual resources and are a subset of the attendee's own. Power Platform and Dataverse work still runs as the team account, because the developer environment must belong to it; those tokens are requested in-process, so the password never appears on a command line. The Azure CLI profile for the provisioning identity lives in `C:\LabFiles\.azure-provisioning`, apart from the attendee's own `az login`.
- **Private MCP server repository.** The server's repository is private, so nothing on the VM needs GitHub access or credentials. `Build-LabFilesZip.ps1` packs the release tag into the lab files archive with `git archive`. Provisioning builds the starter image from that copy and creates each team's local Git repository at `C:\LabFiles\mcp-server`, with no remote and a system-wide `safe.directory` entry, because SYSTEM creates it. Exercise 3 opens that copy instead of cloning, and `git diff` shows exactly what a team changed. Attendees still see the full source, which the exercises require. The archive therefore stays out of the lab repository (`.gitignore`) and goes only to the template library.
- **Mandatory MFA: attendee sign-in with a Temporary Access Pass.** Attendees make Resource Manager changes in Exercises 1, 3 and 4, so the guide signs them in with the TAP that a CloudLabs TAP tenant shows as `AzureAdUserPassword`, and tells them not to register personal devices on the shared account.
- **Durations.** The guide holds 4 hours of exercises (65 + 35 + 45 + 50 + 45 minutes); README and getting-started state 4 hours and explain the 5-hour session with arrival, breaks and wrap-up, so the lint duration check reconciles.
- **Validation.** Nine platform checks read ARM, the search service and the MCP server's own tool-call log in Log Analytics (each line records `caller` = `agent` or `operator`). Exercise 2 and the trace join use Success Criteria checklists because they are conversational or manual.

## Verification performed in this build

- MCP server: 22 automated tests pass (fixture backend), including a regression test that the managed identity credential works without `aiohttp`; a smoke run through the ASGI app confirmed tool results, structured errors, the `caller` field and the gateway-key rejection.
- Seed generator: `setup/tests/test_seed_determinism.py` passes for 254 anchors across a year (same tickets, notes and counts: 473 tickets, 1,161 notes, 42 open, 548 search documents).
- Seed loader: run against a mock Dataverse Web API; all nine tables loaded with zero errors and the counts match the manifest.
- Search loader: run against mocks of Dataverse, Azure OpenAI embeddings and Azure AI Search; 548 documents uploaded with no fields outside the index schema, correct SLA snapshot ordering and open-ticket lists, and recovery from injected 429 rate limits.
- ARM template: parsed and statically checked (65 resources, 11 parameters, 46 variables, 30 outputs; every reference and dependency resolves).
- `setup/assets/msp-labfiles.zip` rebuilt with 63 files: the 20 lab files match `setup/assets/labfiles` byte for byte, and the 43 files in `provision/mcp-server` match tag `v1.0.0` of the private MCP server repository. A dry run of provisioning's local-repository commands on that copy produced one commit tagged `v1.0.0` with a clean working tree.
- All 26 PowerShell scripts parse; all 18 JSON files parse; no em or en dashes in any Markdown file.
- Architecture diagram rendered from `Instructions/media/architecture.mmd` with Mermaid CLI and checked visually (no connector crosses a node box).
- Lint gate (`lint-lab.ps1 -Profile cloudlabs-step-by-step`): PASS with 0 blockers, 76 warnings and 0 hygiene items; the warnings are the accepted ones below.

Not verified (needs the pilot): a live deployment end to end. `setup/README.md` section 8 lists the specific behaviors to confirm.

## Accepted lint warnings

- **ScreenshotPending (67).** Every screenshot is a pending marker until the pilot capture pass; `SCREENSHOT-TODO.md` lists them. Getting-started markers use `GS` IDs, which the current lint regex reports as "malformed"; this is a known lint defect (pending-marker regex rejects `GS{n}`), not a marker error.
- **ValidationPlaceholder (9).** `REPLACE-WITH-VALIDATION-GUID` stays until the steps are registered (`validation-scripts/README.md`).

## Review outcomes

Three independent reviews ran against the finished build: platform conformance (profile, timings, data consistency), code and infrastructure, and freshness against live Microsoft Learn. Every blocker and warning was fixed or is tracked below.

| Finding | Resolution |
|---|---|
| Seed counts and answer keys depended on the provisioning date | Generator rebuilt on a fixed reference anchor with whole-week shifts; the loader counts only seeded notes, so re-runs after the exercises still verify |
| The MCP server would crash in Azure (async credential without `aiohttp`) | Synchronous `azure-identity` credentials run in a worker thread; a regression test covers it |
| Mandatory MFA blocked provisioning writes and the guide's "Ask Later" sign-in | Provisioning identity for Resource Manager work; TAP sign-in in the guide; the setup README states the tenant prerequisites |
| Team password on the `az` command line | Removed; Dataverse tokens are requested in-process |
| Service Desk app built without its tables; validation errors only logged | All eight sitemap tables added as app components; `ValidateApp` errors and form update failures now stop the step |
| App labels differed from the guide | Sitemap shows **Customers** > **Accounts**; the guide uses the **Internal** and **Customer visible** labels of the Internal Note column |
| Redeploying with the same tag collided with an existing revision | Revision suffixes carry a timestamp, and the deploy script waits for the new version on `/health` |
| AI Search keyless roles below the documented requirement | Search Index Data Contributor added for the Foundry account and project identities |
| Backend key seed visible in deployment history | `mcpBackendKeySeed` is now a secure parameter; the guide no longer claims only API Management holds the key |
| Origin header rejected by the MCP SDK's transport security | Both API Management policies delete the Origin header before forwarding |
| Timing and step density in Exercises 1 and 5 | Task budgets rebalanced (README); the Exercise 5 trace revisit is optional |
| Stale UI labels and missing notes (Show hidden types, Filter by keyword, Revisions and replicas, playground evaluator cost, AppGenAIContent since 30 September 2026) | Guide text updated from the cited Learn pages |
| No troubleshooting sections; missing new-chat steps; no fallback for an unsecurable Email column | Troubleshooting blocks in every exercise; new chats before repeated questions; Email fallback and an Important callout in Exercise 5 Task 3 |

## Known content risks

- **Power Platform sign-in in a TAP tenant (pilot-critical).** Creating the developer environment and loading Dataverse as the team account uses the password grant. If CloudLabs' TAP tenant gives the deployment a TAP rather than a password in `AzureAdUserPassword`, those steps fail. `setup/README.md` section 1 lists the options to settle before the pilot.
- **The provisioning identity stays on the VM.** Any process on the VM can request tokens for `id-prov-<DID>` through the instance metadata service. Its roles are a subset of the attendee's own, scoped to the team's resources, so this grants an attendee nothing new.
- **VM and trainer passwords in deployment outputs.** CloudLabs needs the outputs for the Environment tab, and the attendee role can read deployments. The VM is the attendee's own and the trainer account exists only on it, so this is the accepted CloudLabs pattern; exclude the trainer outputs from the Environment tab (`setup/README.md` section 6).
- Foundry portal labels drift between Learn pages; the guide notes this and offers script fallbacks for the two portal-heavy steps.
- Dataverse audit display names for application users may show a `#` prefix; the guide says so.
- `emailaddress1` and `telephone1` securability isn't stated in Learn (`mobilephone` is); the guide tells learners to skip a column whose **Enable column security** option is unavailable.
- Power Platform licensing for shared team accounts needs Microsoft confirmation (see `setup/README.md`).
- The Dataverse daily request allowance for non-licensed identities is pooled per tenant (25,000 per 24 hours with Power Apps licences only); repeated `-ResetData` runs across many teams can exhaust it.
