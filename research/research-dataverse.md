# Research: Dataverse service desk, environment provisioning, identities and packaging

Research notes for the lab "Agentic MSP Support Agent Guided Lab" (Relecloud Managed Services). Researched on 2026-11-06 from Microsoft Learn and official microsoft.com pages only, retrieved with the Microsoft Learn MCP tools (search, then a full fetch of every page relied on). No blogs, lab repos or third-party sites were used.

This note replaces the note of 2026-10-01, which was written for one shared tenant with team accounts. The planned environment is now one Microsoft Entra tenant per participant, with a Global Administrator held by the CloudLabs platform for provisioning only, a Senior Technician (read and write on tickets) and a Tier 1 Technician (read-only on tickets). Every fact kept from the previous note was re-verified today; facts that could not be re-verified were dropped or moved to OPEN QUESTIONS.

Conventions:

- **Bold** text is a UI label (node, tab, filter, column, button, pane section) exactly as written in the cited page. Where pages disagree on a label, both spellings are given and the conflict is listed under OPEN QUESTIONS, the last section.
- [Sxx] is a source ID from section 0. Every statement carries at least one source ID. "Derived from [Sxx]" marks a design judgment that follows from sourced facts.
- Status: **GA** means the page carries no preview label. **Preview** means the page labels it preview. **Retiring** means the page announces a retirement or deprecation date. **Enforcement** means the page announces a dated licensing or security enforcement. **Removed** means the page says the capability has already ended. **Conflicting labels** means two cited pages label it differently.
- Page text is paraphrased. Error message templates are reproduced in code format because the guide must match them.

Partial reads, stated for transparency: S02 (the sections on unmanaged developer environments and on Purview audit values, plus the heading list), S11 (the command table and the sections cited), S27 (searched for each code cited; the full table has about 4,500 rows), S70 (searched for the Power Apps product rows), S71 (the notes, lifecycle operations and FAQ sections), S72 (the capacity and multiplexing sections). The Power Platform Licensing Guide is a PDF linked from S53 and S03 and is not retrievable with these tools.

What changed since the 2026-10-01 note, and why it drives the rebuild:

1. Unmanaged developer environments are deprecated. Creation ends on 2026-11-15 (nine days after this note) from Power Apps, the Power Platform admin center, PowerShell and the Power Platform CLI; existing ones are suspended from 2026-12-15 and deleted from 2027-01-15. The developer type continues only as a managed developer environment, one per user [S02][S06].
2. The Power Apps Developer Plan includes no managed environment use rights, so every user who runs an app in a managed developer environment needs a premium license such as Power Apps Premium [S01][S03]. From February 2027, users without a qualifying license can't open apps in managed environments or model-driven apps [S03][S53].
3. The Power Platform API Provision New Environment request now has a `governanceConfiguration.protectionLevel` property (`Standard` enables managed environments) and a `usedBy` user identity [S09][S04].
4. Tenant-level admins aren't given the Dataverse System Administrator role automatically; they self-elevate per environment [S56][S68], and without a license they run in the Administrative access mode [S12].
5. Since May 2026, Dataverse no longer sends before-and-after field values to Microsoft Purview audit events; Dataverse's own audit stays the source of field changes [S02].

## 0. Sources

| ID | URL | Page title | Read on |
| - | - | - | - |
| S01 | https://learn.microsoft.com/power-platform/developer/plan | Power Apps Developer Plan Guide: Features and Benefits | 2026-11-06 |
| S02 | https://learn.microsoft.com/power-platform/important-changes-coming | Important changes (deprecations) coming in Power Platform (partial, see above) | 2026-11-06 |
| S03 | https://learn.microsoft.com/power-platform/admin/managed-environment-licensing | Licensing requirements for managed environments | 2026-11-06 |
| S04 | https://learn.microsoft.com/power-platform/admin/managed-environment-enable | Enable managed environments | 2026-11-06 |
| S05 | https://learn.microsoft.com/power-platform/admin/create-environment | Create and manage environments in the Power Platform admin center | 2026-11-06 |
| S06 | https://learn.microsoft.com/power-platform/admin/control-environment-creation | Control who can create and manage environments in Power Platform | 2026-11-06 |
| S07 | https://learn.microsoft.com/power-platform/admin/environments-overview | Power Platform environments overview | 2026-11-06 |
| S08 | https://learn.microsoft.com/power-platform/admin/default-environment-routing | Environment routing | 2026-11-06 |
| S09 | https://learn.microsoft.com/rest/api/power-platform/environmentmanagement/environment-provisioning/provision-new-environment | Environment Provisioning - Provision New Environment (api-version 2024-10-01) | 2026-11-06 |
| S10 | https://learn.microsoft.com/power-platform/developer/cli/reference/admin | pac admin | 2026-11-06 |
| S11 | https://learn.microsoft.com/power-platform/developer/cli/reference/environment-management | pac environment-management (partial, see above) | 2026-11-06 |
| S12 | https://learn.microsoft.com/power-platform/admin/create-users | Create users | 2026-11-06 |
| S13 | https://learn.microsoft.com/power-apps/developer/data-platform/impersonate-another-user (the URL .../webapi/impersonate-another-user-web-api returns the same article) | Impersonate another user | 2026-11-06 |
| S14 | https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data | Retrieve the history of audited data changes | 2026-11-06 |
| S15 | https://learn.microsoft.com/power-apps/developer/data-platform/auditing/configure | Configure auditing | 2026-11-06 |
| S16 | https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing | Manage Dataverse auditing | 2026-11-06 |
| S17 | https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations | Requests limits and allocations | 2026-11-06 |
| S18 | https://learn.microsoft.com/power-apps/developer/data-platform/api-limits | Service protection API limits | 2026-11-06 |
| S19 | https://learn.microsoft.com/power-platform/admin/manage-application-users | Manage application users in the Power Platform admin center | 2026-11-06 |
| S20 | https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/applicationuser | ApplicationUser table/entity reference (Microsoft Dataverse) | 2026-11-06 |
| S21 | https://learn.microsoft.com/power-platform/admin/create-dataverseapplicationuser | Create a Dataverse application user (preview) | 2026-11-06 |
| S22 | https://learn.microsoft.com/power-platform/admin/programmability-authentication-v2 | Authentication (Power Platform API) | 2026-11-06 |
| S23 | https://learn.microsoft.com/entra/identity/authentication/concept-mandatory-multifactor-authentication | Mandatory multifactor authentication for Azure and admin portals | 2026-11-06 |
| S24 | https://learn.microsoft.com/power-platform/developer/cli/reference/auth | pac auth | 2026-11-06 |
| S25 | https://learn.microsoft.com/power-platform/admin/security-roles-privileges | Security roles and privileges for Dataverse | 2026-11-06 |
| S26 | https://learn.microsoft.com/power-platform/admin/how-record-access-determined | How access to a record is determined | 2026-11-06 |
| S27 | https://learn.microsoft.com/power-apps/developer/data-platform/reference/web-service-error-codes | Web service error codes (searched for the codes cited) | 2026-11-06 |
| S28 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors | Compose HTTP requests and handle errors | 2026-11-06 |
| S29 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/replaceprivilegesrole | ReplacePrivilegesRole Action | 2026-11-06 |
| S30 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/roleprivilege | RolePrivilege ComplexType | 2026-11-06 |
| S31 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/privilegedepth | PrivilegeDepth EnumType | 2026-11-06 |
| S32 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-functions-actions-sample | Web API Functions and Actions Sample | 2026-11-06 |
| S33 | https://learn.microsoft.com/power-platform/admin/wp-security-cds | Ownership-based security in Microsoft Dataverse | 2026-11-06 |
| S34 | https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security | Column-level security by using code | 2026-11-06 |
| S35 | https://learn.microsoft.com/power-platform/admin/field-level-security | Column-level security to control access | 2026-11-06 |
| S36 | https://learn.microsoft.com/power-platform/admin/create-manage-masking-rules | Create and manage masking rules | 2026-11-06 |
| S37 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/samples/column-level-security-powershell | Sample: Column-level security using Dataverse Web API (PowerShell) | 2026-11-06 |
| S38 | https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/solutioncomponent | Solution Component (SolutionComponent) table/entity reference | 2026-11-06 |
| S39 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/addsolutioncomponent | AddSolutionComponent Action | 2026-11-06 |
| S40 | https://learn.microsoft.com/power-platform/alm/solution-api | Work with solutions using the Dataverse SDK | 2026-11-06 |
| S41 | https://learn.microsoft.com/power-platform/alm/solution-async | Solution staging, with asynchronous import and export | 2026-11-06 |
| S42 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/importsolutionasync | ImportSolutionAsync Action | 2026-11-06 |
| S43 | https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/exportsolution | ExportSolution Action | 2026-11-06 |
| S44 | https://learn.microsoft.com/power-platform/developer/cli/reference/solution | pac solution | 2026-11-06 |
| S45 | https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code | Create, manage, and publish model-driven apps using code | 2026-11-06 |
| S46 | https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/sitemap | Site Map (SiteMap) table/entity reference | 2026-11-06 |
| S47 | https://learn.microsoft.com/power-platform/admin/automatic-environment-cleanup | Automatic deletion of Power Platform environments | 2026-11-06 |
| S48 | https://learn.microsoft.com/power-platform/developer/create-developer-environment | Create a developer environment with the Power Apps Developer Plan | 2026-11-06 |
| S49 | https://learn.microsoft.com/power-platform/admin/pay-as-you-go-overview | Pay-as-you-go plan | 2026-11-06 |
| S50 | https://learn.microsoft.com/power-platform/admin/pay-as-you-go-set-up | Set up pay-as-you-go | 2026-11-06 |
| S51 | https://learn.microsoft.com/power-platform/admin/pay-as-you-go-meters | Pay-as-you-go meters | 2026-11-06 |
| S52 | https://learn.microsoft.com/power-platform/admin/pay-as-you-go-issues-faq | Known issues and frequently asked questions (pay-as-you-go) | 2026-11-06 |
| S53 | https://learn.microsoft.com/power-platform/admin/powerapps-licensing-faq | Power Apps licensing FAQs | 2026-11-06 |
| S54 | https://www.microsoft.com/en-us/power-platform/products/power-apps/pricing | Power Apps licensing and pricing | 2026-11-06 |
| S55 | https://learn.microsoft.com/power-platform/admin/database-security | Role-based security roles for Dataverse | 2026-11-06 |
| S56 | https://learn.microsoft.com/power-platform/admin/manage-high-privileged-admin-roles | Manage admin roles with Microsoft Entra Privileged Identity Management | 2026-11-06 |
| S57 | https://learn.microsoft.com/power-platform/admin/create-edit-business-units | Create or edit business units | 2026-11-06 |
| S58 | https://learn.microsoft.com/power-platform/admin/manage-teams | Microsoft Dataverse teams management | 2026-11-06 |
| S59 | https://learn.microsoft.com/power-platform/admin/assign-security-roles | Assign a security role to a user | 2026-11-06 |
| S60 | https://learn.microsoft.com/dynamics365/customerengagement/on-premises/developer/security-dev/use-field-security-control-access-field-values?view=op-9-1 | Use field security to control access to field values (Dynamics 365 Customer Engagement on-premises 9.1) | 2026-11-06 |
| S61 | https://learn.microsoft.com/power-apps/developer/data-platform/authenticate-oauth | Use OAuth authentication with Microsoft Dataverse | 2026-11-06 |
| S62 | https://learn.microsoft.com/power-platform/admin/managed-identity-overview | Power Platform managed identity overview | 2026-11-06 |
| S63 | https://learn.microsoft.com/power-platform/admin/powerapps-powershell | PowerShell support for Power Apps and Power Automate | 2026-11-06 |
| S64 | https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/add-adminpowerappssyncuser?view=pa-ps-latest | Add-AdminPowerAppsSyncUser | 2026-11-06 |
| S65 | https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/new-adminpowerappenvironment?view=pa-ps-latest | New-AdminPowerAppEnvironment | 2026-11-06 |
| S66 | https://learn.microsoft.com/rest/api/power-platform/environmentmanagement/environment-managed-governance/enable-managed-environment | Environment Managed Governance - Enable Managed Environment | 2026-11-06 |
| S67 | https://learn.microsoft.com/rest/api/power-platform/environmentmanagement/operation/get-operation-by-id | Operation - Get Operation By ID | 2026-11-06 |
| S68 | https://learn.microsoft.com/rest/api/power-platform/usermanagement/users/apply-admin-role | Users - Apply Admin Role | 2026-11-06 |
| S69 | https://learn.microsoft.com/graph/api/user-assignlicense?view=graph-rest-1.0 | user: assignLicense | 2026-11-06 |
| S70 | https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference | Product names and service plan identifiers for licensing (searched for the rows cited) | 2026-11-06 |
| S71 | https://learn.microsoft.com/power-platform/admin/capacity-storage | Dataverse capacity-based storage details (partial, see above) | 2026-11-06 |
| S72 | https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs | Power Automate licensing FAQ (partial, see above) | 2026-11-06 |
| S73 | https://learn.microsoft.com/troubleshoot/power-platform/dataverse/environment-app-access/troubleshooting-user-needs-read-write-access-organization | Troubleshoot user access problems for different environments | 2026-11-06 |
| S74 | https://learn.microsoft.com/industry/nonprofit/fundraising-engagement-data-sync-accelerator | Migrate data with the data sync accelerator (step 9: application user for a managed identity) | 2026-11-06 |
| S75 | https://learn.microsoft.com/power-platform/admin/database-security-configure | Configure user security in an environment | 2026-11-06 |
| S76 | https://learn.microsoft.com/power-apps/developer/data-platform/optional-parameters | Use optional parameters | 2026-11-06 |
| S77 | https://learn.microsoft.com/power-apps/developer/data-platform/use-multi-tenant-server-server-authentication | Use multi-tenant server-to-server authentication | 2026-11-06 |
| S78 | https://learn.microsoft.com/power-platform/admin/security/role-based-access-control | Role-based access control for Power Platform admin center (preview) | 2026-11-06 |
| S79 | https://learn.microsoft.com/power-platform/admin/programmability-extensibility-overview | Programmability and extensibility overview | 2026-11-06 |
| S80 | https://learn.microsoft.com/power-platform/admin/activity-logging-auditing/activity-logs-dataverse-model-driven-apps | View Microsoft Dataverse and model-driven app activity logs in Microsoft Purview | 2026-11-06 |
| S81 | https://learn.microsoft.com/power-platform/alm/use-managed-properties | Use managed properties | 2026-11-06 |
| S82 | https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits | Limit sharing | 2026-11-06 |
| S83 | https://learn.microsoft.com/dotnet/api/microsoft.crm.sdk.messages.addsolutioncomponentrequest?view=dataverse-sdk-latest | AddSolutionComponentRequest Class | 2026-11-06 |
| S84 | https://learn.microsoft.com/power-platform/admin/unified-experience/tutorial-deploy-new-environment-with-erp-template | Tutorial: Provision a new environment with an ERP-based template | 2026-11-06 |
| S85 | https://learn.microsoft.com/power-platform/admin/powerplatform-api-create-service-principal | Creating a service principal application using API (preview) | 2026-11-06 |
| S86 | https://learn.microsoft.com/power-apps/developer/data-platform/aad-group-team | Work with Microsoft Entra ID group teams | 2026-11-06 |
| S87 | https://learn.microsoft.com/power-apps/developer/model-driven-apps/publish-customizations | Publish customizations | 2026-11-06 |

## 1. Status at a glance

| Feature | Status | Date or condition | Source |
| - | - | - | - |
| Unmanaged developer environments | Retiring | Creation ends 2026-11-15; existing ones suspended from 2026-12-15; deleted from 2027-01-15 | S02 |
| Managed developer environments | GA | From 2026-11-15 the only developer type; one per user; existing managed ones unchanged | S02, S06 |
| Developer Plan sign-up creating an environment | Retiring | Stops on 2026-11-15 | S01, S48 |
| Environment routing (personal managed developer environments) | GA | Premium governance feature; off by default; only Power Platform admins turn it on | S08 |
| Managed environments | GA | Enabled by a Power Platform admin or Dynamics 365 admin | S04 |
| Managed environments licensing compliance | Enforcement | Admin notices since March 2026, in-app notices since June 2026; unlicensed users blocked from opening apps from February 2027 | S03 |
| Premium license to run model-driven apps | Enforcement | Strictly required from February 2027 | S53 |
| Power Platform API Provision New Environment, Enable Managed Environment, Get Operation By ID, Apply Admin Role | GA | api-version 2024-10-01; no preview label | S09, S66, S67, S68 |
| `pac admin` commands used here (`create`, `assign-user`, `set-governance-config`, `self-elevate`) | GA | No preview label on these commands | S10 |
| `pac environment-management` and `pac user-management` | Preview | Every command labeled preview | S11 |
| BAP `addAppUser` endpoint | Preview | Always assigns System Administrator | S21 |
| Service principal registration through the BAP admin API | Preview | Needs an admin in username and password context | S85 |
| Power Platform role-based access control (supports managed identities) | Preview | Tenant, environment group or environment scope | S78 |
| Agent users (Microsoft Entra Agent ID) in Dataverse | Preview | Added under **Users + permissions** > **Agents** | S12 |
| Column-level security | GA | System Administrator configures it | S35 |
| Masking rules on secured columns | Conflicting labels | Admin page has no preview label; developer optional-parameters page calls it preview; needs a managed environment | S36, S76 |
| Dataverse auditing | GA | Environment, table and column levels | S16 |
| Dataverse activity logging to Microsoft Purview | GA | Production environments only | S16, S80 |
| Before-and-after values in Purview audit events | Removed | Since May 2026; Dataverse audit keeps them | S02 |
| Record ownership across business units | GA | Feature toggle in the environment | S33 |
| Filtered table record ownership | Preview | | S33 |
| ImportSolutionAsync, ExportSolutionAsync, StageSolution | GA | | S41 |
| Pay-as-you-go | GA | Production and sandbox environments only | S50, S52 |
| Mandatory MFA, Phase 2 (Azure Resource Manager create, update, delete) | Enforcement | From 2025-10-01; postponement possible until 2026-07-01 at most | S23 |
| Microsoft.PowerApps.Administration.PowerShell | GA | Windows PowerShell 5.x only; incompatible with PowerShell 6 and later | S63 |

## 2. Navigation and exact click paths

All paths start in the Power Platform admin center (`https://admin.powerplatform.microsoft.com`) unless the row names Power Apps (`https://make.powerapps.com`) or the model-driven app.

| Page or task | Click path | What the page shows | Source |
| - | - | - | - |
| Find unmanaged developer environments | **Manage** > **Environments**, filter **Type** = **Developer** and **Managed** = **No**, read **Last activity** | Environments hit by the suspension | S02 |
| Create an environment (admin) | **Manage** > **Environments** > **New**; set **Name**, **Region**, **Type** (**Developer**, **Sandbox**, **Production**, **Trial**), **Add a Dataverse data store** = **Yes**, optional **Pay-as-you-go with Azure** > **Next** > **Language**, **URL**, **Currency**, **Security group** > **Save** | New environment; **Security group** is now a required field (**None** for open access) | S05 |
| Enable managed environments | **Manage** > **Environments** > the ellipsis (**...**) next to the environment > **Enable Managed Environments** (or **Edit Managed Environments**) > **Enable** or **Save** | Managed property on | S04 |
| Sharing limits | **Manage** > **Environments** > managed environment > **Edit Managed Environments** > **Manage sharing** section > **Save** | Canvas apps, solution-aware cloud flows and agents only | S82 |
| Restrict developer environment creation | **Manage** > **Tenant settings** > **Environment assignments: Developer** > **Only specific admins** > **Save** | Only Global admins, Dynamics 365 admins and Power Platform admins create | S06 |
| Environment routing (leave off) | **Manage** > **Tenant settings** > **Environment routing** | Rules that create personal managed developer environments | S08 |
| Self-elevate to System Administrator | **Manage** > **Environments** > environment > **Membership** > **System Administrators** pane > **Add me** | Global admin, Power Platform admin or Dynamics 365 admin only | S56 |
| User profile and diagnostics | **Manage** > **Environments** > environment > **Settings** > **Users + permissions** > **Users** > select a user | **Run diagnostics**, **Refresh user**, roles, teams, business unit | S12, S73 |
| Manage a user's roles | **Users** page > select a user > **Manage security roles** > select roles > **Save** | Direct role assignments | S59 |
| Assign a role from the role side | environment > **Access** tile > **Security roles** **See all** > select business unit > select role > **Add people** > **Add** | Role members | S75 |
| Create an application user for a managed identity | environment > **Settings** > **Users + permissions** > **Application users** > **+ New app user** > **+ Add an app** (enter the managed identity's Application ID, not its name) > **Add** > **Business Unit** > **Email address** > edit icon for security roles > **Save** > **Save** > **Create** | Unlicensed application user | S19, S74 |
| Edit an application user's roles | **Application users** > select the user > **Edit security roles** > **Save** | Selected roles replace the current set | S19 |
| Security roles | environment > **Settings** > **Users + permissions** > **Security roles** > **New role** (**Role Name**, **Business unit**, member inheritance) > **Save** | Role editor tabs | S75 |
| Role members | **Security roles** > role > **More actions** (**...**) > **Members** > **+ Add people** > **Add** | | S25 |
| Business units | environment > **Settings** > **Users + permissions** > **Business units** > **New business unit** | Child business unit with a default team | S57 |
| Team roles | environment > **Settings** > **Users + permissions** > **Teams** > team ellipsis > **Manage security roles** | Owner team roles | S58 |
| Column security profile | environment > **Settings** > **Users + permissions** > **Column security profiles** > **New Profile** > **Save** > **Users** or **Teams** tab > **+ Add Users** or **+ Add Teams** > **Column Permission** tab > select columns > **Edit** > **Save** | Read, Read unmasked, Update, Create per column | S35 |
| Secure a column (Power Apps) | **Solutions** > unmanaged solution > **Objects** > **Tables** > table > **Schema** > **Columns** > column > **Advanced options** > **Enable column security** > **Save** | Column secured | S35 |
| Masking rule on a column (Power Apps) | **Tables** > table > **Schema** > **Columns** > column > **Advanced options** > **Masking rule** > **Save** | Managed environment only | S36 |
| Audit settings | **Manage** > **Environments** > environment > **Settings** > **Audit and logs** > **Audit settings** > **Global Audit Settings** > **Start Auditing** | Retention, log access, read logs | S16 |
| Audit through Compliance | **Security** > **Compliance** > **Auditing** tile > environment > **Set up auditing** > **Turn on auditing** | Optional common-entities set | S16 |
| Table auditing (Power Apps) | **Tables** > table > **Edit** > **Edit table properties** > **Advanced options** > **Audit changes to its data** > **Save** | Then publish | S16 |
| Record audit history | model-driven app > record > **Related** > **Audit History** | Needs the **View Audit History** privilege | S16 |
| Audit summary | **Power Platform Environment Settings** app, or **Settings** > **Advanced Settings** > **System** > **Auditing** > **Audit Summary view** | Needs **View Audit Summary** | S16 |
| Users needing licenses | **Licensing** > **Power Apps** > **Summary** > **Download report** > **Usage type** = **Users requiring licenses in Managed Environments** > **Download report** | Users who launched apps unlicensed | S03 |
| Pay-as-you-go billing plan | **Licensing** > **Pay-as-you-go plans** > **New billing plan** > **Azure subscription** | Production and sandbox only | S50 |

Older or alternate names still found in the documentation: **Developer environment assignments** [S02] and **Environment assignment: Developer** [S08] for the setting S06 calls **Environment assignments: Developer**; the admin center host appears as both `admin.powerplatform.microsoft.com` [S05] and `admin.powerplatform.com` [S48]; the admin UI says **Column security profiles** [S35] while the API calls them field security profiles [S34]. Treat **Environment assignments: Developer** as current, because S06 is the page that documents the setting step by step.

## 3. Developer environments after the 2026-11-15 change

### 3.1 What exists from 2026-11-15

- Users can't create unmanaged developer environments from Power Apps, the admin center, PowerShell or the Power Platform CLI from 2026-11-15; existing ones stop working from 2026-12-15 and are deleted from 2027-01-15 [S02].
- The developer type remains only as a managed developer environment, and each user can create one; managed developer environments, including those that environment routing creates, aren't affected [S02].
- From 2026-11-15 the **Environment assignments: Developer** setting controls who can create managed developer environments [S06].
- Signing up for the Developer Plan no longer creates an environment from that date; Learn points makers to an admin-provided managed developer environment, environment routing, or a standard trial environment [S01][S48].
- Microsoft's migration options are to enable managed environments on an existing developer environment or to move its solutions to a sandbox or other environment [S02].
- Derived from [S02]: the build environment that holds the Golden Environment v1.0 solution must not be an unmanaged developer environment; keep the exported solution files in source control.

### 3.2 Who can create a developer environment

- Developer environments are intended only for use by their owner, and admins can restrict who creates them [S06][S07].
- Admin creation in the admin center is documented with **Type** = **Developer** [S05]. The license requirement for creating environments is waived for service administrators such as Power Platform admins and Dynamics 365 admins, except for standard trial environments [S05].
- When creation is restricted, only Global admins, Dynamics 365 admins and Power Platform admins can create; environments created before the restriction remain manageable by their creators [S06].
- Environment routing creates a managed developer environment the first time a maker visits a supported maker portal, makes the maker an admin in it, and isn't affected by the **Environment assignments: Developer** setting [S08].
- For a just-assigned Power Platform or Dynamics 365 admin role, one tutorial notes a 12-hour cache before an unlicensed admin can create an environment; it's stated for finance and operations templates [S84]. Whether it hits a Global Administrator in a brand-new tenant is an open question (OPEN QUESTIONS 3).

### 3.3 Automation options

| Tool | How to make it a managed developer environment | Target user | Status | Source |
| - | - | - | - | - |
| Power Platform API `POST https://api.powerplatform.com/environmentmanagement/provisioning/environments?api-version=2024-10-01` | `environmentSku: "Developer"` plus `governanceConfiguration.protectionLevel: "Standard"` in the same request | `usedBy` (`userId`, `tenantId`, `type`, `displayName`); what the platform does with it isn't documented | GA | S09 |
| `pac environment-management provision-new-environment` | `--environment-sku Developer --governance-configuration-protection-level Standard` | `--used-by-user-id`, `--used-by-tenant-id`, `--used-by-type`, `--used-by-display-name` | Preview | S11 |
| `pac admin create` | `--type Developer`; the command has no managed flag, so follow it with `pac admin set-governance-config --environment <id> --protection-level Standard` | `--user`, object ID or UPN of the user "to be assigned to the environment" | GA | S10 |
| `New-AdminPowerAppEnvironment` (Windows PowerShell 5.x) | `-EnvironmentSku Developer -ProvisionDatabase -LanguageName <> -CurrencyName <>`, then `Set-AdminPowerAppEnvironmentGovernanceConfiguration` with `protectionLevel = "Standard"` | None; the cmdlet creates the environment as the signed-in user | GA (legacy module) | S65, S04, S63 |
| Admin center **New** | **Type** = **Developer**, then **Enable Managed Environments** | None | GA | S05, S04 |
| Environment routing | Always managed | The maker who visits a portal | GA | S08 |

- The two-step paths (create, then enable managed) depend on whether the platform still accepts an unmanaged developer create after 2026-11-15; S02 says it doesn't, and no page says whether the request is converted or rejected (OPEN QUESTIONS 2). Derived from [S02][S09]: use the single Power Platform API request with `protectionLevel: "Standard"`.
- Enable managed environments on an existing environment: `POST https://api.powerplatform.com/environmentmanagement/environments/{environmentId}/governanceSetting/enableManaged?api-version=2024-10-01` returns 202 [S66]; `pac admin set-governance-config --protection-level Standard` [S10]; or the PowerShell governance cmdlet; `Basic` disables it [S04].
- Enabling or editing managed environments requires the Power Platform Administrator or Dynamics 365 Administrator Entra role; the Environment Admin security role can't change the property [S04].
- Track the operation with `GET https://api.powerplatform.com/environmentmanagement/operations/{operationId}?api-version=2024-10-01`; statuses are `Queued`, `InProgress`, `Succeeded`, `ValidationFailed`, `Failed`, `NoOperation` and `ValidationPassed`, and the result carries `updatedEnvironment.dataverseOrganizationUrl` [S67][S09]. A failed validation returns 400 with `errorDetail.fieldErrors` [S09].
- `CommonDataService` as `databaseType` requires `location` or `macroRegion`, `linkedEnvironmentMetadata.baseLanguageCode` and `linkedEnvironmentMetadata.currency.code` [S09]. Some tenants need a macro region; the legacy cmdlet then fails with `MacroRegionRequired` and the tutorial says to use the Provision New Environment API with `macroRegion` [S84]. `pac admin create --macro-region` accepts `asia-pacific`, `emea`, `eu-efta`, `europe-uk`, `north-america` and `the-americas` [S10].
- `pac admin create` defaults are region `unitedstates`, currency USD and language English; a taken `--domain` gets a numeric suffix; `--async` and `--max-async-wait-time` (default 60 minutes) are available [S10].

### 3.4 Example: one managed developer environment for the participant

Property names come from S09; the values are illustrative. Whether `usedBy` makes the Senior Technician the owner or a System Administrator isn't documented [S09] (OPEN QUESTIONS 1).

```http
POST https://api.powerplatform.com/environmentmanagement/provisioning/environments?api-version=2024-10-01
Authorization: Bearer <token for https://api.powerplatform.com/.default>
Content-Type: application/json

{
  "displayName": "Relecloud Service Desk <DeploymentID>",
  "environmentSku": "Developer",
  "databaseType": "CommonDataService",
  "location": "unitedstates",
  "governanceConfiguration": { "protectionLevel": "Standard" },
  "linkedEnvironmentMetadata": {
    "baseLanguageCode": 1033,
    "currency": { "code": "USD" },
    "domainName": "relecloudsd<deploymentid>"
  },
  "usedBy": { "userId": "<Senior Technician object ID>", "tenantId": "<tenant ID>", "type": "User", "displayName": "Senior Technician" }
}
```

Responses: 201 or 202 with an `OperationExecutionResult` (`operationId`, `status`, `stageStatuses`), 400 `ValidationResponse`, 401, 403, 429 [S09].

### 3.5 Tenant settings that block, open or redirect creation

- **Environment assignments: Developer**, **Production** and **Trial** each take **Only specific admins** [S06]. PowerShell: `Set-TenantSettings` with `powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers = $True`; `DisableEnvironmentCreationByNonAdminUsers` and `DisableTrialEnvironmentCreationByNonAdminUsers` restrict the other types [S06]. The CLI reads and writes tenant settings with `pac admin list-tenant-settings` and `pac admin update-tenant-settings --setting-name <name> --setting-value <value>` [S10].
- The Developer Plan is a viral or internal license; the tenant must allow internal consent plans for a developer environment to be provisioned at sign-up, checked with `Get-AllowedConsentPlans` and changed with `Add-AllowedConsentPlans` [S01]. `Remove-AllowedConsentPlans -Types "Internal"` blocks self-service trials and developer plans while admins can still assign licenses [S63].
- Security groups can't be assigned to developer environments [S07].
- Environment routing is off by default; when on, makers who open Power Apps, Power Automate or Copilot Studio are routed to a personal managed developer environment, and new ones are created for makers without one [S08]. Derived from [S08]: keep routing off in participant tenants, because Exercise 6 sends the Senior Technician to Power Apps and routing would create a second environment for that user.

### 3.6 Time, capacity and lifecycle

- Provisioning time: the sign-up flow says it might take a couple of minutes [S48]. The legacy cmdlet waits by default with a default timeout of 10,080 minutes [S65]; `pac admin create` waits up to 60 minutes by default [S10]. No page gives a provisioning time for an admin API request (section 16.5).
- Capacity per developer environment: 750 flow runs per month and 2 GB database; add-ons can't raise it, and it doesn't count toward the company quota [S01]. Developer environments show as 0 GB in the capacity report [S71], and routed developer environments don't affect the tenant Dataverse quota [S08]. Whether the 2 GB cap is the same for a managed developer environment created by an admin isn't stated (OPEN QUESTIONS 6).
- Inactivity: unmanaged developer environments are disabled after 30 days without activity; managed developer environments use a 60-day threshold (warnings at 53 and 57 days); both are deleted 15 days after being disabled and can be recovered for 7 days [S47]. Only default, developer and Dataverse for Teams environments are subject to this cleanup [S47].
- A deleted or changed environment's URL can't be reused for at least 24 hours [S05].
- Dynamics 365 apps can't be installed in a developer environment, and apps running in one show a banner [S01].
- Users aren't added to a developer environment automatically [S01]; only the user who created a developer environment is added to Dataverse [S12].
- The Developer Plan feature table lists adding coworkers as environment makers and admins, adding coworkers to database roles, sharing apps, and applications that use the .NET SDK or Web API [S01].

### 3.7 Fallback: a sandbox environment

- A sandbox is a nonproduction environment with copy and reset; its creation can be restricted by blocking production creation [S07].
- Creating any non-default environment needs at least 1 GB of available database capacity [S05][S71]. The first Power Apps, Power Automate or Copilot Studio subscription in a tenant adds a one-time 10 GB default database capacity [S72], and each Power Apps Premium license adds 250 MB database and 2 GB file capacity [S54].
- Sandboxes aren't subject to the inactivity cleanup, which covers only default, developer and Dataverse for Teams environments [S47], and they can use pay-as-you-go billing [S50].
- The Developer Plan can't run premium apps outside a developer environment [S01]. Derived from [S01][S03][S53]: a sandbox needs the same Power Apps Premium licenses as a managed developer environment, so the fallback changes the environment type, not the license count.

## 4. Adding the two technicians and assigning their roles

### 4.1 Requirements for a user to be added to Dataverse

- The user must be enabled in Microsoft Entra ID and hold a valid license; exceptions are unlicensed admins (added as "Setup user" in an administrative-only access mode), environments with app pass capacity, non-interactive users, and free Dataverse plans from Microsoft 365 licenses when the user is added on demand [S12].
- If the environment has a security group, the user must be a member, unless the user is a tenant or Power Platform administrator [S12].
- To access an environment, a user needs a license with a Dynamics 365 or Power Platform recognized service plan (or active per-app plans in the environment) and at least one Dataverse security role, directly or through a group team [S73].
- License-based default role assignment doesn't apply to users in Dataverse for Teams, trial and developer environments [S59].
- A user license change can take a few minutes to synchronize to the environment [S12].

### 4.2 Ways to add the second user

| Method | What it does | Notes | Source |
| - | - | - | - |
| Just-in-time at first sign-in to the environment URL | Adds a qualified user | Requires the user to sign in | S73, S12 |
| An impersonation call | Triggers a just-in-time sync for the impersonated user | The MCP server's first `CallerObjectId` call does this | S73 |
| `POST systemusers(azureactivedirectoryobjectid=<user object ID>)/systemuserroles_association/$ref` | Assigns a role; adds the user to Dataverse first if missing | Documented in the group-team article | S86 |
| `GET SystemUser(azureactivedirectoryobjectid=<user object ID>)` | Retrieves the user; adds the user if missing | Documented in the group-team article | S86 |
| `pac admin assign-user --environment <id> --user <UPN or object ID> --role "<role>" [--business-unit <id>]` | Adds the user with a role | `--async` is deprecated and ignored | S10 |
| `Add-AdminPowerAppsSyncUser -EnvironmentName <id> -PrincipalObjectId <object ID>` | Adds a user to Dataverse | Windows PowerShell 5.x module | S64, S63, S12 |
| Admin center **Users** page | Adds or refreshes users on demand | | S12, S73 |
| Security group on the environment | Not available for developer environments | Sandbox only | S07, S05 |

No Power Platform API endpoint for adding another user to an environment was found; `applyAdminRole` elevates only the calling user [S68][S56].

### 4.3 Role assignment through the Web API

```http
POST [Organization URI]/api/data/v9.2/systemusers(azureactivedirectoryobjectid=<user object ID>)/systemuserroles_association/$ref
{ "@odata.id": "[Organization URI]/api/data/v9.2/roles(<role ID>)" }
```

- The pattern above is documented with v9.0 URLs [S86]. Teams take roles through `teams(<id>)/teamroles_association/$ref` [S86].
- A role can be assigned only to users enabled in the environment unless **allowRoleAssignmentOnDisabledUsers** is on [S75].
- Security roles belong to business units; unless record ownership across business units is on, users get only roles from their own business unit [S59].
- The assigner needs **Read** and **Assign** on the security role table and can't assign a role with more privileges than the assigner holds, checked by depth and business unit [S59]. The platform error is `AssignRoleValidationFailure`, `0x80048d3b` [S27].
- `RetrieveAadUserRoles(DirectoryObjectId=<object ID>)` and `RetrieveAadUserPrivileges(DirectoryObjectId=<object ID>)` return a user's roles and privileges, which suits a readiness check [S86].

### 4.4 The provisioning admin: self-elevation and access mode

- Global admins, Power Platform admins and Dynamics 365 admins don't get the System Administrator role automatically; they must self-elevate in each environment, and every elevation is logged to Microsoft Purview [S56].
- Self-elevation: `POST https://api.powerplatform.com/usermanagement/environments/{environmentId}/user/applyAdminRole?api-version=2024-10-01` [S68] (S56's sample script still uses `2022-03-01-preview`), `pac admin self-elevate` [S10], or **Membership** > **Add me** [S56]. Only the user who needs elevation can call it, role assignments through groups aren't supported, and a success reads `"Code": "UserExists"` [S56].
- Tenant-level admin roles don't grant Dataverse data access; a System Administrator assignment in the environment is needed [S55].
- An unlicensed Global admin, Power Platform admin or Dynamics 365 admin is enabled in the Administrative access mode [S12]; an administrative user has access to settings and administration features but not to customer data, apps or functionality [S12]. Derived from [S12]: load seed data as an application user (or as a licensed account), not as the unlicensed Global Administrator (OPEN QUESTIONS 7).

## 5. Provisioning identity and authentication

- The Power Platform API (app ID `8578e004-a5c6-46e7-913e-12f58912df43`) uses delegated permissions only; service principals get their access from a Power Platform RBAC role instead of application permissions [S22]. A user can call it with a token from `Get-AzAccessToken -ResourceUrl "https://api.powerplatform.com"` after `Connect-AzAccount` [S22]. The management plane (environments, billing policies, capacity) is the Power Platform API; the data plane is the Dataverse Web API [S79].
- Power Platform RBAC is in preview; it accepts users, security groups, app registrations and both system and user-assigned managed identities (by Enterprise object ID), and its four built-in roles (role-based access control administrator, reader, contributor, owner) are each listed with the tenant as assignable scope [S78]. RBAC governs the Power Platform API layer, while Dataverse keeps its own security roles for business data [S78]. Which API endpoints honor RBAC is listed in a known-limitations section that wasn't available in the fetched page [S78][S79] (OPEN QUESTIONS 8).
- The older service principal route: register the app with Power Platform through `PUT https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/adminApplications/{clientId}?api-version=2020-10-01` (preview); a service principal can't register itself, an administrator in username and password context must do it, and the registered service principal is treated like a user with the Power Platform Administrator role [S85]. Licenses can't be assigned to service principals [S85].
- Mandatory MFA: Phase 1 covers the Azure portal, Microsoft Entra admin center, Intune admin center and Microsoft 365 admin center; Phase 2 covers create, update and delete through Azure Resource Manager (`https://management.azure.com`) from Azure CLI, Azure PowerShell, SDKs and REST [S23]. Workload identities aren't affected; user accounts used for automation are [S23]. The resource owner password credentials (ROPC) grant is incompatible with MFA, and the MSAL and Azure Identity username-and-password APIs are deprecated [S23]. Derived from [S23]: calls to the Power Platform API and to Dataverse aren't in the listed enforcement scope, but a non-interactive Global Administrator sign-in works only while no MFA policy applies to that account.
- `pac auth create` supports `--username` and `--password`, `--applicationId` with `--clientSecret` or a certificate and `--tenant`, GitHub and Azure DevOps federation, `--deviceCode`, and `--managedIdentity`, which uses DefaultAzureCredential (set `AZURE_CLIENT_ID` for a user-assigned managed identity) [S24].
- Microsoft.PowerApps.Administration.PowerShell requires Windows PowerShell 5.x because it uses .NET Framework [S63]; `Add-PowerAppsAccount -Username -Password` signs in without a prompt [S63].
- Dataverse tokens: a confidential client (including an app-only token) uses the scope `<environment-url>/.default`; a public client uses `<environment-url>/user_impersonation` [S61]. Learn recommends managed identities over username and password flows where viable [S61].

## 6. Application user for the MCP server's user-assigned managed identity

- An application user is an unlicensed user for a Microsoft Entra registered application; one application user per application per environment [S19]. In the admin center you can enter an Azure Managed Identity Application ID (not the identity's name) [S19]; a Microsoft walkthrough creates an application user from a user-assigned managed identity's client ID this way [S74].
- Application users are created as non-interactive accounts, don't count toward the limit of seven non-interactive users, have no count limit, get "#" as First Name, and are enabled automatically [S12].
- Application users run in environments secured with a security group without being members; only inactive application users can be deleted [S19].
- Application users can't be included in a solution, so each environment needs its own creation step, for example a program using the web services [S77].
- Documented creation routes:
  - `pac admin assign-user --environment <id> --user <managed identity client ID> --role "<role name or ID>" --application-user [--business-unit <id>]`; without `--business-unit` the application user goes into the authenticated user's business unit [S10].
  - Admin center **Application users** > **+ New app user** [S19].
  - BAP `POST https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/{environmentId}/addAppUser?api-version=2020-10-01` with `{"servicePrincipalAppId": "<client ID>"}` (preview); it always assigns System Administrator and callers must be Power Platform administrators or a Power Platform service principal [S21].
- The Dataverse `applicationuser` table supports `POST /applicationusers` with writable `applicationid`, `applicationname`, `applicationtype`, `businessunitid` and `canimpersonateassystemuser`, and has an `applicationuserrole` relationship to roles and an `applicationuserprofile` relationship to field security profiles [S20]. No page documents it as a creation procedure (OPEN QUESTIONS 10).
- Roles: a custom security role must exist for a multi-tenant application user, and that article says an application user can't be associated with a default role [S77], while the admin center, `pac` and BAP all assign System Administrator [S10][S21] (OPEN QUESTIONS 11).
- `pac admin create-service-principal` creates a new app registration with a client secret plus its application user (default role System Administrator); it doesn't apply to an existing managed identity [S10].
- "Power Platform managed identity" is the reverse direction: Dataverse plug-ins reaching Azure resources through a user-assigned managed identity with federated credentials [S62]. It isn't needed for the MCP server.
- Derived from [S61][S19]: no federated credential is needed for the MCP server; the user-assigned managed identity gets its own app-only token for the scope `<environment-url>/.default`, and its application user maps that token to a Dataverse user.

## 7. Impersonation with CallerObjectId

- The impersonator needs **Act on Behalf of Another User** (`prvActOnBehalfOfAnotherUser`), included in the **Delegate** role or addable to any role [S13]. It must be assigned directly to the user (an application user is a user), never through a team [S13]. **Delegate** is a predefined role that can't be edited [S55].
- Effective privileges are the intersection: the impersonator can act only if both the impersonator and the impersonated user hold the privilege [S13].
- Header: `CallerObjectId: <impersonated user's Entra object ID>` (preferred), or the legacy `MSCRMCallerID: <systemuserid>` [S13][S28]. A null or empty caller ID returns `InvalidCallerId`, `0x80048d1A` [S27]; a caller without the privilege gets `CannotActOnBehalfOfAnotherUser`, `0x8004A110`, HTTP 403 [S27][S28].
- Records created by impersonation show the impersonated user in `createdby` and `owninguser` and the real caller in `createdonbehalfby`; updates use `modifiedonbehalfby` [S13].
- Audit records carry `callinguserid` when impersonation is used (null otherwise), and `userid` is "Changed By" [S14]. The relationship `lk_audit_callinguserid` links a user to the audit records they created while impersonating [S14]. Derived from [S13][S14]: an impersonated update shows the technician in `userid` and the MCP application user in `callinguserid` (OPEN QUESTIONS 12).
- An impersonation call triggers a just-in-time sync of the impersonated user [S73]; a disabled user returns `unManagedidsusernotenabled`, `0x80040225` [S27]. Derived from [S12][S73]: the Tier 1 Technician must hold a license for impersonated calls to succeed.
- Field security under impersonation: the on-premises 9.1 developer guide says Retrieve and RetrieveMultiple check whether the caller and the impersonated user have access to each record and each secured field, returning null for secured fields without access [S60]. The Dataverse online pages read today don't restate this (OPEN QUESTIONS 13).
- Service-to-service impersonation through an application user avoids a paid license for the impersonator [S13].
- `RetrievePrincipalAccess` can be called on behalf of a user to check that user's access rights to a record without attempting the change [S86].

## 8. Security roles, least privilege and business units

### 8.1 Privileges and access levels

- Table privileges are Create, Read, Write, Delete, Append, Append To, Assign and Share [S25]. Append attaches the current record to another; Append To lets other records be attached to the current one; for many-to-many relationships the user needs Append on both tables [S25][S26].
- Access levels: Organization, Parent: Child Business Unit, Business Unit, User, None [S25]. In the API the `PrivilegeDepth` values are `Basic` (0), `Local` (1), `Deep` (2), `Global` (3) and `RecordFilter` (4) [S31].
- Dataverse checks the privilege first without regard to depth, then the access check (ownership, role access by depth, sharing, hierarchy) [S26]. A record in a business unit that isn't a descendant of the user's business unit needs Organization level; a descendant needs Parent: Child; the same business unit needs Business Unit level [S26].
- Owning a record, or being in a team that owns it, gives access at any level once the privilege check passes [S26].
- Copy templates: **App Opener** has the minimum privileges to run an app, **Basic User** adds core business tables [S25][S75].

### 8.2 Create a role and set its privileges through the Web API

```http
POST [Organization URI]/api/data/v9.2/roles
{ "businessunitid@odata.bind": "businessunits(<business unit ID>)", "name": "Service Desk Tier 1 Technician" }

GET  [Organization URI]/api/data/v9.2/privileges?$select=name&$filter=name eq 'prvReadspk_Ticket'

POST [Organization URI]/api/data/v9.2/roles(<role ID>)/Microsoft.Dynamics.CRM.AddPrivilegesRole
{ "Privileges": [ { "Depth": "Global", "PrivilegeId": "<ID>", "BusinessUnitId": "<business unit ID>", "PrivilegeName": "prvReadspk_Ticket" } ] }

POST [Organization URI]/api/data/v9.2/roles(<role ID>)/Microsoft.Dynamics.CRM.ReplacePrivilegesRole
{ "Privileges": [ <RolePrivilege objects> ] }
```

- Role create and AddPrivilegesRole each return 204; a new role starts with nine default privileges (SharePoint data, SDK message and plug-in privileges); check the result with `roles(<id>)?$select=roleid&$expand=roleprivileges_association($select=name)` [S32].
- ReplacePrivilegesRole replaces the role's privilege set with the array passed [S29]. `RolePrivilege` carries `BusinessUnitId`, `Depth`, `PrivilegeId`, `PrivilegeName`, `RecordFilterId` and `RecordFilterUniqueName` [S30].
- Adding, updating or removing privileges on a role requires the caller to hold those privileges; otherwise `RoleUpdateValidationFailure`, `0x80048d3c` [S27].
- Role changes are audited as actions 57 (Add Privileges to Role), 58 (Remove) and 59 (Replace); role assignment to a user is action 55 and removal 56 [S14].
- After a role or permission change, the `Consistency: Strong` header returns the latest cached permissions within the roughly 30 seconds after the change [S28].

### 8.3 Append and Append To for ticket notes

- Derived from [S25][S26]: creating a ticket note that looks up its ticket needs Create and Append on the note table and Append To on the ticket table, plus Read on the ticket; the ticket table's Write privilege isn't needed for that.
- Dataverse notes (`annotation`) can't be audited [S16]. Derived from [S16]: keep ticket notes in the custom note table so note creation is audited.

### 8.4 Business-unit boundary with team-owned records

- Every business unit has one parent and a default team whose membership Dataverse manages; new users land in the root business unit [S57][S33].
- Owner teams can own records and hold security roles; access teams can't own records [S58][S33]. Changing a team member of an owner team requires privileges equal to or above the team's [S58].
- Business units and teams aren't solution components; create them in each environment [S33].
- Changing a user's business unit can remove all the user's role assignments; at least one role from the new business unit is needed [S57].
- Derived from [S26][S33]: the boundary holds only at Business Unit (Local) depth, or at Parent: Child depth when the protected records sit in a sibling business unit; Organization (Global) depth crosses every business unit. Records owned by a child business unit's team are reachable from the root business unit at Parent: Child or Organization depth.
- Derived from [S13][S26]: with impersonation, the narrower depth of the two principals decides, because both must pass (OPEN QUESTIONS 14).

### 8.5 Error codes the guide shows

| Situation | Error name | Hex / decimal | HTTP | Message template or behavior | Source |
| - | - | - | - | - | - |
| Tier 1 Technician asks for a priority change (no Write privilege) | PrivilegeDenied | `0x80040220` / -2147220960 | 403 | `{5} {2}(Id = {3}) is missing {0} privilege on {1} entity(OTC={4}). Consider adding missing privilege to one of the principal (user/team) roles for the request to succeed.` | S27, S28 |
| Write on a record outside the role's depth (business-unit boundary) | unManagedIdsAccessDenied | `0x80048306` / -2147187962 | Not listed in S28's status table | `{0} with id {1} does not have {2} right(s) for record with id {3} of entity {4}. Consider assigning a role with the {7} level to the user or team...` | S27, S28 |
| Application user lacks Delegate | CannotActOnBehalfOfAnotherUser | `0x8004A110` / -2147180272 | 403 | User doesn't have the privilege to act on behalf of another user | S27, S28 |
| Adding prvActOnBehalfOfAnotherUser to a role | CannotAddOrActonBehalfAnotherUserPrivilege | `0x8004Ed43` / -2147160765 | 403 | The privilege can't be added or removed | S27, S28 |
| Read of a secured column without permission | (no error) | | 200 | The column returns no data, indistinguishable from null | S34 |
| Update of a secured column without permission | AttributePermissionUpdateIsMissingDuringUpdate | `0x8004F507` / -2147158777 | 403 | User lacks update permission to the secured field | S27, S28 |
| Create with a secured column without permission | AttributePrivilegeCreateIsMissing | `0x8004F502` / -2147158782 | 403 | | S27, S28 |
| Read permission missing on a secured field | AttributePermissionReadIsMissing | `0x8004F504` / -2147158780 | 403 | | S27, S28 |
| Field security set but customizations unpublished | AttributeNotSecured | `0x8004F508` / -2147158776 | | Not enabled until published | S27 |
| Impersonated user disabled (for example unlicensed) | unManagedidsusernotenabled | `0x80040225` / -2147220955 | | The specified user is disabled | S27 |
| Service protection | | `0x80072322`, `0x80072321`, `0x80072326` | 429 | With `Retry-After` in seconds | S18 |

- The error body is `{"error":{"code":"<hex, often empty>","message":"..."}}`; `Prefer: odata.include-annotations="*"` adds `@Microsoft.PowerApps.CDS.HelpLink`, `TraceText`, `InnerError.Message` and the `ErrorDetails` annotations [S28].
- Derived from [S27][S28]: the guide should quote the hex code and the pattern of the message, not a fixed string, because the template's placeholders hold the principal, privilege and entity code.

## 9. Column security

- Column-level security is organization-wide, applies to every data access request, and needs the System Administrator role to configure [S35]. It doesn't apply to users with the System Administrator role, so tests need a non-admin account [S35].
- Columns that can't be secured: virtual table columns, lookups, formula columns, primary name columns and system columns such as `createdon`, `modifiedon`, `statecode` and `statuscode` [S35]. Eligibility follows `CanBeSecuredForCreate`, `CanBeSecuredForRead` and `CanBeSecuredForUpdate`; query them with `RetrieveMetadataChanges` [S34]. The developer page names telephone numbers and email addresses as typical columns to secure [S34], but no page read states the flags for `emailaddress1`, `telephone1` or `mobilephone` (OPEN QUESTIONS 15).
- Secure a column by retrieving its definition, setting `IsSecured` to true and updating it with `MSCRM.MergeLabels: true` and the solution unique name [S34]; field-level security isn't enabled until the customizations are published (`0x8004F508`) [S27].
- Profiles and permissions: create `fieldsecurityprofiles` records and `fieldpermissions` records with `fieldsecurityprofileid`, `entityname`, `attributelogicalname`, `cancreate`, `canread`, `canupdate` (0 Not Allowed, 4 Allowed) and `canreadunmasked` (0, 1 One Record, 3 All Records); link permissions through `lk_fieldpermission_fieldsecurityprofileid`, users through `systemuserprofiles_association` and teams through `teamprofiles_association` [S34]. The ApplicationUser table also has an `applicationuserprofile` relationship [S20]. The documented PowerShell sample associates an application user with a profile [S37].
- The System Administrator field security profile has ID `572329c1-a042-4e22-be47-367c6374ea45` [S34].
- Per-record field sharing uses `PrincipalObjectAttributeAccess` with `AttributeId` (the column `MetadataId`), `ObjectId`, `PrincipalId`, `ReadAccess` and `UpdateAccess` [S34].
- Behavior without access: by default the API returns no data for a secured column, and the caller can't tell it from null [S34]; forms and views show a lock icon and asterisks [S35]; until a profile is assigned, only System Administrators can access the column [S35].
- Masking returns a masked string instead; it needs a managed environment, supports text and number columns, and system and application users with Read and Read unmasked still receive masked values by default [S36]. `UnMaskedData=true` asks for unmasked values when the permission allows it [S76]. Audit records show masked values for masked columns [S36].
- Composite columns (contact `fullname`, `address1_composite`) need their source columns secured too; calculated and prompt columns that use a secured column can leak it [S35].
- Timing: clients need a browser refresh to see column security changes [S35]; the Microsoft sample waits 30 seconds for caches after creating roles and profiles [S37]; `Consistency: Strong` covers permission caches within about 30 seconds [S28].
- In Purview activity logs, secured column values appear as `*` [S35][S80].
- Field security profiles are solution component type 70 and field permissions type 71 [S38]; profiles move between environments in solutions, while assigning users and teams is per environment [S33].

## 10. Auditing

- Three levels: environment, table and column; all three must be on to log changes [S16]. The organization row holds `isauditenabled`, `auditretentionperiodv2` (developer guide: default 30 days, 1 to 365,000, -1 keeps forever), `isuseraccessauditenabled`, `useraccessauditinginterval` (default 4 hours) and `auditsettings` [S15]. Changing them needs System Administrator or System Customizer [S15].
- Update with `PATCH [Organization URI]/api/data/v9.2/organizations(<organizationid>)` and `If-Match: *`; the organization ID comes from the single organization row or `WhoAmI` [S15].
- Tables and columns use the managed property `IsAuditEnabled` (`Value`, `CanBeChanged`, `ManagedPropertyLogicalName: canmodifyauditsettings`); changes take effect only after publishing, for example `PublishXml` with `<importexportxml><entities><entity>contact</entity></entities></importexportxml>` [S15].
- Audit records are written when audited records change; update records only when the value actually changes [S16]. Retrieve and export operations, definition changes and authentication aren't audited [S16]. Derived from [S16]: a request that Dataverse denies changes nothing, so it leaves no Dataverse audit record; the MCP and gateway logs are the evidence for denials.
- Audit logs live in log storage and can appear with a delay in **Audit History** and **Audit Summary** [S16]; no duration is given (section 16.5).
- Reading: entity set `audits` (read-only), needs `prvReadAuditSummary`; not available through the TDS endpoint [S14]. Columns: `action`, `operation` (1 Create, 2 Update, 3 Delete, 4 Access), `_objectid_value`, `objecttypecode`, `_userid_value`, `_callinguserid_value`, `createdon` (milliseconds since July 2025), `transactionid`; don't use `attributemask` [S14]. Only one link entity per query, so `userid` and `callinguserid` can't both be expanded at once [S14].

```http
GET [Organization URI]/api/data/v9.2/audits?$select=_objectid_value,objecttypecode,createdon,_userid_value,_callinguserid_value,action,operation&$filter=objecttypecode eq 'spk_ticket' and _objectid_value eq <ticket ID>&$orderby=createdon desc
Prefer: odata.include-annotations="*"
```

- The `Prefer` header returns formatted lookup names, as in the documented example [S14]. `audits(<id>)/Microsoft.Dynamics.CRM.RetrieveAuditDetails` returns old and new values [S14].
- `RetrieveRecordChangeHistory` and `RetrieveAttributeChangeHistory` need `prvReadRecordAuditHistory` and `prvReadAuditSummary`; in the Web API their `AuditDetail` results don't include the audit record, so who and when come from the `audits` query [S14]. Values above about 5 KB are truncated [S14].
- In the app, **Audit History** needs **View Audit History** and **Audit Summary** needs **View Audit Summary** [S16].
- Retention: the developer guide gives a default of 30 days [S15], while the admin guide's retention policy defaults to **Forever** [S16] (OPEN QUESTIONS 16). Changing the retention period doesn't change the retention stamped on existing records [S16].
- Non-auditable tables include `Annotation` and `ActivityPointer` [S16].
- Purview: user access and activity logging go to Purview only for production environments [S16][S80]; before-and-after values are no longer sent to Purview since May 2026 [S02][S80].

## 11. Request limits and service protection

- Licensed users: paid Power Platform licenses such as Power Apps Premium give 40,000 requests per user per 24 hours; Power Apps per app, Microsoft 365 and pay-as-you-go users get 6,000 [S17].
- Non-licensed identities (application users, non-interactive users, administrative users and SYSTEM) share a tenant pool; with Power Apps licenses it's 25,000 base requests per 24 hours with no per-license accrual, and individual application users don't get their own allowance [S17]. Enforcement of the official limits starts at least six months after Power Automate usage reporting is generally available [S17].
- Service protection limits are per user and per web server over a sliding 300-second window: 6,000 requests, 1,200 seconds of combined execution time and 52 or more concurrent requests; application users have the same limits [S18]. Exceeding them returns 429 with `Retry-After`; trial environments get a single web server [S18].
- Batches don't bypass entitlement limits; start with batches of about 10 and add concurrency [S18].
- Derived from [S17][S18]: one tenant per participant gives every participant its own 25,000-request pool and its own service protection counters; whether an impersonated call counts against the application user or the impersonated user isn't documented (OPEN QUESTIONS 17).

## 12. Packaging the Dataverse deliverable as a solution

- Every solution needs a publisher (customization prefix, unique name, friendly name), and Learn recommends a custom publisher and solution for deployment [S40]. The unique name allows only alphanumeric characters and underscore; versions use major.minor.build.revision [S40].
- Put components in the solution as they're created: `MSCRM.SolutionUniqueName` works with `Create` (POST), `Update` (PATCH), `Delete`, `AddPrivilegesRole` and `MakeAvailableToOrganizationTemplate` [S76][S28]. Components created this way land in both the default solution and the named one [S83].
- `AddSolutionComponent` adds an existing component: `ComponentId`, `ComponentType`, `SolutionUniqueName`, `AddRequiredComponents`, `DoNotIncludeSubcomponents`, `IncludedComponentSettingsValues` [S39]; it needs System Administrator or System Customizer [S83]. Use it only with a known component type; some newer types aren't in the `componenttype` choice [S83][S40].
- Component types used here: 1 Entity, 2 Attribute, 9 Option Set, 10 Entity Relationship, 14 Entity Key, 20 Role, 21 Role Privilege, 26 Saved Query, 60 System Form, 61 Web Resource, 62 Site Map, 70 Field Security Profile, 71 Field Permission [S38]. The model-driven app (`appmodule`) isn't in that list [S38]; derived from [S83][S76]: create the app with the `MSCRM.SolutionUniqueName` header.
- `pac solution add-solution-component --solutionUniqueName <name> --component <schema name or ID> --componentType <type> [--AddRequiredComponents]` is the CLI equivalent [S44].
- Publish before export: only published customizations are exported with a solution, and creating or deleting items publishes automatically while updates to definitions that affect the UI need an explicit publish [S87]. `PublishXml` publishes named components; `PublishAllXml` and `pac solution publish` publish all customizations [S87][S44].
- Export: `ExportSolution` with `SolutionName` and `Managed` (plus optional `Export*Settings` flags and `ExportComponentsParams`) returns the file [S43]; `ExportSolutionAsync` returns `AsyncOperationId` and `ExportJobId`, then `DownloadSolutionExportData` returns `ExportSolutionFile` [S41]. CLI: `pac solution export --name <name> --path <zip> [--managed] [--async]` [S44].
- Import: `ImportSolutionAsync` takes `CustomizationFile`, `OverwriteUnmanagedCustomizations`, `PublishWorkflows`, `HoldingSolution`, `ComponentParameters`, `SolutionParameters` and more, and returns `ImportJobKey` and `AsyncOperationId` [S42][S41]. Poll `asyncoperation` until `statecode` 3; `statuscode` 30 is success, 31 failure, and `RetrieveFormattedImportJobResults` gives the log [S41]. `StageSolution` validates and returns a `StageSolutionUploadId` [S41]. The synchronous `ImportSolution` can use an `ImportJobId` to read the `importjob` row [S40]. CLI: `pac solution import --path <zip> [--async] [--publish-changes] [--force-overwrite] [--import-as-holding] [--stage-and-upgrade] [--skip-lower-version] [--settings-file <json>] [--max-async-wait-time <minutes>]` [S44].
- Unattended `pac`: `pac auth create` with a service principal (`--applicationId`, `--clientSecret` or certificate, `--tenant`), with `--managedIdentity`, or with `--username` and `--password` [S24]; the service principal must also be an application user in the target environment [S24].
- Not carried by solutions: application users [S77], business units and teams [S33], user role assignments and profile assignments [S33]. Organization audit settings are organization-table columns set by request [S15].
- Managed solutions: custom components are customizable by default; `IsCustomizable` set to false locks a component after a managed import; security roles have `Role.IsCustomizable` [S81]. You can't develop an update for a managed solution in an environment where it's installed [S81]. Derived from [S81]: keep roles customizable if Exercise 5 asks participants to edit a solution-shipped role.
- Learn's multi-tenant guidance: ship the custom role in a managed solution and create the application user with your own program or Package Deployer [S77].

## 13. The model-driven app through the Web API (re-verified)

1. Create the app: `POST [Organization URI]/api/data/v9.0/appmodules` with at least `name`, `uniquename` (English letters and digits; the publisher prefix is added) and `webresourceid` (default icon `953b9fac-1e5e-e611-80d6-00155ded156f`); 204 with `OData-EntityId` [S45]. System Administrator or System Customizer is required [S45].
2. Create the sitemap: `POST /sitemaps` with writable `SiteMapName`, `SiteMapNameUnique`, `SiteMapXml`, `IsAppAware`, `ShowHome`, `ShowPinned`, `ShowRecents`, `EnableCollapsibleGroups`; `ComponentState` tracks published and unpublished [S46].
3. Add components: `POST /AddAppComponents` with `AppId` and `Components`, each with its ID and `@odata.type` (for example `Microsoft.Dynamics.CRM.savedquery` with `savedqueryid`, `Microsoft.Dynamics.CRM.systemform` with `formid`); `RemoveAppComponents` takes the same parameters [S45].
4. Validate: `GET /ValidateApp(AppModuleId=<id>)` returns `AppValidationResponse` with `ValidationSuccess` and `ValidationIssueList`; a missing sitemap is an Error, "App does not contain Site Map" (`CRMErrorCode` -2147155684); a table without a referenced form or view is a Warning (-2147155691) [S45].
5. Publish: `POST /PublishXml` with `<importexportxml><appmodules><appmodule><id></appmodule></appmodules></importexportxml>` [S45].
6. Share: `POST appmodules(<id>)/appmoduleroles_association/$ref` with `{"@odata.id":"[Organization URI]/api/data/v9.0/roles(<roleId>)"}`; the published example omits the slash before `appmoduleroles_association`, while the delete example has it [S45].
7. Read: published apps from `appmodules`; unpublished ones from `appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()`; components from `RetrieveAppComponents(AppModuleId=<id>)`; roles with `$expand=appmoduleroles_association` [S45].

- Sharing limits in managed environments cover canvas apps, flows and agents [S82]. Derived from [S82][S45]: they don't restrict the model-driven Service Desk app, which is shared through security roles.

## 14. Roles: view versus manage

| Role | View | Manage (create, change, delete, approve) | Source |
| - | - | - | - |
| Global Administrator (Entra) | Tenant settings, analytics, capacity | Create environments when restricted; self-elevate; no Dataverse data access until elevated; unlicensed means Administrative access mode | S06, S56, S55, S12 |
| Power Platform Administrator (Entra) | Same | Enable or edit managed environments; billing policies for all environments; self-elevate | S04, S50, S56 |
| Dynamics 365 Administrator (Entra) | Same | Enable or edit managed environments; self-elevate (must be in the environment's security group if it has one) | S04, S56 |
| Environment Admin (environment role) | Environment resources | Can't change the managed property; can create billing policies and link environments it administers | S04, S50, S55 |
| System Administrator (Dataverse) | All data, including secured columns | Column security, auditing settings, roles, solution import, users and application users | S35, S15, S59, S55 |
| System Customizer (Dataverse) | | Audit settings, create model-driven apps, add solution components | S15, S45, S83 |
| Delegate (Dataverse, predefined) | | `prvActOnBehalfOfAnotherUser`; direct assignment only | S13, S55 |
| App Opener and Basic User (Dataverse, predefined) | Minimum to run an app; Basic User adds core tables | | S25, S75 |
| Custom Service Desk Senior Technician | Service Desk tables | Ticket write and ticket notes | Design (SOW) |
| Custom Service Desk Tier 1 Technician | Service Desk tables | None | Design (SOW) |
| MCP application user (custom read and write roles plus Delegate) | Through its roles | Through its roles, intersected with the impersonated user's | S19, S13 |

Page-level exceptions:

| Page or task | Roles that can view | Roles that can manage | Source |
| - | - | - | - |
| Configure column security and profiles | | System Administrator | S35 |
| Turn auditing on or off | Anyone can view the configuration | System Administrator or System Customizer | S15, S16 |
| **Audit History** and **Audit Summary** | Holders of **View Audit History** and **View Audit Summary** | | S16 |
| Assign security roles | | Read and Assign on Security Role, and no more privileges than the assigner holds | S59 |
| Edit role privileges | | Caller must hold the privileges being changed | S27 |
| Owner team membership | | Privileges at or above the team's | S58 |
| Capacity report **Summary** tab | Tenant admin, Power Platform admin, Dynamics 365 admin | | S71 |
| Self-elevation | | Global, Power Platform or Dynamics 365 admin, for themselves only | S56 |

- Least-privilege role to view everything a participant must see: the custom Senior Technician role plus **View Audit History** [S16][S25]. If Exercise 5 Task 3 (edit a role) and Exercise 6 Task 1 (secure a column, create a profile) stay hands-on, the Senior Technician also needs the Dataverse System Administrator role in the environment [S35][S59][S27], which is not a tenant administrator role [S55]; then column security no longer hides data from that user in the app [S35].
- Assign the System Administrator role directly to users [S59].

## 15. Licensing and pricing

| Capability | Developer Plan only | Power Apps Premium | Source |
| - | - | - | - |
| Run an app in a managed developer environment | No: no managed environment use rights | Yes | S01, S03 |
| Run a model-driven app anywhere | Only inside a developer environment that isn't managed | Yes | S01, S53 |
| Create or preview an app in a managed developer environment | Yes: no premium license needed to create or preview | Yes | S08 |
| Be added to Dataverse as an enabled user | Yes (a valid license) | Yes | S12 |
| Daily Power Platform requests | Not listed | 40,000 per user per 24 hours | S17 |
| Dataverse capacity | 2 GB per developer environment, not pooled | +250 MB database, +2 GB file per license; 10 GB tenant default with the first subscription | S01, S54, S72 |

- Power Apps Premium: string ID `POWERAPPS_PER_USER`, SKU ID `b30411f5-fea1-4a59-9ad9-3db7c7ead579` [S70]; list price $20.00 per user per month, paid yearly, as shown on 2026-11-06 (marketing price; actual price at checkout) [S54].
- Microsoft PowerApps for Developer: `POWERAPPS_DEV`, `5b631642-bd26-49fe-bd20-1daaa972ef80` [S70]; free [S54]. The pricing page still lists "three developer environments" [S54], which Learn's deprecation contradicts [S01][S02] (OPEN QUESTIONS 18).
- Microsoft Power Apps Plan 2 Trial: `POWERAPPS_VIRAL`, `dcb1a3ae-b33f-4487-846a-a640262fadf4` [S70]. The Power Apps trial gives the per user plan for 30 days [S01]; trial licenses can license users in managed environments within their 30-day limit [S03] and can be renewed only three times [S53].
- Qualifying licenses for managed environments: Power Apps Premium, Power Automate Premium, Microsoft Copilot Studio, Power Pages, Dynamics 365 Premium, Enterprise, Team Members and Customer Insights, plus the pay-as-you-go meters for Power Apps per app, Power Pages and Copilot Studio [S03].
- Pay-as-you-go: links an environment to an Azure subscription through a billing plan, which creates a Power Platform account resource in a chosen resource group [S49][S50]; available for production and sandbox environments only [S50][S52]; the Power Apps per-app meter costs $10 per active user per app per month, and per-user licensed users aren't counted [S51]. A pay-as-you-go environment includes 1 GB database and 1 GB file; extra database is $48 per GB per month, file $2.40, and log (auditing) $12 per GB per month [S51][S52]. Per-app licenses can't be used in a pay-as-you-go environment [S52].
- Dataverse database capacity add-on: $40.00 per GB per month, paid yearly [S54].
- License assignment through Microsoft Graph: `POST /users/{id}/assignLicense` with `addLicenses` (`skuId`, `disabledPlans`) and `removeLicenses`; least privilege `LicenseAssignment.ReadWrite.All`; delegated callers need Directory Writers, License Administrator or User Administrator [S69].
- Multiplexing (software that pools connections or reduces the users who directly access Power Apps) to reduce licenses is a license violation [S72]. Derived from [S72][S12][S73]: license both technicians even for the MCP path, which also keeps them enabled for impersonation.
- `Get-AdminPowerAppLicenses` exports assigned Power Apps and Power Automate licenses, but only for users who have accessed Power Platform services, so a technician who never signed in doesn't appear in it [S63]. Derived from [S63]: check license assignment through Microsoft Graph in the readiness report instead.
- Per tenant in this design: two Power Apps Premium licenses (Senior and Tier 1); application users are unlicensed [S19]; the Global Administrator can stay unlicensed if seeding runs as an application user [S12].

## 16. LAB FEASIBILITY (25 participants per workshop plus 2 spares, one Microsoft Entra tenant per participant)

### 16.1 Constraints that drive the design

- Every participant tenant needs its own Dataverse environment, and from 2026-11-15 that can only be a managed developer environment (or another type such as sandbox) [S02][S06]. Derived from [S02]: assume every workshop runs after 2026-11-15.
- Managed environments require a qualifying license for every user who runs an app; in-app notices escalate every 7 days, and from February 2027 unlicensed users can't open the app [S03][S53]. Derived from [S03]: both technicians need Power Apps Premium (or a trial) before the lab starts.
- One managed developer environment per user [S02]; the effect of `usedBy` on that count isn't documented [S09]. Derived from [S02]: in a dedicated tenant the Global Administrator creates exactly one environment, so the limit isn't hit even if it counts the creator.
- Only the creator is added to a developer environment; everyone else is added on demand, with a license [S12][S01].
- Tenant admins must self-elevate and, when unlicensed, run in the Administrative access mode [S56][S12].
- Mandatory MFA Phase 2 targets Azure Resource Manager; Dataverse and the Power Platform API aren't in its listed scope, and ROPC sign-ins break once any MFA policy applies [S23].
- Legacy admin cmdlets need Windows PowerShell 5.x [S63]; some tenants need a macro region [S84].
- A tenant with Power Apps licenses has a 25,000-request daily pool for application users [S17]; service protection is per user and per web server [S18].
- Managed developer environments are disabled after 60 days without activity [S47]; spares and the 24-hour reviewer window are well inside that.
- Deleted environment URLs can't be reused for 24 hours [S05]. Derived from [S05]: put the DeploymentID in the domain name.
- Dataverse activity logs reach Purview only from production environments [S16][S80]. Derived from [S16][S80]: the correlated trail uses Dataverse's native audit plus the MCP and gateway logs.

### 16.2 Recommended role set

- Participants: the Senior Technician holds the custom Senior role plus **View Audit History**; the Tier 1 Technician holds only the custom read-only role [S16][S25]. Neither holds an Entra admin role (SOW). If the guide keeps role and column-security editing hands-on, the Senior Technician also needs the Dataverse System Administrator role [S35][S59], which bypasses column security in the app [S35]; decide this in BUILD-SPEC.
- MCP application user (`id-mcp`): Service Desk Agent Read, Service Desk Agent Write and the predefined **Delegate**, all directly assigned, never System Administrator [S13][S55][S19].
- Provisioning: the CloudLabs-held Global Administrator creates the environment and self-elevates [S09][S68]; a provisioning application user (for example the lab VM's managed identity) holds System Administrator during provisioning for solution import and seeding, then is reduced to a read role or deactivated [S19][S12].
- Never hand out: Global Administrator, Power Platform Administrator or Dynamics 365 Administrator, because each can self-elevate to System Administrator in any environment [S56].

### 16.3 Task classification

| Task | Mode | Role needed | Why | Source |
| - | - | - | - | - |
| 1.1 Verify readiness (app and row counts, Tier 1 user present) | Hands-on, read-only | Senior role | Reads only | S25 |
| 1.4, 2.1 to 2.4 Verify answers in the Service Desk app | Hands-on, read-only | Senior role, Power Apps Premium | Model-driven app needs premium rights | S53, S03 |
| 3.1, 3.2 Trace a read tool to the Web API and `CallerObjectId` | Hands-on, read-only | Senior role | Own tenant | S13 |
| 4.1, 4.2, 4.3, 4.5 Approved writes, public reply and internal note | Hands-on, write | Senior role; `id-mcp` with Agent Write and Delegate | Writes only to the participant's own environment | S13 |
| 5.1 Find the application user in the admin center | Hands-on, read-only | Senior with environment admin access in the admin center | Needs a pilot check that a non-tenant-admin can open **Application users** | S19 |
| 5.3 Narrow the Agent Write role to Business Unit and see Dataverse refuse | Hands-on, write | Senior as Dataverse System Administrator (role edit) | Edits a role in its own tenant only; error `0x80048306` | S27, S59, S26 |
| 5.4 Tier 1 denied, Senior allowed, audit shows the user | Hands-on, write | Tier 1 and Senior roles; both licensed | Denial is `0x80040220`; only the allowed change is audited | S27, S16, S14 |
| 6.1 Secure a contact column and add a profile | Hands-on, write | Senior as Dataverse System Administrator | Column security needs System Administrator | S35 |
| 6.3, 7.1 Trace one action end to end with the Dataverse audit | Hands-on, read-only | Senior with **View Audit History** | Reads audit only | S16, S14 |

### 16.4 Pre-seeding checklist (per tenant, in order)

1. Before the workshop: confirm the tenant has Power Apps Premium (or trial) seats and assign them to both technicians with Graph `assignLicense` [S69][S70]; keep **Environment routing** off and set **Environment assignments: Developer**, **Production** and **Trial** to **Only specific admins** [S08][S06].
1. Create the managed developer environment with one Power Platform API request (`environmentSku` Developer, `protectionLevel` Standard, `usedBy` the Senior Technician, unique domain) and poll the operation [S09][S67]. Fallback: the same request without `usedBy`, then a sandbox [S09][S05].
1. Self-elevate the Global Administrator with `applyAdminRole` [S68].
1. Create the provisioning application user for the VM's managed identity with `pac admin assign-user --application-user --role "System Administrator"` [S10].
1. As the provisioning application user: import the managed Service Desk solution with `ImportSolutionAsync` and wait for `statuscode` 30 [S42][S41]; turn on organization auditing (`isauditenabled`, `auditretentionperiodv2`) [S15]; create the business unit and give its default team a role from that business unit [S57][S58][S59]; secure the baseline contact columns and assign profiles [S34].
1. Add both technicians with their roles (`pac admin assign-user` or `systemuserroles_association` by object ID) and remove any role the platform added that the design doesn't want [S10][S86][S59].
1. Create `id-mcp`'s application user with the read role, then associate the write role and **Delegate** [S10][S86][S13].
1. Seed the data as the provisioning application user, respecting `Retry-After` [S18]; share the app with the technician roles [S45].
1. Readiness: `RetrieveAadUserPrivileges` for both technicians, `RetrievePrincipalAccess` on behalf of the Tier 1 Technician to confirm no write access, and a `WhoAmI` with `CallerObjectId` to trigger the just-in-time sync [S86][S73]; record the solution version as the Golden Environment version [S40].
1. Event day: participants only read and change their own environment; no instructor demo is needed for the Dataverse tasks (derived from section 16.3).

### 16.5 Data latency

| Signal or change | Documented latency | Source |
| - | - | - |
| Developer environment provisioning (sign-up flow) | A couple of minutes | S48 |
| Managed developer environment provisioning through the API | Not documented | none |
| License assignment synchronized into the environment | A few minutes | S12 |
| Role and permission changes in cached permissions | Up to about 30 seconds; `Consistency: Strong` bypasses | S28 |
| Column security changes in the app | Needs a browser refresh | S35 |
| Field security profiles and roles in API reads (sample) | Sample waits 30 seconds | S37 |
| Audit records in **Audit History** and **Audit Summary** | Delayed, duration not documented | S16 |
| User access audit | Logged per interval, default 4 hours | S15 |
| Solution import (asynchronous) | Not documented; poll `asyncoperation` | S41 |
| Sharing rules in managed environments | Up to an hour | S82 |
| Admin role cache before an unlicensed admin can create an environment | 12 hours (stated for finance and operations templates) | S84 |

### 16.6 Timing and fallbacks

- Run every Dataverse step during deployment; the readiness report runs after the just-in-time sync of both technicians [S73][S86].
- After any role edit in a task, tell participants to wait about a minute or send `Consistency: Strong` from the server [S28].
- If the Developer request with `usedBy` fails validation, retry without `usedBy`; if developer creation is refused, create a sandbox, which keeps the same licensing and isn't cleaned up for inactivity [S09][S47][S01].
- If impersonated field security doesn't behave as the guide expects, assign the column security profile to both the application user and the technician and record the result for the design pack [S60][S34].
- Keep the denial evidence in the MCP log and the absence of a Dataverse audit row, since Dataverse audits only changes [S16].

## 17. SCREENSHOT SOURCES

All URLs below returned HTTP 200 on 2026-11-06 (header requests); relative media paths were resolved against each page URL.

- https://learn.microsoft.com/power-platform/admin/media/managed-environment-licensing/informational-license-message.png : in-app notice when an unlicensed user opens an app in a managed environment [S03]
- https://learn.microsoft.com/power-platform/admin/media/managed-environment-licensing/error-license-message.png : final notice stage before blocking [S03]
- https://learn.microsoft.com/power-platform/admin/media/default-environment-routing/diagram-environment-routing.png : how routing places makers in personal developer environments [S08]
- https://learn.microsoft.com/power-platform/admin/media/environments-overview/environments.png : a tenant with three environments, each with its own Dataverse [S07]
- https://learn.microsoft.com/power-platform/developer/media/power_apps_dev_env_app_banner.png : banner on apps in a developer environment [S01]
- https://learn.microsoft.com/power-platform/admin/media/see-all-security-roles.png : **Access** tile, **Security roles** **See all** [S75]
- https://learn.microsoft.com/industry/nonprofit/media/dsa-managed-identity-clientid.png : a managed identity's client ID in the Azure portal [S74]
- https://learn.microsoft.com/industry/nonprofit/media/dsa-new-app-user.png : **+ New app user** [S74]
- https://learn.microsoft.com/industry/nonprofit/media/dsa-add-app-search.png : searching for the managed identity's client ID [S74]
- https://learn.microsoft.com/industry/nonprofit/media/dsa-add-managed-identity.png : selecting the managed identity and **Add** [S74]
- https://learn.microsoft.com/industry/nonprofit/media/dsa-add-business-unit.png : **Business unit** and **Create** [S74]
- https://learn.microsoft.com/power-platform/admin/media/field-security-advanced-options-enable.png : **Advanced options** > **Enable column security** [S35]
- https://learn.microsoft.com/power-platform/admin/media/field-security-enable-column-security.png : the enabled checkbox on an eligible column [S35]
- https://learn.microsoft.com/power-platform/admin/media/admin-field-level-security-lock.png : lock icon and asterisks for a secured value [S35]
- https://learn.microsoft.com/power-apps/developer/data-platform/media/fieldsecurityprofile-erd.png : field security profile, permission and principal relationships [S34]
- https://learn.microsoft.com/power-platform/admin/media/create-and-manage-masking-rules/select-masking-rule.png : **Masking rule** on a secured column [S36]
- https://learn.microsoft.com/power-platform/admin/media/dataverse-audit-log-single-record.png : **Audit History** for one record [S16]
- https://learn.microsoft.com/power-platform/admin/media/dataverse-audit-log-summary.png : **Audit Summary** view [S16]
- https://learn.microsoft.com/power-platform/admin/media/dataverse-audit-select-audit-history.png : **Related** > **Audit History** [S16]
- https://learn.microsoft.com/power-platform/admin/media/dataverse-audit-changes-to-data.png : **Audit changes to its data** on a table [S16]
- https://learn.microsoft.com/power-platform/admin/media/dataverse-audit-enable-auditing.png : **Enable auditing** on a column [S16]
- https://learn.microsoft.com/power-platform/admin/media/wp-security-cds/hierarchical-business-unit-data-access-example.png : hierarchical business unit access [S33]
- https://learn.microsoft.com/power-platform/admin/media/member-privilege-inheritance.png : **Member's privilege inheritance** on a role [S26]
- https://learn.microsoft.com/power-platform/admin/media/pay-as-you-go-azure-relationship.png : environment linked to an Azure subscription [S49]

## 18. OPEN QUESTIONS

1. `usedBy` semantics are undocumented [S09][S11]: does the Senior Technician become owner, System Administrator, or neither, and is the "one managed developer environment per user" limit [S02] counted against the creator or the `usedBy` user? Test in the pilot tenant before 2026-11-15 if possible, and again after.
1. After 2026-11-15, does `pac admin create --type Developer` or `New-AdminPowerAppEnvironment -EnvironmentSku Developer` fail, or create a managed environment? S02 says unmanaged creation is blocked from PowerShell and CLI, and neither tool has a managed flag [S10][S65]. Use the single API request [S09] and test the others.
1. Does the 12-hour admin role cache [S84] stop a just-created Global Administrator from creating an environment in a brand-new tenant? Fallback: license the provisioning account, or start provisioning after the cache window.
1. Provisioning time for an admin-created managed developer environment isn't documented [S48]. Measure it against acceptance criteria 12 (reset within 60 minutes) and 14 (spare within 15 minutes).
1. Workshop dates aren't in the SOW. If any run before 2026-11-15, unmanaged developer environments still exist but are suspended from 2026-12-15 [S02]; plan only managed environments.
1. Is the 2 GB database cap [S01] the same for an admin-created managed developer environment? Check the environment's capacity page after seeding.
1. Can a self-elevated but unlicensed Global Administrator (Administrative access mode [S12]) import a solution and create records? Test; the recommended path seeds as an application user.
1. Which Power Platform API endpoints accept RBAC-authorized managed identities [S78]? If environment provisioning does, the VM's managed identity could replace the Global Administrator's password; the known-limitations list wasn't in the fetched page [S79].
1. Is a non-interactive Global Administrator sign-in (ROPC) blocked by any default policy in CloudLabs tenants? S23 says ROPC fails once MFA applies; confirm the tenant has no such policy.
1. Raw Web API creation of an application user (`POST systemusers` with `applicationid` and `businessunitid`, or `POST applicationusers` [S20]) isn't documented as a procedure; S77 only says you can write your own program. Use `pac admin assign-user --application-user` [S10] and test the raw call in the pilot.
1. Conflict: S77 says an application user can't take a default security role, while `pac`, the admin center and BAP assign System Administrator [S10][S21]. Confirm that `Delegate` (a predefined role) can be assigned to the application user, and that the error `0x8004Ed43` [S27] means custom roles can't receive `prvActOnBehalfOfAnotherUser` despite S13 saying any role can.
1. Confirm in the pilot that an impersonated update writes the technician to `userid` and the MCP application user to `callinguserid` [S14], and that the app's **Audit History** shows both.
1. Field security under impersonation in Dataverse online: S60 (on-premises 9.1) says both caller and impersonated user are evaluated. Exercise 6 Task 1 depends on it: with the Senior Technician as System Administrator, mobile numbers stay hidden only if the application user's profile is part of the evaluation.
1. Depth intersection under impersonation: S13 states the intersection for privileges; confirm that the application user's Business Unit depth blocks the Senior Technician's Organization depth for a child business unit's records (Exercise 5 Task 3).
1. Can `emailaddress1`, `telephone1` and `mobilephone` on contact be secured for read? Run `RetrieveMetadataChanges` for `CanBeSecuredForRead` [S34] in the build environment.
1. Conflict on audit retention default: 30 days [S15] versus **Forever** [S16]. Set `auditretentionperiodv2` explicitly.
1. Does an impersonated request consume the application user's tenant pool or the technician's 40,000 daily requests [S17]? Not documented; irrelevant at lab volumes but needed for the design pack.
1. The pricing page still advertises three developer environments for the Developer Plan [S54], contradicting S01 and S02. Treat Learn as current.
1. Which principal does the PrivilegeDenied message name under impersonation, the technician or the application user [S27]? Capture the real string in the pilot for the guide's expected result.
1. HTTP status for `unManagedIdsAccessDenied` (`0x80048306`) isn't in S28's table; capture it in the pilot (expected 403).
1. Can a user who is Dataverse System Administrator but no tenant admin open the admin center pages in Exercise 5 (**Application users**, **Security roles**)? Not stated in the pages read; test with the Senior Technician.
1. The model-driven app's `componenttype` value isn't in the documented choice list [S38]; confirm that creating the app with `MSCRM.SolutionUniqueName` [S76] adds it to the solution, and whether `ReplacePrivilegesRole` honors the header (S76 lists only `AddPrivilegesRole`).
1. Masking rules: the admin page has no preview label [S36] while S76 calls the feature preview; masking now becomes possible because the environment is managed [S36]. Decide whether the guide uses it.
1. Default managed environment settings for an API-created environment (solution checker mode, sharing limits) aren't documented; routed environments get solution checker **Warn** and five-person sharing [S08]. Set them explicitly with `pac admin set-governance-config` [S10] so solution checker can't block the import.
1. The group-team article's add-on-assign behavior [S86] is described for Microsoft Entra group users; confirm it adds an ordinary licensed user with no group team.
1. Whether `az account get-access-token --resource https://api.powerplatform.com` works like the documented `Get-AzAccessToken` [S22] for the Power Platform API from Azure CLI isn't documented.
1. Label drift: **Environment assignments: Developer** [S06], **Developer environment assignments** [S02], **Environment assignment: Developer** [S08]. Use S06's label in the guide.
