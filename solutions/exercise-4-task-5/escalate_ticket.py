    # ==== Exercise 4 Task 5: reference solution
    # Paste this block inside register() in src/servicedesk_mcp/tools_write.py, after add_public_reply,
    # with the same indentation (four spaces). It needs no new imports. The decorator publishes the
    # tool on the write endpoint (/write/mcp), so the agent asks for approval before every call, and
    # the catalogue adds the duplicate guard, the Agent Action row and the log line.
    ESCALATE_TICKET_OUTPUT = schemas.result({**schemas.WRITE_TICKET, "changes": schemas.obj({
        "escalated_to": schemas.string("The escalation level now recorded on the ticket."),
        "escalated_on": schemas.string("When the ticket was escalated (ISO 8601 UTC)."),
        "previous_level": schemas.string("The escalation level before, or none."),
    }, required=["escalated_to", "escalated_on"])}, "The ticket's new escalation.", write=True)

    @catalogue.write_tool(permission=TICKET_WRITE, changes="escalation flag, level, time and reason",
                          sensitivity="medium", output=ESCALATE_TICKET_OUTPUT)
    async def escalate_ticket(
        ctx: Context,
        ticket_number: TicketNumber,
        level: Annotated[Literal["L3 Specialist", "Vendor", "Account Manager"],
                         Field(description="Who the ticket is escalated to. A Major Incident is declared by a person "
                                           "through runbook RB-009, never by the agent.")],
        reason: Reason,
    ) -> dict[str, Any]:
        """Escalate an open ticket to an L3 specialist, the vendor or the customer's account manager.
        Requires approval.

        Records the escalation level, time and reason on the ticket and writes an internal audit
        note. It doesn't change the priority, the status or the assigned technician, and it never
        declares a Major Incident: a person does that through the major incident process (runbook
        RB-009). A Resolved or Closed ticket is refused (TICKET_CLOSED).
        """
        require_user("escalate_ticket")
        reason_text = policy.validate_reason(reason)
        ticket = await load_ticket(repo, ticket_number)
        if ticket["status"] in ("Resolved", "Closed"):
            raise ToolFailure(code="TICKET_CLOSED",
                              message=f"{ticket_number} is {ticket['status']}; a closed ticket isn't escalated.",
                              hint="Reopen the ticket with update_ticket_status first, or ask the user.")
        now = datetime.now(timezone.utc).replace(microsecond=0)
        previous = ticket["escalation"]["level"] or "none"
        updates = {"spk_isescalated": True, "spk_escalationlevel": choices.ESCALATION_LEVEL_VALUE[level],
                   "spk_escalatedon": now, "spk_escalationreason": reason_text}
        await repo.update_ticket(ticket["id"], updates)
        record_change(ticket, updates)
        return await changed(ticket, f"Escalated by the service desk agent to {level} (was {previous}). "
                                     f"Reason: {reason_text}",
                             {"escalated_to": level, "escalated_on": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                              "previous_level": previous})
