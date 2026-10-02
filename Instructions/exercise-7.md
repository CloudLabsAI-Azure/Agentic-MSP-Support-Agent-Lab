# Exercise 7: End-to-End Scenario and Business Case

### Estimated Duration: 25 minutes

## Scenario

A second incident has just arrived: Consolidated Messenger's dispatchers at the north depot can't load today's delivery routes, and vans are waiting to leave. Relecloud's leadership wants to see the agent handle it end to end, from the new ticket to an authorized, audited action, and then hear in a few minutes why an MSP should deploy what your team built.

## Overview

In this exercise, you run the whole scenario in one exchange: the agent identifies the customer, retrieves its history, procedures and the relevant knowledge, summarises the likely issue, recommends priority and category, asks for approval, acts through the MCP server and reports the outcome. You capture the correlated audit trail for the run. Finally, you complete the business case template in your lab notes and present it as a short walkthrough.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Run the End-to-End Scenario
- Task 2: Present the Business Case

## Task 1: Run the End-to-End Scenario

In this task, you will take a new ticket through customer context, history, recommendation, authorized action, update and log, in one run.

1. Open the second new incident in your Service Desk queue. In the Service Desk app, open **Tickets**, select the **Untriaged Tickets** view, and open **TCK-10515** from **Consolidated Messenger**: *Dispatchers can't load routes: certificate warning*. Since the start of the morning shift, five dispatchers at the north depot see a warning that the routing application's certificate has expired; the south depot is working normally. It has no priority, category or technician, and it isn't in the knowledge index.

1. Have your agent identify the customer, retrieve history and knowledge, summarise the likely issue and recommend priority and category. Start a new chat and send:

   ```
   Work the new incident TCK-10515. Identify the customer, retrieve their history and agreed procedures, the similar historical incidents and the relevant knowledge, summarise the likely issue, and recommend a priority, a category and who should take it, with your sources. Don't change anything yet.
   ```

   **Expected results:**

   - **Customer:** Consolidated Messenger (CUST-020), **Silver**, **Fully Managed**. Its procedure **CUST-020-PR3** *Dispatch hours* says dispatchers need the routing application from 06:00, and an outage that stops dispatchers is **P2**, with a phone call to the operations contact straight away.
   - **Likely issue:** an expired TLS certificate on the on-premises routing application, probably on the server or site that serves the north depot, since the south depot works. The article is **KB0133** *Line-of-business application shows a certificate expired warning*, and the runbook **RB-005** *Certificate expired on a line-of-business application*.
   - **History:** the KB0133 tickets, among them two for a routing application, **TCK-10089** (Bellows College) and **TCK-10401** (Blue Yonder Airlines). Each P2 KB0133 ticket was handled by **Daniel Cho** and **escalated to the Vendor**.
   - **Recommendation:** category **Line-of-Business App**, priority **P2 High** (the customer procedure, and KB0133's rule that several users blocked on a time-critical process is P2), assign to **Daniel Cho** (TECH-06), and escalate to the vendor as the history shows. A Silver P2 has an SLA target of **16** business hours.
   - **Not the same incident:** the open **TCK-10512** at Lucerne Publishing is also a certificate warning, but at another customer, on a payroll application.

   > **[SCREENSHOT PENDING: E7T1S2 | Agent summary and recommendation for TCK-10515 with its sources | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Have it request approval, act through the MCP server and report the outcome. In the same chat, send:

   ```
   Go ahead. Triage TCK-10515 and assign it as you recommended. If you have a tool for escalations, escalate it to the vendor. Then post a short customer-visible reply telling the dispatch team what happens next, and report the outcome of each change with its correlation ID.
   ```

   Approve each call after you check its arguments: **triage_ticket** (Line-of-Business App, priority `2`, a reason that cites CUST-020-PR3 and KB0133), **assign_ticket** (Daniel Cho), your scoped tool from Exercise 4 if it fits, and **add_ticket_note** with `is_internal` `false` and no internal content. The agent reports each outcome with its correlation identifier. In the Service Desk app, open **TCK-10515**: **Line-of-Business App**, **P2 High**, SLA target **16**, **Daniel Cho**, **In Progress**, the escalation if you made one, and the customer reply and the audit notes under **Related** > **Ticket Notes**.

1. Capture the correlated audit trail for the run. In PowerShell 7, run the trail script with the correlation identifier of the triage, and then of the assignment:

   ```powershell
   C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId <correlation ID>
   ```

   In **Lab notes.txt**, next to **TCK-10515**, record the customer, the recommendation, the actions taken and their correlation identifiers. You use this trail as evidence in Task 2.

   > **[SCREENSHOT PENDING: E7T1S4 | Get-ActionTrail.ps1 timeline for the TCK-10515 triage | source: capture]**

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "End-to-end scenario completed" is registered (validation-scripts/README.md). -->

## Task 2: Present the Business Case

In this task, you will position what you built as something an MSP could deploy for a customer.

1. Summarise your agent's grounding, tool design, security model and audit evidence in a short walkthrough. Open the **Business case** section at the end of **Lab notes.txt** and fill in each heading with evidence from your own environment:

   | Heading | Evidence from this lab |
   |---|---|
   | **What the agent does (grounding and tools)** | The index of 561 documents with citations; the article chosen by product version, tier or contract; the read tools for live data; the approval-gated write tools, including the one your team designed |
   | **Controls (identity, least privilege, approval, data protection, audit)** | The technician's own identity at every hop; the least-privileged roles; the Tier 1 denial from Exercise 5; the gateway key in Key Vault; approval on every write; the withheld column, note and document from Exercise 6 |
   | **Evidence from this lab** | The correlation identifiers and trails from Exercise 6 Task 3 and Task 1 of this exercise |

   Keep it to what you can show: every claim should point to something you saw.

1. State the operational value for an MSP and the controls that make it safe to deploy. Complete the remaining headings, **Problem today**, **Operational value for the MSP (time, consistency, SLA)** and **Risks and next steps**. For example: a third of handling time went to searching old tickets and articles; new tickets waited for triage; SLA breaches cost service credits. The agent finds similar incidents and the right article in seconds, triages new tickets with the desk's own conventions, and flags SLA risk, while every action stays within the technician's own permissions and leaves a trail the security team can follow. Present the walkthrough in about three minutes to another team, or record it for your stakeholders.

### Expected results

- [ ] Your business case covers grounding, tool design, the security model and audit evidence
- [ ] Each claim points to evidence from your environment: a citation, a denied call, a withheld value or a correlation identifier
- [ ] It states the operational value for an MSP and the controls that make the agent safe to deploy

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The agent doesn't find TCK-10515 in the index:** that is expected. It reads the ticket with the Service Desk tools.
- **The agent recommends P3:** ask it to read Consolidated Messenger's procedures with `get_customer`; procedure CUST-020-PR3 makes a dispatch outage P2.
- **Your scoped tool from Exercise 4 isn't offered:** start a new chat so the agent reads the tool list again, or leave the escalation out.
- **The trail script finds no Application Insights rows:** agent traces can take several minutes to arrive. Run it again later; the gateway, MCP server and Dataverse hops appear first.

</details>

## Summary

In this exercise, you have completed the following:

- Ran the second new incident from intake to an approved triage, assignment and customer reply in one exchange, grounded in the customer's procedures, history and knowledge
- Captured the correlated audit trail for the run
- Completed and presented a business case for the agent, backed by evidence from your environment

### Congratulations on completing the lab!

You have built a support agent that answers from Relecloud's own Service Desk data, acts through governed, approval-gated tools on behalf of the technician who asks, and leaves a trail from the request to the database record.
