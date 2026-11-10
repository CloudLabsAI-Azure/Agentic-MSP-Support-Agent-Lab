# Changelog

What changed in each version of the Agentic MSP Support Agent Guided Lab. The reasons behind each decision are in [BUILD-NOTES.md](BUILD-NOTES.md).

## Version 3.0, Golden Environment v1.0 (2026-11-09, branch `toc-v3`)

Rebuilt for the agreed table of contents v3: 7 exercises, 27 tasks and 104 steps in a 4-hour lab window with no scheduled breaks, followed by a 24-hour review of the submitted work.

### Session and guide

- Exercises take 220 minutes (35, 25, 35, 50, 30, 30 and 15), with 10 minutes to sign in and 10 minutes to close. Every task has fixed minutes that add up to its exercise.
- Every page follows the Lab Builder v2 anatomy: a stakeholder question in the Scenario, an animated diagram with a "How to read this diagram" paragraph, Objectives, tasks with **Expected results** and **Troubleshooting**, **Success Criteria** with a negative check, **Apply It in Production**, a **Knowledge Check** and a Summary. Exercise 7 ends with **Congratulations** and the reusable assets.
- One participant per environment: the guide says "you" throughout, and the team model is gone. Each participant still uses two identities, the Senior Technician and the Tier 1 Technician.
- A **Lab notes.txt** file on the desktop collects the evidence each exercise asks for, and Exercise 7's business case points back to it.
- New delivery documents: the README delivery path, [AGENDA.md](AGENDA.md), [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md) for the pilot and the self-paced workshop day, and the acceptance test suite in `tests/acceptance/`.
- Nine animated diagrams built as code in `tools/diagrams/` replace the two Mermaid diagrams.

### Environment

- One dedicated Microsoft Entra tenant and Azure subscription per participant, in Canada Central (previously one shared tenant with team accounts in Sweden Central).
- The lab user is the Senior Technician; the Tier 1 Technician comes from the user-creation JSON. Provisioning uses the lab user's Global Administrator role once, through a certificate-based setup app, and removes it before the lab starts.
- `gpt-5.1` Global Standard replaces `gpt-5.4-mini`; API Management moves to the Developer tier; the Dataverse environment is a managed developer environment with Power Apps Premium (unmanaged developer environments can no longer be created after 2026-11-15).
- The template is authored in Bicep (`setup/bicep/`) and compiled to `setup/deploy-01.json`.
- The agent has two MCP tools on two connections: `servicedesk-read` without approval and `servicedesk-write` with approval on every call.
- Provisioning exports the searchable content to Blob storage (753 documents, one JSON file each); participants build the index from it in Exercise 1.
- The contact phone columns are protected by column security from the start, and Microsoft Purview's DLP policy and sensitivity label are in place before the lab starts.

### MCP server (release `v3.0.0`)

- Separate read and write endpoints (`/read/mcp` and `/write/mcp`), with output schemas on every tool.
- An Agent Action row for every write attempt that reaches the server, so a denied action leaves a record in Dataverse too. A declined approval never reaches the server; the agent run records it.
- Duplicate submission protection: a repeated identical write within 10 minutes, with the same correlation ID or from the same user after a successful first call, returns the first result.

### Data

- 120 knowledge articles (previously 50), 36 customer documents in a new table, 15 technicians in 4 teams, 500 historical tickets, 60 open tickets plus 2 new incidents, and 1,436 ticket notes, generated deterministically. `setup/DATA-SPEC.md` lists every record the guide quotes.

### Delivery documents (2026-11-10)

- [DESIGN-PACK.md](DESIGN-PACK.md): the Milestone 1 design pack (architecture, tool catalog with each tool's required permission, data specification, identity and token-flow design) and the adjustments made under the platform-dependency clause, with a sign-off block.
- [SOW-COVERAGE.md](SOW-COVERAGE.md): every point of the statement of work and its exhibits, with its status and the file that delivers it, the handover package, and the open items.
- [SUPPORT-GUIDE.md](SUPPORT-GUIDE.md): the customer test environment hand-over, token checks during the window with the 80 percent notice, the reviewers' export, and the workshop report.
- [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md): each subscription's activity log is exported before deletion and kept 30 days for the requester.

## Version 2.2 (2026-10-02, branch `toc-v2`)

The TOC v2.2 build: 7 exercises, 27 tasks and 104 steps in a 6-hour session for teams of two identities in a shared tenant, with the MCP server release `v2.0.0`.

## Version 1.0 (2026-10-01, branch `main`)

The first build of the lab with the MCP server release `v1.0.0`.
