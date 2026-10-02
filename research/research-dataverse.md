# Dataverse research: Service Desk MCP lab (CloudLabs)

Research date: 2026-10-01. Sources: current Microsoft Learn pages only, retrieved with the Microsoft Learn MCP tools (search, then full fetch of the key pages). Every bullet ends with its source URL. JSON snippets keep the property names and shapes shown in the docs; table and column names are adapted to the lab (prefix `msp_`). Anything the docs did not confirm is listed under "Unverified or contradictory".

Partial reads (stated for transparency): of `web-api-metadata-operations-sample` only Sections 0, 8, 9 and 10 were read; of the developer page `column-level-security` the discover, secure, provide-access, field-sharing and masking sections were read, not every code sample.

## 1. Developer environments

### Who can create them and the governing tenant setting
- Developer environments are created by users who have the Developer Plan license. They are meant to be used only by the owner, and admins can restrict who provisions them. Security groups can't be assigned to developer environments. https://learn.microsoft.com/power-platform/admin/environments-overview
- Self-service: signing up for the Power Apps Developer Plan (on the website, in Power Apps, or in PPAC) automatically creates one developer environment named after the user. Any further developer environments have to be created manually. https://learn.microsoft.com/power-platform/developer/plan
- The Developer Plan is a viral/internal license. The tenant must allow viral or internal consent plans, which you check with `Get-AllowedConsentPlans` and change with `Add-AllowedConsentPlans`. https://learn.microsoft.com/power-platform/developer/plan
- "Internal" consent plans are the trials and developer plans users sign themselves up for in the Power Apps or Power Automate portals. An admin can block self-assignment with `Remove-AllowedConsentPlans -Types "Internal"` and still assign licenses on behalf of users. https://learn.microsoft.com/power-platform/admin/powerapps-powershell
- Governing setting: PPAC > Manage > Tenant settings > **Developer environment assignments**, set to Everyone or Only specific admins. When it's restricted, only Global admins, Dynamics 365 admins and Power Platform admins can create developer environments. Environments created before the restriction stay manageable by their creators. https://learn.microsoft.com/power-platform/admin/control-environment-creation
- PowerShell equivalent: `Set-TenantSettings` with `powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers = $True`. https://learn.microsoft.com/power-platform/admin/control-environment-creation
- The Tenant settings page describes "Developer environment assignments" as controlling who can create and manage developer environments. https://learn.microsoft.com/power-platform/admin/tenant-settings
- Admin route in PPAC: Manage > Environments > New, then Type = Developer with "Add a Dataverse data store" = Yes. https://learn.microsoft.com/power-platform/admin/create-environment
- Location: if you create the environment in the admin portal you can choose it. If it's created during sign-up, it's the tenant home location. https://learn.microsoft.com/power-platform/admin/environments-overview
- Environment routing (a premium governance feature) auto-creates personal developer environments, which are *managed* by default. Its FAQ mentions developer environments "created by them or on their behalf". https://learn.microsoft.com/power-platform/admin/default-environment-routing

### Creating a developer environment for another user programmatically
| Tool | How to pick Developer | Target-user parameter | Source |
| --- | --- | --- | --- |
| `New-AdminPowerAppEnvironment` (Microsoft.PowerApps.Administration.PowerShell) | `-EnvironmentSku Developer` (allowed values: Trial, Sandbox, Production, SubscriptionBasedTrial, Teams, Developer) | None. The cmdlet "creates a new environment by the logged in user" | https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/new-adminpowerappenvironment?view=pa-ps-latest |
| `pac admin create` | `--type Developer` | `--user`: object ID or UPN "to be assigned to the environment" | https://learn.microsoft.com/power-platform/developer/cli/reference/admin |
| `pac environment-management provision-new-environment` (Preview) | `--environment-sku Developer` | `--used-by-user-id`, `--used-by-tenant-id`, `--used-by-type` (for example User), `--used-by-display-name` | https://learn.microsoft.com/power-platform/developer/cli/reference/environment-management |
| Power Platform API, Provision New Environment (api-version 2024-10-01) | `"environmentSku": "Developer"` | `usedBy` (UserIdentity: userId, tenantId, type, displayName) | https://learn.microsoft.com/en-us/rest/api/power-platform/environmentmanagement/environment-provisioning/provision-new-environment |

- None of these pages explains what `--user` or `usedBy` actually does (owner, or just an added user), or what license the target user is checked for. Treat this as a gap (see Unverified). https://learn.microsoft.com/en-us/rest/api/power-platform/environmentmanagement/environment-provisioning/provision-new-environment
- Power Platform API request: `POST https://api.powerplatform.com/environmentmanagement/provisioning/environments?api-version=2024-10-01`, OAuth resource `https://api.powerplatform.com`, scope `.default`. Responses are 201/202, 400 (ValidationResponse with `errorDetail.fieldErrors`), 403 and 429. The operation status values are Queued, InProgress, Succeeded, ValidationFailed, Failed, NoOperation and ValidationPassed. https://learn.microsoft.com/en-us/rest/api/power-platform/environmentmanagement/environment-provisioning/provision-new-environment
- Poll the operation with `pac environment-management get-operation-by-id --operation-id <id>`. https://learn.microsoft.com/power-platform/developer/cli/reference/environment-management
- Some tenants require a macro region for new environments. The legacy PowerShell module then fails with `MacroRegionRequired`, and the doc says to use the Provision New Environment API with `macroRegion` instead. https://learn.microsoft.com/power-platform/admin/unified-experience/tutorial-deploy-new-environment-with-erp-template
- Service principals: SPN authentication works for environment management, tenant settings and Power Apps management. Power Platform treats the SPN like a user with the Power Platform Administrator role, licenses can't be assigned to SPNs, and an admin user has to register the SPN with Power Platform (it can't register itself). https://learn.microsoft.com/power-platform/admin/powerplatform-api-create-service-principal
- `pac admin create` defaults: region `unitedstates`, currency USD, language English. If the `--domain` is already taken, a numeric suffix is appended. `--async` is available, and `--max-async-wait-time` defaults to 60 minutes. https://learn.microsoft.com/power-platform/developer/cli/reference/admin
- `New-AdminPowerAppEnvironment -ProvisionDatabase` requires `-LanguageName` and `-CurrencyName`. `-WaitUntilFinished` defaults to true and `-TimeoutInMinutes` to 10080. https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/new-adminpowerappenvironment?view=pa-ps-latest
- You can't reuse the URL of a deleted or changed environment until at least 24 hours have passed. https://learn.microsoft.com/power-platform/admin/create-environment

```json
POST https://api.powerplatform.com/environmentmanagement/provisioning/environments?api-version=2024-10-01
{
  "displayName": "Team01 Service Desk",
  "environmentSku": "Developer",
  "databaseType": "CommonDataService",
  "location": "unitedstates",
  "linkedEnvironmentMetadata": {
    "baseLanguageCode": 1033,
    "currency": { "code": "USD" },
    "domainName": "t01svcdesk20261001"
  },
  "usedBy": { "userId": "<Entra object id of team user>", "tenantId": "<tenant id>", "type": "User" }
}
```
(The property names come from the REST reference. The values are illustrative, and the effect of `usedBy` isn't documented.)

### Limits, capacity, provisioning time
- Each user can have up to three developer environments; one is created at sign-up. https://learn.microsoft.com/power-platform/developer/plan
- An older (preview-labelled) maker page also says app makers can create up to three developer environments by default. https://learn.microsoft.com/power-apps/maker/maker-create-environment
- Capacity per developer environment: Database size 2 GB and 750 flow runs per month. Add-ons can't raise these limits, and the entitlements don't count toward the company's overall quota. https://learn.microsoft.com/power-platform/developer/plan
- Developer environments show as 0 GB on the tenant capacity page, and the capacity report doesn't count their consumption. https://learn.microsoft.com/power-platform/admin/capacity-storage
- Every environment except trial and developer environments consumes 1 GB when it's provisioned. https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy
- Provisioning time: "It might take a couple of minutes" before the new environment is available. Progress is visible in PPAC. https://learn.microsoft.com/power-platform/developer/create-developer-environment
- Trial environments get only one web server, which lowers effective throughput. The docs don't say how many web servers a developer environment gets. https://learn.microsoft.com/power-apps/developer/data-platform/api-limits

### Inactivity cleanup
- Activity-based cleanup applies only to default, developer and Dataverse for Teams environments, and it can't be turned off. https://learn.microsoft.com/power-platform/admin/automatic-environment-cleanup
- Non-managed developer environments: warning emails at 23 and 27 days without activity, disabled at 30 days, deletion warnings at 7 and 11 days after being disabled, deleted 15 days after being disabled, then recoverable for 7 days. https://learn.microsoft.com/power-platform/admin/automatic-environment-cleanup
- Managed developer environments use a 60-day threshold (warnings at 53 and 57 days, disabled at 60) and the same timeline after that. https://learn.microsoft.com/power-platform/admin/automatic-environment-cleanup
- What counts as activity: most user, maker or admin create/read/update/delete operations, including launching an app or the environment URL, running a flow, and scheduled flow runs. Visiting the home page, solution explorer or a designer doesn't count, and CoE toolkit queries stopped counting on 2025-04-20. Notifications go to the environment's system admins and to its creator. https://learn.microsoft.com/power-platform/admin/automatic-environment-cleanup
- PPAC has **Trigger environment activity** for inactive environments and **Re-enable environment** for disabled ones. https://learn.microsoft.com/power-platform/admin/automatic-environment-cleanup

### Dynamics 365 apps
- Dynamics 365 apps can't be installed in a developer environment; installing them requires an environment created with "Enable Dynamics 365 apps" = Yes. https://learn.microsoft.com/power-platform/developer/plan
- Enable Dynamics 365 apps can only be chosen when the database is provisioned, and it's irreversible. https://learn.microsoft.com/power-platform/admin/create-environment

### What is and is not supported
- The Developer Plan includes: create and share apps, Dataverse, data modelling, and apps that use the .NET SDK or OData Web API. Dataflows aren't included. You can add coworkers as environment makers or admins and to database roles. https://learn.microsoft.com/power-platform/developer/plan
- No Power Automate RPA and no AI Builder use rights. https://learn.microsoft.com/power-platform/developer/plan
- Business process flows and RPA flows can't be created in an environment under the Developer plan. https://learn.microsoft.com/power-platform/admin/power-automate-licensing/deep-dive-on-specific-license
- Managed Environments: a developer environment can become managed, but the Developer Plan doesn't include managed-environment use rights. Users, makers included, then need a premium license to run assets. https://learn.microsoft.com/power-platform/developer/plan
- In managed developer environments created by routing, Developer Plan users can only create and preview resources; running them needs a license. https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy
- Apps running in a developer environment show a banner. https://learn.microsoft.com/power-platform/developer/plan
- Users aren't added to a developer environment automatically; you add them manually. https://learn.microsoft.com/power-platform/developer/plan
- Auditing: no restriction for developer environments was found. Dataverse auditing is described for any environment with a Dataverse database, but user access and activity logging is sent to Purview only for production environments. https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing
- Column security: no restriction for developer environments was found. Masking rules, however, require a Managed Environment. https://learn.microsoft.com/power-platform/admin/create-manage-masking-rules
- Application users: no restriction for developer environments was found. Application users are unlicensed. https://learn.microsoft.com/power-platform/admin/manage-application-users

### Licenses needed to use a model-driven app
- Model-driven apps use Dataverse and are premium by default, so everyone who runs one needs Power Apps premium use rights. https://learn.microsoft.com/power-platform/admin/powerapps-licensing-faq
- The Developer Plan gives the same Power Apps functionality as the paid plans (aligned with trials), but only in developer environments and only for development and test. It can't be used to launch premium apps outside developer environments. https://learn.microsoft.com/power-platform/developer/plan
- License SKU to assign: product "Microsoft PowerApps for Developer", string ID `POWERAPPS_DEV`, GUID `5b631642-bd26-49fe-bd20-1daaa972ef80` (service plans DYN365_CDS_DEV_VIRAL, FLOW_DEV_VIRAL, POWERAPPS_DEV_VIRAL). https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference
- An older (deprecated) CoE doc says the "Microsoft Power Apps for Developers" license type can be assigned to users or to Microsoft Entra groups. https://learn.microsoft.com/power-platform/guidance/coe/cli/alm/development-environments
- Every user needs a security role (and the app shared with that role) to run a model-driven app. https://learn.microsoft.com/power-apps/maker/model-driven-apps/model-app-faq

## 2. Programmatic schema with the Web API

### Common rules
- Tables, columns and global choices are solution components. Adding the `MSCRM.SolutionUniqueName: <uniquename>` header puts the new component in that solution. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-definitions-using-web-api
- Include `Accept: application/json`, `OData-MaxVersion: 4.0`, `OData-Version: 4.0` and `If-None-Match: null` on every request, plus `Content-Type: application/json` when there's a body. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors
- If you don't name a solution, changes go to the caller's preferred solution, or to a default solution if there isn't one. https://learn.microsoft.com/power-apps/developer/model-driven-apps/customize-entity-views
- The SchemaName must carry the publisher's customization prefix, and the prefix can't be changed later. When setting labels, set only `LocalizedLabels`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-definitions-using-web-api
- Updates use `PUT` with the full definition, never `PATCH`. Send `MSCRM.MergeLabels: true` so labels in other languages aren't wiped (without the header the behavior is the same as false). https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-definitions-using-web-api

### Publisher and solution (records)
```http
POST [org]/api/data/v9.2/publishers
{ "friendlyname": "MSP Lab Publisher", "uniquename": "msplab", "description": "Lab publisher",
  "customizationprefix": "msp", "customizationoptionvalueprefix": 72700 }

POST [org]/api/data/v9.2/solutions
{ "friendlyname": "Service Desk", "uniquename": "ServiceDesk", "version": "1.0.0.0",
  "publisherid@odata.bind": "publishers(<publisherid>)" }
```
Both return 204 with an `OData-EntityId` header. Dataverse applies the publisher's `customizationoptionvalueprefix` to choice option values automatically (for example 72700xxxx). https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-metadata-operations-sample

### Create a custom table, including the primary name column
- Required properties: SchemaName, DisplayName, DisplayCollectionName, OwnershipType (`UserOwned` or `OrganizationOwned`), IsActivity, HasActivities and HasNotes. `Attributes` must contain exactly one StringAttributeMetadata with `IsPrimaryName: true` and `FormatName: Text`. A successful create returns 204 with `OData-EntityId`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-definitions-using-web-api
```http
POST [org]/api/data/v9.2/EntityDefinitions
MSCRM.SolutionUniqueName: ServiceDesk
{
 "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
 "SchemaName": "msp_Ticket",
 "DisplayName": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [
   { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Ticket", "LanguageCode": 1033 } ] },
 "DisplayCollectionName": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [
   { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Tickets", "LanguageCode": 1033 } ] },
 "Description": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [
   { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Service desk tickets", "LanguageCode": 1033 } ] },
 "OwnershipType": "UserOwned", "IsActivity": false, "HasActivities": false, "HasNotes": false,
 "Attributes": [ {
   "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
   "AttributeType": "String", "AttributeTypeName": { "Value": "StringType" },
   "SchemaName": "msp_Title", "IsPrimaryName": true, "MaxLength": 200, "FormatName": { "Value": "Text" },
   "RequiredLevel": { "Value": "None", "CanBeChanged": true, "ManagedPropertyLogicalName": "canmodifyrequirementlevelsettings" },
   "DisplayName": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [
     { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Title", "LanguageCode": 1033 } ] }
 } ]
}
```
- When the table is created, Dataverse generates its privileges from the SchemaName. The doc example shows `prvCreatenew_BankAccount`, `prvReadnew_BankAccount`, `prvWritenew_BankAccount` and so on through Delete, Assign, Share, Append and AppendTo, each with an ID and its allowed depths (`CanBeBasic`, `CanBeLocal`, `CanBeDeep`, `CanBeGlobal`). For this lab that means names like `prvWritemsp_Ticket`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-definitions-using-web-api

### Add columns (works the same for custom and standard tables)
- `POST [org]/api/data/v9.2/EntityDefinitions(LogicalName='<table>')/Attributes` with one attribute definition returns 204 and `OData-EntityId`. For standard tables, use `LogicalName='account'` or `'contact'`, and the custom column's SchemaName still needs the publisher prefix. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-column-definitions-using-web-api

| Type | `@odata.type` | `AttributeType` / `AttributeTypeName.Value` | Type-specific properties shown in the docs |
| --- | --- | --- | --- |
| Text | `Microsoft.Dynamics.CRM.StringAttributeMetadata` | String / StringType | `MaxLength`, `FormatName: {"Value":"Text"}` |
| Multiline | `Microsoft.Dynamics.CRM.MemoAttributeMetadata` | Memo / MemoType | `MaxLength`, `Format: "TextArea"` |
| Whole number | `Microsoft.Dynamics.CRM.IntegerAttributeMetadata` | Integer / IntegerType | `MinValue`, `MaxValue`, `Format: "None"` |
| Decimal | `Microsoft.Dynamics.CRM.DecimalAttributeMetadata` | Decimal / DecimalType | `MinValue`, `MaxValue`, `Precision` |
| Date time | `Microsoft.Dynamics.CRM.DateTimeAttributeMetadata` | DateTime / DateTimeType | `Format: "DateOnly"` (DateTimeFormat enum) |
| Yes/No | `Microsoft.Dynamics.CRM.BooleanAttributeMetadata` | Boolean / BooleanType | `DefaultValue`, `OptionSet` with TrueOption and FalseOption |
| Choice (local) | `Microsoft.Dynamics.CRM.PicklistAttributeMetadata` | Picklist / PicklistType | `OptionSet` with `IsGlobal: false` and `Options` |
| Customer lookup | via `CreateCustomerRelationships` action | Lookup | two OneToManyRelationships (account and contact) |
Source for the table: https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-column-definitions-using-web-api

Yes/No column, used here for the ticket note internal flag:
```json
{ "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
  "AttributeType": "Boolean", "AttributeTypeName": { "Value": "BooleanType" }, "DefaultValue": false,
  "OptionSet": { "OptionSetType": "Boolean",
    "TrueOption":  { "Value": 1, "Label": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Internal", "LanguageCode": 1033 } ] } },
    "FalseOption": { "Value": 0, "Label": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Public", "LanguageCode": 1033 } ] } } },
  "SchemaName": "msp_IsInternal",
  "RequiredLevel": { "Value": "None", "CanBeChanged": true, "ManagedPropertyLogicalName": "canmodifyrequirementlevelsettings" },
  "DisplayName": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Internal", "LanguageCode": 1033 } ] } }
```
Local choice column (only the Options shape is shown; the remaining properties are as above):
```json
{ "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
  "AttributeType": "Picklist", "AttributeTypeName": { "Value": "PicklistType" }, "SourceTypeMask": 0,
  "OptionSet": { "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata", "IsGlobal": false, "OptionSetType": "Picklist",
    "Options": [
      { "Value": 727000000, "Label": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Low", "LanguageCode": 1033 } ] } },
      { "Value": 727000001, "Label": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "High", "LanguageCode": 1033 } ] } } ] },
  "SchemaName": "msp_Priority" }
```
Integer and decimal columns also need `"MinValue"` and `"MaxValue"`; decimal adds `"Precision": 1`; datetime adds `"Format": "DateOnly"`; memo adds `"Format": "TextArea", "MaxLength": 500`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-column-definitions-using-web-api

### Lookup columns: one-to-many relationship
- `POST [org]/api/data/v9.2/RelationshipDefinitions` with `@odata.type` `Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata`. The lookup column is created in the same request (deep insert) through the `Lookup` property. Setting `ReferencingEntityNavigationPropertyName` and `ReferencedEntityNavigationPropertyName` gives the navigation properties custom names. Eligibility actions you can call first: CanBeReferenced, CanBeReferencing and GetValidReferencedEntities. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-relationships-using-web-api
```http
POST [org]/api/data/v9.2/RelationshipDefinitions
MSCRM.SolutionUniqueName: ServiceDesk
{
 "@odata.type": "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
 "SchemaName": "msp_ticket_msp_ticketnote",
 "ReferencedEntity": "msp_ticket", "ReferencedAttribute": "msp_ticketid", "ReferencingEntity": "msp_ticketnote",
 "ReferencingEntityNavigationPropertyName": "msp_TicketId",
 "AssociatedMenuConfiguration": { "Behavior": "UseCollectionName", "Group": "Details", "Order": 10000,
   "Label": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Notes", "LanguageCode": 1033 } ] } },
 "CascadeConfiguration": { "Assign": "Cascade", "Delete": "Cascade", "Merge": "Cascade", "Reparent": "Cascade", "Share": "Cascade", "Unshare": "Cascade" },
 "Lookup": { "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata", "AttributeType": "Lookup",
   "AttributeTypeName": { "Value": "LookupType" }, "SchemaName": "msp_TicketId",
   "RequiredLevel": { "Value": "ApplicationRequired", "CanBeChanged": true, "ManagedPropertyLogicalName": "canmodifyrequirementlevelsettings" },
   "DisplayName": { "@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [ { "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": "Ticket", "LanguageCode": 1033 } ] } }
}
```
- Many-to-many relationships use the same entity set with `Microsoft.Dynamics.CRM.ManyToManyRelationshipMetadata`, plus Entity1LogicalName, Entity2LogicalName and IntersectEntityName. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-entity-relationships-using-web-api
- Reference pages show `NoCascade` and `Restrict` as cascade values, for example on systemuser relationships. https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/systemuser

### Put the standard tables in your solution
- `pac solution add-solution-component --solutionUniqueName ServiceDesk --component contact --componentType 1`; component type 1 is a table. https://learn.microsoft.com/power-platform/developer/cli/reference/solution
- The Web API equivalent is the AddSolutionComponent action, which requires the System Administrator or System Customizer role. Creating a component with `SolutionUniqueName` adds it to both the default solution and the named solution. https://learn.microsoft.com/dotnet/api/microsoft.crm.sdk.messages.addsolutioncomponentrequest?view=dataverse-sdk-latest

### Publishing
- Customizations are published automatically when items are created or deleted. Updates to schema or UI components have to be published, and only published customizations are exported. https://learn.microsoft.com/power-apps/developer/model-driven-apps/publish-customizations
```http
POST [org]/api/data/v9.2/PublishXml
{ "ParameterXml": "<importexportxml><entities><entity>msp_ticket</entity><entity>contact</entity></entities></importexportxml>" }
```
Returns 204. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/configure
- `POST [org]/api/data/v9.2/PublishAllXml` publishes all changes to solution components; it has no parameters. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/reference/publishallxml
- `pac solution publish [--async]` publishes all customizations. https://learn.microsoft.com/power-platform/developer/cli/reference/solution
- The Dataverse SDK for Python (`pip install PowerPlatform-Dataverse-Client`) runs on the Web API and supports creating, updating and deleting tables and columns with optional solution association, as well as relationships and batch operations. https://learn.microsoft.com/power-apps/developer/data-platform/sdk-python/overview

## 3. Model-driven app created programmatically

### appmodule, AddAppComponents, ValidateApp, PublishXml
- Steps: create an AppModule record, add components (AddAppComponents and RemoveAppComponents), validate (ValidateApp), publish, then associate security roles. You need the System Administrator or System Customizer role. https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code
- Minimum properties: `name`, `uniquename` (English letters and digits only; the publisher prefix is added automatically) and `webresourceid` (the system default icon ID is `953b9fac-1e5e-e611-80d6-00155ded156f`). https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code
```http
POST [org]/api/data/v9.2/appmodules
{ "name": "Service Desk", "uniquename": "ServiceDesk", "webresourceid": "953b9fac-1e5e-e611-80d6-00155ded156f" }

POST [org]/api/data/v9.2/AddAppComponents
{ "AppId": "<appmoduleid>", "Components": [
   { "savedqueryid": "<viewid>", "@odata.type": "Microsoft.Dynamics.CRM.savedquery" },
   { "formid": "<formid>", "@odata.type": "Microsoft.Dynamics.CRM.systemform" } ] }

GET  [org]/api/data/v9.2/ValidateApp(AppModuleId=<appmoduleid>)

POST [org]/api/data/v9.2/PublishXml
{ "ParameterXml": "<importexportxml><appmodules><appmodule><appmoduleid></appmodule></appmodules></importexportxml>" }

POST [org]/api/data/v9.2/appmodules(<appmoduleid>)/appmoduleroles_association/$ref
{ "@odata.id": "[org]/api/data/v9.2/roles(<roleid>)" }
```
- ValidateApp returns `AppValidationResponse.ValidationSuccess` and a `ValidationIssueList`. A missing sitemap is reported as Error "App does not contain Site Map" (CRMErrorCode -2147155684). A table with no form or view referenced is a warning, and users then see all forms and views. https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code
- To read unpublished apps use `appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()`. To list an app's components use `RetrieveAppComponents(AppModuleId=...)`. https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code
- In the doc's role-association example the slash before `appmoduleroles_association` is missing. The DELETE example uses `/appmoduleroles_association/$ref?$id=...`. https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code

### Sitemap
- SiteMap table (`POST /sitemaps`). Writable columns: SiteMapName, SiteMapNameUnique, SiteMapXml, IsAppAware, ShowHome, ShowPinned, ShowRecents and EnableCollapsibleGroups. ComponentState tracks Published, Unpublished and the deleted states. https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/sitemap
- `IsAppAware` tells the default sitemap apart from an app-specific one. The XML structure (Area, Group, SubArea with an `Entity` attribute) is documented only in the on-premises customization docs and in Schemas.zip (SiteMap.xsd). https://learn.microsoft.com/dynamics365/customerengagement/on-premises/developer/customize-dev/customize-sitemaps?view=op-9-1
- SubArea elements that point at a table only appear if the user has read access to that table. https://learn.microsoft.com/dynamics365/customerengagement/on-premises/developer/customize-dev/change-application-navigation-using-sitemap?view=op-9-1

### Main form (systemform) and views (savedquery)
- Forms are stored in SystemForm. Important columns: FormXml, Type (2 = main, 5 = mobile, 6 = quick, 7 = quickCreate), ObjectTypeCode (the table logical name) and FormActivationState. You can create forms directly or with the `CopySystemForm` action. The documented way to edit a form definition is to export the solution, edit FormXml in customizations.xml with schema validation, and reimport. https://learn.microsoft.com/power-apps/developer/model-driven-apps/customize-entity-forms
- To create a public view, set `name`, `returnedtypecode` (table logical name), `fetchxml`, `layoutxml` and `querytype` (always 0 for public). Other QueryType codes: 1 Advanced Find, 2 Associated, 4 Quick Find, 64 Lookup; these are update-only. `IsDefault` sets the default public view. Associate the view with your solution through SolutionUniqueName. https://learn.microsoft.com/power-apps/developer/model-driven-apps/customize-entity-views
- A new custom table automatically gets Active and Inactive public views plus Quick Find, Advanced Find, Associated and Lookup views. https://learn.microsoft.com/dynamics365/customerengagement/on-premises/customize/create-edit-views?view=op-9-1
- Default views can't be deactivated (CannotDeactivateDefaultView, 0x8004027a). https://learn.microsoft.com/power-apps/developer/data-platform/reference/web-service-error-codes

### Recommended route: import a solution zip
- Forms and sitemaps are formally documented through solution XML, and creating appmodules through the API is only thinly documented. Importing a solution exported from a build environment is the more reliable path (this is my judgement based on the pages above).
- ImportSolution (sync) body, from the docs sample:
```http
POST [org]/api/data/v9.2/ImportSolution
{ "OverwriteUnmanagedCustomizations": false, "PublishWorkflows": false,
  "CustomizationFile": "<base64 of solution.zip>", "ImportJobId": "<new guid>" }
```
Returns 204. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-metadata-operations-sample
- ExportSolution body: `{ "SolutionName": "ServiceDesk", "Managed": true, ... }` with the Export*Settings flags set to false. The response is `ExportSolutionFile` (base64). https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-metadata-operations-sample
- `ImportSolutionAsync` takes the same inputs plus `ComponentParameters` and `SolutionParameters`. It returns `ImportJobKey` and `AsyncOperationId`; track `AsyncOperationId` to follow the job. `StageSolution` validates a staged holding solution and returns a `StageSolutionUploadId`. https://learn.microsoft.com/power-platform/alm/solution-async
- asyncoperation `statuscode` values: 30 succeeded, 31 failed, 32 cancelled. Only one asynchronous message runs at a time per organization. https://learn.microsoft.com/power-apps/developer/data-platform/org-service/use-executeasync
- `pac solution import --path <zip>` options: `--async`, `--publish-changes`, `--activate-plugins`, `--force-overwrite`, `--import-as-holding`, `--stage-and-upgrade`, `--skip-lower-version`, `--settings-file`, and `--max-async-wait-time` (default 60). https://learn.microsoft.com/power-platform/developer/cli/reference/solution
- Authentication for pac: `pac auth create --applicationId ... --clientSecret ... --tenant ...` for a service principal, or `--managedIdentity` (DefaultAzureCredential). https://learn.microsoft.com/power-platform/developer/cli/reference/auth
- Overwrite customizations doesn't affect components with merge behavior (forms, sitemap, ribbon, app modules). https://learn.microsoft.com/power-apps/maker/data-platform/update-solutions

## 4. Application users

### Facts
- An application user is an unlicensed user in the environment. Each Microsoft Entra registered application can have only one application user per environment. https://learn.microsoft.com/power-platform/admin/manage-application-users
- Once created, the primary email address and username can't be changed. Application users are activated automatically. https://learn.microsoft.com/power-apps/developer/data-platform/use-single-tenant-server-server-authentication
- Application users are non-interactive accounts but don't count toward the limit of seven non-interactive accounts, and there's no limit on how many you create. The system sets the First Name to "#". https://learn.microsoft.com/power-platform/admin/create-users
- Application users can run in environments secured with a security group without being members of it. Only inactive application users can be deleted. https://learn.microsoft.com/power-platform/admin/manage-application-users
- Application users can't be included in a solution, so you need your own way to create them and assign roles (code or Package Deployer). https://learn.microsoft.com/power-apps/developer/data-platform/use-multi-tenant-server-server-authentication

### Managed identity (user-assigned) as the identity behind an application user
- In the PPAC "Create a new app user" pane you can enter an Azure Managed Identity Application ID. Use the Application ID, not the managed identity's name. https://learn.microsoft.com/power-platform/admin/manage-application-users
- Microsoft's nonprofit data sync accelerator creates an application user from a managed identity's client ID. https://learn.microsoft.com/industry/nonprofit/fundraising-engagement-data-sync-accelerator
- The Azure Data Factory Dataverse connector supports user-assigned managed identity authentication for Dataverse online. https://learn.microsoft.com/azure/data-factory/connector-dynamics-crm-office-365
- The Dataverse OAuth guidance recommends more secure flows, managed identities among them, over client secrets. https://learn.microsoft.com/power-apps/developer/data-platform/authenticate-oauth
- Don't confuse this with "Power Platform managed identity", which is the reverse direction: Dataverse plug-ins calling Azure resources. https://learn.microsoft.com/power-platform/admin/managed-identity-overview

### Creating the application user programmatically
- PAC CLI (documented): `pac admin assign-user --environment <id> --user <application (client) id> --role "System Administrator" --application-user [--business-unit <id>]`. Without `--business-unit`, the application user goes into the authenticated user's business unit. https://learn.microsoft.com/power-platform/developer/cli/reference/admin
- `pac admin create-service-principal --environment <id> [--role]` creates a new Entra app with a secret plus its application user; the default role is System Administrator. It doesn't apply to managed identities. https://learn.microsoft.com/power-platform/developer/cli/reference/admin
- BAP API (preview): `POST https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/{envId}/addAppUser?api-version=2020-10-01` with body `{ "servicePrincipalAppId": "<app id>" }`. It always adds the user as System Administrator. https://learn.microsoft.com/power-platform/admin/create-dataverseapplicationuser
- The systemuser columns involved are `applicationid` (Application ID), `azureactivedirectoryobjectid` (filled in from applicationid) and `businessunitid` (a SystemRequired lookup). https://learn.microsoft.com/power-apps/developer/data-platform/use-multi-tenant-server-server-authentication
- A raw Web API `POST systemusers` with `applicationid` and `businessunitid@odata.bind` isn't shown on any page that was read; see Unverified.

### Tokens
- A confidential client uses the scope `<environment-url>/.default`, for example `https://<org>.crm.dynamics.com/.default`. A public client uses `<environment-url>/user_impersonation`. https://learn.microsoft.com/power-apps/developer/data-platform/authenticate-oauth
- Server-to-server apps don't need the delegated "Access Dynamics 365 as organization users" permission. https://learn.microsoft.com/power-apps/developer/data-platform/authenticate-oauth
- Python: `ManagedIdentityCredential(client_id="<UAMI client id>")`; `get_token` accepts one scope per request. https://learn.microsoft.com/python/api/azure-identity/azure.identity.managedidentitycredential?view=azure-python
- The Dataverse Python SDK constructor is `DataverseClient(base_url, credential: TokenCredential)` and accepts any Azure Identity credential. https://learn.microsoft.com/python/api/powerplatform-dataverse-client/powerplatform.dataverse.client.dataverseclient?view=dataverse-sdk-python-latest

### Assign or remove a security role
```http
POST [org]/api/data/v9.2/systemusers(<systemuserid>)/systemuserroles_association/$ref
{ "@odata.id": "[org]/api/data/v9.2/roles(<roleid>)" }
```
The doc example keys the user by `azureactivedirectoryobjectid`; keying by systemuserid follows the same navigation property. https://learn.microsoft.com/power-apps/developer/data-platform/aad-group-team
- systemuserroles_association is the many-to-many navigation property between role and systemuser. https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/role
- Remove a role with `DELETE .../systemusers(<id>)/systemuserroles_association/$ref?$id=[org]/api/data/v9.2/roles(<roleid>)`, the same pattern the Web API sample uses for disassociation. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-basic-operations-sample
- Roles belong to business units; without matrix ownership you can only assign roles from the user's own business unit. An assigner can't grant a role with more privileges than the assigner holds. https://learn.microsoft.com/power-platform/admin/assign-security-roles

## 5. Security roles

### Create a role and add privileges
```http
POST [org]/api/data/v9.2/roles
{ "businessunitid@odata.bind": "businessunits(<root bu id>)", "name": "MCP Least Privilege" }

GET  [org]/api/data/v9.2/privileges?$select=name&$filter=name eq 'prvReadmsp_Ticket' or name eq 'prvWritemsp_Ticket'

POST [org]/api/data/v9.2/roles(<roleid>)/Microsoft.Dynamics.CRM.AddPrivilegesRole
{ "Privileges": [
   { "Depth": "Global", "PrivilegeId": "<id of prvReadmsp_Ticket>", "BusinessUnitId": "<bu id>", "PrivilegeName": "prvReadmsp_Ticket" },
   { "Depth": "Basic",  "PrivilegeId": "<id of prvCreatemsp_TicketNote>", "BusinessUnitId": "<bu id>", "PrivilegeName": "prvCreatemsp_TicketNote" } ] }
```
- Create returns 204 and AddPrivilegesRole returns 204. A new role starts with 9 default privileges (Read SharePoint data, Read SdkMessage, and so on). Verify the result with `roles(<id>)?$expand=roleprivileges_association($select=name)`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-functions-actions-sample
- PrivilegeDepth values: Basic = 0 (owned by or shared with the user), Local = 1 (the user's business unit), Deep = 2 (business unit and its children), Global = 3 (whole organization); RecordFilter = 4 has no description. The Web API takes these names as strings. https://learn.microsoft.com/dotnet/api/microsoft.crm.sdk.messages.privilegedepth?view=dataverse-sdk-latest
- In the UI the access levels are named User, Business Unit, Parent: Child Business Unit and Organization. https://learn.microsoft.com/power-platform/admin/security-roles-privileges
- Related messages: ReplacePrivilegesRole, RemovePrivilegeRole and RetrieveRolePrivilegesRole, all bound to role. https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/role
- Global privileges like prvBypassCustomPlugins are added with AddPrivilegesRole at Depth Global (3). https://learn.microsoft.com/power-apps/developer/data-platform/bypass-custom-business-logic

### Copying a role
- Copying is documented only in the UI (PPAC > Security roles > Copy). Only privileges are copied, not members or teams, and a role can't be copied into a different business unit. https://learn.microsoft.com/power-platform/admin/database-security-configure
- The System Administrator role can't be edited; copy it to change it. The docs warn against handing copied System Administrator roles to admin users. https://learn.microsoft.com/power-platform/admin/create-edit-security-role
- Copied roles don't pick up new privileges added by product updates. https://learn.microsoft.com/power-platform/admin/prevent-elevation-security-role-privilege
- To copy in code, combine documented messages: RetrieveRolePrivilegesRole or `roles(<src>)/roleprivileges_association`, then create the role, then AddPrivilegesRole. No single copy API was found.

### Privilege check, access check and the exact errors
- Dataverse checks the privilege first; the access level isn't considered in that step. The access check (ownership, role depth, sharing, hierarchy) comes second. https://learn.microsoft.com/power-platform/admin/how-record-access-determined
- PrivilegeDenied: `0x80040220` (-2147220960). Message template: `{5} {2}(Id = {3}) is missing {0} privilege on {1} entity(OTC={4}). Consider adding missing privilege to one of the principal (user/team) roles for the request to succeed.` https://learn.microsoft.com/power-apps/developer/data-platform/reference/web-service-error-codes
- The troubleshooting page summarizes the same error as "Principal user is missing privilege on OTC for entity" (-2147220960). An access-check failure is a different error, -2147187962: "Principal with ID <guid> does not have <X>Access right(s) for record with ID <guid> of entity". A failed privilege check can also appear as -2147220839 ("CrmCheckPrivilege failed"). https://learn.microsoft.com/troubleshoot/power-platform/dataverse/user-permissions/client-errors
- HTTP status: **403 Forbidden** for AccessDenied, PrincipalPrivilegeDenied, PrivilegeDenied, CrmSecurityError, InvalidAccessRights, AttributePermissionReadIsMissing, AttributePermissionUpdateIsMissingDuringUpdate and AttributePrivilegeCreateIsMissing. 401 is used for authentication ticket errors. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors
- Error body: `{"error":{"code":"<hex such as 0x80040265, often empty>","message":"..."}}`. With `Prefer: odata.include-annotations="*"` the body also carries `@Microsoft.PowerApps.CDS.HelpLink`, `...TraceText`, `...InnerError.Message`, and the ErrorDetails OperationStatus and SubErrorCode. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors
- Use the `Consistency: Strong` header when you must read user or team permissions (or metadata) within about 30 seconds of a change. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors
- Role changes are auditable: action 55 Assign Role To User, 56 Remove Role From User, 57 Add Privileges to Role, 58 Remove, 59 Replace. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data

## 6. Column security

### Which columns can be secured
- Column-level security settings apply to the whole organization and to every data access request. You need the System Administrator role to configure them. https://learn.microsoft.com/power-platform/admin/field-level-security
- Can't be secured: columns in virtual tables, lookup columns, formula columns, primary name columns, and system columns (createdon, modifiedon, statecode, statuscode). File and Image columns can be secured but not masked. https://learn.microsoft.com/power-platform/admin/field-level-security
- Eligibility depends on CanBeSecuredForCreate, CanBeSecuredForRead and CanBeSecuredForUpdate. If all three are false the column can't be secured; some columns can be secured for only some operations. You can query this with RetrieveMetadataChanges. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
- The official column-level security example secures contact **Mobile Phone** (`mobilephone`), so that column is securable. The docs don't explicitly confirm emailaddress1 or telephone1; see Unverified. https://learn.microsoft.com/power-platform/admin/column-level-security-example
- Composite columns (contact fullname, address1_composite) need their source columns secured as well. Calculated and prompt columns that use a secured column can leak its value, so secure them too. https://learn.microsoft.com/power-platform/admin/field-level-security

### Enable IsSecured programmatically
- Retrieve the full column definition, set `IsSecured: true`, and `PUT` it back with `MSCRM.MergeLabels: true` and `MSCRM.SolutionUniqueName`. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
```http
GET [org]/api/data/v9.2/EntityDefinitions(LogicalName='contact')/Attributes(LogicalName='mobilephone')/Microsoft.Dynamics.CRM.StringAttributeMetadata
PUT [org]/api/data/v9.2/EntityDefinitions(LogicalName='contact')/Attributes(LogicalName='mobilephone')
MSCRM.MergeLabels: true
MSCRM.SolutionUniqueName: ServiceDesk
{ ...full definition as retrieved..., "IsSecured": true }
```
- Then publish. AttributeNotSecured (0x8004F508) says field-level security isn't enabled until customizations are published. https://learn.microsoft.com/power-apps/developer/data-platform/reference/web-service-error-codes

### Field security profile and permissions
- A profile is a FieldSecurityProfile (`fieldsecurityprofiles`; writable columns name and description). Each permission is a FieldPermission (`fieldpermissions`) with fieldsecurityprofileid (lookup), entityname, attributelogicalname, cancreate, canread, canupdate and canreadunmasked. https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/fieldpermission
- canread, canupdate and cancreate take 0 (Not Allowed) or 4 (Allowed). canreadunmasked takes 0 (Not Allowed), 1 (One Record) or 3 (All Records). https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
- Associate users and teams through `systemuserprofiles_association` and `teamprofiles_association`. Field permissions hang off `lk_fieldpermission_fieldsecurityprofileid`, whose referencing navigation property is `fieldsecurityprofileid`. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
```http
POST [org]/api/data/v9.2/fieldsecurityprofiles
{ "name": "Contact PII readers", "description": "Lab profile" }
POST [org]/api/data/v9.2/fieldpermissions
{ "fieldsecurityprofileid@odata.bind": "/fieldsecurityprofiles(<profileid>)", "entityname": "contact",
  "attributelogicalname": "emailaddress1", "canread": 4, "canupdate": 0, "cancreate": 0 }
POST [org]/api/data/v9.2/fieldsecurityprofiles(<profileid>)/systemuserprofiles_association/$ref
{ "@odata.id": "[org]/api/data/v9.2/systemusers(<app user systemuserid>)" }
```
(This JSON is assembled from the documented entity sets, columns and relationships; the doc page itself shows these operations in SDK and PowerShell form.) https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/fieldsecurityprofile
- The documented PowerShell sample adds an **application user** (with a custom role) to a field security profile and shows it can read only the permitted secured columns. The sample waits 30 seconds for caches to catch up. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/samples/column-level-security-powershell
- The built-in System Administrator field security profile has ID `572329c1-a042-4e22-be47-367c6374ea45`. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
- Per-record field sharing: `POST principalobjectattributeaccessset` with `objectid_<table>@odata.bind`, `attributeid` (the column MetadataId), `principalid_systemuser@odata.bind`, `readaccess` and `updateaccess`. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security

### Behavior for principals without permission, and System Administrator
- By default the API returns **no data** for a secured column the caller can't read, and the caller can't tell that apart from null. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
- Forms and views show a lock icon and asterisks to users outside the profiles. Until a profile is assigned, only system administrators can access the column. Clients need a browser refresh to see changes. https://learn.microsoft.com/power-platform/admin/field-level-security
- Column-level security **doesn't apply to System Administrator**; data is never hidden from system administrators, so test with a non-admin account. https://learn.microsoft.com/power-platform/admin/field-level-security
- Errors: AttributePermissionUpdateIsMissingDuringUpdate `0x8004F507` (update), AttributePrivilegeCreateIsMissing `0x8004F502` (create), AttributePermissionReadIsMissing `0x8004F504` (read). https://learn.microsoft.com/power-apps/developer/data-platform/reference/web-service-error-codes
- In Purview activity logs, secured column values appear as `*`. https://learn.microsoft.com/power-platform/admin/field-level-security
- Alternate keys can't include columns that have field-level security. https://learn.microsoft.com/power-apps/developer/data-platform/define-alternate-keys-entity

### Masking rules (newer feature)
- Masking returns a masked string instead of nothing. The developer page labels it preview. Masking rules use C# regular expressions and are attached to a column through an AttributeMaskingRule record; unmasked reads use the `UnMaskedData` optional parameter together with canreadunmasked. https://learn.microsoft.com/power-apps/developer/data-platform/column-level-security
- **Prerequisite: the environment must be a Managed Environment** before you can add a masking rule to a secured column. Supported types are text and number. Audit logs show masked before and after values. System and application users get masked values by default even with Read unmasked. https://learn.microsoft.com/power-platform/admin/create-manage-masking-rules
- Unmasked-read error: AttributePermissionReadUnMaskedIsMissing `0x8004F50F`. https://learn.microsoft.com/power-apps/developer/data-platform/reference/web-service-error-codes

## 7. Auditing

### Enable it at three levels
- Organization (one row) columns: `isauditenabled`; `auditretentionperiodv2` (developer doc: default 30, range 1 to 365,000, -1 keeps forever); `isuseraccessauditenabled`; `useraccessauditinginterval` (default 4 hours); and `auditsettings` (JSON). The organization ID is in `WhoAmI.OrganizationId`. Changing these requires System Administrator or System Customizer. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/configure
```http
GET   [org]/api/data/v9.2/organizations?$select=isauditenabled,auditretentionperiodv2,isuseraccessauditenabled,auditsettings
PATCH [org]/api/data/v9.2/organizations(<organizationid>)
If-Match: *
{ "isauditenabled": true }
```
(The doc shows PATCH for `auditsettings`; per the doc, the other columns are changed the same way.) https://learn.microsoft.com/power-apps/developer/data-platform/auditing/configure
- Table and column: the managed property `IsAuditEnabled` (`{ "Value": true, "CanBeChanged": true, "ManagedPropertyLogicalName": "canmodifyauditsettings" }`) on EntityMetadata and AttributeMetadata. Update it with PUT. **Changes don't take effect until you publish.** https://learn.microsoft.com/power-apps/developer/data-platform/auditing/configure
- You have to turn auditing on for the environment, the table and the column. Audit logs consume log storage, can appear with a delay, and record updates only when the value actually changes. https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing
- Not audited: retrieve and export operations, table and column definition changes, and authentication. Some non-customizable tables can't be audited at all, Annotation (notes) among them. https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing

### Reading audit records
- Entity set `audits` (read-only). The caller needs `prvReadAuditSummary`. Audit data isn't available through the TDS (SQL) endpoint. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data
- Columns: `action` (event choice, for example 1 Create, 2 Update, 3 Delete, 13 Assign, 55 Assign Role To User); `operation` (1 Create, 2 Update, 3 Delete, 4 Access); `_objectid_value` plus `objecttypecode` (the table logical name); `_userid_value` (Changed By); `_callinguserid_value` (the calling user when impersonation is used, otherwise null); `createdon` (millisecond precision since July 2025); `transactionid`; and `attributemask`, which the docs say not to use. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data
- Audit records have only two relationships, both to systemuser (`lk_audit_userid`, `lk_audit_callinguserid`). You can include only one link entity per query and can't join to other tables. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data
```http
GET [org]/api/data/v9.2/audits?$select=_objectid_value,objecttypecode,createdon,_userid_value,action,operation&$filter=objecttypecode eq 'msp_ticket' and _objectid_value eq <ticketid>&$orderby=createdon desc
Prefer: odata.include-annotations="*"
GET [org]/api/data/v9.2/audits(<auditid>)/Microsoft.Dynamics.CRM.RetrieveAuditDetails
GET [org]/api/data/v9.2/RetrieveRecordChangeHistory(Target=@target,PagingInfo=@paginginfo)?@target={'@odata.id':'msp_tickets(<id>)'}&@paginginfo={"PageNumber":1,"Count":20,"ReturnTotalRecordCount":true}
```
- RetrieveAuditDetails returns AttributeAuditDetail with OldValue and NewValue. RetrieveRecordChangeHistory and RetrieveAttributeChangeHistory need `prvReadRecordAuditHistory` plus `prvReadAuditSummary`. **In the Web API, the AuditDetail types don't return the AuditRecord, so who and when aren't included.** Take those from the `audits` query. Values larger than about 5 KB are truncated. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data
- In the UI, Audit History needs the View Audit History privilege and Audit Summary needs View Audit Summary. https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing

### Attribution of application-user changes
- `userid` is the user who changed the data, and `callinguserid` is set only for impersonation. A change the MCP application user makes on its own therefore shows `userid` = the application user's systemuserid. https://learn.microsoft.com/power-apps/developer/data-platform/auditing/retrieve-audit-data
- If the MCP server impersonates a user (with the `CallerObjectId` header, which requires `prvActOnBehalfOfAnotherUser`), the record shows the impersonated user as createdby and the real caller in `createdonbehalfby` and `modifiedonbehalfby`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/impersonate-another-user-web-api
- Developer environments: no documented restriction on Dataverse auditing. Purview user access and activity logs are production-only. https://learn.microsoft.com/power-platform/admin/manage-dataverse-auditing

## 8. Web API data operations for the MCP server and seed loader

### $batch
- Up to **1,000** requests per batch, and batches can't be nested. A batch is equivalent to ExecuteMultiple; a change set is atomic and equivalent to ExecuteTransaction. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/execute-batch-operations-using-web-api
- GET isn't allowed inside a change set. `Content-ID` values can be referenced later as `$1`, `$2`, and so on, but referencing one before it's defined returns 400. Payloads must use CRLF line endings. Headers must be set on each part. URLs inside a batch can be up to 64 KB (outside, 32 KB). https://learn.microsoft.com/power-apps/developer/data-platform/webapi/execute-batch-operations-using-web-api
- By default the batch stops at the first error. With `Prefer: odata.continue-on-error` it returns 200 and reports per-request errors in the body. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/execute-batch-operations-using-web-api
- Guidance: avoid large batches, start around 10 per batch and use parallel requests. Batches don't get around entitlement limits. https://learn.microsoft.com/power-apps/developer/data-platform/api-limits

### Upsert with alternate keys
- Upsert is a `PATCH` to `entityset(key1=v1,key2=v2)`. With no If-Match it upserts; `If-Match: *` makes it update-only (404 if the row is missing); `If-None-Match: *` makes it create-only (412 if the row exists). Both outcomes return 204, while `Prefer: return=representation` gives 201 for a create and 200 for an update. Don't put the key values in the body. https://learn.microsoft.com/power-apps/developer/data-platform/use-upsert-insert-update-record
- Key rules: allowed column types are Decimal, Integer, String, DateTime, Lookup and Picklist; columns with field-level security aren't allowed; up to 10 keys per table; 900 bytes and 16 columns per key. Values containing `/ < > * % & : \ ? +` break GET, PATCH and upsert. https://learn.microsoft.com/power-apps/developer/data-platform/define-alternate-keys-entity
- Index creation is asynchronous: `EntityKeyMetadata.EntityKeyIndexStatus` goes Pending, In Progress, then Active or Failed, and a failed key can be retried with ReactivateEntityKey. https://learn.microsoft.com/power-apps/developer/data-platform/define-alternate-keys-entity
- Bulk messages: CreateMultiple, UpdateMultiple and UpsertMultiple are actions with a `Targets` array in which each item needs `@odata.type`. UpsertMultiple returns 204 and errors on duplicate keys within one payload. UpdateMultiple doesn't support alternate keys in the Web API. https://learn.microsoft.com/power-apps/developer/data-platform/bulk-operations
- Every custom table supports the bulk messages, but not every core table does. The doc gives Account and Contact as examples; check with an sdkmessagefilters query. On standard tables, one error fails the whole bulk operation. https://learn.microsoft.com/power-apps/developer/data-platform/optimize-performance-create-update

### Lookups and choices
- To bind a lookup: `"primarycontactid@odata.bind": "/contacts(<guid>)"`. Collection-valued properties take an array of URIs. Remove a binding by setting the navigation property to null. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-entity-web-api
- Navigation property names are case-sensitive and are not always the lookup's logical name. For contact.parentcustomerid you must use `parentcustomerid_account`; a wrong name fails with "An undeclared property ... was found in the payload". https://learn.microsoft.com/troubleshoot/power-platform/dataverse/dataverse-web-api-and-sdk/web-api-client-errors
- The single-valued navigation property name comes from `ReferencingEntityNavigationPropertyName`. Lookup values are read back as `_<name>_value`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/web-api-navigation-properties
- Choice values are integers; the publisher option prefix is applied. Labels come back with `Prefer: odata.include-annotations="OData.Community.Display.V1.FormattedValue"`. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors

### Service protection API limits
- Limits are evaluated per user, and application users get the same limits as everyone else. They're enforced per web server: 6,000 requests, 1,200 seconds of combined execution time, and 52 or more concurrent requests, all within a sliding 300-second window. https://learn.microsoft.com/power-apps/developer/data-platform/api-limits
- Exceeding them returns **429** with a `Retry-After` header in seconds. Hex codes: `0x80072322` (request count), `0x80072321` (execution time), `0x80072326` (concurrency). The headers `x-ms-ratelimit-burst-remaining-xrm-requests` and `x-ms-ratelimit-time-remaining-xrm-requests` are for debugging only. https://learn.microsoft.com/power-apps/developer/data-platform/api-limits
- Daily entitlements: application users draw from a **tenant-level pooled** allowance shared by all non-licensed identities. With Power Apps licenses only it's 25,000 requests per 24 hours (Dynamics 365 Enterprise/Professional tenants get 500,000 plus 5,000 per user license). Individual application users don't get separate allowances. https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations

### Error shape and status codes
- `{"error":{"code":"...","message":"..."}}`; see the status table in Section 5. Other limits: 413 Payload Too Large, 412 for concurrency mismatch or duplicate record, a 32 KB maximum URL, and a 260-character maximum OData segment. https://learn.microsoft.com/power-apps/developer/data-platform/webapi/compose-http-requests-handle-errors

## 9. Licensing

- The Power Apps Developer Plan is free and meant for building and testing, not production use. It stays available while you actively use it and don't abuse it (no production use, stay within capacity). It requires a work or school account; personal accounts can't sign up. https://learn.microsoft.com/power-platform/developer/plan
- Running solutions in production for production use requires a paid plan. https://learn.microsoft.com/power-platform/developer/plan
- The Developer Plan lets you share apps with team members for development and testing. https://learn.microsoft.com/power-platform/developer/plan
- The licensing overview describes it as providing "an individual developer environment". https://learn.microsoft.com/power-platform/admin/pricing-billing-skus
- Anyone who runs a model-driven app needs premium use rights; in developer environments the Developer Plan provides them. https://learn.microsoft.com/power-platform/admin/powerapps-licensing-faq
- With Managed Environments turned on, every active user needs a qualifying license, and the Developer Plan doesn't include managed-environment use rights. https://learn.microsoft.com/power-platform/developer/plan
- Shared accounts: no Learn page covers lab or training scenarios. Related statements: you need one user license per person with an active user record who signs in, and each user license needs a unique Microsoft account (from the Dynamics 365 license assignment page). https://learn.microsoft.com/power-platform/admin/assign-licenses
- Using multiplexing to reduce the number of licenses is a license violation, and Microsoft recommends service principals over shared service accounts. https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs
- The detailed terms live in the Power Platform Licensing Guide (a PDF linked from Learn, not retrievable with these tools) and in your agreement. https://learn.microsoft.com/power-platform/admin/pricing-billing-skus

## Recommendations for the lab design

1. **Spike the provisioning path first; it decides everything else.** Run Power Platform API Provision New Environment with `environmentSku: Developer` and `usedBy` set to a team account, called by (a) a Power Platform admin user and (b) a registered service principal. Check who ends up owning the environment, whether the team account needs `POWERAPPS_DEV` beforehand, whether the three-per-user cap applies to the caller or to the target, and what error comes back. Fallbacks: the admin creates the developer environment and adds the team account as System Administrator (`pac admin assign-user`); otherwise use Sandbox environments, which consume 1 GB of tenant capacity each and aren't subject to inactivity cleanup. Sandboxes also need premium Power Apps licenses for the team accounts, because the Developer Plan can't launch premium apps outside developer environments.
2. Before provisioning, assign `POWERAPPS_DEV` (5b631642-bd26-49fe-bd20-1daaa972ef80) to every team account through Graph or group-based licensing. Also confirm the tenant settings for consent plans and Developer environment assignments.
3. **Keep the environments non-managed.** That rules out masking rules (they need a Managed Environment) and environment routing (it creates managed environments). Without Managed Environments the Developer Plan alone covers running the model-driven app.
4. Build the Service Desk solution once (tables, columns, relationships, forms, views, sitemap, app module, and optionally the least-privilege role as a template). Export it and import it per team with `ImportSolutionAsync` or `pac solution import --async --publish-changes`, then poll asyncoperation. Use the Web API per team only for things solutions can't carry: the application user, role assignment, organization audit settings, field security assignments and seed data.
5. Give environment domains a unique suffix; a deleted environment's URL can't be reused for 24 hours.
6. Use one user-assigned managed identity per team. That keeps audit attribution clean and gives each team its own service protection bucket, though the tenant-pooled daily entitlement is still shared. Create the application user with the UAMI client ID via `pac admin assign-user --application-user --role "System Administrator"`. The MCP server calls `ManagedIdentityCredential(client_id=...)` with scope `https://<org>.crm.dynamics.com/.default`, or uses `DataverseClient`.
7. Make the denial deterministic: have the least-privilege role leave out `prvWritemsp_Ticket` entirely, which produces HTTP 403 with code `0x80040220` (PrivilegeDenied). If the role grants Write at Basic depth instead, participants get the access-check error -2147187962 on records they don't own. Have the MCP server pass `error.code` and `error.message` through verbatim, and send `Consistency: Strong` (or wait about 30 seconds) after role changes.
8. Order the column-security steps: demote the MCP application user from System Administrator first, because the bypass hides column security. Secure `emailaddress1`, `telephone1` and `mobilephone`, publish, then add the field security profile. Expect reads to return the columns empty, not an error, and updates to fail with `0x8004F507` (403). Don't use contact email as an alternate key, because secured columns can't be key columns.
9. Turn on auditing during provisioning: organization `isauditenabled`, IsAuditEnabled on `msp_ticket`, `msp_ticketnote`, `contact` and the key columns, then publish. For the readback exercise, query `audits` by `_objectid_value` and `objecttypecode` and expand `userid`; the application user's First Name is "#", so expect that in the display name. Allow for delay. Don't rely on Web API RetrieveRecordChangeHistory for who and when. If the MCP server itself exposes audit tools, its role needs `prvReadAuditSummary` and `prvReadRecordAuditHistory`.
10. Keep ticket notes in the custom table: Annotation can't be audited, and the custom table supports the bulk messages.
11. Seed loader: create alternate keys and wait until they're Active. Use UpsertMultiple for custom tables and small `$batch` change sets for account and contact, honor `Retry-After`, and budget the shared daily pool across all teams (25,000 per 24 hours if the tenant has only Power Apps licenses).
12. Inactivity: environments are disabled after 30 days without activity and deleted 15 days later. For longer-lived labs, include re-enable or "Trigger environment activity" steps, or tear down and reprovision. Flow runs are capped at 750 a month.

## Unverified or contradictory

- **Admin or service principal creating a developer environment for another user:** the API and CLI surfaces exist (`usedBy`, `--used-by-*`, `pac admin create --user`), and the routing FAQ mentions creation "on their behalf". But no page explains ownership, licensing checks or the three-environment cap in that case, or whether a service principal (which can't hold licenses) is allowed. Needs a live test.
- Whether Web API calls made by an application user count as "activity" for inactivity cleanup isn't stated.
- **Application user creation through raw `POST systemusers`** (`applicationid` + `businessunitid@odata.bind`) isn't documented on the pages read. Documented routes are PPAC, `pac admin assign-user --application-user` and BAP `addAppUser` (preview, always System Administrator).
- **Contradiction:** the multi-tenant S2S page says an application user can't be given a default security role and needs a custom one, while PPAC, pac and the BAP API all assign System Administrator to application users. https://learn.microsoft.com/power-apps/developer/data-platform/use-multi-tenant-server-server-authentication versus https://learn.microsoft.com/power-platform/admin/create-dataverseapplicationuser
- The exact runtime text of the PrivilegeDenied message wasn't captured. The docs give a template ({5} {2}(Id = {3}) is missing {0} privilege...) and a troubleshooting paraphrase. Capture the real string in a dry run for the lab guide.
- Whether `emailaddress1` and `telephone1` on contact can be secured isn't stated (`mobilephone` is). Check CanBeSecuredForRead with RetrieveMetadataChanges in the build environment.
- No document says auditing or column security works in developer environments, but none says it doesn't either. Only Purview logging is limited to production.
- **Audit retention default contradiction:** the developer doc says `auditretentionperiodv2` defaults to 30, while the admin doc gives the retention policy default as "Forever".
- **Environment routing contradiction:** the environment-strategy guidance says disallowing manual developer environment creation also stops routing from creating them, while the routing FAQ says changing Developer environment assignments doesn't affect routing.
- Whether a tenant that has only Developer Plan licenses gets the 25,000 per day non-licensed pool ("Power Apps (all licenses)") isn't stated.
- How many web servers a developer environment gets, and therefore its service protection headroom, isn't stated.
- Shared CloudLabs accounts: no Learn guidance for lab or training multi-person use of one account with the Developer Plan. The general rule of one license per person, plus the multiplexing guidance, suggests getting written confirmation from Microsoft licensing.
- The `bulk-operations` performance page names "Account or Contact" as examples of core tables that may not support bulk messages. Verify with an sdkmessagefilters query.
- The `pac environment-management` commands are Preview, and `pac admin create --user` semantics aren't documented.
