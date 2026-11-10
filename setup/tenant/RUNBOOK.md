# Environment Runbook: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phases 3 and 7 of 8, prepare the environments and close the event.** Phase 3 turns the published template into one ready environment per participant, plus two spares per workshop, at least 24 hours before the start. Phase 7 closes the event after the reviewers' 24-hour window. Before you start phase 3, phase 2 must be complete: the template is published and one test deployment succeeded ([setup/README.md](../README.md)). Start of the path: [README.md](../../README.md#delivery-path).

**Who:** a CloudLabs engineer for both phases; the delivery lead joins the phase 7 cost review. **Time:** phase 3, about 3 hours of elapsed time per batch of deployments (they run in parallel) plus 30 minutes of checks per workshop, started 48 hours ahead; phase 7, about 1 hour.

## What one environment is

Each participant gets a dedicated Microsoft Entra tenant with an Azure subscription in it (CloudLabs **Dedicated Tenant**). The template deploys the Azure resources, then the lab VM provisions the rest inside the tenant: the setup app, the gateway and Purview app registrations, the two MCP OAuth connections, the sensitivity label and the DLP policy, the managed developer environment with the Service Desk app and its data, the search export, the MCP server image and the agent. The last provisioning step removes the participant's Global Administrator role and every privilege the provisioning used. Every environment is built from **Golden Environment v1.0** and reports a consistency fingerprint, so two environments can be compared line by line.

| Timing that drives this runbook | Value |
|---|---|
| Template deployment (API Management Developer tier is the slowest part) | 35 to 50 minutes |
| Provisioning on the lab VM | 60 to 90 minutes |
| A new sensitivity label reaches the tenant | up to 24 hours |
| A new DLP policy takes effect | about 1 hour |
| Microsoft Purview activity appears | 60 to 90 minutes |
| Agent traces appear in Application Insights | 2 to 5 minutes |

## Rules for every event

- **Provision at least 24 hours ahead,** because the sensitivity label can take that long. Aim for 48 hours, which leaves a working day for repairs.
- **Two spares per workshop,** provisioned and checked like the participant environments. A failed environment is replaced by a spare; nobody repairs an environment while a participant waits.
- **No smoke tests as the participant accounts within 48 hours of an event.** Do not sign in as the Senior Technician or the Tier 1 Technician to try the agent, the tools or the app. The validation steps read the MCP server's tool log and the Dataverse audit, and they would count those calls as the participant's work. The readiness check is safe: it uses the lab VM's own identity, and its diagnostics call carries no user. If you must try something, use a spare and then redeploy that spare.
- **Change nothing in an environment after its readiness check passed,** except through this runbook.
- **Never hand out an environment whose CloudLabs status is Failed.** The status comes from the readiness check at the end of provisioning.

## Phase 3: Prepare the environments

### T minus 5 working days: confirm the event

1. Confirm the workshop date, the start time and the participant count with the delivery lead; add two spares per workshop.
2. Confirm the CloudLabs answers in [setup/README.md](../README.md#questions-for-cloudlabs) still hold, especially the bootstrap identity and the licenses (Microsoft 365 E5 and Power Apps Premium for both accounts of every environment).
3. Confirm the gpt-5.1 Global Standard quota in Canada Central for the subscriptions you will use ([setup/README.md](../README.md#step-1-check-quota-and-region)).

### T minus 48 hours: deploy

1. Deploy one environment per participant plus the spares from the CloudLabs template, in Canada Central.
2. Each deployment shows **Pending** while the lab VM provisions, then **Succeeded** or **Failed** with a message. A successful message reads like *Golden Environment v1.0 ready (fingerprint 3f9a1c0d2b7e). Every component is ready.*
3. Deployments run in parallel; nothing in one environment depends on another.

### T minus 47 hours: enable Purview pay-as-you-go in every tenant

Follow [PURVIEW-RUNBOOK.md](PURVIEW-RUNBOOK.md) in each tenant, spares included. It is a portal step with no API, and it takes about 5 minutes per tenant.

### T minus 45 hours: check provisioning

For every deployment:

1. Read the CloudLabs status message. **Succeeded** means every provisioning step succeeded and the readiness check passed, with one allowance: a new label can take up to 24 hours to be published, so the check accepts an unpublished label during its first 24 hours.
2. For **Failed**, open the lab VM (the trainer or support shadow access, or RDP as the VM administrator) and read:

   | File on the lab VM | What it tells you |
   |---|---|
   | `C:\LabFiles\provision-status.json` | Every provisioning step with **Succeeded**, **Failed** or **Skipped**, the reason, the time and the duration; `overall` summarizes |
   | `C:\WindowsAzure\Logs\MspProvisioning.txt` | The full provisioning transcript |
   | `C:\LabFiles\readiness\consistency-report.json` | The readiness result per component, the Golden Environment facts and the fingerprint |
   | `C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt` and `CloudLabsLogOnTask.txt` | The bootstrap and the logon task |

3. Repair with [If a provisioning step failed](#if-a-provisioning-step-failed), or replace the environment with a new deployment.

The provisioning steps, in order: `prerequisites`, `bootstrap`, `users`, `gateway`, `connections`, `purviewapp`, `purview`, `environment`, `schema`, `security`, `seed`, `export`, `incidents`, `agent`, `mcp`, `tracing`, `readiness`, `finalize`. A failed step skips only the steps that depend on it. `finalize` always runs, so no environment keeps an administrator right behind.

### T minus 24 hours: readiness and consistency

1. On every environment, run the readiness check. Either open the lab VM and double-click **Lab readiness check**, or run it remotely as an owner of the subscription:

   ```powershell
   az vm run-command invoke --resource-group <resource group> --name labvm-<DeploymentID> --command-id RunPowerShellScript `
       --scripts "& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File C:\LabFiles\tools\Test-LabReadiness.ps1"
   ```

   Every component must be **Ready**, and the last line must read *Every component is ready. You can start Exercise 1.* The check needs no sign-in and changes nothing.
2. Collect the consistency reports. Provisioning copied one per environment to the environment's storage account, container `servicedesk-export-meta`, folder `readiness/` (`<DeploymentID>-consistency-report.json` and `<DeploymentID>-provision-status.json`); the current one is `C:\LabFiles\readiness\consistency-report.json` on the VM. The same `fingerprint` on every environment means they were built identically. A different fingerprint names its cause in the `facts` section of the two reports.
3. Share the consistency reports with the delivery lead.
4. Mark each spare as ready in the CloudLabs pool.

When phase 3 is complete for the first workshop, register the validation steps if this is the first event: [Phase 4, validation-scripts/README.md](../../validation-scripts/README.md). Then run the pilot ([Phase 5](../../SUPPORT-GUIDE.md#phase-5-run-the-pilot)) or support the workshop ([Phase 6](../../SUPPORT-GUIDE.md#phase-6-support-the-workshop)).

### If a provisioning step failed

Re-running is safe: every step is idempotent. Steps after `finalize` need the supplier's own sign-in, because provisioning removed its own rights. Work on the lab VM in **PowerShell 7 started with Run as administrator**:

1. Sign in as a supplier Global Administrator of the tenant who is also Owner of the subscription:

   ```powershell
   az login --tenant <tenant ID> --allow-no-subscriptions
   ```

2. Run the failed steps with `-Bootstrap AzureCli`. Add `restore-roles` before them and `finalize` after them; `restore-roles` gives the provisioning identity back its provisioning-only roles, and `finalize` removes them again together with the setup app's rights. The bootstrap step is added automatically when a step needs the setup app.

   ```powershell
   $s = Get-Content C:\LabFiles\lab-settings.json -Raw | ConvertFrom-Json
   & C:\LabFiles\provision\Provision-ServiceDesk.ps1 -DeploymentID $s.DeploymentID -AzureUserName $s.SeniorUser `
       -AzureTenantID $s.TenantId -AzureSubscriptionID $s.SubscriptionId -Bootstrap AzureCli `
       -Steps restore-roles, agent, mcp, readiness, finalize
   ```

3. Run **Lab readiness check** again, then set the CloudLabs status by running the logon task once more: `powershell -ExecutionPolicy Bypass -File C:\LabFiles\logontask-01.ps1`.

Known failures and their fixes:

| Failed step and reason | Fix |
|---|---|
| `bootstrap`: *The ODL credential cannot sign in without interaction* | The ODL value is a Temporary Access Pass, or MFA applies, and no bootstrap service principal was supplied. See [Bootstrap by hand](#bootstrap-by-hand) |
| `environment`: *No identity is registered with Power Platform* | See [Register the setup app with Power Platform](#register-the-setup-app-with-power-platform) |
| `connections`: *no OAuth redirect URL was found* | See [Register the OAuth redirect URL](#register-the-oauth-redirect-url). The agent is still created |
| `users`: *does not exist after 30 minutes* | CloudLabs did not create the Tier 1 Technician from `setup/scripts/user-creation.json`. Fix the user creation, then re-run from `users` |
| `purview`: *Connect-IPPSSession* errors | A new tenant's Security & Compliance endpoint can take up to an hour to answer. Re-run `purview`, `seed`, `mcp`, `readiness`, `finalize` |
| `security`: *Setting the Senior Technician's roles failed* | Dataverse refused to remove System Administrator from the environment's owner. Redeploy with the template parameter `seniorDataverseSystemAdministrator` set to `true` (the pilot fallback) |
| `finalize`: *No other enabled user holds Global Administrator* | The tenant has no supplier Global Administrator besides the participant. Add one (setup/README.md, Questions for CloudLabs), or redeploy with `requireSupplierGlobalAdmin` set to `false` |
| `readiness`: one component not ready | The detail names the cause; fix it with the step that owns the component and run the check again |

#### Bootstrap by hand

When the ODL credential is a Temporary Access Pass and CloudLabs supplies no bootstrap service principal, the bootstrap needs a person once:

1. On the lab VM, sign in with `az login --tenant <tenant ID> --allow-no-subscriptions` as a supplier Global Administrator (a browser opens; complete MFA).
2. Run every step from `bootstrap` with `-Bootstrap AzureCli`, as in step 2 above, with `-Steps bootstrap, users, gateway, connections, purviewapp, purview, environment, schema, security, seed, export, incidents, agent, mcp, tracing, readiness, finalize`. The first-boot run stopped before it removed any role, so `restore-roles` is not needed.

#### Register the setup app with Power Platform

Power Platform accepts a service principal only after a tenant administrator registered it, with a user sign-in. Provisioning does this with the ODL password when it can. When it could not (a Temporary Access Pass and a service principal bootstrap), re-run with your own sign-in, which registers the setup app in the bootstrap step: `-Bootstrap AzureCli -Steps restore-roles, environment, schema, security, seed, export, incidents, agent, mcp, readiness, finalize`.

#### Register the OAuth redirect URL

Foundry generates the redirect URL of an OAuth connection when the connection is created. Provisioning registers every redirect URL it can read from the connection and from the template parameter `oauthRedirectUris`. When it found none:

1. In the Foundry portal (`https://ai.azure.com`), open the project `proj-msp-<DeploymentID>`, select **Tools** (or **Connected resources**), open `servicedesk-read` and copy its **Redirect URL**. Do the same for `servicedesk-write` if it shows a different URL.
2. In the Microsoft Entra admin center, as a supplier administrator, open **App registrations** > **Relecloud Service Desk MCP Gateway** > **Authentication**, add the URL under **Web**, and select **Save**.
3. Run **Lab readiness check**; **MCP connections** must be **Ready**.
4. Record the URL. If it is the same for every tenant, set it in the template parameter `oauthRedirectUris` so later deployments register it automatically; if it contains a tenant or connection identifier, record the pattern in BUILD-NOTES.md.

#### Reload the seed data

Only when an environment was provisioned so early that its SLA snapshot is out of date (for example a postponed event), and never within 48 hours of the event: re-run with `-ResetData`, which re-anchors the data to the current week, exports the search content again and loads the new incidents. It adds `restore-roles`, `bootstrap` and `finalize` itself, so sign in with `az login` first and pass `-Bootstrap AzureCli`. Changes made in the environment's tickets and notes are lost.

## Event day: checks, spares and resets

The workshop itself is run by CloudLabs support as [SUPPORT-GUIDE.md](../../SUPPORT-GUIDE.md#phase-6-support-the-workshop) describes. These are the environment procedures it refers to.

### From 30 minutes before the start

1. Run the readiness check on every environment and spare (remotely, as in [T minus 24 hours](#t-minus-24-hours-readiness-and-consistency)).
2. Replace any environment that is not ready with a spare before its participant arrives.
3. Confirm that each participant's **Environment** tab shows the Senior Technician's Temporary Access Pass and the Tier 1 Technician's sign-in.

### Replace a failed environment with a spare (within 15 minutes)

1. Confirm the failure: the participant's readiness check shows a component that stays **Not ready** after a second run, or a lab step fails in a way the guide's Troubleshooting does not cover.
2. Assign a spare whose readiness check passed that day, and send the participant its access details.
3. Record the time of the report and the time the participant resumed; the participant's lab time is extended by the difference.
4. Work done in the failed environment is not carried over. Keep the failed environment until the end of the day for diagnosis, then let it be deleted with the others.

### Reset an environment (within 60 minutes)

A reset gives the participant a fresh environment in a new tenant. Provisioning a new one takes more than 60 minutes, and its sensitivity label needs up to 24 hours, so a reset is always served from a prepared spare:

1. Assign a ready spare, exactly as in the swap above. That is the reset, and it completes well within 60 minutes.
2. Deploy a replacement spare at once, so the pool is back to two. It is usable for the next workshop day, not the same day.
3. When no spare is left, tell the delivery lead: the participant continues in their current environment, and support helps them past the problem.

## Phase 7: Close the event

### After the 24-hour review window

1. Confirm with the delivery lead that the requester's reviewers have finished. Nothing is deleted before.
2. Export each subscription's activity log before the deployments are deleted. The statement of work lets the requester ask for the Azure subscription audit logs for up to 30 days after deletion, so take them while the subscription still exists. As an owner or reader of each subscription, spares included:

   ```powershell
   az account set --subscription <subscription ID>
   az monitor activity-log list --start-time <the deployment time, in UTC> --max-events 100000 --output json > "<DeploymentID>-activity-log.json"
   ```

   Give the files to the delivery lead, who shares them only with the requester and only on request, and deletes them 30 days after the environments were deleted. They are the only logs the supplier keeps after teardown.
3. Let CloudLabs delete the deployments as usual. With a Dedicated Tenant, the resource group and the subscription go with the deployment; ask CloudLabs whether the tenant is deleted or returned to a pool ([setup/README.md](../README.md#questions-for-cloudlabs)).
4. If tenants are returned to a pool, clean the tenant objects that are not Azure resources, as a supplier Global Administrator, for each tenant:

   ```powershell
   pwsh setup/tenant/Remove-LabTenantObjects.ps1 -TenantId <tenant ID> -DeploymentID <DeploymentID>
   ```

   It signs you in (Azure CLI and Security & Compliance PowerShell), lists what it found, and asks before deleting each object: the managed developer environment, the three app registrations (setup app, gateway, Purview integration), the sensitivity label policy, the DLP policy and its rule, the label, and the Senior Technician's Purview role group memberships. Run it with `-WhatIf` first to see the list only.

### Verify the teardown

- In the CloudLabs portal, every deployment of the event, spares included, shows as deleted.
- In each tenant that was not deleted: the Power Platform admin center lists no environment named `Relecloud Service Desk <DeploymentID>`, and **App registrations** lists no app named `Relecloud Lab Setup`, `Relecloud Service Desk MCP Gateway` or `Relecloud Service Desk Purview Integration`.
- The temporary records of the event (support log, swap times, consistency reports, token checks) are filed with the delivery lead, and the delivery lead has sent the requester the [workshop report](../../SUPPORT-GUIDE.md#workshop-report).

### Reconcile the costs

With the delivery lead, compare the actual costs with the estimate in [estimates/](../../estimates/):

| Cost | Where to read it |
|---|---|
| Azure (API Management Developer, AI Search Basic, Container Apps, Container Registry, Foundry tokens, Log Analytics, the lab VM) | Cost Management for each subscription, filtered by the event's dates |
| Foundry model tokens per participant | The token usage of the `gpt-5.1` deployment in each Foundry resource; tell the delivery lead about any participant above 80 percent of the allowance |
| Microsoft Purview pay-as-you-go | The pay-as-you-go billing view of each tenant ([PURVIEW-RUNBOOK.md](PURVIEW-RUNBOOK.md)) |
| Licenses (Microsoft 365 E5, Power Apps Premium) | The CloudLabs license report for the event |
| Spares and resets | The number of spares deployed and used, from the swap records |

## Phase checklist

**Phase 3, prepare the environments:**

- [ ] Every environment and two spares per workshop were deployed at least 24 hours before the start
- [ ] Purview pay-as-you-go is enabled in every tenant
- [ ] Every deployment shows **Succeeded**, and every failed one was repaired or replaced
- [ ] The readiness check reports every component **Ready** on every environment and spare, 24 hours ahead and again 30 minutes before the start
- [ ] The consistency reports are collected, their fingerprints match, and the delivery lead has them
- [ ] Nobody signed in as a participant account within 48 hours of the event

**Phase 7, close the event:**

- [ ] The reviewers confirmed they are done before anything was deleted
- [ ] Every subscription's activity log was exported before deletion, and the date it is deleted (30 days later) is recorded
- [ ] Every deployment of the event is deleted, spares included
- [ ] The workshop report was sent to the requester
- [ ] Tenants returned to a pool were cleaned with `Remove-LabTenantObjects.ps1`
- [ ] Costs are reconciled with the estimate, and the incident, swap and extension records are filed

---

**Next:** Phase 8, maintain the lab: [BUILD-NOTES.md](../../BUILD-NOTES.md).
