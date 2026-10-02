# Exercise 2: Ticket and Incident Intelligence

### Estimated Duration: 35 minutes

## Scenario

Relecloud's technicians don't need an agent that recites articles; they need one that spots the pattern in a new incident, sees what a customer's history really looks like, triages what arrived without a priority, and warns before an SLA is breached. Those are the four jobs that eat the third of handling time the service review measured.

## Overview

In this exercise, you use the grounded agent from Exercise 1 on four service desk jobs. You match a new incident that is waiting in your queue, and that the agent has never seen, to historical tickets; summarize one customer's support history; recommend priority, category and assignment for the new incident; and find the tickets closest to breaching their SLA. You check every answer against the Service Desk app and the expected results in this guide. The agent reads live tickets through its read tools; it doesn't change anything in this exercise.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Identify Similar Historical Incidents
- Task 2: Summarise a Customer's Support History
- Task 3: Recommend Priority, Category and Assignment
- Task 4: Detect an SLA Risk

## Task 1: Identify Similar Historical Incidents

In this task, you will find the historical tickets closest to a new incident. Similarity that can be explained is worth more than similarity that cannot.

1. Open the new, unclassified incident waiting in your Service Desk queue; it is not in your search index, so your agent has never seen it. In the Service Desk app, open **Tickets**, select the **Untriaged Tickets** view, and open **TCK-10514** from **A. Datum Corporation**, *Nightly protection job stopped creating recovery points*. Read its description: the job stopped creating recovery points on Saturday night, the console says the cloud storage allowance is used up, and the customer copied a 2019 to 2024 drawing archive onto the server last week. **Priority**, **Category** and **Assigned Technician** are empty.

   > **[SCREENSHOT PENDING: E2T1S1 | TCK-10514 in the Untriaged Tickets view with its description | source: capture]**

1. Ask the agent to find the closest historical tickets in your environment. In the playground, start a new chat and send:

   ```
   A new incident, TCK-10514, is waiting in the Service Desk queue. Read it with the Service Desk tools, then find the five historical tickets most similar to it, and any open ticket that looks like the same problem.
   ```

   The agent reads the incident with **get_ticket**, because it isn't in the index, and then searches the index.

1. Ask it to explain what makes each one similar, beyond keyword overlap:

   ```
   For each match, explain what makes it similar beyond shared words: the symptom, the error code, what changed just before it started, the product, the cause and how it was resolved. Then name any ticket that only looks similar, and say why it isn't the same problem.
   ```

   > **[SCREENSHOT PENDING: E2T1S3 | Agent answer listing similar historical tickets with explained similarity | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Open one of the results in the Service Desk app, confirm it is a genuine match, and compare your list with the expected matches below. Select a ticket citation, or open **Tickets**, select the **All Tickets** view, and type the ticket number in the **Filter by keyword** box. Compare its **Description**, **Related Article** and **Resolution Summary** with what the agent said.

   **Expected results: true matches.** The new incident is a cloud vault that reached its contracted size after a large data import, so jobs stop creating restore points. That is **KB0023** *RBA-2201: cloud vault storage quota exceeded*, and the historical tickets resolved with it are the true matches:

   | Ticket | Customer | Title | Why it matches |
   |---|---|---|---|
   | TCK-10004, TCK-10035, TCK-10061 | Contoso Pharmaceuticals | *Backup failed: RBA-2201 vault quota exceeded*, *No new restore points: vault full* | Same cause (vault quota reached), same symptom (no new restore points), same error RBA-2201, resolved with KB0023 |
   | TCK-10029 | Adventure Works Cycles | *No new restore points: vault full* | Same |
   | TCK-10040 | Northwind Traders | *Backup failed: RBA-2201 vault quota exceeded* | Same |
   | TCK-10092, TCK-10205, TCK-10264, TCK-10390, TCK-10402 | Bellows College, Proseware Inc, Wide World Importers, Fabrikam Residences, Lucerne Publishing | *No new restore points: vault full* or *RBA-2201 vault quota exceeded* | Same |
   | TCK-10486 (open) | Trey Research | *Backup failing with RBA-2201 vault quota exceeded* | The same problem at another customer, open now |

   Every one of the ten historical KB0023 tickets was **P3 Medium**, assigned to **Priya Raman** (TECH-01, Backup and Recovery), and **escalated to the Account Manager**, because a vault size increase needs a quote and the customer's approval. A strong answer also notes A. Datum's own procedure **CUST-019-PR3**: vault size increases need written approval from the customer's IT manager, and large archive imports must be announced a week ahead.

   **Expected results: decoys.** These share words or a product area with the incident but are a different problem:

   | Ticket or article | Shares | Why it isn't the same problem |
   |---|---|---|
   | KB0012 and KB0013 tickets, for example TCK-10399 *Backup failed twice for ADCFS01* (A. Datum) | "nightly backup failed" | The standard response to a failed job by SLA tier; the cause is not a full vault |
   | KB0033 tickets, for example TCK-10110 *Backup jobs running into the morning* | "vault" | Slow backups after vault encryption was turned on; restore points are still created |
   | KB0036 tickets, for example TCK-10332 *Backup uploading large .pst files every night* (A. Datum) | large files in the backup | A file exclusion problem, not a storage limit |
   | KB0039 and the open TCK-10494 *CAD workstation backup status Unknown* (A. Datum) | same customer, backup status | The device is offline and not reporting; nothing is wrong with the vault |
   | KB0007 tickets, for example TCK-10007 | a failed backup job | Error RBA-1043, a snapshot timeout after patching |

   > **[SCREENSHOT PENDING: E2T1S4 | Historical ticket TCK-10035 with its related article KB0023 and resolution summary | source: capture]**

### Expected results

- [ ] The agent read TCK-10514 with a Service Desk tool before it searched
- [ ] Its matches are KB0023 tickets, and it found the open TCK-10486
- [ ] Each explanation goes beyond shared words (cause, error code, trigger, resolution)
- [ ] It told at least one decoy apart from the real matches, for example TCK-10494
- [ ] The ticket you opened in the app matches what the agent said about it

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Agent reads the new incident" is registered (validation-scripts/README.md). -->

## Task 2: Summarise a Customer's Support History

In this task, you will produce the summary a support lead asks for first about any account.

1. Pick a customer with several open tickets. **Woodgrove Bank** (CUST-007) has six, more than any other customer.

1. Ask the agent to summarise open issues by category or urgency, and how previous incidents for this customer were resolved. Start a new chat and send:

   ```
   Summarise Woodgrove Bank's support history. Group the open tickets by category and urgency, with each ticket's number, status, priority and SLA remaining. Then summarise how Woodgrove Bank's previous incidents were resolved: the most common problems and the knowledge articles that resolved them.
   ```

1. Ask it to flag anything recurring or previously escalated:

   ```
   Flag any issue that recurs across Woodgrove Bank tickets, and any of their previous tickets that were escalated, with the escalation level.
   ```

   **Expected results.** Woodgrove Bank has **6** open tickets:

   | Category | Ticket | Priority | Status | SLA remaining (business hours) |
   |---|---|---|---|---|
   | Network and VPN | TCK-10504 | P2 High | In Progress | 6.0 of 8 |
   | Network and VPN | TCK-10507 | P2 High | New | 6.5 of 8 |
   | Network and VPN | TCK-10484 | P3 Medium | Waiting on Customer | 7.0 of 16 |
   | Printing | TCK-10493 | P3 Medium | In Progress | 11.0 of 16 |
   | Endpoint | TCK-10502 | P3 Medium | New | 13.0 of 16 |
   | Email and Collaboration | TCK-10481 | P4 Low | In Progress | 28.0 of 40 |

   - **Recurring:** the hourly Remote Access disconnect in **TCK-10484**, **TCK-10504** and **TCK-10507**. Woodgrove runs client 4.2.0 on firmware 10.1.4, so all three point to **KB0058** and one gateway change. TCK-10502 (*Laptop very slow since this week's agent update*) matches **KB0067** for Woodgrove's Endpoint Agent 7.4.0.
   - **How previous incidents were resolved:** 30 resolved or closed tickets, most often with **KB0055** (choppy calls over Remote Access, split tunnelling) and **KB0044** (firewall rule change requests), three tickets each.
   - **Previously escalated:** TCK-10038, TCK-10077 and TCK-10257 (KB0055) and TCK-10313, TCK-10395 and TCK-10430 (KB0044), all to the **L3 Specialist**, and **TCK-10365** to **Major Incident** (KB0143, ransomware indicator).

   > **[SCREENSHOT PENDING: E2T2S3 | Agent summary of Woodgrove Bank's open tickets and escalated history | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary. SLA figures are a snapshot, so the agent should say when they were calculated.

1. Verify the open ticket count against the Service Desk app. Open **Tickets**, select the **Open Tickets** view, select the **Customer** column header, choose **Filter by**, and filter on **Woodgrove Bank**. The list shows **6** rows. Then open the **Escalated Tickets** view and find Woodgrove Bank's escalated tickets.

   > **[SCREENSHOT PENDING: E2T2S4 | Open Tickets view filtered on Woodgrove Bank showing six rows | source: capture]**

### Expected results

- [ ] The summary lists exactly the six open Woodgrove Bank tickets and no closed tickets, grouped by category and urgency
- [ ] It summarises how previous incidents were resolved, naming KB0055 and KB0044
- [ ] It flags the recurring Remote Access issue and the escalated tickets with their levels
- [ ] The count in the app matches the summary

## Task 3: Recommend Priority, Category and Assignment

In this task, you will see whether the agent learns the desk's conventions or guesses. Classification is where the difference shows.

1. Use the same new incident, **TCK-10514**, which has no priority, category or technician set.

1. Ask the agent to recommend priority, category and the technician or team, citing the historical pattern it used. In the chat from Task 1, send:

   ```
   TCK-10514 has no priority, category or technician yet. Recommend a priority, a category, and the technician or team to assign it to. Cite the historical tickets, the knowledge article and the customer procedure your recommendation is based on, and say which Relecloud priority rule applies. Don't change the ticket.
   ```

   **Expected results.** Category **Backup and Recovery**; priority **P3 Medium**, which every historical KB0023 ticket had: one server, existing restore points intact, no data lost; technician **Priya Raman** (TECH-01, Backup and Recovery team, L2, skills include vault storage), who resolved all ten historical KB0023 tickets. A strong answer adds that the historical tickets were escalated to the **Account Manager**, that A. Datum's account manager is **Owen Fletcher**, and that procedure **CUST-019-PR3** requires the customer's written approval for a vault increase. With A. Datum's **Silver** tier, a P3 has an SLA target of **32** business hours.

   > **[SCREENSHOT PENDING: E2T3S2 | Agent recommendation for TCK-10514 citing KB0023, historical tickets and the customer procedure | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary. You apply this recommendation through a write tool in Exercise 4.

1. Open a seeded ticket with incomplete information and confirm the agent asks for what is missing rather than guessing. In the **Untriaged Tickets** view, open **TCK-10513** from **VanArsdel Ltd**: *It stopped working again*, with no product, version or number of affected users. Start a new chat and send:

   ```
   Triage TCK-10513: recommend a priority, category and technician.
   ```

   **Expected results.** The agent reads the ticket, says it can't triage it from the information given, and asks what is missing: which system or application stopped working, the error message, how many people are affected, when it started, and which earlier ticket "same as last time" refers to. It may list VanArsdel's recent tickets as candidates, but it must not pick one and triage on a guess.

### Expected results

- [ ] The TCK-10514 recommendation is Backup and Recovery, P3 and Priya Raman, and cites KB0023 and historical tickets by number
- [ ] The recommendation names the priority rule and the customer procedure behind it
- [ ] For TCK-10513, the agent asked for the missing details instead of guessing

## Task 4: Detect an SLA Risk

In this task, you will find the tickets closest to breaching their resolution SLA. SLA fields and a business calendar are seeded in your environment and are arithmetically consistent.

1. Ask the agent which open tickets are closest to breaching their resolution SLA. Start a new chat and send:

   ```
   Which open tickets are closest to breaching their resolution SLA? List the three closest, and list separately any that have already breached.
   ```

1. Ask it to show the working: priority, SLA target and elapsed business hours:

   ```
   For each of those tickets, show the customer and SLA tier, the priority, the SLA target, the elapsed and remaining business hours, and when the figures were calculated.
   ```

   **Expected results:**

   | Ticket | Customer | Priority | Target | Elapsed | Remaining |
   |---|---|---|---|---|---|
   | TCK-10500 | Contoso Pharmaceuticals (Platinum) | P1 Critical | 4 | 3.5 | 0.5 |
   | TCK-10489 | Humongous Insurance (Platinum) | P2 High | 8 | 7.0 | 1.0 |
   | TCK-10474 | Bellows College (Gold) | P3 Medium | 24 | 22.0 | 2.0 |

   Already breached: **TCK-10471** (Tailspin Toys, Bronze, P3, 48 target, 54.0 elapsed, 6.0 hours over) and **TCK-10480** (Northwind Traders, Gold, P2, 12 target, 13.5 elapsed, 1.5 hours over). Untriaged tickets have no priority, so no SLA clock yet: the index's SLA snapshot lists three (TCK-10511, TCK-10512 and TCK-10513), and the **Untriaged Tickets** view also shows the two new incidents, which aren't indexed. Target minus elapsed equals remaining; business hours run Monday to Friday, 08:00 to 18:00 UTC, so a 4-hour P1 target opened at 16:00 on a Friday is due at 10:00 on Monday.

   > **[SCREENSHOT PENDING: E2T4S2 | Agent list of the tickets closest to SLA breach with business-hour figures | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Verify one result against the SLA fields on the ticket record itself. In the Service Desk app, open **TCK-10500** and compare **SLA Target**, **SLA Elapsed**, **SLA Remaining**, **SLA Due On** and **SLA Calculated On** in the **SLA** section with the agent's answer. Then open **Tickets** and select the **Open Tickets by SLA Remaining** view: its first five rows are TCK-10471, TCK-10480, TCK-10500, TCK-10489 and TCK-10474.

   > **[SCREENSHOT PENDING: E2T4S3 | TCK-10500 SLA section in the Service Desk app | source: capture]**

### Expected results

- [ ] The three closest tickets are TCK-10500, TCK-10489 and TCK-10474, in that order, with priority, target, elapsed and remaining hours
- [ ] TCK-10471 and TCK-10480 are reported as already breached, not as at risk
- [ ] The answer says when the SLA figures were calculated
- [ ] The figures on TCK-10500 in the app match the agent's answer

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The agent says it can't find TCK-10514:** that is expected from the index alone. Ask it to read the ticket with the Service Desk tools.
- **The agent lists closed tickets as open, or misses some:** ask it to use the customer's profile, which lists the open tickets, or the SLA risk snapshot; then check the count in the app.
- **The agent invents ticket numbers:** start a new chat and ask again. If it persists, check that the agent's instructions are the grounded ones from Exercise 1, which say never to invent numbers.
- **SLA figures differ from the app by a little:** the index holds the snapshot taken at **SLA Calculated On**; compare the same columns on the record, not the time now.

</details>

## Summary

In this exercise, you have completed the following:

- Matched the new incident TCK-10514, which the agent had never seen, to its true historical matches and told the decoys apart
- Summarised Woodgrove Bank's open issues, how earlier incidents were resolved, and what recurred or was escalated
- Got a cited priority, category and assignment recommendation for TCK-10514, and saw the agent ask for missing details on TCK-10513
- Found the tickets closest to SLA breach in business hours and verified one on its record

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
