# Exercise 3: Using the MCP Read Tools

### Estimated Duration: 45 minutes

## Scenario

The knowledge index is a snapshot. When a Woodgrove Bank manager phones to ask where a ticket stands, Relecloud's technicians need the live record, not last week's copy. The MCP server gives the agent live, read-only access to the Service Desk through its read tools, and the automation team has to understand exactly what each tool does in Dataverse, and with whose permissions, before anyone trusts it.

## Overview

In this exercise, you open your team's copy of the MCP server on the lab VM, read its tool catalogue, and trace one read tool from its definition to the Dataverse Web API query it sends. You call a read tool from the agent, compare the result with the app, and find the call in the server's tool invocation log by its correlation identifier. You then test how the tools fail, make a small change to the server, redeploy it to your Container App, and note how to roll back.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Review the MCP Server on Your Lab VM
- Task 2: Call an Existing Read Tool
- Task 3: Test Tool Error Handling
- Task 4: Redeploy Your Copy of the MCP Server

## Task 1: Review the MCP Server on Your Lab VM

In this task, you will read the server your agent calls. The MCP server source is already cloned on your lab VM from a single shared repository. No GitHub account is required.

1. Open the MCP server repository already cloned on your lab VM in Visual Studio Code. In PowerShell 7, run:

   ```powershell
   Set-Location C:\LabFiles\mcp-server
   git log -1
   git switch -c team-changes
   code .
   ```

   `git log` shows one commit, *Relecloud Service Desk MCP server v2.0.0*, the release your Container App runs, and Git reports that you are on the new branch `team-changes`. `git diff` will always show exactly what your team changed.

1. Read the tool catalogue and list the read tools, their descriptions, input schemas and output schemas. In Visual Studio Code, open `TOOLS.md`. Under **Read tools**, each of the nine tools has a description, an input table (argument, type, allowed values, default) and an output schema. Then, in the Visual Studio Code terminal, read the catalogue the server itself publishes for `tools/list`:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List
   ```

   The **Kind** column is `read` for the nine read tools and `write` for the five write tools, and **Approval** shows which ones need the user's approval. Record the nine read tool names in **Lab notes.txt**.

   > **[SCREENSHOT PENDING: E3T1S2 | Invoke-McpTool.ps1 -List output with the Kind and Approval columns | source: capture]**

   > **Note:** The server doesn't publish an output schema in `tools/list`, because Microsoft Foundry rejects schemas with optional fields. `TOOLS.md` documents each tool's output schema instead, and every result ends with the request's `correlation_id`.

1. Trace one tool through the source to the Dataverse Web API query it issues. Trace **get_ticket**:

   - Open `src/servicedesk_mcp/tools_read.py` and find `async def get_ticket`. The docstring is the tool description the agent reads, and the `TicketNumber` type sets the input pattern `^TCK-\d{5}$`. The function calls `repo.get_ticket`.
   - Open `src/servicedesk_mcp/dataverse_repository.py` and find `async def get_ticket`. It sends one Web API request that looks the ticket up by its alternate key, the ticket number:

     ```text
     GET /api/data/v9.2/spk_tickets(spk_ticketnumber='TCK-10489')?$select=<TICKET_SELECT>&$expand=<TICKET_EXPAND>
     ```

   - In the same file, find `async def _request`. Every request carries the header `CallerObjectId` with the signed-in user's object ID, so Dataverse runs it on behalf of that user, and `x-ms-client-request-id` with the request's correlation identifier.

   > **[SCREENSHOT PENDING: E3T1S3 | dataverse_repository.py get_ticket with the alternate key request in Visual Studio Code | source: capture]**

1. Note which permission each tool requires, ready for Exercise 5. In `TOOLS.md`, each tool lists its **Permission**, for example *Read on spk_ticket, account, contact, spk_technician, spk_knowledgearticle* for get_ticket; the same text is in each tool's `_meta` as `relecloud/permission`. In **Lab notes.txt**, next to **Permission each read tool needs**, record the permissions of the nine read tools. Keep in mind whose permissions they are: the server's application user holds them through its **Service Desk Agent Read** role, and because each call runs on behalf of the signed-in user, the user's own role must allow the read too.

## Task 2: Call an Existing Read Tool

In this task, you will confirm the tool layer reaches real data in your own environment.

1. Invoke a read tool from your agent with a valid argument. In the playground, start a new chat and send:

   ```
   Get the current details of ticket TCK-10502 from the Service Desk tools, including its status, priority, assigned technician and SLA figures, and tell me the correlation ID of the tool call.
   ```

   The agent calls **get_ticket** with `TCK-10502`; read tools don't ask for approval.

1. Confirm the data returned matches the same record in the Service Desk app. Open **TCK-10502** in the app: Woodgrove Bank, *Laptop very slow since this week's agent update*, **New**, **P3 Medium**, unassigned, **13.0** of 16 business hours remaining.

   > **[SCREENSHOT PENDING: E3T2S2 | Agent answer for TCK-10502 next to the ticket form in the Service Desk app | source: capture]**

1. Find the call in the tool invocation log and note the correlation identifier recorded with it. In the Visual Studio Code terminal, run:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -Tail 50
   ```

   The script reads the server's live console log and shows one row per tool call. Find the **get_ticket** row: **User** is the Senior Technician, **ActingAs** is `user`, and **CorrelationId** is the identifier API Management gave the request. It matches the `correlation_id` at the end of the tool result the agent quoted. To see every field of the line, including the Dataverse call and its request ID, run it again with the correlation identifier:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -CorrelationId <correlation ID> -Detail
   ```

   In **Lab notes.txt**, next to **Correlation ID of your first read tool call**, record it. In Exercise 6 you follow one identifier like this through every log.

   > **[SCREENSHOT PENDING: E3T2S3 | Show-McpServerLog.ps1 output with the get_ticket call and its correlation ID | source: capture]**

   > **Note:** The same lines reach the Log Analytics table `ContainerAppConsoleLogs` a few minutes later, where the validation step reads them.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Agent calls a read tool through the gateway" is registered (validation-scripts/README.md). -->

## Task 3: Test Tool Error Handling

In this task, you will see how the tools fail. How a tool fails matters more to an agent than how it succeeds.

1. Call the tool with a record identifier that does not exist. In the playground, start a new chat and send:

   ```
   Show me ticket TCK-99999.
   ```

   The tool returns the structured error `TICKET_NOT_FOUND`: *No ticket 'TCK-99999' exists in the Service Desk.*, with the hint *Check the number with the user, or use search_tickets.*

1. Call it again with a required argument missing. The agent's tool schema doesn't let it send a call without `ticket_number`, so call the tool directly, through the gateway's diagnostics API, in the Visual Studio Code terminal:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_ticket @{}
   ```

   Then send a malformed value:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_ticket @{ ticket_number = 'TCK-1' }
   ```

1. Confirm the agent receives a structured, readable error rather than a raw exception or stack trace. Both direct calls show `isError: True` and the same JSON shape as the not-found error: `ok: false`, an `error` with `code` `INVALID_ARGUMENT`, a `message`, `retryable`, a `hint`, and `details.violations` naming the argument, the problem (*Field required*, or the pattern `^TCK-\d{5}$` with the value you sent), and the allowed values. Every result, failed or not, ends with its `correlation_id`. The server checked the arguments against the input schema before the tool ran, so nothing reached Dataverse, and `Show-McpServerLog.ps1` shows the calls with **Outcome** `rejected`.

   > **[SCREENSHOT PENDING: E3T3S3 | INVALID_ARGUMENT error with details.violations for the malformed ticket number | source: capture]**

1. Confirm the agent either recovers or asks a clarifying question, rather than inventing a result. Look back at the TCK-99999 answer: the agent says the ticket doesn't exist and offers to search, rather than inventing one. Then start another new chat, so that no ticket number is in context, and send:

   ```
   Get the notes for the ticket.
   ```

   The agent asks which ticket you mean instead of guessing a number. If it calls a tool with a guessed number, record that under **Findings** in **Lab notes.txt**.

### Expected results

- [ ] TCK-99999 came back as `TICKET_NOT_FOUND` and the agent didn't invent ticket details
- [ ] The missing and malformed arguments came back as `INVALID_ARGUMENT` with `details.violations`, and no stack trace
- [ ] The agent asked which ticket you meant when the number was missing

## Task 4: Redeploy Your Copy of the MCP Server

In this task, you will use the edit, build and redeploy path you need for the rest of the lab. Allow time for the image build.

1. Make a small local change on your VM, for example improving a tool description or adding a log field. Improve the description of **get_ticket**:

   - In Visual Studio Code, open `src/servicedesk_mcp/__init__.py` and change the version:

     ```python
     __version__ = "2.0.1"
     ```

   - Open `src/servicedesk_mcp/tools_read.py`, find `async def get_ticket`, and change the first line of its docstring, which is the tool description the agent sees. Keep the line's eight leading spaces; Python uses the indentation, and a misaligned line stops the server from starting. The new line is:

     ```python
             """Get one ticket by number, with its SLA figures, escalation and related knowledge article.
     ```

   Save both files. Run `git diff` in the terminal to see your change.

1. Build the container image into your team's container registry. In the Visual Studio Code terminal, run:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag v2-0-1
   ```

   Stage **[1/3]** builds the image with Azure Container Registry Tasks (no Docker on the VM) and pushes `mcp-server:v2-0-1` to **<inject key="Container Registry Name" enableCopy="false"/>**. Leave the script running; it continues with the next step by itself. The whole run takes around **4 to 7 minutes**.

1. Deploy the new revision to your team's MCP server Container App. Stage **[2/3]** of the same run creates a new revision of **ca-mcp-<inject key="DeploymentID" enableCopy="false"/>** with the new image, and stage **[3/3]** waits until the revision runs, takes all the traffic and reports version `2.0.1` on `/health`. The container app runs in single revision mode: traffic moves only when the new revision is ready, so a revision that fails to start never takes traffic.

   > **[SCREENSHOT PENDING: E3T4S3 | Deploy-McpServer.ps1 output with the revision table and the cycle time | source: capture]**

1. Confirm the revision is running and that the change is visible to your agent.

   - In the Azure portal, open the Container App **ca-mcp-<inject key="DeploymentID" enableCopy="false"/>** and select **Revisions and replicas**. The new revision is **Running** with 100% of the traffic.
   - In the terminal, run `.\scripts\Invoke-McpTool.ps1 -List`: the **Summary** of **get_ticket** shows your new description.
   - In the playground, start a new chat, so the agent reads the tool list again, and ask about TCK-10502 once more. The answer still works: you changed the description, not the behavior.

   > **[SCREENSHOT PENDING: E3T4S4 | Container App Revisions and replicas page with the new revision running | source: capture]**

1. Note how to roll back to the previous revision, and how long the full cycle took. The deploy script prints **Build took** and **full cycle**; record both in **Lab notes.txt** next to **Redeploy**. To roll back, you would run:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Rollback
   ```

   It creates a new revision from the previous revision's image and settings with `az containerapp revision copy`, and waits until it is healthy, in about a minute because nothing is built. Don't run it now; record the command in your notes.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Changed MCP server redeployed" is registered (validation-scripts/README.md). -->

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **Git reports *dubious ownership* in `C:\LabFiles\mcp-server`:** contact support; provisioning registers the folder for every user on the VM.
- **The agent asks for consent again:** select **Open consent** and accept; the consent lasts until the token can no longer be refreshed.
- **`Show-McpServerLog.ps1` shows no rows:** the log stream shows the latest revision's recent lines only. Call a tool again, then rerun the script, or raise `-Tail` to 300.
- **`Deploy-McpServer.ps1` times out waiting for the revision:** the new image probably failed to start; the previous revision keeps serving traffic. Run `.\scripts\Show-McpServerLog.ps1 -All`, fix the error it shows (usually indentation in the file you edited), and run the deploy script again. Each run creates a revision with a new name, so you can reuse the same `-Tag`.

</details>

## Summary

In this exercise, you have completed the following:

- Opened your team's copy of the MCP server, already cloned on the VM, and read its tool catalogue with input and output schemas
- Traced get_ticket from its tool definition to its Dataverse Web API query, and saw it run on behalf of the signed-in user
- Recorded the permission each read tool needs for Exercise 5
- Called a read tool from the agent, checked the record in the app, and found the call in the tool invocation log by its correlation identifier
- Tested a nonexistent ID and missing and malformed arguments, and saw structured errors
- Changed the server, rebuilt it in Azure Container Registry, deployed a new revision, timed the cycle, and noted how to roll back

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
