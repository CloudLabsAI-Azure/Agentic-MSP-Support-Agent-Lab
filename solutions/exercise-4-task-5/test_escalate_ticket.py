r"""Tests for the reference escalate_ticket tool (Exercise 4 Task 5).

Copy this file into the MCP server's tests folder after you add the tool, then run:
    .\.venv\Scripts\python.exe -m pytest tests\test_escalate_ticket.py
The ticket and the level come from the seed manifest (scenario write_targets.escalation_tool).
"""
from __future__ import annotations

import jsonschema

from .conftest import DIAG, SCENARIOS, SENIOR, WRITE, new_id

TARGET = SCENARIOS["write_targets"]["escalation_tool"]
CLOSED_TICKET = SCENARIOS["kb0023_history"]["tickets"][0]["ticket"]


def fresh() -> dict:
    return {**WRITE, "x-correlation-id": new_id()}


def test_escalate_ticket_is_a_write_tool_that_needs_approval(mcp):
    tool = mcp.tools("write")["escalate_ticket"]
    assert "escalate_ticket" not in mcp.tools("read")
    assert tool["annotations"]["readOnlyHint"] is False
    assert tool["_meta"]["relecloud/approval"] == "required" and tool["_meta"]["relecloud/endpoint"] == "/write/mcp"
    assert set(tool["inputSchema"]["properties"]["level"]["enum"]) == {"L3 Specialist", "Vendor", "Account Manager"}
    assert "anyOf" not in str(tool["inputSchema"]) and "anyOf" not in str(tool["outputSchema"])
    assert "escalate_ticket" in mcp.http.get("/health").json()["tools"]["write"]


def test_escalation_is_recorded_with_an_audit_note_and_an_agent_action(mcp):
    headers = fresh()
    is_error, body = mcp.write("escalate_ticket", headers=headers, ticket_number=TARGET["ticket"], level=TARGET["level"],
                               reason="The vault increase needs the account manager's quote and the customer's approval.")
    assert not is_error, body
    jsonschema.validate(body, mcp.tools("write")["escalate_ticket"]["outputSchema"])
    assert body["changes"]["escalated_to"] == TARGET["level"] and body["changes"]["previous_level"] == "none"
    ticket = mcp.repo.tickets[TARGET["ticket"]]
    assert ticket["escalation"]["escalated"] is True and ticket["escalation"]["level"] == TARGET["level"]
    assert ticket["last_correlation_id"] == headers["x-correlation-id"]
    note = mcp.repo.notes[ticket["id"]][-1]
    assert note["is_internal"] and headers["x-correlation-id"] in note["body"]
    action = mcp.repo.agent_actions[-1]
    assert action["tool"] == "escalate_ticket" and action["outcome"] == "Succeeded"
    assert action["authorization"] == "Allowed" and action["user_name"] == SENIOR["x-user-name"]


def test_the_same_escalation_twice_is_a_duplicate(mcp):
    arguments = {"ticket_number": TARGET["ticket"], "level": "Vendor", "reason": "Vendor fix needed for the agent."}
    mcp.write("escalate_ticket", headers=fresh(), **arguments)
    is_error, body = mcp.write("escalate_ticket", headers=fresh(), **arguments)
    assert not is_error and body["duplicate"] is True
    assert mcp.repo.agent_actions[-1]["outcome"] == "Duplicate, first result returned"


def test_major_incident_is_not_a_choice(mcp):
    is_error, body = mcp.write("escalate_ticket", headers=fresh(), ticket_number=TARGET["ticket"], level="Major Incident",
                               reason="Trying to declare a major incident from the agent.")
    assert is_error and body["error"]["code"] == "INVALID_ARGUMENT"
    assert mcp.repo.agent_actions[-1]["authorization"] == "Rejected by the MCP server"


def test_closed_tickets_are_not_escalated(mcp):
    is_error, body = mcp.write("escalate_ticket", headers=fresh(), ticket_number=CLOSED_TICKET, level="Vendor",
                               reason="Escalating a ticket that is already closed.")
    assert is_error and body["error"]["code"] == "TICKET_CLOSED"


def test_escalation_needs_a_signed_in_user(mcp):
    is_error, body = mcp.call("escalate_ticket", endpoint="diagnostics", headers={**DIAG, "x-correlation-id": new_id()},
                              ticket_number=TARGET["ticket"], level="Vendor", reason="Attempted through the diagnostics API.")
    assert is_error and body["error"]["code"] == "USER_CONTEXT_REQUIRED"
