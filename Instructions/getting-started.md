# Agentic MSP Support Agent Guided Lab

### Overall Estimated Duration: 4 hours

## Lab Scenario

Relecloud Managed Services is a managed service provider that runs IT for 24 customers, from Woodgrove Bank and Humongous Insurance to Fabrikam Residences and Tailspin Toys. Every incident and request lands in Relecloud's Service Desk app, where 12 technicians work the queue. Last quarter's service review found that engineers spent about a third of their handling time searching old tickets and knowledge articles, that new tickets waited in the queue until a technician found time to set their priority and category, and that Platinum and Gold SLA breaches were costing service credits. Today two open tickets still have no priority or category, and five are within two business hours of their SLA target or already past it. As a member of the Relecloud service desk automation team, you are responsible for building an AI support agent that answers from Relecloud's own Service Desk data, acts on tickets through governed tools, and leaves an audit trail that the security team can follow from the agent's answer to the database record.

## Lab Overview

In this lab, your team builds an AI agent over a live ticketing environment. Every team has an identical environment: a dedicated Azure resource group, a Microsoft Foundry agent registered under its own Microsoft Entra Agent ID, a Service Desk model-driven app on Microsoft Dataverse seeded with customers, contacts, knowledge articles, technicians and historical tickets, a starter MCP (Model Context Protocol) server with reference tools, and the identity, secret storage, gateway and logging around them. Permissions are enforced by Dataverse security roles.

The MCP server source is already on your lab VM, as a local Git repository of the release your Container App runs. You change it there and redeploy it to your team's Container App; you don't need a GitHub account. When you arrive, the agent has no knowledge connection, no tools beyond its model, and no permission model. You add each of these during the lab.

The session runs for 5 hours, of which 4 hours are hands-on:

| Time | Segment | Duration |
|---|---|---|
| 00:00 | Arrival, sign-in and orientation (this page) | 15 min |
| 00:15 | Exercise 1: Environment Verification and Grounding | 65 min |
| 01:20 | Break | 10 min |
| 01:30 | Exercise 2: Ticket and Incident Intelligence | 35 min |
| 02:05 | Exercise 3: MCP Read Tools | 45 min |
| 02:50 | Break | 10 min |
| 03:00 | Exercise 4: MCP Action Tools | 50 min |
| 03:50 | Exercise 5: Security, Governance, and Audit | 45 min |
| 04:35 | Wrap-up | 15 min |
| 04:50 | Close and float | 10 min |

## Lab Objectives

After completing this lab, you will be able to:

- **Environment verification and grounding:** Verify a team environment end to end, build a search index over Dataverse data, and ground a Foundry agent in it so that every answer cites its source.
- **Ticket and incident intelligence:** Use the grounded agent to find similar incidents, summarize a customer's open issues, recommend triage, and spot SLA risk in business hours.
- **MCP read tools:** Trace an MCP tool from its manifest to its Dataverse Web API query, call it from the agent through API Management, test its error handling, and redeploy a change.
- **MCP action tools:** Let the agent change tickets through write tools, keep internal notes out of customer replies, chain grounding into action, and tighten an argument boundary in code.
- **Security, governance, and audit:** Replace an over-privileged backend identity with a least-privilege Dataverse role, protect contact data with column security, and trace one agent action across four logs.

## Prerequisites

Before starting the lab, you should have:

- Working knowledge of the Azure portal and resource groups
- Basic PowerShell and the ability to read Python and JSON
- A general idea of how REST APIs and OAuth tokens work
- Familiarity with service desk concepts (tickets, priorities, SLAs); Power Apps or Dataverse experience helps but isn't required

The following are prerequisites, **already configured in this lab environment**:

- An **Azure subscription** with your team's resource group and every Azure resource in it (pre-provisioned)
- A **Microsoft Entra ID** work account for your team (pre-created; its credentials are on the **Environment** tab)
- A **Power Apps Developer Plan** licence on your team account, and a **Power Platform developer environment** with the Service Desk app and seeded data (pre-provisioned)
- The **Foundry agent** `msp-support-agent`, already registered with its own **Microsoft Entra Agent ID** (pre-created, with no knowledge and no tools)
- The **starter MCP server**, release `v1.0.0`, running in your Container App, with its source on your lab VM in `C:\LabFiles\mcp-server` (pre-deployed)

## Architecture

The service desk engineer works in three places: the Foundry agent playground, the Service Desk app, and the lab VM. The Foundry agent runs on the `gpt-5.4-mini` model. It reads knowledge from an Azure AI Search index that you build from the Dataverse tables, and it calls MCP tools through Azure API Management, which accepts only a Microsoft Entra token issued to the agent's own agent identity. API Management forwards each call to the MCP server in Azure Container Apps with a gateway key from Azure Key Vault, so the server can't be called around the gateway. The MCP server reads and writes Dataverse as its own managed identity, which Dataverse knows as an application user; that application user's security role is the real limit on what the agent can do. You build new versions of the MCP server from its source on the lab VM with Azure Container Registry. Foundry agent traces go to Application Insights, and API Management and the MCP server write their logs to the same Log Analytics workspace, which is how you trace one action end to end.

## Architecture Diagram

![Architecture of the lab: the support agent in Microsoft Foundry grounded in Azure AI Search, calling the MCP server in Azure Container Apps through API Management with its agent identity, and the MCP server reading and writing Dataverse as a managed identity](./media/architecture.png)

## Explanation of Components

| Component | Description |
|-----------|-------------|
| Microsoft Foundry Agent Service | Hosts `msp-support-agent`, a prompt agent on `gpt-5.4-mini`. You add its knowledge, tools and instructions during the lab and test it in the agent playground. |
| Microsoft Entra Agent ID | Gives the agent its own agent identity. The agent presents a token for this identity when it calls MCP tools, and API Management checks it. |
| Microsoft Entra ID | Holds your team account, the agent identity, and the gateway app registration whose Application ID URI is the token audience for the MCP gateway. |
| MCP server (Azure Container Apps) | The Relecloud Service Desk MCP server: seven read tools and five write tools over the Service Desk tables. It is the only code in the lab. |
| Azure API Management | The MCP gateway. One API accepts only the agent identity; a second diagnostics API accepts a subscription key so you can call tools yourself. It logs every MCP call. |
| Microsoft Dataverse | The system of record in your Power Platform developer environment: tickets, ticket notes, customers, contacts, knowledge articles, technicians, SLA policies and the business calendar. |
| Power Apps model-driven app | The **Service Desk** console. You use it to check every answer and every change the agent makes. |
| Azure AI Search | Hosts the `servicedesk-knowledge` index that you create and load from Dataverse. It is the agent's knowledge source. |
| Azure Key Vault | Stores the key that API Management sends to the MCP server, so only the gateway can call the server. |
| Azure Container Registry | Builds new MCP server images from the source on your lab VM, with `az acr build`, so you don't need Docker on the VM. |
| Azure Monitor (Log Analytics and Application Insights) | Collects agent traces, API Management gateway and MCP logs, and the MCP server's tool-call log. |
| Git (on the lab VM) | Your team's copy of the MCP server source at release `v1.0.0`. `git diff` shows exactly what your team changed. |

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

Some tasks in this lab are automatically graded. After completing a task, click the **Validate** button for the corresponding step - inline in the guide or on the **Lab Validation** tab.

1. If you receive a success message, proceed to the next task.
1. If validation fails, hover over the information icon to read the error message, retry the step, and validate again.

> **[SCREENSHOT PENDING: GS6 | Lab Validation tab with the Validate button per step | source: reuse]**

> **Note:** Several checks read the MCP server's logs, which reach Log Analytics a few minutes after the action. If a validation fails right after you finish a task, wait two or three minutes and validate again.

## Before You Begin: Browser and Clipboard Tips

> **Note:** Use **Microsoft Edge** or **Google Chrome** for the best experience. Firefox and Safari can show a persistent "Paste" button that interferes with clicks.

> **Note:** When the browser asks for clipboard permission, select **Allow** - the copy buttons in this guide need it. If copy-paste into the VM still fails, use the **VM Native Clipboard** slider in the ellipsis (three-dot) menu, or right-click and copy manually.

> **Note:** If the browser-based VM connection fails, check that your network allows `wss://*.ms-cloudlabs.ai` (minimum 8 Mbps), disable VPN/proxy and ad blockers, or fall back to a native RDP connection using the **LabVM DNS Name**, **LabVM Admin Username**, and **LabVM Admin Password** from the **Environment** tab (prefix a local username with `.\`).

> **Note:** Lab emails (invitations, credentials) come from **noreply@cloudlabsai.net**; check your SPAM/JUNK folder and add the sender to your safe senders list.

> **Note:** Everyone in your team signs in with the same team account. Agree who drives each task, and keep one browser tab per portal so that sign-ins don't collide.

## Let's Get Started with Azure Portal

1. In the virtual machine, double-click the **Azure Portal** shortcut on the desktop (or browse to the URL below):

   ```
   https://portal.azure.com
   ```

1. On the **Sign into Microsoft** tab, enter the following email/username, and click **Next**:

   - **Email/Username:** <inject key="AzureAdUserEmail" enableCopy="true"/>

     > **[SCREENSHOT PENDING: GS7 | Sign-in screen with the username field highlighted | source: capture]**

1. Enter the following Temporary Access Pass, and click **Sign in**:

   - **Temporary Access Pass:** <inject key="AzureAdUserPassword" enableCopy="true"/>

     > **[SCREENSHOT PENDING: GS8 | Sign-in screen with the Temporary Access Pass field highlighted | source: capture]**

   > **Note:** Azure requires multifactor authentication to sign in to the Azure portal and for every change you make through the Azure CLI. The Temporary Access Pass satisfies that requirement; use it again whenever the lab asks you to sign in.

1. If you're asked to set up a passkey or the Microsoft Authenticator app, select **Skip for now**.

   > **Note:** Don't register a personal phone, authenticator app or passkey on the team account. The whole team shares it, and the Temporary Access Pass is all you need.

1. If you see the **Stay signed in?** pop-up, click **No**.

1. If a **Welcome to Microsoft Azure** tour pop-up appears, select **Maybe Later** to skip it.

1. In the search bar at the top of the portal, type **Resource groups** and select **Resource groups**, then select your resource group:

   ```
   <inject key="Resource Group Name" enableCopy="false"/>
   ```

   > **[SCREENSHOT PENDING: GS9 | Resource groups page with the team resource group selected | source: capture]**

## Sign In to the Azure CLI

The lab scripts on the VM use your own Azure CLI sign-in. Sign in once now.

1. On the VM, select **Start**, type **PowerShell 7**, and open **PowerShell 7 (x64)**.

1. Run the following command:

   ```powershell
   az login
   ```

1. In the sign-in window that opens, choose **Work or school account** if you are asked, and sign in with the team account:

   - **Email/Username:** <inject key="AzureAdUserEmail" enableCopy="true"/>
   - **Temporary Access Pass:** <inject key="AzureAdUserPassword" enableCopy="true"/>

   > **Note:** Depending on the Azure CLI version, the sign-in opens as a Windows account window or as a browser tab. Both work. Because you sign in with the Temporary Access Pass, the changes you make later with `az` meet Azure's multifactor authentication requirement. If a command later fails with an error that asks for multifactor authentication, run `az login` again and sign in with the pass.

1. If the Azure CLI lists subscriptions and asks you to select one, press **Enter** to keep the default.

1. Confirm the sign-in:

   ```powershell
   az account show --query "{user:user.name, subscription:name}" --output table
   ```

   The **User** column shows your team account.

   > **[SCREENSHOT PENDING: GS10 | PowerShell 7 window showing az account show output with the team account | source: capture]**

## Meet Your Team Environment

1. On the VM desktop, find the shortcuts the environment created for you: **Service Desk**, **Microsoft Foundry**, **Azure Portal**, **Power Platform admin center** and **Microsoft Entra admin center**.

1. Open **Team environment.txt** on the desktop. It lists the names and addresses of your team's resources. The full settings, which the lab scripts read, are in `C:\LabFiles\team-settings.json`.

1. Open **Lab notes.txt** on the desktop and keep it open. The exercises ask you to record values here, such as your agent identity's object ID and the time of a change, and later exercises use them.

   > **[SCREENSHOT PENDING: GS11 | Lab VM desktop with the lab shortcuts, Team environment.txt and Lab notes.txt | source: capture]**

## Support Contact

The CloudLabs support team is available 24/7, 365 days a year, via email and live chat.

- Email Support: cloudlabs-support@spektrasystems.com
- Live Chat Support: https://cloudlabs.ai/labs-support

When you contact support, include your Deployment ID: <inject key="DeploymentID" enableCopy="true"/>

Now you're all set to explore the powerful world of technology. Learn, experiment, and make the most of your lab experience!

Click **Next** from the bottom-right corner to embark on your lab journey!

### Happy Learning!!
