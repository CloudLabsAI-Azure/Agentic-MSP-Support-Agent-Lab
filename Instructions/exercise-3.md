# Exercise 3: Using the MCP Read Tools

### Estimated Duration: 35 minutes

## Scenario

"What exactly can the agent read from the Service Desk, and what happens when a call fails?" Relecloud's platform engineering lead asks it before anyone builds on the tool layer. The index you built in Exercise 1 is a snapshot: everything live, from the 60 open tickets to the 2 new incidents that arrived this morning, reaches the agent only through the MCP server's read tools. The earlier automation pilot was stopped after an internal note about an invoice dispute appeared in a reply to a customer, so the lead wants to know, tool by tool, what each one returns, which Dataverse query it runs and with whose permissions, and what the agent gets when the input is wrong or the record doesn't exist. In this exercise you answer from the code and the logs: you trace a tool to the request it sends, call it through the agent and find the call in the log, make it fail on purpose, and ship a change to your own server through the edit, build and deploy path you use for the rest of the lab.

## Overview

In this exercise, you open the MCP server's source on your lab VM, list its 16 read tools with their descriptions, input schemas and output schemas, and trace `get_ticket` from its definition to the Dataverse Web API request it sends on your behalf. You call it through `msp-support-agent`, check the result against the Service Desk app and find the call in the tool invocation log by its correlation ID. Then you make the tool fail with a ticket that doesn't exist and with a missing argument, and you change a tool description, build the image in Azure Container Registry, deploy a new revision and note how to roll back.

![One read tool call from msp-support-agent through API Management, which validates the token and adds the correlation ID, to the MCP server's read endpoint, which checks the input schema, and on to the Dataverse Web API on behalf of the signed-in technician; a call with no ticket_number stops at the schema with INVALID_ARGUMENT, a call for TCK-99999 returns TICKET_NOT_FOUND, and a lower lane loops from editing the source to az acr build, a new revision serving 3.0.1 and an optional rollback](./media/exercise-3-mcp-read-path.png)

How to read this diagram: the four cards across the top are the hops of one read tool call, from left to right. `msp-support-agent` calls `get_ticket` on its **servicedesk-read** connection, with no approval; API Management validates your token and adds `x-correlation-id`; the MCP server's read endpoint, `/read/mcp` in Azure Container Apps, checks the arguments against the tool's input schema; and the Dataverse Web API runs the query on behalf of the signed-in technician. Requests travel along the upper arrows and results come back along the lower ones, and the chip under API Management shows the correlation ID of the call in flight. Three calls play in turn. The first succeeds, and the panel **What the agent receives** shows `ok` true, the ticket and its `correlation_id`. The second has no `ticket_number`: the MCP server rejects it against the input schema with `INVALID_ARGUMENT`, and nothing reaches Dataverse. The third asks for TCK-99999: Dataverse has no such ticket, and the agent receives `TICKET_NOT_FOUND`. Both errors arrive as the same kind of JSON, with a code, a message and the correlation ID and no stack trace; the panel shortens their messages. The lower lane, labeled Task 3.4, is Task 4 of this exercise and plays at the same time: edit the source in Visual Studio Code, build the image `mcp-server:3.0.1` with `az acr build`, and let a new revision of your Container App serve 3.0.1 and report it on `/health`. The last box, **Roll back if needed**, has a dashed border because you only note how to run `az containerapp revision copy` from the previous revision, and the arrow back to the start shows that every change goes round the same loop.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Review the MCP Server on Your Lab VM
- Task 2: Call an Existing Read Tool
- Task 3: Test Tool Error Handling
- Task 4: Redeploy Your Copy of the MCP Server

## Task 1: Review the MCP Server on Your Lab VM

In this task, you will read the server your agent calls, from its tool catalog down to the Dataverse request one tool sends, and note the permission each read tool needs.

1. Open the MCP server repository already cloned on your lab VM in Visual Studio Code. The MCP server source is already cloned on your lab VM from a Spektra-managed private repository. No GitHub account is required: provisioning placed release `v3.0.0` in `C:\LabFiles\mcp-server` as a local Git repository. On the desktop, double-click **MCP server (VS Code)**. If Visual Studio Code asks whether you trust the authors of the files in this folder, select **Yes, I trust the authors**. Then select **Terminal** > **New Terminal**: the terminal opens in PowerShell 7, in `C:\LabFiles\mcp-server`. Run the following command, which shows the commit you're on and where it came from:

   ```powershell
   git log --oneline --decorate -1; git remote -v
   ```

   The repository holds one commit, *Relecloud Service Desk MCP server v3.0.0*, on the branch `main` with the tag `v3.0.0`: the release your Container App runs. The `origin` remote names the private repository on GitHub for reference only; the VM holds no credentials for it, and you never pull or push. In the **Explorer**, `src\servicedesk_mcp` is the server, `tests` its test suite, and `scripts` the call, log and deploy scripts you use in this exercise, next to `README.md` and `TOOLS.md`.

   > **[SCREENSHOT PENDING: E3T1S1 | Visual Studio Code with C:\LabFiles\mcp-server in the Explorer and the terminal showing the v3.0.0 commit | source: capture]**

1. Read the tool catalog and list the read tools, their descriptions, input schemas and output schemas. Start with what the server itself publishes. Run the following command, which asks your MCP server for its tool list (the MCP `tools/list` request) through the API Management diagnostics API:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List
   ```

   The first line reads *Connected to Relecloud Service Desk (diagnostics) 3.0.0*. The table lists 23 tools: 16 with **Kind** `read`, **Endpoint** `/read/mcp` and **Approval** `not required`, then 7 with **Kind** `write`, **Endpoint** `/write/mcp` and **Approval** `required`. **Required** shows each tool's required arguments, and **Summary** is the first line of its description. The 16 read tools are everything the agent can read:

   | Scenario | Read tools |
   |---|---|
   | Customer | `get_customer`, `search_customers`, `get_customer_contacts` |
   | Ticket | `search_tickets`, `get_ticket`, `get_open_tickets`, `get_ticket_history` |
   | Knowledge | `search_kb_articles`, `get_kb_article` |
   | SLA | `get_sla_status` |
   | Assignment | `get_assignment`, `list_technicians` |
   | Historical incidents | `get_similar_tickets` |
   | Communication | `get_ticket_notes` |
   | Customer documents | `search_customer_documents`, `get_customer_document` |

   > **[SCREENSHOT PENDING: E3T1S2 | Invoke-McpTool.ps1 -List output with 16 read tools on /read/mcp, approval not required, and 7 write tools on /write/mcp, approval required | source: capture]**

   Then read where that list comes from. In the **Explorer**, open these three files, and use **Ctrl+F** to find the names in the second column:

   | File | Find | What it tells you |
   |---|---|---|
   | `TOOLS.md` | **The catalog at a glance**, then **Read tools** > **`get_ticket`** | Each tool's full description, its input table, its output fields, the Dataverse calls it makes, its permission and its errors. `get_ticket` takes one required string, `ticket_number`, with the pattern `^TCK-\d{5}$`, and returns `ticket` with its title, description, customer, requester, status, priority, category, subcategory, product, technician, related article, tags, escalation, resolution and SLA figures |
   | `src\servicedesk_mcp\catalogue.py` | `ENDPOINT_KINDS`, `read_tool`, `_decorator` | The three endpoints: `/read/mcp` serves read tools only, `/write/mcp` write tools only, and `/mcp` every tool, for the diagnostics API. `@catalogue.read_tool(...)` publishes a function on the read endpoint and the diagnostics endpoint, with its docstring as the description, its type hints as the input schema, `readOnlyHint` set to true, and a `_meta` block that names its kind, approval, endpoint and permission |
   | `src\servicedesk_mcp\schemas.py` | `result`, `GET_TICKET` | The output schemas, written by hand. Every result shares one envelope: `ok` and `correlation_id` always, `error` only when `ok` is false, `note` and `warnings` when they apply, and the tool's own fields, for `get_ticket` the object `ticket`. No property allows null or more than one type, because Microsoft Foundry rejects such schemas, so a value that isn't known is left out |

   `ServiceDeskMCPServer.list_tools` in `catalogue.py` attaches these output schemas to the tool list, so whoever lists the tools, including Foundry Agent Service for your agent, receives each tool's description, input schema and output schema from the server itself. The per-tool sections of `TOOLS.md` are generated from that same list.

1. Trace one tool through the source to the Dataverse Web API query it issues. Trace `get_ticket`, the tool you already used in Exercises 1 and 2. Use **Ctrl+F** to find each name below:

   - **`get_ticket`** in `src\servicedesk_mcp\tools_read.py`, inside `register()`: the decorator `@catalogue.read_tool(permission="Read on spk_ticket, account, contact, spk_technician, spk_knowledgearticle", output=schemas.GET_TICKET)` publishes it. Its docstring is the description the agent reads, and its one argument, `ticket_number: TicketNumber`, is defined at the top of the file as a string with the pattern `^TCK-\d{5}$`. The function calls `load_ticket`, then passes the description through `protect`, the Microsoft Purview check you meet in Exercise 6.
   - **`load_ticket`** in the same file: calls `repo.get_ticket(ticket_number)`. When the repository returns nothing, it raises `not_found("ticket", ...)`, the `TICKET_NOT_FOUND` error you trigger in Task 3.
   - **`build_repository`** in `server.py`: `repo` follows the contract in `repository.py`, and in Azure, where `DATA_BACKEND` is `dataverse`, it is a `DataverseRepository`. The tests and local runs use `FixtureRepository` on the seed data instead.
   - **`DataverseRepository.get_ticket`** in `dataverse_repository.py`: looks the ticket up by its alternate key, the ticket number, with the columns in `TICKET_SELECT` and the related records in `TICKET_EXPAND`, and with `allow_404=True`, so a ticket that doesn't exist comes back as nothing instead of an exception.
   - **`_request`** in the same file: sends every Web API call. It adds a bearer token for your Dataverse environment from the Container App's managed identity, the header `CallerObjectId` with the signed-in user's Microsoft Entra object ID, and `x-ms-client-request-id` with the request's correlation ID, and it records the call, its HTTP status and Dataverse's request ID for the log line.

   Put together, and shown before URL encoding, `get_ticket` for TCK-10524 sends this one request to your environment, <inject key="Dataverse Environment URL" enableCopy="false"/>:

   ```http
   GET /api/data/v9.2/spk_tickets(spk_ticketnumber='TCK-10524')?$select=spk_ticketid,spk_ticketnumber,spk_name,spk_description,spk_category,spk_subcategory,spk_priority,spk_status,spk_product,spk_productversion,spk_affectedusers,spk_channel,spk_openedon,spk_resolvedon,spk_resolutionsummary,spk_outcome,spk_tags,spk_slatargethours,spk_slaelapsedhours,spk_slaremaininghours,spk_sladueon,spk_slastatus,spk_slacalculatedon,spk_isescalated,spk_escalationlevel,spk_escalatedon,spk_escalationreason,spk_correlationid&$expand=spk_CustomerId($select=accountid,name,spk_customercode,spk_slatier,spk_contracttype),spk_ContactId($select=contactid,fullname),spk_AssignedTechnicianId($select=spk_technicianid,spk_techniciancode,spk_name),spk_RelatedArticleId($select=spk_knowledgearticleid,spk_articlenumber,spk_name)
   Authorization: Bearer <token of the MCP server's managed identity for your Dataverse environment>
   CallerObjectId: <your Microsoft Entra object ID>
   x-ms-client-request-id: <the call's correlation ID>
   Consistency: Strong
   Accept: application/json
   OData-MaxVersion: 4.0
   OData-Version: 4.0
   If-None-Match: null
   ```

   There is no `$filter`: the alternate key addresses exactly one row of the entity set `spk_tickets`, `$select` limits it to 28 columns, and `$expand` brings the customer, the requester, the assigned technician and the related article in the same request. `CallerObjectId` makes the request run on your behalf: Dataverse allows the read only when both your security role and the role of the server's application user grant it. Your object ID reaches the server in the `x-user-oid` header that API Management sets from the token it validated (see **How it fits together** in `README.md`); the server never sees your token. The diagnostics API carries no user, so `meta_from_headers` in `telemetry.py` ignores user headers on that endpoint, and the same request goes without `CallerObjectId`, as the application user alone. In **Lab notes.txt**, next to **Tool you traced to its Dataverse query**, record **get_ticket: GET spk_tickets(spk_ticketnumber='TCK-...') with $select and $expand (customer, requester, technician, article), on my behalf through CallerObjectId**.

   > **[SCREENSHOT PENDING: E3T1S3 | dataverse_repository.py in Visual Studio Code with DataverseRepository.get_ticket and the CallerObjectId line in _request | source: capture]**

1. Note which permission each tool requires, ready for Exercise 5. Each tool publishes its permission in `_meta` as `relecloud/permission`, the same text as the **Permission** line of its section in `TOOLS.md`. Run the following command, which prints the permission of every read tool from the server's own tool list and copies the 16 lines to the clipboard:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List -Raw | Where-Object { $_._meta.'relecloud/kind' -eq 'read' } | ForEach-Object { '{0}: {1}' -f $_.name, $_._meta.'relecloud/permission' } | Set-Clipboard -PassThru
   ```

   Every read tool needs **Read** privileges only, on the tables it touches. For example, `get_ticket` needs *Read on spk_ticket, account, contact, spk_technician, spk_knowledgearticle*, `get_sla_status` needs *Read on spk_ticket, account, spk_slapolicy*, and `get_customer_contacts` needs *Read on account, contact (column security applies)*. These are Dataverse table privileges, and both identities must hold them for a call on your behalf: your own security role, and the MCP server's application user, which holds them through its **Service Desk Agent Read** role. Column security can still withhold single columns: the contact phone columns are secured from the start, so the server never receives a phone number, and `get_ticket_notes` returns internal notes only when a technician asks for them. In **Lab notes.txt**, next to **Permission each read tool needs (for Exercise 5)**, press **Ctrl+V** to paste the 16 lines.

   > **[SCREENSHOT PENDING: E3T1S4 | Terminal with the 16 read tools and the relecloud/permission text of each | source: capture]**

   > **Note:** The seven write tools publish their permission the same way, with Write, Create, Append and Append To privileges; you use them in Exercise 4. If the command can't reach the gateway, the **Permission** line of each tool's section in `TOOLS.md` holds the same text.

### Expected results

- [ ] Visual Studio Code shows `C:\LabFiles\mcp-server` on the `v3.0.0` commit, and its terminal runs PowerShell 7
- [ ] `Invoke-McpTool.ps1 -List` listed 16 read tools on `/read/mcp` with approval not required, and 7 write tools on `/write/mcp` with approval required
- [ ] You can say where a tool's description (its docstring), input schema (its type hints) and output schema (`schemas.py`) come from
- [ ] You traced `get_ticket` to `GET spk_tickets(spk_ticketnumber='...')` with `CallerObjectId`, and recorded it in **Lab notes.txt**
- [ ] **Lab notes.txt** holds the permission of each of the 16 read tools

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `Invoke-McpTool.ps1` stops with *Could not read the diagnostics subscription key. Run 'az login' and try again.* | Your Azure CLI sign-in expired | Run `az login`, sign in as the Senior Technician, and run the command again |
| PowerShell says the term `.\scripts\Invoke-McpTool.ps1` is not recognized | The terminal isn't in `C:\LabFiles\mcp-server`, for example a PowerShell 7 window you opened elsewhere | Use the Visual Studio Code terminal of the **MCP server (VS Code)** window, or run `Set-Location C:\LabFiles\mcp-server` first |
| `git` reports *detected dubious ownership* in `C:\LabFiles\mcp-server` | Provisioning didn't register the folder for your account | Contact support with your Deployment ID: <inject key="DeploymentID" enableCopy="true"/> |

## Task 2: Call an Existing Read Tool

In this task, you will confirm that the tool layer reaches real data in your own environment: you call a read tool through the agent, check the result against the Service Desk app, and find the call in the server's log.

1. Invoke a read tool from your agent with a valid argument. Make the call through the agent: only then does it pass the read gateway with your own token, which the **Validate** step for this task looks for. The diagnostics API you used in Task 1 carries no user. On the desktop, double-click **Microsoft Foundry**, select your project **<inject key="Foundry Project Name" enableCopy="false"/>**, select **Build**, and then select **msp-support-agent**. On the **Playground** tab, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Use the get_ticket tool to read ticket TCK-10524. Show its title, customer, requester, status, priority, category, subcategory, assigned technician, channel and number of affected users, then its SLA target, elapsed and remaining business hours, SLA status, due time and the time the SLA figures were calculated. End with the correlation ID of the tool call.
   ```

   **Expected Output:** the agent calls `get_ticket` on **servicedesk-read**, with no approval request, and answers: **TCK-10524**, *Claims team cannot open policy documents*; customer **Humongous Insurance** (**CUST-013**), **Platinum**, **Fully Managed**; requester **Kofi Kim**; status **In Progress**; priority **P2 High**; category **Line-of-Business App** and subcategory **Certificate**; assigned technician **Daniel Cho (TECH-06)**; channel **Phone**; **25** affected users. The SLA target is **8.0** business hours, with **7.0** elapsed and **1.0** remaining, status **At Risk**, due at 15:00 UTC and calculated at 14:00 UTC on the same day. The answer ends with the call's `correlation_id`, a GUID.

   **What this validates:** the read tool reaches the live Dataverse record through API Management and the MCP server, as you, and returns a result the agent can quote field by field.

   > **[SCREENSHOT PENDING: E3T2S1 | Playground answer for TCK-10524 with its fields, its SLA figures and the correlation ID of the get_ticket call | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Note:** The agent may also call `get_sla_status` for the SLA figures; it's a read tool too. If the answer gives two correlation IDs, keep the one for `get_ticket`. If the chat shows **Open Consent**, select it, sign in as <inject key="AzureAdUserEmail" enableCopy="false"/>, close the confirmation tab, and send the prompt again if the agent doesn't continue on its own.

1. Confirm the data returned matches the same record in the Service Desk app. On the desktop, double-click **Service Desk**, select **Work** > **Tickets**, and select the **Open Tickets by SLA Remaining** view: **TCK-10524** is its fourth row. Open it and compare the form with the agent's answer, field by field:

   | Form section | Field | Value |
   |---|---|---|
   | **Summary** | **Customer** | Humongous Insurance |
   | **Summary** | **Requester** | Kofi Kim |
   | **Summary** | **Status** | In Progress |
   | **Summary** | **Priority** | P2 High |
   | **Summary** | **Category** and **Subcategory** | Line-of-Business App, Certificate |
   | **Summary** | **Assigned Technician** | Daniel Cho |
   | **Summary** | **Channel** and **Affected Users** | Phone, 25 |
   | **SLA** | **Opened On (UTC)** | 5:00 PM on the day before the figures were calculated |
   | **SLA** | **SLA Target (business hours)**, **SLA Elapsed (business hours)** and **SLA Remaining (business hours)** | 8.00, 7.00 and 1.00 |
   | **SLA** | **SLA Due On (UTC)** and **SLA Calculated On (UTC)** | 3:00 PM and 2:00 PM (14:00), on the same day |
   | **SLA** | **SLA Status** | At Risk |
   | **Traceability** | **Last Correlation ID** | Empty |

   Every value the agent quoted is on the record. The elapsed hours count business hours only: one from 5:00 PM to 6:00 PM on the first day and six from 8:00 AM to 2:00 PM on the next, 7.0 in all. **Last Correlation ID** stays empty because a read changes nothing; only a write to a ticket field records its correlation ID there, as you see in Exercise 4.

   > **[SCREENSHOT PENDING: E3T2S2 | TCK-10524 in the Service Desk app with the Summary and SLA sections matching the agent's answer | source: capture]**

1. Find the call in the tool invocation log and note the correlation identifier recorded with it. The MCP server writes one JSON line per tool call. In the Visual Studio Code terminal, run the following command, which reads the newest 50 lines of your Container App's live console log and shows one row per tool call, newest last:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -Tail 50
   ```

   The newest **get_ticket** row shows **Endpoint** `read`, **Outcome** `ok`, **Authorization** `Allowed`, **DecidedBy** `dataverse`, **User** <inject key="AzureAdUserEmail" enableCopy="false"/> and, under **CorrelationId**, the GUID the agent gave you. Run the following command, with that ID in place of `<correlation ID>`, to see the whole line:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -CorrelationId <correlation ID> -Detail
   ```

   The line records `gateway_api` `servicedesk-read`, `caller` `agent` and `correlation_source` `gateway`; your object ID and account under `user`; under `agent`, the Agent ID you recorded in Exercise 1; `arguments` with `ticket_number` **TCK-10524**; and `authorization` with `acting_as` `user`. The first entry of `backend_calls` is the request you traced in Task 1: `system` `dataverse`, `method` `GET`, `entity_set` `spk_tickets`, `path` `spk_tickets(spk_ticketnumber='TCK-10524')`, `status` `200`, Dataverse's `request_id` and `on_behalf_of_user` `true`. When Microsoft Purview checks are on, the Microsoft Graph calls that checked the description follow it.

   > **[SCREENSHOT PENDING: E3T2S3-1 | Show-McpServerLog.ps1 row for get_ticket with read, ok, Allowed, dataverse, the Senior Technician and the correlation ID | source: capture]**

   The same line reaches Log Analytics a few minutes later, and that copy is what the **Validate** button reads. In the Azure portal, search for **Log Analytics workspaces**, open **<inject key="Log Analytics Workspace" enableCopy="false"/>**, and select **Logs**. If the editor opens in **Simple mode**, select **KQL mode** in the dropdown at the top right of the query editor. Paste the following query, which lists the `get_ticket` calls of the last two hours from the MCP server's log, and select **Run**:

   ```kql
   ContainerAppConsoleLogs
   | where TimeGenerated > ago(2h) and ContainerAppName startswith "ca-mcp-"
   | extend entry = parse_json(Log)
   | where tostring(entry.event) == "tool_call" and tostring(entry.tool) == "get_ticket"
   | project TimeGenerated, endpoint = tostring(entry.endpoint), user = tostring(entry.user.upn),
             ticket = tostring(entry.arguments.ticket_number), outcome = tostring(entry.outcome),
             authorization = tostring(entry.authorization.result), correlation_id = tostring(entry.correlation_id)
   | order by TimeGenerated desc
   ```

   The newest row is your call: **endpoint** `read`, your account, **TCK-10524**, `ok`, `Allowed` and the same **correlation_id**. Older rows for TCK-10524 on the `diagnostics` endpoint, with no user, are the readiness check and your Exercise 1 call through the diagnostics API; they ran as the server's application user and don't count for validation. In **Lab notes.txt**, next to **Read tool call: ticket and correlation ID**, record **TCK-10524** and the ID.

   > **[SCREENSHOT PENDING: E3T2S3-2 | Log Analytics result of the query with the get_ticket row for TCK-10524 on the read endpoint and its correlation ID | source: capture]**

   > **Note:** The live log shows a call within seconds. Log Analytics receives the same lines several minutes later; Azure Monitor resource logs typically arrive in 3 to 10 minutes. If the query returns no row for your call yet, wait a few minutes and select **Run** again.

### Expected results

- [ ] The agent read **TCK-10524** with `get_ticket`, without an approval request, and quoted the fields and SLA figures above with a correlation ID
- [ ] The Service Desk app shows the same values on TCK-10524, and **Last Correlation ID** is empty
- [ ] `Show-McpServerLog.ps1` showed the call on the `read` endpoint with your account, **Allowed** by `dataverse`, and a backend `GET` on `spk_tickets` with `on_behalf_of_user` `true`
- [ ] The Log Analytics query returned the same call, and you recorded TCK-10524 and its correlation ID in **Lab notes.txt**

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The agent answers without calling the tool, or gives figures but no correlation ID | It answered from the knowledge index, which holds a snapshot of TCK-10524 | In the same chat, send `Call get_ticket for TCK-10524 now and give me the correlation ID from its result.` |
| The chat shows **Open Consent**, or the call fails with a sign-in or authorization error | Your sign-in to the **servicedesk-read** connection needs renewing, or the browser is signed in with another account | Select **Open Consent**, sign in as <inject key="AzureAdUserEmail" enableCopy="false"/>, and send the prompt again |
| `Show-McpServerLog.ps1` says *No matching calls in the recent log. Call a tool, then run this again.* | The call is older than the last 50 console lines | Run it again with `-Tail 300`, or with `-LogAnalytics` once the line has reached Log Analytics |
| Validation fails right after you finish the task | The log line reaches Log Analytics a few minutes after the call | Wait two or three minutes and validate again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 3: Test Tool Error Handling

In this task, you will make the tool fail on purpose, twice, and check exactly what the agent receives. How a tool fails matters more to an agent than how it succeeds: a vague failure invites the model to fill the gap with something plausible.

1. Call the tool with a record identifier that does not exist. In the playground, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Use get_ticket to read ticket TCK-99999 and give me its status and priority.
   ```

   **Expected Output:** the agent says that no ticket TCK-99999 exists in the Service Desk, gives no status or priority, and suggests checking the number or searching for the ticket. It may name the error code, `TICKET_NOT_FOUND`.

   **What this validates:** the tool reports a missing record as a clear, final answer, and the agent passes it on instead of making up a ticket.

   > **[SCREENSHOT PENDING: E3T3S1 | Playground answer saying that ticket TCK-99999 does not exist, with no status or priority | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   The call took the path you traced in Task 1: Dataverse answered the alternate-key lookup with HTTP 404, `DataverseRepository.get_ticket` returned nothing because of `allow_404=True`, and `load_ticket` raised `TICKET_NOT_FOUND`.

1. Call it again with a required argument missing. The agent's model writes a tool's arguments itself, so you can't make it leave one out the way a script can. Send that call directly first. In the Visual Studio Code terminal, run the following command, which calls `get_ticket` with no arguments through the diagnostics API, where a read tool runs as the server's application user, without a signed-in user:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_ticket @{}
   ```

   The script prints *isError: True* with the call's correlation ID, followed by the result exactly as the server returns it:

   ```json
   {
     "ok": false,
     "error": {
       "code": "INVALID_ARGUMENT",
       "message": "get_ticket: 'ticket_number' is not valid: Field required.",
       "source": "input validation",
       "retryable": false,
       "hint": "Correct the arguments and call the tool again. The tool's input schema lists the allowed values.",
       "details": {
         "violations": [
           {
             "argument": "ticket_number",
             "problem": "Field required"
           }
         ]
       }
     },
     "correlation_id": "<the call's correlation ID>"
   }
   ```

   The server checked the arguments against the input schema before the tool ran: `ServiceDeskMCPServer.call_tool` in `catalogue.py` hands the violation to `refuse_invalid`, which answers with `INVALID_ARGUMENT`, so nothing reached Dataverse.

   > **[SCREENSHOT PENDING: E3T3S2-1 | Terminal with the INVALID_ARGUMENT result of get_ticket called with no arguments, isError True | source: capture]**

   Then ask the agent. In the playground, in the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Call get_ticket again, this time with no ticket number at all, and show me exactly what the tool returns.
   ```

   **Expected Output:** one of two correct answers. Either the agent sends the call without a valid `ticket_number` and reports the `INVALID_ARGUMENT` error, which names `ticket_number`, or it doesn't send the call and asks you which ticket you mean. Either way, it doesn't pick a ticket number of its own.

   **What this validates:** a call that breaks the input schema is refused before it reaches Dataverse, and the agent either reports the refusal or asks for the missing value.

   > **[SCREENSHOT PENDING: E3T3S2-2 | Playground answer reporting INVALID_ARGUMENT for ticket_number, or asking which ticket to read | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Confirm the agent receives a structured, readable error rather than a raw exception or stack trace. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Show me, as JSON, the exact result the get_ticket tool returned for TCK-99999, with every field.
   ```

   **Expected Output:** the same envelope as the error in step 2, with these values and the correlation ID of the step 1 call:

   ```json
   {
     "ok": false,
     "error": {
       "code": "TICKET_NOT_FOUND",
       "message": "No ticket 'TCK-99999' exists in the Service Desk.",
       "source": "mcp-server",
       "retryable": false,
       "hint": "Check the number with the user, or use search_tickets."
     },
     "correlation_id": "<the call's correlation ID>"
   }
   ```

   **What this validates:** the agent received a stable code it can act on, a message in plain language, the layer that decided, whether a retry can help, a hint for the next step and the correlation ID, and no exception text or stack trace.

   > **[SCREENSHOT PENDING: E3T3S3-1 | Playground answer with the TICKET_NOT_FOUND result as JSON, with code, message, source, retryable, hint and correlation_id | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   Then check what the server recorded for each failure. In the terminal, run the following command, which shows the recent `get_ticket` calls:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -Tool get_ticket -Tail 100
   ```

   Besides your Task 2 call, which shows `ok`, the newest rows are your failures:

   | Call | Endpoint | Outcome | ErrorCode | Authorization | DecidedBy | User |
   |---|---|---|---|---|---|---|
   | The agent's call for TCK-99999 | `read` | `error` | `TICKET_NOT_FOUND` | `Allowed` | `dataverse` | Your account |
   | Your call with no arguments | `diagnostics` | `rejected` | `INVALID_ARGUMENT` | `Rejected by the MCP server` | `input validation` | Empty |
   | The agent's call without a ticket number, if it sent one | `read` | `rejected` | `INVALID_ARGUMENT` | `Rejected by the MCP server` | `input validation` | Your account |

   `Allowed` on the not-found row is correct: nothing refused the call, Dataverse let you read tickets and simply had no ticket with that number. The rejected rows were decided by input validation and never called Dataverse; with `-CorrelationId` and `-Detail` you would see an empty `backend_calls` and the violation under `record`. An unexpected failure inside the server would come back as `INTERNAL_ERROR` with the correlation ID, while its stack trace stays in the server log (`invoke` in `catalogue.py`). In **Lab notes.txt**, next to **Error codes the agent received**, record **TICKET_NOT_FOUND for TCK-99999; INVALID_ARGUMENT for get_ticket without ticket_number**, and whether the agent sent that call or asked you for the number.

   > **[SCREENSHOT PENDING: E3T3S3-2 | Show-McpServerLog.ps1 rows for the TICKET_NOT_FOUND call and the INVALID_ARGUMENT calls | source: capture]**

1. Confirm the agent either recovers or asks a clarifying question, rather than inventing a result. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   I probably mistyped the ticket number. Find Humongous Insurance's open ticket about the certificate warning in claims intake instead.
   ```

   **Expected Output:** the agent follows the error's hint and searches instead of guessing, for example with `search_tickets`, and finds **TCK-10524**, *Claims team cannot open policy documents* (Humongous Insurance, **In Progress**, **P2 High**). It doesn't claim that TCK-99999 exists. If its search returns more than one candidate, it asks you which one you mean; Humongous Insurance's only other open ticket, **TCK-10550**, *Admin rights request for claims analyst*, isn't about a certificate.

   **What this validates:** after a failure the agent recovers with another read tool or asks you, and every ticket it names is one the tools returned.

   > **[SCREENSHOT PENDING: E3T3S4 | Playground answer finding TCK-10524 through a search after the TCK-99999 error | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   If the agent asked you for the ticket number in step 2, you have already seen the other acceptable behavior: a clarifying question instead of a guess.

### Expected results

- [ ] For TCK-99999 the agent said the ticket doesn't exist and gave no status or priority
- [ ] `get_ticket` with no arguments returned `INVALID_ARGUMENT` with `details.violations` naming `ticket_number`, and the agent either reported that error or asked you for the number
- [ ] The agent showed the `TICKET_NOT_FOUND` result as JSON with its code, message, source, retryable flag, hint and correlation ID, and no stack trace
- [ ] The log shows the not-found call as `error` and `Allowed`, and every call without a ticket number as `rejected` by input validation
- [ ] After the failure, the agent found TCK-10524 by searching, or asked you, and you recorded the error codes in **Lab notes.txt**

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The agent describes a ticket TCK-99999, with a status or a priority | It answered without calling the tool | Select **New chat** and send the step 1 prompt again. If it invents a ticket again, record that next to **Error codes the agent received**: it's the failure this task looks for |
| `Invoke-McpTool.ps1` stops with *Could not read the diagnostics subscription key. Run 'az login' and try again.* | Your Azure CLI sign-in expired | Run `az login`, sign in as the Senior Technician, and run the command again |
| The JSON the agent shows has renamed or extra fields | The model reformatted the tool result | Ask it to copy the tool result unchanged. The log and your diagnostics call show the server's own JSON |
| In step 4 the agent can't find TCK-10524 | Its search used words the ticket doesn't contain | Ask: `Search the open tickets for the word certificate.` |

## Task 4: Redeploy Your Copy of the MCP Server

In this task, you will take one change from your VM all the way to the agent: edit a tool description, build the image in your registry, deploy a new revision and confirm the agent sees it. This is the edit, build and redeploy path you use for the rest of the lab. Allow time for the image build.

1. Make a small local change on your VM, for example improving a tool description or adding a log field. Improve the description of `get_sla_status`: it reports elapsed and remaining business hours but never says which hours those are, so a client that reads only the tool's description can't tell.

   - In the **Explorer**, open `src\servicedesk_mcp\tools_read.py`. Press **Ctrl+F**, search for `targets_for_tier shows what each priority would mean`, and press **Esc**: the cursor is on line 446, the last line of text in the `get_sla_status` docstring. Press **End**, then **Enter**; Visual Studio Code indents the new line to match. Paste this sentence:

     ```
     All SLA hours are business hours, Monday to Friday 08:00 to 18:00 UTC: nights and weekends don't count.
     ```

   - Open `src\servicedesk_mcp\__init__.py` and change its last line to the new version, which `/health`, every log line and the deploy script read:

     ```python
     __version__ = "3.0.1"
     ```

   - Press **Ctrl+S** in each file. Then run the following command, which shows exactly what you changed:

     ```powershell
     git --no-pager diff
     ```

     Two files changed: in `__init__.py`, `__version__ = "3.0.0"` became `__version__ = "3.0.1"`, and in `tools_read.py` your sentence is the one added line, marked `+`, just before the docstring's closing `"""`.

   - Run the following command, which checks that both files are still valid Python. It prints nothing when they are:

     ```powershell
     python -m py_compile .\src\servicedesk_mcp\tools_read.py .\src\servicedesk_mcp\__init__.py
     ```

   > **[SCREENSHOT PENDING: E3T4S1 | tools_read.py with the new sentence in the get_sla_status docstring, and the git diff output in the terminal | source: capture]**

   > **Note:** `C:\LabFiles` gives you the server's source and its tests, but no Python environment for them: the VM has Python 3.12 and no `.venv` for the server. Running the 107 tests is therefore optional in this task, because the first run downloads the dependencies and the suite takes a few minutes. To run them, in a second terminal run `python -m venv .venv`, then `.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt -c constraints.txt`, then `.\.venv\Scripts\python.exe -m pytest`; all 107 pass with this change. `.dockerignore` keeps `.venv` and `tests` out of the image.

1. Build the container image into your container registry. Run the following command, which builds the image from your working copy with Azure Container Registry Tasks, so no Docker is needed on the VM, and then deploys it and waits for it:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag 3.0.1
   ```

   The first stage prints this line, with your registry's name:

   ```text
   [1/3] Building <inject key="Container Registry Name" enableCopy="false"/>.azurecr.io/mcp-server:3.0.1 (version 3.0.1) in <inject key="Container Registry Name" enableCopy="false"/> with ACR Tasks...
   ```

   Check that it says **version 3.0.1**: the script reads the version from `__init__.py` on disk. `az acr build` then uploads your source, without what `.dockerignore` excludes, and streams the build log of the `Dockerfile`: the Azure Linux Python 3.12 base image from the Microsoft Container Registry, the pinned dependencies and the `src` folder. When the script moves on to the next stage, the image is in your registry. To see it, open a second terminal with **Terminal** > **New Terminal** and run the following command, which lists the image tags in your registry:

   ```powershell
   az acr repository show-tags --name <inject key="Container Registry Name" enableCopy="false"/> --repository mcp-server --output table
   ```

   It lists **3.0.0**, the release image that provisioning built, and **3.0.1**, yours.

   > **[SCREENSHOT PENDING: E3T4S2 | Deploy-McpServer.ps1 stage 1/3 with the build log, and az acr repository show-tags listing 3.0.0 and 3.0.1 | source: capture]**

   > **Note:** Microsoft documents no build time for an image like this one. Its smallest documented example, a one-line image, builds and pushes in about 10 seconds, and this build also installs the server's Python dependencies, so it takes longer. No time is documented for a new revision to become ready either. The script measures both for you and waits up to 10 minutes for the new revision (`-TimeoutSeconds 600`) before it gives up, so leave it running.

1. Deploy the new revision to your MCP server Container App. The same run continues on its own:

   ```text
   [2/3] Deploying a new revision of <inject key="Container App Name" enableCopy="false"/>...
   [3/3] Checking the new revision...
   Waiting for revision <inject key="Container App Name" enableCopy="false"/>--v3-0-1-<time stamp> to run and report version 3.0.1...
   ```

   Stage **[2/3]** runs `az containerapp update --image` with your image and a revision suffix made from the tag and the time, so every run creates a revision with a new name. Your app runs in single revision mode: the new revision starts beside the one serving traffic, traffic moves only when the new one is ready, and a revision that fails to start never takes traffic. Stage **[3/3]** checks the new revision every 10 seconds and prints its state, its share of the traffic, the version it reports and whether it is ready, until a line ends with **version 3.0.1, ready True**. The script then lists your latest revisions, with the new one active and serving 100 percent of the traffic, and ends with these two lines, your own times in place of `mm:ss`:

   ```text
   Build took mm:ss; full cycle mm:ss. <inject key="Container App Name" enableCopy="false"/> now serves <inject key="Container Registry Name" enableCopy="false"/>.azurecr.io/mcp-server:3.0.1.
   To roll back to the previous revision: .\scripts\Deploy-McpServer.ps1 -Rollback
   ```

   > **[SCREENSHOT PENDING: E3T4S3 | Deploy-McpServer.ps1 stages 2/3 and 3/3, the revision table, and the Build took and full cycle line | source: capture]**

1. Confirm the revision is running and that the change is visible to your agent. Run the following command, which reads the server's `/health` endpoint, the one path that needs no gateway key and returns no data:

   ```powershell
   Invoke-RestMethod <inject key="MCP Server URL" enableCopy="false"/>/health | Select-Object status, version, revision, gateway_key_source
   ```

   **status** is `ok`, **version** is `3.0.1`, **revision** is the new revision's name, and **gateway_key_source** is `key vault`: the new revision read its gateway key from Key Vault when it started, as the old one did. Then run the following command, which lists every revision of your app with whether it is active, its share of the traffic, its running state and its image:

   ```powershell
   az containerapp revision list --name <inject key="Container App Name" enableCopy="false"/> --resource-group <inject key="Resource Group Name" enableCopy="false"/> --all --query "[].{revision:name, active:properties.active, traffic:properties.trafficWeight, state:properties.runningState, image:properties.template.containers[0].image}" --output table
   ```

   Your revision is active, with 100 percent of the traffic and the image `mcp-server:3.0.1`. The `baseline-` revision that provisioning created with `mcp-server:3.0.0` is now inactive, as is the placeholder revision the template created first. Now check what the server publishes. Run the following command, which prints the full description of `get_sla_status` from the running server's tool list:

   ```powershell
   (.\scripts\Invoke-McpTool.ps1 -List -Raw | Where-Object name -eq 'get_sla_status').description
   ```

   The first line reads *Connected to Relecloud Service Desk (diagnostics) 3.0.1*, and the description ends with your sentence. Finally, check the agent. In the playground, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Quote the description of your get_sla_status tool word for word, exactly as your tool list gives it. Don't call the tool.
   ```

   **Expected Output:** the full description of `get_sla_status`, starting *Get a ticket's SLA status: the stored target, elapsed and remaining business hours, due time and status* and ending with your sentence, *All SLA hours are business hours, Monday to Friday 08:00 to 18:00 UTC: nights and weekends don't count.*

   **What this validates:** the agent gets its tool descriptions from the running server, so your change reached it with the new revision, without any change to the agent itself.

   > **[SCREENSHOT PENDING: E3T4S4 | Playground answer quoting the get_sla_status description that ends with the new business hours sentence | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Note:** In the Azure portal, the same revisions are listed under your Container App's **Revision management**. Some portal versions show the page as **Revisions and replicas** under **Application**.

1. Note how to roll back to the previous revision, and how long the full cycle took. Note it, but don't do it: Exercise 4 continues from your 3.0.1 code, this task's **Validate** step needs your revision serving, and the reviewers judge your environment as you leave it. The rollback is one command:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Rollback
   ```

   It builds nothing. It creates a new revision from the template of the revision before the one serving traffic, here the `baseline-` revision, with the same image `mcp-server:3.0.0` and the same settings, using `az containerapp revision copy --from-revision`. Then it waits until that revision runs and is healthy, and prints *Rollback took mm:ss*. If the copy fails, for example because the previous revision is no longer provisioned, the recovery table in `README.md` redeploys the release image without building: `.\scripts\Deploy-McpServer.ps1 -Tag 3.0.0 -NoBuild`. A rollback changes what runs, not your source: your 3.0.1 change stays in `C:\LabFiles\mcp-server`. In **Lab notes.txt**, next to **Redeploy: your change, the new revision, how long the cycle took, how to roll back**, record **get_sla_status description says SLA hours are business hours (3.0.1)**, your revision's name, the **Build took** and **full cycle** times, and **.\scripts\Deploy-McpServer.ps1 -Rollback (az containerapp revision copy from the baseline revision)**.

   > **Important:** Don't run the rollback. A rollback to the release image makes this task's validation fail, and Exercise 4 builds on your 3.0.1 code.

### Expected results

- [ ] `git --no-pager diff` shows your sentence in the `get_sla_status` docstring and `__version__ = "3.0.1"`, and `py_compile` printed nothing
- [ ] `Deploy-McpServer.ps1 -Tag 3.0.1` built `mcp-server:3.0.1` into your registry, and `az acr repository show-tags` lists **3.0.0** and **3.0.1**
- [ ] The script ended with *Build took ...; full cycle ...*, `/health` reports `ok`, `3.0.1` and the new revision, and your revision is active with 100 percent of the traffic
- [ ] The diagnostics API and the agent both give the new `get_sla_status` description
- [ ] You recorded the change, the revision, the times and the rollback command in **Lab notes.txt**, and didn't roll back

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The script stops with *mcp-server:3.0.0 is the release image that provisioning deployed...* | The tag resolved to the release tag, 3.0.0 | Run it with `-Tag 3.0.1`, after you check that `__init__.py` says `3.0.1` and is saved |
| Stage **[1/3]** says *(version 3.0.0)*, or `/health` still reports `3.0.0` after the run | `__init__.py` wasn't saved before the run | Save it, check it with `git --no-pager diff`, and run the same command again: every run creates a revision with a new name, so the same tag is fine |
| *az acr build failed (...). Nothing was deployed; the running revision is unchanged.* | The build couldn't start or a build step failed, often because the Azure CLI sign-in expired | Read the last lines of the build log, run `az login` if it asks you to sign in, and run the command again. If it fails twice, contact support with your Deployment ID |
| *Revision ... did not become ready within 600 seconds. Traffic stays on the previous revision.* | The new image doesn't start, usually because an edit broke the Python syntax | Run `.\scripts\Show-McpServerLog.ps1 -All` to read the startup error, fix the file (`git --no-pager diff` shows what changed), run the `py_compile` check, and deploy again with the same tag |
| The agent still quotes the old description | The chat started before the new revision served, or the agent answered from memory | Select **New chat** and ask again. When `/health` and the diagnostics API show 3.0.1, the server side is done |

> **Note:** Validate this task now, before anything else changes. The check reads the revision that serves traffic, its image tag and the version the server reports, so it passes while `mcp-server:3.0.1` serves and fails after a rollback to the release image.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Success Criteria

You have completed this exercise when:

- [ ] You can name the 16 read tools and where their descriptions, input schemas and output schemas come from, and you traced `get_ticket` to `GET spk_tickets(spk_ticketnumber='...')` with `CallerObjectId`
- [ ] The agent read **TCK-10524** through **servicedesk-read**, its values matched the Service Desk app, and the log line shows your account, the `read` endpoint, **Allowed** and the correlation ID you recorded
- [ ] **TCK-99999** came back as `TICKET_NOT_FOUND` and the call without `ticket_number` as `INVALID_ARGUMENT`, each with a code, a message, a source, a retry flag, a hint and a correlation ID
- [ ] **<inject key="Container App Name" enableCopy="false"/>** serves your revision from `mcp-server:3.0.1`, `/health` reports `3.0.1`, and the agent quotes the new `get_sla_status` description
- [ ] **Lab notes.txt** holds your five Exercise 3 values
- [ ] Negative check: no error reached the agent as an exception or a stack trace, the agent invented no ticket for TCK-99999 or for the missing number, and the calls without a ticket number show `rejected` by input validation, with no Dataverse call

## Apply It in Production

**What you built:**

- A read path you can account for line by line: 16 read tools, each with a description, an input schema, an output schema and the Dataverse privileges it needs, each running its one query on behalf of the signed-in technician.
- Failures an agent can act on: a stable code, the layer that decided, a retry flag, a hint and the correlation ID, one log line per call, and the stack trace kept out of the result.
- A redeploy loop with a way back: a versioned image built in your registry, a new revision that takes traffic only when it is ready, and a timed run you can repeat.

**Decisions to make before production:**

1. **Who builds images.** The lab builds from a workstation with `az acr build`. In production, build in a pipeline from a reviewed commit, run the test suite first, and promote the same image from test to production instead of rebuilding it.
1. **Descriptions are behavior.** The agent chooses a tool, and its arguments, from the descriptions and schemas. Review a description change like a code change, and test it with the agent before you release it.
1. **Revision strategy.** Single revision mode moves all traffic at once, when the new revision is ready. Multiple revision mode lets you split traffic and move it back without a new revision, at the cost of two active revisions that are both billed.
1. **Error contract.** Decide which codes are final (permission, data protection, not found) and which are retryable (throttling, an unavailable backend), and what each hint tells the agent to do. Keep the codes stable: agents, alerts and dashboards depend on them.

**Production checklist:**

- [ ] The test suite gates every image build, and a failed run blocks the deploy
- [ ] Image tags are versions that are never overwritten, and the last good tag stays in the registry for rollback
- [ ] `/health` reports the version and the revision, and startup and readiness probes gate traffic
- [ ] Alerts fire on a rise in `INVALID_ARGUMENT`, `DATAVERSE_*` or `INTERNAL_ERROR` in the tool invocation log
- [ ] A diagnostics path like this lab's, which runs as the server's application user, is closed or limited to operators
- [ ] The rollback is rehearsed and timed against your recovery target

**Common pitfalls:**

| Pitfall | How to avoid it |
|---|---|
| A failure reaches the agent as a raw exception or an empty result, and the model fills the gap with something plausible | Return a stable code with a hint and the correlation ID for every failure, and keep the stack trace in the server log under that ID |
| A redeploy that never becomes ready, noticed only when users complain | Probe a health endpoint that reports the version, and let the deploy succeed only when the new version answers |

## Knowledge Check

**Question 1:** The agent's call for TCK-99999 failed, yet its log line records the authorization result `Allowed`, decided by `dataverse`. Why isn't that a contradiction?

<details>
<summary>Show the answer</summary>

The authorization result records whether a layer refused the call, and none did. The server sent the lookup to Dataverse on your behalf, your role and the server's both allowed reading tickets, and Dataverse answered that no ticket has that key. That is an outcome, `error` with `TICKET_NOT_FOUND`, not a denial. A permission refusal comes back as `DATAVERSE_ACCESS_DENIED` with the result `Denied by Dataverse`, which you meet in Exercise 5.

</details>

**Question 2:** The call without a `ticket_number` left no Dataverse call in the log. Where was it stopped, and why does that matter?

<details>
<summary>Show the answer</summary>

In the MCP server, before the tool function ran: the arguments are checked against the tool's input schema, and `refuse_invalid` in `catalogue.py` answers with `INVALID_ARGUMENT` and the violation. A malformed request never turns into a Dataverse query, costs nothing downstream, and tells the agent exactly which argument to fix.

</details>

**Question 3:** You changed only a docstring, yet the agent saw the change only after a new revision was serving. Why, and what does that mean for a rollback?

<details>
<summary>Show the answer</summary>

The agent's definition names the MCP server, its connection and the allowed tool names, not their descriptions: the descriptions and schemas come from the server's tool list when the agent runs. A description ships inside the image like code, so it changes only with a new revision, and a rollback to the previous revision brings the old description back.

</details>

## Summary

In this exercise, you have completed the following:

- Opened the MCP server source on your lab VM, listed its 16 read tools from the server's own catalog, and found where each description, input schema and output schema is defined.
- Traced `get_ticket` to the one Dataverse Web API request it sends with `CallerObjectId`, and recorded the permission every read tool needs.
- Called `get_ticket` through the agent, matched TCK-10524 field by field in the Service Desk app, and found the call by its correlation ID in the live log and in Log Analytics.
- Made the tool fail with a ticket that doesn't exist and with a missing argument, and saw structured errors, a recovery by search, and no stack trace or invented result.
- Changed a tool description, built `mcp-server:3.0.1` in your registry, deployed a new revision that the agent uses, and noted the rollback and the cycle time.

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
