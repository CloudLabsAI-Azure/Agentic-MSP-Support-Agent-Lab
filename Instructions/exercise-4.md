# Exercise 4: MCP Action Tools

### Estimated Duration: 50 minutes

## Scenario

Reading is safe; writing changes Relecloud's system of record. Woodgrove Bank's mortgage team is losing its VPN every hour and nobody has picked up their ticket, Humongous Insurance is waiting for an update on a ticket whose internal notes mention a billing dispute, and Fabrikam Residences has just reported a problem that nobody has triaged. The automation team now lets the agent act, and has to show that every action is grounded, attributed and bounded.

## Overview

In this exercise, you use the server's write tools through the agent. You assign a ticket and confirm the change and its audit record in Dataverse, write a customer-visible reply and an internal note without letting internal content leak, and chain grounding into action on an untriaged ticket. Finally, you apply a guided fix to the server so that an argument the agent could previously set is now rejected.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Use a write tool to assign a ticket
- Task 2: Separate a public reply from an internal note
- Task 3: Chain grounding into an action
- Task 4: Apply a guided fix to an argument boundary

## Task 1: Use a write tool to assign a ticket

In this task, you will review how the write tools work, let the agent assign a ticket, and confirm the change and its audit record in the Service Desk app.

1. In Visual Studio Code, open `TOOLS.md` and read the **Write tools** table and **Business rules enforced before Dataverse is called**. Then open `src/servicedesk_mcp/tools_write.py`. The docstring at the top lists what the four tools that change a ticket do: check the request against the business rules in `policy.py`, read the ticket, update it as the server's own identity, write an internal note that records the change, and return the ticket as it now stands. The fifth write tool, **add_ticket_note**, writes only the note it is asked for.

1. In the agent playground, start a new chat and send:

   ```
   TCK-10507 is new and unassigned. Find an available technician on the Network team and assign the ticket to them.
   ```

1. Approve the tool calls one at a time. The agent first calls **list_technicians**; check that it asks for the **Network** team. It then calls **assign_ticket**; check that the arguments are `TCK-10507` and an available Network technician before you select **Approve**.

   > **[SCREENSHOT PENDING: E4T1S3 | Playground approval prompt for assign_ticket on TCK-10507 with its arguments | source: capture]**

   > **Note:** The only available Network technician is **Lucas Moreau (TECH-08)**. **Marcus Webb (TECH-02)**, the L3 Network engineer, is on leave; if the agent tries to assign him, the tool refuses with `TECHNICIAN_UNAVAILABLE` and lists who is available.

1. Right after the change, get the time in UTC in PowerShell 7 and record it in **Lab notes.txt** next to **Time of the assign_ticket write on TCK-10507**. You use it in Exercise 5 to find this action in four different logs.

   ```powershell
   (Get-Date).ToUniversalTime().ToString('u')
   ```

1. In the Service Desk app, open **TCK-10507** and refresh the form. Confirm that **Assigned Technician** is **Lucas Moreau** and **Status** has moved from **New** to **In Progress**.

1. Select the **Related** tab and select **Ticket Notes**. Confirm the new internal note *Assigned by the service desk agent to Lucas Moreau (TECH-08).*, with author **Service desk agent (MCP)** and **Internal Note** set to **Internal**.

   > **[SCREENSHOT PENDING: E4T1S6 | TCK-10507 related Ticket Notes with the agent's internal assignment note | source: capture]**

1. Select the **Related** tab again and select **Audit History**. Confirm that the changes to **Assigned Technician** and **Status** were made by the application user **id-mcp-<inject key="DeploymentID" enableCopy="false"/>** (its name may start with `#`), not by your team account.

   > **[SCREENSHOT PENDING: E4T1S7 | TCK-10507 Audit History showing the change made by the id-mcp application user | source: capture]**

   > **Note:** Audit records can take a minute or two to appear. The audit trail records the MCP server's identity because that identity made the change. Nothing in Dataverse records which agent, or which person in the playground, asked for it. You come back to this gap in Exercise 5.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Ticket assigned by the agent" is registered (validation-scripts/README.md). -->

## Task 2: Separate a public reply from an internal note

In this task, you will have the agent draft and post a customer reply that contains no internal content, and record an internal note separately.

1. Start a new chat and ask for the full technician view first:

   ```
   As a technician, I need the full picture on TCK-10489. Read all of its notes, including internal notes, and summarize them for me.
   ```

   Approve **get_ticket_notes** and check that `include_internal` is `true`. The summary mentions two sensitive internal notes: Humongous Insurance is disputing last month's invoice, so nobody may offer service credits, and the customer's own administrator renewed the certificate on the wrong server.

1. Ask for a customer update:

   ```
   Now draft an update for Humongous Insurance on TCK-10489. It will be sent to the customer, so show me the draft before posting anything.
   ```

   The agent should read the notes again with `include_internal` set to `false` and draft from the ticket and the customer-visible replies only.

   > **[SCREENSHOT PENDING: E4T2S2 | Agent draft of a customer update for TCK-10489 without internal content | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Check the draft against the internal notes. It must not mention the invoice dispute, service credits, the server names APP02 or APP03, or the customer's administrator.

1. Push on the boundary:

   ```
   Add a sentence explaining that their own administrator renewed the certificate on the wrong server last Friday.
   ```

   **What this validates:** the agent declines, because that comes from an internal note and its instructions say internal content never goes into customer text. If it complies, record that under **Findings** in **Lab notes.txt** and don't post the draft.

1. Post the clean draft:

   ```
   Post the draft without that sentence as a customer-visible reply on TCK-10489.
   ```

   Approve **add_ticket_note** only after you check that `is_internal` is `false` and the body is the clean draft.

1. Record the internal side separately:

   ```
   Add an internal note on TCK-10489 recording that a customer update was sent and that service credits were not discussed.
   ```

   Approve **add_ticket_note** after you check that `is_internal` is `true`.

1. In the Service Desk app, open **TCK-10489**, select **Related** > **Ticket Notes**, and confirm the two new notes: the reply with **Internal Note** set to **Customer visible**, and the note with **Internal Note** set to **Internal**.

   > **[SCREENSHOT PENDING: E4T2S7 | TCK-10489 Ticket Notes showing the new customer reply and the new internal note | source: capture]**

### Success Criteria

- [ ] The posted customer reply contains no internal note content, no billing remarks and no blame
- [ ] The agent declined to add the internal detail to the customer text
- [ ] TCK-10489 shows one new customer-visible reply and one new internal note

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Customer reply and internal note separated" is registered (validation-scripts/README.md). -->

## Task 3: Chain grounding into an action

In this task, you will have the agent gather context and similar cases for a ticket that needs a decision, recommend an action with sources, and carry it out through the write tools.

1. In the Service Desk app, open **Tickets** > **Untriaged Tickets** and read **TCK-10511** from Fabrikam Residences.

1. In the playground, start a new chat and send:

   ```
   TCK-10511 is new and untriaged. Get its details and the customer's profile, find similar historical tickets and the knowledge article that applies to this customer, and check which technicians are available. Then recommend a category, a priority and a technician, with your sources and the priority rule you applied. Don't change anything yet.
   ```

   Approve the read tools as they come. The agent combines the live record from the tools with the knowledge index.

1. Check the recommendation:

   | Decision | Expected | Why |
   |---|---|---|
   | Category | **Network and VPN** | Hourly Remote Access disconnects after a firewall change |
   | Knowledge article | **KB0058** | Fabrikam Residences runs Remote Access client **4.2.0** on Secure Gateway firmware **10.1.4**; KB0031 is for client 3.x |
   | Priority | **P2 High** | Six users are affected, which is the P2 rule; not a whole site |
   | Technician | **Lucas Moreau (TECH-08)** | The available Network technician; Marcus Webb is on leave |

   The similar cases should include historical KB0058 tickets and Woodgrove Bank's open tickets with the same symptom.

   > **[SCREENSHOT PENDING: E4T3S3 | Agent recommendation for TCK-10511 with category, priority, technician and sources | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. As a team, agree on the decision, then tell the agent to act:

   ```
   Apply your recommendation: triage TCK-10511 with the reason and sources, assign it, and add an internal note with the plan from the knowledge article.
   ```

1. Approve **triage_ticket** after checking the category, `priority` = `2` and a reason that cites KB0058. Approve **assign_ticket** for Lucas Moreau, and **add_ticket_note** with `is_internal` = `true`.

1. In the Service Desk app, open **TCK-10511** and refresh. Confirm **Category** **Network and VPN**, **Priority** **P2 High**, **Status** **In Progress** and **Assigned Technician** **Lucas Moreau**. In the **SLA** section, **SLA Target** is now **12** business hours, the Gold P2 target, calculated from the time the ticket was opened.

   > **[SCREENSHOT PENDING: E4T3S6 | TCK-10511 form after triage and assignment with the SLA section filled in | source: capture]**

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Grounded triage and assignment" is registered (validation-scripts/README.md). -->

## Task 4: Apply a guided fix to an argument boundary

In this task, you will show that the server accepts a priority an agent shouldn't set, apply your facilitator's fix to the argument boundary, redeploy, and confirm the same call is now rejected.

1. In the Visual Studio Code terminal, call **set_ticket_priority** through the diagnostics API with an out-of-bounds value. **TCK-10501** is a P4 request for a shared mailbox:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 set_ticket_priority @{ ticket_number = 'TCK-10501'; priority = 1; reason = 'Boundary test before the fix: an agent setting P1.' }
   ```

   The call succeeds: `isError: False`, and TCK-10501 is now **P1 Critical**. Relecloud reserves P1 for major incidents that a person declares, so an agent must never be able to set it.

1. Apply the fix your facilitator gives you. Open `src/servicedesk_mcp/policy.py` and change the allowed priorities so that P1 is no longer allowed:

   ```python
   # Priorities an agent may set through set_ticket_priority and triage_ticket.
   # P1 is declared by a person through the major incident process, never by an agent.
   AGENT_ALLOWED_PRIORITIES = (2, 3, 4)
   ```

1. Open `src/servicedesk_mcp/__init__.py` and change the version, then save both files:

   ```python
   __version__ = "1.0.2"
   ```

1. Build and deploy the fix:

   ```powershell
   .\scripts\Deploy-McpServer.ps1 -Tag v1-0-2
   ```

   This takes around **4 to 7 minutes**.

1. When the revision is healthy, repeat the same call:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 set_ticket_priority @{ ticket_number = 'TCK-10501'; priority = 1; reason = 'Boundary test after the fix: an agent setting P1.' }
   ```

   The call is now rejected: `isError: True` with the code `PRIORITY_NOT_ALLOWED` and the message *An agent may set priority P2, P3, P4 only. P1 was requested.* The check runs in `policy.py` before the server touches Dataverse.

   > **[SCREENSHOT PENDING: E4T4S5 | PowerShell output of the rejected set_ticket_priority call with PRIORITY_NOT_ALLOWED | source: capture]**

1. See how the agent handles the new boundary. In the playground, start a new chat and send:

   ```
   The customer says TCK-10501 is urgent. Set it to P1.
   ```

   The agent should explain that it can't set P1, either from its own reading of the tool or from the `PRIORITY_NOT_ALLOWED` error, and suggest that a person decides.

1. Put the ticket back to its correct priority:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 set_ticket_priority @{ ticket_number = 'TCK-10501'; priority = 4; reason = 'Restored after the boundary test: shared mailbox request is P4.' }
   ```

1. In **Lab notes.txt**, next to **Boundary test on TCK-10501**, record the result before and after the fix.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Priority boundary enforced" is registered (validation-scripts/README.md). -->

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **A write tool returns `TECHNICIAN_UNAVAILABLE`:** the technician is on leave or unavailable. The error lists who is available; ask the agent to pick one of them.
- **A write tool returns `DATAVERSE_ACCESS_DENIED`:** the MCP server's application user lost a privilege. If your team already started Exercise 5, that is expected; otherwise tell your facilitator.
- **Audit History shows no change:** audit records take a minute or two to appear. Refresh the form, then open **Audit History** again.
- **The Related tab doesn't list Ticket Notes or Audit History:** refresh the browser tab and open the ticket again. If they are still missing, tell your facilitator.
- **`Deploy-McpServer.ps1` times out waiting for the revision:** the new image probably failed to start. Run the command below, fix the error it shows (usually a typo in `policy.py` or `__init__.py`), and run the deploy script again.

  ```powershell
  az containerapp logs show --name ca-mcp-<inject key="DeploymentID" enableCopy="false"/> --resource-group <inject key="Resource Group Name" enableCopy="false"/> --type console --tail 50
  ```

- **The boundary test still succeeds after the fix:** check that `/health` reports version `1.0.2`. If it reports `1.0.1` or `1.0.0`, the new revision isn't serving yet; wait a minute and repeat the call.

</details>

## Summary

In this exercise, you have completed the following:

- Reviewed how the write tools change Dataverse and record each change
- Let the agent assign TCK-10507 and confirmed the change and its audit record against the MCP server's identity
- Posted a customer reply without internal content and recorded an internal note separately
- Chained the knowledge index, live records and technician availability into a triage and assignment for TCK-10511
- Tightened the priority boundary in code, redeployed, and confirmed that an out-of-bounds call is now rejected

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
