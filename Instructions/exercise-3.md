# Exercise 3: MCP Read Tools

### Estimated Duration: 45 minutes

## Scenario

The knowledge index is a snapshot. When a Woodgrove Bank manager phones to ask where a ticket stands, Relecloud's technicians need the live record, not last night's copy. The starter MCP server gives the agent live, read-only access to the Service Desk through tools, and the automation team has to understand exactly what each tool does in Dataverse before anyone trusts it.

## Overview

In this exercise, you open your team's copy of the MCP server source on the lab VM, read its tool manifest, and trace one tool from its definition to the Dataverse Web API query it sends. You connect the server to the agent through API Management with the agent's own identity, call a read tool from the agent, and find that call in the gateway logs. You then test how the tools report errors, make a small change to the server, and redeploy it to your Container App.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Explore the MCP server source
- Task 2: Invoke a read tool from the agent
- Task 3: Test error handling
- Task 4: Change and redeploy the server

## Task 1: Explore the MCP server source

In this task, you will open your team's copy of the MCP server source, read the tool manifest, and trace one read tool to its Dataverse Web API query and the permissions it needs.

1. In PowerShell 7 on the VM, open the MCP server source. Your team's copy is already on the VM in `C:\LabFiles\mcp-server`: a local Git repository of release `v1.0.0`, the version running in your Container App. Create a branch for your team's changes and open the folder in Visual Studio Code:

   ```powershell
   Set-Location C:\LabFiles\mcp-server
   git log --oneline --decorate -1
   git switch -c team-changes
   code .
   ```

   `git log` shows one commit, tagged `v1.0.0`, and Git reports that you are on the new branch `team-changes`.

   > **Note:** Relecloud keeps the server's source in a private repository, and your copy has no remote. Your changes reach your Container App only when you deploy them, and `git diff` always shows exactly what your team changed.

1. In Visual Studio Code, open `TOOLS.md`. The **Read tools** table lists seven tools with their inputs, outputs, the Dataverse call each one makes, and the privileges it needs. The **Write tools** table lists five more that you use in Exercise 4.

   > **[SCREENSHOT PENDING: E3T1S2 | TOOLS.md read tools table open in Visual Studio Code | source: capture]**

1. In the Visual Studio Code terminal, read the machine-readable manifest the server returns for `tools/list`:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List
   ```

   The **ReadOnly** column is `True` for the seven read tools. Compare the **Required** column with the inputs in `TOOLS.md`.

1. Trace **get_ticket** to its Dataverse query. Open `src/servicedesk_mcp/tools_read.py` and find `async def get_ticket`. The function's docstring is the tool description the agent reads, and the `TicketNumber` type sets the input pattern `^TCK-\d{5}$`. The function calls `repo.get_ticket`.

1. Open `src/servicedesk_mcp/dataverse_repository.py` and find `async def get_ticket`. It sends one Web API request that looks the ticket up by its alternate key, the ticket number:

   ```text
   GET /api/data/v9.2/msp_tickets(msp_ticketnumber='TCK-10489')?$select=<TICKET_SELECT>&$expand=<TICKET_EXPAND>
   ```

   `TICKET_SELECT` and `TICKET_EXPAND`, at the top of the file, list the ticket columns it reads and the related customer, requester, technician and knowledge article it expands.

   > **[SCREENSHOT PENDING: E3T1S5 | dataverse_repository.py get_ticket with the alternate key request in Visual Studio Code | source: capture]**

1. Note the permissions. In `TOOLS.md`, the **Privileges** column for get_ticket lists **Read** on `msp_ticket`, `account`, `contact`, `msp_technician` and `msp_knowledgearticle`. The server holds them as its own identity: in `dataverse_repository.py`, `ManagedIdentityCredential(client_id=...)` signs in as the managed identity **id-mcp-<inject key="DeploymentID" enableCopy="false"/>**, which Dataverse knows as an application user. Today that application user has the **System Administrator** role, far more than Read. You fix that in Exercise 5.

## Task 2: Invoke a read tool from the agent

In this task, you will add the MCP server to the agent, authenticated by the agent's identity, call a read tool, compare the result with the app, and find the call in the API Management logs.

1. In the Foundry portal, open **Build** > **Agents** > **msp-support-agent**, and on the **Playground** tab open the **Tools** list and select **Add**.

1. In **Select a tool**, select the **Custom (1)** tab, select **Model Context Protocol (MCP) (2)**, and then select **Create (3)**.

   > **[SCREENSHOT PENDING: E3T2S2 | Foundry Select a tool dialog with the Custom tab and Model Context Protocol (MCP) selected | source: capture]**

1. In **Add Model Context Protocol tool**, enter the following details:

   - **Name:** `servicedesk` **(1)**
   - **Remote MCP Server endpoint:** <inject key="MCP Gateway URL" enableCopy="true"/> **(2)**
   - **Authentication:** **Microsoft Entra** **(3)**
   - **Type:** **Agent Identity** **(4)**
   - **Audience:** <inject key="MCP Gateway Audience" enableCopy="true"/> **(5)**

   Select **Connect (6)**.

   > **[SCREENSHOT PENDING: E3T2S3 | Add Model Context Protocol tool form with the gateway URL, Microsoft Entra agent identity and audience | source: capture]**

   > **Note:** The audience is the Application ID URI of the gateway app registration, not the gateway URL. Foundry asks Microsoft Entra ID for a token for that audience on behalf of your agent identity, and API Management accepts only tokens for this audience whose client ID is your agent identity's.

1. Select **Save** to save the agent with its new tool.

   > **Note:** If your portal doesn't offer these options, run the fallback script below in PowerShell 7 instead. It creates the same MCP connection and tool, keeps the knowledge index, and also applies the tool-use instructions from `instructions-ex3.md`.

   ```powershell
   C:\LabFiles\tools\Update-AgentDefinition.ps1 -Tools
   ```

1. Give the agent instructions for using tools. In Visual Studio Code, open `C:\LabFiles\agent\instructions-ex3.md`, select all the text and copy it. In the playground, replace the agent's **Instructions** with it and select **Save**. The new rules cover when to use tools rather than the index, how to treat errors such as `DATAVERSE_ACCESS_DENIED`, and how to keep internal notes out of customer text.

1. Start a new chat and ask for live data:

   ```
   Get the current details of ticket TCK-10489 from the Service Desk tools, including its status, assigned technician and SLA figures.
   ```

1. When the playground asks you to approve the tool call, check that the tool is **get_ticket** and the argument is `TCK-10489`, then select **Approve**.

   > **[SCREENSHOT PENDING: E3T2S7 | Playground tool approval prompt for get_ticket with its arguments | source: capture]**

   > **Note:** Every call to this MCP server asks for approval. The approval prompt is your first governance control: you see the tool and its arguments before anything runs.

1. Compare the answer with the record: in the Service Desk app, open **TCK-10489** and check **Status** (**In Progress**), **Assigned Technician** (**Daniel Cho**) and the **SLA** section.

1. In the Azure portal, open the Log Analytics workspace **log-msp-<inject key="DeploymentID" enableCopy="false"/>**, select **Logs**, switch the editor to **KQL mode** if it opens in simple mode, and run:

   ```kql
   ApiManagementGatewayMCPLog
   | where TimeGenerated > ago(1h)
   | where Method == "tools/call" and ToolName == "get_ticket"
   | project TimeGenerated, ToolName, SessionId, CorrelationId, ClientName, AuthenticationMethod, Error
   | order by TimeGenerated desc
   ```

   > **[SCREENSHOT PENDING: E3T2S9 | Log Analytics results for ApiManagementGatewayMCPLog with the get_ticket call | source: capture]**

   > **Note:** Gateway logs reach the workspace 5 to 15 minutes after the call. If the query returns nothing yet, continue with Task 3 and come back.

1. In **Lab notes.txt**, next to **get_ticket call through API Management**, record the **SessionId** and **CorrelationId**. **SessionId** is the MCP session identifier. If it is empty, the session isn't missing by accident: this server runs stateless MCP, so there is no session to record, and **CorrelationId** is the identifier this hop gives you. In Exercise 5 you follow the same two identifiers for a write.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Agent calls a read tool through the gateway" is registered (validation-scripts/README.md). -->

## Task 3: Test error handling

In this task, you will send the tools a nonexistent ID and a call with a missing argument, check that each error is structured and readable, and see how the agent recovers.

1. In the playground, start a new chat so that earlier tickets aren't in context. Ask for a ticket that doesn't exist, and approve the tool call:

   ```
   Show me ticket TCK-99999.
   ```

   **What this validates:** a structured error the agent can act on. The tool returns `TICKET_NOT_FOUND` with the message *No ticket 'TCK-99999' exists in the Service Desk.* and the hint *Check the number with the user, or use search_tickets.* The agent should say the ticket doesn't exist and offer to search, not invent a ticket.

1. Start another new chat, so that no ticket number is in context, and ask for something without the detail the tool needs:

   ```
   Get the notes for the ticket.
   ```

   **What this validates:** the agent asks which ticket you mean instead of guessing a number. If it calls a tool with a guessed number, record that under **Findings** in **Lab notes.txt**.

1. In the Visual Studio Code terminal, call the tool directly with the required argument missing:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_ticket @{}
   ```

   The result shows `isError: True` and a validation message that names `ticket_number` as a required field. The server rejected the call before the tool code ran.

1. Call it with a malformed argument:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_ticket @{ ticket_number = 'TCK-1' }
   ```

   The message says the value doesn't match the pattern `^TCK-\d{5}$`.

   > **[SCREENSHOT PENDING: E3T3S4 | PowerShell output of the malformed get_ticket call with the validation message | source: capture]**

1. Call it with the nonexistent ticket and look at the full error object:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_ticket @{ ticket_number = 'TCK-99999' }
   ```

   Every failure that the tool code returns has the same shape: `ok: false` and an `error` with `code`, `message`, `source`, `retryable` and `hint`. Failures that come from Dataverse also carry the platform's own status, code and message under `error.dataverse`; you see one in Exercise 5. The two argument errors before this one look different: the MCP SDK checks arguments against the tool's input schema before any tool code runs, and it reports a failed check as plain text.

### Success Criteria

- [ ] The agent reported TCK-99999 as not found and didn't invent ticket details
- [ ] The agent asked which ticket you meant when the number was missing
- [ ] The direct calls returned `isError: True` with readable messages for the missing and malformed arguments

## Task 4: Change and redeploy the server

In this task, you will make a small change to the server, build a new image in your team's registry, deploy it as a new Container App revision, and time the cycle.

1. In Visual Studio Code, open `src/servicedesk_mcp/__init__.py` and change the version:

   ```python
   __version__ = "1.0.1"
   ```

1. Open `src/servicedesk_mcp/tools_read.py`, find `async def get_ticket`, and change the first line of its docstring, which is the tool description the agent sees. Keep the line's eight leading spaces; Python uses the indentation, and a misaligned line stops the server from starting. The new line is:

   ```python
           """Get one ticket by number, with its SLA figures and related knowledge article.
   ```

   Save both files.

1. In the Visual Studio Code terminal, build and deploy the change:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag v1-0-1
   ```

   The script builds the image with Azure Container Registry Tasks (no Docker needed on the VM), pushes `mcp-server:v1-0-1` to your registry, creates a new revision of your Container App, and waits until the revision is running and healthy. This takes around **4 to 7 minutes**.

   > **[SCREENSHOT PENDING: E3T4S3 | Deploy-McpServer.ps1 output with the revision table and the cycle time | source: capture]**

1. Record the two times the script prints, **Build took** and **full cycle**, in **Lab notes.txt** next to **Redeploy cycle time**.

1. Confirm the new version is running:

   ```powershell
   Invoke-RestMethod '<inject key="MCP Server URL" enableCopy="false"/>/health'
   ```

   The `version` is now `1.0.1`.

1. Confirm the change is visible to clients:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List
   ```

   The **Summary** of **get_ticket** shows your new description.

1. In the Azure portal, open the Container App **ca-mcp-<inject key="DeploymentID" enableCopy="false"/>** and select **Revisions and replicas** (under **Application**, or under **Configure** > **More** as **Revisions & Replicas** in the updated menu). Confirm the new revision is **Running** with 100% of the traffic.

   > **[SCREENSHOT PENDING: E3T4S7 | Container App Revisions and replicas page with the new revision running | source: capture]**

1. In the playground, start a new chat so the agent reads the tool list again, and ask about TCK-10489 once more. The answer still works: you changed the description, not the behavior.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Changed MCP server redeployed" is registered (validation-scripts/README.md). -->

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **Git reports *dubious ownership* in `C:\LabFiles\mcp-server`:** run `git config --global --add safe.directory C:/LabFiles/mcp-server` and try again. If the folder is missing, tell your facilitator; provisioning creates it.
- **Adding the MCP tool fails, or tool calls fail with 401 Unauthorized:** the audience must be exactly <inject key="MCP Gateway Audience" enableCopy="false"/>, not the gateway URL. If it is right and calls still fail, ask your facilitator to check that the gateway accepts your agent identity's client ID.
- **The playground doesn't ask for approval and nothing happens:** start a new chat; the agent reads its tools when a chat starts.
- **The log query returns no rows:** gateway logs take 5 to 15 minutes to arrive. Widen the time range to `ago(2h)` and try again later.
- **`Deploy-McpServer.ps1` times out waiting for the revision:** the new image probably failed to start. Run the command below, fix the error it shows (usually indentation in the file you edited), and run the deploy script again. Each run creates a revision with a new name, so you can reuse the same `-Tag`.

  ```powershell
  az containerapp logs show --name ca-mcp-<inject key="DeploymentID" enableCopy="false"/> --resource-group <inject key="Resource Group Name" enableCopy="false"/> --type console --tail 50
  ```

</details>

## Summary

In this exercise, you have completed the following:

- Opened your team's copy of the MCP server source and read its tool manifest
- Traced get_ticket from its tool definition to its Dataverse Web API query and the privileges it needs
- Connected the MCP server to the agent through API Management with the agent identity, called a read tool, and found the call in the gateway logs
- Tested the tools with a nonexistent ID and missing and malformed arguments
- Changed the server, rebuilt it in Azure Container Registry, deployed a new revision, and timed the cycle

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
