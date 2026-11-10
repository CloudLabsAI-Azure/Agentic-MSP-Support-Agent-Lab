# Microsoft Purview Runbook: Agentic MSP Support Agent Guided Lab

> **Delivery path: Phase 3 of 8, prepare the environments (Microsoft Purview part).** Provisioning creates the sensitivity label, its publishing policy, the DLP policy for the MCP server's app and the participant's Purview role groups, but one Purview setting has no API: pay-as-you-go billing, which Purview needs before it applies a DLP policy to an Entra-registered AI app. This page enables it in each participant tenant and checks what provisioning created. Before you start, the environment's deployment must have started ([RUNBOOK.md](RUNBOOK.md#t-minus-48-hours-deploy)). Start of the path: [README.md](../../README.md#delivery-path).

**Who:** a CloudLabs engineer signed in as a supplier Global Administrator of the tenant (only a Global Administrator can enable pay-as-you-go). **Time:** about 5 minutes per tenant; the setting can take a few hours to complete, so do it right after the deployment starts.

## Why the lab needs it

Exercise 6 shows Microsoft Purview blocking a card number that the agent would otherwise receive. The MCP server sends each tool result to Microsoft Purview as the **Relecloud Service Desk Purview Integration** app, and the DLP policy **Relecloud Service Desk card numbers** is scoped to that app. Purview applies policies to Entra-registered AI apps only when pay-as-you-go billing is enabled in the tenant. Without it, the policy exists but never blocks, and the exercise's Purview event never appears.

## Prerequisites

- The participant's Azure subscription is in the same tenant (CloudLabs Dedicated Tenant with an Azure subscription).
- The tenant has a license with the service plan `MIP_S_Exchange` or `EXCHANGE_S_FOUNDATION`; Microsoft 365 E5 includes both.
- A resource group for the Purview billing resource. Do **not** use the lab's resource group: its deny policy allows only the lab's resource types. Create a resource group named `purview-billing` in the same subscription, in Canada Central, if it does not exist.

## Enable pay-as-you-go billing

1. Sign in to the Microsoft Purview portal (`https://purview.microsoft.com`) as the supplier Global Administrator of the participant's tenant. Use a private browser window per tenant, so you never act in the wrong tenant.
2. Select the rocket icon in the header, next to **Settings**, then **Get started**. (The same setting is in **Settings** > **Account details**.)
3. Select the participant's Azure subscription and the resource group `purview-billing`, and confirm. The country or region is fixed for the tenant.
4. Wait for the confirmation. The change can take a few hours to complete; you do not need to wait for it before the next tenant.

## Check what provisioning created

Do this after the deployment shows **Succeeded**, in the same portal session:

| Where in the Microsoft Purview portal | What you should see |
|---|---|
| **Information protection** > **Sensitivity labels** | The label **Relecloud Confidential** |
| **Information protection** > **Policies** > **Label publishing policies** | **Relecloud Service Desk label policy**, publishing that label |
| **Data loss prevention** > **Policies** | **Relecloud Service Desk card numbers**, turned on, with the rule **Block card numbers sent to the agent** (sensitive information type **Credit Card Number**, action block) for the app **Relecloud Service Desk Purview Integration** |
| **Settings** > **Roles and scopes** > **Role groups** | The Senior Technician is a member of **Information Protection Analysts** and **Data Security AI Viewers** |
| **Data Security Posture Management for AI** > **Policies** | **Relecloud Service Desk AI interactions**, when the tenant offers it (provisioning creates it if the cmdlet is available and reports it otherwise) |

The readiness check confirms the same objects from the lab VM: component **Microsoft Purview** is **Ready** when the label exists, the DLP policy was created and the configuration document in the Service Desk carries the label. A new label can take up to 24 hours to be published; the check allows for that during the first 24 hours after provisioning.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| **Get started** is not offered | You are not a Global Administrator of this tenant, or pay-as-you-go is already enabled | Check the account; if it is already enabled, **Settings** > **Account details** shows the subscription |
| Enabling fails with a policy error | The lab resource group was selected, and its deny policy refused the billing resource | Select or create the `purview-billing` resource group |
| The DLP policy is missing | The `purview` provisioning step failed (often because a new tenant's Security & Compliance endpoint was not ready yet) | Re-run the `purview` step as [RUNBOOK.md](RUNBOOK.md#if-a-provisioning-step-failed) describes, with `seed`, `mcp`, `readiness` and `finalize` after it |
| The label is missing from the Service Desk's configuration document | The `seed` step ran without a label because `purview` had failed | Re-run `purview`, then `seed` with `-ResetData` more than 48 hours before the event, or replace the environment |
| Exercise 6 shows no Purview event | Pay-as-you-go was enabled less than a few hours ago, or Purview activity is still arriving (60 to 90 minutes) | The participant records the MCP server's log entry for the blocked content, which is immediate, as the guide's Note says |

## Phase checklist

- [ ] Pay-as-you-go billing is enabled in every participant tenant and spare, with the resource group `purview-billing`
- [ ] In a sample of tenants, the label, the label policy, the DLP policy and the role group memberships match the table above
- [ ] The readiness check reports **Microsoft Purview** as **Ready** on every environment 24 hours ahead

---

**Next:** Phase 3 continues: check provisioning in [RUNBOOK.md](RUNBOOK.md#t-minus-45-hours-check-provisioning).
