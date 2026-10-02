# Deployment package: Agentic MSP Support Agent Guided Lab

This folder holds everything CloudLabs needs to provision one team environment. One CloudLabs deployment is one team environment. The learner guide ships from the repository root `masterdoc.json`; there is no second masterdoc in this folder. The lab is self-paced: participants check their own progress against the expected results in the guide and contact support when something is wrong, so this file is also the support runbook.

## What is here

| Path | Purpose |
|---|---|
| `deploy-01.json` | ARM template for the team resource group: lab VM, Foundry resource, project, model deployments and the OAuth MCP connection, Azure AI Search, API Management with the two MCP APIs, Container Apps environment and app, Container Registry, Key Vault with its audit log, managed identities, Log Analytics, Application Insights, diagnostic settings and role assignments |
| `deploy-01.parameters.json` | Parameter file with CloudLabs tokens and the tenant values from step 2 |
| `scripts/psscript-01.ps1` | userData bootstrap (stage 1) on the Spektra `cloudlabs-windows-jumpvm` image: CloudLabs agent sequence, tooling, lab files, then `Provision-ServiceDesk.ps1` |
| `scripts/logontask-01.ps1` | First-logon task (stage 2): VS Code extensions, desktop shortcuts (including **Lab readiness check**), team summary and notes files, final validation table and deployment status |
| `assets/labfiles/` | Source of `C:\LabFiles` on the VM: provisioning scripts, Dataverse schema, seed generator and loader, search export and loader, agent instructions and lab tools |
| `assets/msp-labfiles.zip` | Build output of `Build-LabFilesZip.ps1`; the file the VM downloads. It contains the private MCP server source, so it goes to the template library only and `.gitignore` keeps it out of this repository |
| `Build-LabFilesZip.ps1` | Packages `assets/labfiles` and an MCP server release tag into `assets/msp-labfiles.zip` |
| `policy/armpolicy-01.json` | Deny policy: allowed resource types, VM size and image, disk SKU, AI Search Basic, API Management Basic v2, ACR Basic, Foundry kind and model deployments |
| `policy/armrbac-01.json` | `Spektra Custom RBAC` role for the attendee |
| `policy/usagepolicy.json` | Usage limits per resource type |
| `tenant/Initialize-LabTenant.ps1` | One-time tenant preparation: the MCP gateway app (scope, OAuth client secret, redirect URL), the Purview app, and the Power Platform checks |
| `tests/test_seed_determinism.py` | Checks that the seed generator produces the same tickets, notes and counts for any anchor date (`python -m pytest setup/tests`) |

## How the environment is secured

Safe by default, so no exercise asks participants to fix an exposure:

- **Two identities per team.** The team account is the **Senior Technician**. A second lab user is the **Tier 1 Technician**, read-only on tickets.
- **User identity end to end.** The agent's MCP connection uses OAuth identity passthrough. API Management accepts only a signed-in technician's token for the gateway audience with the `ServiceDesk.Access` scope and forwards who the user is. The MCP server runs every Dataverse call on behalf of that user (`CallerObjectId`), so a call succeeds only when both the technician's role and the server's application user allow it.
- **Least privilege, reads and writes separated.** The server's application user holds **Service Desk Agent Read**, **Service Desk Agent Write** (ticket updates and ticket notes only) and **Delegate**; never System Administrator. The agent itself has no Dataverse permission.
- **Secrets in Key Vault.** The gateway key is a Key Vault secret that API Management reads through its managed identity and the MCP server reads at startup through its own. Nothing secret is in the repository, the image or the container app configuration, and the vault's audit log records every read.
- **Approval on writes.** The agent's MCP tool lists only the nine read tools as never needing approval, so every write tool, and any tool a team adds, asks the user first.
- **Input validation and correlation.** Every tool validates its arguments before it runs, and every call carries the API Management request ID as its correlation ID, from the gateway log to the Dataverse record.
- **Data protection.** Internal notes are withheld unless asked for, contact columns can be secured, and when Purview is configured, ticket text and customer documents go through Microsoft Purview DLP; a document with the restricted sensitivity label is never returned.

## 1. Prerequisites to confirm (per tenant and subscription)

- [ ] **Region:** Sweden Central. East US and East US 2 currently block new Azure AI Search services.
- [ ] **Model quota:** Global Standard `gpt-5.4-mini` (version 2026-03-17) and `text-embedding-3-small` (version 1) in Sweden Central, 30,000 TPM per team for each. 25 teams need 750,000 TPM of each model, so the subscription needs quota Tier 1 or higher.
- [ ] **Subscription type:** not funded by free credits; ACR Tasks (`az acr build`) are paused on free-credit subscriptions.
- [ ] **Image:** the Spektra `cloudlabs-windows-jumpvm` image (`win2022mssd`, version `24.04.01`) is available in Sweden Central, with `Standard_D4s_v5` capacity.
- [ ] **Two lab users per deployment:** CloudLabs issues the team account (Senior Technician) and a second user (Tier 1 Technician), and passes the second user's UPN and object ID to `tier1UserName` and `tier1UserObjectId`. Both users' credentials appear on the **Environment** tab.
- [ ] **Licences, for both users:** **Microsoft Power Apps for Developer** (`POWERAPPS_DEV`, `5b631642-bd26-49fe-bd20-1daaa972ef80`), and **Microsoft 365 E5** or **E5 Compliance** for Microsoft Purview DLP on AI interactions. Assign them in the CloudLabs template licence settings or through group-based licensing.
- [ ] **Power Platform tenant settings:** **Developer environment assignments** allows the team accounts to create developer environments, and internal consent plans are allowed (`Initialize-LabTenant.ps1` prints both).
- [ ] **Sign-in and MFA:** Azure's mandatory MFA covers sign-in to the Azure portal and every Azure Resource Manager change. Exercises 1, 3, 4 and 5 make such changes. Issue each lab user a multi-use **Temporary Access Pass** whose lifetime covers launch plus the 6-hour session, shown on the **Environment** tab. The VM needs Azure CLI 2.76 or later; `InstallAzCLI` installs the current release.
- [ ] **Provisioning sign-in:** provisioning runs every Resource Manager change as the VM's user-assigned identity `id-prov-<DID>`, which is outside the MFA enforcement. Power Platform and Dataverse changes still run as the team account, because it owns the developer environment, with its password and no browser (the resource owner password grant). That needs a password in `AzureAdUserPassword` during provisioning and no Conditional Access policy that requires MFA for Power Platform or Dataverse. Confirm with CloudLabs how the TAP tenant provides this.
- [ ] **Conditional Access:** no policy blocks agent identities.
- [ ] **Microsoft Entra admin center access:** **Restrict access to Microsoft Entra administration portal** is **No**, so lab users can browse to **Agent ID** in Exercises 1 and 5.
- [ ] **Microsoft Purview:** pay-as-you-go billing is enabled for Purview data security for AI apps, and the tenant has the DLP policy and sensitivity label from step 2.
- [ ] **Application Insights GenAI content:** leave the `AppGenAIContent` table unprotected in each workspace, or grant the team account **Privileged Monitoring Data Reader**, so Exercise 6 Task 3 and `Get-ActionTrail.ps1` can read the agent's tool calls and results.
- [ ] **Licensing confirmation:** each team shares one account per role. Get written confirmation from Microsoft licensing that this is acceptable for the training delivery, or give every attendee their own accounts.

## 2. One-time tenant preparation

1. As a tenant administrator, run:

   ```powershell
   pwsh setup/tenant/Initialize-LabTenant.ps1 -TenantId <tenant id> -NewSecrets
   ```

   It creates or updates the **Relecloud Service Desk MCP Gateway** app (delegated scope `ServiceDesk.Access`, admin-consented, with a client secret for the Foundry OAuth connection) and the **Relecloud Service Desk Purview Integration** app (Graph application permission `Content.Process.All`, admin-consented, with a client secret). It prints the values once.
1. Put the values in the CloudLabs template: `mcpGatewayAppId` and `purviewClientId` in `deploy-01.parameters.json`; `mcpOAuthClientSecret` and `purviewClientSecret` as **secure parameters** in the template configuration, never in this repository.
1. **Redirect URL.** Foundry shows a redirect URL when an OAuth connection is created. After the first pilot deployment, open the team's Foundry project, **Management center** > **Connected resources** > `servicedesk-mcp`, copy its redirect URL and run `Initialize-LabTenant.ps1 -TenantId <tenant id> -RedirectUri <url>`. Until it is registered, the consent step in Exercise 1 fails with a redirect URI mismatch.
1. **Sensitivity label.** In the Microsoft Purview portal, use or create the label **Confidential** (Information protection > Sensitivity labels) and put its label ID in `sensitivityLabelId`. Provisioning stamps it on the seeded customer configuration document, and the MCP server never returns documents with that label.
1. **DLP policy.** In the Microsoft Purview portal, create a DLP policy for the location of the **Relecloud Service Desk Purview Integration** app (data security for AI apps) that detects **Credit Card Number** and blocks it. Seeded internal notes on TCK-10472 and TCK-10486 carry test card numbers, which Exercise 6 Task 2 relies on.
1. Apply the Power Platform changes the script reports.

## 3. The MCP server repository

The MCP server source is in the private repository `CloudLabsAI-Azure/agentic-msp-mcp-server`, and this lab uses its tag `v2.0.0`. Lab VMs never contact GitHub, so they need no GitHub access or credentials:

- `Build-LabFilesZip.ps1` packs the tagged source into the lab files archive as `provision/mcp-server`, with `git archive`, so the archive holds exactly the tagged files.
- `Provision-ServiceDesk.ps1` builds the starter image from that copy, and creates each team's local Git repository of the same release in `C:\LabFiles\mcp-server`, already cloned when the lab starts, with no remote. It also adds that folder to the VM's system-wide Git `safe.directory` list.
- Exercises 3 and 4 change that local copy and redeploy it with `scripts/Deploy-McpServer.ps1`.

To build the archive, you need a clone of the repository next to this one, or pass its path with `-McpServerRepo`:

```powershell
gh repo clone CloudLabsAI-Azure/agentic-msp-mcp-server
```

To ship a server change, commit it, tag a new release whose tag matches `__version__` in `src/servicedesk_mcp/__init__.py` (for example `v2.0.1` and `"2.0.1"`), and rebuild the archive with `-McpRelease v2.0.1`. The guide's version numbers (`2.0.0` at the start, `2.0.1` after Exercise 3 Task 4, `2.0.2` after Exercise 4 Task 4, `2.0.3` after Exercise 4 Task 5) assume the starter release is `2.0.0`; update them if you ship a newer starter.

## 4. Build the lab files archive

Run this after any change under `assets/labfiles` and after every new MCP server release:

```powershell
pwsh setup/Build-LabFilesZip.ps1
```

The script checks that the tag exists and that its `__version__` matches. Upload the archive to the template library (section 5) and don't commit it.

## 5. Register the template files (CloudEasyTemplates)

1. In the AZ-Templates library, create the project folder `agentic-msp-support-agent` and add the files with this layout:

   ```text
   agentic-msp-support-agent/
   ├── deploy-01.json
   ├── deploy-01.parameters.json
   ├── armpolicy-01.json
   ├── armrbac-01.json
   ├── usagepolicy.json
   ├── scripts/
   │   ├── psscript-01.ps1
   │   └── logontask-01.ps1
   └── assets/
       └── msp-labfiles.zip
   ```

1. Add the files to `AZ-Templates.deployproj` so they are published with the project:

   ```xml
   <Content Include="agentic-msp-support-agent\deploy-01.json" />
   <Content Include="agentic-msp-support-agent\deploy-01.parameters.json" />
   <Content Include="agentic-msp-support-agent\armpolicy-01.json" />
   <Content Include="agentic-msp-support-agent\armrbac-01.json" />
   <Content Include="agentic-msp-support-agent\usagepolicy.json" />
   <Content Include="agentic-msp-support-agent\scripts\psscript-01.ps1" />
   <Content Include="agentic-msp-support-agent\scripts\logontask-01.ps1" />
   <Content Include="agentic-msp-support-agent\assets\msp-labfiles.zip" />
   ```

1. Make sure these blob paths resolve; the VM downloads them at boot:

   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/scripts/psscript-01.ps1`
   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/scripts/logontask-01.ps1`
   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/assets/msp-labfiles.zip`

## 6. Configure the CloudLabs Template

- **Cloud and region:** Azure, Sweden Central, shared subscription with one resource group per deployment.
- **ARM template:** `deploy-01.json` with `deploy-01.parameters.json`; governance `armpolicy-01.json`, `armrbac-01.json` and `usagepolicy.json`.
- **Users:** two lab users per deployment (section 1), with the second user's UPN and object ID mapped to `tier1UserName` and `tier1UserObjectId`.
- **Secure parameters:** `mcpOAuthClientSecret` and `purviewClientSecret` (step 2).
- **Licences:** both users, as in section 1.
- **Output parameters:** keep the deployment outputs on the **Environment** tab (the guide injects them). Add **Trainer Username** and **Trainer Password** (the CloudLabs support shadow account) to **Excluding Output Parameters**.
- **Lab guide:** Github Master Document file URL `https://docs-api.cloudlabs.ai/repos/raw.githubusercontent.com/CloudLabsAI-Azure/Agentic-MSP-Support-Agent-Lab/refs/heads/main/masterdoc.json`.
- **Validation:** turn on **Enable Lab Validation** and register the steps in `validation-scripts/README.md`, then replace each `REPLACE-WITH-VALIDATION-GUID` in the guide with the minted GUID.
- **Duration:** 6 hours wall-clock (sign-in and breaks included), with a VM uptime limit of at least 6 hours. Launch deployments at least 2 hours before the start: provisioning takes about 50 to 80 minutes, and new Log Analytics workspaces can take up to 90 minutes to show their first diagnostic records.

## 7. What provisioning creates outside Azure, and teardown

`Provision-ServiceDesk.ps1` creates a **Power Platform developer environment** named `Relecloud Service Desk <DeploymentID>` as the team account and adds the Tier 1 user to it. Deleting the CloudLabs resource group doesn't remove it. After the event, a Power Platform administrator deletes these environments in the Power Platform admin center (**Manage** > **Environments**), or they are disabled automatically after 30 days without activity and deleted 15 days later. The two app registrations are tenant-wide; keep them while labs run, and rotate their secrets after each event (`Initialize-LabTenant.ps1 -NewSecrets`).

## 8. Support runbook

### Before the event

- [ ] Every deployment reports **Succeeded** in the CloudLabs admin portal. The logon task fails the deployment if any provisioning step, the MCP server health check (including the Key Vault key), the Entra Agent ID or a lab tool is missing.
- [ ] On one environment, double-click **Lab readiness check**: every component reports **Ready** (Tier 1 Technician reports **Not configured** when the deployment has no second user).
- [ ] Walk one environment through Exercise 1 Task 1, including the one-time Foundry consent for the MCP connection.

### Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| The readiness check reports a component **Not ready** | Provisioning step failed or is still finishing | Read `C:\LabFiles\provision-status.json` and `C:\WindowsAzure\Logs\MspProvisioning.txt`; re-run the failed step (below) |
| Scripts fail with *Run 'az login' first* | The participant's Azure CLI session expired or belongs to another user | `az login` as the team account in PowerShell 7 |
| An `az` command or a portal change asks for multifactor authentication | Signed in without the Temporary Access Pass, or the pass expired | Sign in again with the pass from the **Environment** tab; CloudLabs issues a new one if it expired |
| The agent's first tool call shows a consent link that fails with a redirect error | The connection's redirect URL is not registered on the gateway app | Step 2, **Redirect URL** |
| Tool calls return 401 | The user's token lacks the `ServiceDesk.Access` scope, or the user consented before the scope existed | Re-run `Initialize-LabTenant.ps1`; the user removes the connection consent and consents again |
| Write tools return `USER_CONTEXT_REQUIRED` | The call came through the diagnostics API, which carries no user | Expected: writes run only through the agent |
| `Load-SearchIndex.ps1` prints rate-limit waits | The 30,000 TPM embedding deployment is saturated | Expected; let it finish (3 to 6 minutes) |
| Log queries return nothing | Ingestion delay, or the environment was provisioned less than two hours ago | Wait 5 to 15 minutes; up to 90 minutes for brand-new workspaces |
| `az acr build` fails with `TasksOperationsNotAllowed` | The subscription is funded by free credits | Move the deployment to a paid subscription |
| A redeploy doesn't become healthy | The new image fails to start | `C:\LabFiles\mcp-server\scripts\Show-McpServerLog.ps1 -All`, fix the code error, redeploy; or roll back with `Deploy-McpServer.ps1 -Rollback` |
| Dataverse writes fail with 429 | The tenant-pooled daily request allowance is exhausted | Stop bulk reloads; avoid `-ResetData` runs during the event |
| Purview never blocks anything | No DLP policy for the Purview app, Purview pay-as-you-go not enabled, or the user lacks an E5 licence | Step 2 and section 1; `/health` reports `purview` as `enabled` when the server is configured |

### Re-running provisioning

Run these on the team's lab VM in PowerShell 7 started with **Run as administrator**, after `az login` as the team account. The commands read their values from `C:\LabFiles\team-settings.json`.

- **Re-run one or more steps** (for example after a transient failure):

  ```powershell
  $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
  pwsh C:\LabFiles\provision\Provision-ServiceDesk.ps1 -DeploymentID $s.DeploymentID -ResourceGroupName $s.ResourceGroup `
      -AzureUserName $s.TeamUser -AzureTenantID $s.TenantId -AzureSubscriptionID $s.SubscriptionId `
      -McpGatewayAppId $s.McpGatewayAppId -Steps security, readiness
  ```

  Re-running `security` also restores the least-privileged roles if a team changed them.

- **Reload the seed data** (removes every seeded record, loads a fresh copy whose dates fall in the current week, re-exports the search content and loads the new incidents; participant changes to tickets and notes are lost): the same command with `-ResetData` instead of `-Steps`. The participants then run `C:\LabFiles\search\Load-SearchIndex.ps1` again.
- **Restore the previous MCP server revision:** `C:\LabFiles\mcp-server\scripts\Deploy-McpServer.ps1 -Rollback`.
- **Rebuild the agent definition:** `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge` (state after Exercise 1) or `-Reset` (the baseline).

## 9. Pilot checklist and setup TODO

Walk one deployment through the whole guide before the first delivery. These are the items the documentation doesn't settle, and the manual setup that must be done once.

**Tenant, licence and manual setup (TODO before the first delivery):**

- [ ] CloudLabs: a second lab user per deployment, its inject keys for the guide (Tier 1 UPN and password on the **Environment** tab), and the mapping to `tier1UserName` and `tier1UserObjectId`.
- [ ] Licences for both users: Developer Plan, and E5 or E5 Compliance.
- [ ] `Initialize-LabTenant.ps1` run, secrets stored as template secure parameters, redirect URL registered (step 2).
- [ ] Sensitivity label ID set; DLP policy for the Purview app created; Purview pay-as-you-go enabled.
- [ ] Power Platform tenant settings and the provisioning sign-in confirmed (section 1).

**Behaviors to confirm on the pilot:**

- [ ] The `servicedesk-mcp` connection that `deploy-01.json` creates (ARM, `authType` `OAuth2`, category `RemoteTool`) works for consent and tool calls. Compare it with a reference connection created with the same values by the Azure Developer CLI (`azd ai connection create`, kind `remote-tool`, auth type `oauth2`); if the metadata keys differ, align `deploy-01.json`.
- [ ] The redirect URL is the same for every connection in the region (register once) or per connection (then provisioning must register each one).
- [ ] The agent's `require_approval` `{ never: { tool_names: [...] } }` is accepted, the read tools run without a prompt and every write tool asks for approval.
- [ ] API Management validates the user token (`scp` contains `ServiceDesk.Access`, `azp` is the gateway app) and forwards `x-user-oid` and `x-user-name`; the MCP log line shows the user.
- [ ] Dataverse impersonation with `CallerObjectId`: the Tier 1 write is refused with `0x80040220`, the Senior write succeeds, and the audit history shows the technician with the application user as the caller.
- [ ] Narrowing **Service Desk Agent Write** to Business Unit refuses writes on TCK-10479 and TCK-10491 (record owned by the **Relecloud Regulated Accounts** team) and record the exact error code.
- [ ] The Tier 1 user is added to the developer environment by `Add-AdminPowerAppsSyncUser`, can sign in to Foundry with the Foundry User role on the project, and the Service Desk app opens for it.
- [ ] The MCP server reads `mcp-backend-key` from Key Vault at startup, and `AZKVAuditLogs` shows the `SecretGet` by the server's managed identity.
- [ ] Purview `processContent` returns `restrictAccess` for the seeded card numbers with the lab's DLP policy, and the DLP event shows in the Purview portal (Activity explorer).
- [ ] `ApiManagementGatewayLogs.CorrelationId` equals the MCP server's `correlation_id`; record whether `ApiManagementGatewayMCPLog` carries a session ID.
- [ ] Foundry agent traces in Application Insights contain the tool output with the correlation ID, so `Get-ActionTrail.ps1` finds the agent run.
- [ ] Securing a contact column takes effect for the MCP application user within a minute.
- [ ] Capture every screenshot listed in `SCREENSHOT-TODO.md` and replace the pending markers.
- [ ] Register and deploy the validation steps; run Template Audit **Lab Test** end to end.
