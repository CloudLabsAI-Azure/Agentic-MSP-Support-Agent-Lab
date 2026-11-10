# Reference solution: Exercise 4 Task 5, a scoped `escalate_ticket` tool

This folder holds one reference answer for Exercise 4 Task 5, for MCP server release 3.0.0. It is
not part of the lab guide pages: design your own tool first and compare afterwards. Provisioning
copies the folder to `C:\LabFiles\solutions\exercise-4-task-5` on your lab VM.

The task's other example, linking a knowledge article, is already in the baseline catalog as
`link_kb_article`, so this answer adds the escalation.

## Design

| Element | Decision |
|---|---|
| **Action** | Record an escalation on one open ticket. One action, one table, no reads beyond loading the ticket. |
| **Description** | Escalate an open ticket to an L3 specialist, the vendor or the customer's account manager. Requires approval. Doesn't change priority, status or assignment, and never declares a Major Incident (a person does, through runbook RB-009). |
| **Endpoint and approval** | `@catalogue.write_tool` publishes it on the write endpoint (`/write/mcp`) only. The agent's `servicedesk-write` tool requires approval for every tool on that endpoint, so the playground asks before every call. Nothing else to configure. |
| **Input schema** | `ticket_number` (pattern `^TCK-\d{5}$`), `level` (one of `L3 Specialist`, `Vendor`, `Account Manager`), `reason` (10 to 500 characters). No optional values, so no `anyOf`. |
| **Output schema** | `ESCALATE_TICKET_OUTPUT`: the shared write envelope (`ok`, `correlation_id`, `error`, `duplicate`, `duplicate_of`, `warnings`), plus `ticket_number`, `changes` {`escalated_to`, `escalated_on`, `previous_level`}, `audit_note` and `ticket` (the ticket summary) |
| **Columns changed** | **Escalated**, **Escalation Level**, **Escalated On**, **Escalation Reason**, and **Last Correlation ID** |
| **Required permission** | Write on `spk_ticket`; Create and Append on `spk_ticketnote`, Append To on `spk_ticket` (audit note); Create on `spk_agentaction` for the server's application user (Agent Action row). The server's **Service Desk Agent Write** role already holds them, and the signed-in user's role must hold the ticket and note privileges too. |
| **Controls you get from the catalog** | Input validation, `USER_CONTEXT_REQUIRED` without a signed-in user, the 10-minute duplicate guard, an Agent Action row for every attempt, the audit note, the correlation ID in the result and one log line per call |
| **Errors** | `INVALID_ARGUMENT` (schema, including `Major Incident`), `USER_CONTEXT_REQUIRED`, `TICKET_NOT_FOUND`, `TICKET_CLOSED`, `DATAVERSE_ACCESS_DENIED` |

## Apply it

1. Open `C:\LabFiles\mcp-server\src\servicedesk_mcp\tools_write.py` in Visual Studio Code.
1. Paste the whole of `escalate_ticket.py` at the end of the file, inside `register()`, after
   `add_public_reply`. Keep its indentation: the lines start with four spaces. It needs no new
   imports.
1. Set `__version__ = "3.0.3"` in `src/servicedesk_mcp/__init__.py`.
1. Copy `test_escalate_ticket.py` into `tests\` and run the tests locally first:
   `.\.venv\Scripts\python.exe -m pytest` (run `.\scripts\Start-LocalServer.ps1` once to create the
   virtual environment). Every test must pass, the new ones included.
1. Optionally, try it on your machine: start `.\scripts\Start-LocalServer.ps1`, then in a second
   terminal run
   `.\scripts\Invoke-McpTool.ps1 escalate_ticket @{ ticket_number = 'TCK-10561'; level = 'Account Manager'; reason = 'The vault increase needs the account manager.' } -Endpoint http://localhost:8000 -LocalUser`.
1. Deploy: `.\scripts\Deploy-McpServer.ps1`. The image is tagged `3.0.3`, the version you set.
1. Document it: add a `### escalate_ticket` section under **Write tools** in `TOOLS.md`, with its
   description, arguments, output and permission, as the other write tools have.

## Try it

```
Escalate TCK-10561 to the Account Manager: the vault increase needs the account manager's quote and the customer's written approval under the customer's change approval procedure.
```

Approve the call in the playground. TCK-10561 then shows the escalation in its **Escalation**
section and appears in the **Escalated Tickets** view; the ticket's notes have the audit note with
the correlation ID, and the Agent Action table has a Succeeded row for `escalate_ticket`. Ask the
same thing again within 10 minutes and approve it: the result says `duplicate` and nothing changes
twice.
