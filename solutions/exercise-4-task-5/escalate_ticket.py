    # ================================================================== Exercise 4 Task 5
    # Reference solution: paste this block inside register() in src/servicedesk_mcp/tools_write.py,
    # after add_ticket_note, with the same indentation (four spaces). It needs no new imports.

    @mcp.tool(annotations=WRITE, meta=write_meta("escalation flag, level, time and reason", "medium", TICKET_WRITE))
    async def escalate_ticket(
        ctx: Context,
        ticket_number: TicketNumber,
        level: Annotated[Literal["L3 Specialist", "Vendor", "Account Manager"],
                         Field(description="Who the ticket is escalated to. A Major Incident is declared by a person "
                                           "through runbook RB-009, never by the agent.")],
        reason: Reason,
    ) -> CallToolResult:
        """Escalate a ticket to an L3 specialist, the vendor or the customer's account manager.

        Requires approval. Records the escalation level, time and reason on the ticket and
        writes an internal note. It doesn't change the priority, the status or the assigned
        technician, and it never declares a Major Incident: a person does that through the
        major incident process (runbook RB-009).
        """
        telemetry.bind_from_context(ctx)
        args = {"ticket_number": ticket_number, "level": level, "reason": reason}
        with telemetry.ToolCallLog("escalate_ticket", args) as log:
            try:
                require_user("escalate_ticket")
                reason_text = policy.validate_reason(reason)
                ticket = await load(ticket_number)
                if ticket["status"] in ("Resolved", "Closed"):
                    raise ToolFailure(code="TICKET_CLOSED",
                                      message=f"{ticket_number} is {ticket['status']}; a closed ticket isn't escalated.",
                                      hint="Reopen the ticket with update_ticket_status first, or ask the user.")
                now = datetime.now(timezone.utc).replace(microsecond=0)
                changes = {"spk_isescalated": True, "spk_escalationlevel": choices.ESCALATION_LEVEL_VALUE[level],
                           "spk_escalatedon": now, "spk_escalationreason": reason_text}
                await repo.update_ticket(ticket["id"], changes)
                log.record = {"table": "spk_ticket", "id": ticket["id"], "columns": sorted(changes)}
                note_code = await audit_note(ticket, f"Escalated by the service desk agent to {level}. Reason: {reason_text}")
                updated = await load(ticket_number)
                return ok(audited({"ticket_number": ticket_number,
                                   "changes": {"escalated_to": level, "escalated_on": updated["escalation"]["escalated_on"]},
                                   "audit_note": note_code, "ticket": ticket_summary(updated)}))
            except ToolFailure as failure:
                log.fail(failure.code)
                return failed(failure)
