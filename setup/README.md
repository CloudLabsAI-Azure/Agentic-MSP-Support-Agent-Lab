# Build and Publish the Template: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phase 2 of 8, build and publish the template.** This phase turns this folder into a CloudLabs template that builds one complete participant environment per deployment, and proves it with one test deployment. Do it once per lab version. Before you start, phase 1 must be complete: the delivery dates, the participant count and the licenses are agreed ([AGENDA.md](../AGENDA.md)), and CloudLabs has answered the [Questions for CloudLabs](#questions-for-cloudlabs). Start of the path: [README.md](../README.md#delivery-path).

**Who:** a CloudLabs engineer, with the setup author for the questions. **Time:** about half a day, plus one test deployment (about 2.5 hours until it reports **Succeeded**).

## What is in this folder

| Path | What it is |
|---|---|
| `bicep/main.bicep`, `bicep/modules/*.bicep` | The source of the Azure template. Change the template here, never in `deploy-01.json` |
| `bicep/Build-Template.ps1`, `bicep/bicepconfig.json` | Compiles the template with the pinned Bicep version (0.48.1), checks the CloudLabs contract and writes `deploy-01.json`; fails when `deploy-01.json` is out of date |
| `deploy-01.json` | The compiled ARM template CloudLabs deploys (generated) |
| `deploy-01.parameters.json` | The parameters file with the CloudLabs tokens |
| `scripts/psscript-01.ps1` | The VM bootstrap (stage 1): CloudLabs sequence, tools, lab files, then provisioning |
| `scripts/logontask-01.ps1` | The first-logon task (stage 2): desktop, Lab notes, readiness check, final CloudLabs status |
| `scripts/user-creation.json` | The second lab user (Tier 1 Technician) and both accounts' licenses |
| `policy/armpolicy-01.json`, `policy/armrbac-01.json`, `policy/usagepolicy.json` | The CloudLabs governance: allowed resource types and SKUs, the participant's custom role, usage limits |
| `apim/*.policy.xml` | The API Management policies of the read, write and diagnostics APIs (embedded in the template) |
| `assets/labfiles/` | The source of `C:\LabFiles` on the lab VM: provisioning, seed, search, tools, agent instructions |
| `Build-LabFilesZip.ps1` | Packs `assets/labfiles`, the reference solutions and the MCP server release into `assets/msp-labfiles.zip` |
| `tenant/RUNBOOK.md`, `tenant/PURVIEW-RUNBOOK.md`, `tenant/Remove-LabTenantObjects.ps1` | Phases 3 and 7: preparing, checking, repairing and closing environments |
| `DATA-SPEC.md`, `tests/` | The seed data specification and its determinism tests (data author) |

## How one environment is built

One CloudLabs deployment is one participant environment: a **Dedicated Tenant** (a Microsoft Entra tenant of its own) with an Azure subscription in that tenant. Nothing is shared between participants.

1. **The template** (`deploy-01.json`, about 35 to 50 minutes) creates, in Canada Central: the Foundry resource and project with `gpt-5.1` and `text-embedding-3-small` (Global Standard) and the `search` and `appinsights` project connections; Azure AI Search Basic (role-based access only); the export storage account; API Management Developer with the read, write and diagnostics MCP APIs and their policies; the Container Apps environment and the MCP server app; the container registry; Key Vault with its audit log; Log Analytics and Application Insights; three managed identities (`id-mcp`, `id-prov`, `id-apim`) and every role assignment Azure Resource Manager can make. The lab VM comes last, so its first boot finds everything in place.
2. **The VM bootstrap** (`psscript-01.ps1`) installs the tools and the lab files and runs **provisioning** (`C:\LabFiles\provision\Provision-ServiceDesk.ps1`, 60 to 90 minutes) inside the tenant. A certificate-based **setup app**, created once by a bootstrap identity, creates the gateway and Purview app registrations, the two MCP OAuth connections, the sensitivity label, its publishing policy and the DLP policy, and the managed developer environment. The lab VM's identity `id-prov` deploys the Service Desk schema, roles and data, the search export, the MCP server image and the agent. The last step removes the participant's Global Administrator role, reduces `id-prov` to read-only, and strips the setup app of every right.
3. **The logon task** (`logontask-01.ps1`) prepares the desktop, runs the readiness check and reports **Succeeded** or **Failed** to CloudLabs, with the Golden Environment version and the consistency fingerprint.

The bootstrap identity creates the setup app. Two kinds are supported; CloudLabs chooses with the [questions below](#questions-for-cloudlabs):

| Bootstrap | How it works | When to use it |
|---|---|---|
| **CloudLabs service principal (preferred)** | A per-tenant service principal with Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All and RoleManagement.ReadWrite.Directory (or the Global Administrator role). Its application ID and secret arrive as the template parameters `bootstrapAppId` and `bootstrapAppSecret`; the template stores the secret in Key Vault only, and the last provisioning step deletes it | Always, when CloudLabs can supply it: no person and no password involved |
| **ODL credential** | The participant's account, a Global Administrator during provisioning, signs in with its password (resource owner password grant) | Only when the ODL credential is a real password and no MFA applies to it. A Temporary Access Pass cannot be used this way |

Power Platform accepts the setup app only after a tenant administrator registered it with a user sign-in. Provisioning does that with the ODL password when it can. With a Temporary Access Pass, either CloudLabs registers its own service principal with Power Platform (question 2), or a supplier administrator signs in once per tenant ([RUNBOOK.md, Register the setup app with Power Platform](tenant/RUNBOOK.md#register-the-setup-app-with-power-platform)).

## Questions for CloudLabs

Answer these before the first deployment; the answers decide the parameters and the runbook steps.

| # | Question | Why it matters | Where the answer goes |
|---|---|---|---|
| 1 | Is the ODL credential (`AzureAdUserPassword`) a password or a Temporary Access Pass? | A password allows the ODL bootstrap; a Temporary Access Pass needs question 2 or a manual bootstrap per tenant. The guide calls the value a Temporary Access Pass either way | Bootstrap choice above |
| 2 | Can CloudLabs supply a per-tenant service principal with the permissions above, as template tokens (for example `GET-SERVICEPRINCIPAL-APPLICATION-ID` and `GET-SERVICEPRINCIPAL-SECRET`), and register it once with Power Platform as a management application? | Fully unattended provisioning with no password, the preferred design | `bootstrapAppId` and `bootstrapAppSecret` in `deploy-01.parameters.json` |
| 3 | Are security defaults off, and does no Conditional Access policy require MFA for the ODL account during provisioning or block agent identities? | Security defaults block the ODL bootstrap; a policy that blocks agent identities stops the agent's Entra Agent ID | Tenant baseline |
| 4 | What are the CSP offer IDs of **Microsoft 365 E5** and **Power Apps Premium**, and how does the ODL user get them? | Both accounts need both licenses: Purview for Exercise 6, the managed developer environment for the Service Desk. `user-creation.json` assigns them to the Tier 1 Technician only (quantity 1 each), so the ODL user, the Senior Technician, needs them from the template's own license settings, or the quantities become 2 with the ODL user assigned | `scripts/user-creation.json` (replace the two `REPLACE-WITH-CSP-OFFER-ID-...` values, and raise the quantities if the JSON also licenses the ODL user) and the template's license settings |
| 5 | Does every tenant keep a supplier Global Administrator besides the participant? | Provisioning removes the participant's Global Administrator role only when another administrator remains, so the tenant stays manageable | Template parameter `requireSupplierGlobalAdmin` (default `true`) |
| 6 | Is the Azure subscription created in the same tenant, with the deployment identity as Owner? | Provisioning and the participant's roles assume the subscription and the tenant are the same | Tenant baseline |
| 7 | Is each tenant deleted after the event, or returned to a pool? | A pooled tenant keeps the Power Platform environment, the app registrations and the Purview objects | Phase 7 in [RUNBOOK.md](tenant/RUNBOOK.md#phase-7-close-the-event) |
| 8 | What is the object ID of the CloudLabs validation service principal in each tenant, and its token? | It gets read-only data roles on search and storage for the graded steps | `validationPrincipalObjectId` in `deploy-01.parameters.json` |
| 9 | Under which field name does the **Environment** tab show the Tier 1 Technician's sign-in and pass? | The guide tells participants to copy it from there | Lab guide |
| 10 | Can the template library serve `assets/msp-labfiles.zip` without anonymous read access, for example through a SAS URL or a protected asset? | The archive carries the private MCP server source, which the statement of work treats as confidential, and the lab VM downloads it at first boot | `$projectBlob` in `scripts/psscript-01.ps1` and [Step 4](#step-4-upload-the-files-to-the-template-library) |

## Step 1: Check quota and region

For every subscription the environments will use (one per participant tenant):

- [ ] **Region:** Canada Central (fallback Canada East). East US 2 and Sweden Central no longer accept new Azure AI Search services. The Dataverse environment is created in the Power Platform region `canada` (template parameters `dataverseLocation` and `dataverseUrlSuffix` change both together).
- [ ] **Model quota:** Global Standard `gpt-5.1` (version 2025-11-13), 100,000 tokens per minute, and `text-embedding-3-small` (version 1), 150,000 tokens per minute, per subscription (`chatModelCapacity` and `embeddingModelCapacity`). In the Foundry portal, **Quota** shows the subscription's limit for each model in the region; request more before the event if a new subscription's default is lower.
- [ ] **Subscription type:** not funded by free credits, because ACR Tasks (the image build) are paused on free-credit subscriptions.
- [ ] **Lab VM:** the Spektra `cloudlabs-windows-jumpvm` image (`win2022mssd`) and `Standard_D2s_v5` capacity in the region.
- [ ] **Entra admin center access:** **Restrict access to Microsoft Entra admin center** is **No**, so participants can open **Agent ID** in Exercises 1 and 5.
- [ ] **Application Insights GenAI content:** if `Get-ActionTrail.ps1` reports that the `AppGenAIContent` table is protected in the pilot, grant the Senior Technician **Privileged Monitoring Data Reader** on the workspace, or leave the table unprotected.

## Step 2: Build the template

You need PowerShell 7 and the Azure CLI. `Build-Template.ps1` uses the Bicep version pinned in `bicep/bicepconfig.json`; install it once with `az bicep install --version v0.48.1`.

```powershell
pwsh setup/bicep/Build-Template.ps1            # checks: fails when deploy-01.json is out of date
pwsh setup/bicep/Build-Template.ps1 -Update    # compiles and writes deploy-01.json
```

It fails on any Bicep warning, renames the outputs to the names CloudLabs shows (Bicep cannot use spaces), checks the eight CloudLabs platform parameters and the 38 outputs against the contract, and compares the result with `deploy-01.json`. The compiled template holds 12 nested deployments, one per Bicep module.

## Step 3: Build the lab files archive

You need a clone of the private MCP server repository next to this repository (or pass `-McpServerRepo`), with the release tag `v3.0.0`:

```powershell
gh repo clone CloudLabsAI-Azure/agentic-msp-mcp-server
pwsh setup/Build-LabFilesZip.ps1
```

The script packs `assets/labfiles`, the repository's `solutions` folder and the tagged MCP server source (`git archive`, so exactly the tagged files) into `assets/msp-labfiles.zip`. It stops when the tag's `__version__` differs from `McpRelease` in `assets/labfiles/provision/LabConfig.psd1`, when the agent's read or write tool lists name a tool the release does not have, when a file the VM needs is missing, or when a PowerShell file does not parse. The archive holds the private server source: upload it to the template library only; `.gitignore` keeps it out of this repository.

To ship a server change later: tag a new release whose tag matches `__version__`, set `McpRelease` in `LabConfig.psd1` and the `lab-mcp-release` tag value in `bicep/main.bicep`, rebuild the template and the archive, and update the version numbers in the guide (3.0.0 at the start, 3.0.1 after Exercise 3, 3.0.2 and 3.0.3 in Exercise 4).

## Step 4: Upload the files to the template library

1. In the AZ-Templates library, create the project folder `agentic-msp-support-agent` with this layout, and add every file to `AZ-Templates.deployproj` as `Content`:

   ```text
   agentic-msp-support-agent/
   ├── deploy-01.json
   ├── deploy-01.parameters.json
   ├── armpolicy-01.json
   ├── armrbac-01.json
   ├── usagepolicy.json
   ├── user-creation.json
   ├── scripts/
   │   ├── psscript-01.ps1
   │   └── logontask-01.ps1
   └── assets/
       └── msp-labfiles.zip
   ```

2. Make sure these blob paths resolve; the lab VM downloads them at first boot:

   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/scripts/psscript-01.ps1` (the template's userData points here)
   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/scripts/logontask-01.ps1`
   - `https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent/assets/msp-labfiles.zip`

## Step 5: Create the CloudLabs template

| Setting | Value |
|---|---|
| Cloud and tenancy | Azure, **Dedicated Tenant** with an Azure subscription in that tenant; region Canada Central |
| ARM template | `deploy-01.json` with `deploy-01.parameters.json` |
| Parameters | The eight platform parameters come from CloudLabs tokens (`GET-AZUSER-UPN`, `GET-AZUSER-PASSWORD`, `GET-ODL-ID`, `GET-DEPLOYMENT-ID`, `GEN-PASSWORD`); `azuserobjectid` is `GET-AZUSER-OBJECTID`. Set `bootstrapAppId` and `bootstrapAppSecret` to the service principal tokens from question 2 (as a secure parameter for the secret), or leave both empty for the ODL bootstrap. Set `validationPrincipalObjectId` from question 8 |
| Users | `scripts/user-creation.json`: the Tier 1 Technician (`tier1.technician@<tenant domain>`, password generated by CloudLabs, no administrator role) and the licenses of both accounts, with the CSP offer IDs from question 4 |
| Governance | `armpolicy-01.json` (deny policy), `armrbac-01.json` (the participant's custom role), `usagepolicy.json` |
| Output parameters | Keep every output on the **Environment** tab: the guide injects them. Add **Trainer Username** and **Trainer Password** to **Excluding Output Parameters** |
| Lab guide | The repository's `masterdoc.json` on the `toc-v3` branch, where this version lives: `https://docs-api.cloudlabs.ai/repos/raw.githubusercontent.com/CloudLabsAI-Azure/Agentic-MSP-Support-Agent-Lab/refs/heads/toc-v3/masterdoc.json`. Its pages point at the same branch. When the version is merged into `main`, change both to `refs/heads/main`. The repository is private, so CloudLabs also needs a fine-grained read-only token for it |
| Validation | **Enable Lab Validation**, with the steps registered in phase 4 ([validation-scripts/README.md](../validation-scripts/README.md)) |
| Duration | The 4-hour window plus the reviewers' 24-hour access agreed in phase 1. The template has no auto-shutdown schedule; CloudLabs manages uptime |
| Deployment lead time | At least 24 hours before the start (sensitivity labels), see [RUNBOOK.md](tenant/RUNBOOK.md) |

## Step 6: Run one test deployment

1. Deploy one environment from the template and watch its status: **Pending** while the VM provisions, then **Succeeded** with *Golden Environment v1.0 ready (fingerprint ...). Every component is ready.*
2. On the lab VM, open `C:\LabFiles\provision-status.json`: every step shows **Succeeded**. The transcript is `C:\WindowsAzure\Logs\MspProvisioning.txt`.
3. Double-click **Lab readiness check** on the desktop: ten components **Ready** and the last line *Every component is ready. You can start Exercise 1.*
4. Enable Purview pay-as-you-go in the test tenant ([PURVIEW-RUNBOOK.md](tenant/PURVIEW-RUNBOOK.md)) and check its table.
5. Keep this environment for the pilot (phase 5) if the pilot is within the next days; otherwise let it be deleted.

## Reference

### Template parameters

| Parameter | Default | Purpose |
|---|---|---|
| `adminUsername`, `adminPassword` | `azureuser`, `GEN-PASSWORD` | Lab VM administrator (the account that signs in to the VM) |
| `AzureUserName`, `AzurePassword` | `GET-AZUSER-UPN`, `GET-AZUSER-PASSWORD` | The participant, the Senior Technician; the password is used only by the ODL bootstrap |
| `ODLID`, `DeploymentID` | `GET-ODL-ID`, `GET-DEPLOYMENT-ID` | CloudLabs instance and the naming suffix of every resource |
| `trainerUserName`, `trainerUserPassword` | `trainer`, `GEN-PASSWORD` | The CloudLabs support shadow account on the VM (hidden outputs) |
| `azuserobjectid` | `GET-AZUSER-OBJECTID` | The participant's object ID, for direct role assignments |
| `bootstrapAppId`, `bootstrapAppSecret` | empty | The CloudLabs bootstrap service principal (question 2); the secret is stored only in Key Vault |
| `validationPrincipalObjectId` | empty | The CloudLabs validation service principal (question 8): read-only data roles on search and storage |
| `oauthRedirectUris` | empty | Redirect URLs of the Foundry OAuth connections, comma separated, when Foundry does not return them ([RUNBOOK.md](tenant/RUNBOOK.md#register-the-oauth-redirect-url)) |
| `dataverseLocation`, `dataverseUrlSuffix` | `canada`, `crm3.dynamics.com` | Power Platform region of the managed developer environment |
| `chatModelCapacity`, `embeddingModelCapacity` | `100`, `150` | Global Standard capacity in thousands of tokens per minute |
| `requireSupplierGlobalAdmin` | `true` | Remove the participant's Global Administrator role only when another administrator remains |
| `tier1FoundryRole` | `Foundry Agent Consumer` | The Tier 1 Technician's role on the Foundry project; `Foundry User` is the pilot fallback for the portal playground |
| `seniorDataverseSystemAdministrator` | `false` | Pilot fallback: the Senior Technician is also System Administrator in the Dataverse environment |
| `foundrySearchFallbackRoles` | `false` | Pilot fallback: extra search roles for the Foundry resource identity |
| `mcpBackendKeySeed` | generated | Never set: seeds the per-deployment backend key |

### Outputs (the Environment tab and the guide's inject keys)

`DeploymentID`, `Region`, `Resource Group Name`, `LabVM DNS Name`, `LabVM Admin Username`, `LabVM Admin Password`, `Trainer Username`, `Trainer Password` (hidden), `Foundry Resource Name`, `Foundry Project Name`, `Foundry Project Endpoint`, `Chat Model Deployment`, `Embedding Model Deployment`, `Agent Name`, `AI Search Service Name`, `AI Search Endpoint`, `Storage Account Name`, `Export Container`, `API Management Name`, `MCP Read Gateway URL`, `MCP Write Gateway URL`, `MCP Diagnostics URL`, `MCP Gateway Audience`, `MCP Read Connection`, `MCP Write Connection`, `MCP Server URL`, `Container App Name`, `Container Registry Name`, `Key Vault Name`, `Key Vault URL`, `Log Analytics Workspace`, `Application Insights Name`, `MCP Backend Identity Name`, `MCP Backend Identity Client ID`, `Dataverse Environment URL`, `Service Desk App URL`, `Tier 1 Technician Username`, `Golden Environment Version`.

The resource group also carries the tags the validation steps read: `lab-golden-environment` (`v1.0`), `lab-searchable-documents` (`753`), `lab-new-incident-1` (`TCK-10561`), `lab-new-incident-2` (`TCK-10562`) and `lab-mcp-release` (`3.0.0`), merged with the tags CloudLabs sets. The readiness check compares them with the seed manifest and the release.

### Names

| Object | Name |
|---|---|
| Lab VM, Foundry resource and project | `labvm-<DID>`, `aif-msp-<DID>`, `proj-msp-<DID>` |
| Model deployments | `gpt-5.1`, `text-embedding-3-small` |
| Agent | `msp-support-agent`, MCP tools `servicedesk-read` (no approval) and `servicedesk-write` (approval on every call) |
| Project connections | `servicedesk-read`, `servicedesk-write` (OAuth identity passthrough), `search` (Microsoft Entra ID), `appinsights` |
| AI Search, index objects of Exercise 1 | `srch-msp-<DID>`; `servicedesk-knowledge`, `servicedesk-export-ds`, `servicedesk-embed-skills`, `servicedesk-export-indexer` |
| Storage account and containers | `stmsp<DID><4 characters>`; `servicedesk-export` (one JSON file per document), `servicedesk-export-meta` (export manifest, readiness reports) |
| API Management, APIs, diagnostics subscription | `apim-msp-<DID>`; `servicedesk-read`, `servicedesk-write`, `servicedesk-diag`; `lab-diagnostics` |
| Container Apps environment and app, registry | `cae-msp-<DID>`, `ca-mcp-<DID>` (baseline revision suffix `baseline-<time>`), `acrmsp<DID><4 characters>`, image `mcp-server:3.0.0` |
| Key Vault and its secrets | `kv-msp-<DID>-<4 characters>`; `mcp-backend-key`, `purview-client-secret`, `apim-diagnostics-key` |
| Monitoring | `log-msp-<DID>`, `appi-msp-<DID>` |
| Managed identities | `id-mcp-<DID>` (MCP server), `id-prov-<DID>` (lab VM), `id-apim-<DID>` (API Management) |
| App registrations in the tenant | `Relecloud Lab Setup <DID>` (stripped at the end), `Relecloud Service Desk MCP Gateway` (scope `ServiceDesk.Access`, audience `https://<tenant domain>/servicedesk-mcp`), `Relecloud Service Desk Purview Integration` |
| Microsoft Purview | Label `Relecloud Confidential`, label policy `Relecloud Service Desk label policy`, DLP policy `Relecloud Service Desk card numbers` with rule `Block card numbers sent to the agent` |
| Power Platform | Managed developer environment `Relecloud Service Desk <DID>` (domain `mspdesk<DID>`), app **Service Desk** (`spk_ServiceDesk`) |
| Dataverse roles | `Service Desk Agent Read`, `Service Desk Agent Write`, `Service Desk Senior Technician`, `Service Desk Tier 1 Technician`, `Service Desk Security Steward`, `Service Desk Readiness Read`; business unit `Relecloud Regulated Accounts`; column security profile `Contact Phone Protection` |

### Settings file: C:\LabFiles\lab-settings.json

Written by provisioning, read by every lab tool; it never holds a secret. Keys: `DeploymentID`, `TenantId`, `SubscriptionId`, `ResourceGroup`, `Region`, `SeniorUser`, `SeniorUserObjectId`, `Tier1User`, `Tier1UserObjectId`, `FoundryResource`, `FoundryProject`, `FoundryProjectEndpoint`, `ChatDeployment`, `EmbeddingDeployment`, `AgentName`, `AgentId` (the Entra Agent ID client ID), `AgentIdentityObjectId`, `AgentVersion`, `SearchService`, `SearchEndpoint`, `SearchIndex`, `StorageAccount`, `ExportContainer`, `ExportMetaContainer`, `ExportManifest`, `ApimName`, `McpReadGatewayUrl`, `McpWriteGatewayUrl`, `McpDiagnosticsUrl`, `ApimDiagnosticsSubscription`, `ApimDiagnosticsKeySecret`, `McpReadConnection`, `McpWriteConnection`, `McpGatewayAppId`, `McpGatewayAppObjectId`, `McpGatewayAudience`, `McpGatewayScope`, `McpConnectionSecretExpires`, `McpConnectionRedirectUris`, `ContainerApp`, `ContainerRegistry`, `ContainerRegistryLoginServer`, `McpServerUrl`, `McpRelease`, `McpImage`, `McpBaselineRevision`, `McpBackendIdentityName`, `McpBackendIdentityClientId`, `ProvisioningIdentityClientId`, `ProvisioningPrincipalId`, `KeyVault`, `KeyVaultUrl`, `LogAnalyticsWorkspace`, `LogAnalyticsWorkspaceId`, `AppInsights`, `DataverseUrl`, `DataverseEnvironmentId`, `DataverseEnvironmentSku`, `ServiceDeskAppUrl`, `SensitivityLabelId`, `SensitivityLabelName`, `PurviewAppId`, `PurviewDlpPolicy`, `Purview` (a summary), `GoldenEnvironmentVersion`, `McpServerSource`, `SeedManifest`, `ReadinessReport`, `ProvisionedOn`.

Other files on the VM: `C:\LabFiles\provision-status.json` (provisioning steps), `C:\LabFiles\readiness\readiness-report.json` (one object per component: `Component`, `Status`, `Detail`) and `consistency-report.json` (with the facts and the fingerprint), `C:\LabFiles\search\export-manifest.json` and `sample-documents\`, `C:\LabFiles\seed\data\manifest.json`, and `C:\LabFiles\evidence\` (the participants' exported evidence).

### MCP server contract (release v3.0.0)

What provisioning, API Management and the readiness check expect from the server in `CloudLabsAI-Azure/agentic-msp-mcp-server`:

| Item | Contract |
|---|---|
| Endpoints | `/read/mcp` read tools only (the `servicedesk-read` API), `/write/mcp` write tools only (`servicedesk-write`), `/mcp` every tool for the diagnostics API (user headers ignored, so writes refuse), `/health` without a key. Stateless streamable HTTP with JSON responses, port 8000 |
| Gateway key | Every MCP path requires `x-backend-key`, compared with the Key Vault secret `mcp-backend-key`, which the server reads at startup with `id-mcp` |
| Headers from API Management | `x-correlation-id` (a GUID, echoed in every result), `x-user-oid`, `x-user-name`, `x-client-app-id`, `x-agent-id` (the Entra Agent ID from the named value `agent-id`), `x-gateway-api` (`servicedesk-read`, `servicedesk-write` or `servicedesk-diag`), `x-gateway-caller` (`agent` or `operator`). The diagnostics API removes every user header |
| Environment variables | `DATA_BACKEND`, `DATAVERSE_URL`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `KEY_VAULT_URL`, `BACKEND_KEY_SECRET_NAME`, `REQUIRE_BACKEND_KEY`, `DATAVERSE_IMPERSONATION`, `REQUIRE_USER_FOR_WRITES`, `AGENT_NAME`, `AGENT_ID`, `PURVIEW_ENABLED`, `PURVIEW_TENANT_ID`, `PURVIEW_CLIENT_ID`, `PURVIEW_CLIENT_SECRET_NAME`, `PURVIEW_RESTRICTED_LABELS` (label ID and name, comma separated), `MCP_ALLOWED_HOSTS`, `MCP_STATELESS`, `MCP_READ_PATH`, `MCP_WRITE_PATH`, `MCP_DIAGNOSTICS_PATH`, `GOLDEN_ENVIRONMENT_VERSION`, `LOG_LEVEL`, `PORT` |
| `/health` | `status` `ok`, `version` equal to `__version__`, `gateway_key_source` `key vault`, `user_impersonation` `true`; `purview` is shown by the readiness check |
| Tools | The read and write lists in `LabConfig.psd1` (`ReadTools`, `WriteTools`) are checked against the release's `@catalogue.read_tool` and `@catalogue.write_tool` functions when the archive is built. `get_ticket` takes `ticket_number`. Agent action records (`spk_agentaction`) are written by the server as itself, never impersonated |
| Release | Tag `v3.0.0` with `__version__ = "3.0.0"`, and `scripts/Deploy-McpServer.ps1`, `Invoke-McpTool.ps1` and `Show-McpServerLog.ps1`, which provisioning copies to `C:\LabFiles\tools` and which read `C:\LabFiles\lab-settings.json`. The diagnostics key is available from the subscription `lab-diagnostics` (the participant's role may list its keys) or the Key Vault secret `apim-diagnostics-key` (the VM's identity may read it) |

### Identities and their rights

| Identity | During provisioning | After provisioning |
|---|---|---|
| Senior Technician (the participant) | Global Administrator (CloudLabs) | No directory role. The custom role on the resource group; Foundry User on the project; Reader on the Foundry resource and the storage account; Log Analytics Reader; Key Vault Reader; Search Service Contributor and Search Index Data Reader; Storage Blob Data Reader; Managed Identity Operator on `id-mcp`; Purview role groups Information Protection Analysts and Data Security AI Viewers; Dataverse Service Desk Senior Technician and Service Desk Security Steward |
| Tier 1 Technician | none | Foundry Agent Consumer on the project; Dataverse Service Desk Tier 1 Technician |
| `id-prov` (lab VM) | Provisioning-only: Storage Blob Data Contributor, Foundry Project Manager, Key Vault Secrets Officer, API Management Service Contributor, a conditional role assignment administrator role; Dataverse System Administrator | Reader on the resource group, Foundry User, Storage Blob Data Reader, Log Analytics Reader, Key Vault Reader, Key Vault Secrets User on `apim-diagnostics-key` only, registry push and Tasks, Container Apps Contributor, Managed Identity Operator on `id-mcp`; Graph read-only (users, directory roles, applications, consent grants, published labels); Dataverse Service Desk Agent Read and Service Desk Readiness Read |
| `id-mcp` (MCP server) | same as after | Key Vault Secrets User, AcrPull; Dataverse application user with Service Desk Agent Read, Service Desk Agent Write and Delegate (never System Administrator) |
| `id-apim` (API Management) | same as after | Key Vault Secrets User, for the `mcp-backend-key` named value |
| Setup app | Graph application permissions, Exchange.ManageAsApp, Global Administrator role, Power Platform management application, Dataverse System Administrator | No credential, no role, no permission (stripped by the last step); its certificate is deleted from the VM |
| Agent (`msp-support-agent`) | none | Its own Entra Agent ID; no Dataverse permission. Its tool calls carry the signed-in technician's token |

## Phase checklist

- [ ] CloudLabs answered every question in [Questions for CloudLabs](#questions-for-cloudlabs), and the answers are in the parameters file and `user-creation.json`
- [ ] Quota, region and tenant settings are confirmed (step 1)
- [ ] `Build-Template.ps1` reports `deploy-01.json` up to date
- [ ] `Build-LabFilesZip.ps1` built `msp-labfiles.zip` from the MCP server tag `v3.0.0` with every check passing
- [ ] The files are uploaded and the three blob paths resolve
- [ ] The CloudLabs template is configured as in step 5, with the trainer outputs excluded
- [ ] One test deployment reports **Succeeded**, and its readiness check shows every component **Ready**

---

**Next:** Phase 3, prepare the environments: [tenant/RUNBOOK.md](tenant/RUNBOOK.md).
