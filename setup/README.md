# Deployment package: Agentic MSP Support Agent Guided Lab

This folder holds everything CloudLabs needs to provision one team environment. One CloudLabs deployment is one team environment. The learner guide ships from the repository root `masterdoc.json`; there is no second masterdoc in this folder.

## What is here

| Path | Purpose |
|---|---|
| `deploy-01.json` | ARM template for the team resource group: lab VM, Foundry resource, project and model deployments, Azure AI Search, API Management with the two MCP APIs, Container Apps environment and app, Container Registry, Key Vault, managed identities, Log Analytics, Application Insights, diagnostic settings and role assignments |
| `deploy-01.parameters.json` | Parameter file with CloudLabs tokens; set `mcpGatewayAppId` per tenant (see step 2) |
| `scripts/psscript-01.ps1` | userData bootstrap (stage 1) on the Spektra `cloudlabs-windows-jumpvm` image: CloudLabs agent sequence, tooling, lab files, then `Provision-ServiceDesk.ps1` (Azure Resource Manager work as the VM's provisioning identity, Power Platform and Dataverse work as the team user) |
| `scripts/logontask-01.ps1` | First-logon task (stage 2): VS Code extensions, desktop shortcuts, team summary and notes files, final validation table and deployment status |
| `assets/labfiles/` | Source of `C:\LabFiles` on the VM: provisioning scripts, Dataverse schema, seed generator and loader, search index tooling, agent instructions and helper tools |
| `assets/msp-labfiles.zip` | Build output of `Build-LabFilesZip.ps1`; the file the VM downloads. It contains the private MCP server source, so it goes to the template library only and `.gitignore` keeps it out of this repository |
| `Build-LabFilesZip.ps1` | Packages `assets/labfiles` and an MCP server release tag into `assets/msp-labfiles.zip` |
| `policy/armpolicy-01.json` | Deny policy: allowed resource types, VM size and image, disk SKU, AI Search Basic, API Management Basic v2, ACR Basic, Foundry kind and model deployments |
| `policy/armrbac-01.json` | `Spektra Custom RBAC` role for the attendee |
| `policy/usagepolicy.json` | Usage limits per resource type |
| `tenant/Initialize-LabTenant.ps1` | One-time tenant preparation: the gateway app registration and Power Platform checks |
| `tests/test_seed_determinism.py` | Checks that the seed generator produces the same tickets, notes and counts for any anchor date (`python -m pytest setup/tests`) |

## 1. Prerequisites to confirm (per tenant and subscription)

- [ ] **Region:** Sweden Central. East US and East US 2 currently block new Azure AI Search services.
- [ ] **Model quota:** Global Standard `gpt-5.4-mini` (version 2026-03-17) and `text-embedding-3-small` (version 1) in Sweden Central, 30,000 TPM per team for each, which gives the chat deployment about 30 requests per minute. 25 teams need 750,000 TPM of each model, so the subscription needs quota Tier 1 or higher (Tier 0 has no `gpt-5.4-mini` quota).
- [ ] **Subscription type:** not funded by free credits; ACR Tasks (`az acr build`) are paused on free-credit subscriptions.
- [ ] **Image:** the Spektra `cloudlabs-windows-jumpvm` image (`win2022mssd`, version `24.04.01`) is available to the subscription in Sweden Central, and `Standard_D4s_v5` capacity is available.
- [ ] **Licences:** every team account gets **Microsoft Power Apps for Developer** (`POWERAPPS_DEV`, `5b631642-bd26-49fe-bd20-1daaa972ef80`) before the deployment starts. Assign it in the CloudLabs template licence settings or through group-based licensing.
- [ ] **Power Platform tenant settings:** **Developer environment assignments** must allow the team accounts to create developer environments, and internal consent plans must be allowed (`Initialize-LabTenant.ps1` prints both).
- [ ] **Sign-in and MFA for attendees:** Azure's mandatory MFA applies to every tenant, with no exception for test or lab tenants. It covers sign-in to the Azure portal and the Microsoft Entra admin center, and every Azure Resource Manager create, update or delete from the CLI, PowerShell, REST or the portal. Exercises 1, 3 and 4 make such changes. Issue each team account a multi-use **Temporary Access Pass** whose lifetime covers launch plus the session, and show it on the **Environment** tab (`AzureAdUserPassword` in a TAP tenant; the guide labels it accordingly). The VM needs Azure CLI 2.76 or later; `InstallAzCLI` installs the current release.
- [ ] **Provisioning sign-in:** provisioning runs every Resource Manager change as the VM's user-assigned identity `id-prov-<DID>`, and managed identities are outside the MFA enforcement. Power Platform and Dataverse calls still run as the team account, because it owns the developer environment: `New-DeveloperEnvironment.ps1` (`Add-PowerAppsAccount`) and the Dataverse token use the account's password without a browser (the resource owner password grant). That needs a password, not a Temporary Access Pass, in `AzureAdUserPassword` during provisioning, and no Conditional Access policy or security default that requires MFA for Power Platform or Dataverse. Confirm with CloudLabs how the TAP tenant provides this before the pilot: for example, a password that is valid during provisioning, or a Power Platform service principal that creates the environment for the team account.
- [ ] **Conditional Access:** no policy blocks agent identities.
- [ ] **Microsoft Entra admin center access:** set **Restrict access to Microsoft Entra administration portal** to **No**, so team accounts can browse to **Agent identities** in Exercises 1 and 5.
- [ ] **Application Insights GenAI content:** leave the `AppGenAIContent` table unprotected in each workspace, or grant the team account **Privileged Monitoring Data Reader**, so Exercise 5 can read tool-call arguments.
- [ ] **Licensing confirmation:** each team shares one account. The Power Platform licensing guidance treats multiplexing as a violation; get written confirmation from Microsoft licensing that one Developer Plan account per team is acceptable for this training delivery, or give every attendee their own account.

## 2. One-time tenant preparation

1. As a tenant administrator, run:

   ```powershell
   pwsh setup/tenant/Initialize-LabTenant.ps1 -TenantId <tenant id>
   ```

1. Copy the printed **Application (client) ID** into `deploy-01.parameters.json` as the value of `mcpGatewayAppId`, replacing `REPLACE-WITH-MCP-GATEWAY-APP-ID`. Every team's agent requests tokens for `api://<that ID>`, and each team's API Management accepts only its own agent identity's client ID for that audience.
1. Apply the Power Platform changes the script reports.

## 3. The MCP server repository

The MCP server source is in the private repository `CloudLabsAI-Azure/agentic-msp-mcp-server`, and this lab uses its tag `v1.0.0`. Lab VMs never contact GitHub, so they need no GitHub access or credentials:

- `Build-LabFilesZip.ps1` packs the tagged source into the lab files archive as `provision/mcp-server`, with `git archive`, so the archive holds exactly the tagged files.
- `Provision-ServiceDesk.ps1` builds the starter image from that copy, and creates each team's local Git repository of the same release in `C:\LabFiles\mcp-server`, with no remote. It also adds that folder to the VM's system-wide Git `safe.directory` list, because SYSTEM creates it and the attendee's Git would otherwise refuse it.
- Exercises 3 and 4 change that local copy and redeploy it with `scripts/Deploy-McpServer.ps1`.

To build the archive, you need a clone of the repository. The build script looks for it next to this repository (the build workspace layout); otherwise pass its path with `-McpServerRepo`:

```powershell
gh repo clone CloudLabsAI-Azure/agentic-msp-mcp-server
```

To ship a server change, commit it, tag a new release whose tag matches `__version__` in `src/servicedesk_mcp/__init__.py` (for example `v1.0.1` and `"1.0.1"`), and rebuild the archive with `-McpRelease v1.0.1`. The guide's version numbers (`1.0.0` at the start, `1.0.1` after Exercise 3, `1.0.2` after Exercise 4) assume the starter release is `1.0.0`; update them if you ship a newer starter.

Attendees still see the full source on their VMs, which the exercises need, and anyone with the template blob URL can download the archive, as with every CloudLabs template asset. The repository is private on GitHub, not secret.

## 4. Build the lab files archive

Run this after any change under `assets/labfiles` and after every new MCP server release:

```powershell
pwsh setup/Build-LabFilesZip.ps1
```

The script checks that the tag exists and that its `__version__` matches. The archive contains the private MCP server source: upload it to the template library (section 5) and don't commit it.

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

   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/scripts/psscript-01.ps1` (the userData pointer in `deploy-01.json`)
   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/scripts/logontask-01.ps1`
   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/assets/msp-labfiles.zip`

## 6. Configure the CloudLabs Template

- **Cloud and region:** Azure, Sweden Central, shared subscription with one resource group per deployment.
- **ARM template:** `deploy-01.json` with `deploy-01.parameters.json`; governance `armpolicy-01.json`, `armrbac-01.json` and `usagepolicy.json`.
- **Licences:** **Microsoft Power Apps for Developer** on the attendee account.
- **Output parameters:** keep the deployment outputs on the **Environment** tab (the guide injects them). Add **Trainer Username** and **Trainer Password** to **Excluding Output Parameters** so attendees don't see them.
- **Lab guide:** Github Master Document file URL `https://docs-api.cloudlabs.ai/repos/raw.githubusercontent.com/CloudLabsAI-Azure/Agentic-MSP-Support-Agent-Lab/refs/heads/main/masterdoc.json`.
- **Validation:** turn on **Enable Lab Validation** and register the steps in `validation-scripts/README.md`, then replace each `REPLACE-WITH-VALIDATION-GUID` in the guide with the minted GUID.
- **Duration:** 5 hours for the session, with a VM uptime limit of at least 5 hours. Launch deployments at least 2 hours before the session (provisioning takes about 45 to 75 minutes, and new Log Analytics workspaces can take up to 90 minutes to show their first diagnostic records).

## 7. What provisioning creates outside Azure, and teardown

`Provision-ServiceDesk.ps1` creates a **Power Platform developer environment** named `Relecloud Service Desk <DeploymentID>` as the team account. Deleting the CloudLabs resource group does not remove it. After the event, a Power Platform administrator deletes these environments in the Power Platform admin center (**Manage** > **Environments**), or they are disabled automatically after 30 days without activity and deleted 15 days later. The gateway app registration is tenant-wide; keep it while labs run.

## 8. Pilot checklist

Walk one deployment through the whole guide before the first delivery and confirm each item. These are the behaviors the documentation doesn't settle.

- [ ] Provisioning: `az login --identity` as `id-prov-<DID>` succeeds within a few minutes of boot, and the `mcp`, `gateway` and `smoketest` steps succeed as that identity (`C:\LabFiles\provision-status.json`).
- [ ] Provisioning: the team account signs in to Power Platform and Dataverse with `AzureAdUserPassword` without a browser (`environment`, `schema`, `security` and `seed` steps).
- [ ] `C:\LabFiles\mcp-server` exists with one commit tagged `v1.0.0`, and the attendee runs `git log` and `git switch` in it from a non-elevated PowerShell 7 without a *dubious ownership* error.
- [ ] A team account signs in on the VM with its Temporary Access Pass, and the Foundry **Add connection** step, `Update-AgentDefinition.ps1` and `Deploy-McpServer.ps1` all succeed with no MFA-required error.
- [ ] `New-AdminPowerAppEnvironment -EnvironmentSku Developer` succeeds as the team account with the Developer Plan licence, and the URL is `https://mspdesk<DID>.crm4.dynamics.com` (a taken domain gets a numeric suffix; the script then updates the settings and the Container App).
- [ ] Creating the application user with `POST systemusers` and the managed identity's client ID works; otherwise use the Power Platform admin center (**Application users** > **New app user**) once per environment.
- [ ] The model-driven app opens from the **Service Desk** shortcut, with the sitemap areas, views and forms the guide names.
- [ ] The Foundry agent has an `instance_identity` immediately after creation, and the agent identity can get a token for `api://<gateway app ID>` without an app role assignment.
- [ ] The portal path **Tools** > **Add** > **Custom** > **Model Context Protocol (MCP)** with **Microsoft Entra** > **Agent Identity** exists as written; otherwise teams use `Update-AgentDefinition.ps1 -Tools`.
- [ ] `ApiManagementGatewayMCPLog` rows arrive and `CorrelationId` equals the MCP server's `correlation_id`; record whether `SessionId` is populated.
- [ ] Foundry agent traces show the `execute_tool` spans in the **Traces** tab and in `AppDependencies`, and tool-call arguments in `AppGenAIContent`.
- [ ] Selecting **Save** in the playground after Exercise 1 keeps the Azure AI Search tool that `Update-AgentDefinition.ps1 -Knowledge` attached, with `top_k` 10 and the hybrid query type.
- [ ] `Update-AgentDefinition.ps1 -Tools` creates the RemoteTool connection (an ARM PUT with `authType` `AgenticIdentityToken` and `audience` at API version `2025-10-01-preview`, which the published schema doesn't list). If ARM rejects it, switch the fallback to `azd ai connection create --kind remote-tool --auth-type agentic-identity --audience <audience>`.
- [ ] Securing a contact column takes effect for the MCP application user within a minute without **Publish all customizations**; if it doesn't, add that step to Exercise 5 Task 3.
- [ ] `az acr build` and `az containerapp update` work with the attendee's roles.
- [ ] The least-privilege role still lets `get_customer_contacts` read column definitions (the server falls back to the last known list if not), and **Enable column security** is available for contact **Email** and **Business Phone**.
- [ ] Capture the exact Dataverse privilege error text for the guide's screenshot.
- [ ] Capture every screenshot listed in `SCREENSHOT-TODO.md` and replace the pending markers.
- [ ] Register and deploy the validation steps; run Template Audit **Lab Test** end to end.
