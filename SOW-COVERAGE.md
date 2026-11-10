# Statement of Work Coverage: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phase 1 of 8, plan the delivery.** Every point of the statement of work and its Exhibits A to H, with where this repository delivers it and what is still open. Share it with the design pack for Milestone 1, and check it again before each workshop. Start of the path: [README.md](README.md#delivery-path).

**Who:** the delivery lead and the lab author. **Time:** about 30 minutes to review.

Checked on 2026-11-10 against lab version 3.0 (branch `toc-v3`) and MCP server release 3.0.0. Each row has one status:

| Status | Meaning |
|---|---|
| **Delivered** | Built, and checked offline: lint, links, parse checks, the seed and MCP server tests, the table of contents check |
| **Pilot** | Built; confirmed on a live environment in Phase 5, because it depends on how a deployed service behaves |
| **Event** | A procedure the delivery team runs for every workshop; the document named holds it |
| **Adjusted** | Delivered with an adjustment under the platform-dependency clause, in [DESIGN-PACK.md, section 8](DESIGN-PACK.md#8-adjustments-under-the-platform-dependency-clause) |
| **Commercial** | A contract term the delivery lead handles; nothing to build |
| **Gap** | Not delivered yet; the row says what is missing |

## Services and milestones (Sections 3 and 4)

| Point | Status | Where |
|---|---|---|
| Lab Guide aligned to the agreed table of contents | Delivered; screenshots and task GIFs Pilot | `Instructions/`, [masterdoc.json](masterdoc.json), [SCREENSHOT-TODO.md](SCREENSHOT-TODO.md) |
| Golden Environment and one environment per participant | Delivered, Pilot | `setup/bicep/`, `setup/deploy-01.json`, `setup/assets/labfiles/`, [setup/README.md](setup/README.md) |
| Functioning MCP server | Delivered, Pilot | `CloudLabsAI-Azure/agentic-msp-mcp-server`, release `v3.0.0` |
| Automation of identities, RBAC, policies and seeded data | Delivered | `setup/assets/labfiles/provision/`, `setup/policy/`, `setup/scripts/` |
| Customer test environment | Event | [SUPPORT-GUIDE.md, Phase 5 step 10](SUPPORT-GUIDE.md#phase-5-run-the-pilot) |
| Documentation and handover (Exhibits B to E) | Delivered | [Handover package](#handover-package-exhibit-f-part-3) below |
| 4 workshops of up to 25 concurrent participants, 4 hours of access, 24 hours of review | Event | [AGENDA.md](AGENDA.md), [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md), [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md) |
| Milestone 1, due 2026-11-15: design pack approved in writing | Delivered; approval pending | [DESIGN-PACK.md](DESIGN-PACK.md) |
| Milestone 1: readiness and baseline consistency report of the Golden Environment | Pilot | The readiness check and consistency report of the test deployment ([setup/README.md, Step 6](setup/README.md#step-6-run-one-test-deployment)) |
| Milestone 1: customer test environment and Lab Guide | Pilot | One deployed environment, handed over as Phase 5 step 10 describes |
| Milestone 1: executed acceptance test results (Exhibit G) | Pilot | [tests/acceptance/README.md](tests/acceptance/README.md): scripts and procedures delivered; the run needs a deployed environment |
| Milestone 1: pilot test run with the requester's subject matter expert | Event | [SUPPORT-GUIDE.md, Phase 5](SUPPORT-GUIDE.md#phase-5-run-the-pilot) |
| Milestone 2: workshop completion and participant count | Event | [SUPPORT-GUIDE.md, Workshop report](SUPPORT-GUIDE.md#workshop-report) |
| Fees, invoices, purchase order, payment terms | Commercial | |
| No requester information, participant data, credentials or requester-specific files in a public repository; the MCP source repository private | Delivered | Both repositories are private and hold synthetic data only; no file, commit or archive names the requester (checked by the name scan in `tools/qa/qa-scan.py`). The lab files archive carries the MCP server source to the lab VMs: see [setup/README.md](setup/README.md#questions-for-cloudlabs), question 10 |

## Exhibit A: Scope and participant outcome

| Point | Status | Where |
|---|---|---|
| A turnkey, repeatable, isolated environment to ground an agent, use and extend MCP tools with read and controlled write operations, and show identity boundaries, least privilege, data protection and auditability | Delivered | [README.md](README.md), [AGENDA.md](AGENDA.md), Exercises 1 to 7 |
| Participant experience: sign up, launch the lab, verify readiness, begin building | Delivered | [Instructions/getting-started.md](Instructions/getting-started.md), Exercise 1 Task 1 |
| Part 1: Golden Environment and one environment per participant | Delivered, Pilot | [DESIGN-PACK.md, section 1](DESIGN-PACK.md#1-architecture-figure-b1) |
| Part 1: functioning MCP server | Delivered, Pilot | [DESIGN-PACK.md, section 2](DESIGN-PACK.md#2-mcp-server-and-tool-catalog-exhibit-c) |
| Part 1: synthetic seeded data | Delivered | [setup/DATA-SPEC.md](setup/DATA-SPEC.md) |
| Part 1: Lab Guide with expected results for self-checking | Delivered | Every task has **Expected results**; every task of five minutes or more has **Troubleshooting**; every exercise has **Success Criteria** |
| Part 1: readiness check | Delivered | `setup/assets/labfiles/tools/Test-LabReadiness.ps1` (desktop shortcut **Lab readiness check**) |
| Part 1: validation scripts | Delivered; registration Event | [validation-scripts/README.md](validation-scripts/README.md): 14 graded tasks |
| Part 1: reset and recovery automation | Delivered, Adjusted (7) | [setup/tenant/RUNBOOK.md, Event day](setup/tenant/RUNBOOK.md#event-day-checks-spares-and-resets) |
| Part 1: runbooks and test scripts | Delivered | [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md), [setup/tenant/PURVIEW-RUNBOOK.md](setup/tenant/PURVIEW-RUNBOOK.md), `tests/acceptance/`, `setup/tests/`, the MCP server's `tests/` |
| Part 1: customer test environment for 10 business days | Event | [SUPPORT-GUIDE.md, Phase 5 step 10](SUPPORT-GUIDE.md#phase-5-run-the-pilot) |
| Part 1: technical support during workshops | Event | [SUPPORT-GUIDE.md, Phase 6](SUPPORT-GUIDE.md#phase-6-support-the-workshop) |
| Part 2: participants perform the exercises; controls are safe by default, and no exercise asks a participant to fix a security exposure | Delivered | [BUILD-NOTES.md](BUILD-NOTES.md#scenario-and-audience) |
| Part 3: requester dependencies (purchase order, design pack review within 3 business days, network prerequisites confirmed, a named contact at each workshop) | Commercial, Event | [DESIGN-PACK.md, Sign-off](DESIGN-PACK.md#sign-off), [AGENDA.md](AGENDA.md#participant-prerequisites), [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#before-the-window-from-30-minutes-before-the-start) |
| Part 4: optional and excluded items (instructor-led delivery, extra seats or workshops, branding, a requester dataset, production deployment, Dynamics 365 Customer Service, third-party PSA products, GLPI, licenses outside the lab, participant devices) | Commercial | None of them is built. The lab has no instructor, uses Dataverse as its only ticketing backend, and uses the synthetic dataset |

## Exhibit B: Architecture and Golden Environment

| Point | Status | Where |
|---|---|---|
| Figure B1 is binding | Delivered | [DESIGN-PACK.md, section 1](DESIGN-PACK.md#1-architecture-figure-b1); the diagram `Instructions/media/architecture.svg`, built by `tools/diagrams/build_diagrams.py` |
| Foundry Agent Service, GPT-5.1 Global Standard, text-embedding-3-small; the agent's own Entra Agent ID | Delivered | `setup/bicep/modules/foundry.bicep`, `provision/foundry/New-SupportAgent.ps1`, `tools/Get-AgentIdentity.ps1` |
| Dataverse in a Power Platform developer environment with a custom Service Desk model-driven app | Adjusted (9) | `provision/powerplatform/`, `provision/dataverse/` |
| GLPI not used | Delivered | Dataverse is the only ticketing backend |
| Container Apps (Consumption), API Management (Developer), AI Search (Basic), Key Vault: one each per participant | Delivered | `setup/bicep/modules/` |
| Log Analytics, Application Insights, Dataverse auditing | Delivered | `monitoring.bicep`, `schema.json` (`audit`) |
| Purview DLP, sensitive information types and sensitivity labels in each tenant; Dataverse column security | Delivered, Pilot | `provision/purview/Set-PurviewProtection.ps1`, [setup/tenant/PURVIEW-RUNBOOK.md](setup/tenant/PURVIEW-RUNBOOK.md), `provision/dataverse/security.json` |
| Browser access through CloudLabs; lab VM Standard_D2s_v5 over HTTPS; nothing installed on participant devices | Delivered | `setup/bicep/modules/labvm.bicep`, [AGENDA.md](AGENDA.md#participant-prerequisites) |
| Data flow: export to Blob storage, index in AI Search, retrieval by the agent; agent, API Management, MCP server, Dataverse Web API | Delivered | `provision/export/Export-SearchContent.ps1`, `tools/New-KnowledgeIndex.ps1`, Exercise 1 Task 2 |
| Identity and authorization flow | Adjusted (1, 2) | [DESIGN-PACK.md, section 4](DESIGN-PACK.md#4-identity-and-token-flow-design) |
| Network flow: HTTPS through CloudLabs; public endpoints restricted by authentication and network rules | Adjusted (10) | [DESIGN-PACK.md, Flows](DESIGN-PACK.md#flows) |
| Isolation: a dedicated tenant per participant, nothing shared, never a tenant administrator role, supplier accounts never issued | Delivered, Pilot | [DESIGN-PACK.md, Isolation boundary](DESIGN-PACK.md#isolation-boundary); acceptance criterion 2 |
| A reset creates a new environment in a new tenant | Adjusted (7) | [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md#reset-an-environment-within-60-minutes) |
| Golden Environment version v1.0, recorded in the readiness report | Delivered | `Test-LabReadiness.ps1`, the resource group tag `lab-golden-environment`, the template output **Golden Environment Version** |

## Exhibit C: MCP server deliverable

| Point | Status | Where |
|---|---|---|
| A functioning MCP server, not a REST API or a concept, and not built from scratch by participants | Delivered | The MCP server repository, release `v3.0.0`, with 107 tests |
| Part 1: hosting, transport, connectivity and security model | Delivered | [DESIGN-PACK.md, Hosting and security model](DESIGN-PACK.md#hosting-and-security-model) |
| Part 2: baseline tool catalog | Delivered | All 12 baseline read tools and 7 baseline write tools, plus `get_ticket_notes`, `get_customer_contacts`, `search_customer_documents` and `get_customer_document` ([DESIGN-PACK.md, Tool catalog](DESIGN-PACK.md#tool-catalog)) |
| Part 3: description, input schema, output schema, required permission, input validation and structured errors on every tool | Delivered | `TOOLS.md` and `tests/test_catalogue.py` in the MCP server repository |
| Part 3: read and write operations in separate tools with separate permissions | Delivered | `/read/mcp` and `/write/mcp`; Dataverse roles **Service Desk Agent Read** and **Service Desk Agent Write** |
| Part 3: approval before every write runs | Delivered, Pilot | The agent's MCP tool `servicedesk-write`, approval always |
| Part 3: every invocation logged with correlation ID, user, agent ID, tool, argument summary, authorization result, backend call, outcome, duration and any failure | Delivered | [DESIGN-PACK.md, Tool contract](DESIGN-PACK.md#tool-contract-exhibit-c-part-3) |
| Part 4: source in a private repository the requester can access | Delivered; access Event | Read access for the requester's named people in Phase 1 ([README.md](README.md#delivery-path)) |
| Part 4: pre-cloned on each lab VM, with generic code, configuration templates and synthetic data only | Delivered | A Git repository of the release at `C:\LabFiles\mcp-server` (`provision/mcp/Deploy-McpBaseline.ps1`) |
| Part 4: documented build, test, deploy, rollback and recovery | Delivered | The MCP server README, section "Build, test, deploy, roll back and recover" |
| Part 4: participants inspect, modify, extend, test and redeploy their own server without affecting others | Delivered | Exercise 3 Task 4, Exercise 4 Tasks 4 and 5, [solutions/exercise-4-task-5/](solutions/exercise-4-task-5/README.md) |
| Part 5: one read and one controlled write end to end, visible in Dataverse and the correlated log | Pilot | Acceptance criterion 6, `tests/acceptance/Test-ReadWriteFlow.ps1` |
| Part 6: scope, approver, configuration and rejection | Delivered, Pilot | [DESIGN-PACK.md, Approval model](DESIGN-PACK.md#approval-model-for-write-tools-exhibit-c-part-6) |
| Part 6: presentation of the approval request (server, tool, full arguments) | Pilot | BUILD-NOTES question 12 |
| Part 6: timeout, with the expiry confirmed in the design pack | Pilot, Adjusted (6) | Measured in the pilot and recorded in the design pack |
| Part 6: duplicate submission | Adjusted (4) | The duplicate guard in the MCP server, `tests/test_duplicates.py` |
| Part 6: audit of every request and decision | Adjusted (5) | `tools/Get-ActionTrail.ps1`, acceptance criterion 11 |

## Exhibit D: Data, identity, security and auditability

| Point | Status | Where |
|---|---|---|
| Part 1: minimum volumes and required fields | Delivered | [DESIGN-PACK.md, section 3](DESIGN-PACK.md#3-data-specification-exhibit-d-part-1), [setup/DATA-SPEC.md](setup/DATA-SPEC.md#volumes); checked by `setup/tests/test_seed_determinism.py` and acceptance criterion 4 |
| Part 1: the eight scenario types, each used in the guide with documented expected results | Delivered | [setup/DATA-SPEC.md, Scenario types](setup/DATA-SPEC.md#scenario-types) and [Records the exercises depend on](setup/DATA-SPEC.md#records-the-exercises-depend-on) |
| Part 2: the six identities and their permissions | Delivered | [DESIGN-PACK.md, Identities](DESIGN-PACK.md#identities-exhibit-d-part-2), [setup/README.md](setup/README.md#identities-and-their-rights) |
| Part 3: authentication and token flow, documented in the design pack | Delivered, Adjusted (1) | [DESIGN-PACK.md, Token flow](DESIGN-PACK.md#token-flow-for-one-write-exhibit-d-part-3), Exercise 5 Task 1 |
| Part 4: least privilege with read and write separated; secrets only in Key Vault through managed identity | Delivered, Adjusted (11) | [DESIGN-PACK.md, Roles, least privilege and secrets](DESIGN-PACK.md#roles-least-privilege-and-secrets-exhibit-d-part-4); acceptance criterion 9 |
| Part 5: column security on contact fields; internal flag on notes kept out of customer responses | Delivered | Exercise 4 Task 2, Exercise 6 Task 1 |
| Part 5: Purview DLP with sensitive information types and a sensitivity-labeled document, applied to agent interactions as agreed in the design pack | Delivered, Pilot | [DESIGN-PACK.md, section 5](DESIGN-PACK.md#5-data-protection-design-exhibit-d-part-5), Exercise 6 Task 2 |
| Part 5: approval for write tools; input validation on every tool | Delivered | The MCP server |
| Part 6: log sources (Application Insights, API Management, MCP server, Key Vault, Dataverse audit, Purview events) | Delivered, Adjusted (8) | [DESIGN-PACK.md, section 6](DESIGN-PACK.md#6-logging-retention-and-correlation-exhibit-d-part-6) |
| Part 6: logs exist only for the life of the environment; no participant data kept after teardown | Event | [setup/tenant/RUNBOOK.md, Phase 7](setup/tenant/RUNBOOK.md#phase-7-close-the-event) |
| Part 6: Azure subscription audit logs can be shared up to 30 days after deletion | Event | Each subscription's activity log is exported before deletion and kept 30 days ([setup/tenant/RUNBOOK.md, Phase 7](setup/tenant/RUNBOOK.md#phase-7-close-the-event)) |
| Part 6: each participant sees only their own logs; reviewers use the participants' lab access for 24 hours | Delivered, Event | One tenant per participant; [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#at-the-end-of-the-window) |
| Part 6: participants export their audit evidence in Exercises 6 and 7; the requester can export from any environment until the review window ends | Delivered, Event | Exercise 6 Task 3, Exercise 7 Task 1 (`C:\LabFiles\evidence`); [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#at-the-end-of-the-window) |
| Part 6: one correlation ID links request, agent, tool, authorization result, backend call, action and outcome | Delivered, Pilot | Exercise 6 Task 3; acceptance criterion 11 |

## Exhibit E: Provisioning, reset, support and capacity

| Point | Status | Where |
|---|---|---|
| Golden Environment template and version recorded for every workshop | Event | The consistency reports ([RUNBOOK.md, T minus 24 hours](setup/tenant/RUNBOOK.md#t-minus-24-hours-readiness-and-consistency)) and the [workshop report](SUPPORT-GUIDE.md#workshop-report) |
| Environments created by automation from the template and scripts before each workshop | Delivered | The CloudLabs template and VM provisioning |
| Reset and reseeding in a new tenant from the Golden Environment | Adjusted (7) | [RUNBOOK.md](setup/tenant/RUNBOOK.md#reset-an-environment-within-60-minutes) |
| Every environment passes the readiness check before participant access, and the consistency report is shared | Event | [RUNBOOK.md, T minus 24 hours](setup/tenant/RUNBOOK.md#t-minus-24-hours-readiness-and-consistency) |
| 2 spare environments per workshop, readiness-checked and held unassigned | Event | [RUNBOOK.md, Rules for every event](setup/tenant/RUNBOOK.md#rules-for-every-event) |
| A failed environment replaced with a spare within 15 minutes; the participant's time extended | Event | [RUNBOOK.md](setup/tenant/RUNBOOK.md#replace-a-failed-environment-with-a-spare-within-15-minutes), [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#replace-a-failed-environment-with-a-spare) |
| A deleted environment can't be recovered; environments ready and validated before the start | Event | [RUNBOOK.md](setup/tenant/RUNBOOK.md#from-30-minutes-before-the-start) |
| Up to 25 concurrent participants per workshop, 4 workshops | Pilot | Acceptance criterion 13 (`tests/acceptance/Measure-ConcurrentRun.ps1`) |
| Scheduling 15 business days ahead; rescheduling and cancellation with 10 business days' notice; unused workshops lapse | Commercial | [AGENDA.md](AGENDA.md) records the agreed dates |
| The customer test environment is kept only for its period; pilot environments are available 24 hours from the lab start, then deleted | Event | [SUPPORT-GUIDE.md, Phase 5 step 10](SUPPORT-GUIDE.md#phase-5-run-the-pilot) |
| A 4-hour window covering sign-in, the seven exercises and close, with no scheduled breaks; supplier delays extend the participant's time; judging in the additional 24 hours | Delivered | [AGENDA.md](AGENDA.md), [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#how-this-lab-is-delivered) |
| The pilot validates that representative participants complete the lab within 4 hours | Event | [SUPPORT-GUIDE.md, Phase 5](SUPPORT-GUIDE.md#phase-5-run-the-pilot) |
| Targets: ready 30 minutes before the start, reset within 60 minutes, replacement within 15 minutes, chat within 5 minutes, email within 60 minutes, escalation within 30 minutes, participant count changes 5 business days ahead | Event | [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md#phase-6-support-the-workshop), [RUNBOOK.md](setup/tenant/RUNBOOK.md#t-minus-5-working-days-confirm-the-event) |
| Prerequisites: a current Edge or Chrome; outbound HTTPS to `*.cloudlabs.ai`, `*.azure.com`, `*.microsoft.com`, `*.powerapps.com` and `*.dynamics.com`; nothing to install | Delivered | [AGENDA.md, Participant prerequisites](AGENDA.md#participant-prerequisites) |
| Limitations: environments exist for the window and the review window only | Delivered | [AGENDA.md, Logistics](AGENDA.md#logistics) |

## Exhibit F: Commercial inclusions and ownership

| Point | Status | Where |
|---|---|---|
| Azure services for provisioning, the workshop hours and teardown | Delivered | [estimates/](estimates/), [estimates/ESTIMATE-NOTES.md](estimates/ESTIMATE-NOTES.md) |
| Model usage up to 4 million input and 0.4 million output tokens per environment per workshop | Delivered, Pilot | The estimate assumes about 2 million input tokens per participant; BUILD-NOTES question 23 measures it |
| Notify the requester at 80 percent of the token allowance, before any overage | Event | [SUPPORT-GUIDE.md, Watch the token allowance](SUPPORT-GUIDE.md#watch-the-token-allowance) |
| Power Platform developer environments and Dataverse capacity | Delivered | A managed developer environment per tenant |
| Microsoft licenses for lab identities, including Purview | Delivered; offer IDs Pilot | Microsoft 365 E5 and Power Apps Premium from the user-creation JSON, Purview pay-as-you-go per tenant ([README.md](README.md#required-licenses-and-entitlements)); [setup/README.md](setup/README.md#questions-for-cloudlabs), question 4 |
| CloudLabs platform charges, readiness checks, resets in the window, workshop support | Commercial, Event | [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md) |
| Part 3: ownership and reuse rights for each deliverable | Delivered | The [Handover package](#handover-package-exhibit-f-part-3) below; the MCP server README's License section states the terms, and its `THIRD-PARTY-NOTICES.md` lists the open-source components in the image |
| Microsoft services under Microsoft's terms; open-source components keep their own licenses | Delivered | The MCP server's `THIRD-PARTY-NOTICES.md` |
| Licensing valid for the contracted workshop use | Delivered, Pilot | The licensing notes in `research/` (sources on Microsoft Learn); the offer IDs are confirmed with CloudLabs |
| Reproduction: the requester can deploy and run individual environments in its own tenants from the artifacts and runbooks | Gap | The template boots the lab VM from the CloudLabs jump VM image, fetches its scripts and the lab files from the CloudLabs template library, and uses CloudLabs helper functions. A path without CloudLabs needs a marketplace Windows image with a Custom Script Extension, and a template parameter for the script location; neither is built yet |

## Exhibit G: Acceptance and change control

| Criterion | Status | Test |
|---|---|---|
| 1. Participant login and launch within 5 minutes | Pilot | [Procedure 1](tests/acceptance/README.md#criterion-1-login-and-launch-within-5-minutes) |
| 2. Isolation | Pilot | `Test-Isolation.ps1` |
| 3. Baseline consistency | Pilot | `Export-EnvironmentFingerprint.ps1`, `Compare-ConsistencyReports.ps1` |
| 4. Seeded-data validation | Pilot | `Test-SeedData.ps1` |
| 5. Grounded retrieval on 5 scripted questions | Pilot | `Test-GroundedRetrieval.ps1`, `grounded-questions.json` |
| 6. MCP read and controlled write | Pilot | `Test-ReadWriteFlow.ps1` and the manual checks |
| 7. MCP modification, redeployment and rollback | Pilot | `Test-RedeployRollback.ps1` |
| 8. Authorization denial and least privilege | Pilot, Adjusted (3) | `Test-UserAuthorization.ps1` |
| 9. Secure secret handling | Pilot | `Test-SecretHandling.ps1` |
| 10. Data-protection enforcement | Pilot | `Test-DataProtection.ps1` and the Purview check |
| 11. Correlated audit evidence | Pilot | `Test-CorrelatedAudit.ps1` |
| 12. Environment reset within 60 minutes in a new tenant | Pilot, Adjusted (7) | [Checklist 12](tests/acceptance/README.md#criterion-12-reset-within-60-minutes) |
| 13. 25 concurrent participants without degradation | Pilot | [Procedure 13](tests/acceptance/README.md#criterion-13-25-concurrent-participants) |
| 14. Failure recovery from a spare within 15 minutes, recorded in the workshop report | Pilot, Event | [Checklist 14](tests/acceptance/README.md#criterion-14-recovery-from-a-spare-within-15-minutes), [workshop report](SUPPORT-GUIDE.md#workshop-report) |
| Part 2: review period, rejection notice, correction, retest with the supplier's test scripts and support, payment on acceptance | Commercial; test scripts Delivered | [tests/acceptance/README.md](tests/acceptance/README.md) |
| Part 3: change control | Commercial | A change to the design updates [DESIGN-PACK.md](DESIGN-PACK.md) and this file ([BUILD-NOTES.md, How to change the lab](BUILD-NOTES.md#how-to-change-the-lab)) |

## Exhibit H: Agreed table of contents

| Point | Status | Where |
|---|---|---|
| 7 exercises and 27 tasks; the Lab Guide follows the table of contents task for task | Delivered | `Instructions/exercise-1.md` to `exercise-7.md`: 27 tasks and 104 steps, each step opening with the agreed step's text ([BUILD-NOTES.md](BUILD-NOTES.md#scenario-and-audience)) |
| Schedule: sign-in 10 minutes, Exercises 1 to 7 of 35, 25, 35, 50, 30, 30 and 15 minutes, close 10 minutes | Delivered | [AGENDA.md](AGENDA.md); the task minutes in each exercise add up to its duration |
| Platform dependencies: the closest working equivalent, notified in writing within 3 business days and confirmed in the design pack or the pilot | Delivered | [DESIGN-PACK.md, section 8](DESIGN-PACK.md#8-adjustments-under-the-platform-dependency-clause) |
| The binding architecture diagram is Figure B1 | Delivered | [DESIGN-PACK.md, section 1](DESIGN-PACK.md#1-architecture-figure-b1) |

## Handover package (Exhibit F, Part 3)

| Deliverable | Where |
|---|---|
| MCP server source and container build files | The MCP server repository: `src/`, `Dockerfile`, `requirements.txt`, `constraints.txt`, `pyproject.toml`, `tests/`, `scripts/` |
| Bicep templates for the per-environment Azure resources | `setup/bicep/`, compiled to `setup/deploy-01.json` |
| API Management policies | `setup/apim/` |
| Dataverse solution: tables, Service Desk app, security roles, column security profiles | As code in `setup/assets/labfiles/provision/dataverse/` (`schema.json`, `security.json`, `Deploy-ServiceDeskSchema.ps1`, `Set-DataverseSecurity.ps1`). The tables, choices, views, forms and app are built into the unmanaged solution `RelecloudServiceDesk`; to hand over a solution package, add the security roles and the column security profile to it as existing components in the test environment, then export it |
| Seed data and loader scripts | `setup/assets/labfiles/seed/` (`generate_seed.py`, `load_seed.py`); the generated data in the MCP server repository's `fixtures/seed/` |
| Agent definition | `setup/assets/labfiles/provision/foundry/` (`New-SupportAgent.ps1`, `New-McpConnections.ps1`) and `setup/assets/labfiles/agent/` (the instructions) |
| Purview configuration runbook | [setup/tenant/PURVIEW-RUNBOOK.md](setup/tenant/PURVIEW-RUNBOOK.md) and `provision/purview/Set-PurviewProtection.ps1` |
| Readiness and validation scripts | `setup/assets/labfiles/tools/Test-LabReadiness.ps1`, `validation-scripts/` |
| Synthetic data | As seed data above, plus `setup/assets/labfiles/search/sample-documents/` |
| Lab Guide content | `Instructions/` and [masterdoc.json](masterdoc.json) |
| Architecture diagrams | `Instructions/media/` (SVG sources and animated PNGs), built by `tools/diagrams/` |
| Runbooks, test scripts and documentation | [setup/README.md](setup/README.md), [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md), [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md), [BUILD-NOTES.md](BUILD-NOTES.md), [DESIGN-PACK.md](DESIGN-PACK.md), `tests/acceptance/`, `setup/tests/`, the MCP server's `README.md` and `TOOLS.md` |
| Not transferred: CloudLabs platform automation | The CloudLabs template configuration, the user-creation JSON and governance files in `setup/scripts/` and `setup/policy/`, the CloudLabs jump VM image and its helper functions |

## Open items

1. **Reproduction without CloudLabs** (Exhibit F): the gap described above. It changes the template, so build it after the pilot and test it with one deployment.
2. **Milestone 1 evidence that needs a deployed environment:** the Golden Environment readiness and consistency report, the customer test environment and the executed acceptance test results. All three come from one test deployment and the pilot (Phase 5).
3. **Pilot values:** the approval prompt labels and expiry, the license offer IDs, and the other questions in [BUILD-NOTES.md](BUILD-NOTES.md#open-questions-to-settle-in-the-pilot).

## Phase checklist

- [ ] Every **Gap** row has an owner and a date
- [ ] Every **Pilot** row was confirmed in the pilot, and its evidence is filed
- [ ] The requester received this file with the design pack

---

**Next:** Phase 2, build and publish the template: [setup/README.md](setup/README.md).
