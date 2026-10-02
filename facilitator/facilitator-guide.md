# Facilitator Guide: Agentic MSP Support Agent Guided Lab

This guide is for the people running the session. It is not listed in `masterdoc.json`, and it is not copied to the lab VMs, because it contains the answer keys.

## 1. Before the event

### One week before

- [ ] Run `setup/tenant/Initialize-LabTenant.ps1` once in the lab tenant (see `setup/README.md`). It creates the **Relecloud Service Desk MCP Gateway** app registration and prints its application ID for `deploy-01.parameters.json`.
- [ ] Confirm the Power Platform tenant settings: **Developer environment assignments** allows the team accounts to create developer environments, and internal (self-service) consent plans are allowed.
- [ ] Confirm that CloudLabs assigns **Microsoft Power Apps for Developer** (`POWERAPPS_DEV`) to every team account before provisioning starts.
- [ ] Confirm sign-in. Azure requires multifactor authentication for Azure portal sign-in and for every Azure Resource Manager change, with no exception for lab tenants. Each team account needs a multi-use **Temporary Access Pass** that lasts from launch to the end of the session and is shown on the **Environment** tab. Provisioning also signs the team account in to Power Platform and Dataverse without a browser; confirm with CloudLabs that this works in the lab tenant (see `setup/README.md`, section 1).
- [ ] Confirm the Global Standard quota in Sweden Central: each team deploys 30,000 TPM of `gpt-5.4-mini` and 30,000 TPM of `text-embedding-3-small`. For 25 teams that is 750,000 TPM of each, against a Tier 1 quota of 1,000,000 TPM per model.
- [ ] Confirm the subscription is not funded by free credits. Azure Container Registry Tasks (`az acr build`) are paused on free-credit subscriptions, which breaks provisioning and Exercises 3 and 4.
- [ ] Confirm that the `msp-labfiles.zip` in the template library was built from the private MCP server repository `CloudLabsAI-Azure/agentic-msp-mcp-server` at tag `v1.0.0` (`setup/README.md`, sections 3 and 4). Lab VMs never contact GitHub, and attendees need no GitHub account.

### The day before, or at least two hours before

- [ ] Launch the team environments at least **two hours** before the session. A new Log Analytics workspace and the Container Apps diagnostic setting can take up to 90 minutes to deliver their first records, and Exercises 3 to 5 read those logs.
- [ ] In the CloudLabs admin portal, check that every deployment reports **Succeeded**. The logon task fails the deployment if any provisioning step, the MCP health check, or the agent identity is missing.
- [ ] Walk one environment through Exercise 1 Task 1 yourself.

### On the morning

- [ ] Optional: re-anchor the seed data so that ticket dates fall in the week of the session (see section 5). Re-anchoring moves every date by whole weeks; the ticket numbers, the SLA figures and every answer key below stay the same.
- [ ] Have the three unseen incidents (section 3, Exercise 2) ready to paste into the session chat.
- [ ] Have the guided fix for Exercise 4 Task 4 ready to share.

## 2. Run of show

| Time | Segment | Facilitator actions |
|---|---|---|
| 00:00 | Arrival (15 min) | Teams sign in to the CloudLabs environment, the Azure portal and the Azure CLI (getting-started page). Make sure every team has signed in with its Temporary Access Pass and has `az login` working before 00:15. |
| 00:15 | Exercise 1 (65 min) | Remind teams to fill in **Lab notes.txt**, and that one person drives the playground at a time: each team's model deployment allows about 30 requests per minute, so on a rate-limit error wait 10 seconds and resend. Watch for index creation errors in Task 2 (section 4). At 00:45 every team should have started `Load-SearchIndex.ps1`; help any team that hasn't. |
| 01:20 | Break (10 min) | |
| 01:30 | Exercise 2 (35 min) | At 01:30, paste one unseen incident per team (rotate A, B, C so neighbours get different ones). Teams that don't get one use Incident D, which is printed in the guide. |
| 02:05 | Exercise 3 (45 min) | The gateway logs take 5 to 15 minutes to arrive; tell teams to continue and come back. Each team runs one redeploy (4 to 7 minutes). |
| 02:50 | Break (10 min) | Teams can start their Exercise 3 redeploy before the break if they are behind. |
| 03:00 | Exercise 4 (50 min) | At about 03:35, share the guided fix for Task 4 in chat. |
| 03:50 | Exercise 5 (45 min) | Task 1 is a 10-minute comparison; keep teams moving into Task 2. |
| 04:35 | Wrap-up (15 min) | Use the discussion prompts in section 6. |
| 04:50 | Close and float (10 min) | Catch-up time; collect feedback. |

## 3. Answer keys

### Exercise 1

**Task 1 expected counts:** 42 open tickets, 473 tickets in total, 1,161 ticket notes, 24 managed customers, 72 contacts, 50 knowledge articles (49 Published, KB0019 Retired), 12 technicians (Marcus Webb, TECH-02, unavailable). `Invoke-McpTool.ps1 -List` shows 12 tools.

**Task 2:** the index has 26 fields and 548 documents (50 + 473 + 24 + 1 SLA snapshot).

**Task 3:**

- Humongous Insurance (CUST-013): Platinum, Fully Managed, 510 seats, 2 sites, Backup Agent 5.2.1, Remote Access 4.2.0, Secure Gateway 10.1.4, Endpoint Agent 7.4.1, account manager Isabel Grant.
- RBA-1043: KB0007. KB0019 is Retired and superseded by KB0007 (via the upgrade article KB0021 for 4.x agents).
- Monthly contract value: not in the data. The agent must say it can't find it.

**Task 4:** KB0031 (Remote Access client 3.8 and 3.9: upgrade the client to 4.2.0, don't touch IKE) versus KB0058 (client 4.x on Secure Gateway firmware 10.1: set the IKE phase 1 lifetime to 28800 seconds, don't reinstall the client). The deciding attribute is the product version. Woodgrove Bank runs 4.2.0 on 10.1.4, so KB0058; Northwind Traders runs 3.9.2 on 9.6.2, so KB0031. Other pairs for fast teams: KB0012 and KB0013 split on SLA tier, KB0044 and KB0045 on contract type (Margie's Travel is Break-Fix, so KB0045; Woodgrove Bank is Fully Managed, so KB0044).

### Exercise 2

**Task 1, unseen incidents.** Paste one of these into the session chat. Don't share them in advance.

Incident A (expected article KB0058, or KB0031 depending on the client version):

```text
From the IT coordinator at a 40-person architecture practice: since your engineers worked on our office firewall on Tuesday night, people working from home keep getting thrown off the company network connection at about the same point in every hour, usually in the middle of a call, and have to sign back in each time. Restarting their laptops hasn't changed anything.
```

Expected matches: the historical KB0058 tickets TCK-10367, TCK-10375 and TCK-10404 (Humongous Insurance), TCK-10369 and TCK-10393 (Proseware Inc), TCK-10371 (Lamna Healthcare), TCK-10397 (Consolidated Messenger) and TCK-10405 (Blue Yonder Airlines). Similarity beyond keywords: the same 60-minute pattern, starting after gateway or firewall firmware work, unaffected by restarts or reinstalls, `RRA-4012` in the client log. A strong answer says the Remote Access client version must be confirmed, because client 3.x points to KB0031 instead (historical KB0031 tickets include TCK-10003 and TCK-10015 at Northwind Traders).

Incident B (expected article KB0007):

```text
This morning the overnight protection job for our main document server came back red. The console says the shadow copy step gave up after ten minutes. Last night was our monthly Windows update window, and the server is still asking to restart.
```

Expected matches: historical KB0007 tickets such as TCK-10007 and TCK-10062 (Humongous Insurance), TCK-10102 (Bellows College, *Snapshot timeout on BCFS02 backup after patching*) and TCK-10104 (Proseware Inc, *Backup tray icon red on PIFS02 since patch night*). Similarity: RBA-1043 snapshot timeout at 600 seconds, the night after patching, pending restart. A strong answer asks for the Backup Agent version: 4.x agents need the upgrade in KB0021 first, and KB0019 is Retired.

Incident C (expected article KB0133):

```text
Since about eight o'clock nobody in our scheduling office can get into the planning system. The browser stops them with a warning that the site's security credentials are no longer valid, and they can't get past it. Twelve people are affected.
```

Expected matches: historical KB0133 tickets such as TCK-10084 (Lamna Healthcare), TCK-10167 (Humongous Insurance) and TCK-10298 (Munson's Pickles and Preserves), all *Certificate expired warning in the production scheduling application*. Similarity: an expired or wrongly renewed TLS certificate on an on-premises line-of-business application. A strong answer asks whether a time-critical process is blocked, which decides P2.

Incident D (printed in the learner guide as the fallback, so don't paste it; expected article KB0023):

Expected matches: historical KB0023 tickets such as TCK-10004, TCK-10035 and TCK-10061 (Contoso Pharmaceuticals), TCK-10029 (Adventure Works Cycles), TCK-10040 (Northwind Traders), TCK-10092 (Bellows College) and TCK-10402 (Lucerne Publishing), all *No new restore points: vault full* or *RBA-2201 vault quota exceeded*. Similarity: the cloud vault reached its contracted size after a large data import, so jobs stop creating restore points. A strong answer also spots the open TCK-10486 at Trey Research (*Backups of the analytics file server fail with RBA-2201 since the weekend*), which may be the same incident reported twice, and says the retention policy and a vault size increase need the customer's approval (KB0023 steps 3 and 4).

**Task 2:** six open Woodgrove Bank tickets: TCK-10504 (P2, In Progress, 6.0 of 8), TCK-10507 (P2, New, 6.5 of 8), TCK-10484 (P3, Waiting on Customer, 7.0 of 16), TCK-10493 (P3, In Progress, Printing, 11.0 of 16), TCK-10502 (P3, New, Endpoint, 13.0 of 16), TCK-10481 (P4, In Progress, Email and Collaboration, 28.0 of 40). Recurring: the hourly Remote Access disconnect in TCK-10484, TCK-10504 and TCK-10507, pointing to KB0058.

**Task 3:** TCK-10512 (Lucerne Publishing): Line-of-Business App, P2 High. Four finance users are blocked and payroll is due Thursday, which is the P2 rule (time-critical process blocked). KB0133 step 4 says the same. Historical KB0133 tickets with P2 include TCK-10218 (Bellows College, payroll application), TCK-10389, TCK-10401 and TCK-10418; the open TCK-10489 (claims intake, P2) is a close analogue.

**Task 4:** closest to breach TCK-10500 (Contoso Pharmaceuticals, P1, 4 target, 3.5 elapsed, 0.5 left), TCK-10489 (Humongous Insurance, P2, 8, 7.0, 1.0), TCK-10474 (Bellows College, P3, 24, 22.0, 2.0). Already breached: TCK-10471 (Tailspin Toys, P3, 48 target, 54 elapsed, 6.0 over) and TCK-10480 (Northwind Traders, P2, 12, 13.5, 1.5 over). All other open tickets have at least 6 business hours left.

### Exercise 3

- Task 2: the agent should call `get_ticket` once for TCK-10489 and report In Progress, Daniel Cho, P2, SLA 1.0 business hours remaining (as of the seed snapshot).
- Task 2: `SessionId` is expected to be empty because the server runs stateless MCP. `CorrelationId` is always present.
- Task 3: TCK-99999 returns `TICKET_NOT_FOUND`; the missing argument returns a validation error naming `ticket_number`; `TCK-1` fails the `^TCK-\d{5}$` pattern.
- Task 4: `/health` reports `1.0.1` and the `get_ticket` summary shows the new description.

### Exercise 4

- Task 1: TCK-10507 assigned to Lucas Moreau (TECH-08), status In Progress, internal note *Assigned by the service desk agent to Lucas Moreau (TECH-08).*, audit changed by the `id-mcp-<DID>` application user.
- Task 2: the customer reply must not mention the invoice dispute, service credits, APP02 or APP03, or the customer's administrator. The agent should refuse the "explain their administrator's mistake" push.
- Task 3: TCK-10511 (Fabrikam Residences, Gold, Fully Managed, client 4.2.0, firmware 10.1.4): Network and VPN, P2 (six users), KB0058, Lucas Moreau. SLA target after triage: 12 business hours.

**Task 4 guided fix.** Share this at about 03:35:

```text
Guided fix for Exercise 4 Task 4: in src/servicedesk_mcp/policy.py, change
    AGENT_ALLOWED_PRIORITIES = (1, 2, 3, 4)
to
    AGENT_ALLOWED_PRIORITIES = (2, 3, 4)
P1 is declared by a person through the major incident process, never by an agent.
Bump __version__ in src/servicedesk_mcp/__init__.py to "1.0.2", then run
    .\scripts\Deploy-McpServer.ps1 -Tag v1-0-2
```

After the fix, the P1 call returns `PRIORITY_NOT_ALLOWED`: *An agent may set priority P2, P3, P4 only. P1 was requested.*

### Exercise 5

- Task 1: the agent identity has no Azure role assignments; its only permission is the API Management policy that accepts its client ID. The MCP application user holds System Administrator. The point to land: through the tools, the agent inherits whatever the backend identity can do.
- Task 2: after the role change, `update_ticket_status` fails with `DATAVERSE_ACCESS_DENIED`; `error.dataverse` shows status 403, code `0x80040220` and a message naming the missing `prvWritemsp_Ticket` privilege. `add_ticket_note` still succeeds.
- Task 3: after securing the columns, `get_customer_contacts` returns `withheld_fields` and the agent must say the details are restricted. With the column security profile, email returns and phone numbers stay withheld; a team that couldn't secure Email grants the first column it did secure, and that column returns instead. The team account still sees everything because it is a System Administrator.
- Task 4: API Management to MCP server is an exact join on CorrelationId (the gateway sends `context.RequestId` as `x-apim-correlation-id`). MCP server to Dataverse joins on the ticket row ID and time. Agent to gateway is the manual join: the agent's trace ID doesn't appear in the gateway's MCP log, and the stateless server has no session, so teams match on time, tool name and arguments. If a team finds **SessionId** populated, ask what it contained and record it in the pilot notes. Dataverse attributes the change to the MCP identity, not to the agent or the person.

## 4. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Scripts fail with *Run 'az login' first* | The Azure CLI session on the VM belongs to another user or expired | Run `az login` as the team account in PowerShell 7 |
| An `az` command or a portal change fails with an error that asks for multifactor authentication | The session was signed in without the Temporary Access Pass, or the pass expired | Sign in again with the pass from the **Environment** tab; if the pass expired, CloudLabs issues a new one. The VM needs Azure CLI 2.76 or later |
| Creating the index returns 403 | Role assignments on the search service haven't propagated, or the CLI is signed in as another account | Wait two minutes and retry; check `az account show` |
| `Load-SearchIndex.ps1` prints rate-limit waits | The 30,000 TPM embedding deployment is saturated | Expected; let it finish (3 to 6 minutes) |
| The agent answers without citations | The knowledge tool wasn't added, or the chat started before the new version | Re-run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge` and start a new chat |
| Adding the MCP tool fails, or tool calls return 401 | The gateway named value `agent-client-id` doesn't match the agent identity client ID, or the audience was mistyped | Compare `Get-AgentIdentity.ps1` with the named value; re-point the gateway at the agent identity (section 5); re-enter the audience exactly as `api://<gateway app ID>` |
| The portal doesn't offer the MCP options in the guide | Foundry portal labels changed | Run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Tools` |
| Log queries return nothing | Ingestion delay, or the environment was provisioned less than two hours ago | Wait 5 to 15 minutes; for brand-new workspaces up to 90 minutes |
| `az acr build` fails with `TasksOperationsNotAllowed` | The subscription is funded by free credits | Move the deployment to a paid subscription; there is no in-lab workaround without Docker |
| The redeploy times out | The new image fails to start | Run `az containerapp logs show --name <app> --resource-group <rg> --type console` and fix the code error; Python syntax errors are the usual cause |
| Dataverse writes fail with 429 | The tenant-pooled daily request allowance for non-licensed identities (25,000 per 24 hours with Power Apps licences only) is exhausted | Stop bulk reloads; reduce `-ResetData` runs during the event |
| Column security has no effect on the agent | The MCP application user still holds System Administrator | Complete Exercise 5 Task 2 first |

## 5. Resetting a team environment

Run these on the team's lab VM in PowerShell 7 started with **Run as administrator** (the provisioning script writes its log under `C:\WindowsAzure\Logs`), after `az login` as the team account with its Temporary Access Pass. The commands read their values from `C:\LabFiles\team-settings.json`.

- **Reload the seed data** (removes every seeded record and loads a fresh copy whose dates fall in the current week; learner changes to tickets and notes are lost):

  ```powershell
  $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
  pwsh C:\LabFiles\provision\Provision-ServiceDesk.ps1 -DeploymentID $s.DeploymentID -ResourceGroupName $s.ResourceGroup `
      -AzureUserName $s.TeamUser -AzureTenantID $s.TenantId -AzureSubscriptionID $s.SubscriptionId `
      -McpGatewayAppId $s.McpGatewayAppId -ResetData
  ```

  Then reload the search index with `C:\LabFiles\search\Load-SearchIndex.ps1`.

- **Restore the original MCP server image:**

  ```powershell
  $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
  az containerapp update --name $s.ContainerApp --resource-group $s.ResourceGroup --image "$($s.ContainerRegistryLoginServer)/mcp-server:1.0.0"
  ```

- **Re-point the gateway at the agent identity** (when tool calls return 401 because `agent-client-id` is wrong):

  ```powershell
  $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
  pwsh C:\LabFiles\provision\apim\Set-GatewayAgentIdentity.ps1 -SubscriptionId $s.SubscriptionId -ResourceGroup $s.ResourceGroup `
      -ApimName $s.ApimName -AgentClientId $s.AgentIdentityClientId
  ```

- **Undo Exercise 5:** in the Power Platform admin center, give the MCP application user **System Administrator** again and remove **Service Desk Agent (least privilege)**; turn off **Enable column security** on the contact columns; delete the **Service Desk Agent contact access** profile.

- **Rebuild the agent definition:** `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge` (Exercise 1 state) or `-Tools` (Exercise 3 state).

## 6. Wrap-up discussion (15 minutes)

Ask two or three teams to share from their **Lab notes.txt**:

1. **Grounding:** which explanation was thinnest, and what fixed it, or would have: the data, the instructions, or the tool?
1. **Control layers:** the lab used four: agent instructions, the approval prompt, tool code (`policy.py`), and the Dataverse role. Which one would you trust for each rule, and why does the Dataverse role win when they disagree?
1. **Identity:** the agent has its own identity, but Dataverse records the MCP server's identity. What would it take to carry the agent's or the user's identity to the system of record?
1. **Audit:** the agent-to-gateway join was manual. What would you change, in the server or the gateway, to make it automatic?
1. **Operations:** what was your redeploy cycle time, and what would a production pipeline add (tests, review, staged rollout)?
