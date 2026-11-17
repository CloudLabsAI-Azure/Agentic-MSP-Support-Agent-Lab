# Exercise 4: Using the MCP Action Tools

### Estimated Duration: 50 minutes

## Scenario

"If we let the agent act, how do we stay in control of every change it makes?" Relecloud's head of service delivery asks it before the agent changes a single ticket, because the last attempt at automation ended badly: the earlier pilot was stopped after an internal note about an invoice dispute appeared in a reply to a customer. Until now the agent has only advised. In Exercise 2 it recommended a triage for TCK-10561, one of the 2 new incidents in a queue of 60 open tickets, and changed nothing. In this exercise it starts acting, and you stay in control at every step: you approve or decline each change with its tool and arguments in front of you, check every change in the Service Desk app and the tool invocation log, keep a customer reply apart from an internal note on a ticket whose internal notes include an invoice dispute, and let the agent triage the new incident from evidence it cites. Then you change the MCP server itself twice, tightening one tool's input boundary and adding a scoped tool of your own, so you can show how the tool catalog stays under Relecloud's control as it grows.

## Overview

In this exercise, you put the seven write tools on the MCP server's write endpoint to work through `msp-support-agent`, and every call waits for your approval in the playground. You approve a priority change on TCK-10544 and decline a status change on the same ticket, add a customer-visible reply and an internal note to TCK-10524 and check that a customer draft holds nothing from the internal notes, and chain the grounded triage of TCK-10561 into three approved writes. Then you lower the maximum `limit` of `get_open_tickets` from 50 to 20 and redeploy as version 3.0.2, and add an `escalate_ticket` tool and redeploy as version 3.0.3.

![msp-support-agent proposes update_ticket_priority on TCK-10544 on the servicedesk-write connection; after Approve the call passes API Management and the MCP server's write endpoint, TCK-10544 becomes P3 Medium with an audit note and an Agent Action row, a rejected call never reaches the server, a repeat within 10 minutes returns the first result, and on TCK-10524 a public reply and an internal note carry different internal flags](./media/exercise-4-approval-flow.png)

How to read this diagram: the top row follows one write from left to right. **msp-support-agent** proposes a write on the **servicedesk-write** connection, and the approval request card lists the server, the tool and the full arguments. Its example is the change you approve in Task 1: `update_ticket_priority` on TCK-10544 with priority 3 and a reason. Each call needs its own decision. After **Approve**, API Management validates the token and adds the correlation ID, the MCP server's write endpoint `/write/mcp` checks for a duplicate, TCK-10544 is updated to P3 Medium on behalf of the technician, and an internal audit note records what changed, why, for whom and the correlation ID. A row then appears in the **AGENT ACTION ROWS** panel with the outcome Succeeded. The red card under the approval request is the decline path, drawn as **Reject**: the tool is never called. In Task 1 you decline a status change on TCK-10544 this way, the ticket stays New, and the agent says the call was not approved. The animation then sends the same call again: the orange card is the duplicate guard, which returns the first result within 10 minutes and makes no second change, so the second row reads Duplicate, first result returned. The lane at the bottom left is Task 2 on TCK-10524: `add_public_reply` writes a note with the internal flag false, which the customer can read, and `add_internal_note` writes one with the internal flag true, for technicians only and never in a customer-facing reply. The key idea at the bottom sums it up: nothing changes until you approve, a rejected call never reaches the MCP server, and a repeat returns the first result instead of changing the ticket twice.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Call a Write Tool with Approval
- Task 2: Separate a Public Reply from an Internal Note
- Task 3: Chain Grounding into Action
- Task 4: Tighten a Tool Boundary
- Task 5: Design and Add a Scoped Tool

## Task 1: Call a Write Tool with Approval

In this task, you will reach the point at which the agent stops advising and starts acting. Write tools require approval before they run, so you approve one change, decline another, and check both against the records they leave.

1. Review the write tools available and what each one changes and confirm that each one requires approval. In Visual Studio Code (double-click **MCP server (VS Code)** on the desktop if it isn't open), open `TOOLS.md` and read **Write tools**. Each tool makes one kind of change, and its **Changes** line gives a sensitivity: `high` when a wrong call changes an SLA commitment, the ticket's status, or something the customer reads.

   | Tool | What it changes | Sensitivity |
   |---|---|---|
   | `update_ticket_status` | Status; on **Resolved** also the resolution summary, resolved time and final SLA status; optionally the outcome | high |
   | `update_ticket_priority` | Priority, with the SLA target, elapsed and remaining hours, due time and SLA status that follow from it | high |
   | `update_ticket_category` | Category and subcategory | medium |
   | `link_kb_article` | The related knowledge article (Published articles only) | medium |
   | `assign_ticket` | The assigned technician; a **New** ticket moves to **In Progress** | medium |
   | `add_internal_note` | Adds one internal note, visible to technicians only | medium |
   | `add_public_reply` | Adds one customer-visible reply that the customer will read | high |

   Every change to a ticket field also adds an internal audit note with the reason, and every write call that reaches the server, whatever its outcome, adds an **Agent Action** row in Dataverse. Then, in the Visual Studio Code terminal (if none is open, select **Terminal** > **New Terminal**; it opens in PowerShell 7 in `C:\LabFiles\mcp-server`), run the following command, which lists the catalog your MCP server publishes, with each tool's kind, endpoint and approval from its `_meta` block:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List
   ```

   The seven write tools show **Kind** `write`, **Endpoint** `/write/mcp` and **Approval** `required`; the 16 read tools show `/read/mcp` and `not required`. The `_meta` block describes a tool; the agent's connection enforces the approval. Run the following command, which reads the agent's tools from your Foundry project:

   ```powershell
   C:\LabFiles\tools\Get-AgentIdentity.ps1
   ```

   Under **Its tools (latest version)**, **servicedesk-read** shows the approval **never** with the scope **16 allowed tools**, and **servicedesk-write** shows **always** with **every tool the endpoint lists**. The write endpoint serves only write tools, so every write waits for your decision, including the tool you add in Task 5.

   > **[SCREENSHOT PENDING: E4T1S1-1 | Invoke-McpTool.ps1 -List output with the seven write tools showing Kind write, Endpoint /write/mcp and Approval required | source: capture]**

   > **[SCREENSHOT PENDING: E4T1S1-2 | Get-AgentIdentity.ps1 tools table with servicedesk-read approval never and servicedesk-write approval always for every tool the endpoint lists | source: capture]**

1. Through your agent, change a ticket's status or priority and approve the action when prompted. On the desktop, double-click **Microsoft Foundry**, select your project **<inject key="Foundry Project Name" enableCopy="false"/>**, select **Build**, and then select **msp-support-agent**. On the **Playground** tab, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Hiro Lambert at Contoso Pharmaceuticals says that one QA user is now blocked without the qa-releases shared mailbox requested in TCK-10544, and has no workaround. Raise TCK-10544 to P3 Medium under Relecloud's priority rules, and report the outcome with its correlation ID.
   ```

   **Expected Output:** the agent reads **TCK-10544**, *Shared mailbox for the QA team*, from **Contoso Pharmaceuticals** (status **New**, **P4 Low**), and says what it will change and why: Relecloud's rules make one user with no workaround a P3. Then the chat shows an approval request with the tool and its arguments. Check them, and select **Approve** only when they match:

   | Tool | Arguments to check before you approve |
   |---|---|
   | `update_ticket_priority` | `ticket_number` **TCK-10544**, `priority` **3**, and a `reason` that says one user is blocked with no workaround |

   After you approve, the agent reports the change from **P4 Low** to **P3 Medium** with a new SLA target of **16** business hours (Contoso Pharmaceuticals is a **Platinum** customer, and a Platinum P3 resolves in 16 business hours), the code of the internal audit note it added, and the `correlation_id`.

   > **Note:** **Approve** is a split button. Select the word **Approve** itself, which approves this one call. Don't use the arrow next to it: **Always approve this tool** and **Always approve all tools** turn approval off and save a new agent version, so later writes in this lab, and the checks in Exercises 5 and 6, run without an approval request. If you chose one by mistake, run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Reset` and then `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions`. The button to refuse a call is labelled **Deny**.

   **What this validates:** the change waits for your decision on its exact arguments, and runs only after you approve it.

   > **[SCREENSHOT PENDING: E4T1S2-1 | Playground approval request for update_ticket_priority with ticket_number TCK-10544, priority 3 and a reason | source: capture]**

   > **[SCREENSHOT PENDING: E4T1S2-2 | Agent's report of the change from P4 Low to P3 Medium with the 16-hour SLA target, the audit note and the correlation ID | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Note:** Your first write can show **Open Consent** instead of an approval request: write tools use their own connection, **servicedesk-write**, and you consent once per connection. Select **Open Consent**, sign in as <inject key="AzureAdUserEmail" enableCopy="false"/>, close the confirmation tab, and send the prompt again if the agent doesn't continue on its own. If the agent describes the change and asks you to confirm in the chat before it calls the tool, reply `Yes, go ahead.`

   > **Note:** The approval request shows the tool and its full arguments. Whether the playground also names the MCP server isn't documented, but the tool tells you the connection, because only **servicedesk-write** serves write tools. A request with no decision is never carried out. Approve this change once: Exercise 6 traces exactly this write.

   In **Lab notes.txt**, next to **Approved write: ticket, change and correlation ID (you trace it in Exercise 6)**, record **TCK-10544, priority P4 Low to P3 Medium** and the correlation ID the agent reported.

1. Repeat the request and decline the approval, then confirm nothing changed. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Now set TCK-10544 to In Progress: work on the mailbox has started.
   ```

   **Expected Output:** the agent proposes `update_ticket_status` with `ticket_number` **TCK-10544**, `status` **In Progress** and a reason. Decline this one: TCK-10544 has no assigned technician, so nobody has started work on it. Select the other choice beside **Approve**, the one that declines the call. Microsoft doesn't document its label, so look for the option that refuses or denies the request, and don't select **Approve**. The agent then says that the call was not approved and that TCK-10544 is unchanged, still **New**.

   **What this validates:** a declined call is never sent, so nothing changes, and the agent says so instead of reporting a result.

   > **[SCREENSHOT PENDING: E4T1S3 | Declined approval request for update_ticket_status on TCK-10544, and the agent saying the call was not approved and the ticket is unchanged | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   Confirm it in the Service Desk app: double-click **Service Desk** on the desktop if it isn't open, select **Work** > **Tickets**, and select the **Open Tickets** view. Select the **Ticket Number** column header, select **Filter by**, enter `TCK-10544`, and select **Apply**. Open **TCK-10544**: its **Status** is still **New**. In **Lab notes.txt**, next to **Declined write: ticket, and confirmed unchanged**, record **TCK-10544, status change to In Progress declined, Status still New**.

   > **Note:** A declined call never reaches API Management or the MCP server, so neither the gateway, the server's log, the Dataverse audit nor the Agent Action table records it. The only record of your decision is the conversation in Foundry; Exercise 6 shows where to find it.

1. Confirm the approved change in the Service Desk app and in the tool invocation log. On the **TCK-10544** form, check:

   - **Summary**: **Priority** is **P3 Medium** and **Status** is **New**.
   - **SLA**: **SLA Target (business hours)** is **16.00**, where it was 40.00.
   - **Traceability**: **Last Correlation ID** is the correlation ID you recorded, because the MCP server writes the ID of every ticket-field change on the ticket it changes.
   - **Related** > **Ticket Notes**: one note, by **Service desk agent (MCP)**, with **Internal Note** **Internal**. Open it: its **Body** reads *Priority changed by the service desk agent from P4 Low to P3 Medium. Reason:* followed by the agent's reason, *Requested by* your account *through msp-support-agent*, and *Correlation ID:* with the same ID.

   Then, under **Work**, select **Agent Actions**. The **All Agent Actions** view lists the newest rows first. The row **update_ticket_priority on TCK-10544: Succeeded** shows **Tool** `update_ticket_priority`, **Ticket Number** **TCK-10544**, your account as **User Name**, **Authorization** **Allowed**, **Outcome** **Succeeded** and the same **Correlation ID**. No row names `update_ticket_status`: the call you declined never reached the server.

   > **[SCREENSHOT PENDING: E4T1S4-1 | TCK-10544 form with Priority P3 Medium, Status New, SLA Target (business hours) 16.00 and the Last Correlation ID | source: capture]**

   > **[SCREENSHOT PENDING: E4T1S4-2 | All Agent Actions view with the update_ticket_priority row for TCK-10544, Allowed and Succeeded, and its correlation ID | source: capture]**

   Finally, in the Visual Studio Code terminal, run the following command, which reads the MCP server's tool invocation log (one JSON line per call) from your Container App's live log stream, and shows the calls of one tool:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -Tool update_ticket_priority
   ```

   One row: **Endpoint** `write`, **Tool** `update_ticket_priority`, **Outcome** `ok`, **Authorization** `Allowed`, **DecidedBy** `dataverse`, your account under **User**, and the same **CorrelationId**. Then run the following command, which looks for the status change you declined:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -Tool update_ticket_status
   ```

   It reports *No matching calls in the recent log*.

   > **[SCREENSHOT PENDING: E4T1S4-3 | Show-McpServerLog.ps1 output with the update_ticket_priority row, outcome ok and Allowed, and no update_ticket_status call | source: capture]**

   > **Note:** **SLA Elapsed (business hours)**, **SLA Remaining (business hours)**, **SLA Due On (UTC)**, **SLA Status** and **SLA Calculated On (UTC)** were recalculated from **Opened On (UTC)** at the moment of your change. They depend on when your environment was prepared, so they differ from other participants'; the target of 16 business hours is the same for everyone.

   > **Note:** The MCP server also guards against a change made twice. When the same user calls the same tool with the same arguments, reason included, within 10 minutes of a first call that succeeded, the server doesn't run it again: it returns the first result with `duplicate: true` and `duplicate_of`, which names the first call's correlation ID, adds no audit note and leaves **Last Correlation ID** as it is. That call's Agent Action row carries its own correlation ID and the outcome **Duplicate, first result returned**. A request with a different reason isn't identical and runs again. The guard keeps its memory in the running server, so a new revision starts with an empty guard.

### Expected results

- [ ] `Invoke-McpTool.ps1 -List` shows the seven write tools on `/write/mcp` with **Approval** `required`, and `Get-AgentIdentity.ps1` shows **servicedesk-write** with the approval **always**
- [ ] You approved `update_ticket_priority` on **TCK-10544** after checking its arguments, and the agent reported **P3 Medium**, a 16-hour SLA target and a correlation ID
- [ ] You declined `update_ticket_status`, the agent said the call wasn't approved, and **TCK-10544** is still **New**
- [ ] **TCK-10544** shows **P3 Medium**, **SLA Target (business hours)** **16.00**, one internal audit note and a **Last Correlation ID** that matches your note
- [ ] **All Agent Actions** and `Show-McpServerLog.ps1` show the `update_ticket_priority` call as **Allowed** and `ok`, and nothing for `update_ticket_status`
- [ ] You recorded the approved write and the declined write in **Lab notes.txt**

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The chat shows **Open Consent** instead of an approval request | You haven't consented to the **servicedesk-write** connection yet | Select **Open Consent**, sign in as <inject key="AzureAdUserEmail" enableCopy="false"/>, and send the prompt again |
| No approval request appears, and the agent asks you to confirm in the chat | The agent wants your confirmation before it calls the tool | Reply `Yes, go ahead.`; the approval request follows |
| The approval request shows a priority other than `3` | The agent mapped P3 Medium to the wrong number, or chose another priority | Decline it, and ask again for priority 3 (P3 Medium); an agent may set only P2 to P4, because a person declares a P1 |
| `Show-McpServerLog.ps1` shows no rows | It reads the last 100 lines of the live log stream, and other calls have pushed yours out | Run it again with `-Tail 300`, or a few minutes later with `-LogAnalytics` |
| Validation fails right after you finish the task | The MCP server's tool invocation log reaches Log Analytics a few minutes after the call | Wait two or three minutes and validate again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 2: Separate a Public Reply from an Internal Note

In this task, you will learn the sharpest data-protection lesson in the lab. Ticket notes in Dataverse carry an internal flag: a customer-visible reply is written for the customer, an internal note is for technicians only, and nothing from the second may reach the first. You work on **TCK-10524**, *Claims team cannot open policy documents*, from **Humongous Insurance**, which already holds two internal notes that must never reach the customer: **TCK-10524-N2**, the account manager's note that Humongous Insurance is disputing last month's invoice, so no service credits may be offered, and **TCK-10524-N3**, Daniel Cho's finding that the customer's own administrator renewed the certificate on the old server APP02 instead of APP03.

1. Add a customer-visible reply (`add_public_reply`) and an internal note (`add_internal_note`) to the same ticket through the agent. In the playground, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   On TCK-10524, add this customer-visible reply, word for word: "Hello, we have found the cause of the certificate warning in the document management application. A technician is renewing the certificate now, and we will confirm here as soon as your claims team can open policy documents again." Then add this internal note, word for word: "Customer-visible update sent. Daniel Cho is renewing the certificate on the correct application server today. Service credits were not discussed with the customer." Report the note code and correlation ID of each.
   ```

   **Expected Output:** the agent says what it will add, and then asks for your approval once per note. Check that each text goes to the right tool, and select **Approve** only when both match:

   | Tool | Arguments to check before you approve |
   |---|---|
   | `add_public_reply` | `ticket_number` **TCK-10524**, and a `body` that is the reply, word for word, starting *Hello, we have found the cause* |
   | `add_internal_note` | `ticket_number` **TCK-10524**, and a `body` that is the internal note, word for word, starting *Customer-visible update sent* |

   After both approvals, the agent reports two notes, each with its own correlation ID: the reply with the visibility **customer-visible**, and the internal note with the visibility **internal**. Each note code is the ticket number, `-A`, the date and time in UTC and four more characters, for example `TCK-10524-A20261210143015a3f9`.

   **What this validates:** the text the customer will read and the text only technicians will read go through two different tools, and you see which is which before either is written.

   > **[SCREENSHOT PENDING: E4T2S1-1 | Playground approval request for add_public_reply on TCK-10524 with the reply text as the body | source: capture]**

   > **[SCREENSHOT PENDING: E4T2S1-2 | Agent's report of the two notes with their codes, visibility and correlation IDs | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Important:** A reply sent with `add_internal_note`, or an internal note sent with `add_public_reply`, is exactly the mistake this task guards against. If the tool and the text don't match, decline the request and tell the agent which tool to use.

   In **Lab notes.txt**, next to **Customer-visible reply and internal note: ticket and note codes**, record **TCK-10524** and the two note codes, marking which is the reply and which is the internal note.

1. Confirm both landed with the correct internal flag set in Dataverse. In the Service Desk app, select **Work** > **Tickets**, select the **Open Tickets** view, filter the **Ticket Number** column on `TCK-10524` as you did in Task 1, and open **TCK-10524**. Select **Related** > **Ticket Notes**. The ticket now has five notes: the three seeded ones (Daniel Cho's first reply, **Customer visible**; Isabel Grant's account manager note, **Internal**; and Daniel Cho's finding, **Internal**) and your two notes by **Service desk agent (MCP)**:

   | Summary starts with | Internal Note |
   |---|---|
   | *Reply: Hello, we have found the cause* | **Customer visible** |
   | *Internal: Customer-visible update sent* | **Internal** |

   Open each of your two notes: **Body** is the text you approved, and **Correlation ID** matches the one the agent reported for it. The app doesn't show the note code, so match each note by its correlation ID. On the ticket form, **Last Correlation ID** is unchanged: adding a note doesn't change a ticket field, so the ID is recorded on the note instead.

   > **[SCREENSHOT PENDING: E4T2S2 | TCK-10524 Related Ticket Notes with the new reply marked Customer visible and the new note marked Internal, both by Service desk agent (MCP) | source: capture]**

   > **Note:** If the **Ticket Notes** list under **Related** doesn't show the **Internal Note** column, select **Work** > **Ticket Notes** instead. The **All Ticket Notes** view lists the newest notes first, with **Ticket**, **Internal Note**, **Author**, **Noted On (UTC)** and **Summary**, so your two notes are at the top.

1. Ask the agent to draft a customer-facing response for that ticket. Select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Draft an update for Humongous Insurance on TCK-10524 that says what is happening and what happens next. The customer will read it, so show me the draft only and don't add it to the ticket.
   ```

   **Expected Output:** the agent reads TCK-10524 and its notes with `get_ticket_notes`, which by default returns only the customer-visible ones, **TCK-10524-N1** and your reply, and withholds the three internal notes. The draft is a short update for the claims team: the certificate warning in the document management application is being fixed, a technician is renewing the certificate, and Relecloud will confirm as soon as policy documents open again. No approval request appears, because nothing is written; if one does, decline it.

   **What this validates:** the agent drafts a customer message from what the customer may read, and the internal flag decides what the read tool returns.

   > **[SCREENSHOT PENDING: E4T2S3 | Playground draft of a customer update for TCK-10524 with no internal note content | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Confirm no internal-note content appears anywhere in that response. Read the whole draft and check it against each item below. None of them may appear, in any wording:

   | Must not appear in the draft | Where it comes from |
   |---|---|
   | The invoice dispute, or any billing or invoice remark | **TCK-10524-N2**, the account manager's note |
   | Service credits | **TCK-10524-N2** and your internal note |
   | APP02 or APP03 | **TCK-10524-N3** |
   | The customer's own administrator, or any blame for the renewal | **TCK-10524-N3** |
   | Anything else from your internal note, such as *the correct application server* | Your internal note |

   If any item appears, select **New chat** and ask again; if it appears a second time, add the finding next to **Customer-visible reply and internal note: ticket and note codes** in **Lab notes.txt**.

   > **Note:** The agent's instructions and your approval are not the only safeguards. `add_public_reply` checks every reply against the ticket's internal notes before it writes anything: a reply that repeats six or more consecutive words of an internal note is refused with `INTERNAL_CONTENT_IN_REPLY`, which names the note, and a reply that contains a payment card number is refused with `SENSITIVE_DATA_IN_REPLY`. That second line of defense runs in the server's code on every call, whatever the model wrote.

### Expected results

- [ ] You approved `add_public_reply` and `add_internal_note` on **TCK-10524** after checking that each text went to the right tool
- [ ] **Related** > **Ticket Notes** shows the reply as **Customer visible** and the note as **Internal**, both by **Service desk agent (MCP)**, with the correlation IDs the agent reported
- [ ] The draft update for Humongous Insurance mentions no invoice dispute, no service credits, no APP02 or APP03, no administrator and nothing from your internal note
- [ ] You recorded TCK-10524 and the two note codes in **Lab notes.txt**

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The approval request for the reply shows `add_internal_note`, or the other way round | The agent mixed up the two texts | Decline it, and reply that the reply goes to `add_public_reply` and the note to `add_internal_note` |
| The reply is refused with `INTERNAL_CONTENT_IN_REPLY` | The agent changed the reply so that it repeats six or more consecutive words of an internal note | The server's check worked. Ask the agent to send the reply exactly as written in the prompt |
| The draft contains an item from the table | The agent read the internal notes into the draft | Select **New chat** and send the prompt again, adding `Use only the customer-visible notes.` |
| Validation fails | Both notes must be on the same ticket and both calls must succeed, or the log hasn't reached Log Analytics yet | Check that both results were ok on TCK-10524, then wait two or three minutes and validate again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 3: Chain Grounding into Action

In this task, you will join everything from Exercises 1 and 2 to the MCP tools, in one unbroken exchange. The agent reads the new incident **TCK-10561**, grounds a recommendation in Relecloud's own records, and carries it out through writes you approve, so the triage that the agent only recommended in Exercise 2 now lands on the ticket.

1. Give the agent the new incident from Exercise 2. In the playground, select **New chat**, enter the following prompt, and press **Enter**. Stay in this chat until the end of step 4.

   **Prompt:**

   ```
   TCK-10561 is the new incident from this morning. Read it with the Service Desk tools and tell me what it reports and what is still missing from the record. Don't change anything yet.
   ```

   **Expected Output:** the agent reads TCK-10561 with `get_ticket`, a read tool that runs without an approval request: **A. Datum Corporation** (**CUST-019**), *Nightly protection job stopped creating recovery points*, status **New**. Since Saturday night the nightly protection job for the project archive server has stopped creating new recovery points, the console says the cloud storage allowance has been used up, and the customer copied the 2019 to 2024 drawing archive onto that server last week. Missing: the priority, category, subcategory and technician, so the ticket has no SLA clock yet.

   **What this validates:** the agent reaches a ticket that the knowledge index has never seen through the read tools, before it reasons about it.

   > **[SCREENSHOT PENDING: E4T3S1 | Playground answer restating TCK-10561 from A. Datum Corporation with no priority, category or technician | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Have it retrieve the customer context, similar historical cases and relevant knowledge articles. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Before you recommend anything, retrieve the context: A. Datum Corporation's profile and agreed procedures, the most similar historical tickets and any open ticket with the same problem, the knowledge articles and runbook that apply, and the available technicians with the right skills.
   ```

   **Expected Output:** read tools and the knowledge index only, so no approval request appears. With a source for each point, the agent reports:

   - **Customer:** **A. Datum Corporation** (**CUST-019**), **Silver**, **Co-Managed**, account manager **Owen Fletcher**, with the procedures **CUST-019-PR1**, **CUST-019-PR2** and **CUST-019-PR3** *Backup retention and vault size changes*: vault size increases need the IT manager's written approval, Owen Fletcher quotes them, and large archive imports must be announced a week ahead.
   - **History:** tickets resolved with **KB0023**, such as **TCK-10004**, **TCK-10035** and **TCK-10471**, and the open **TCK-10521** at Trey Research with the same problem.
   - **Knowledge:** **KB0023** *RBA-2201: cloud vault storage quota exceeded*, runbook **RB-002** *Vault capacity and retention changes*, and possibly **CDOC-033**, A. Datum's configuration notes, which put the vault allowance at 3 TB with about 2.5 TB normally used.
   - **Technician:** **Priya Raman** (**TECH-01**, Infrastructure, L2, available), with skills in the Relecloud Backup Agent and vault storage, who resolved the ten earlier KB0023 tickets. If the agent lists the whole team, it notes that Marcus Webb (TECH-02) is on leave.

   **What this validates:** the agent gathers customer context, history and knowledge before it recommends, which is what makes the later writes reviewable.

   > **[SCREENSHOT PENDING: E4T3S2 | Playground answer with A. Datum's profile and CUST-019-PR3, the KB0023 history and TCK-10521, KB0023 and RB-002, and Priya Raman available | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Have it state a recommendation and name the sources behind it. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   State your recommendation for TCK-10561: the category and subcategory, the priority with the SLA target it gives this customer, and the technician. Name the source behind each part. Don't change anything yet.
   ```

   **Expected Output:** the same triage you recorded in Exercise 2, now with its sources:

   | Part | Recommendation | Sources the agent names |
   |---|---|---|
   | Category | **Backup and Recovery**, subcategory **Storage quota** | **KB0023**, and the classification of the open **TCK-10521** |
   | Priority | **P3 Medium**, with an SLA target of **32** business hours | The ten KB0023 tickets and TCK-10521, all P3 Medium; A. Datum Corporation's **Silver** SLA targets, where P3 Medium resolves in 32 business hours |
   | Technician | **Priya Raman** (**TECH-01**, Infrastructure) | The KB0023 history, her skills and her availability |

   The agent may add an escalation to the **Account Manager** for a vault quote, from KB0023's resolution, runbook RB-002 and procedure CUST-019-PR3.

   **What this validates:** every part of the triage traces to a record you can open, before anything changes.

   > **[SCREENSHOT PENDING: E4T3S3 | Playground recommendation for TCK-10561: Backup and Recovery, Storage quota, P3 Medium with 32 business hours, Priya Raman, each with its sources | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Have it carry out that recommendation through a write tool, with approval, in the same exchange. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Go ahead and apply your recommendation to TCK-10561, one change at a time: first the category and subcategory, then the priority, then the technician. Give each change a reason that cites its source. Leave the escalation for later. Report each outcome with its correlation ID.
   ```

   **Expected Output:** the agent asks for your approval three times, once per write. Check each request against this table, and select **Approve** only when it matches:

   | Write | Arguments to check before you approve |
   |---|---|
   | `update_ticket_category` | `ticket_number` **TCK-10561**, `category` **Backup and Recovery**, `subcategory` **Storage quota**, and a `reason` that cites KB0023 or TCK-10521 |
   | `update_ticket_priority` | `ticket_number` **TCK-10561**, `priority` **3**, and a `reason` that cites the KB0023 history |
   | `assign_ticket` | `ticket_number` **TCK-10561**, `technician` **TECH-01** or **Priya Raman**, and a `reason`, which is optional for this tool |

   After the third approval, the agent reports three outcomes, each with its own correlation ID: the category changed from **Not set** to **Backup and Recovery** / **Storage quota**, the priority from **Not set** to **P3 Medium** with an SLA target of **32** business hours, and **Priya Raman (TECH-01)** assigned, with the status now **In Progress**.

   **What this validates:** grounding and action meet in one exchange, and each change still waits for your decision on its own arguments.

   > **[SCREENSHOT PENDING: E4T3S4-1 | Playground approval request for update_ticket_priority on TCK-10561 with priority 3 and a reason that cites the KB0023 history | source: capture]**

   > **[SCREENSHOT PENDING: E4T3S4-2 | Agent's report of the three outcomes on TCK-10561, each with its correlation ID | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Note:** The baseline catalog has no tool that escalates a ticket, which is why the prompt leaves the escalation for later. You add one in Task 5 and use it on this ticket. If the agent proposes any other write, decline it as you declined the status change on TCK-10544.

   In **Lab notes.txt**, next to **Grounded action on TCK-10561: recommendation, sources and correlation ID**, record **Backup and Recovery (Storage quota), P3 Medium with 32 business hours, Priya Raman (TECH-01); KB0023, TCK-10521, CUST-019-PR3** and the correlation IDs of the three writes.

1. Verify the resulting state of the ticket in the Service Desk app. Select **Work** > **Tickets** and the **Untriaged Tickets** view: TCK-10561 is gone, and four tickets remain: **TCK-10558**, **TCK-10559**, **TCK-10560** and **TCK-10562**. Select the **Open Tickets** view, filter the **Ticket Number** column on `TCK-10561`, and open **TCK-10561**:

   - **Summary**: **Status** **In Progress**, **Priority** **P3 Medium**, **Category** **Backup and Recovery**, **Subcategory** **Storage quota** and **Assigned Technician** **Priya Raman**.
   - **SLA**: **SLA Target (business hours)** **32.00**, the resolution target of the **Silver P3 Medium** SLA policy.
   - **Traceability**: **Last Correlation ID** is the correlation ID of the assignment, the last change.
   - **Related** > **Ticket Notes**: three internal audit notes by **Service desk agent (MCP)**, starting *Category set by the service desk agent to Backup and Recovery / Storage quota*, *Priority changed by the service desk agent from Not set to P3 Medium* and *Assigned by the service desk agent to Priya Raman (TECH-01)*, each with its reason, your account and its correlation ID.

   Then, under **Work**, select **Agent Actions**: the **All Agent Actions** view lists three rows for **TCK-10561**, for `update_ticket_category`, `update_ticket_priority` and `assign_ticket`, each **Allowed** and **Succeeded** with its own **Correlation ID**.

   > **[SCREENSHOT PENDING: E4T3S5-1 | TCK-10561 form with In Progress, P3 Medium, Backup and Recovery, Storage quota, Priya Raman and SLA Target (business hours) 32.00 | source: capture]**

   > **[SCREENSHOT PENDING: E4T3S5-2 | All Agent Actions view with the three TCK-10561 rows, Allowed and Succeeded | source: capture]**

   > **Note:** **SLA Elapsed (business hours)**, **SLA Remaining (business hours)**, **SLA Due On (UTC)** and **SLA Status** count from the ticket's **Opened On (UTC)**, which depends on when your environment was prepared, so your figures differ from other participants'. The target of 32 business hours is the same for everyone.

### Expected results

- [ ] The agent read TCK-10561 and retrieved A. Datum Corporation's context, the KB0023 history, KB0023 and RB-002, and Priya Raman's availability, all without an approval request
- [ ] Its recommendation was **Backup and Recovery**, **Storage quota**, **P3 Medium** with 32 business hours, and **Priya Raman** (**TECH-01**), with a source for each part
- [ ] You approved `update_ticket_category`, `update_ticket_priority` and `assign_ticket` after checking their arguments, in the same chat
- [ ] **TCK-10561** shows **In Progress**, **P3 Medium**, **Backup and Recovery**, **Storage quota**, **Priya Raman** and **SLA Target (business hours)** **32.00**, with three audit notes, and it is no longer in **Untriaged Tickets**
- [ ] **All Agent Actions** lists the three writes on TCK-10561, each **Allowed** and **Succeeded**, and you recorded the recommendation, its sources and the correlation IDs

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The agent recommends P2 or P1 because backups are failing | It applied general urgency instead of Relecloud's history | Ask it for the priority of the ten KB0023 tickets and of TCK-10521, and to recommend again |
| `assign_ticket` returns `TECHNICIAN_UNAVAILABLE` | It chose Marcus Webb (TECH-02), who is on leave | The error lists available technicians from the same team whose skills fit; ask the agent to assign TECH-01 |
| `update_ticket_category` returns `INVALID_ARGUMENT` | The subcategory doesn't belong to the category | The error lists the allowed subcategories; **Storage quota** belongs to **Backup and Recovery** |
| An approval request appears before the agent has stated its recommendation | The agent jumped ahead to the change | Decline it, and ask for the recommendation and its sources first |
| Validation fails right after you finish the task | The log reaches Log Analytics a few minutes after the call | Wait two or three minutes and validate again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 4: Tighten a Tool Boundary

In this task, you will tighten one limit and redeploy under time pressure. The baseline already validates its inputs: every argument of every tool has a range, a pattern, a list of values or a length, checked before the tool runs. You lower one of those boundaries in code, ship it as version 3.0.2, and prove that the server enforces the new one.

1. Review the change: reduce the maximum limit argument of get_open_tickets from 50 to 20. In Visual Studio Code, open `src\servicedesk_mcp\policy.py` and find `MAX_OPEN_TICKETS_LIMIT = 50`, the largest number of tickets `get_open_tickets` may return in one call. Then open `src\servicedesk_mcp\tools_read.py` and find the `limit` argument of `get_open_tickets`: `Field(..., ge=1, le=policy.MAX_OPEN_TICKETS_LIMIT)`. The `le` bound (less than or equal to) becomes the `maximum` of the tool's input schema, so the agent reads it in `tools/list`, and the server rejects a larger value with `INVALID_ARGUMENT` before the tool runs. In the Visual Studio Code terminal, run the following command, which calls the tool with a limit of 30 through the diagnostics API and shows the counts from the result:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_open_tickets @{ limit = 30 } | ConvertFrom-Json | Select-Object ok, returned, limit, total_open
   ```

   The first line, *Connected to Relecloud Service Desk (diagnostics) 3.0.1*, names the version serving now, and the call succeeds: **ok** `True`, **returned** `30`, **limit** `30` and **total_open** `62`.

   > **[SCREENSHOT PENDING: E4T4S1 | policy.py with MAX_OPEN_TICKETS_LIMIT = 50, and the limit 30 call returning ok True and 30 tickets | source: capture]**

1. Update the MCP server. In Visual Studio Code, make these changes and save each file:

   - In `src\servicedesk_mcp\policy.py`, set the limit to 20:

     ```python
     MAX_OPEN_TICKETS_LIMIT = 20
     ```

   - In `src\servicedesk_mcp\__init__.py`, raise the version to the next patch after the 3.0.1 you deployed in Exercise 3:

     ```python
     __version__ = "3.0.2"
     ```

   - Two unit tests pin the old boundary, so update them with it. In `tests\test_catalogue.py`, in `test_open_tickets_limit_is_published_in_the_schema`, change `policy.MAX_OPEN_TICKETS_LIMIT == 50` to `policy.MAX_OPEN_TICKETS_LIMIT == 20`. In `tests\test_logging.py`, in `test_validation_line_carries_the_violation`, change the accepted call's `limit=25` to `limit=20`, the rejected call's `limit=51` and both checks of `51` to `30`, and `["le"] == 50` to `["le"] == 20`.

   Then, in the Visual Studio Code terminal, run the following command, which checks that the four files are still valid Python. It prints nothing when they are:

   ```powershell
   python -m py_compile .\src\servicedesk_mcp\policy.py .\src\servicedesk_mcp\__init__.py .\tests\test_catalogue.py .\tests\test_logging.py
   ```

   If you created `.venv` in Exercise 3 to run the tests, run the following command, which runs the two test files you changed; it reports **22 passed**:

   ```powershell
   .\.venv\Scripts\python.exe -m pytest tests\test_catalogue.py tests\test_logging.py
   ```

   > **Note:** Without `.venv`, skip the test run: creating it first downloads and installs the server's dependencies, which this task has no time for. The image build doesn't run the tests either, because `.dockerignore` leaves the `tests` folder out of the image. In production, a pipeline runs the whole suite before every build.

   > **[SCREENSHOT PENDING: E4T4S2 | policy.py with MAX_OPEN_TICKETS_LIMIT = 20 and __init__.py with version 3.0.2 in Visual Studio Code | source: capture]**

1. Build and redeploy to your MCP server. In the Visual Studio Code terminal, run the following command. It builds the image `mcp-server:3.0.2` from this folder with ACR Tasks in your registry **<inject key="Container Registry Name" enableCopy="false"/>**, so the VM needs no Docker, deploys it as a new revision of **<inject key="Container App Name" enableCopy="false"/>**, and waits until the new revision runs with all the traffic and reports version 3.0.2:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag 3.0.2
   ```

   The script prints its three stages, **[1/3] Building**, **[2/3] Deploying a new revision** and **[3/3] Checking the new revision**, then a status line every 10 seconds until the new revision shows `version 3.0.2, ready True`. It ends with your last five revisions and *Build took mm:ss; full cycle mm:ss*, followed by the app name and *now serves* the `mcp-server:3.0.2` image.

   > **[SCREENSHOT PENDING: E4T4S3 | Deploy-McpServer.ps1 output with the new revision ready at version 3.0.2, the revision table and the build and cycle times | source: capture]**

   > **Note:** Microsoft documents no build time for an image like this one, which installs the server's Python dependencies (its smallest documented example, a one-line image, builds in about 10 seconds), and no time for a new revision to become ready, so the script measures both and prints them at the end. Expect about as long as the redeploy you timed in Exercise 3 and recorded next to **Redeploy: your change, the new revision, how long the cycle took, how to roll back**. The script waits up to 600 seconds for the revision, so leave it running. Meanwhile the previous revision keeps serving, because in single revision mode traffic moves only when the new revision is ready.

1. Confirm a call above the new limit is rejected with a structured error. Run the following command, which sends the same call with a limit of 30 and prints the whole result:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_open_tickets @{ limit = 30 }
   ```

   The script now connects to version 3.0.2 and prints `isError: True` with the call's `correlation_id`. The result has `ok` `false` and an `error` with `code` `INVALID_ARGUMENT`, `message` *get_open_tickets: 'limit' is not valid: Input should be less than or equal to 20.*, `source` `input validation`, `retryable` `false`, a `hint`, and `details.violations` with one entry: `argument` `limit`, `problem` *Input should be less than or equal to 20*, `constraint` `{"le": 20}` and `received` `30`. There is no stack trace and no Dataverse call: the server checked the argument against the new schema before the tool ran. Then run the following command, which shows how the tool invocation log recorded the call:

   ```powershell
   .\scripts\Show-McpServerLog.ps1 -Tool get_open_tickets
   ```

   The row shows **Endpoint** `diagnostics`, **Outcome** `rejected`, **ErrorCode** `INVALID_ARGUMENT`, **Authorization** `Rejected by the MCP server` and **DecidedBy** `input validation`, with no user, because the diagnostics API carries none.

   > **[SCREENSHOT PENDING: E4T4S4 | Invoke-McpTool.ps1 output with isError True, INVALID_ARGUMENT, received 30 and the constraint le 20 | source: capture]**

   > **Note:** The agent reads the new maximum from the tool's input schema. In a new chat, if you ask it for the 30 open tickets closest to breach, it should ask for at most 20, or correct its call after the `INVALID_ARGUMENT` error, as its instructions say. Validation reads the server's log, so the call above is the one that counts.

   In **Lab notes.txt**, next to **get_open_tickets limit before and after, and the rejected call**, record **50 before, 20 after; limit 30 rejected with INVALID_ARGUMENT (received 30, le 20)** and the rejected call's correlation ID.

### Expected results

- [ ] Before the change, `get_open_tickets` with a limit of 30 returned 30 tickets
- [ ] `MAX_OPEN_TICKETS_LIMIT` is 20, `__version__` is `3.0.2`, and the two tests expect the new boundary
- [ ] `Deploy-McpServer.ps1` reported the new revision ready at version 3.0.2, serving `mcp-server:3.0.2`
- [ ] The same call now fails with `INVALID_ARGUMENT`, `received` 30 and the constraint `le` 20, and the log shows it as `rejected` by `input validation`
- [ ] You recorded the limit before and after and the rejected call in **Lab notes.txt**

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `Deploy-McpServer.ps1` stops because it can't find `src\servicedesk_mcp\__init__.py` | The script was given a `-SourcePath` that isn't the repository, or the terminal is in another folder | Run `.\scripts\Deploy-McpServer.ps1 -Tag 3.0.2` in the Visual Studio Code terminal, which opens in `C:\LabFiles\mcp-server`. The copy in `C:\LabFiles\tools` also finds that working copy on its own |
| *az acr build failed (...). Nothing was deployed; the running revision is unchanged.* | A build step failed, often because your Azure CLI sign-in expired | Read the last lines of the build log, run `az login` as the Senior Technician if it asks you to sign in, and run the script again; each run gets its own revision name, so the same tag is fine |
| *Revision ... did not become ready within 600 seconds.* | The new image fails to start, for example after a typo in `policy.py`; traffic stays on the previous revision | Run `.\scripts\Show-McpServerLog.ps1 -All` to read the startup error, fix the file, run the `py_compile` check, and deploy again |
| The call with a limit of 30 still succeeds | The revision that serves traffic doesn't hold your change | Check that the script ended with *now serves* the `mcp-server:3.0.2` image and that `policy.py` was saved, then deploy again |
| Validation fails right after the call | The log reaches Log Analytics a few minutes after the call | Wait two or three minutes and validate again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 5: Design and Add a Scoped Tool

In this task, you will design one new tool, build it into your MCP server as version 3.0.3 and use it. MCP tool design is part of what you are evaluated on: one action, a description the agent can act on, typed arguments, an output schema, the least permission that works, and approval because it writes.

1. Choose one new action, for example escalating a ticket or linking a knowledge article. Linking a knowledge article is already in the catalog: `link_kb_article` links a Published article to a ticket as its related article, and refuses a Draft or Retired one with `ARTICLE_NOT_PUBLISHED`. So choose the escalation. TCK-10561 still lacks the step that every KB0023 ticket took, an escalation to the **Account Manager** for a vault quote: KB0023's resolution says to ask the account manager to offer a vault size increase, runbook RB-002's escalation path is *Escalate to the account manager for the quote*, and all ten KB0023 tickets were escalated to the Account Manager. No tool can record that today, so the reference answer is `escalate_ticket`, and you use it to escalate TCK-10561 to the Account Manager.

1. Define its description, input schema, output schema, required permission and whether it needs approval. In File Explorer, open `C:\LabFiles\solutions\exercise-4-task-5` and open `README.md` in Visual Studio Code: its **Design** table is the reference design. In short:

   | Element | Design of `escalate_ticket` |
   |---|---|
   | Description | Escalate an open ticket to an L3 specialist, the vendor or the customer's account manager. Requires approval. It doesn't change the priority, the status or the assigned technician, and it never declares a Major Incident: a person does that, through runbook RB-009 |
   | Input schema | `ticket_number` (pattern `^TCK-\d{5}$`), `level` (one of `L3 Specialist`, `Vendor` and `Account Manager`) and `reason` (10 to 500 characters), all required, with no optional values |
   | Output schema | The shared write result (`ok`, `correlation_id`, `error`, `note`, `warnings`, `duplicate`, `duplicate_of`), plus `ticket_number`, `changes` with `escalated_to`, `escalated_on` and `previous_level`, `audit_note` and `ticket` |
   | Required permission | Write on `spk_ticket`; Create and Append on `spk_ticketnote` and Append To on `spk_ticket` for the audit note; Create on `spk_agentaction` for the Agent Action row, held by the server's application user only |
   | Approval | Required: it changes the system of record, so it is a write tool on `/write/mcp`, where the agent's **servicedesk-write** tool asks before every call |

   It changes four columns, **Escalated**, **Escalation Level**, **Escalated On (UTC)** and **Escalation Reason**, plus **Last Correlation ID**. If you design another tool, give it the same five elements and keep it to one action on one table. In **Lab notes.txt**, next to **Your scoped tool: name, description, permission and approval**, record your design, for example **escalate_ticket: escalates an open ticket to L3 Specialist, Vendor or Account Manager, never a Major Incident; Write on spk_ticket plus the audit note and Agent Action privileges; approval required on servicedesk-write**.

   > **[SCREENSHOT PENDING: E4T5S2 | Lab notes.txt with the scoped tool line completed for escalate_ticket | source: capture]**

1. Implement and redeploy it, keeping reading and writing operations in separate tools. In Visual Studio Code, open `C:\LabFiles\solutions\exercise-4-task-5\escalate_ticket.py`. It follows the checklist in `TOOLS.md`, section **Add your own tool**, item by item: `@catalogue.write_tool(...)` publishes it on the write endpoint with approval required, and runs the duplicate guard, the Agent Action row and the log line for it; the docstring is the description the agent reads; `TicketNumber`, a `Literal` of the three levels and `Reason` type every argument; `require_user` and `policy.validate_reason` check the rules first, and a Resolved or Closed ticket is refused with `TICKET_CLOSED`; the change goes through `repo.update_ticket`, and `await changed(...)` adds the audit note and returns the ticket as it now stands. Reading stays in the read tools: the new tool loads only the ticket it changes, to check that it is open, returns no notes, contacts or documents, and is never published on `/read/mcp`.

   In the Visual Studio Code terminal, run the following command, which appends the reference block to the end of `tools_write.py`. Because `add_public_reply` is the last function in `register()` and every line of the block starts with four spaces, the block lands inside `register()`, after `add_public_reply`. Run it once only:

   ```powershell
   Get-Content C:\LabFiles\solutions\exercise-4-task-5\escalate_ticket.py | Add-Content .\src\servicedesk_mcp\tools_write.py
   ```

   In Visual Studio Code, open `src\servicedesk_mcp\tools_write.py` and go to the end: the block starts with the comment `# ==== Exercise 4 Task 5: reference solution`, indented four spaces like `add_public_reply` above it. To adapt the tool instead of copying it, edit the block here, for example its description or its levels, and keep the decorator, `require_user`, `policy.validate_reason` and the change through `repo.update_ticket`. Then, in `src\servicedesk_mcp\__init__.py`, set the version and save:

   ```python
   __version__ = "3.0.3"
   ```

   Run the following command, which checks that both files are still valid Python, so a bad paste fails here and not after a build. It prints nothing when they are:

   ```powershell
   python -m py_compile .\src\servicedesk_mcp\tools_write.py .\src\servicedesk_mcp\__init__.py
   ```

   Run the following command, which copies the reference tests into the repository's `tests` folder:

   ```powershell
   Copy-Item C:\LabFiles\solutions\exercise-4-task-5\test_escalate_ticket.py .\tests\
   ```

   If you created `.venv` in Exercise 3, run the following command, which runs the six new tests; it reports **6 passed**:

   ```powershell
   .\.venv\Scripts\python.exe -m pytest tests\test_escalate_ticket.py
   ```

   Then run the following command, which builds and deploys version 3.0.3 the same way as in Task 4. While it runs, read `test_escalate_ticket.py`: its six tests prove that the tool is a write tool on `/write/mcp` only, that an escalation leaves an audit note and an Agent Action row, that a repeat is a duplicate, that **Major Incident** isn't a choice, that a closed ticket is refused, and that a call without a signed-in user is refused.

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag 3.0.3
   ```

   When the script reports the new revision ready at version 3.0.3, run the following command, which lists the catalog your server now publishes:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 -List
   ```

   The list has eight write tools: `escalate_ticket` shows **Kind** `write`, **Endpoint** `/write/mcp`, **Approval** `required` and **Required** `ticket_number, level, reason`.

   > **[SCREENSHOT PENDING: E4T5S3-1 | tools_write.py in Visual Studio Code with the escalate_ticket block at the end of register(), after add_public_reply | source: capture]**

   > **[SCREENSHOT PENDING: E4T5S3-2 | Invoke-McpTool.ps1 -List output with escalate_ticket as a write tool on /write/mcp with Approval required | source: capture]**

   > **Note:** The deploy takes about as long as in Task 4, and the script prints the build and cycle times at the end. If you run out of time while it builds, keep it running and continue when it reports the revision ready; the previous revision serves the agent until then.

1. Call it from your agent and confirm the result in the Service Desk app. In the playground, select **New chat**, so that the agent lists its tools again and finds the new one, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Use the escalate_ticket tool to escalate TCK-10561 to the Account Manager. Reason: the vault size increase needs Owen Fletcher's quote and the IT manager's written approval under CUST-019-PR3, as KB0023 and RB-002 say. Report the outcome with its correlation ID.
   ```

   **Expected Output:** the agent asks for your approval, although you set up nothing for the new tool in Foundry: the **servicedesk-write** tool lists every tool the write endpoint serves, and asks before each call. Check the request, and select **Approve** only when it matches:

   | Tool | Arguments to check before you approve |
   |---|---|
   | `escalate_ticket` | `ticket_number` **TCK-10561**, `level` **Account Manager**, and a `reason` that cites CUST-019-PR3, KB0023 or RB-002 |

   The agent then reports the escalation to the **Account Manager**, the previous level **none**, the time of the escalation, the audit note and the `correlation_id`.

   **What this validates:** a tool you added is published only on the write endpoint and inherits the approval, the duplicate guard, the audit note and the Agent Action row without any other change.

   > **[SCREENSHOT PENDING: E4T5S4-1 | Playground approval request for escalate_ticket with ticket_number TCK-10561, level Account Manager and a reason | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   In the Service Desk app, open **TCK-10561** again, or select **Refresh** if it's open. The **Escalation** section shows **Escalated** **Escalated**, **Escalation Level** **Account Manager**, **Escalated On (UTC)** the time of your approval, and **Escalation Reason** the agent's reason. **Status**, **Priority** and **Assigned Technician** are unchanged (**In Progress**, **P3 Medium**, **Priya Raman**), and **Last Correlation ID** is the escalation's correlation ID. Under **Related** > **Ticket Notes**, a new internal audit note starts *Escalated by the service desk agent to Account Manager (was none)*. Under **Work** > **Agent Actions**, the newest row is **escalate_ticket on TCK-10561: Succeeded**, with **Authorization** **Allowed**. Finally, select **Work** > **Tickets** and the **Escalated Tickets** view: **TCK-10561** is at the top, with **Escalation Level** **Account Manager**.

   > **[SCREENSHOT PENDING: E4T5S4-2 | TCK-10561 Escalation section with Escalated, Escalation Level Account Manager, Escalated On (UTC) and Escalation Reason | source: capture]**

   > **[SCREENSHOT PENDING: E4T5S4-3 | All Agent Actions view with the escalate_ticket row for TCK-10561, Allowed and Succeeded | source: capture]**

### Expected results

- [ ] You recorded a design for your tool with its description, input and output schemas, permission and approval
- [ ] `tools_write.py` holds the new tool inside `register()`, `__version__` is `3.0.3`, and `Deploy-McpServer.ps1` reported the new revision ready at version 3.0.3
- [ ] `Invoke-McpTool.ps1 -List` shows `escalate_ticket` as a write tool on `/write/mcp` with **Approval** `required`
- [ ] In a new chat, the agent asked for approval before it called `escalate_ticket`, and you approved it after checking the arguments
- [ ] **TCK-10561** shows the escalation to the **Account Manager** with its audit note, an **Allowed** and **Succeeded** Agent Action row, and a place in the **Escalated Tickets** view

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The new revision never becomes ready, and `.\scripts\Show-McpServerLog.ps1 -All` shows *Tool escalate_ticket is registered twice* | The block was appended twice | In `tools_write.py`, delete the second copy of the block, save, and deploy again with `-Tag 3.0.3` |
| `py_compile` reports an `IndentationError` or `SyntaxError` | The block was pasted outside `register()` or lost its indentation | Make the block the last lines of the file, with each line starting four spaces in, run the check again, and then deploy |
| The agent says it has no tool that escalates a ticket | The chat started before the new revision was ready | Check that the deploy reported version 3.0.3, then select **New chat** and send the prompt again |
| The agent proposes `update_ticket_status` or `add_internal_note` instead | It worked around the missing tool from an older chat | Decline the request, select **New chat**, and send the prompt, which names `escalate_ticket` |
| `escalate_ticket` returns `INVALID_ARGUMENT` for `level` | The agent sent another level, such as **Major Incident** | Only `L3 Specialist`, `Vendor` and `Account Manager` are allowed; ask for the Account Manager |
| Validation fails | The call must succeed through the agent; a call through the diagnostics API carries no user and is refused, or the log hasn't arrived yet | Make the call in the playground, approve it, wait two or three minutes and validate again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Success Criteria

You have completed this exercise when:

- [ ] **TCK-10544** shows **P3 Medium** and **SLA Target (business hours)** **16.00**, and its **Last Correlation ID** matches the approved write in **Lab notes.txt**
- [ ] **TCK-10524** has a new reply flagged **Customer visible** and a new note flagged **Internal**, and their codes are in **Lab notes.txt**
- [ ] **TCK-10561** shows **In Progress**, **Backup and Recovery**, **Storage quota**, **P3 Medium**, **Priya Raman** and **SLA Target (business hours)** **32.00**, and is escalated to the **Account Manager**
- [ ] Your MCP server runs version 3.0.3: `get_open_tickets` rejects a limit of 30 with `INVALID_ARGUMENT`, and `escalate_ticket` is a write tool on `/write/mcp` that requires approval
- [ ] **Lab notes.txt** holds the six Exercise 4 values
- [ ] Negative check: the declined status change left TCK-10544 **New**, with no Agent Action row and no log line for it, and the draft update for TCK-10524 held nothing from its internal notes

## Apply It in Production

**What you built:**

- An agent that changes tickets only through approval-gated write tools, where every change leaves an audit note on the ticket, an Agent Action row and a log line, all joined by one correlation ID.
- Three layers between what technicians read and what customers read: the internal flag in Dataverse, the agent's instructions and the server's own check in `add_public_reply`, with your approval on top.
- A governed change path for the tool catalog itself: a tighter input boundary and a new scoped write tool, each tested, versioned and redeployed.

**Decisions to make before production:**

1. **Approval policy.** Approval on every write is the safe default, and this lab's requirement. Decide which writes stay behind a person's decision for good, such as customer-visible replies, priority and status, before anyone asks to drop approval for speed.
1. **Duplicate protection at scale.** The guard here keeps its memory in the process of one replica and starts empty with every revision. Before you run more than one replica, move it to a shared store, or key it on an idempotency value that every retry carries.
1. **Boundaries as code.** Limits live in one file and reach the agent through the input schema. Decide who may change them, and require a test for each one, like the two you updated.
1. **Tool review.** Treat every new tool like a change to production access: one action, typed arguments, an output schema, the narrowest permission, approval when it writes, and tests that prove its endpoint and its refusals.

**Production checklist:**

- [ ] Every write tool sits on the approval-required connection, and the read connection lists its tools by name
- [ ] A pipeline runs the whole test suite before every image build
- [ ] Images are tagged by version, and the previous revision stays available for rollback
- [ ] Alerts fire on `INTERNAL_CONTENT_IN_REPLY`, on bursts of `INVALID_ARGUMENT` and on denied writes
- [ ] Agent Action rows and the tool invocation log are kept as long as your customers' audit periods require

**Common pitfalls:**

| Pitfall | How to avoid it |
|---|---|
| A new write tool lands where it skips approval, for example on the read connection | Register writes only with `@catalogue.write_tool`, and test that the tool is absent from `/read/mcp`, as `test_escalate_ticket.py` does |
| A customer reply is approved without reading all of it | Read the whole body in the approval request, and decline anything that carries account, billing or internal detail |

## Knowledge Check

**Question 1:** You declined the status change on TCK-10544, and no Agent Action row records it, although the MCP server writes a row for every write it receives, even one that fails. Why?

<details>
<summary>Show the answer</summary>

Approval happens in Foundry, before the tool is called. A declined call is never sent, so it never reaches API Management, the MCP server or Dataverse, and none of them can record it. The conversation holds the approval request and your decision, which is where Exercise 6 finds it. The Agent Action row exists for the calls that do reach the server, because Dataverse audits only the changes that succeed.

</details>

**Question 2:** The agent's instructions already forbid putting internal notes into anything a customer reads. Why does `add_public_reply` check every reply as well?

<details>
<summary>Show the answer</summary>

Because instructions guide a model but don't bind it. The check is server code that runs on every call, whatever the model wrote: a reply that repeats six or more consecutive words of one of the ticket's internal notes is refused with `INTERNAL_CONTENT_IN_REPLY`, and one that contains a payment card number with `SENSITIVE_DATA_IN_REPLY`, before anything is written. With your approval in front of it, an internal note reaches a customer only if three safeguards fail at once.

</details>

**Question 3:** You added `escalate_ticket` without changing the agent, its connections or API Management. What made every call to it wait for your approval?

<details>
<summary>Show the answer</summary>

The `@catalogue.write_tool` decorator publishes a tool on the write endpoint and never on the read endpoint. The agent's **servicedesk-write** tool requires approval always and has no list of allowed tools, so every tool that endpoint serves appears with approval required. The **servicedesk-read** tool lists its 16 tools by name, so a new tool can never appear there. Keeping read and write tools on separate endpoints is what makes the approval automatic.

</details>

## Summary

In this exercise, you have completed the following:

- Reviewed the seven write tools, approved a priority change on TCK-10544 after checking its arguments, and declined a status change that then left nothing behind.
- Confirmed the approved change on the ticket, in the Agent Action table and in the tool invocation log, and recorded the correlation ID that Exercise 6 traces.
- Added a customer-visible reply and an internal note to TCK-10524, confirmed their internal flags, and checked a customer draft against the ticket's internal notes.
- Chained the grounded triage of TCK-10561 into three approved writes in one conversation, and verified the ticket in the Service Desk app.
- Lowered the `get_open_tickets` limit to 20, redeployed as version 3.0.2, and saw a larger limit rejected with a structured error.
- Designed and built `escalate_ticket`, deployed it as version 3.0.3, and escalated TCK-10561 to the Account Manager with your approval.

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
