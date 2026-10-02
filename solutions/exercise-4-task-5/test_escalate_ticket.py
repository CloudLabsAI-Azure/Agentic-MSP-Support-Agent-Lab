"""Tests for the reference escalate_ticket tool. Copy this file into the MCP server's tests/
folder after you add the tool; run with: python -m pytest tests/test_escalate_ticket.py"""
from __future__ import annotations

from .conftest import CORRELATION_ID, OPERATOR_HEADERS


def test_escalate_ticket_is_an_approval_gated_write_tool(mcp):
    tools = {t["name"]: t for t in mcp.rpc("tools/list").json()["result"]["tools"]}
    tool = tools["escalate_ticket"]
    assert tool["annotations"]["readOnlyHint"] is False
    assert tool["_meta"]["relecloud/approval"] == "required"
    assert set(tool["inputSchema"]["properties"]["level"]["enum"]) == {"L3 Specialist", "Vendor", "Account Manager"}


def test_escalate_ticket_records_the_escalation_and_an_audit_note(mcp):
    is_error, body = mcp.call("escalate_ticket", ticket_number="TCK-10514", level="Account Manager",
                              reason="Vault increase needs the account manager's quote (CUST-019-PR3).")
    assert not is_error, body
    ticket = mcp.repo.tickets["TCK-10514"]
    assert ticket["escalation"]["escalated"] is True
    assert ticket["escalation"]["level"] == "Account Manager"
    assert ticket["last_correlation_id"] == CORRELATION_ID
    assert mcp.repo.notes[ticket["id"]][-1]["is_internal"]


def test_major_incident_is_not_a_choice(mcp):
    is_error, body = mcp.call("escalate_ticket", ticket_number="TCK-10514", level="Major Incident",
                              reason="Trying to declare a major incident from the agent.")
    assert is_error and body["error"]["code"] == "INVALID_ARGUMENT"


def test_escalation_needs_a_signed_in_user(mcp):
    is_error, body = mcp.call("escalate_ticket", headers=OPERATOR_HEADERS, ticket_number="TCK-10514",
                              level="Vendor", reason="Attempted through the diagnostics API.")
    assert is_error and body["error"]["code"] == "USER_CONTEXT_REQUIRED"
