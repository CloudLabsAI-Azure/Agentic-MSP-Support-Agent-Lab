# Reference solution: Exercise 4 Task 5, a scoped `escalate_ticket` tool

This folder holds one reference answer for Exercise 4 Task 5. It is not part of the lab guide pages: teams design their own tool first and compare afterwards. Provisioning copies the folder to `C:\LabFiles\solutions\exercise-4-task-5` on the lab VM.

## Design

| Element | Decision |
|---|---|
| **Action** | Record an escalation on one ticket. One action, one table, no reads beyond loading the ticket. |
| **Description** | Escalate a ticket to an L3 specialist, the vendor or the customer's account manager. Requires approval. Doesn't change priority, status or assignment, and never declares a Major Incident (a person does, through runbook RB-009). |
| **Input schema** | `ticket_number` (pattern `^TCK-\d{5}$`), `level` (one of `L3 Specialist`, `Vendor`, `Account Manager`), `reason` (10 to 500 characters) |
| **Output schema** | `ticket_number`, `changes` {`escalated_to`, `escalated_on`}, `audit_note`, `ticket` (TicketSummary), `correlation_id`; on failure the standard error object |
| **Columns changed** | **Escalated**, **Escalation Level**, **Escalated On**, **Escalation Reason**, and **Last Correlation ID** |
| **Required permission** | Write on `spk_ticket`; Create and Append on `spk_ticketnote`, Append To on `spk_ticket` (audit note). The server's **Service Desk Agent Write** role already holds them, and the signed-in user's role must too. |
| **Approval** | Required (`write_meta`). The tool isn't on the agent's list of tools that never need approval, so the playground asks. |
| **Errors** | `INVALID_ARGUMENT` (schema, including `Major Incident`), `USER_CONTEXT_REQUIRED`, `TICKET_NOT_FOUND`, `TICKET_CLOSED`, `DATAVERSE_ACCESS_DENIED` |

## Apply it

1. Open `C:\LabFiles\mcp-server\src\servicedesk_mcp\tools_write.py` in Visual Studio Code.
1. Paste the whole of `escalate_ticket.py` at the end of the file, inside `register()`, after `add_ticket_note`. Keep its indentation: the `@mcp.tool` line starts with four spaces. It needs no new imports.
1. Set `__version__ = "2.0.3"` in `src/servicedesk_mcp/__init__.py`.
1. Optionally, copy `test_escalate_ticket.py` into `tests\` and run the tests locally first (`.\.venv\Scripts\python.exe -m pytest tests`, after `.\scripts\Start-LocalServer.ps1` has created the virtual environment once).
1. Deploy: `.\scripts\Deploy-McpServer.ps1 -Tag v2-0-3`.

## Try it

```
Escalate TCK-10514 to the Account Manager: the vault increase needs Owen Fletcher's quote and the customer's written approval under procedure CUST-019-PR3.
```

Approve the call. TCK-10514 then shows the escalation in its **Escalation** section and appears in the **Escalated Tickets** view.
