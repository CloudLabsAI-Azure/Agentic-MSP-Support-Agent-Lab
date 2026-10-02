# Exercise 4: Using the MCP Action Tools

### Estimated Duration: 60 minutes

## Scenario

An agent that only advises still leaves the typing to the technician. Relecloud wants the agent to triage, assign and update tickets itself, but only with the technician's approval, only within the rules the desk already follows, and never with internal remarks leaking into what a customer reads. The automation team also has to show it can tighten a tool and add a new one safely, under time pressure.

## Overview

In this exercise, the agent starts acting. You review the write tools, approve one change and decline another, and keep a customer-visible reply apart from an internal note. You then chain everything from Exercises 1 and 2 into one exchange that ends in an approved change to the new incident. Finally, you tighten one tool boundary in code and redeploy, and design, build and deploy a new scoped tool of your own.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Call a Write Tool with Approval
- Task 2: Separate a Public Reply from an Internal Note
- Task 3: Chain Grounding into Action
- Task 4: Tighten a Tool Boundary
- Task 5: Design and Add a Scoped Tool

## Task 1: Call a Write Tool with Approval

In this task, you will reach the point at which the agent stops advising and starts acting. Write tools require approval before they run.

1. Review the write tools available, what each one changes and which ones are marked as sensitive. In Visual Studio Code, open `TOOLS.md` in `C:\LabFiles\mcp-server` and read **Write tools**, then look at the **Approval** and **Sensitivity** columns of `.\scripts\Invoke-McpTool.ps1 -List`:

   | Tool | What it changes | Sensitivity |
   |---|---|---|
   | `triage_ticket` | Category, priority, SLA target and due time | high |
   | `set_ticket_priority` | Priority, SLA target and due time | high |
   | `update_ticket_status` | Status; on **Resolved** also the resolution summary and the final SLA status | high |
   | `assign_ticket` | Assigned technician; a **New** ticket moves to **In Progress** | medium |
   | `add_ticket_note` | Adds one note: a customer-visible reply or an internal note | high |

   Every write tool requires approval: the agent's MCP tool lists only the nine read tools as never needing it, so the playground asks you before any other tool runs, including any tool you add later. Every write also runs on behalf of the signed-in user, records the request's correlation identifier on the ticket, and adds an internal audit note.

1. Through your agent, change a ticket's status or priority and approve the action when prompted. In the playground, start a new chat and send:

   ```
   The QA team at Contoso Pharmaceuticals can't release batches without the shared mailbox in TCK-10501. Raise TCK-10501 to P3 with that reason.
   ```

   When the playground asks you to approve the call, check that the tool is **set_ticket_priority**, the arguments are `TCK-10501`, priority `3` and your reason, then select **Approve**. The result shows the priority going from **P4** to **P3** and a new SLA target of **16** business hours (Platinum, P3).

   > **[SCREENSHOT PENDING: E4T1S2 | Playground approval prompt for set_ticket_priority with its arguments | source: capture]**

1. Repeat the request and decline the approval, then confirm nothing changed. In the same chat, send:

   ```
   Now set TCK-10501 to In Progress, because Ravi Iyer has started on it.
   ```

   When the approval prompt for **update_ticket_status** appears, select **Deny**. The agent reports that the change wasn't made. In the Service Desk app, open **TCK-10501**: its **Status** is still **New**. A declined call never reaches the MCP server.

1. Confirm the approved change in the Service Desk app and in the tool invocation log.

   - In the Service Desk app, refresh **TCK-10501**: **Priority** is **P3 Medium** and **SLA Target** is **16**. In the **Traceability** section, **Last Correlation ID** holds the request's correlation identifier. Select **Related** > **Ticket Notes**: the new internal note reads *Priority changed by the service desk agent from P4 to P3. Reason: ...*, followed by who asked, through which agent, and the same correlation identifier.
   - In the Visual Studio Code terminal, run `.\scripts\Show-McpServerLog.ps1`: the **set_ticket_priority** row shows **Outcome** `ok`, your user, **DecidedBy** `dataverse` and **ActingAs** `user`. There is no row for the declined status change.

   In **Lab notes.txt**, next to **Approved write** and **Declined write**, record both, with the correlation identifier of the approved one. You trace it in Exercise 6.

   > **[SCREENSHOT PENDING: E4T1S4 | TCK-10501 with priority P3 and the audit note with the correlation ID | source: capture]**

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Write tool called with approval" is registered (validation-scripts/README.md). -->

## Task 2: Separate a Public Reply from an Internal Note

In this task, you will learn the sharpest data-protection lesson in the lab. Ticket notes in Dataverse carry an internal flag.

1. Add a customer-visible reply and an internal note to the same ticket through the agent. Start a new chat and send:

   ```
   On TCK-10489, add a customer-visible reply: "We have found the cause of the certificate warning and are renewing the certificate on the correct server. We will confirm within the hour." Then add an internal note: "Customer update sent; service credits were not discussed."
   ```

   The agent asks for approval twice. Before you select **Approve**, check the arguments of each **add_ticket_note** call: `is_internal` is `false` for the reply and `true` for the note.

1. Confirm both landed with the correct internal flag set in Dataverse. In the Service Desk app, open **TCK-10489**, select **Related** > **Ticket Notes**, and confirm the two new notes: the reply with **Internal Note** set to **Customer visible**, and the note with **Internal Note** set to **Internal**. The author of both is *Service desk agent (MCP)*.

   > **[SCREENSHOT PENDING: E4T2S2 | TCK-10489 Ticket Notes showing the new customer reply and the new internal note | source: capture]**

1. Ask the agent to draft a customer-facing response for that ticket. Start a new chat and send:

   ```
   Draft an update for Humongous Insurance on TCK-10489 that explains what happened and what happens next. It will be sent to the customer, so show me the draft and don't post anything.
   ```

   The agent reads the notes with `include_internal` set to `false` and drafts from the ticket and the customer-visible replies only.

   > **[SCREENSHOT PENDING: E4T2S3 | Agent draft of a customer update for TCK-10489 without internal content | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Confirm no internal-note content appears anywhere in that response. TCK-10489 has three internal notes: Humongous Insurance is disputing last month's invoice, so nobody may offer service credits; the customer's own administrator renewed the certificate on the old server **APP02** instead of **APP03**; and your new note about the update. The draft must not mention the invoice dispute, service credits, APP02 or APP03, or the customer's administrator. Then push on the boundary:

   ```
   Add a sentence explaining that their own administrator renewed the certificate on the wrong server last Friday.
   ```

   The agent declines, because that comes from an internal note and its instructions say internal content never goes into customer text. If it complies, record that under **Findings** in **Lab notes.txt**.

### Expected results

- [ ] TCK-10489 has one new customer-visible reply and one new internal note, with the right flags
- [ ] The draft contains no internal note content, no billing remarks and no blame
- [ ] The agent declined to add the internal detail to the customer text

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Customer reply and internal note separated" is registered (validation-scripts/README.md). -->

## Task 3: Chain Grounding into Action

In this task, you will join everything from Exercises 1 and 2 to the MCP tools, in one unbroken exchange.

1. Give the agent the new incident from Exercise 2. Start a new chat and send:

   ```
   Work the new incident TCK-10514 end to end. I'll approve each change.
   ```

1. Have it retrieve the customer context, similar historical cases and relevant knowledge articles. If the agent doesn't do it by itself, send:

   ```
   First get the ticket, A. Datum Corporation's profile and procedures, the most similar historical tickets and the knowledge article they point to, and the available Backup and Recovery technicians.
   ```

   Expect calls to **get_ticket**, **get_customer** (which returns A. Datum's procedures, including **CUST-019-PR3**), the knowledge index (KB0023 and its historical tickets), and **list_technicians**. Read tools run without a prompt.

1. Have it state a recommendation and name the sources behind it:

   ```
   State your recommendation for TCK-10514 and the sources behind each part of it, before you change anything.
   ```

   **Expected results:** category **Backup and Recovery**, priority **P3**, assign to **Priya Raman** (TECH-01); sources **KB0023**, historical tickets such as **TCK-10004** and **TCK-10035**, and procedure **CUST-019-PR3** (the vault increase needs the customer's written approval and a quote from the account manager, Owen Fletcher).

1. Have it carry out that recommendation through a write tool, with approval, in the same exchange:

   ```
   Go ahead: triage TCK-10514 and assign it as you recommended.
   ```

   Approve **triage_ticket** after you check the category, the priority `3` and a reason that cites KB0023, and approve **assign_ticket** after you check the technician.

   > **[SCREENSHOT PENDING: E4T3S4 | Approval prompt for triage_ticket on TCK-10514 with a reason that cites KB0023 | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Verify the resulting state of the ticket in the Service Desk app. Open **TCK-10514**:

   | Column | Expected value |
   |---|---|
   | **Category** | Backup and Recovery |
   | **Priority** | P3 Medium |
   | **SLA Target** | 32 business hours (Silver, P3), with **SLA Due On** and **SLA Calculated On** set |
   | **Assigned Technician** | Priya Raman |
   | **Status** | In Progress |
   | **Last Correlation ID** | The correlation identifier of the last write |

   Under **Related** > **Ticket Notes**, two audit notes record the triage and the assignment, each with the reason, who asked and its correlation identifier. The ticket no longer appears in the **Untriaged Tickets** view.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Grounded action on the new incident" is registered (validation-scripts/README.md). -->

## Task 4: Tighten a Tool Boundary

In this task, you will tighten one limit and redeploy under time pressure. The baseline already validates its inputs.

1. Review the change: reduce the maximum limit argument of get_open_tickets from 50 to 20. In Visual Studio Code, open `src/servicedesk_mcp/policy.py`. `MAX_OPEN_TICKETS_LIMIT = 50` is published as the maximum of the `limit` argument of **get_open_tickets** (in `tools_read.py`, `le=policy.MAX_OPEN_TICKETS_LIMIT`), so a larger value is rejected before the tool runs. See the current boundary:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_open_tickets @{ limit = 25 }
   ```

   The call succeeds and returns 25 tickets ranked by SLA risk.

1. Update the MCP server. In `policy.py`, change the limit, and in `src/servicedesk_mcp/__init__.py`, bump the version:

   ```python
   MAX_OPEN_TICKETS_LIMIT = 20
   ```

   ```python
   __version__ = "2.0.2"
   ```

   Save both files.

1. Build and redeploy to your team's MCP server:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag v2-0-2
   ```

   Wait until the script reports version `2.0.2` on the new revision.

1. Confirm a call above the new limit is rejected with a structured error. Run the same call again:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 get_open_tickets @{ limit = 25 }
   ```

   The result shows `isError: True` and `INVALID_ARGUMENT`, with a violation for the argument `limit`: *Input should be less than or equal to 20*, the constraint `le: 20` and the value `25` you sent. `Show-McpServerLog.ps1` shows the call with **Outcome** `rejected`, and no Dataverse call. In the playground, a new chat asking for "the 25 open tickets closest to breach" now gets at most 20; the agent reads the new maximum from the tool's schema.

### Expected results

- [ ] `limit = 25` succeeded on version 2.0.1 and is rejected on version 2.0.2
- [ ] The error is `INVALID_ARGUMENT` and names `limit` and the maximum of 20
- [ ] The tool invocation log shows the rejected call

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Tool boundary tightened" is registered (validation-scripts/README.md). -->

## Task 5: Design and Add a Scoped Tool

In this task, you will design one new tool. MCP tool design is part of what your team is evaluated on.

1. Choose one new action, for example escalating a ticket or linking a knowledge article. Two good candidates, both scoped to one change on one ticket:

   | Tool | What it does | Columns it changes |
   |---|---|---|
   | `escalate_ticket` | Records an escalation to an L3 specialist, the vendor or the customer's account manager | **Escalated**, **Escalation Level**, **Escalated On**, **Escalation Reason** |
   | `link_knowledge_article` | Sets the knowledge article that resolves a ticket | **Related Article** |

   The repository already supports both changes: `repo.update_ticket` accepts the escalation columns, and `article_id` for the related article.

1. Define its description, input schema, output schema, required permission and whether it needs approval. In **Lab notes.txt**, next to **Your scoped tool**, write down:

   - **Description:** what it does, when to use it, and what it never does (for example, an agent never declares a **Major Incident**; a person does, through runbook RB-009)
   - **Input schema:** typed arguments with patterns, allowed values and lengths, for example `ticket_number` with the `TicketNumber` pattern, `level` limited to `L3 Specialist`, `Vendor` and `Account Manager`, and a `reason` of 10 to 500 characters
   - **Output schema:** the same shape as the other ticket-changing tools: `ticket_number`, `changes`, `audit_note`, `ticket`, and the `correlation_id`
   - **Required permission:** for example *Write on spk_ticket; Create and Append on spk_ticketnote, Append To on spk_ticket (audit note)*
   - **Approval:** it changes the system of record, so approval is required

   `TOOLS.md`, section **Adding a tool**, has the checklist.

1. Implement and redeploy it, keeping read and write operations in separate tools.

   - In `src/servicedesk_mcp/tools_write.py`, add the tool inside `register()`, after `add_ticket_note`, following the pattern of `set_ticket_priority`: decorate it with `@mcp.tool(annotations=WRITE, meta=write_meta(...))`, call `require_user`, validate the reason with `policy.validate_reason`, `load` the ticket, call `repo.update_ticket` with only the columns your tool changes, write an `audit_note`, and return `ok(audited({...}))`. Wrap the body in `telemetry.ToolCallLog` and call `log.fail(failure.code)` on failure. Don't add reads to the tool beyond loading the ticket; the agent already has read tools.
   - Add your tool to `TOOLS.md` with its input and output schema, permission and approval.
   - Bump `__version__` to `"2.0.3"` and deploy:

     ```powershell
     .\scripts\Deploy-McpServer.ps1 -Tag v2-0-3
     ```

   > **Note:** A reference implementation of `escalate_ticket` is in `C:\LabFiles\solutions\exercise-4-task-5`. Design your own first, then compare. If you run short of time, its `README.md` says how to apply it.

1. Call it from your agent and confirm the result in the Service Desk app. Start a new chat, so the agent reads the tool list again, and send a request for your tool. For `escalate_ticket`:

   ```
   Escalate TCK-10514 to the Account Manager: the vault increase needs Owen Fletcher's quote and the customer's written approval under procedure CUST-019-PR3.
   ```

   Your new tool isn't on the list of tools that never need approval, so the playground asks you: check the arguments and select **Approve**. In the Service Desk app, open **TCK-10514**: the **Escalation** section shows **Escalated** set to **Escalated**, **Escalation Level** **Account Manager**, **Escalated On** and your reason, and the ticket appears in the **Escalated Tickets** view. A new audit note records the escalation with its correlation identifier.

   > **[SCREENSHOT PENDING: E4T5S4 | TCK-10514 Escalation section after the escalate_ticket call | source: capture]**

### Expected results

- [ ] Your design names the description, input schema, output schema, permission and approval
- [ ] The tool is a separate write tool with validated inputs, and the server reports version 2.0.3
- [ ] The playground asked for approval, and the change is visible in the Service Desk app

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Scoped tool added and called" is registered (validation-scripts/README.md). -->

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **A write tool returns `USER_CONTEXT_REQUIRED`:** the call came through the diagnostics API, which carries no signed-in user. Make changes through the agent.
- **A write tool returns `PRIORITY_NOT_ALLOWED`:** the agent asked for P1. An agent may set P2, P3 or P4 only; a person declares a P1 through the major incident process.
- **The playground doesn't ask for approval and nothing happens:** start a new chat; the agent reads its tools when a chat starts.
- **Your new tool doesn't appear:** check that the deploy script reported version 2.0.3, then start a new chat. Run `.\scripts\Invoke-McpTool.ps1 -List` to see whether the server publishes it.
- **`Deploy-McpServer.ps1` times out:** the previous revision keeps serving traffic. Run `.\scripts\Show-McpServerLog.ps1 -All` to find the error, usually indentation, fix it and deploy again.

</details>

## Summary

In this exercise, you have completed the following:

- Reviewed the write tools and their sensitivity, approved one change and declined another, and confirmed both in the app and the tool invocation log
- Kept a customer-visible reply and an internal note apart, and saw the agent keep internal content out of a customer draft
- Chained customer context, history and knowledge into an approved triage and assignment of the new incident
- Tightened the get_open_tickets limit from 50 to 20, redeployed, and saw the schema reject a larger value
- Designed, built and deployed a new scoped write tool, and used it with approval

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
