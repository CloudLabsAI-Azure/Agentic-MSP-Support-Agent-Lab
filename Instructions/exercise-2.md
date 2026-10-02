# Exercise 2: Ticket and Incident Intelligence

### Estimated Duration: 35 minutes

## Scenario

Relecloud's technicians don't need an agent that recites articles; they need one that spots the pattern in a new incident, sees what a customer's open queue really looks like, triages what arrived without a priority, and warns before an SLA is breached. Those are the four jobs that eat the third of handling time the service review measured.

## Overview

In this exercise, you use the grounded agent from Exercise 1 on four service desk jobs. You match an incident your facilitator gives you to historical tickets, summarize one customer's open issues, recommend triage for an untriaged ticket, and find the tickets closest to breaching their SLA. You check every answer against the Service Desk app. The agent still has only its knowledge index; it gets tools in Exercise 3.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Find similar incidents
- Task 2: Summarize open issues for a customer
- Task 3: Recommend a priority and category for a new ticket
- Task 4: Identify SLA risk

## Task 1: Find similar incidents

In this task, you will give the agent an incident it has never seen and ask it to find the closest historical tickets, explaining the similarity in more than shared keywords.

1. Your facilitator shares a new incident with your team. Copy its text.

   <details>
   <summary>If your facilitator hasn't shared an incident, use this one</summary>

   ```
   From the operations lead at a research consultancy: since Saturday the nightly protection job for our analytics file share has stopped creating new recovery points. The console says our cloud storage allowance has been used up. We copied a large research archive onto that share last week.
   ```

   </details>

1. In the agent playground, start a new chat and send the following prompt, then paste the incident text on the next line of the same message:

   ```
   Here is a new incident that is not in the Service Desk yet. Find the three historical tickets most similar to it. For each one, explain the similarity in terms of the symptom pattern, its timing, what changed just before it started, the product and versions involved, and how it was resolved, not just the words they share. Then tell me which knowledge article the matches point to and what I would need to confirm with the customer before following it. Incident:
   ```

   > **[SCREENSHOT PENDING: E2T1S2 | Agent answer listing three similar historical tickets with explained similarity | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Review the answer. A good answer explains why the tickets match in terms of the pattern, the trigger and the cause, not shared words (the incident may use none of the words in the matching tickets), and it says what is still unknown, such as a product version or a contract detail that decides between two articles.

1. Open one of the matched tickets in the Service Desk app: select its citation, or open **Tickets**, select the **All Tickets** view, and type the ticket number in the **Filter by keyword** box (it's labeled **Quick find** in some environments). Compare the ticket's **Resolution Summary** with what the agent said about it.

   > **[SCREENSHOT PENDING: E2T1S4 | Historical ticket form with its resolution summary in the Service Desk app | source: capture]**

### Success Criteria

- [ ] The agent returned three historical tickets, each with a ticket number and a citation
- [ ] Each explanation goes beyond shared words (pattern, timing, trigger, versions or resolution)
- [ ] The ticket you opened in the app matches what the agent said about its resolution
- [ ] The agent named what must be confirmed before choosing an article, instead of assuming it

## Task 2: Summarize open issues for a customer

In this task, you will ask for a summary of one customer's open tickets, grouped and checked for recurring issues, and confirm the count in the app.

1. Start a new chat and send:

   ```
   Summarize all open tickets for Woodgrove Bank. Group them by category and by urgency, show each ticket's number, status, priority and SLA remaining, and flag any issue that appears in more than one ticket.
   ```

1. Check the answer against the expected result. Woodgrove Bank has **6** open tickets:

   | Category | Ticket | Priority | Status | SLA remaining (business hours) |
   |---|---|---|---|---|
   | Network and VPN | TCK-10504 | P2 High | In Progress | 6.0 of 8 |
   | Network and VPN | TCK-10507 | P2 High | New | 6.5 of 8 |
   | Network and VPN | TCK-10484 | P3 Medium | Waiting on Customer | 7.0 of 16 |
   | Printing | TCK-10493 | P3 Medium | In Progress | 11.0 of 16 |
   | Endpoint | TCK-10502 | P3 Medium | New | 13.0 of 16 |
   | Email and Collaboration | TCK-10481 | P4 Low | In Progress | 28.0 of 40 |

   The recurring issue is the hourly Remote Access disconnect in **TCK-10484**, **TCK-10504** and **TCK-10507**. Woodgrove runs client 4.2.0 on firmware 10.1.4, so the three tickets point to KB0058 and one gateway change.

   > **[SCREENSHOT PENDING: E2T2S2 | Agent summary of Woodgrove Bank's six open tickets grouped by category with the recurring VPN issue flagged | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary. SLA figures are a snapshot, so the agent should say when they were calculated.

1. Verify the count in the Service Desk app: open **Tickets**, select the **Open Tickets** view, select the **Customer** column header, choose **Filter by**, and filter on **Woodgrove Bank**. The list shows **6** rows.

   > **[SCREENSHOT PENDING: E2T2S3 | Open Tickets view filtered on Woodgrove Bank showing six rows | source: capture]**

### Success Criteria

- [ ] The summary lists exactly the six open Woodgrove Bank tickets and no closed tickets
- [ ] The tickets are grouped by category and urgency
- [ ] The recurring Remote Access issue across TCK-10484, TCK-10504 and TCK-10507 is flagged
- [ ] The count in the app matches the summary

## Task 3: Recommend a priority and category for a new ticket

In this task, you will ask the agent to triage a ticket that has neither a priority nor a category, citing the historical pattern, and compare its recommendation with your own.

1. In the Service Desk app, open **Tickets** and select the **Untriaged Tickets** view. Open **TCK-10512** from Lucerne Publishing and read its description.

1. In the playground, start a new chat and send:

   ```
   TCK-10512 has no priority and no category yet. Recommend a priority and a category for it. Cite the knowledge article and the historical tickets that support your recommendation, and say which Relecloud priority rule applies.
   ```

1. Check the recommendation. Expect category **Line-of-Business App** and priority **P2 High**: four finance users are blocked on a time-critical process, payroll, which is the P2 rule. The agent should cite **KB0133** *Line-of-business application shows a certificate expired warning*, whose last step says several users blocked on payroll or claims intake is P2, and historical certificate tickets resolved with KB0133.

   > **[SCREENSHOT PENDING: E2T3S3 | Agent recommendation for TCK-10512 citing KB0133 and historical tickets | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. As a team, decide whether you agree. Consider what would change the priority: if only one person were affected, the P3 rule would apply; if the whole business couldn't work, P1. Record your decision and the reason in **Lab notes.txt** next to **Triage recommendation for TCK-10512**. Don't apply the triage yet. The agent can't change tickets until it has write tools in Exercise 4.

### Success Criteria

- [ ] The recommendation names a category and a priority and the rule behind the priority
- [ ] It cites KB0133 and at least one historical ticket by number
- [ ] Your team has recorded whether it agrees and why

## Task 4: Identify SLA risk

In this task, you will find the open tickets closest to breaching their SLA, with the figures in business hours, and verify one of them on its record.

1. Start a new chat and send:

   ```
   Which open tickets are closest to breaching their SLA? For the three closest, show the customer, priority, SLA target, elapsed and remaining business hours, and when the figures were calculated. List any tickets that have already breached separately.
   ```

1. Check the answer against the expected result:

   | Ticket | Customer | Priority | Target | Elapsed | Remaining |
   |---|---|---|---|---|---|
   | TCK-10500 | Contoso Pharmaceuticals (Platinum) | P1 Critical | 4 | 3.5 | 0.5 |
   | TCK-10489 | Humongous Insurance (Platinum) | P2 High | 8 | 7.0 | 1.0 |
   | TCK-10474 | Bellows College (Gold) | P3 Medium | 24 | 22.0 | 2.0 |

   Already breached: **TCK-10471** (Tailspin Toys, Bronze, P3, 6.0 hours over) and **TCK-10480** (Northwind Traders, Gold, P2, 1.5 hours over). Every other open ticket has at least 6 business hours left.

   > **[SCREENSHOT PENDING: E2T4S2 | Agent list of the three tickets closest to SLA breach with business-hour figures | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Check the arithmetic: target minus elapsed equals remaining. Business hours run Monday to Friday, 08:00 to 18:00 UTC, so a 4-hour P1 target opened at 16:00 on a Friday is due at 10:00 on Monday.

1. Verify one ticket on its record: in the Service Desk app, open **TCK-10500** and compare **SLA Target**, **SLA Elapsed**, **SLA Remaining**, **SLA Due On** and **SLA Calculated On** in the **SLA** section with the agent's answer. Then open **Tickets** and select the **Open Tickets by SLA Remaining** view. It sorts by remaining hours, lowest first, so its first five rows are the two breached tickets (TCK-10471, TCK-10480) followed by TCK-10500, TCK-10489 and TCK-10474.

   > **[SCREENSHOT PENDING: E2T4S4 | Open Tickets by SLA Remaining view in the Service Desk app | source: capture]**

### Success Criteria

- [ ] The three closest tickets are TCK-10500, TCK-10489 and TCK-10474, in that order, with priority, target, elapsed and remaining hours
- [ ] TCK-10471 and TCK-10480 are reported as already breached, not as at risk
- [ ] The answer says when the SLA figures were calculated
- [ ] The figures on TCK-10500 in the app match the agent's answer

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The agent lists closed tickets as open, or misses some:** ask it to use the customer's profile, which lists the open tickets, or the SLA risk snapshot; then check the count in the app.
- **The agent invents ticket numbers:** start a new chat and ask again. If it persists, check that the agent's instructions are the grounded ones from Exercise 1 (they say never to invent numbers).
- **Answers have no citations:** the knowledge tool may be missing from the latest agent version. Run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge` and start a new chat.
- **SLA figures differ from the app by a little:** the index holds the snapshot taken at **SLA Calculated On**; compare the same columns on the record, not the time now.

</details>

## Summary

In this exercise, you have completed the following:

- Matched an unseen incident to historical tickets and checked one of them in the Service Desk app
- Summarized Woodgrove Bank's open tickets by category and urgency and flagged the recurring Remote Access issue
- Got a cited triage recommendation for the untriaged ticket TCK-10512 and compared it with your own judgment
- Found the tickets closest to SLA breach in business hours and verified one on its record

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
