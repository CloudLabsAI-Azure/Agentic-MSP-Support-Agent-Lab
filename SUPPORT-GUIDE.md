# Pilot and Workshop Support Guide: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phases 5 and 6 of 8, run the pilot and support the workshop.** The pilot proves that a participant can complete the whole lab in its 4-hour window and produces the screenshots and task GIFs; the workshop day is run by CloudLabs support, because the lab has no instructor. Before you start, phases 1 to 4 must be complete: the agenda is agreed, the template is published, the environments are prepared and the validation steps are registered. Start of the path: [README.md](README.md#delivery-path).

**Who:** Phase 5, the lab author and a CloudLabs engineer; phase 6, CloudLabs support, with the delivery manager on escalation. **Time:** phase 5, one working day for the walkthrough after the pilot environment has been provisioned for at least 24 hours; phase 6, the 4-hour window plus 30 minutes before it.

## How this lab is delivered

- Every participant has a dedicated environment: a Microsoft Entra tenant with an Azure subscription, built from Golden Environment v1.0. Nobody shares a tenant, so one participant's mistake never affects another.
- There is no instructor and there are no demonstrations. Participants follow the guide, check their work against the **Expected results** under every task, and contact CloudLabs support by live chat or email.
- The lab is safe by default. Participants extend and test controls that already work; no exercise asks them to fix a security exposure.
- The window is 4 hours with no scheduled breaks: 10 minutes to sign in and check readiness, 220 minutes of exercises, 10 minutes to close (see [AGENDA.md](AGENDA.md)). The requester's reviewers then have 24 hours with the participants' lab access, and the platform deletes the environment.

## Phase 5: Run the pilot

The pilot validates that a representative participant completes the full lab flow within 4 hours. Run it on an environment deployed from the published template, never on a hand-built one.

1. **Deploy the pilot environment (CloudLabs engineer).** Deploy one environment from the template at least 24 hours before the walkthrough, because sensitivity labels can take up to 24 hours to apply. Enable Purview pay-as-you-go in its tenant as [setup/tenant/PURVIEW-RUNBOOK.md](setup/tenant/PURVIEW-RUNBOOK.md) describes. Success: the provisioning log reports **Succeeded** for every step and the readiness check ends with "Every component is ready. You can start Exercise 1."
2. **Run the acceptance tests (CloudLabs engineer).** Run the scripts in `tests/acceptance/` against the pilot environment. They cover the acceptance criteria that can be automated: seeded data, grounded retrieval on the scripted questions, the read and write flow, redeploy and rollback, user authorization, secret handling, data protection and the correlated audit trail. Success: every test reports a pass; record any failure in [BUILD-NOTES.md](BUILD-NOTES.md#pilot-log).
3. **Walk every exercise as a participant (lab author).** Sign in as the lab user exactly as the guide says, in a browser sized like the lab VM, and follow every step in order without shortcuts. Time each task against the minutes in the guide. Success: the whole lab fits in 220 minutes, and every expected result matches what you see.
4. **Capture the screenshots (lab author).** Capture one screenshot for every `SCREENSHOT PENDING` marker listed in [SCREENSHOT-TODO.md](SCREENSHOT-TODO.md), at native resolution, with the CloudLabs boxes and the border, and blur anything that is not a lab account. Success: no marker is left in the guide.
5. **Build one GIF per task (lab author).** Build each task's walkthrough GIF from the same full-resolution frames with `tools/screenshots/Build-StepGif.py`, and keep the GIF variant on its own branch (for example `toc-v3-gif`) with its `masterdoc.json` pointing at that branch, until the requester picks a variant. Success: every one of the 27 tasks has a GIF after its intro sentence.
6. **Test the second identity (lab author).** Sign in as the Tier 1 Technician as Exercise 5 Task 4 describes and confirm that Dataverse denies its priority change while the same request as the Senior Technician succeeds. Success: both attempts appear in the tool invocation log with their correlation IDs.
7. **Settle the open questions (lab author and CloudLabs engineer).** Work through every item in [BUILD-NOTES.md](BUILD-NOTES.md#open-questions-to-settle-in-the-pilot), apply the documented fallback where a product behaves differently from the guide, and record the decision and its date.
8. **Run each validation step once (CloudLabs engineer).** Trigger every registered validation step against the pilot environment after the matching task. Success: all 14 pass on a completed environment and fail with their helpful message on a fresh spare.
9. **Rehearse recovery (CloudLabs engineer).** Replace the pilot environment with a spare once and reset one environment once, as [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md) describes, and time both. Success: the swap takes no more than 15 minutes and the reset no more than 60 minutes, ending with a passing readiness check.
10. **Hand over the customer test environment (CloudLabs engineer and delivery lead).** For Milestone 1, give the requester one environment deployed from the published template, with the Lab Guide, for 10 business days from delivery, and longer only while a retest runs. Set its CloudLabs duration to cover the whole period, and ask CloudLabs for sign-in credentials that stay valid as long (a Temporary Access Pass lasts at most 30 days). Send it with the [design pack](DESIGN-PACK.md), [SOW-COVERAGE.md](SOW-COVERAGE.md), the consistency report and the acceptance test evidence of step 2. Delete it when the period ends; it is not kept. Pilot environments, like workshop environments, stay available for 24 hours from the lab start time and are then deleted. Success: the requester confirms access, and the deletion date is recorded.

## Phase 6: Support the workshop

### Before the window (from 30 minutes before the start)

1. Confirm that every participant environment and both spares passed the readiness check after provisioning, and that the consistency report was shared with the requester.
2. Keep the roster that maps each participant to an environment, and the two spares, unassigned and ready.
3. Open the support channels: live chat (first response within 5 minutes) and email (first response within 60 minutes). The delivery manager is the escalation point, within 30 minutes. Note the requester's named contact for the workshop.

### During the window

Ask the participant which exercise, task and step they are on, and what the readiness check or the error message says. Most questions are answered by the **Troubleshooting** section of the task they are on.

| Symptom | Likely cause | Fix |
|---|---|---|
| The readiness check shows a component that is not ready | A transient failure, or a provisioning step that failed | Ask the participant to run the check again. If the same component still fails, replace the environment with a spare (next section) and extend the participant's time by the time lost |
| The Azure portal asks for a code or for multifactor authentication | The lab user signs in with a Temporary Access Pass | The participant pastes the value shown on the **Environment** tab into the password field, whether the page says **Enter Temporary Access Pass** or **Enter password** |
| The agent playground shows **Open Consent** before a Service Desk tool runs | OAuth identity passthrough asks each user once per connection, and there are two connections (read and write) | The participant selects **Open Consent**, signs in with the same lab account and accepts, then sends the prompt again |
| A write tool call never runs | The participant has not answered the approval request in the chat | The participant reviews the tool name and arguments and selects **Approve**, or declines; every call needs its own decision |
| The search index has fewer documents than the guide expects | The indexer is still running | Wait one minute and check the index again; if it stays short, the participant runs the indexing command again as the guide's Troubleshooting says |
| Agent traces do not appear yet | Traces take 2 to 5 minutes to arrive | Wait, then refresh |
| The Microsoft Purview event does not appear yet | Purview activity can take 60 to 90 minutes | The participant records the MCP server log entry for the withheld content, which is immediate, as the guide's Note says |
| The MCP server redeploy fails or the new revision is unhealthy | A build error in the participant's change | The participant reads the build output, fixes the change and deploys again, or rolls back to the previous revision as Exercise 3 Task 4 shows |
| A participant is close to the token allowance | Repeated long prompts | Tell the delivery manager, who notifies the requester when a participant reaches 80 percent of the allowance, before any overage |

### Watch the token allowance

Each environment may use up to 4 million input and 0.4 million output tokens per workshop. Check every environment twice during the window, after about 2 hours 35 minutes (the end of Exercise 4) and after about 3 hours 35 minutes, and once more before the review window starts. Run this as an owner or reader of the environment's subscription, as for the remote readiness check in [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md#t-minus-24-hours-readiness-and-consistency); it reads the Azure Monitor metrics **Input Tokens** and **Output Tokens** of the Foundry resource, for all its deployments together:

```powershell
$id = az cognitiveservices account show --resource-group <resource group> --name aif-msp-<DeploymentID> --query id --output tsv
$m = az monitor metrics list --resource $id --metrics InputTokens OutputTokens --aggregation Total --interval 1h `
    --start-time <the deployment time, in UTC, for example 2026-12-02T09:00:00Z> | ConvertFrom-Json
$m.value | ForEach-Object { '{0}: {1:N0}' -f $_.name.value, ($_.timeseries.data.total | Where-Object { $_ } | Measure-Object -Sum).Sum }
```

At 3,200,000 input tokens or 320,000 output tokens (80 percent), tell the delivery manager at once. The delivery manager notifies the requester before any overage applies, and records the time for the [workshop report](#workshop-report). No overage is charged without the requester's written approval.

### Replace a failed environment with a spare

When an environment cannot be fixed within a few minutes, replace it within 15 minutes of the report: assign a spare that passed the readiness check, send the participant its access details, and record the time lost so the participant's lab time is extended by it. Work in the failed environment is not kept. Follow the spare and reset procedures in [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md); a reset creates a new environment in a new tenant and completes within 60 minutes.

### At the end of the window

1. Participant access ends at 4 hours, plus any extension owed for supplier-caused delays.
2. The requester's reviewers keep 24 hours of access through the participants' lab access to judge the submitted work. Point them to the two places each participant leaves evidence: **Lab notes.txt** on the lab VM desktop, which ends with the business case, and `C:\LabFiles\evidence`, which holds the exported audit trails (a JSON and a Markdown file per traced action). Nothing is deleted during the review window.
3. Reviewers can also export logs and audit records from any environment until the review window ends. On the lab VM, `C:\LabFiles\tools\Get-ActionTrail.ps1 <correlation ID> -LookbackHours 48 -OutFile C:\LabFiles\evidence\<name>` writes the full trail of one action, with its Dataverse audit record and Agent Action row, as JSON and Markdown; `Get-ActionTrail.ps1 -ConversationId <ID>` lists every approval and tool call of one conversation, declined ones included. In the Azure portal, a query on the workspace `log-msp-<DeploymentID>` exports to CSV from the **Share** menu of the **Logs** page.
4. Record every incident, swap and extension for the close-out in phase 7.

### Workshop report

The delivery lead sends the requester a workshop report within one business day after the review window ends. It is the completion and participant count evidence of Milestone 2, it records the Golden Environment version used, and it lists every replacement (acceptance criterion 14).

| Section | Content | Source |
|---|---|---|
| Workshop | Number, date, lab start and end time, the requester's named contact | Agenda and roster |
| Golden Environment | The version and the consistency fingerprint of every environment and spare | The consistency reports |
| Participants | Agreed, assigned, signed in, completed and partly completed | The roster and the CloudLabs validation results |
| Completion | For each participant, the graded tasks that passed (14 in all) and the last exercise reached. A participant whose 14 graded tasks pass completed the lab | The CloudLabs validation results |
| Replacements and resets | For each one: the time of the report, the spare used, the time the participant resumed, and the time added to their window | The support log |
| Support | Chats and emails with their first-response times, and every escalation | CloudLabs support |
| Token use | Environments that reached 80 percent of the allowance, and when the requester was told | The token checks |
| Incidents | What happened, the cause and the fix | The support log |
| Review window | Its start and end, and the reviewers' confirmation that they finished | The delivery lead |

## Phase checklists

**Phase 5, pilot:**

- [ ] The pilot environment was deployed from the published template and provisioned for at least 24 hours
- [ ] The acceptance tests pass, or each failure is recorded in BUILD-NOTES.md with its fix
- [ ] A participant walkthrough completed every exercise within 220 minutes
- [ ] Every screenshot marker is replaced, and each of the 27 tasks has a GIF on the GIF branch
- [ ] The Tier 1 denial and the Senior success were both observed
- [ ] Every open question in BUILD-NOTES.md has a decision and a date
- [ ] All 14 validation steps pass on a completed environment
- [ ] A spare swap took no more than 15 minutes and a reset no more than 60 minutes
- [ ] The requester has the customer test environment for 10 business days, with the design pack, the coverage file, the consistency report and the acceptance evidence, and its deletion date is recorded

**Phase 6, workshop:**

- [ ] Every environment and spare passed the readiness check at least 30 minutes before the start
- [ ] Live chat and email were staffed for the whole window
- [ ] Every environment's token use was checked twice during the window, and every environment at 80 percent was reported to the requester
- [ ] Every swap and extension is recorded with its time
- [ ] The reviewers' 24-hour access was confirmed with the requester
- [ ] The workshop report was sent within one business day after the review window

---

**Next:** Phase 7, close the event: [setup/tenant/RUNBOOK.md](setup/tenant/RUNBOOK.md).
