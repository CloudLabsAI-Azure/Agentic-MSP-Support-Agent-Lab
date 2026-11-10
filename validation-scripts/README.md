# Register the Validation Steps

> **Delivery path: Phase 4 of 8, register the validation steps.** This phase gives the CloudLabs template its 14 automatic grading steps, confirms that the CloudLabs validation service principal can read what the steps check (read-only), and puts each step's GUID into the guide. Before you start, Phase 2 must be complete: the template exists and one test deployment succeeded ([setup/README.md](../setup/README.md)). Start of the path: [README.md](../README.md#delivery-path).

**Who:** CloudLabs engineer, with the setup author for Step 2. **Time:** about 1 hour, plus the test in the Phase 5 pilot.

## What is graded

Fourteen tasks are graded; every other task is checked by the participant with its **Expected results** checklist (Exercise 1 Tasks 1, 3, 4 and 5; Exercise 2 Tasks 2 to 4; Exercise 3 Tasks 1 and 3; Exercise 5 Tasks 1 and 2; Exercise 6 Task 3; Exercise 7 Task 2). The scores add up to 100.

| Exercise and task | Script | Step name in CloudLabs | Score | Passes when |
|---|---|---|---|---|
| Exercise 1, Task 2: Connect the Agent to the Knowledge Base | `ex1-task2-knowledge-index.ps1` | `Exercise 1 Task 2: Knowledge index built and loaded` | 10 | Index `servicedesk-knowledge` exists on `srch-msp-<DID>`, holds 753 documents (the seed manifest's `searchable_documents.total`), and the last run of `servicedesk-export-indexer` succeeded |
| Exercise 2, Task 1: Identify Similar Historical Incidents | `ex2-task1-similar-incidents.ps1` | `Exercise 2 Task 1: New incident read through the tools` | 5 | A successful `get_ticket` or `get_similar_tickets` call on the first new incident, TCK-10561, by the Senior Technician |
| Exercise 3, Task 2: Call an Existing Read Tool | `ex3-task2-read-tool.ps1` | `Exercise 3 Task 2: Read tool called through the read gateway` | 5 | A successful read tool call through the read gateway with the Senior Technician's token (diagnostics API calls don't count) |
| Exercise 3, Task 4: Redeploy Your Copy of the MCP Server | `ex3-task4-redeploy.ps1` | `Exercise 3 Task 4: MCP server redeployed` | 10 | `ca-mcp-<DID>` serves a ready revision newer than the provisioning revision, from an `mcp-server` image whose tag isn't `3.0.0`, and the server reports a version other than `3.0.0` |
| Exercise 4, Task 1: Call a Write Tool with Approval | `ex4-task1-write-approval.ps1` | `Exercise 4 Task 1: Write approved and applied` | 5 | A successful `update_ticket_status` or `update_ticket_priority` call by the Senior Technician (a rejected call never reaches the server) |
| Exercise 4, Task 2: Separate a Public Reply from an Internal Note | `ex4-task2-reply-and-note.ps1` | `Exercise 4 Task 2: Public reply and internal note on one ticket` | 5 | Successful `add_public_reply` and `add_internal_note` calls on the same ticket, through the agent |
| Exercise 4, Task 3: Chain Grounding into Action | `ex4-task3-grounded-action.ps1` | `Exercise 4 Task 3: Grounded write on the new incident` | 5 | A successful write tool call on TCK-10561, through the agent |
| Exercise 4, Task 4: Tighten a Tool Boundary | `ex4-task4-tool-boundary.ps1` | `Exercise 4 Task 4: Tool boundary tightened` | 5 | A `get_open_tickets` call with a limit above 20 rejected with `INVALID_ARGUMENT` by an image other than `3.0.0`; when the log names the maximum, it is 20 |
| Exercise 4, Task 5: Design and Add a Scoped Tool | `ex4-task5-scoped-tool.ps1` | `Exercise 4 Task 5: Scoped tool added and called` | 10 | A successful call, through the agent, to a tool that is not in the baseline catalog (for example `escalate_ticket`) |
| Exercise 5, Task 3: Enforce a Least-Privilege Boundary | `ex5-task3-least-privilege.ps1` | `Exercise 5 Task 3: Least-privilege boundary enforced by Dataverse` | 10 | A write by the Senior Technician with the authorization result `Denied by Dataverse` (the narrowed role, for example on TCK-10511) |
| Exercise 5, Task 4: Apply User-Level Authorization | `ex5-task4-user-authorization.ps1` | `Exercise 5 Task 4: Tier 1 denied, Senior allowed` | 10 | On the same ticket (TCK-10543 in the guide), a denied `update_ticket_priority` by the Tier 1 Technician and a successful one by the Senior Technician |
| Exercise 6, Task 1: Restrict What the Agent Can Return | `ex6-task1-restrict-return.ps1` | `Exercise 6 Task 1: Email column withheld` | 5 | A successful `get_customer_contacts` call whose result withholds the email column (`emailaddress1`); the phone columns are withheld from the start and don't count |
| Exercise 6, Task 2: Apply Microsoft Purview Data Protection | `ex6-task2-purview.ps1` | `Exercise 6 Task 2: Content withheld by policy or label` | 5 | A read through the agent whose result was withheld by policy (`withheld_by_policy`) or by label (`CONTENT_BLOCKED_BY_LABEL`) |
| Exercise 7, Task 1: Run the End-to-End Scenario | `ex7-task1-end-to-end.ps1` | `Exercise 7 Task 1: End-to-end scenario completed` | 10 | On the second new incident, TCK-10562: a successful category or priority change, `assign_ticket` and `add_public_reply` |

The step names match the TODO comments next to the validation tags in `Instructions/exercise-1.md` to `exercise-7.md`, which still hold the placeholder `REPLACE-WITH-VALIDATION-GUID`.

### How the steps check

- **No Dataverse permission.** Twelve steps read the MCP server's tool invocation log instead of Dataverse: one JSON line per tool call in the Log Analytics table `ContainerAppConsoleLogs` of `log-msp-<DID>`, with the correlation ID, user, agent ID, tool, argument summary, authorization result, backend calls, outcome and duration. They look back 48 hours.
- **Who did it.** "By the Senior Technician" means the line's user object ID equals `GET-AZUSER-OBJECTID` (or its user name equals `GET-AZUSER-UPN`). The Tier 1 Technician is the other user (`tier1.technician@<tenant domain>`). Calls through the diagnostics API carry no user and never count.
- **Values from the seed.** The steps read the resource group tags that provisioning writes from the seed manifest, and fall back to the values in the scripts (data version 3.0):

  | Tag on the participant's resource group | Value | Used by |
  |---|---|---|
  | `lab-searchable-documents` | `753` | Exercise 1 Task 2 |
  | `lab-new-incident-1` | `TCK-10561` | Exercise 2 Task 1, Exercise 4 Task 3 |
  | `lab-new-incident-2` | `TCK-10562` | Exercise 7 Task 1 |
  | `lab-mcp-release` | `3.0.0` | Exercise 3 Task 4, Exercise 4 Task 4 |

  If the seed or the MCP server release changes, update the tags in provisioning and the constants at the top of the scripts together (`$ExpectedDocuments`, `$FirstNewIncident`, `$SecondNewIncident`, `$ReleaseVersion`), and keep `$ReadTools` and `$WriteTools` in the shared part of the log-based scripts equal to the release's tool catalog (Exercise 4 Task 5 grades any tool outside it).
- **Latency.** Console logs reach Log Analytics within minutes. Each step tries three times, 60 seconds apart, so one **Validate** can take up to three minutes; its message says when to try again.

## What the validation service principal needs

The scripts carry no sign-in code: CloudLabs adds the Azure sign-in of its validation service principal when the steps are deployed (**Run As** **System**). Everything they do is a read.

**Same tenant.** Each participant's subscription belongs to the participant's own lab tenant, and the validation service principal signs in to that subscription's tenant. The steps read only that participant's resources.

| Access | Used by | Required | Why |
|---|---|---|---|
| Reader (or the broader role CloudLabs holds) on the participant's resource group | All steps | Yes | Finds `srch-msp-<DID>`, `ca-mcp-<DID>` and `log-msp-<DID>`, reads the Container App and its revisions, reads the resource group tags |
| Query access to `log-msp-<DID>` (`Microsoft.OperationalInsights/workspaces/query/read`, part of Reader and above) | Twelve log-based steps, and Exercise 3 Task 4 as a fallback | Yes | Queries `ContainerAppConsoleLogs` |
| Read of index statistics and indexer status on `srch-msp-<DID>` (role-based access; part of Reader and above) | Exercise 1 Task 2 | Yes | `GET /indexes/servicedesk-knowledge/stats` and `GET /indexers/servicedesk-export-indexer/status` |
| **Search Index Data Reader** on `srch-msp-<DID>` | Exercise 1 Task 2 | Fallback only | `GET /indexes/servicedesk-knowledge/docs/$count`, used only when the statistics call is refused. The search service accepts role-based access only, so an API key can't replace it |
| `listAdminKeys` on `srch-msp-<DID>` (Contributor or Owner) | Exercise 1 Task 2 | Optional | Tried only if the service also accepts API keys |

**Never granted: any write permission, and no Microsoft Graph or Dataverse permission.** A Dataverse role would let the checks read tickets directly, but the MCP server's log already records every decision with its user, so the validation service stays out of the participant's data.

**Keep participant accounts out of pre-event tests.** The log-based steps count any call from the last 48 hours. Run readiness and smoke tests through the diagnostics API (`Invoke-McpTool.ps1`, no signed-in user) or with a supplier account, never as the Senior Technician or the Tier 1 Technician, or steps will pass before the participant has done anything.

## Step 1: Get the validation service principal

Role: CloudLabs engineer.

1. Ask CloudLabs support for the **application (client) ID** of the service principal that runs **Run As** **System** validation steps for this template's subscriptions.
1. On one test deployment, check that it exists in the lab tenant. The command prints its display name:

   ```powershell
   az login --tenant <lab-tenant-id>
   az ad sp show --id <cloudlabs-validation-app-id> --query displayName --output tsv
   ```

1. Check its Azure roles. **Reader**, **Contributor** or **Owner** at the subscription (or on the lab resource group) is enough for every row above except **Search Index Data Reader**:

   ```powershell
   az role assignment list --assignee <cloudlabs-validation-app-id> --all --query "[].{Role:roleDefinitionName, Scope:scope}" --output table
   ```

## Step 2: Confirm the seed tags and the search data access

Role: setup author (provisioning), with the CloudLabs engineer.

1. On the test deployment, list the tags of the participant's resource group. The four `lab-*` tags in the table above must be present with those values:

   ```powershell
   az group show --name <resource-group> --query tags --output json
   ```

   If they are missing, the steps still work from the constants in the scripts; ask the setup author to add the tags so a seed change reaches validation without editing the scripts.
1. Check whether the validation service principal holds **Search Index Data Reader** on the search service. It needs it only when the index statistics call is refused (Troubleshooting, first row):

   ```powershell
   az role assignment list --assignee <cloudlabs-validation-app-id> --scope <search-service-resource-id> --query "[].roleDefinitionName" --output tsv
   ```

   If the pilot shows it is needed, the setup author adds that assignment to the template for the deploying principal.

## Step 3: Register the steps on the template

Role: CloudLabs engineer, in the CloudLabs admin portal.

1. Open the template, select **Edit**, open the **Course Details** tab, and select **Manage**.
1. For each row, add a **Module** with the exercise name, under it a **Labs/Lectures/Quizzes** item of **Type** **Lab** with the task name, and under that one **Step**:

   | Module | Lab (Type: Lab) | Step name | Script |
   |---|---|---|---|
   | `Exercise 1: Environment Readiness and Grounding the Agent` | `Task 2: Connect the Agent to the Knowledge Base` | `Exercise 1 Task 2: Knowledge index built and loaded` | `ex1-task2-knowledge-index.ps1` |
   | `Exercise 2: Ticket and Incident Intelligence` | `Task 1: Identify Similar Historical Incidents` | `Exercise 2 Task 1: New incident read through the tools` | `ex2-task1-similar-incidents.ps1` |
   | `Exercise 3: Using the MCP Read Tools` | `Task 2: Call an Existing Read Tool` | `Exercise 3 Task 2: Read tool called through the read gateway` | `ex3-task2-read-tool.ps1` |
   | `Exercise 3: Using the MCP Read Tools` | `Task 4: Redeploy Your Copy of the MCP Server` | `Exercise 3 Task 4: MCP server redeployed` | `ex3-task4-redeploy.ps1` |
   | `Exercise 4: Using the MCP Action Tools` | `Task 1: Call a Write Tool with Approval` | `Exercise 4 Task 1: Write approved and applied` | `ex4-task1-write-approval.ps1` |
   | `Exercise 4: Using the MCP Action Tools` | `Task 2: Separate a Public Reply from an Internal Note` | `Exercise 4 Task 2: Public reply and internal note on one ticket` | `ex4-task2-reply-and-note.ps1` |
   | `Exercise 4: Using the MCP Action Tools` | `Task 3: Chain Grounding into Action` | `Exercise 4 Task 3: Grounded write on the new incident` | `ex4-task3-grounded-action.ps1` |
   | `Exercise 4: Using the MCP Action Tools` | `Task 4: Tighten a Tool Boundary` | `Exercise 4 Task 4: Tool boundary tightened` | `ex4-task4-tool-boundary.ps1` |
   | `Exercise 4: Using the MCP Action Tools` | `Task 5: Design and Add a Scoped Tool` | `Exercise 4 Task 5: Scoped tool added and called` | `ex4-task5-scoped-tool.ps1` |
   | `Exercise 5: Identity, Secrets and Authorization` | `Task 3: Enforce a Least-Privilege Boundary` | `Exercise 5 Task 3: Least-privilege boundary enforced by Dataverse` | `ex5-task3-least-privilege.ps1` |
   | `Exercise 5: Identity, Secrets and Authorization` | `Task 4: Apply User-Level Authorization` | `Exercise 5 Task 4: Tier 1 denied, Senior allowed` | `ex5-task4-user-authorization.ps1` |
   | `Exercise 6: Data Protection and Auditability` | `Task 1: Restrict What the Agent Can Return` | `Exercise 6 Task 1: Email column withheld` | `ex6-task1-restrict-return.ps1` |
   | `Exercise 6: Data Protection and Auditability` | `Task 2: Apply Microsoft Purview Data Protection` | `Exercise 6 Task 2: Content withheld by policy or label` | `ex6-task2-purview.ps1` |
   | `Exercise 7: End-to-End Scenario and Business Case` | `Task 1: Run the End-to-End Scenario` | `Exercise 7 Task 1: End-to-end scenario completed` | `ex7-task1-end-to-end.ps1` |

1. Fill in each step:

   | Field | Exercise 1 Task 2 and Exercise 3 Task 4 | The other twelve steps |
   |---|---|---|
   | Validation Type | Custom | Custom |
   | Score | From the table in [What is graded](#what-is-graded) | From the table in [What is graded](#what-is-graded) |
   | Script Type | PowerShellV2 | PowerShellV2 |
   | Script | The whole script file | The whole script file |
   | Parameters | `GET-DEPLOYMENT-ID` to `DeploymentID` | `GET-DEPLOYMENT-ID` to `DeploymentID`; `GET-AZUSER-OBJECTID` to `AzureUserObjectId`; `GET-AZUSER-UPN` to `AzureUserName` |
   | Run As | System | System |

   Paste each script from this folder at the commit you publish, unchanged. Do not add sign-in code: CloudLabs adds it. The twelve log-based scripts share an identical block between `# ==== Shared` and `# ==== End of the shared part`; if you change it, change it in all twelve.
1. On the **Course Details** tab, select **DEPLOY ALL STEPS**. Mapping takes 5 to 7 minutes, and the CloudLabs team completes the backend steps.
1. Make sure **Enable Lab Validation** is on in the template settings, so participants get the **Lab Validation** tab.

## Step 4: Put the step GUIDs into the guide

Role: CloudLabs engineer or lab author.

1. After the deployment, open each step in **Course Details** and copy the GUID that CloudLabs minted for it.
1. In `Instructions/exercise-1.md` to `exercise-7.md`, at the end of each graded task listed above, replace `REPLACE-WITH-VALIDATION-GUID` in the validation tag with the step's GUID, and delete the TODO comment line under it. For example:

   ```markdown
   <validation step="8ef6e340-178f-4e34-b921-3bfae73ff76a" />
   ```

1. Check that no placeholder is left; the command must print nothing:

   ```powershell
   Select-String -Path .\Instructions\*.md -Pattern 'REPLACE-WITH-VALIDATION-GUID', 'TODO: replace with the GUID'
   ```

1. Commit the change through the repository's normal review, so it reaches the branch that `masterdoc.json` reads.

## Step 5: Test the steps in the pilot

Role: CloudLabs engineer, during Phase 5, on a pilot deployment, signed in as the participant accounts.

1. **Negative test first.** Before doing any task, select **Validate** on each step in the **Lab Validation** tab. Each must report **Failed** with a message that says what to do, for example `No get_ticket or get_similar_tickets call on the new incident TCK-10561 has been logged yet. Ask the agent to find incidents similar to TCK-10561, as Task 1 shows.`
1. **Positive test.** Do each task as the guide says, wait about five minutes for the logs, then validate. Each must report **Succeeded**, and the message names the evidence (tool, ticket, user, time and correlation ID). Validate Exercise 3 Task 4 before any rollback: a rollback to the release image makes that step fail again, which is correct.
1. In the CloudLabs admin portal, open the **Per User Validation Report** and check that the scores add up to 100.
1. Run the end-to-end verification: **Template Audit** > **+ADD** > Event Type **Lab Test** > **End to End verification testing**, and select the ODL and the Deployment ID. Every item must reach **Successful**.
1. Record each step's time to **Succeeded** after its task in `BUILD-NOTES.md`, so support knows how long to tell a participant to wait.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Validation could not read the search service srch-msp-<DID> (HTTP 403 ...)` | The service principal can't read index statistics through role-based access, and the service refuses API keys | Step 2, item 2: give the validation service principal **Search Index Data Reader** on the search service (provisioning) |
| `The index servicedesk-knowledge holds N documents; the seed manifest says 753.` | The indexer stopped early, or the participant changed the export | The participant runs `New-KnowledgeIndex.ps1` again (it resets and reruns the indexer and explains any error) |
| Every log-based step says nothing has been logged, although the participant did the task | Console logs haven't reached the workspace yet, or the Container Apps environment doesn't send them to `log-msp-<DID>` | Wait five minutes and validate again. If it persists, check the environment's diagnostic setting (`ContainerAppConsoleLogs` to `log-msp-<DID>`); a new setting can take up to 90 minutes to deliver its first data |
| Steps pass before the participant did the task | Someone tested with the Senior or Tier 1 Technician within the last 48 hours | Use the diagnostics API or a supplier account for smoke tests; use **Update Validation Result** for the affected participant |
| `... was read by <user>, not by you.` | The participant signed in to Foundry with another account | Sign in with the lab account from the **Environment** tab |
| `Only read tool calls through the diagnostics API (no signed-in user) have been logged.` | The participant used `Invoke-McpTool.ps1` (diagnostics API) instead of the agent | Follow the guide's step that calls the tool through the agent |
| `The Container App still runs the release image (tag 3.0.0).` | The build or the deployment didn't run, or the participant rolled back | Deploy again with a new tag; validate before rolling back |
| `Revision ... runs the image tag ..., but its version could not be read yet` | `/health` accepts only the gateway and the startup log line hasn't arrived | Wait five minutes and validate again |
| `get_open_tickets accepted limit ... so the maximum is not 20 yet` | The change wasn't deployed, or the limit is enforced elsewhere | Redeploy with the maximum of 20 and call it again |
| `update_ticket_priority succeeded for tier1.technician@...` | The Tier 1 Technician holds a write role | Stop: this breaks least privilege. Check the Dataverse roles provisioning assigned and contact the setup author |
| A step reports success with the wrong user or ticket | The MCP server's log line changed its field names | Compare one log line with the fields under [How the steps check](#how-the-steps-check) and adjust the shared part of the scripts |
| The **Validate** button is missing in the guide | The GUID was not put into the guide, or **Enable Lab Validation** is off | Step 4; Step 3, last item |

## Phase checklist

Phase 4 is complete when:

- [ ] The validation service principal exists in the lab tenant and holds a read role on the lab resource group, and no write permission was added for validation
- [ ] The four `lab-*` tags are on the test deployment's resource group with the values above (or the constants in the scripts match the seed manifest)
- [ ] The 14 steps are registered with the names, scores (total 100), parameters and **Run As** **System** above, and **DEPLOY ALL STEPS** finished
- [ ] **Enable Lab Validation** is on
- [ ] The GUIDs are in the guide and no `REPLACE-WITH-VALIDATION-GUID` is left
- [ ] In the pilot, each step failed before its task and succeeded after it, and the Per User Validation Report shows 100

---

**Next:** Phase 5, run the pilot, including the acceptance tests in [tests/acceptance/README.md](../tests/acceptance/README.md): [SUPPORT-GUIDE.md](../SUPPORT-GUIDE.md#phase-5-run-the-pilot).
