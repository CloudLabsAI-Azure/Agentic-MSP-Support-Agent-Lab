# Research: Microsoft Purview data security for agent tool output, and unattended identity setup per lab tenant

Research notes for the lab "Agentic MSP Support Agent Guided Lab" (fictional MSP: Relecloud Managed Services). Researched on 2026-11-06 from Microsoft Learn (read in full through the Learn MCP fetch tool), official microsoft.com and azure.microsoft.com pages, and the Azure Retail Prices API only. No blogs, lab repos or third-party sites were used. The previous build's `src/servicedesk_mcp/purview.py`, `setup/tenant/Initialize-LabTenant.ps1` and `Instructions/exercise-6.md` were read only to list what had to be re-verified; nothing in this note is taken from them.

Planned environment (from the binding requirements of 2026-11-06, not a documentation source): one dedicated Microsoft Entra tenant per participant, created by CloudLabs, holding that participant's Azure subscription and resources; 4 workshops of up to 25 participants plus 2 spares each; two participant identities (Senior Technician, Tier 1 Technician); participants never hold a tenant administrator role; every tenant-wide setup step runs from a script on the lab VM (PowerShell 7, Python 3.12, Azure CLI) before admin rights are removed; a reset creates a new environment in a new tenant within 60 minutes.

Conventions:

- **Bold** text is a UI label (node, tab, filter, column, button, pane section) exactly as written in the cited page. Where pages disagree on a label, both spellings are given and the conflict is listed under OPEN QUESTIONS, the last section.
- [Sxx] is a source ID from section 0. Every statement carries at least one source ID. Design judgments that follow from sourced facts say "derived from" with the IDs.
- Status: **GA** means the page carries no preview label. **Preview** means the page labels it preview (public or private) or it is a Microsoft Graph beta API. **Retiring** means the page announces a deprecation or retirement date.
- Page text is paraphrased. One short direct quote is used (section 9.1).

## 0. Sources

| ID | URL | Page title | Read on |
| - | - | - | - |
| S01 | https://learn.microsoft.com/en-us/graph/api/userdatasecurityandgovernance-processcontent?view=graph-rest-1.0 | userDataSecurityAndGovernance: processContent (all prose, permissions, HTTP examples 1 to 4 and responses; per-language SDK tabs skipped) | 2026-11-06 |
| S02 | https://learn.microsoft.com/en-us/graph/security-datasecurityandgovernance-overview | Microsoft Purview data security and governance APIs | 2026-11-06 |
| S03 | https://learn.microsoft.com/en-us/purview/developer/use-the-api | Tutorial: Use Microsoft Purview APIs to leverage your policies in your apps | 2026-11-06 |
| S04 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-dlpcompliancerule | New-DlpComplianceRule (description, examples 1 to 4, and the parameters cited here) | 2026-11-06 |
| S05 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-dlpcompliancepolicy | New-DlpCompliancePolicy | 2026-11-06 |
| S06 | https://learn.microsoft.com/en-us/purview/ai-entra-registered | Use Microsoft Purview to manage data security & compliance for Entra-registered AI apps | 2026-11-06 |
| S07 | https://learn.microsoft.com/en-us/purview/ai-azure-foundry | Use Microsoft Purview to manage data security & compliance for Microsoft Foundry | 2026-11-06 |
| S08 | https://learn.microsoft.com/en-us/azure/foundry/control-plane/how-to-manage-compliance-security | Manage compliance and security in Microsoft Foundry | 2026-11-06 |
| S09 | https://learn.microsoft.com/en-us/purview/purview-billing-models | Learn about Microsoft Purview billing models | 2026-11-06 |
| S10 | https://learn.microsoft.com/en-us/purview/purview-payg-subscription-based-enablement | Enable Microsoft Purview pay-as-you-go features for new customers | 2026-11-06 |
| S11 | https://learn.microsoft.com/en-us/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description | Microsoft Purview service description | 2026-11-06 |
| S12 | https://learn.microsoft.com/en-us/purview/ai-microsoft-purview-permissions | Permissions for Data Security Posture Management for AI (classic) | 2026-11-06 |
| S13 | https://learn.microsoft.com/en-us/purview/ai-microsoft-purview-considerations | Considerations for DSPM for AI to manage data security and compliance protections for AI interactions (classic) | 2026-11-06 |
| S14 | https://learn.microsoft.com/en-us/purview/data-classification-activity-explorer | Get started with activity explorer | 2026-11-06 |
| S15 | https://learn.microsoft.com/en-us/purview/data-security-posture-management-permissions | Permissions for Data Security Posture Management | 2026-11-06 |
| S16 | https://learn.microsoft.com/en-us/defender-office-365/scc-permissions | Roles and role groups in Microsoft Defender for Office 365 and Microsoft Purview | 2026-11-06 |
| S17 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/add-rolegroupmember | Add-RoleGroupMember | 2026-11-06 |
| S18 | https://learn.microsoft.com/en-us/purview/purview-permissions | Permissions in the Microsoft Purview portal | 2026-11-06 |
| S19 | https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2 | App-only authentication for unattended scripts in Exchange Online PowerShell and Security & Compliance PowerShell | 2026-11-06 |
| S20 | https://learn.microsoft.com/en-us/entra/identity/authentication/concept-mandatory-multifactor-authentication | Mandatory multifactor authentication for Azure and admin portals | 2026-11-06 |
| S21 | https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth-ropc | Microsoft identity platform and OAuth 2.0 Resource Owner Password Credentials | 2026-11-06 |
| S22 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-ippssession | Connect-IPPSSession | 2026-11-06 |
| S23 | https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands | Authentication module cmdlets in Microsoft Graph PowerShell | 2026-11-06 |
| S24 | https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults | Security defaults in Microsoft Entra ID | 2026-11-06 |
| S25 | https://learn.microsoft.com/en-us/entra/identity/conditional-access/managed-policies | Microsoft-managed Conditional Access policies | 2026-11-06 |
| S26 | `https://prices.azure.com/api/retail/prices?$filter=serviceName eq 'Microsoft Purview'&currencyCode=USD` | Azure Retail Prices API, all 712 Microsoft Purview items | 2026-11-06 |
| S27 | https://learn.microsoft.com/en-us/graph/permissions-grant-via-msgraph | Grant or revoke API permissions programmatically (both pivots; SDK tabs skipped) | 2026-11-06 |
| S28 | https://learn.microsoft.com/en-us/graph/api/unifiedroleassignment-delete?view=graph-rest-1.0 | Delete unifiedRoleAssignment | 2026-11-06 |
| S29 | https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-remove-assignment | Remove Microsoft Entra role assignments | 2026-11-06 |
| S30 | https://learn.microsoft.com/en-us/graph/api/authentication-post-temporaryaccesspassmethods?view=graph-rest-1.0 | Create temporaryAccessPassMethod | 2026-11-06 |
| S31 | https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-temporary-access-pass | Configure Temporary Access Pass to register passwordless authentication methods | 2026-11-06 |
| S32 | https://learn.microsoft.com/en-us/purview/create-sensitivity-labels | Create and configure sensitivity labels and their policies | 2026-11-06 |
| S33 | https://learn.microsoft.com/en-us/information-protection/develop/concept-mip-metadata | Microsoft Information Protection SDK - Metadata | 2026-11-06 |
| S34 | https://learn.microsoft.com/en-us/graph/api/tenantdatasecurityandgovernance-processcontent?view=graph-rest-beta | tenantDataSecurityAndGovernance: processContent (beta) | 2026-11-06 |
| S35 | https://learn.microsoft.com/en-us/graph/api/userprotectionscopecontainer-compute?view=graph-rest-1.0 | userProtectionScopeContainer: compute | 2026-11-06 |
| S36 | https://learn.microsoft.com/en-us/graph/permissions-reference | Microsoft Graph permissions reference (the entries for every permission named in this note) | 2026-11-06 |
| S37 | https://learn.microsoft.com/en-us/agent-framework/integrations/by-component/middleware/purview | Microsoft Purview (Agent Framework middleware) | 2026-11-06 |
| S38 | https://learn.microsoft.com/en-us/purview/purview-trial | Learn about the Microsoft Purview Suite trial | 2026-11-06 |
| S39 | https://learn.microsoft.com/en-us/purview/dlp-learn-about-dlp | Learn about data loss prevention | 2026-11-06 |
| S40 | https://learn.microsoft.com/en-us/purview/developer/configurepurview | Configure Data Security Posture Management (DSPM) for AI for custom AI apps | 2026-11-06 |
| S41 | https://learn.microsoft.com/en-us/purview/developer/how-to-test-an-ai-application-integrated-with-purview-sdk | How to test an AI application that uses the Microsoft Purview APIs in Microsoft Graph | 2026-11-06 |
| S42 | https://learn.microsoft.com/en-us/purview/audit-copilot | Audit logs for Copilot and AI applications | 2026-11-06 |
| S43 | https://learn.microsoft.com/en-us/purview/sit-defn-credit-card-number | Credit card number (sensitive information type entity definition) | 2026-11-06 |
| S44 | https://learn.microsoft.com/en-us/purview/audit-search | Search the audit log | 2026-11-06 |
| S45 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-labelpolicy | New-LabelPolicy | 2026-11-06 |
| S46 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-label | New-Label (description, example, and the Name, DisplayName, Tooltip and ContentType parameters) | 2026-11-06 |
| S47 | https://learn.microsoft.com/en-us/purview/dspm-task-mapping | Find familiar tasks that you did in DSPM for AI or in DSPM | 2026-11-06 |
| S48 | https://learn.microsoft.com/en-us/power-platform/developer/plan | Power Apps Developer Plan Guide: Features and Benefits | 2026-11-06 |
| S49 | https://learn.microsoft.com/en-us/power-platform/important-changes-coming | Important changes (deprecations) coming in Power Platform (only the section on unmanaged developer environments and the Power Apps Developer Plan, read in full) | 2026-11-06 |
| S50 | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-featureconfiguration | New-FeatureConfiguration | 2026-11-06 |
| S51 | https://learn.microsoft.com/en-us/purview/dlp-create-deploy-policy | Create and deploy data loss prevention policies | 2026-11-06 |
| S52 | https://learn.microsoft.com/en-us/purview/dlp-create-policy-cc-email | Help prevent sharing credit card numbers through email | 2026-11-06 |
| S53 | https://learn.microsoft.com/en-us/purview/data-security-posture-management-learn-about | Learn about Data Security Posture Management | 2026-11-06 |
| S54 | https://learn.microsoft.com/en-us/purview/register-scan-dataverse | Connect to and manage Microsoft Dataverse in Microsoft Purview | 2026-11-06 |
| S55 | https://learn.microsoft.com/en-us/graph/api/resources/apiapplication?view=graph-rest-1.0 | apiApplication resource type | 2026-11-06 |
| S56 | https://learn.microsoft.com/en-us/purview/communication-compliance-permissions | Assign permissions in Communication Compliance | 2026-11-06 |
| S57 | https://learn.microsoft.com/en-us/graph/api/application-addkey?view=graph-rest-1.0 | application: addKey | 2026-11-06 |
| S58 | https://learn.microsoft.com/en-us/purview/data-security-posture-management-considerations | Considerations for Microsoft Purview Data Security Posture Management | 2026-11-06 |
| S59 | https://azure.microsoft.com/en-us/pricing/details/purview/ | Microsoft Purview consumption pricing (table cells render as "$-"; body text and FAQ read) | 2026-11-06 |
| S60 | https://www.microsoft.com/en-us/security/microsoft-purview-pricing | Microsoft Purview pricing | 2026-11-06 |
| S61 | https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleassignments?view=graph-rest-1.0 | Create unifiedRoleAssignment | 2026-11-06 |

## 1. Status at a glance

| Feature | Status | Date or condition | Source |
| - | - | - | - |
| Graph `processContent` for a user (`/me` or `/users/{id}`), v1.0 | GA | No preview label; not available in China (21Vianet) | S01 |
| Graph `protectionScopes/compute` for a user, v1.0 | GA | No preview label | S35 |
| Tenant-scoped `processContent` for agent interactions (`/security/dataSecurityAndGovernance/processContent`, `evaluationScope.type` = `agent`) | Preview | Graph beta; beta APIs are not supported in production | S34 |
| DLP for Entra-registered AI apps (policy scoped to one app, `EnforcementPlanes` `Application`) | GA (no preview label), PowerShell only | Only SIT-based blocking of prompts is supported; the portal can't create these policies | S03, S05, S06 |
| `EnforcementPlanes` value `Entra` | Retiring | Deprecated; replaced by `Application`; existing policies keep working | S05, S40 |
| Purview pay-as-you-go enablement (subscription-based, new customers) | Preview | Global Administrator only; completion can take a few hours | S10 |
| `New-FeatureConfiguration` (collection policies by PowerShell) | Preview | Public Preview, not available in all organizations | S50 |
| Data Security Posture Management (current version) | GA | Replaces DSPM for AI (classic) and DSPM (classic) | S47, S53 |
| DSPM for AI (classic) | Retiring | Classic version; new features go to the current DSPM only | S12, S13 |
| Purview integration in Microsoft Foundry (**Powered by Microsoft Purview** toggle) | GA (no preview label) | Foundry (new) portal only; per Azure subscription; policies need pay-as-you-go or an Agent 365 subscription | S08 |
| Purview capabilities for agents on Foundry and Entra-connected AI apps under Microsoft 365 E7 and Agent 365 SKUs | Announced, not yet in effect | The service description describes this support in the future tense | S11 |
| Sensitivity labels and label policies by PowerShell (`New-Label`, `New-LabelPolicy`) | GA | Changes take up to 24 hours to propagate | S32, S45, S46 |
| Modern label scheme | GA | Applies to tenants created from October 1, 2025, so to every lab tenant | S32 |
| Mandatory MFA, Phase 1 (Azure portal, Microsoft Entra admin center, Intune admin center; Microsoft 365 admin center) | Enforced | Rolled out from October 2024; Microsoft 365 admin center from February 2025 | S20 |
| Mandatory MFA, Phase 2 (Azure CLI, Azure PowerShell, Azure mobile app, IaC tools, ARM REST, Azure SDK; create, update and delete only) | Enforced | From October 1, 2025; postponement was possible only until July 1, 2026 | S20 |
| Security defaults on new tenants | GA | On by default with a 24-hour grace period; device code flow blocked in new tenants from July 1, 2026 | S24 |
| Microsoft-managed Conditional Access policies | GA | Created in **Report-only**, enabled no less than 30 days later (sometimes sooner) | S25 |
| `Connect-IPPSSession -UseRPSSession` | Retiring | Deprecated in module 3.9.2 or later | S22 |
| `Connect-IPPSSession -AccessToken` | GA (no preview label on the cmdlet page) | Introduced in module 3.8.0-Preview1 | S22 |
| Power Apps Developer Plan developer environments (unmanaged) | Retiring | Creation ends November 15, 2026; suspension from December 15, 2026; deletion from January 15, 2027 | S48, S49 |
| Purview Data Map sensitivity labeling of Dataverse assets | Preview | The Data Map source list marks sensitivity labeling as preview | S54 |

## 2. Navigation and exact click paths

All Purview paths start at the Microsoft Purview portal, https://purview.microsoft.com [S10].

| Page or task | Click path | What the page shows | Source |
| - | - | - | - |
| Enable pay-as-you-go billing | Rocket icon (top right, near **Settings**) > **Get Started**, or **Settings** > **Account details** > select the active Azure subscription > select the resource group | Associates the tenant with an Azure subscription; the billing resource is created in the resource group; the **Country/Region** value is fixed | S10 |
| DLP policies list | **Data loss prevention** solution > **Policies** (> **+ Create policy** to create) | Policies; creation starts with **Enterprise applications & devices** or **Inline web traffic** | S52, S39 |
| DLP activity in Activity explorer | **Data loss prevention** > **Activity explorer** tab; set the activity filter to **DLP rule matched** | DLP events of the last 30 days; preconfigured filters include **DLP policies that detected activities** and **DLP policy rules that detected activities** | S39 |
| Activity explorer (direct link) | https://purview.microsoft.com/informationprotection/dataclassification/activityexplorer | Activities on labeled content and DLP events, up to 30 days | S14 |
| DSPM AI activity | **Solutions** > **DSPM** > **Discover** > **Activity explorer** > **AI activities** tab | Events **AI interaction**, **AI website visit**, **DLP rule match**, **Sensitive info types** | S53, S47, S58 |
| DSPM reports | **DSPM** > **Reports**; AI policies: **DSPM** > **Reports** > **Policies with AI workloads** | Activity and posture reports | S47 |
| DSPM for AI (classic) one-click collection policy | **Solutions** > **DSPM for AI (classic)** > **Recommendations** > **Secure interactions from enterprise apps** | Creates the collection policy **DSPM for AI - Capture interactions for enterprise AI apps** | S06, S13 |
| DSPM for AI (classic) reports | **Reports** > AI app category **Enterprise AI apps** > **View details** | Reports need at least a day of data | S06 |
| Sensitivity labels | **Solutions** > **Information Protection** > **Sensitivity labels** > **+ Create** > **Label** (modern label scheme) | Label list and the label wizard | S32 |
| Label publishing | **Solutions** > **Information Protection** > **Publishing policies**; on the **Label policies** page select **Publish label** | Label policies | S32 |
| Purview role groups | **Settings** > **Roles and scopes** > **Role groups** | Role groups, Microsoft Entra roles, administrative units (needs **Role Management** or Global Administrator to view) | S18 |
| Audit search | **Audit** solution card (or **View all solutions** > **Audit** in **Core**) > **Search**; use **Activities - operations names**, **Record types**, **Workloads** | Audit search jobs and results | S44 |
| Foundry Purview toggle | Foundry (new) portal: **Operate** > **Compliance** > **Data security and governance** tab > subscription dropdown > **Powered by Microsoft Purview** | Sends Foundry interaction data of that subscription to Purview | S08 |
| Remove an Entra role assignment | Microsoft Entra admin center: **Entra ID** > **Roles & admins** > role > select user > **Remove assignment** > **Yes** | Role assignments | S29 |
| Temporary Access Pass policy | **Entra ID** > **Authentication methods** > **Policies** > **Temporary Access Pass** > **Enable** (> **Configure**) > **Save** | TAP policy, scope, lifetime | S31 |
| Create a Temporary Access Pass | **Entra ID** > **Users** > user > **Authentication methods** > **Add authentication method** > **Temporary Access Pass** > **Add** | Shows the pass once | S31 |
| Confirm mandatory MFA enforcement | https://aka.ms/managemfaforazure (Phase 1) and https://aka.ms/postponePhase2MFA (Phase 2), as Global Administrator | Enforcement banner | S20 |

Older or alternate names still found in the documentation: **DSPM for AI (classic)** and **Data Security Posture Management (classic)** for the earlier versions of **DSPM** [S53]; **Microsoft Purview Suite** was formerly **Microsoft 365 E5 Compliance** [S38, S44] (one microsoft.com page gives the former name as Microsoft E5 Compliance Suite [S60]); the Foundry roles **Foundry Account Owner** and **Azure AI Account Owner** are the same role after a rename [S08]; the enforcement plane `Entra` is now `Application` [S05, S40]. Treat **DSPM**, **Microsoft Purview Suite**, **Foundry Account Owner** and `Application` as current, because the cited pages call the older names previous or deprecated.

## 3. How Purview can protect what the agent receives

- Purview offers three integration routes for Foundry or custom AI apps: the native Foundry integration, the Purview APIs in Microsoft Graph, and Microsoft Agent Framework middleware [S07, S37, S06].
- **Native Foundry integration:** a Foundry Account Owner turns on **Powered by Microsoft Purview** per Azure subscription; interaction data of all apps and agents in that subscription flows to Purview [S08]. Data security policies apply only to calls that use Microsoft Entra ID user-context authentication against Foundry's managed inference endpoint (`/chat/completions`); other calls are visible in Audit and DSPM classifications but are not enforced [S08]. Policies need pay-as-you-go meters or an Agent 365 subscription, otherwise only Purview Audit works; network isolation isn't supported yet; a Purview license must exist in the tenant [S08].
- **Purview APIs (the route this lab uses):** an app registered in Entra calls **Compute protection scopes** and **Process content**; Purview then treats it as an Entra-registered AI app [S06, S03]. Managing these interactions requires pay-as-you-go billing [S06]. DLP support for these apps is limited to a policy that blocks prompts based on sensitive information types, configured with PowerShell and scoped to the specific app [S06, S07].
- **Agent Framework middleware:** prerequisites are a Microsoft 365 subscription with an E5 license and pay-as-you-go billing [S37]. Policy evaluation fails closed when the middleware can't resolve a user ID, tenant or application location [S37].
- **Preview alternative:** a tenant-scoped `processContent` evaluates content exchanged between a protected agent and users, agents or tools, with `policyLocationAgent` and `activityMetadata.participants`; it needs `Content.Process.All` and is a beta API [S34].
- Lab decision (derived from S06, S08): keep the MCP server as the integration point. The agent reaches tools through Foundry Agent Service, and the native toggle enforces policies only on user-context `/chat/completions` calls, so tool output is protected only if the server itself calls `processContent` before returning ticket text, notes or documents. The Foundry toggle remains an optional extra for audit visibility of Foundry interactions [S07, S08].

## 4. The processContent contract for the MCP server

### 4.1 Endpoints and permissions

| Call | HTTP | Least privileged permission | Higher permission | Source |
| - | - | - | - | - |
| Process content for the signed-in user | `POST /me/dataSecurityAndGovernance/processContent` (delegated only) | `Content.Process.User` | `Content.Process.All` | S01 |
| Process content for a given user | `POST /users/{userId}/dataSecurityAndGovernance/processContent` (delegated or application) | `Content.Process.User` | `Content.Process.All` | S01 |
| Compute protection scopes for a user | `POST /users/{usersId}/dataSecurityAndGovernance/protectionScopes/compute` (or `/me/...`) | `ProtectionScopes.Compute.User` | `ProtectionScopes.Compute.All` | S35 |
| Log activity when no scope applies | Content activity API | `ContentActivity.Write` | none listed | S03, S36 |

Permission identifiers (application / delegated), all with admin consent required [S36]:

| Permission | Application ID | Delegated ID |
| - | - | - |
| `Content.Process.User` | `24ceb246-ad29-4680-90b4-3e91ffad15eb` | `1d787a13-f750-4ad6-875a-fcbd2725596b` |
| `Content.Process.All` | `5ad511bf-571c-4ef6-8c3c-85b94b85df98` | `7e2467d1-f874-46bb-828e-24cb06b29d3f` |
| `ProtectionScopes.Compute.User` | `fe696d63-5e1f-4515-8232-cccc316903c6` | `4fc04d16-a9fc-4c5e-8da4-79b6c33638a4` |
| `ProtectionScopes.Compute.All` | `e5a76501-dbb0-492c-ab55-5d09e8837263` | `98f5a27a-539a-48bc-a597-f78e9e1e76bf` |

The tutorial's own example assigns `Content.Process.User` and `ProtectionScopes.Compute.User` to the app [S03].

### 4.2 Request body and headers

| Field | Value for this lab | Source |
| - | - | - |
| `contentEntries[].@odata.type` | `microsoft.graph.processConversationMetadata` (text); `processFileMetadata` exists for files | S01 |
| `contentEntries[].content` | `{"@odata.type": "microsoft.graph.textContent", "data": "<tool output text>"}` | S01 |
| `contentEntries[]` metadata | `identifier`, `name`, `correlationId`, `sequenceNumber`, `isTruncated`, `createdDateTime`, `modifiedDateTime` | S01 |
| `contentEntries[].agents[]` | `microsoft.graph.aiAgentInfo` with `blueprintId`, `identifier`, `name`, `version` | S01 |
| `activityMetadata.activity` | `uploadText` (text sent to the AI); others are `downloadText`, `uploadFile`, `downloadFile` | S03 |
| `deviceMetadata` | `deviceType`, `operatingSystemSpecifications` (`operatingSystemPlatform`, `operatingSystemVersion`), `ipAddress` | S01 |
| `protectedAppMetadata.applicationLocation` | `{"@odata.type": "microsoft.graph.policyLocationApplication", "value": "<Entra application (client) ID>"}` | S01 |
| `integratedAppMetadata` | `name`, `version` | S01 |
| Header `Client-Request-Id` | GUID recommended; echoed back in the response | S01 |
| Header `If-None-Match` | The `ETag` cached from `protectionScopes/compute` | S01, S03 |

Threads: use one `correlationId` per conversation thread and increment `sequenceNumber` per message [S03].

### 4.3 Response and required app behavior

- Success is `200 OK` with a `processContentResponse` (`protectionScopeState`, `policyActions`, `processingErrors`), or `202 Accepted` / `204 No Content` without a body [S01]. A block arrives as a `restrictAccessAction` with `action` `restrictAccess` and `restrictionAction` `block` [S01].
- `protectionScopeState` `modified` (with a changed `ETag`) means the app must call `protectionScopes/compute` again and cache the new `ETag` [S01, S03]. If 60 minutes have passed since the last `processContent` call, Microsoft recommends recomputing the scopes [S03].
- `restrictAccess` means the app must block the requested activity; an agent must also block before calling another agent [S03].
- Execution modes: `evaluateInline` means wait for the verdict before continuing; `evaluateOffline` means don't wait [S02, S03]. If compute always returns `evaluateOffline`, Microsoft says to check that the DLP policy was created with `New-DlpComplianceRule` and appears enabled in **DSPM** > **Collection policies**, because policies created in the portal don't apply to Entra-registered apps [S03].
- An empty scope list means no policy applies to that user and activity; Microsoft recommends logging the activity with the Content activity API instead [S03].
- There are no Purview APIs to extract data or analytics out of Purview [S03], so neither the MCP server nor a validation script can read the DLP event back through these APIs (derived from S03; audit search is covered in section 6).
- No size limit or throttling limit for `processContent` text appears in the API or tutorial pages [S01, S03] (see OPEN QUESTIONS).

### 4.4 Re-verification of the previous build (`purview.py`)

| Previous behavior | Verdict | Source |
| - | - | - |
| Posts to `/users/{oid}/dataSecurityAndGovernance/processContent` with `uploadText`, `processConversationMetadata`, `textContent`, `policyLocationApplication` = the Purview app's client ID, `aiAgentInfo`, `Client-Request-Id` = correlation ID | Consistent with the documented request | S01, S03 |
| Treats `202`/`204` as no decision (allow) and `restrictAccess`/`block` as withhold | Consistent with the documented responses | S01 |
| Fails closed when Purview can't be reached | Consistent with Microsoft's middleware behavior | S37 |
| Uses the application permission `Content.Process.All` | Works, but `Content.Process.User` is the least privileged option for the same call | S01 |
| Never calls `protectionScopes/compute`, never sends `If-None-Match`, ignores `protectionScopeState` | Gap against the documented flow | S03 |
| `aiAgentInfo` without `blueprintId` | The v1.0 example includes `blueprintId`; add the agent's Entra Agent ID values when known | S01 |
| Truncates text at 15,000 characters and sets `isTruncated` | The field exists; no limit is documented, so keep and test | S01 |

## 5. DLP policy for the MCP server's app

### 5.1 Facts

- The Microsoft Purview portal doesn't support creating DLP policies for Entra-registered applications; the policy must be created with `New-DlpComplianceRule` (and `New-DlpCompliancePolicy`) in Security & Compliance PowerShell [S03].
- The documented example scopes the policy with `-Locations` (`Workload` `Applications`, `Location` = the Entra app ID, `LocationSource` `Entra`, `LocationType` `Individual`, inclusion `Tenant`/`All`) and `-EnforcementPlanes @("Application")`, then adds a rule with `-ContentContainsSensitiveInformation @{Name = "credit card number"}` and `-RestrictAccess @(@{setting="UploadText";value="Block"})` [S04].
- `EnforcementPlanes` valid values are `Browser`, `CopilotExperiences`, `Application` (for Entra-registered enterprise apps; replaces the deprecated `Entra`) and `Network` [S05].
- `-Mode` accepts `Enable` (default), `Disable`, `TestWithNotifications` and `TestWithoutNotifications` [S05]. `-WhatIf` doesn't work in Security & Compliance PowerShell [S05].
- Every rule needs one condition and one action [S04]. `-ContentContainsSensitiveInformation` takes hash tables such as `@{Name="Credit Card Number"}` with optional `minCount`, and can also reference sensitivity labels [S04].
- The reference page for `-RestrictAccess` (and `-MipRestrictAccess`) has no description yet, only a placeholder [S04]. `-GenerateAlert` and `-GenerateIncidentReport` accept email addresses or `SiteAdmin` [S04].
- In general, DLP policies take effect about an hour after being turned on [S39].
- A collection policy (scenario `KnowYourData`) for enterprise AI apps can be created with `New-FeatureConfiguration -FeatureScenario KnowYourData`, `EnforcementPlanes` `Application`, `IsIngestionEnabled` true and the location `ee1680d0-702f-4090-b26c-c49091e86531` (`LocationSource` `Entra`, `LocationType` `Group`) [S40]; the cmdlet is Public Preview and not available in all organizations [S50]. The same policy comes from the DSPM one-click recommendation [S06, S40].

### 5.2 Script shape (adapted from S04 Example 4 and S40; names are lab placeholders)

```powershell
# Security & Compliance PowerShell session already open (section 9)
$appId   = '<Application (client) ID of the Relecloud Service Desk Purview Integration app>'
$appName = 'Relecloud Service Desk Purview Integration'
$locations = "[{`"Workload`":`"Applications`",`"Location`":`"$appId`",`"LocationDisplayName`":`"$appName`",`"LocationSource`":`"Entra`",`"LocationType`":`"Individual`",`"Inclusions`":[{`"Type`":`"Tenant`",`"Identity`":`"All`"}]}]"
New-DlpCompliancePolicy -Name 'Relecloud Service Desk card numbers' -Mode Enable -Locations $locations -EnforcementPlanes @('Application')
New-DlpComplianceRule -Name 'Block card numbers sent to the agent' -Policy 'Relecloud Service Desk card numbers' `
    -ContentContainsSensitiveInformation @{Name = 'Credit Card Number'} `
    -RestrictAccess @(@{setting = 'UploadText'; value = 'Block'})

# Optional collection policy so AI interactions are stored and visible (Public Preview cmdlet)
New-FeatureConfiguration -FeatureScenario KnowYourData -Name 'DSPM for AI - Collection policy for enterprise AI apps' -Mode Enable `
    -ScenarioConfig '{"Activities": ["UploadText", "DownloadText"], "EnforcementPlanes": ["Application"], "SensitiveTypeIds": ["All"], "IsIngestionEnabled": true}' `
    -Locations '[{"Workload": "Applications","Location": "ee1680d0-702f-4090-b26c-c49091e86531","LocationSource":"Entra","LocationType":"Group","Inclusions": [{"Type": "Tenant","Identity": "All"}]}]'
```

### 5.3 The Credit Card Number sensitive information type and the seed data

- Format: 14 to 19 digits, formatted or not; must pass the Luhn test and match the formats of major card brands [S43].
- Reserved card numbers that financial institutions use for testing are not flagged [S43].
- High confidence (85) needs, within 300 characters, a keyword from `Keyword_cc_verification` or `Keyword_cc_name` (for example `card number`, `credit card`, `expiration date`, `cvv2`) or a date that `Func_expiration_date` recognizes; low confidence (65) needs only the pattern and checksum [S43].
- Seed-data rule (derived from S43 and S01): don't use well-known test card numbers; use a Luhn-valid number in a major brand format that Microsoft's own examples use (the Graph examples send `4532667785213500` [S01, S03]) and put "card number" and an expiration date next to it, so the note on the seeded ticket matches at high confidence.
- Activity explorer supports keyword highlighting for this type in the **Contextual Summary** view [S43].

## 6. Where the DLP event appears, and when

### 6.1 Surfaces

| Surface | What a block from processContent should produce | Source |
| - | - | - |
| **Data loss prevention** > **Activity explorer** | DLP events for 30 days; the activity **DLP rule matched** lists items that matched a rule; `DLPRuleMatch` events carry the surrounding text (**Contextual summary**) | S39 |
| Activity explorer (Information Protection) | Built from the unified audit log; about 50 filters (date range, activity type, location, sensitivity label, user, and more) and filter sets such as **DLP policies that detected activities** | S14 |
| **DSPM** > **Discover** > **Activity explorer** > **AI activities** | **DLP rule match** when a DLP rule matched during an interaction; **AI interaction** with prompts and responses only when a collection policy captures content; **Sensitive info types** | S53, S58 |
| Audit | Interactions with custom or third-party apps registered in the organization use record type and operation `ConnectedAIAppInteraction`, workload `ConnectedAIApp`, `AppIdentity` `ConnectedAIApp.Entra.<AppId>` | S42, S41 |
| eDiscovery | Search `ItemClass` `IPM.SkypeTeams.Message.ConnectedAIApp.Entra.<AppID>` | S06, S41 |
| DLP alerts | Only if the rule raises alerts; alerts stay 30 days in the Purview dashboard and six months in the Defender portal | S39 |

Display caveat: **AI interaction** events show no prompt or response when the user has no Exchange Online mailbox [S58]. Viewing prompts and responses needs the **Content Explorer Content Viewer** or **Data Security AI Content Viewer** role (section 12) [S15].

### 6.2 Audit specifics

- Audit for non-Microsoft AI applications uses pay-as-you-go billing (record type `AIAppInteraction`, workload `AIApp`), and some scenarios logged as `ConnectedAIAppInteraction` are also pay-as-you-go; Microsoft applications, including custom apps built with Copilot Studio and Microsoft Foundry, stay in Audit (Standard) [S42].
- Searching the audit log needs the **Audit Logs** or **View-Only Audit Logs** role; a custom role group with one of them also works [S44]. The underlying cmdlet `Search-UnifiedAuditLog` runs in Exchange Online PowerShell [S44].
- Default audit retention is 180 days for non-E5 users, one year for Entra ID, Exchange and SharePoint activity of E5 or Purview Suite users [S44].

### 6.3 Latency

| Signal | Documented latency | Source |
| - | - | - |
| Activity explorer entries | Not real time; for core services (Exchange, SharePoint, OneDrive, Teams) 60 to 90 minutes; other services can take longer; no guaranteed time | S14 |
| Audit records | Same: typically 60 to 90 minutes for core services, longer for others, no commitment | S44 |
| Test data from an app integrated with the Purview APIs | A few minutes for the data to land in Purview (developer test page) | S41 |
| DSPM and DSPM for AI reports | Wait at least a day | S06, S40 |
| First-time DSPM setup | Allow a day or so before data shows | S53 |
| DLP policy after it is turned on | About an hour | S39 |

The current guide note in `exercise-6.md`, which promises Activity explorer events within 30 minutes, is not supported by these pages; see OPEN QUESTIONS.

## 7. Sensitivity label and the labeled customer document

### 7.1 Create and publish by script

- Security & Compliance PowerShell can script everything the labeling admin center does: `New-Label`, `New-LabelPolicy`, `Set-Label`, `Set-LabelPolicy`, `Remove-Label`, `Remove-LabelPolicy` [S32].
- `New-Label -Name <unique, max 64 characters> -DisplayName <shown in Office and other clients> -Tooltip <description> -ContentType "File, Email"`; `ContentType` values are `File`, `Email`, `Site`, `UnifiedGroup`, `PurviewAssets`, `Teamwork`, `SchematizedData` [S46].
- `New-LabelPolicy -Name <max 64 characters> -Labels <names or GUIDs> -ExchangeLocation <mailboxes>`; `-ExchangeLocationException` applies when `-ExchangeLocation` is `All` [S45].
- Microsoft recommends referencing labels by GUID; `Get-Label | Format-Table -Property DisplayName, Name, Guid, ContentType` lists them [S32].
- New customers might get default labels and a default label policy created automatically [S32], so the script must check for an existing label with the same display name before creating one (derived from S32).

```powershell
# Adapted from S46 and S45; names are lab placeholders
New-Label -Name 'Relecloud-Confidential' -DisplayName 'Confidential' -Tooltip 'Relecloud customer configuration data.' -ContentType 'File, Email'
New-LabelPolicy -Name 'Relecloud lab label policy' -Labels 'Relecloud-Confidential' -ExchangeLocation '<senior technician UPN>','<tier 1 technician UPN>'
(Get-Label -Identity 'Relecloud-Confidential').Guid   # the GUID the MCP server compares against
```

### 7.2 Propagation

- Allow 24 hours for new labels and label policy settings to reach all services; new or deleted labels for Office for the web can appear within the hour; changes that depend on group membership can take 24 to 48 hours [S32].
- Editing a published label also takes up to 24 hours to replicate [S32].

### 7.3 How a .docx carries the label

- Label metadata is a set of key/value pairs named `MSIP_Label_<label GUID>_<attribute>`; `Enabled` (true or false) and `SiteId` (the Entra tenant ID) are mandatory; `Method`, `SetDate`, `Name` (the label's unique name), `ContentBits` and `ActionId` (removed in MIP SDK 1.8 and later) are optional [S33].
- When co-authoring for files encrypted with sensitivity labels is enabled, Word, Excel and PowerPoint store the metadata in the LabelInfo location instead of the legacy custom document properties, and custom attributes go to `custom.xml` [S33].
- Consequence for the MCP server (derived from S33): read both locations (`docProps/custom.xml` and the LabelInfo part), match `Enabled` = true for the restricted label GUID, and treat the GUID as tenant specific, because every lab tenant creates its own label.
- For Entra-registered apps, DLP supports only sensitive-information-type blocking of prompts [S06], so a label condition in the DLP rule is not a documented option for this app even though `-ContentContainsSensitiveInformation` accepts labels in general [S04]. The labeled document therefore stays blocked by the MCP server's own label check, and its text can additionally be sent to `processContent` (derived from S04, S06).

### 7.4 Is Purview scanning of the file in Dataverse relevant?

No (derived from S54 and S59). Purview Data Map can register and scan a Dataverse environment, but it extracts technical metadata (environment, tables, columns), needs a Microsoft Purview account managed in the classic governance portal with **Data Source Administrator** and **Data Reader** roles, and a Dataverse application user with the **Service Reader** role [S54]. Sensitivity labels and classifications then apply to Data Map assets, not to the bytes the MCP server returns [S54], and Data Map scanning is billed per vCore hour [S59].

## 8. Pay-as-you-go billing and meters

### 8.1 When it is required, and how it is enabled

- Required for: AI interactions of Entra-registered AI apps [S06]; policies on Foundry interactions [S07, S08]; DSPM for AI apps other than Microsoft 365 Copilot and Microsoft Facilitator [S13].
- Model: consumption billing through Azure; the Microsoft 365 tenant must be associated with an active Azure subscription; one Azure bill per month for all Purview pay-as-you-go charges [S09]. Consumption shows in the Azure portal under **Cost Management + Billing** [S10].
- Prerequisites: an Azure subscription in the same tenant as Purview, a resource group in it, and one of the service plans `MIP_S_Exchange` or `EXCHANGE_S_FOUNDATION` [S10].
- Who: only an account in the Global Administrator role can enable it [S10]. (The pricing FAQ says Global Administrator or Purview Administrator can give the consent that existing customers need [S59]; see OPEN QUESTIONS.)
- How: the portal flow in section 2; the billing resource is created in the chosen resource group; completion can take a few hours; the feature is in preview [S10]. No API, PowerShell or ARM procedure for this enablement appears in the pages read [S10, S09].
- The pay-as-you-go meters are only for data security capabilities on non-Microsoft 365 data sources and don't change E3 or E5 entitlements [S59].

### 8.2 Meters this lab can touch (Azure Retail Prices API, USD, retrieved 2026-11-06)

Each meter had one price in every region returned (37 regions for each meter below except the processing unit, which had 27; all include `eastus2` and `swedencentral`) [S26].

| Product / SKU / meter name | Unit | Retail price | Applies here when | Source |
| - | - | - | - | - |
| Microsoft Purview Data Security / In Transit Protection / **In Transit Protection Request** (meterId `075fd082-46d8-5c91-84df-5746da72bc23`, effective 2025-10-01) | 1 request | 0.00005 (0.50 per 10K) | Requests detected within the scope of a Purview policy; for most GenAI apps a prompt and a response are two requests | S26, S59 |
| Microsoft Purview Data Compliance / Audit Standard / **Audit Standard Asset** (meterId `08d12a66-396a-5388-aec3-b70cdbd49530`) | 1K records | 0.015 (15 per 1M) | Audit records of non-Microsoft AI apps | S26, S59, S42 |
| Microsoft Purview Data Compliance / Data Lifecycle Management Premium / **Data Lifecycle Management Premium Asset** | 1K per day | 0.0002 (6 per 1M per month) | Only if a retention policy covers AI interactions | S26, S59 |
| Microsoft Purview Data Compliance / Communication Compliance Standard / **Communication Compliance Standard Asset** | 1K text records | 0.30 | Only if a communication compliance policy covers AI interactions | S26, S59 |
| Microsoft Purview Data Security / Standard / **Standard Data Security Processing Unit** | 1 unit | 25.00 | Only for Insider Risk Management pay-as-you-go indicators | S26, S09 |

The billing-model page lists **Data Security for Gen AI Applications** as counting requests or messages for non-Microsoft 365 AI interactions [S09], but no page read ties `processContent` calls of an Entra-registered app to a named meter (see OPEN QUESTIONS).

Cost judgment (derived from S26): at 0.00005 per request, 2,000 checks per tenant cost 0.10 USD, and 2,000 audit records cost 0.03 USD, so Purview consumption is negligible next to the per-user licenses.

## 9. Unattended automation in a fresh tenant: what can sign in

### 9.1 What enforces MFA

- Phase 1 of mandatory MFA covers any create, read, update or delete in the Azure portal, Microsoft Entra admin center and Intune admin center, and sign-in to the Microsoft 365 admin center [S20]. Phase 2 covers create, update and delete through Azure CLI, Azure PowerShell, the Azure mobile app, IaC tools, ARM REST and the Azure SDK; reads don't need MFA [S20]. Phase 2 started October 1, 2025, and postponement was possible only until July 1, 2026 [S20].
- Managed identities and service principals are not affected by either phase; user accounts used for automation must sign in with MFA [S20]. There is no exception for test tenants and no opt-out [S20].
- Microsoft Graph: "Generally, Microsoft Graph APIs aren't in scope for Azure MFA enforcement." [S20] Only requests to `https://management.azure.com/` are in scope of the Azure enforcement [S20]. Security & Compliance PowerShell and the Microsoft Purview portal are not in the enforcement tables [S20].
- The ROPC grant is incompatible with MFA; ROPC-based APIs throw once MFA applies, and the username/password APIs in MSAL and Azure Identity are deprecated (for example Python `msal` `acquire_token_by_username_password` for public clients from 1.35.0, and `UsernamePasswordCredential` in `azure-identity` from 1.21.0) [S20].
- Security defaults: on by default in new tenants with a 24-hour grace period; they require administrators (Global Administrator and the other listed admin roles, including Privileged Role Administrator and Application Administrator) to do MFA at every sign-in after registration, block legacy authentication, block device code flow, and require MFA for Azure Resource Manager access (Azure portal, Entra admin center, Azure PowerShell, Azure CLI) but not for Microsoft Graph [S24].
- Microsoft-managed Conditional Access policies (for example **Multifactor authentication for admins accessing Microsoft Admin portals**, **Multifactor authentication for all users**, **Block device code flow**) are created in report-only mode and turned on no less than 30 days later unless the tenant is told otherwise; they need Microsoft Entra ID P2 or Business Premium [S25].

### 9.2 Sign-in options per tool

| Tool | Password of a user (no MFA) | Interactive or TAP | App-only (certificate) | Source |
| - | - | - | - | - |
| Microsoft Graph PowerShell (`Connect-MgGraph`) | No password parameter; delegated access is interactive, device code, or `-AccessToken` | Yes (interactive); device code is blocked by security defaults | Yes: `-ClientId -TenantId -CertificateThumbprint` (or `-CertificateName`, `-Certificate`), also client secret and managed identity | S23, S24 |
| Microsoft Graph REST with a token from ROPC | Works only while no MFA requirement applies to the account; accounts without a password can't use ROPC, and a Temporary Access Pass doesn't replace the password | n/a | Microsoft recommends service principal authentication when no user context is available | S21, S31 |
| Security & Compliance PowerShell (`Connect-IPPSSession`) | `-Credential`, which Microsoft says not to use for accounts that use MFA | Yes (`-UserPrincipalName`, modern auth with or without MFA) | Yes: `-AppId -CertificateThumbprint` (Windows only) or `-Certificate`, plus `-Organization <tenant>.onmicrosoft.com`; `-AccessToken` from module 3.8.0-Preview1 | S22, S19 |
| Azure CLI and Azure PowerShell (ARM writes) | Blocked for create, update and delete (Phase 2) | MFA required | Service principal or managed identity, not affected | S20 |
| Azure portal, Entra admin center, Microsoft 365 admin center | No | MFA required (Phase 1) | n/a | S20 |

### 9.3 App-only Security & Compliance PowerShell setup

- Module version 3.0.0 or later for `Connect-IPPSSession` [S19].
- API permission: **Microsoft Exchange Online Protection** > **Exchange.ManageAsApp** (application), with tenant-wide admin consent; in the manifest this is `resourceAppId` `00000007-0000-0ff1-ce00-000000000000`, role ID `455e5cd2-84e8-4751-8344-5672145dfa17` [S19].
- Certificate: self-signed is fine; CNG certificates are not supported, so create it with a CSP key provider (for example `New-SelfSignedCertificate ... -KeySpec KeyExchange`) [S19].
- Roles: assign the app a supported Entra role; for Security & Compliance PowerShell these are Compliance Administrator, Global Administrator, Global Reader, Security Administrator and Security Reader [S19]. Alternatively, register the app with `New-ServicePrincipal` inside a connected session and add it to a custom role group with `Add-RoleGroupMember` [S19].
- App-only authentication is unsupported for eDiscovery cmdlets [S19]; DLP, label and role group cmdlets are not on that list [S19].
- Role coverage (from the role tables): the **Compliance Administrator** role group, which the Entra Compliance Administrator role maps to [S18], contains **DLP Compliance Management** and **Information Protection Admin** (create, edit and delete DLP policies, sensitivity labels and their policies) but not **Role Management** and not **Sensitivity Label Administrator** [S16]. **Role Management** (needed to change role group membership) is only in **Organization Management** and **Purview Administrators** [S16, S17]. Global administrators are added to **Organization Management** automatically [S16].

### 9.4 Answers to the brief

- (a) A Global Administrator password, unattended: Graph calls are outside the Azure MFA enforcement [S20], but Graph PowerShell has no password parameter [S23], so a token must come from ROPC [S21] and that works only while security defaults and every Conditional Access policy leave the account without an MFA requirement [S21, S24, S25]; `Connect-IPPSSession -Credential` has the same limit [S22]; Azure CLI writes are blocked [S20].
- (b) App-only certificate authentication is supported for Graph PowerShell [S23] and Security & Compliance PowerShell (Exchange.ManageAsApp plus an Entra role such as Compliance Administrator) [S19], and workload identities are outside both MFA phases [S20]. This is the safe path (derived from S19, S20, S21).

## 10. Microsoft Entra operations the setup script performs

### 10.1 App registrations and a delegated scope

- An application exposes delegated permissions through `api.oauth2PermissionScopes`; `api.requestedAccessTokenVersion` (1, 2 or null) sets the access token format; `preAuthorizedApplications` and `knownClientApplications` control consent for client apps [S55].
- Certificates are added with **Create application** or **Update application**; `addKey` needs a proof-of-possession token signed by an existing valid certificate, so it fails on an app that has none yet [S57].
- `Application.ReadWrite.All` creates and updates applications and service principals and manages app role assignments, except those exposed by Microsoft Graph, and doesn't manage delegated permission grants; `Application.ReadWrite.OwnedBy` limits this to apps the caller owns [S36].

### 10.2 Tenant-wide admin consent by Graph

- Delegated permissions (for example the gateway's `ServiceDesk.Access`, and `openid profile offline_access` on Microsoft Graph): `POST /oauth2PermissionGrants` with `clientId` (client service principal object ID), `consentType` `AllPrincipals`, `resourceId` (resource service principal object ID) and `scope`; with `AllPrincipals`, `principalId` is null; `PATCH` changes the scope list; `DELETE` revokes [S27]. Needs `DelegatedPermissionGrant.ReadWrite.All` (delegated or application) [S27, S36].
- Application permissions (for example `Content.Process.User` for the Purview integration app): `POST /servicePrincipals/{resource-sp-id}/appRoleAssignedTo` with `principalId`, `resourceId` and `appRoleId` [S27]. Needs `AppRoleAssignment.ReadWrite.All` (plus `Application.Read.All` to read app roles) [S27, S36].
- Grants made this way take effect immediately and aren't reviewed [S27].

### 10.3 Directory role assignment and removal

- Assign: `POST /roleManagement/directory/roleAssignments` with `roleDefinitionId` (template ID or directory-specific ID), `principalId` and `directoryScopeId` `/`; needs `RoleManagement.ReadWrite.Directory`; Privileged Role Administrator is the least privileged role for delegated calls [S61].
- Remove: list the principal's assignments to find the ID, then `DELETE /roleManagement/directory/roleAssignments/{id}` (`204 No Content`; `404` if already gone); needs `RoleManagement.ReadWrite.Directory` (delegated or application), Privileged Role Administrator for delegated calls [S28, S29].
- Restriction: a Global Administrator can't remove their own Global Administrator assignment; Graph returns `400 Bad Request` with the message `Removing self from Global Administrator built-in role is not allowed`, to prevent a tenant with zero Global Administrators; removing other roles from yourself is allowed [S29]. So the step that removes the participant's Global Administrator role must run as a different principal (derived from S29).
- The remove-assignment page lists Microsoft Entra ID P1 or P2 and Privileged Role Administrator as prerequisites [S29].

### 10.4 Temporary Access Pass

- `POST /users/{id | userPrincipalName}/authentication/temporaryAccessPassMethods` with optional `isUsableOnce`, `lifetimeInMinutes` (10 to 43,200) and `startDateTime`; a user has one usable pass at a time [S30]. The application permission `UserAuthMethod-TAP.ReadWrite.All` reads and writes passes for all users [S36] (the API page's table lists read permissions as least privileged; see OPEN QUESTIONS) [S30].
- For delegated calls on another user, Authentication Administrator (members) or Privileged Authentication Administrator (admins and members) is required [S30, S31].
- The method must be enabled in the Authentication methods policy by an Authentication Policy Administrator; defaults: minimum lifetime 1 hour, maximum 8 hours, default 1 hour, one-time use false, length 8 [S31]. Only users in the policy scope can sign in with a pass; changes take a few minutes to replicate; tokens issued during a pass sign-in are capped at the pass expiry at issuance [S31].
- Policy changes by Graph need `Policy.ReadWrite.AuthenticationMethod` [S36].

### 10.5 Re-verification of the previous build (`Initialize-LabTenant.ps1`)

- The gateway app (scope `ServiceDesk.Access`, `requestedAccessTokenVersion` 2, `api://<appId>` identifier URI), the `AllPrincipals` grants and the `appRoleAssignedTo` grant for the Purview app all match the documented Graph objects [S27, S55].
- What must change for one tenant per participant (derived from S19, S20, S23): the script signed in interactively (`Connect-MgGraph -Scopes ...`) once per shared tenant and printed client secrets; it now has to run unattended per tenant, prefer certificates over secrets, request `Content.Process.User` instead of `Content.Process.All` [S01], and create the DLP policy, label and role group memberships that were manual steps before [S03, S32, S17].

## 11. Recommended tenant setup sequence (derived)

Derived from S10, S16, S17, S19, S20, S21, S23, S24, S27, S29, S32, S39, S61. Identity rule: everything runs as a workload identity with a certificate; a user password, if used at all, only bootstraps that identity once.

| Step | Who and how | What | Source |
| - | - | - | - |
| 0 | CloudLabs platform | Tenant, Azure subscription in the tenant, users from the user-creation JSON with licenses | planned environment |
| 1 | Operator in the Purview portal as a Global Administrator (TAP sign-in), per tenant | Enable pay-as-you-go: subscription and resource group; wait for completion (hours) | S10 |
| 2 | Bootstrap identity: preferably a platform-provided service principal with directory roles; otherwise one ROPC token of the Global Administrator, only if no MFA requirement applies | Create the "Relecloud Lab Provisioning" app and service principal; generate a CSP certificate on the VM and add its public key through Create or Update application | S21, S24, S57, S19 |
| 3 | Bootstrap identity (Graph) | Grant the provisioning app `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `User.Read.All`; grant **Exchange.ManageAsApp** (Microsoft Exchange Online Protection); assign it the Entra Compliance Administrator role | S27, S36, S19, S61 |
| 4 | Bootstrap identity (its own Security & Compliance PowerShell session) | `New-ServicePrincipal` for the provisioning app and `Add-RoleGroupMember -Identity 'Purview Administrators'` so it holds **Role Management** (or do step 7 in this delegated session) | S19, S16, S17 |
| 5 | Provisioning app, app-only Graph | Gateway app with `ServiceDesk.Access`, `api://<appId>`, token v2, redirect URI; `AllPrincipals` grants; Purview integration app with `Content.Process.User` and `ProtectionScopes.Compute.User` (application) and consent; certificates instead of secrets, stored in Key Vault | S27, S55, S36, S01, S35 |
| 6 | Provisioning app, app-only Security & Compliance PowerShell | Label and label policy (section 7.1); DLP policy and rule scoped to the Purview integration app (section 5.2); optional collection policy | S32, S45, S46, S04, S05, S40 |
| 7 | Principal holding **Role Management** | `Add-RoleGroupMember` for both participants (section 12) | S16, S17 |
| 8 | Provisioning script | Label the seeded .docx with this tenant's label GUID and tenant ID; load it into Dataverse | S33 |
| 9 | Provisioning app, app-only Graph | Readiness: `protectionScopes/compute` for each participant; one `processContent` call with seeded card text for the Senior Technician must return `restrictAccess`/`block`; the same call should also leave a DLP event to find later (derived; confirm in the pilot) | S35, S01, S03 |
| 10 | Provisioning app, app-only Graph | Remove the participant's Global Administrator assignment (`DELETE /roleManagement/directory/roleAssignments/{id}`) and verify; keep a supplier-only Global Administrator so the tenant never has zero | S28, S29 |
| 11 | Provisioning app or platform | Temporary Access Passes and TAP policy lifetime that covers the 4-hour window and the 24-hour reviewer access | S30, S31 |
| 12 | Provisioning app | Remove its own privileged app roles and Entra roles, delete its certificate credential (or the app) | S27, S28 |

Timing (derived from S10, S32, S39, S56): run steps 1 to 12 at least 24 hours before the workshop because labels need up to 24 hours, DLP about an hour, role group permissions up to 30 minutes (documented for the communication compliance role groups) and pay-as-you-go a few hours.

```http
# Adapted from S27, S29 and S61; IDs are placeholders
POST https://graph.microsoft.com/v1.0/servicePrincipals/{graph-sp-object-id}/appRoleAssignedTo
{ "principalId": "{purview-app-sp-object-id}", "resourceId": "{graph-sp-object-id}", "appRoleId": "24ceb246-ad29-4680-90b4-3e91ffad15eb" }

POST https://graph.microsoft.com/v1.0/oauth2PermissionGrants
{ "clientId": "{gateway-sp-object-id}", "consentType": "AllPrincipals", "resourceId": "{gateway-sp-object-id}", "scope": "ServiceDesk.Access" }

DELETE https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/{participant-global-admin-assignment-id}
```

## 12. Roles: view versus manage

| Role group or role (type) | View | Manage (create, change, delete, approve) | Source |
| - | - | - | - |
| **Information Protection Analysts** (Purview role group) | View-only DLP policies, sensitivity labels and their policies, all classifier types; activity explorer | DLP alerts only (access and manage); no policy changes | S16, S14, S51 |
| **Information Protection Readers** (Purview role group) | View-only reports for DLP policies and labels; activity explorer only together with **Information Protection Admins** | None | S16, S14 |
| **Information Protection Investigators** (Purview role group) | As Analysts plus content explorer and item contents | DLP alerts | S16 |
| **Data Security AI Viewers** (Purview role group, role **Data Security AI Viewer**) | All DSPM for AI (classic) pages and AI data in DSPM, including the **AI activities** tab; not prompts and responses; not information protection policies on its own | None | S16, S15 |
| **Data Security AI Content Viewers** (role **Data Security AI Content Viewer**) | Prompts and responses of AI interactions | None | S16, S15 |
| **Content Explorer Content Viewer** | File contents in content explorer; prompts and responses in DSPM | None | S16, S15 |
| **Data Security Viewers** (role **Data Security Viewer**) | DSPM dashboard insights, Security Dashboard for AI, Security Copilot in DSPM | None | S16, S15 |
| **Audit Reader** (role **View-Only Audit Logs**) | Search, view and export audit logs | None | S16, S44 |
| **Security Reader** (inherits the Entra Security Reader directory role) | Includes **View-Only DLP Compliance Management** and **Sensitivity Label Reader**; view-only in DSPM | None | S16, S15, S18 |
| **Global Reader** (inherits the Entra Global Reader directory role) | Configuration and settings read-only, including DLP and labels | None | S16, S18 |
| **Compliance Administrator**, **Compliance Data Administrator**, **Information Protection**, **Information Protection Admins**, **Security Administrator** | Everything | Create and deploy DLP policies (the role groups that can) | S51, S16 |
| **Data Security AI Admins** | AI content in DSPM | Edit DLP policies | S16 |
| **Organization Management**, **Purview Administrators** | Everything / role groups | **Role Management** (role group membership) | S16, S18 |

Page-level exceptions:

| Page or task | Roles that can view | Roles that can manage | Source |
| - | - | - | - |
| **Data loss prevention** > **Policies** | Information Protection Analyst, Investigator and Reader roles; View-Only DLP Compliance Management | Compliance administrator, Compliance data administrator, Information Protection, Information Protection Admin, Security administrator role groups | S51, S16 |
| Activity explorer (Information Protection) | Role groups Information Protection, Information Protection Investigators, Information Protection Analysts, Information Protection Admins plus Readers; Microsoft 365 role groups Compliance Administrator, Security Administrator, Security Reader | n/a | S14 |
| **DSPM** > **Activity explorer** > **AI activities** | View-only roles and view-only for AI data roles | n/a | S15 |
| Prompts and responses in **AI interaction** events | Only Content Explorer Content Viewer or Data Security AI Content Viewer (no admin role includes it) | n/a | S15, S12 |
| Audit search | Audit Logs or View-Only Audit Logs roles | n/a | S44 |
| **Role groups** page | Global Administrator or Role Management | Role Management | S18 |

- Least-privilege set for both participants, with no Entra directory role (derived from S14, S15, S16, S51): **Information Protection Analysts** (DLP policy, Credit Card Number type, label, Activity explorer) plus **Data Security AI Viewers** (DSPM AI activities). Add **Audit Reader** only if a task searches the audit log, and **Data Security AI Content Viewers** only if a task shows prompts and responses.
- **Information Protection Analysts** also carries the roles **Purview Agent Analysis**, **Purview Agent Deployment**, **Purview Copilot Workspace Contributor** and **Purview Evaluation Administrator**, and lets members manage DLP alerts [S16]. A custom role group with only **Information Protection Analyst** and **Data Security AI Viewer** is tighter and is documented for the portal [S18]; a custom group with only AI-viewer roles can't view information protection policies [S15].
- Avoid **Security Reader**, **Global Reader** and **AI Administrator**: they come from Entra directory roles [S16, S18], which conflicts with the rule that participants hold no tenant administrator role (derived from S18 and the planned environment).
- Script: `Add-RoleGroupMember -Identity '<role group>' -Member '<UPN>'`; a caller who is not in the group's ManagedBy list needs **Organization Management** or the **Role Management** role and the `-BypassSecurityGroupManagerCheck` switch; `-WhatIf` doesn't work in Security & Compliance PowerShell [S17].
- Role group assignments can carry an expiration date (one day to two years) set in the portal [S18].
- Users with a Purview role assigned for the portal need a license [S11], and Activity explorer requires E5-level licensing [S11].
- Role group permissions can take up to 30 minutes to apply (stated for communication compliance role groups) [S56].

## 13. Licensing

| Capability | Without the license | With the license | Source |
| - | - | - | - |
| DLP block of an Entra-registered app's interactions | Not available without pay-as-you-go billing on the tenant | Pay-as-you-go plus (per Agent Framework prerequisites) Microsoft 365 E5 | S06, S37 |
| Activity explorer and content explorer interfaces | E3 tenants keep data aggregation only | Microsoft 365 E5/A5/G5, Microsoft 365 E5 Compliance, Microsoft 365 E5 Information Protection & Governance, Office 365 E5 | S11 |
| Manual sensitivity labeling | Not available | Microsoft 365 E3/E5 and other listed plans | S11 |
| Automatic sensitivity labeling | Not available | Microsoft 365 E5, Purview Suite, E5 Information Protection and Governance, Office 365 E5 | S11 |
| Audit (Standard) of Foundry or Copilot Studio apps | Included | Included | S42 |
| Audit of non-Microsoft AI apps | Pay-as-you-go | Pay-as-you-go | S42 |
| Purview role in the portal | User needs a license | Licensed | S11 |
| Prompt and response display in **AI interaction** events | No text without an Exchange Online mailbox | Mailbox needed | S58 |
| Pay-as-you-go enablement | Needs service plan `MIP_S_Exchange` or `EXCHANGE_S_FOUNDATION` in the tenant | Present | S10 |
| Purview for agents on Foundry and Entra-connected AI apps through Microsoft 365 E7 or Agent 365 | Announced as future support | Not yet documented as a replacement for pay-as-you-go | S11, S08 |

- **Microsoft 365 E5**: includes everything in Microsoft 365 E3 and all Microsoft Purview Suite capabilities; list price 60.00 USD user/month paid yearly, or 51.45 USD for Microsoft 365 E5 (no Teams), as of 2026-11-06 [S60].
- **Microsoft Purview Suite** (formerly Microsoft 365 E5 Compliance): 12.00 USD user/month paid yearly, requires Microsoft 365 E3, or Office 365 E3 and Enterprise Mobility + Security E3 [S60, S38].
- Trial: the Microsoft Purview Suite trial adds 25 licenses for 90 days to a tenant that has Microsoft 365 E3 (or Office 365 E3 plus EMS E3) and no E5 package; Billing Administrator, Compliance Administrator, Compliance Data Administrator or Global Administrator starts it in the portal; solutions can take up to two hours to appear [S38]. One trial per tenant would cover both participant identities, but it still needs an E3 base license and a portal action per tenant (derived from S38).
- Consumption: Purview pay-as-you-go per tenant on the tenant's Azure subscription (section 8) [S09, S10].
- **Power Apps Developer Plan**: free plan for building and testing with Power Apps, Power Automate and Dataverse [S48]. From November 15, 2026 signing up no longer creates a developer environment and nobody can create new unmanaged developer environments; existing ones are suspended from December 15, 2026 and deleted from January 15, 2027; each user can create only one managed developer environment, and users need a premium license to run assets in it because Managed Environments use rights aren't included in the plan [S48, S49]. Managed Environments are an entitlement of standalone Power Apps, Power Automate, Copilot Studio, Power Pages and Dynamics 365 licenses [S49]. This changes the Dataverse environment plan for every workshop after November 15, 2026 (derived from S49).
- CSP offer IDs: the verified table in `license-offer-ids.md` lists only Windows 365 products, so no verified offer ID exists for Microsoft 365 E5, Microsoft 365 E3, Microsoft Purview Suite, the Power Apps Developer Plan or a Power Apps premium license (see OPEN QUESTIONS). The unconfirmed IDs seen in other CloudLabs templates must not be used.

## 14. LAB FEASIBILITY (up to 108 tenants: 4 workshops of 25 participants plus 2 spares, one tenant per participant)

### 14.1 Constraints that drive the design

- Pay-as-you-go enablement is a portal flow for a Global Administrator, in preview, taking hours, with no scripted procedure in the pages read; it becomes a per-tenant operator step before admin rights are removed [S10].
- DLP for the MCP server's app exists only through PowerShell, only for sensitive-information-type blocking of prompts, and portal-created policies don't apply to the app [S03, S06].
- A Global Administrator can't remove their own role, so the removal step needs a second principal [S29].
- Mandatory MFA blocks user-account ARM writes and portal use without MFA; workload identities are exempt [S20]; security defaults and Microsoft-managed policies can block a password bootstrap [S24, S25].
- Latency: labels up to 24 hours, DLP about an hour, Activity explorer and audit 60 to 90 minutes or longer, reports a day, pay-as-you-go hours [S32, S39, S14, S44, S06, S10].
- The Credit Card Number type ignores reserved test numbers and needs nearby keywords for high confidence [S43].
- No Purview API returns Purview analytics, so checks read the MCP server's result and the audit log, not the DLP event [S03, S44].
- Unmanaged developer environments can't be created after November 15, 2026 [S49].
- Each tenant is separate, so nothing collides between participants; the per-tenant cost is the licenses, not the meters (derived from S26, S60).

### 14.2 Recommended role set

- Participants (both identities): Purview role groups **Information Protection Analysts** and **Data Security AI Viewers**; no Entra directory role [S16, S15, S14].
- The one write role, if a task needs it: none in Purview; participants change only their own Azure and Dataverse objects (other notes) (derived from S51).
- Supplier only (no instructor in this lab): a break-glass Global Administrator that is never issued, and the provisioning app, whose privileges are removed at the end of setup [S29, S27].
- Never hand out: Global Administrator, Compliance Administrator, Organization Management, Purview Administrators, Information Protection Admins, Data Security AI Admins, Security Administrator, Security Reader, Global Reader, AI Administrator, because they can change tenant policy or are Entra directory roles [S16, S18, S51].

### 14.3 Task classification

| Task | Mode | Role needed | Why | Source |
| - | - | - | - | - |
| Exercise 5 Task 1: read the Purview app's Graph permission in the identity map | Hands-on, read-only | None | Change the guide's permission to `Content.Process.User` if the build adopts it | S01 |
| Exercise 6 Task 2: open **Data loss prevention** > **Policies** and the lab policy with the **Credit Card Number** type | Hands-on, read-only | Information Protection Analysts | View-only DLP and classifiers; visibility of a PowerShell, Application-plane policy in the list must be confirmed in the pilot | S16, S52, S03 |
| Exercise 6 Task 2: read the label on the seeded customer document | Hands-on, read-only | Licensed user in the label policy; Information Protection Analysts for the portal view | Label published at least 24 hours earlier | S32, S45, S16 |
| Exercise 6 Task 2: ask the agent for the ticket note with a card number; see it withheld | Hands-on, read-only (no tenant change) | Senior Technician with E5, tenant with pay-as-you-go and the DLP policy | The block comes from `processContent` | S01, S06 |
| Exercise 6 Task 2: find the matching event in **Data loss prevention** > **Activity explorer** (**DLP rule matched**) | Hands-on, read-only, latency risk | Information Protection Analysts | 60 to 90 minutes or more is documented; use an earlier or pre-seeded event | S39, S14 |
| Same event in **DSPM** > **Discover** > **Activity explorer** > **AI activities** (**DLP rule match**) | Hands-on, read-only (alternative) | Data Security AI Viewers | View-only for AI data | S53, S15 |
| Search the audit log for `ConnectedAIAppInteraction` | Hands-on, read-only (optional) | Audit Reader | Only if Exercise 7 evidence needs it | S44, S42 |
| Create or change the DLP policy, label, collection policy, role groups, app consent | Screenshots only (supplier setup, Purview configuration runbook) | Compliance Administrator, Role Management | Tenant-wide admin actions; participants never hold these roles | S51, S16, S27 |
| Enable pay-as-you-go | Screenshots only (supplier setup) | Global Administrator | Global Administrator only | S10 |

### 14.4 Pre-seeding checklist

1. Seven or more days before: confirm the CloudLabs items in OPEN QUESTIONS (bootstrap identity, security defaults, offer IDs, pay-as-you-go procedure, Dataverse environment type); procure Microsoft 365 E5 (or E3 plus Purview Suite) for both identities; run one pilot tenant end to end and time every step [S10, S49, S60].
2. Two days before (at least 24 hours): create every tenant and spare; operator enables pay-as-you-go; the setup script runs steps 2 to 12 of section 11; labels and DLP policy exist for at least 24 hours before the lab [S32, S39, S10].
3. One day before: readiness per tenant: `Get-Label` and `Get-LabelPolicy` show the label; the DLP policy is enabled; `protectionScopes/compute` returns a scope for `uploadText`; a scripted `processContent` call with the seeded card text returns `restrictAccess`/`block`; the seeded **DLP rule matched** event is visible in Activity explorer; role groups are assigned; the participant holds no directory role [S32, S35, S01, S14, S28].
4. Event day: participants only read Purview; nothing tenant-wide changes (derived from 14.2).

### 14.5 Data latency

| Signal or change | Documented latency | Source |
| - | - | - |
| Pay-as-you-go enablement | A few hours | S10 |
| New label and label policy | Up to 24 hours (Office for the web within the hour; group-based 24 to 48 hours) | S32 |
| DLP policy turned on | About an hour | S39 |
| Purview role group membership | Up to 30 minutes (communication compliance statement) | S56 |
| Activity explorer event | 60 to 90 minutes for core services; other services longer; no guarantee | S14 |
| Audit record | Same as Activity explorer | S44 |
| AI interaction data from an API-integrated app | A few minutes (developer test page) | S41 |
| DSPM reports | At least a day | S06, S40 |
| Temporary Access Pass prompt after creation | A few minutes | S31 |
| DLP event for an Entra-registered app specifically | Not documented | none |

### 14.6 Timing and fallbacks

- Make the first card-number block happen early (the provisioning readiness call, and the first time the agent reads that ticket in an earlier exercise), so Exercise 6 searches for an event that is at least an hour old (derived from S14, S44).
- The guide checks the MCP server's own result (withheld note, log row with the Purview decision) first and the Purview portal last; if no event is visible yet, the participant records the server evidence and returns later (derived from S14).
- A brand-new tenant can't reach a working DLP block and label within 60 minutes, because pay-as-you-go takes hours and labels up to 24 hours; resets must hand out a pre-prepared spare tenant, which is still a new tenant (derived from S10, S32).
- If pay-as-you-go is missing, protection scopes may come back empty and nothing is blocked, so the readiness check must assert a block, not only a successful call (derived from S03, S06).
- If Purview can't block in the pilot, the closest working equivalent is the MCP server's own label check plus a server-side card-number check, recorded in the design pack under the platform-dependency clause (derived from S06, S43).

## 15. SCREENSHOT SOURCES

All URLs below returned HTTP 200 with content type image/png on 2026-11-06 (GET); relative media paths were resolved against each page URL.

- https://learn.microsoft.com/en-us/purview/media/dspm-posture.png : DSPM **Posture** page with sample data [S53]
- https://learn.microsoft.com/en-us/purview/media/dspm-objectives.png : DSPM **Objectives** page [S53]
- https://learn.microsoft.com/en-us/purview/media/dspm-solution.png : selecting the DSPM for AI solution in the Purview portal [S06]
- https://learn.microsoft.com/en-us/purview/media/example-dspm.png : DSPM for AI example (lightbox) [S06]
- https://learn.microsoft.com/en-us/purview/developer/images/enableaudit.png : **Activate Microsoft Purview Audit** in DSPM for AI [S40]
- https://learn.microsoft.com/en-us/purview/developer/images/kydpolicy.png : **Secure interactions from enterprise apps** policy status [S40]
- https://learn.microsoft.com/en-us/purview/developer/images/createpolicy.png : **Create policy** on a DSPM recommendation [S40]
- https://learn.microsoft.com/en-us/purview/media/dlp-learn-about-dlp/dlp-protected-channels.png : DLP channels overview diagram [S39]
- https://learn.microsoft.com/en-us/purview/media/alert-info-1.png : DLP alert details [S39]
- https://learn.microsoft.com/en-us/purview/media/event-info-1.png : DLP event details [S39]
- https://learn.microsoft.com/en-us/purview/media/create-sensitivity-label-full.png : **+ Create a label** on **Sensitivity labels** [S32]
- https://learn.microsoft.com/en-us/purview/media/sensitivity-labels-scopes.png : label scope page [S32]
- https://learn.microsoft.com/en-us/purview/media/edit-sensitivity-label-full.png : **Edit label** [S32]
- https://learn.microsoft.com/en-us/purview/media/publish-sensitivity-labels-full.png : **Publish label** [S32]
- https://learn.microsoft.com/en-us/purview/media/edit-sensitivity-label-policy-full.png : **Edit Policy** for a label policy [S32]
- https://learn.microsoft.com/en-us/purview/media/purview-portal-roles.png : **Role groups** page in **Roles and scopes** [S18]
- https://learn.microsoft.com/en-us/purview/media/audit-search/audit-new-search-columns.png : audit search job dashboard [S44]
- https://learn.microsoft.com/en-us/purview/media/audit-search/audit-search-job-details-dashboard.png : audit search job details [S44]
- https://learn.microsoft.com/en-us/purview/media/audit-search/audit-new-search-result-details.png : audit record fly-out [S44]
- https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/media/groups-remove-assignment/remove-assignment.png : **Remove assignment** for a role [S29]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/how-to-authentication-temporary-access-pass/select-temporary-access-pass-policy.png : TAP in the Authentication methods policy [S31]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/how-to-authentication-temporary-access-pass/enable-temporary-access-pass.png : enable TAP and scope users [S31]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/how-to-authentication-temporary-access-pass/configure-temporary-access-pass.png : TAP settings (lifetime, length) [S31]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/how-to-authentication-temporary-access-pass/create.png : **Add authentication method** on a user [S31]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/how-to-authentication-temporary-access-pass/add-method.png : TAP activation time and duration [S31]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/how-to-authentication-temporary-access-pass/details.png : TAP details shown once [S31]
- https://learn.microsoft.com/en-us/entra/identity/authentication/media/concept-mandatory-multifactor-authentication/phase-2-confirm.png : Phase 2 MFA enforcement banner [S20]
- https://learn.microsoft.com/en-us/powershell/docs-conceptual/media/exo-app-only-auth-api-permissions-select-exchange-manageasapp.png?view=exchange-ps : selecting **Exchange.ManageAsApp** [S19]
- https://learn.microsoft.com/en-us/powershell/docs-conceptual/media/exo-app-only-auth-find-and-select-supported-role-scc.png?view=exchange-ps : selecting the Compliance Administrator role for an app [S19]
- https://learn.microsoft.com/en-us/powershell/docs-conceptual/media/exo-app-only-auth-admin-consent-granted.png?view=exchange-ps : admin consent granted for Exchange.ManageAsApp [S19]

No Learn image shows **Data loss prevention** > **Activity explorer** with a **DLP rule matched** event for an Entra-registered app, or the **AI activities** tab; those shots are captured live in the pilot.

## 16. OPEN QUESTIONS

1. **Pay-as-you-go enablement by script:** S10 documents only the portal flow for a Global Administrator, in preview, taking hours. Ask Microsoft and CloudLabs whether an API exists; otherwise budget an operator step per tenant (108 or more) and time it in the pilot.
2. **DLP enforcement without pay-as-you-go:** S06 says pay-as-you-go is required for Entra-registered AI apps; S08 allows an Agent 365 subscription instead for Foundry's native integration; S11 announces future support through Microsoft 365 E7 and Agent 365. Test in the pilot whether `processContent` returns a block before pay-as-you-go completes, and whether E7 or Agent 365 licenses change that.
3. **Meter for processContent calls:** S09 names **Data Security for Gen AI Applications** (requests or messages); S26 and S59 show only the **In Transit Protection Request** meter for requests. Read the tenant's Azure cost data after the pilot to see which meter bills the calls.
4. **Audit billing for this app:** S42 says some `ConnectedAIAppInteraction` scenarios are pay-as-you-go. Confirm in the pilot cost data.
5. **`-RestrictAccess` semantics:** the parameter description is a placeholder (S04); only `UploadText`/`Block` is shown. Confirm whether `DownloadText` or an audit-only value exists before using anything else.
6. **Default confidence of `@{Name='Credit Card Number'}`:** not stated in S04. Test seeded text with and without a keyword within 300 characters (S43).
7. **Policy visibility to viewers:** is a PowerShell-created `Application` plane DLP policy listed under **Data loss prevention** > **Policies**, and can an **Information Protection Analysts** member open it? Not documented (S03, S52). Check in the pilot; fallback is a screenshot of the policy and the rule printed by `Get-DlpComplianceRule` in the setup log.
8. **Where the event lands:** does a block from `processContent` create **DLP rule matched** in DLP Activity explorer, **DLP rule match** in the DSPM **AI activities** tab, or both, and is the collection policy (S40, S50) required for either? S03 hints that the DLP policy must appear under **DSPM** > **Collection policies**. Verify in the pilot.
9. **Latency of the event:** not documented for Entra-registered apps; S41 says a few minutes, S14 and S44 say 60 to 90 minutes or more for core services. The current `exercise-6.md` note promises events within 30 minutes, which no source supports. Measure in the pilot and rewrite the note.
10. **Managed identity as the Purview app:** can the Container Apps managed identity be the DLP policy `Location` (LocationSource `Entra`) and call `processContent` app-only? Not documented. Fallback: app registration with a certificate in Key Vault, read by the managed identity.
11. **processContent limits:** no text size or throttling limit was found (S01). Test the longest note and document (the previous build truncates at 15,000 characters).
12. **Removing the last Global Administrator:** S29 blocks only self-removal. Confirm whether a service principal can remove the only user Global Administrator; plan a supplier-only Global Administrator so the question never arises.
13. **Bootstrap identity from CloudLabs:** does the platform provide a per-tenant service principal (`GET-SERVICEPRINCIPAL-APPLICATION-ID` / `-SECRET`) and which directory roles or Graph app roles it holds? Is `AzureAdUserPassword` a password or a Temporary Access Pass (ROPC needs the real password, derived from S21 and S31)? Are security defaults off and is no Conditional Access policy requiring MFA for the deployment Global Administrator (S24, S25)? Can the ODL user be a supplier account that is not shown to participants, with both technicians created by the JSON, so no Global Administrator removal is needed?
14. **App-only permissions for the Purview cmdlets:** will an app with only the Entra Compliance Administrator role run `New-Label`, `New-LabelPolicy`, `New-DlpCompliancePolicy -EnforcementPlanes Application` and `New-FeatureConfiguration`? The **Compliance Administrator** role group has **Information Protection Admin** but not **Sensitivity Label Administrator** (S16). Does an app with Global Administrator get **Role Management** for `Add-RoleGroupMember` (S19 is silent)? Test in the pilot.
15. **Role group identity strings and custom groups:** `Add-RoleGroupMember -Identity` may need the internal role group name rather than the display name; resolve with `Get-RoleGroup` in the pilot. Creating a custom Purview role group by script isn't covered in the pages read (S18 documents the portal only).
16. **Per-tenant document label:** can `New-Label` set a known GUID (not in S46)? How should the setup script label the seeded .docx with the tenant's GUID and tenant ID (MIP SDK), and do Office and Purview honor metadata written without the SDK? Is the LabelInfo (co-authoring) location on by default in new tenants (S33)?
17. **Default labels:** new tenants may receive default labels (S32); check for a "Confidential" display-name clash before `New-Label`.
18. **Label drift:** **Settings** > **Roles and scopes** > **Role groups** (S18) versus **Settings** > **Roles and groups** > **Role groups** (S56); **DSPM** > **Actions** > **Remediation actions** (S47) versus **Tasks and actions** > **Remediation actions** (S53); the Foundry page places Purview enablement on the **Security posture** tab in its overview table but on the **Data security and governance** tab in its steps (S08); **Publishing policies** navigation opens a page titled **Label policies** (S32). Capture the live labels in the pilot.
19. **Pay-as-you-go roles:** S10 says only Global Administrator; S59 says Global Administrator or Purview Administrator can consent (existing customers). Confirm whether a **Purview Administrators** member can do the subscription-based enablement, which would avoid using the Global Administrator.
20. **TAP permission table:** S30 lists `UserAuthMethod-TAP.Read` (delegated) and `UserAuthMethod-TAP.Read.All` (application) as least privileged for creating a pass, which looks wrong for a write; use `UserAuthMethod-TAP.ReadWrite.All` (S36) and confirm in the pilot.
21. **Dataverse developer environments after November 15, 2026 (S48, S49):** the lab can no longer rely on Developer Plan sign-up; options are one managed developer environment per user with premium licenses, environment routing, or sandbox or trial environments. Escalate to the Dataverse note owner and the license plan.
22. **CSP offer IDs:** none verified for Microsoft 365 E5, Microsoft 365 E3, Microsoft Purview Suite, Power Apps premium or the Power Apps Developer Plan in `license-offer-ids.md`. Ask CloudLabs; never copy an unconfirmed ID.
23. **Exchange Online mailbox:** S58 needs a mailbox for prompt display; confirm the chosen SKU includes Exchange Online and that mailboxes exist before `New-LabelPolicy -ExchangeLocation` runs (S45).
24. **Agent identity fields:** which Entra Agent ID values (blueprint ID, agent identifier) belong in `aiAgentInfo` (S01), and do they show in the DSPM event? Check in the pilot.
25. **Mandatory MFA state of lab tenants:** postponement of Phase 2 ended July 1, 2026 (S20); confirm enforcement on a pilot tenant through https://aka.ms/postponePhase2MFA so the VM script never relies on a user account for Azure CLI writes.
