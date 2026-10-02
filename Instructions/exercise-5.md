# Exercise 5: Identity, Secrets and Authorization

### Estimated Duration: 45 minutes

## Scenario

Before Relecloud's security team signs off, it wants answers to three questions about every action the agent takes: who is acting, with which credentials, and who decided it was allowed. A support agent that quietly acts with more access than the technician using it would be worse than no agent at all, so the automation team has to prove that the platform, not the agent's own code, draws every line.

## Overview

In this exercise, you map every identity and token in a request from the technician to Dataverse, and record which permissions are delegated from the user and which belong to the application. You verify that the MCP server's backend credential lives only in Key Vault and is read through a managed identity. You then narrow a least-privilege boundary further and watch Dataverse refuse the action, and finally show that the same agent and the same MCP server do less for the Tier 1 Technician than for the Senior Technician, because each call runs on behalf of the person who asked.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Map the Identities and Token Flow
- Task 2: Verify Secure Secret Handling
- Task 3: Enforce a Least-Privilege Boundary
- Task 4: Apply User-Level Authorization

## Task 1: Map the Identities and Token Flow

In this task, you will find the identity behind every hop. Every hop in User, Agent, MCP and Dataverse runs as a defined identity.

![Sequence of one tool call: the technician's request reaches the Foundry agent, the OAuth connection gets the technician's delegated token for the gateway, API Management validates it and forwards the call with the gateway key and the user's identity, and the MCP server calls Dataverse with its managed identity on behalf of the technician](./media/identity-token-flow.png)

1. Identify the user identity, the agent's Microsoft Entra Agent ID, the gateway, the MCP server's managed identity and the Dataverse application user. Find each one and record it in **Lab notes.txt**:

   | Identity | Where to find it |
   |---|---|
   | **User** | The Senior Technician, <inject key="AzureAdUserEmail" enableCopy="false"/>, signed in to the playground |
   | **Entra Agent ID** | Run `C:\LabFiles\tools\Get-AgentIdentity.ps1`, then in the **Microsoft Entra admin center** open **Entra ID** > **Agent ID** > **All agent identities** and search for the object ID |
   | **Gateway** | API Management **apim-msp-<inject key="DeploymentID" enableCopy="false"/>**, and the app registration **Relecloud Service Desk MCP Gateway** whose audience is <inject key="MCP Gateway Audience" enableCopy="false"/> |
   | **MCP server's managed identity** | **id-mcp-<inject key="DeploymentID" enableCopy="false"/>**, client ID <inject key="MCP Backend Identity Client ID" enableCopy="false"/>, assigned to the Container App |
   | **Dataverse application user** | In the **Power Platform admin center**, open your environment > **Settings** > **Users + permissions** > **Application users**, and find the user whose application ID is the managed identity's client ID |

   > **[SCREENSHOT PENDING: E5T1S1 | Power Platform admin center Application users list with the MCP server's application user | source: capture]**

1. For one write action, trace which token is presented at each hop and what it is scoped to. Use the approved priority change on TCK-10501 from Exercise 4 Task 1. In the Azure portal, open **apim-msp-<inject key="DeploymentID" enableCopy="false"/>** > **APIs** > **Service Desk MCP**, and open the **Inbound processing** policy to see how the gateway checks and replaces the token:

   | Hop | What is presented | Scoped to | Issued to |
   |---|---|---|---|
   | Technician to Foundry | A user token | `https://ai.azure.com` | The Senior Technician |
   | Agent to API Management | The user's delegated token from the OAuth connection **<inject key="MCP Connection Name" enableCopy="false"/>** | Audience <inject key="MCP Gateway Audience" enableCopy="false"/>, scope `ServiceDesk.Access` | The Senior Technician, through the gateway app |
   | API Management to MCP server | No token: the gateway key `x-backend-key` from Key Vault, plus `x-user-oid`, `x-user-name` and `x-correlation-id` | This one Container App | API Management's managed identity reads the key |
   | MCP server to Key Vault, at startup | A managed identity token | `https://vault.azure.net` | id-mcp |
   | MCP server to Dataverse | A managed identity token and the header `CallerObjectId` set to the technician | Your Dataverse environment | id-mcp, acting on behalf of the technician |

   The policy's `validate-azure-ad-token` checks the audience, the issuing client (the gateway app) and the `scp` claim `ServiceDesk.Access`, copies the user's object ID and name into headers, and then deletes the `Authorization` header: the MCP server never sees the user's token.

1. Confirm the agent holds no direct permission on Dataverse. In the **Application users** list from step 1, look for the agent: its Entra Agent ID is not a Dataverse user, and holds no security role. In the Azure portal, open your resource group > **Access control (IAM)** > **Role assignments** and search for the agent's name: it holds no Azure role either. Everything the agent does in Dataverse goes through a tool, as the signed-in technician.

1. Record which permissions are delegated from the user and which belong to the application. In **Lab notes.txt**, next to **Identities on one write**, write down:

   | Delegated from the user | Belonging to an application |
   |---|---|
   | The scope `ServiceDesk.Access`, which the technician consented to for the connection | id-mcp's Dataverse roles: **Service Desk Agent Read**, **Service Desk Agent Write** and **Delegate** |
   | The technician's own Dataverse role, which Dataverse applies to every call through `CallerObjectId` | id-mcp's **Key Vault Secrets User** role on the vault, and **AcrPull** on the registry |
   | | API Management's managed identity: **Key Vault Secrets User**, to read the gateway key |
   | | The Purview app's Microsoft Graph application permission **Content.Process.All** |

   Dataverse allows a call only when both the delegated side, the technician's role, and the application side, id-mcp's roles, allow it. Delegate (`prvActOnBehalfOfAnotherUser`) is what lets id-mcp act on the technician's behalf at all.

## Task 2: Verify Secure Secret Handling

In this task, you will confirm the MCP server doesn't run on a static credential embedded in code.

1. Locate the MCP server's backend credential in Azure Key Vault. In the Azure portal, open the key vault **<inject key="Key Vault Name" enableCopy="false"/>**, select **Objects** > **Secrets**, and select **mcp-backend-key**. You can see its versions and metadata, but not its value: your role on the vault is **Key Vault Reader**, which never includes secret values.

   > **[SCREENSHOT PENDING: E5T2S1 | Key vault Secrets list with mcp-backend-key | source: capture]**

1. Confirm the MCP server reads it through its managed identity at runtime.

   - In Visual Studio Code, open `src/servicedesk_mcp/keyvault.py`. `read_secret` asks the managed identity for a token for `https://vault.azure.net` and reads the secret over the Key Vault REST API; `server.py` calls it once, in `create_app`, before the server accepts any request.
   - In the key vault, select **Access control (IAM)** > **Role assignments**: **id-mcp-<inject key="DeploymentID" enableCopy="false"/>** holds **Key Vault Secrets User**.
   - In Microsoft Edge, open <inject key="MCP Server URL" enableCopy="false"/>/health: `gateway_key_source` is `key vault`.

1. Search the repository and the Container App configuration and confirm no secret appears in either.

   - In Visual Studio Code, press **Ctrl+Shift+F** and search the repository for `secret`, then for `password` and `key =`. You find secret names (`mcp-backend-key`, `purview-client-secret`), setting names, and the test value `test-key` in `tests/`, but no credential.
   - In the Azure portal, open the Container App **ca-mcp-<inject key="DeploymentID" enableCopy="false"/>**. Under **Settings** > **Secrets**, there are none. Under **Application** > **Containers**, select **Environment variables**: `KEY_VAULT_URL`, `AZURE_CLIENT_ID`, `AGENT_ID` and the other settings are plain configuration, and no variable holds the key.

1. Review the Key Vault access log entry recorded when the MCP server started. Open the Log Analytics workspace **log-msp-<inject key="DeploymentID" enableCopy="false"/>**, select **Logs**, switch the editor to **KQL mode** if it opens in simple mode, and run:

   ```kql
   AZKVAuditLogs
   | where TimeGenerated > ago(1d)
   | where OperationName == "SecretGet" and Id has "mcp-backend-key"
   | project TimeGenerated, OperationName, HttpStatusCode, CallerIpAddress, ClientInfo, Identity
   | order by TimeGenerated desc
   ```

   Each MCP server revision you deployed in Exercises 3 and 4 read the key once at startup: find the rows whose **Identity** carries the client ID of id-mcp, <inject key="MCP Backend Identity Client ID" enableCopy="false"/>, at the times your revisions started. Rows with the other managed identity are API Management refreshing its copy. Record one entry in **Lab notes.txt** next to **Backend credential**.

   > **[SCREENSHOT PENDING: E5T2S4 | AZKVAuditLogs SecretGet rows for mcp-backend-key by the MCP server's managed identity | source: capture]**

   > **Note:** Key Vault logs reach the workspace a few minutes after the read.

## Task 3: Enforce a Least-Privilege Boundary

In this task, you will narrow a boundary and make Dataverse refuse an action. The denial must come from Dataverse, not from your own code; that distinction is the exercise.

1. Review the security roles already assigned; the baseline is least-privileged with read and write separated. In the **Power Platform admin center**, open your environment > **Settings** > **Users + permissions** > **Application users**, select the MCP server's application user, and select **Edit security roles**: it holds **Service Desk Agent Read**, **Service Desk Agent Write** and **Delegate**, and not System Administrator. Then open **Security roles** and open **Service Desk Agent Write**: under **Custom Tables**, only **Ticket** (Write, Append, Append To) and **Ticket Note** (Create, Write, Append, Append To) have privileges, plus Append To on **Technician** and **Knowledge Article**, all at **Organization** level. Reads are in **Service Desk Agent Read**. The records of one customer, Lamna Healthcare (CUST-014), are owned by the business unit **Relecloud Regulated Accounts**, not by the root business unit.

1. Narrow one boundary further, for example no access to one customer's records. In **Service Desk Agent Write**, change the **Ticket** privileges **Write**, **Append** and **Append To** from **Organization** to **Business Unit**, and select **Save**. The MCP server's application user belongs to the root business unit, so it can now change only tickets that the root business unit owns, and none of Lamna Healthcare's.

   > **[SCREENSHOT PENDING: E5T3S2 | Service Desk Agent Write role with Ticket Write, Append and Append To at Business Unit level | source: capture]**

1. Attempt the now-forbidden action through your agent. Wait about a minute, start a new chat, and send:

   ```
   TCK-10479 at Lamna Healthcare: the clinic needs the reimaged laptop today. Raise it to P3.
   ```

   Approve the **set_ticket_priority** call.

1. Confirm the refusal originates from Dataverse and capture the error the platform returned. The tool returns `DATAVERSE_ACCESS_DENIED` with `source` `dataverse`, and `error.dataverse` carries the platform's own status **403**, its error code and message, which name the access check and the write access that was refused, and the Dataverse request ID. The agent reports that the change isn't permitted and doesn't retry or work around it. In `Show-McpServerLog.ps1`, the call shows **Outcome** `denied` and **DecidedBy** `dataverse`. Record the code and message in **Lab notes.txt** next to **Boundary you narrowed**. Your own code didn't change: the same tool still changes tickets the root business unit owns, as it did for TCK-10501.

   > **[SCREENSHOT PENDING: E5T3S4 | Tool result with DATAVERSE_ACCESS_DENIED and the platform error under error.dataverse | source: capture]**

   > **Note:** Leave the narrowed role in place. No later task changes Lamna Healthcare's tickets.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Least-privilege boundary enforced by Dataverse" is registered (validation-scripts/README.md). -->

## Task 4: Apply User-Level Authorization

In this task, you will show that the agent doesn't gain more access than the person using it.

1. Sign in as your team's Tier 1 Technician, whose Dataverse role is read-only on tickets. In Microsoft Edge, open a new **InPrivate** window (**Ctrl+Shift+N**), browse to `https://ai.azure.com`, and sign in with the Tier 1 Technician's credentials from the **Environment** tab:

   - **Email/Username:** <inject key="Tier 1 Technician Username" enableCopy="true"/>
   - **Temporary Access Pass:** the **Tier 1 Technician** pass on the **Environment** tab

   Open the project **proj-msp-<inject key="DeploymentID" enableCopy="false"/>**, then **Build** > **Agents** > **msp-support-agent**. The first time this user calls a tool, accept the consent request for the Service Desk connection, as you did for the Senior Technician in Exercise 1.

1. Ask the agent to change a ticket's priority and confirm the request is denied for this user. In the InPrivate window, start a new chat and send:

   ```
   Raise TCK-10502 to P2: the whole Woodgrove Bank mortgage team is affected by the slow laptops.
   ```

   Approve the **set_ticket_priority** call. Dataverse refuses it: `DATAVERSE_ACCESS_DENIED`, with a platform message that the user is missing the **prvWritespk_Ticket** privilege. The agent reports that this user isn't permitted to make the change. Reads still work for the Tier 1 Technician: ask the agent for TCK-10502's details and it answers.

   > **[SCREENSHOT PENDING: E5T4S2 | Tier 1 Technician playground with the denied set_ticket_priority call | source: capture]**

1. Make the same request as the Senior Technician and confirm it succeeds, with the same agent and the same MCP server. Back in your normal browser window, signed in as the Senior Technician, start a new chat, send the same message and approve the call. The priority of TCK-10502 changes from **P3** to **P2**.

1. Find both attempts in the logs and the Dataverse audit, and confirm each records the user who made it.

   - In the Visual Studio Code terminal, run `.\scripts\Show-McpServerLog.ps1`. Two **set_ticket_priority** rows show the two users: the Tier 1 Technician with **Outcome** `denied` and **DecidedBy** `dataverse`, and the Senior Technician with **Outcome** `ok`. Each has its own correlation identifier; record both in **Lab notes.txt**.
   - In the Service Desk app, open **TCK-10502** and select **Related** > **Audit History**. The priority change is recorded with the **Senior Technician** as the user who changed it, made through the MCP server's application user. The denied attempt changed nothing, so the audit history has no entry for it; the tool invocation log is where the refusal is recorded, with the Tier 1 Technician's identity.

   > **[SCREENSHOT PENDING: E5T4S4 | Show-McpServerLog.ps1 rows for the denied and the allowed set_ticket_priority calls | source: capture]**

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "User-level authorization" is registered (validation-scripts/README.md). -->

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The narrowed role has no effect:** wait a minute and start a new chat; the server sends `Consistency: Strong` to Dataverse, but the role change itself can take a moment.
- **The Tier 1 Technician can't open the Foundry project:** contact support; the Tier 1 identity holds the Foundry User role on your project.
- **The Tier 1 Technician isn't listed as a Dataverse user:** run the **Lab readiness check** again. If **Tier 1 Technician** isn't **Ready**, contact support.
- **The Key Vault query returns nothing:** widen the time range to `ago(2d)`, and check that the workspace has the `AZKVAuditLogs` table; the vault's diagnostic setting sends its audit events there.

</details>

## Summary

In this exercise, you have completed the following:

- Mapped the user, the Entra Agent ID, the gateway, the MCP server's managed identity and the Dataverse application user, and traced the token at each hop of a write
- Confirmed the agent holds no direct permission on Dataverse, and separated delegated from application permissions
- Verified that the backend credential lives only in Key Vault, is read through a managed identity at startup, and appears in the vault's audit log
- Narrowed the write role to one business unit and captured Dataverse's own refusal
- Showed that the same agent and MCP server refuse a change for the Tier 1 Technician and make it for the Senior Technician, with both attempts recorded against the user

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
