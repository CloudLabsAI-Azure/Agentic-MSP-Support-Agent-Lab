# Agentic MSP Support Agent Guided Lab

### Overall Estimated Duration: 305 minutes of exercises, in a 6-hour session

## Lab Scenario

Relecloud Managed Services is a managed service provider that runs IT for 24 customers, from Woodgrove Bank and Humongous Insurance to Fabrikam Residences and Tailspin Toys. Every incident and request lands in Relecloud's Service Desk app, where 12 technicians work the queue. Last quarter's service review found that engineers spent about a third of their handling time searching old tickets, runbooks and knowledge articles, that new tickets waited in the queue until a technician found time to set their priority and category, and that Platinum and Gold SLA breaches were costing service credits. Today five open tickets still have no priority or category, two of them reported this morning, and five are within two business hours of their SLA target or already past it. As a member of the Relecloud service desk automation team, you are responsible for building an AI support agent that answers from Relecloud's own Service Desk data, acts on tickets through governed tools on behalf of the technician who asks, and leaves an audit trail that the security team can follow from the agent's answer to the database record.

## Lab Overview

In this lab, you build an AI agent that acts as a workplace intelligence layer over a live ticketing and support environment, built end to end on Microsoft services. Every team environment is provisioned and validated in advance and is identical: a dedicated Azure resource group, a Microsoft Foundry agent registered under its own Microsoft Entra Agent ID, a Service Desk app on Microsoft Dataverse holding the seeded customer documentation, knowledge articles, runbooks and ticket history, a working MCP (Model Context Protocol) server with a baseline catalogue of read tools and approval-gated write tools, and the identity, secret storage, gateway, data protection and logging services that support them.

The Service Desk is a custom Power Apps model-driven app, built by Spektra over Dataverse tables for this lab (their names start with `spk_`), so the ticket data your agent reads and writes is the same data a support engineer sees in the console. Dataverse is the only ticketing backend. Permissions are enforced by Dataverse itself through security roles, so a denied action is denied by the platform, and no change to your code can talk it out of that.

Your environment is safe by default. Identities start least-privileged with read and write separated, the MCP server reads its backend credential from Azure Key Vault, sensitive write tools require approval, every tool validates its input, and every request carries a correlation identifier from the user through the agent, the MCP tool and Dataverse. The exercises extend and test these controls; none of them asks you to fix an exposure before the environment is safe to use.

Each team signs in with two issued identities: a **Senior Technician**, used for most of the lab, and a **Tier 1 Technician** with narrower permissions, used to show user-level authorization. The MCP server source is already cloned on your lab VM from a single shared repository; you modify, build and redeploy your own team's copy. No GitHub account is required.

Your agent starts with no knowledge connection. Every team begins from the identical environment, so what is compared at the end is what was built: grounding quality, MCP tool design, security and the strength of the business case.

The six hours below are wall-clock, inclusive of sign-in and breaks. Hands-on exercise time totals just over five hours.

| Time | Activity | Duration |
|---|---|---|
| 00:00 | Sign in, launch your assigned lab and verify readiness | 15 min |
| 00:15 | Exercise 1: Environment Readiness and Grounding the Agent | 50 min |
| 01:05 | Break | 10 min |
| 01:15 | Exercise 2: Ticket and Incident Intelligence | 35 min |
| 01:50 | Exercise 3: Using the MCP Read Tools | 45 min |
| 02:35 | Break | 10 min |
| 02:45 | Exercise 4: Using the MCP Action Tools | 60 min |
| 03:45 | Break | 10 min |
| 03:55 | Exercise 5: Identity, Secrets and Authorization | 45 min |
| 04:40 | Exercise 6: Data Protection and Auditability | 45 min |
| 05:25 | Exercise 7: End-to-End Scenario and Business Case | 25 min |
| 05:50 | Close, with schedule float retained | 10 min |

## Lab Objectives

After completing this lab, you will be able to:

- **Environment readiness and grounding:** Confirm a team environment is ready, build a search index over the Service Desk data, and ground a Foundry agent in it so that every answer cites its source.
- **Ticket and incident intelligence:** Use the grounded agent to find similar incidents, summarize a customer's support history, recommend priority, category and assignment, and spot SLA risk in business hours.
- **MCP read tools:** Trace an MCP tool from its catalogue entry to its Dataverse Web API query, call it from the agent, test its error handling, and redeploy a change.
- **MCP action tools:** Let the agent change tickets through approval-gated write tools, keep internal notes out of customer replies, chain grounding into action, tighten a tool boundary, and design a new scoped tool.
- **Identity, secrets and authorization:** Map every identity and token in a request, verify secret handling in Key Vault, and show that Dataverse enforces both a least-privilege boundary and the signed-in user's own role.
- **Data protection and auditability:** Restrict what the agent can return with column security and Microsoft Purview, and follow one correlation identifier through every log.
- **End-to-end scenario and business case:** Run a new incident from intake to an authorized, audited action, and present what you built as something an MSP could deploy.

## Prerequisites

Before starting the lab, you should have:

- Working knowledge of the Azure portal and resource groups
- Basic PowerShell and the ability to read Python and JSON
- A general idea of how REST APIs and OAuth tokens work
- Familiarity with service desk concepts (tickets, priorities, SLAs); Power Apps or Dataverse experience helps but isn't required

The following are prerequisites, **already configured in this lab environment**:

- An **Azure subscription** with your team's resource group and every Azure resource in it (pre-provisioned)
- Two **Microsoft Entra ID** work accounts for your team, the **Senior Technician** and the **Tier 1 Technician** (pre-created; their credentials are on the **Environment** tab)
- A **Power Apps Developer Plan** licence and a **Microsoft 365 E5** licence on both accounts, and a **Power Platform developer environment** with the Service Desk app, its seeded data and least-privileged security roles (pre-provisioned)
- The **Foundry agent** `msp-support-agent`, registered with its own **Microsoft Entra Agent ID**, with the baseline Service Desk MCP tools and no knowledge source (pre-created)
- The **MCP server**, release `v2.0.0`, running in your Container App, with its source already cloned on your lab VM in `C:\LabFiles\mcp-server` (pre-deployed)

## Architecture

The service desk technician works in three places: the Foundry agent playground, the Service Desk app, and the lab VM. The Foundry agent runs on the `gpt-5.4-mini` model. It reads knowledge from an Azure AI Search index that you build from the Service Desk content, and it calls MCP tools through Azure API Management with the signed-in technician's own token (OAuth identity passthrough). API Management validates that token, passes on who the user is, adds a correlation identifier and a gateway key from Azure Key Vault, and forwards the call to the MCP server in Azure Container Apps. The MCP server reads its gateway key from Key Vault at startup through its managed identity, and calls Dataverse as that identity, which Dataverse knows as an application user, on behalf of the technician: Dataverse allows a call only when both the technician's security role and the application user's allow it. Ticket text and customer documents pass through Microsoft Purview before they reach the agent. Foundry agent traces go to Application Insights, and API Management, Key Vault and the MCP server write their logs to the same Log Analytics workspace, so one correlation identifier finds a request at every hop.

## Architecture Diagram

![Architecture of the lab: the technician signs in to the support agent in Microsoft Foundry, which is grounded in Azure AI Search and calls the MCP server in Azure Container Apps through API Management with the technician's token; the MCP server reads its key from Key Vault and acts in Dataverse on behalf of the technician, with Purview and Log Analytics alongside](./media/architecture.png)

## Explanation of Components

| Component | Description |
|-----------|-------------|
| Microsoft Foundry Agent Service | Hosts `msp-support-agent`, a prompt agent on `gpt-5.4-mini`, with the Service Desk MCP tool. You add its knowledge source and grounded instructions during the lab and test it in the agent playground. |
| Microsoft Entra Agent ID | Gives the agent its own identity in Microsoft Entra ID. The MCP server records it in every tool call it logs. |
| Microsoft Entra ID | Holds the Senior Technician and Tier 1 Technician accounts, the agent's identity, and the gateway app registration whose scope `ServiceDesk.Access` the technician's token carries. |
| MCP server (Azure Container Apps) | The Relecloud Service Desk MCP server: nine read tools and five approval-gated write tools over the Service Desk tables. It is the only code in the lab. |
| Azure API Management | The MCP gateway. One API accepts only a signed-in technician's token; a second diagnostics API accepts a subscription key so you can call read tools yourself. It logs every call with its correlation identifier. |
| Microsoft Dataverse | The system of record in your Power Platform developer environment: tickets, ticket notes, customers and their procedures, contacts, knowledge articles, runbooks, technicians, SLA definitions and the business calendar. |
| Power Apps model-driven app | The **Service Desk** console, built by Spektra for this lab. You use it to check every answer and every change the agent makes. |
| Azure AI Search | Hosts the `servicedesk-knowledge` index that you create and load. It is the agent's knowledge source. |
| Azure Key Vault | Stores the gateway key that API Management sends to the MCP server, so only the gateway can call the server. Its audit log records every read. |
| Microsoft Purview | Applies data loss prevention and sensitivity labels to what the tools return to the agent. |
| Azure Container Registry | Builds new MCP server images from the source on your lab VM, so you don't need Docker on the VM. |
| Azure Monitor (Log Analytics and Application Insights) | Collects agent traces, gateway logs, Key Vault audit logs and the MCP server's tool invocation log. |
| Git (on the lab VM) | Your team's copy of the MCP server source at release `v2.0.0`. `git diff` shows exactly what your team changed. |

# Getting Started with the Lab

Welcome to your Agentic MSP Support Agent lab! We've prepared a seamless environment for you to explore and learn. Let's begin by making the most of this experience.

## Accessing Your Lab Environment

Once you're ready to dive in, your virtual machine and lab guide will be right at your fingertips within your web browser.

> **[SCREENSHOT PENDING: GS1 | Lab environment with the virtual machine on the left and the lab guide on the right | source: reuse]**

## Exploring Your Lab Resources

To view your lab credentials and resource details, navigate to the **Environment** tab.

> **[SCREENSHOT PENDING: GS2 | Environment tab showing the lab credentials and resource details | source: reuse]**

## Utilizing the Split Window Feature

For convenience, you can open the lab guide in a separate window by selecting the **Split Window** button from the top right corner.

> **[SCREENSHOT PENDING: GS3 | Split Window button in the top right corner of the lab guide | source: reuse]**

## Managing Your Virtual Machine

Feel free to **Start**, **Stop**, or **Restart** your virtual machine as needed from the **Resources** tab. Your experience is in your hands!

> **[SCREENSHOT PENDING: GS4 | Resources tab with the virtual machine Start, Stop, and Restart controls | source: reuse]**

> **Note:** If the VM is not in use, please **deallocate** it to avoid unnecessary resource consumption. VM running time is budgeted separately from your lab duration; when the uptime limit is exhausted only an admin can extend it. The Container App, API Management and the other Azure services keep running while the VM is stopped, so your work is not lost.

## Lab Guide Zoom In/Zoom Out

To adjust the zoom level for the environment page, click the **A↕ : 100%** icon located next to the timer in the lab environment.

> **[SCREENSHOT PENDING: GS5 | Zoom control next to the lab timer | source: reuse]**

## Lab Validation

Some tasks in this lab are automatically graded. After completing a task, click the **Validate** button for the corresponding step, inline in the guide or on the **Lab Validation** tab.

1. If you receive a success message, proceed to the next task.
1. If validation fails, hover over the information icon to read the error message, retry the step, and validate again.

> **[SCREENSHOT PENDING: GS6 | Lab Validation tab with the Validate button per step | source: reuse]**

> **Note:** Several checks read the MCP server's logs, which reach Log Analytics a few minutes after the action. If a validation fails right after you finish a task, wait two or three minutes and validate again. Tasks without automatic validation have an **Expected results** checklist: compare your results with it before you move on.

## Before You Begin: Browser and Clipboard Tips

> **Note:** Use **Microsoft Edge** or **Google Chrome** for the best experience. Firefox and Safari can show a persistent "Paste" button that interferes with clicks.

> **Note:** When the browser asks for clipboard permission, select **Allow**; the copy buttons in this guide need it. If copy-paste into the VM still fails, use the **VM Native Clipboard** slider in the ellipsis (three-dot) menu, or right-click and copy manually.

> **Note:** If the browser-based VM connection fails, check that your network allows `wss://*.ms-cloudlabs.ai` (minimum 8 Mbps), disable VPN/proxy and ad blockers, or fall back to a native RDP connection using the **LabVM DNS Name**, **LabVM Admin Username**, and **LabVM Admin Password** from the **Environment** tab (prefix a local username with `.\`).

> **Note:** Lab emails (invitations, credentials) come from **noreply@cloudlabsai.net**; check your SPAM/JUNK folder and add the sender to your safe senders list.

> **Note:** Your team signs in as the **Senior Technician** for the whole lab, except Exercise 5 Task 4, where you sign in as the **Tier 1 Technician** in a separate browser window. Agree who drives each task, and keep one browser tab per portal so that sign-ins don't collide.

## Let's Get Started with Azure Portal

1. In the virtual machine, double-click the **Azure Portal** shortcut on the desktop (or browse to the URL below):

   ```
   https://portal.azure.com
   ```

1. On the **Sign into Microsoft** tab, enter the Senior Technician's email/username, and click **Next**:

   - **Email/Username:** <inject key="AzureAdUserEmail" enableCopy="true"/>

     > **[SCREENSHOT PENDING: GS7 | Sign-in screen with the username field highlighted | source: capture]**

1. Enter the following Temporary Access Pass, and click **Sign in**:

   - **Temporary Access Pass:** <inject key="AzureAdUserPassword" enableCopy="true"/>

     > **[SCREENSHOT PENDING: GS8 | Sign-in screen with the Temporary Access Pass field highlighted | source: capture]**

   > **Note:** Azure requires multifactor authentication to sign in to the Azure portal and for every change you make through the Azure CLI. The Temporary Access Pass satisfies that requirement; use it again whenever the lab asks you to sign in.

1. If you're asked to set up a passkey or the Microsoft Authenticator app, select **Skip for now**.

   > **Note:** Don't register a personal phone, authenticator app or passkey on the team accounts. The whole team shares them, and the Temporary Access Pass is all you need.

1. If you see the **Stay signed in?** pop-up, click **No**.

1. If a **Welcome to Microsoft Azure** tour pop-up appears, select **Maybe Later** to skip it.

1. In the search bar at the top of the portal, type **Resource groups** and select **Resource groups**, then select your resource group:

   ```
   <inject key="Resource Group Name" enableCopy="false"/>
   ```

   > **[SCREENSHOT PENDING: GS9 | Resource groups page with the team resource group selected | source: capture]**

## Sign In to the Azure CLI

Some lab scripts on the VM use your own Azure CLI sign-in. Sign in once now.

1. On the VM, select **Start**, type **PowerShell 7**, and open **PowerShell 7 (x64)**.

1. Run the following command:

   ```powershell
   az login
   ```

1. In the sign-in window that opens, choose **Work or school account** if you are asked, and sign in as the Senior Technician:

   - **Email/Username:** <inject key="AzureAdUserEmail" enableCopy="true"/>
   - **Temporary Access Pass:** <inject key="AzureAdUserPassword" enableCopy="true"/>

   > **Note:** Depending on the Azure CLI version, the sign-in opens as a Windows account window or as a browser tab. Both work. Because you sign in with the Temporary Access Pass, the changes you make later with `az` meet Azure's multifactor authentication requirement. If a command later fails with an error that asks for multifactor authentication, run `az login` again and sign in with the pass.

1. If the Azure CLI lists subscriptions and asks you to select one, press **Enter** to keep the default.

1. Confirm the sign-in:

   ```powershell
   az account show
   ```

   In the output, **user** > **name** is the Senior Technician account.

   > **[SCREENSHOT PENDING: GS10 | PowerShell 7 window showing az account show output with the team account | source: capture]**

## Meet Your Team Environment

1. On the VM desktop, find the shortcuts the environment created for you: **Lab readiness check**, **Service Desk**, **Microsoft Foundry**, **Azure Portal**, **Microsoft Purview**, **Power Platform admin center** and **Microsoft Entra admin center**.

1. Open **Team environment.txt** on the desktop. It lists the names and addresses of your team's resources and both identities. The full settings, which the lab scripts read, are in `C:\LabFiles\team-settings.json`.

1. Open **Lab notes.txt** on the desktop and keep it open. The exercises ask you to record values here, such as correlation identifiers and the outcome of each check, and later exercises use them. The last section is the business case template you complete in Exercise 7.

   > **[SCREENSHOT PENDING: GS11 | Lab VM desktop with the lab shortcuts, Team environment.txt and Lab notes.txt | source: capture]**

## Support Contact

The CloudLabs support team is available 24/7, 365 days a year, via email and live chat. Contact support whenever a readiness check fails or the environment behaves differently from the expected results in this guide; don't work around an environment failure.

- Email Support: cloudlabs-support@spektrasystems.com
- Live Chat Support: https://cloudlabs.ai/labs-support

When you contact support, include your Deployment ID: <inject key="DeploymentID" enableCopy="true"/>

Now you're all set to explore the powerful world of technology. Learn, experiment, and make the most of your lab experience!

Click **Next** from the bottom-right corner to embark on your lab journey!

### Happy Learning!!
