# Acceptance Tests

> **Delivery path: Phase 5 of 8, run the pilot (acceptance).** These tests prove the 14 acceptance criteria of the statement of work (Exhibit G) on a test environment and produce the evidence the customer signs off. Before you start, Phases 2 to 4 must be complete: the template deploys, the environment is prepared, and the validation steps are registered ([validation-scripts/README.md](../../validation-scripts/README.md)). Start of the path: [README.md](../../README.md#delivery-path).

**Who:** the supplier's test engineer, with a second person for the Tier 1 sign-in and the timed procedures. **Time:** about half a day for criteria 2 to 11 on one environment; criteria 1, 12, 13 and 14 are scheduled runs.

## Before you start

- **Use a test environment, never a participant's.** Several tests change data (one ticket's priority, one status request rejected) or redeploy the MCP server for a few minutes, and the log-based validation steps would count the test's calls as participant work.
- **Provision at least 24 hours ahead,** as for an event: sensitivity labels take up to 24 hours, the DLP policy about an hour, and Purview activity 60 to 90 minutes.
- **Prepare the test environment like a participant at the end of Exercise 1 Task 2:** the index `servicedesk-knowledge` is built (`C:\LabFiles\tools\New-KnowledgeIndex.ps1`) and the agent has the Azure AI Search tool (portal, or `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions`). Criterion 5 needs both.
- **Give OAuth consent once per user:** sign in to the Foundry portal as the Senior Technician, open the agent's playground, ask a question that uses the Service Desk tools and select **Open Consent**; repeat as the Tier 1 Technician. The tests stop with a clear message when consent is missing.
- **Copy this folder to the lab VM,** for example to `C:\Acceptance`, and run the scripts in PowerShell 7 from there. They read `C:\LabFiles\lab-settings.json` and the seed manifest it names; pass `-SettingsPath` or `-ManifestPath` otherwise.
- **Sign-ins.** Each identity gets its own Azure CLI profile under `%USERPROFILE%\.relecloud-acceptance`, so the Senior Technician, the Tier 1 Technician and the provisioning identity never overwrite each other. A browser opens when a sign-in is needed: the tester types the Temporary Access Pass there. No script asks for, prints or stores a password, token or key.
- **Evidence.** Every script writes `criterion-NN-<DeploymentID>-<UTC time>.json` and `.md` to `-EvidencePath` (default `%USERPROFILE%\acceptance-evidence`) and exits with 0 (pass) or 1 (fail). Card-like numbers and credentials are redacted in every file.

## The criteria and their tests

| # | Criterion (Exhibit G) | Test | How | Passes when | Evidence to keep |
|---|---|---|---|---|---|
| 1 | Participant login and launch within 5 minutes | [Procedure 1](#criterion-1-login-and-launch-within-5-minutes) | Manual, timed | Launch to a signed-in Microsoft Foundry portal on the lab VM takes 5 minutes or less | Timestamp table, screen recording with a visible clock |
| 2 | Isolation | `Test-Isolation.ps1` | Script, run in both directions | Every read of the other environment (Resource Manager, AI Search, Foundry, Dataverse, API Management, Key Vault, Storage, Log Analytics) is refused or can't get a token | Two `criterion-02` reports |
| 3 | Baseline consistency | `Export-EnvironmentFingerprint.ps1` on each environment, then `Compare-ConsistencyReports.ps1` | Script | Every environment reports Golden Environment version v1.0, every readiness component is Ready, and no setting differs | Fingerprints, the readiness reports, the `criterion-03` report |
| 4 | Seeded-data validation | `Test-SeedData.ps1` | Script | Counts equal the seed manifest and meet the Exhibit D minimums, every scenario record exists with its facts, and the export holds 753 documents | `criterion-04` report |
| 5 | Grounded retrieval | `Test-GroundedRetrieval.ps1` with `grounded-questions.json` | Script | Each of the five questions cites all its expected sources (url_citation annotations mapped to `sourceId`) | `criterion-05` report with the answers and citations |
| 6 | MCP read and controlled write end to end | `Test-ReadWriteFlow.ps1`, plus [the manual checks](#criterion-6-manual-checks) | Script and manual | Read without approval; write with an approval request naming server, tool and full arguments; approved write applied in Dataverse; rejected write not executed and reported; log and Agent Action row present; duplicate submission returns the first result | `criterion-06` report, approval prompt screenshot, duplicate submission record |
| 7 | MCP modification, redeployment and rollback | `Test-RedeployRollback.ps1` | Script | The changed server builds, deploys as a new ready revision, reports its new version through the gateway, and the rollback serves the previous image and version | `criterion-07` report with build, deploy and rollback times |
| 8 | Authorization denial and least privilege | `Test-UserAuthorization.ps1` | Script (two sign-ins) | Tier 1's priority change is denied by Dataverse with no change; the Senior Technician's succeeds; both are in the MCP and gateway logs with the user's identity and in Dataverse (Agent Action rows; the audit record of the allowed change) | `criterion-08` report and both action trails |
| 9 | Secure secret handling | `Test-SecretHandling.ps1 -IncludeDeniedRead` | Script | No secret in the repositories, lab files or Container App configuration; secrets are Key Vault references; the MCP identity's secret read is in the Key Vault audit log; the participant can't read the value | `criterion-09` report |
| 10 | Data-protection enforcement | `Test-DataProtection.ps1`, plus [the Purview check](#criterion-10-purview-check) | Script and manual | Phone columns (and email after Exercise 6 Task 1, `-ExpectEmailWithheld`) withheld; the labelled document refused with `CONTENT_BLOCKED_BY_LABEL`; the card-number note withheld by policy; no internal-note fact in a customer reply | `criterion-10` report, Activity explorer screenshot |
| 11 | Correlated audit evidence | `Test-CorrelatedAudit.ps1` (runs `Get-ActionTrail.ps1`) | Script | One correlation ID finds the agent run, the approval, the gateway rows, the MCP log line with every Exhibit C field, the Dataverse audit record and the Agent Action row, with the same user throughout | `criterion-11` report and the exported trail (JSON and Markdown) |
| 12 | Environment reset within 60 minutes in a new tenant, passing readiness | [Checklist 12](#criterion-12-reset-within-60-minutes) | Manual, timed, with scripts 3 and 4 | Reset requested to readiness Ready in 60 minutes or less, in a new tenant, with a fingerprint identical to the golden one | Timestamp table, readiness report, fingerprint comparison |
| 13 | 25 concurrent participants without degradation | [Procedure 13](#criterion-13-25-concurrent-participants) with `Measure-ConcurrentRun.ps1` | Scheduled run of script 5 on 25 environments | Every environment answers every question with the expected sources; median answer time within 1.5 times the single-environment baseline; no unrecovered HTTP 429 or 5xx | The 25 `criterion-05` reports, the `criterion-13` report |
| 14 | Failure recovery from a readiness-checked spare within 15 minutes | [Checklist 14](#criterion-14-recovery-from-a-spare-within-15-minutes) | Manual, timed | From the reported failure to the participant working in the spare in 15 minutes or less | Timestamp table, the spare's readiness report and fingerprint |

The scripted tests read what they check (Resource Manager, Dataverse, Log Analytics, the Foundry API); only criteria 6, 7 and 8 change anything, and only in the test environment.

### Suggested order on one test environment

1. `Test-SeedData.ps1` (criterion 4) and `Export-EnvironmentFingerprint.ps1` (criterion 3) before anything changes.
1. `Test-GroundedRetrieval.ps1` (5), `Test-DataProtection.ps1` (10), `Test-ReadWriteFlow.ps1` (6), `Test-UserAuthorization.ps1` (8).
1. Wait at least five minutes (agent traces take 2 to 5 minutes), then `Test-CorrelatedAudit.ps1` (11).
1. `Test-SecretHandling.ps1` (9), `Test-RedeployRollback.ps1` (7) and, with a second environment's settings file, `Test-Isolation.ps1` (2).

## How to run each test

```powershell
Set-Location C:\Acceptance
$evidence = 'C:\Acceptance\evidence'

.\Test-SeedData.ps1 -Identity Provisioning -EvidencePath $evidence                  # criterion 4
.\Export-EnvironmentFingerprint.ps1 -OutPath C:\Acceptance\fingerprints              # criterion 3, on every environment
.\Compare-ConsistencyReports.ps1 -Path C:\Acceptance\fingerprints -EvidencePath $evidence
.\Test-GroundedRetrieval.ps1 -EvidencePath $evidence                                 # criterion 5
.\Test-ReadWriteFlow.ps1 -EvidencePath $evidence                                     # criterion 6 (asks to confirm)
.\Test-RedeployRollback.ps1 -EvidencePath $evidence                                  # criterion 7 (asks to confirm)
.\Test-UserAuthorization.ps1 -EvidencePath $evidence                                 # criterion 8 (asks to confirm)
.\Test-SecretHandling.ps1 -IncludeDeniedRead -EvidencePath $evidence                 # criterion 9
.\Test-DataProtection.ps1 -EvidencePath $evidence                                    # criterion 10
.\Test-CorrelatedAudit.ps1 -EvidencePath $evidence                                   # criterion 11
.\Test-Isolation.ps1 -OtherSettingsPath C:\Acceptance\environment-b\lab-settings.json -EvidencePath $evidence   # criterion 2
```

Notes per test:

- **Criterion 2.** Copy environment B's `lab-settings.json` to A's VM (it holds no secret) and run as A's Senior Technician; then swap and run on B. A refusal to issue a token counts as a pass: B's resources live in another tenant.
- **Criterion 3.** Run the fingerprint as a supplier account or `-Identity Provisioning`, so every section is readable. Add `-ReadinessReport <file>` with the readiness check's result exported as JSON (an array of objects with `Component` and `Status`) to include it in the comparison. Environment-specific names, IDs and the Deployment ID are replaced by placeholders, so any reported difference is real.
- **Criterion 4.** Run it as an account that reads every record (a supplier administrator, or `-Identity Provisioning`). It checks the counts of data version 3.0: 24 customers, 72 contacts, 63 procedures, 36 customer documents, 12 runbooks, 120 articles, 15 technicians in 4 teams, 16 SLA definitions, 500 historical and 60 open tickets plus TCK-10561 and TCK-10562, 1,436 notes, and 753 searchable documents.
- **Criterion 5.** `grounded-questions.json` holds the five questions and the expected sources from the seed manifest: KB0023 (RBA-2201), KB0058 for Woodgrove Bank's hourly disconnects (versions decide it), KB0045 for Margie's Travel's firewall change (Break-Fix decides it), CDOC-026 for Humongous Insurance's escalation contacts and hours, and KB0133 with RB-005 for Consolidated Messenger's north depot certificate. If the seed changes, update the file from `scenarios` in the manifest.
- **Criterion 6.** The write target is `scenarios.write_targets.approved_priority_change` (TCK-10544). The test flips its priority between P3 and P4, so it can run again; the rejected status change leaves the status unchanged.
- **Criterion 7.** Runs as the Senior Technician by default (`-Identity Current` for a supplier account), which proves a participant's rights are enough. The test image `mcp-server:3.0.99` stays in the registry. The participant path, `Deploy-McpServer.ps1`, is covered by Exercise 3 Task 4 and its validation step in the pilot.
- **Criterion 8.** The target is `scenarios.write_targets.tier1_versus_senior` (TCK-10543). Dataverse audits changes only, so the denied request has no audit record: its Dataverse evidence is the Agent Action row, which the MCP server writes for allowed and denied writes. If the Tier 1 Technician can't call the agent through the API (HTTP 403: the account holds Foundry Agent Consumer, a pilot item), make both requests in the playground and run `-Tier1CorrelationId <id> -SeniorCorrelationId <id>`.
- **Criterion 9.** Scans this repository, `C:\LabFiles\mcp-server` and `lab-settings.json` (add paths with `-ScanPath`). Findings name the file, line and kind, never the value. The Key Vault audit check needs the vault's diagnostic setting to Log Analytics and a server start in the last `-AuditDays` days.
- **Criterion 11.** Defaults to the Senior Technician's most recent successful write (run criterion 6 first). The trail is exported as `criterion-11-trail-<correlation ID>.json` and `.md`, the same evidence participants export in Exercises 6 and 7.

## Manual procedures

### Criterion 1: login and launch within 5 minutes

Two people: one participant, one timekeeper with a clock in the screen recording. The environment is pre-provisioned (hot), as on event day.

| Step | What the participant does | Record |
|---|---|---|
| T0 | Selects **Launch Lab** on the CloudLabs lab page | Time |
| T1 | The lab VM desktop appears in the browser | Time |
| T2 | Opens the **Microsoft Foundry** shortcut and signs in with the user name and Temporary Access Pass from the **Environment** tab | Time |
| T3 | The agent `msp-support-agent` opens in the playground | Time |
| T4 | The **Lab readiness check** shortcut reports every component Ready | Time (not part of the 5 minutes) |

Pass: T3 minus T0 is 5 minutes or less. Repeat with three participants; report each time and the longest.

### Criterion 6: manual checks

- **Approval prompt.** In the playground, ask for a priority change and take a screenshot of the approval prompt: it must show the tool and the full arguments. The API-level evidence in the `criterion-06` report also records the server label (`servicedesk-write`).
- **Approval expiry.** Ask for a write and leave the approval unanswered for the expiry the design pack records; then approve. Pass: the tool is not called after expiry and the agent says so. Record the observed behavior: Microsoft doesn't document the expiry, so the design pack carries the measured value.
- **Duplicate submission.** Send the same write twice with the same correlation ID within 10 minutes, as the MCP server's README documents for testing. Pass: one change in Dataverse, two MCP log lines, and the second call returns the first result (its Agent Action row has the outcome **Duplicate, first result returned**).

### Criterion 10: Purview check

At least 90 minutes after `Test-DataProtection.ps1`, sign in to the Microsoft Purview portal as the Senior Technician (role group **Information Protection Analysts**) and open **Data loss prevention** > **Activity explorer** with the activity filter **DLP rule matched**. Pass: an event for the MCP server's application at the time of the test. Activity explorer is not real time (60 to 90 minutes or more), so the scripted check reads the MCP server's own decision and this screenshot completes the evidence.

### Criterion 12: reset within 60 minutes

| Step | Action | Record |
|---|---|---|
| R0 | Request the reset of the test participant's environment in CloudLabs | Time |
| R1 | The new environment, in a new tenant, reports Succeeded | Time, new tenant ID |
| R2 | Provisioning finishes and the readiness check reports every component Ready | Time, readiness report |
| R3 | `Export-EnvironmentFingerprint.ps1` and `Compare-ConsistencyReports.ps1` against a golden environment show no difference | Time, `criterion-03` report |
| R4 | `Test-SeedData.ps1` passes | `criterion-04` report |

Pass: R2 minus R0 is 60 minutes or less, the tenant ID differs from the old one, and R3 and R4 pass. Note: the API Management Developer tier takes 30 to 40 minutes to create, and a brand-new tenant can't have a working sensitivity label (up to 24 hours) or Purview pay-as-you-go (hours) within the hour, so a reset hands out a pre-prepared environment in a new tenant; record which path was used.

### Criterion 13: 25 concurrent participants

1. The day before, on one environment alone, run `.\Test-GroundedRetrieval.ps1 -Repeat 2` and note the median answer time from its report (the baseline).
1. On event conditions, with 25 prepared environments, start `.\Test-GroundedRetrieval.ps1 -EvidencePath <shared folder>` on all 25 lab VMs within the same minute (25 testers, or a scheduled task on each VM).
1. While it runs, run the readiness check on each VM.
1. Run `.\Measure-ConcurrentRun.ps1 -Path <shared folder> -BaselineMedianSeconds <baseline> -ExpectedEnvironments 25`.

Pass: 25 environments reported, every question passed in every environment, the median answer time is within 1.5 times the baseline, and no check reports an unrecovered HTTP 429 or 5xx. Each environment has its own subscription and quota, so a failure points at shared regional capacity; record the region and time.

### Criterion 14: recovery from a spare within 15 minutes

| Step | Action | Record |
|---|---|---|
| S0 | A participant reports an unusable environment (simulate by stopping the test participant's MCP Container App) | Time |
| S1 | Support confirms the failure and assigns a spare whose readiness check and fingerprint were taken that day | Time, spare Deployment ID |
| S2 | The participant has the spare's credentials and is signed in on its lab VM | Time |
| S3 | The participant resumes the current exercise (the readiness check shows Ready) | Time |

Pass: S3 minus S0 is 15 minutes or less, and the spare's fingerprint matched the golden one.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `The agent asked for OAuth consent for a Service Desk connection` | The user hasn't consented to the connection in this project | Give consent once in the playground (Before you start), then run the test again |
| `The signed-in user may not use the agent (HTTP 403)` for the Tier 1 Technician | The account holds Foundry Agent Consumer only | Use the playground and `-Tier1CorrelationId` and `-SeniorCorrelationId`; record the result for the design pack |
| `Signed in as ..., but the test needs ...` | The browser picked another account | Run the test again and choose the account named in the message |
| `The agent has the Azure AI Search tool: FAIL` | Exercise 1 Task 2 hasn't been done in the test environment | Run `C:\LabFiles\tools\New-KnowledgeIndex.ps1`, then add the tool in the portal or run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions` |
| A question fails with `named in the text but not cited` | The agent named the source without a citation annotation | Check the agent's instructions ask for citations (the grounded instructions do), then run again |
| `no log line within 12 minutes` | Container Apps console logs are late, or the environment's diagnostic setting is missing | Check `ContainerAppConsoleLogs` in `log-msp-<DID>`; a new diagnostic setting can take up to 90 minutes to deliver data |
| `Dataverse audit could not be read with this account` | The Senior Technician's role lacks the View Audit Summary privilege | Use a supplier account, or ask the setup author to add the privilege |
| A hop is `Not found yet` in criterion 11 | Agent traces take 2 to 5 minutes, logs a few minutes | Run again later, or raise `-WaitMinutes` |
| `Key Vault audit shows the MCP server's identity reading ...: FAIL` | The server hasn't restarted within `-AuditDays`, or the vault's audit logs go to another table | Raise `-AuditDays`, or restart the revision and wait 10 minutes; the query reads both `AZKVAuditLogs` and `AzureDiagnostics` |

## Phase checklist

The acceptance run is complete when:

- [ ] Criteria 2 to 11 each have a passing `criterion-NN` report from the test environment
- [ ] Criterion 1 has the timed table with three participants at 5 minutes or less
- [ ] Criteria 12 and 14 have their timed checklists, with the readiness reports and fingerprints
- [ ] Criterion 13 has the 25 reports and a passing `criterion-13` report
- [ ] The manual checks of criteria 6 and 10 have their screenshots and records
- [ ] The evidence folder is archived with the build's commit and the seed manifest's data version (3.0)

---

**Next:** Phase 6, deliver the session: [README.md](../../README.md#delivery-path).
