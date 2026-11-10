# Exercise 7: End-to-End Scenario and Business Case

### Estimated Duration: 15 minutes

## Scenario

"Should we offer this agent to our customers, and what makes it safe to deploy?" Relecloud's managing director asks the last question, and the answer has to rest on evidence rather than a demo: last quarter, 11 Platinum and Gold SLA breaches cost USD 18,400 in service credits, and the earlier automation pilot was stopped after an internal note about an invoice dispute appeared in a reply to a customer. This morning's second new incident is the test. At Consolidated Messenger, five dispatchers at the north depot can't load today's delivery routes because of a certificate warning, and vans are waiting to leave. In this exercise, you take that incident from intake to approved, audited changes in one conversation, export the trail of every change for the reviewers, and turn what you recorded across the lab into a business case.

## Overview

In this exercise, you open **TCK-10562** in the Service Desk app and let `msp-support-agent` work it end to end: it reads the ticket through the MCP read tools, applies Consolidated Messenger's procedures, the history of article KB0133 and the routing application's configuration notes, and recommends a cited triage. You approve four writes, check them in the app, and export the correlated audit trail of each write with `Get-ActionTrail.ps1`. Then you complete the business case in **Lab notes.txt** that answers the managing director.

![TCK-10562 at Consolidated Messenger moves through five numbered stages: the new, untriaged incident; the records the agent reads, CUST-020-PR3, KB0133, RB-005 and CDOC-032; a cited recommendation of Line-of-Business App, Certificate, P2 High and Daniel Cho; four writes you approve on servicedesk-write; and the trail each write leaves, which becomes the evidence behind the business case](./media/exercise-7-end-to-end.png)

How to read this diagram: the five numbered columns follow TCK-10562 from left to right, and each one lights up in turn while a dot moves along the arrow to the next. New incident is the ticket as it arrives: New, with no priority, category or technician, and not in the index. Read the context is what the agent reads: CUST-020-PR3, which makes a routing outage that stops dispatchers P2 with a call to the operations contact at once; KB0133, whose ten past tickets were all Daniel Cho's, with the seven P2 tickets escalated to the Vendor and two of them in a routing application; RB-005, the runbook that binds the renewed certificate; and CDOC-032, which names the north depot's routing server, CMRT-N01. Recommend is the triage and the record each part cites: Line-of-Business App and Certificate, P2 High with a 16-hour target, Daniel Cho (TECH-06), a Vendor escalation and a call to Victor Murphy. Approve and write lists the four writes you approve, each passing through `servicedesk-write`, API Management and the MCP server to Dataverse on your behalf with its own correlation ID: four approvals, four Agent Action rows. Prove it lists where each write leaves a trail (Application Insights, the API Management log, the MCP server log, the Dataverse audit and an Agent Action row) and the business case it supports, set against last quarter's 11 Platinum and Gold breaches and USD 18,400 in service credits.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Run the End-to-End Scenario
- Task 2: Present the Business Case

## Task 1: Run the End-to-End Scenario

In this task, you will take one new incident from intake to approved, audited changes in a single conversation, and export the evidence of every change.

1. Open the second new incident in your Service Desk queue. In the Service Desk app (double-click **Service Desk** on the desktop if it isn't open), select **Tickets** under **Work**, and select the **Untriaged Tickets** view. It lists the tickets that are still **New** and have no priority, including **TCK-10562** from **Consolidated Messenger**, *Dispatchers can't load routes: certificate warning*, and **TCK-10559** from **Lucerne Publishing**, another certificate warning. Open **TCK-10562**. Its **Summary** section shows **Status** **New**, **Channel** **Phone** and **Victor Murphy** as the **Requester**, with no **Priority**, **Category**, **Subcategory** or **Assigned Technician**, and its **SLA** section has no target yet. The **Description** under **Details** says that since the start of the morning shift, five dispatchers at the north depot see a warning that the routing application's security certificate has expired and can't load today's delivery routes; vans are waiting to leave, and the south depot is working normally.

   > **[SCREENSHOT PENDING: E7T1S1-1 | Service Desk app, Untriaged Tickets view listing TCK-10562 from Consolidated Messenger and TCK-10559 from Lucerne Publishing | source: capture]**

   > **[SCREENSHOT PENDING: E7T1S1-2 | TCK-10562 form with Status New, Channel Phone, Requester Victor Murphy, no priority, category or technician, and the description | source: capture]**

   > **Note:** TCK-10562 isn't in the knowledge index. Provisioning loaded the two new incidents after the export, so the agent can reach this ticket only through the MCP read tools, as it would reach a ticket that arrived after the last indexing run.

1. Have your agent identify the customer, retrieve history and knowledge, summarize the likely issue and recommend priority and category. In the Microsoft Foundry portal, open **msp-support-agent** on the **Playground** tab. If you closed it, double-click **Microsoft Foundry** on the desktop, select your project **<inject key="Foundry Project Name" enableCopy="false"/>**, select **Build**, and then select **msp-support-agent**. Select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   A new incident has arrived: TCK-10562. Identify the customer and the procedures that apply, find the similar historical incidents and the relevant knowledge, and summarize the likely issue, including which server is affected. Recommend a priority, category, subcategory and technician, with the SLA target and anything the customer's procedures ask us to do right away. Say whether any open ticket is the same incident. Cite every source and don't change anything yet.
   ```

   **Expected Output:** the agent reads TCK-10562 with the read tools, which run without an approval request, searches the knowledge index, and answers with a source for each point:

   - **Customer:** **Consolidated Messenger** (**CUST-020**), **Silver**, **Fully Managed**. The requester, **Victor Murphy**, is its operations contact, and the ticket came in by phone. The agent may also list the customer's two other open tickets, **TCK-10520** (Wi-Fi in the south depot loading bay) and **TCK-10525** (a dispatcher account locked repeatedly), as unrelated.
   - **Procedures:** **CUST-020-PR3** *Dispatch hours*: dispatchers need the routing application from 06:00 local time, a routing application outage that stops dispatchers is P2, and the operations contact gets a phone call straight away. The escalation procedure **CDOC-030** adds a call every 30 minutes until dispatchers can load routes again.
   - **Likely issue:** the TLS certificate on **CMRT-N01**, the north depot's routing application server, has expired. Each depot has its own server and certificate, and the certificate of the south depot's **CMRT-S01** was renewed early when that server was replaced, which is why the south depot still works (**CDOC-032** *Configuration notes: Consolidated Messenger routing application*).
   - **Knowledge:** **KB0133** *Line-of-business application shows a certificate expired warning* and runbook **RB-005** *Certificate expired on a line-of-business application*: identify the server and site binding, renew the certificate, bind it to the application site, and ask one user to confirm the warning is gone.
   - **History:** all ten past KB0133 tickets were handled by **Daniel Cho**, and the seven P2 ones were all escalated to the **Vendor**, including two in a routing application: **TCK-10100** (Bellows College) and **TCK-10470** (Blue Yonder Airlines).
   - **Recommendation:** category **Line-of-Business App**, subcategory **Certificate** and priority **P2 High** (CUST-020-PR3), which for a Silver customer means a resolution target of **16** business hours; technician **Daniel Cho** (**TECH-06**, Service Desk team, available); a Vendor escalation if the binding or the application itself is at fault, as in the history and CDOC-030; and a phone call to Victor Murphy now. It gives no phone number: column security withholds contact phone numbers from the MCP server, so the agent never receives one, and you would read it in the Service Desk app.
   - **Not the same incident:** **TCK-10559** (Lucerne Publishing's payroll application on Lucerne's own server, LPAPP01) and **TCK-10524** (Humongous Insurance's claims document management application on APP03) show the same warning and follow the same article and runbook, but they are separate incidents at other customers, so the agent doesn't link them.

   **What this validates:** the agent reaches a ticket the index has never seen through the read tools, and recommends what Relecloud's best technician would, citing the customer's own procedure and the desk's own history, before anything changes.

   > **[SCREENSHOT PENDING: E7T1S2 | Playground answer for TCK-10562 citing CUST-020-PR3, KB0133, RB-005 and CDOC-032, recommending Line-of-Business App, Certificate, P2 High and Daniel Cho, and keeping TCK-10559 and TCK-10524 apart | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Have it request approval, act through the MCP server and report the outcome. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Apply your recommendation to TCK-10562, one change at a time: set the category and subcategory, set the priority, and assign the technician. Leave the vendor escalation to the technician. Then add a short customer-visible reply for the requester that says what we know, what we are doing now and when they will hear from us next, as Consolidated Messenger's escalation procedure asks. Keep everything else internal. Report the outcome of each change with its correlation ID.
   ```

   **Expected Output:** the agent says what it will change and why, and then asks for your approval once per write. Each approval request shows the tool and its arguments. Check them against this table, and check that any `reason` cites a record; select **Approve** only when they match:

   | Write | Arguments to check before you approve |
   |---|---|
   | **update_ticket_category** | `ticket_number` **TCK-10562**, the `category` **Line-of-Business App**, the `subcategory` **Certificate** and a `reason` that cites **KB0133** or its history |
   | **update_ticket_priority** | `ticket_number` **TCK-10562**, `priority` **2** (P2 High) and a `reason` that cites **CUST-020-PR3** |
   | **assign_ticket** | `ticket_number` **TCK-10562** and the `technician` **TECH-06** or **Daniel Cho** |
   | **add_public_reply** | `ticket_number` **TCK-10562** and a `body` written for Consolidated Messenger: the north depot's routing application certificate has expired, a technician is renewing it now, and Relecloud will phone with an update every 30 minutes. It holds nothing from an internal note, no other customer, no account or billing remark and no blame |

   After the last approval, the agent reports four outcomes, each with its own correlation ID: the category and subcategory set, the priority **P2 High** with an SLA target of **16** business hours, **Daniel Cho** assigned with the status now **In Progress**, and the reply added as a customer-visible note.

   **What this validates:** every change waits for your decision on its exact arguments, runs as you and comes back with a correlation ID, and the one change the customer reads carries only what was written for the customer.

   > **[SCREENSHOT PENDING: E7T1S3-1 | Playground approval request for update_ticket_priority with ticket_number TCK-10562, priority 2 and a reason that cites CUST-020-PR3 | source: capture]**

   > **[SCREENSHOT PENDING: E7T1S3-2 | Agent's report of the four outcomes on TCK-10562, each with its correlation ID | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Important:** The customer reads the reply. Read its whole text in the approval request before you approve it. If anything internal slipped in, decline it and ask the agent to rewrite the reply.

   > **Note:** Approve only these four writes. If the agent proposes anything else, decline it as you declined the status change on TCK-10544 in Exercise 4: nothing changes, and the agent says the call wasn't approved. If the agent describes the changes and asks you to confirm in the chat before it calls a tool, reply `Yes, go ahead.` Decide each request while it's on screen; a request with no decision is never carried out.

   Then check the result in the Service Desk app. Open **TCK-10562** again, or select **Refresh** if it's still open. The **Summary** section shows **Status** **In Progress**, **Priority** **P2 High**, **Category** **Line-of-Business App**, **Subcategory** **Certificate** and **Assigned Technician** **Daniel Cho**; the **SLA** section shows **SLA Target (business hours)** **16**; and **Last Correlation ID** in the **Traceability** section holds the ID of the latest change to the ticket's fields, the assignment. The reply carries its own correlation ID on its note. Select the **Related** tab and then **Ticket Notes**: the reply is listed with **Internal Note** **Customer visible**, beside the notes marked **Internal** that record each change. Then, under **Work**, select **Agent Actions**: the **All Agent Actions** view lists the four writes on **TCK-10562**, newest first, each with **Authorization** **Allowed**, **Outcome** **Succeeded**, your account as **User Name**, and the **Correlation ID** the agent reported. TCK-10562 is no longer in the **Untriaged Tickets** view, and TCK-10559 still is.

   > **[SCREENSHOT PENDING: E7T1S3-3 | TCK-10562 form after the writes: In Progress, P2 High, Line-of-Business App, Certificate, Daniel Cho and SLA Target (business hours) 16 | source: capture]**

   > **[SCREENSHOT PENDING: E7T1S3-4 | Agent Actions, All Agent Actions view with the four TCK-10562 rows, Allowed and Succeeded, with their correlation IDs | source: capture]**

   > **Note:** **SLA Elapsed (business hours)**, **SLA Remaining (business hours)**, **SLA Due On (UTC)** and **SLA Status** count from the ticket's **Opened On (UTC)**, which depends on when your environment was prepared, so your figures differ from other participants'. The target of 16 business hours is the same for everyone.

   In **Lab notes.txt**, next to **TCK-10562: customer, recommendation, actions taken and correlation IDs**, record **Consolidated Messenger (CUST-020)**, the recommendation (**Line-of-Business App**, **Certificate**, **P2 High**, 16 business hours, **Daniel Cho (TECH-06)**, vendor escalation left to him), and the four writes with their correlation IDs.

1. Capture the correlated audit trail for the run. In PowerShell 7, run the following command. It follows the priority change's correlation ID through every record the write left (your approval in the conversation, the agent trace, the gateway log, the MCP server log, the Dataverse audit and the Agent Action row), waits up to 10 minutes for any record that hasn't arrived yet, and exports the trail as a JSON file and a Markdown file in `C:\LabFiles\evidence`, the folder the reviewers open after the lab window. Replace `<correlation ID>`, angle brackets included, with the priority change's correlation ID from your notes:

   ```powershell
   C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId <correlation ID> -WaitMinutes 10 -OutFile C:\LabFiles\evidence\TCK-10562-priority
   ```

   The **Timeline** lists each record in time order. The **Summary** answers six questions about this one write: **Who asked** is your account, <inject key="AzureAdUserEmail" enableCopy="false"/>, from the token the gateway validated, with your request; **Which agent** is **msp-support-agent** with its Agent ID; **Which tool** is **update_ticket_priority** on the write endpoint with **TCK-10562** and priority **2**; **What was authorized** begins with *approval: approved* and shows the gateway's token check and the authorization result **Allowed**; **What changed** is the update Dataverse audited for your account, with the priority going from empty to **P2 High**; and **What was returned** shows the outcome **ok**. Under **Sources checked**, **MCP server log**, **API Management**, **Application Insights**, **Foundry conversation**, **Dataverse audit** and **Agent Action row** each show **Found**, and the last line reads *Evidence written to C:\LabFiles\evidence\TCK-10562-priority.json and C:\LabFiles\evidence\TCK-10562-priority.md.*

   > **[SCREENSHOT PENDING: E7T1S4-1 | PowerShell 7 window with the Get-ActionTrail.ps1 Summary and Sources checked for the TCK-10562 priority change, every source Found | source: capture]**

   > **Note:** Agent traces usually reach Application Insights 2 to 5 minutes after an action, gateway and MCP server logs reach Log Analytics in 3 to 10 minutes, and Microsoft doesn't document how long Dataverse takes to show an audit record. With `-WaitMinutes 10`, the script checks again every 60 seconds until every source is found or 10 minutes have passed, so you can start Task 2 in **Lab notes.txt** while it waits and come back. If a source still shows **Not found yet**, run the same command again a few minutes later: it overwrites both files with the complete trail.

   Export the trail of the other three writes the same way, each with its own correlation ID. These usually finish at once, because their records arrived while the first command ran.

   - Run the following command for the category change:

     ```powershell
     C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId <correlation ID> -WaitMinutes 10 -OutFile C:\LabFiles\evidence\TCK-10562-category
     ```

   - Run the following command for the assignment:

     ```powershell
     C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId <correlation ID> -WaitMinutes 10 -OutFile C:\LabFiles\evidence\TCK-10562-assignment
     ```

   - Run the following command for the customer-visible reply:

     ```powershell
     C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId <correlation ID> -WaitMinutes 10 -OutFile C:\LabFiles\evidence\TCK-10562-reply
     ```

   In File Explorer, open `C:\LabFiles\evidence`: it holds ten files, a JSON file and a Markdown file for each of the four writes, and the two files of the TCK-10544 trail you exported in Exercise 6. Open `TCK-10562-priority.md` in Visual Studio Code and press **Ctrl+Shift+V** to preview it: the summary, the timeline and the sources checked are what the reviewers read. In **Lab notes.txt**, add the evidence folder `C:\LabFiles\evidence` to your TCK-10562 line.

   > **[SCREENSHOT PENDING: E7T1S4-2 | File Explorer showing C:\LabFiles\evidence with ten files, and the TCK-10562-priority.md preview in Visual Studio Code | source: capture]**

### Expected results

- [ ] The agent read **TCK-10562** through the read tools and named **Consolidated Messenger** (**CUST-020**), **Silver**, **Fully Managed**, **CUST-020-PR3**, **KB0133**, **RB-005** and **CMRT-N01**, with a source for each
- [ ] It recommended **Line-of-Business App**, **Certificate**, **P2 High** with a 16-hour target and **Daniel Cho** (**TECH-06**), named **Victor Murphy** to phone without giving a phone number, and kept **TCK-10559** and **TCK-10524** apart
- [ ] You approved four writes after checking their arguments, and **TCK-10562** shows **In Progress**, **P2 High**, **Line-of-Business App**, **Certificate**, **Daniel Cho** and an SLA target of **16**
- [ ] The customer-visible reply holds nothing from an internal note, no other customer and no blame
- [ ] **Agent Actions** lists the four writes on **TCK-10562**, each **Allowed** and **Succeeded**, and you recorded their correlation IDs in **Lab notes.txt**
- [ ] `C:\LabFiles\evidence` holds ten files: the four TCK-10562 trails and the TCK-10544 trail from Exercise 6, and the priority change's **Sources checked** shows every source **Found**

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The agent says it can't find TCK-10562, or searches only the knowledge index | The new incidents were loaded after the export, so they aren't in the index | In the same chat, send `Read TCK-10562 with get_ticket and continue.` |
| The agent recommends P1 or P3 instead of P2 | It applied the general priority rules without the customer's own procedure | Ask it to apply Consolidated Messenger's procedure CUST-020-PR3. A major incident is the duty manager's decision after a depot can't dispatch for more than an hour (CDOC-030), not the agent's |
| No approval request appears, or the chat shows **Open Consent** | The agent is waiting for your confirmation in the chat, or your sign-in to the write connection needs renewing | Reply `Yes, go ahead.` If **Open Consent** appears, select it, sign in as the Senior Technician, and send the prompt again |
| `Get-ActionTrail.ps1` still lists a source as **Not found yet** | That source's records haven't arrived yet | Run the same command again a few minutes later; it overwrites both files. To see the Dataverse change now, open TCK-10562 and select **Related** > **Audit History** |
| `Get-ActionTrail.ps1` stops with *Azure CLI has no sign-in for your lab tenant* | Your Azure CLI sign-in expired | Run `az login`, sign in as the Senior Technician, and run the command again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 2: Present the Business Case

In this task, you will answer the managing director's question with what you built, using only claims that point to evidence.

1. Summarize your agent's grounding, tool design, security model and audit evidence in a short walkthrough. In **Lab notes.txt**, go to the **== Business case ==** section at the end of the file and complete the three lines below. Keep each line to a few sentences, and after each claim, name its evidence in brackets: a value from your notes, a correlation ID or an evidence file. A reviewer should be able to check every claim.

   | Line in Lab notes.txt | What to write | Evidence to point to |
   |---|---|---|
   | **What the agent does (grounding and tools)** | How it grounds and cites its answers, resolves conflicting guidance with customer attributes, and reads and changes tickets through separate read and write tools | **Index document count**, **First grounded answer: article cited** and **Ambiguous case: articles, recommendation and deciding attribute** (Exercise 1); **Tool you traced to its Dataverse query** (Exercise 3); **Your scoped tool: name, description, permission and approval** (Exercise 4); your **TCK-10562** line |
   | **Controls (identity, least privilege, approval, data protection, audit)** | One sentence per control: whose identity each call uses, how access is narrowed, what needs approval, what the agent never receives, and how one action is traced | **Identities on one write: user, Agent ID, gateway, MCP managed identity, Dataverse application user**, **Backend credential: Key Vault secret name, and the access log entry at startup**, **Boundary you narrowed, and the Dataverse error** and **Tier 1 attempt (denied) and Senior attempt (allowed), with correlation IDs** (Exercise 5); **Approved write: ticket, change and correlation ID (you trace it in Exercise 6)**, **Declined write: ticket, and confirmed unchanged** and **Customer-visible reply and internal note: ticket and note codes** (Exercise 4); **What the agent could not return, and what it said** and **Microsoft Purview: policy, sensitive information type, label and DLP event time** (Exercise 6) |
   | **Evidence from this lab** | The records a reviewer can open to check your claims | **End-to-end trail: correlation ID and each hop you found** (Exercise 6), the four TCK-10562 correlation IDs, and the ten files in `C:\LabFiles\evidence` |

   > **[SCREENSHOT PENDING: E7T2S1 | Lab notes.txt Business case section with What the agent does, Controls and Evidence from this lab completed, each claim followed by its evidence | source: capture]**

1. State the operational value for an MSP and the controls that make it safe to deploy. Complete the other three lines of the **== Business case ==** section:

   | Line in Lab notes.txt | What to write |
   |---|---|
   | **Problem today** | The service review's findings: technicians spend about a third of their handling time searching 500 past tickets, 120 knowledge articles and 36 customer documents; new tickets wait until someone has time to triage them; 11 Platinum and Gold SLA breaches cost USD 18,400 in service credits last quarter; and an earlier automation pilot was stopped after an internal note reached a customer |
   | **Operational value for the MSP (time, consistency, SLA)** | One sentence each for time, consistency and SLA, each tied to something you saw, such as TCK-10562 triaged from its procedure and history in one conversation. End with the controls that make the agent safe to deploy: approval on every write, the technician's own permissions, protected data withheld before the agent sees it, and a trail for every change |
   | **Risks and next steps** | The limits you met in this lab and what you would do about each, such as the identity flow the playground supports, log latency and label propagation, and how a pilot would measure handling time and SLA breaches against last quarter |

   Don't put a figure on the time saved: this lab shows the steps, not a measured saving, so the measurement belongs in **Risks and next steps** as the first thing a pilot proves. When you're done, read the section from top to bottom as a one-minute answer to the managing director's question, and save the file with **Ctrl+S**. The reviewers read it, with your evidence files, after the lab window.

   > **[SCREENSHOT PENDING: E7T2S2 | Lab notes.txt with every line of the Business case section completed and saved | source: capture]**

If you're unsure how much to write, compare your section with this example after you've written your own.

<details>
<summary>Show an example business case</summary>

- **Problem today:** Technicians spend about a third of their handling time searching 500 past tickets, 120 knowledge articles and 36 customer documents, new tickets wait until someone has time to triage them, and last quarter 11 Platinum and Gold SLA breaches cost USD 18,400 in service credits. An earlier automation pilot was stopped after an internal note about an invoice dispute reached a customer.
- **What the agent does (grounding and tools):** It answers from an index of 753 Service Desk documents and cites each record (KB0007 for RBA-1043; KB0058 for Woodgrove Bank, decided by its firmware and client versions). It reads live tickets through 16 read tools and changes them only through 7 approval-gated write tools, plus the scoped tool I added. It took TCK-10562 from New to a cited triage, an assignment and a customer reply in one conversation.
- **Controls (identity, least privilege, approval, data protection, audit):** Every call runs as the signed-in technician, so Dataverse applies that person's role: it refused the Tier 1 Technician's priority change and allowed mine. Read and write tools sit on separate connections, and every write waited for my approval. The backend credential stays in Key Vault. Column security, a Microsoft Purview DLP policy and a sensitivity label kept contact details, a card number and a labeled document from the agent, and no internal note reached a customer reply. One correlation ID follows each action through every log.
- **Evidence from this lab:** My notes hold the correlation IDs of the approved and denied writes in Exercises 4 and 5, the declined change that left TCK-10544 unchanged, the Exercise 6 trail of the TCK-10544 priority change, and the four TCK-10562 trails exported to C:\LabFiles\evidence.
- **Operational value for the MSP (time, consistency, SLA):** Time: the search that takes a third of handling time becomes one cited answer. Consistency: the agent triages with the customer's own procedure and the desk's own history, so TCK-10562 got P2 from CUST-020-PR3 and Daniel Cho from the KB0133 pattern. SLA: a new ticket gets its priority, its 16-hour target and a technician at intake instead of waiting in the queue, and SLA risk is ranked in business hours before a breach, the kind of breach that cost USD 18,400 last quarter. It is safe to deploy because no change happens without a person's approval, the agent never has more access than the person asking, protected data never reaches it, and every change can be traced.
- **Risks and next steps:** The playground passes the technician's own token through OAuth identity passthrough, because the agent-on-behalf-of-user flow is still in preview. Logs and traces arrive minutes after an action, and sensitivity labels can take up to 24 hours to apply. Next: a pilot with one customer that measures handling time and SLA breaches against last quarter, with every customer-visible reply reviewed before approval.

</details>

### Expected results

- [ ] Every line of the **== Business case ==** section in **Lab notes.txt** is filled in, and the file is saved
- [ ] Each claim names its evidence: a value from your notes, a correlation ID or a file in `C:\LabFiles\evidence`
- [ ] **Problem today** and **Operational value for the MSP (time, consistency, SLA)** use the lab's numbers: about a third of handling time, 11 Platinum and Gold breaches and USD 18,400 in service credits
- [ ] **Risks and next steps** names at least two limits you met in this lab and what you would do about each

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| A value from an earlier exercise is missing from your notes | The step was skipped or not recorded | Every write's correlation ID is under **Work** > **Agent Actions** in the Service Desk app. If you can't find the evidence for a claim, leave the claim out and say so in **Risks and next steps** |
| You aren't sure a claim is backed by evidence | It describes what the agent could do, not what you saw | Keep only claims you can point to, and move the rest to **Risks and next steps** as something to test in a pilot |
| Your changes to **Lab notes.txt** are gone | Notepad was closed without saving | Reopen **Lab notes.txt** from the desktop, complete the section again, and press **Ctrl+S**; the reviewers read the saved file |

## Success Criteria

You have completed this exercise when:

- [ ] **TCK-10562** shows **In Progress**, **P2 High**, **Line-of-Business App**, **Certificate**, **Daniel Cho** and an **SLA Target (business hours)** of **16**, with a customer-visible reply
- [ ] Every change on TCK-10562 waited for your approval: **Agent Actions** lists four rows for it, each **Allowed** and **Succeeded**, each with its own correlation ID
- [ ] `C:\LabFiles\evidence` holds the JSON and Markdown trail of each of the four writes
- [ ] **Lab notes.txt** holds your TCK-10562 line and a complete business case that cites your evidence
- [ ] Negative check: the agent made no change to **TCK-10559** or **TCK-10524** (**Agent Actions** shows no row for either from this exercise, and TCK-10559 is still in **Untriaged Tickets**), and the reply on TCK-10562 contains nothing from an internal note

## Apply It in Production

**What you built:**

- An agent that takes a new incident from intake to a cited triage, an assignment and a customer reply in one conversation, with every change approved and made as the technician who asked.
- A trail for every write: one correlation ID that joins your approval, the gateway and MCP server logs, the Dataverse audit and an Agent Action row, exported for reviewers.

**Decisions to make before production:**

1. **Identity flow.** The lab passes the technician's token through OAuth identity passthrough, because the agent-on-behalf-of-user flow is in preview and doesn't run in the playground. Decide which flow you ship and how each call records the agent's identity.
1. **Approval at volume.** Four approvals per incident is safe but slow at scale. Decide whether a low-risk write, such as an internal note, may ever skip approval; customer-visible replies and SLA changes keep theirs.
1. **Evidence retention.** Log Analytics includes 31 days of retention, and Dataverse audit retention needs an explicit setting because Microsoft's pages give different defaults. Match both to your customers' audit periods.
1. **Rollout scope.** Start with one customer and the categories whose procedures are current, and measure handling time and SLA breaches against last quarter first.

**Production checklist:**

- [ ] Customer procedures and configuration notes are current, because the agent applies them (CUST-020-PR3 decided P2 here)
- [ ] Every write tool, including each new one, stays on the approval-required connection
- [ ] API Management runs on a production tier: the Developer tier is for nonproduction use and has no SLA
- [ ] Alerts fire on denied writes, Purview blocks and tool failures
- [ ] Rollback is rehearsed for the MCP server revision and the agent version

**Common pitfalls:**

| Pitfall | How to avoid it |
|---|---|
| Approving by habit once the agent has been right a few times | Check every argument, keep one change per approval, and expect each reason to cite a record |
| A customer reply drafted from everything the agent has read | Draft replies from customer-visible notes only, and read every reply before you approve it |

## Knowledge Check

**Question 1:** TCK-10559 and TCK-10524 show the same certificate warning as TCK-10562 and follow the same KB0133 and RB-005. Why must the agent keep them apart?

<details>
<summary>Show the answer</summary>

Because the same fix doesn't make the same incident. TCK-10559 is Lucerne Publishing's payroll application on LPAPP01, which Lucerne's own IT team administers, and TCK-10524 is Humongous Insurance's claims application on APP03, while TCK-10562 is Consolidated Messenger's CMRT-N01 at the north depot. Each has its own customer, SLA, contacts and approvals, and linking them would put one customer's details into another customer's ticket.

</details>

**Question 2:** The agent recommended a Vendor escalation, yet none of your four approvals escalated the ticket. Why is that the right call?

<details>
<summary>Show the answer</summary>

Consolidated Messenger's escalation procedure, CDOC-030, sends the incident to the routing application vendor when the binding or the application itself is at fault, and asks for the vendor's case number in the ticket. Only Daniel Cho's check of CMRT-N01 can establish that. The history of seven P2 KB0133 tickets escalated to the Vendor tells you to expect the escalation, not to make it unseen.

</details>

**Question 3:** The agent reported every change with its correlation ID. What does the exported trail prove that the agent's own report can't?

<details>
<summary>Show the answer</summary>

The report is the model's account of what it did. The trail is made of records the agent can't write: your approval in the conversation, the gateway log of your validated token, the MCP server's authorization result and backend calls, the Dataverse audit of the change made for your account, and the Agent Action row, all joined by the same correlation ID.

</details>

## Summary

In this exercise, you have completed the following:

- Opened the second new incident, TCK-10562 from Consolidated Messenger, in the **Untriaged Tickets** view.
- Had the agent identify the customer, apply its dispatch procedure, the KB0133 history and the routing application's configuration notes, and recommend a cited triage while keeping two similar incidents apart.
- Approved four writes after checking their arguments: the category, the priority, the assignment and a customer-visible reply with no internal content.
- Exported the correlated audit trail of every write to `C:\LabFiles\evidence` as evidence for the reviewers.
- Wrote the business case: the problem, what the agent does, its controls, the evidence and the operational value for an MSP.

## Congratulations

You've completed the Agentic MSP Support Agent Guided Lab. Here is how you answered each question Relecloud's leaders asked:

- **Exercise 1:** The service desk manager asked whether the agent answers from Relecloud's own data. It does: you grounded it in 753 Service Desk documents, and every answer cites its record, down to KB0058 for Woodgrove Bank.
- **Exercise 2:** The support lead asked whether it triages like the best technician. You saw it triage TCK-10561 from the KB0023 pattern and rank SLA risk in business hours before a breach.
- **Exercise 3:** The platform engineering lead asked what the agent can read and what happens when a call fails. You traced the read tools to their Dataverse queries, saw structured errors instead of stack traces, and redeployed your own MCP server.
- **Exercise 4:** The head of service delivery asked how Relecloud stays in control. Every write waited for your approval, the customer reply stayed separate from the internal note, and you tightened one tool and added another.
- **Exercise 5:** The CISO asked whose permissions the agent uses. The signed-in technician's: Dataverse refused the Tier 1 Technician a change it allowed you, and the backend secret stayed in Key Vault.
- **Exercise 6:** The data protection officer asked for proof. Contact details, a card number and a labeled document never reached the agent, and one correlation ID led you through every log.
- **Exercise 7:** The managing director asked whether to offer the agent to customers. You answered with TCK-10562, handled end to end through four approved, traced writes, and a business case built on your own evidence.

### Take It to Your Team

These are the patterns from this lab worth reusing, and how to reuse them safely:

| Asset | Where you used it | Reuse it safely |
|---|---|---|
| The MCP server and its tool contract | `C:\LabFiles\mcp-server`: read and write tools apart, input validation, structured errors and one log line per call | Keep every write tool on the approval-required connection and every secret in Key Vault, and run the tests before each release |
| The grounded agent instructions | `C:\LabFiles\agent\instructions-grounded.md` | Keep the rules to cite every source, to say when the data runs out and to keep internal notes out of customer replies, and test them with unanswerable questions after every change |
| `Get-ActionTrail.ps1` | `C:\LabFiles\tools`, with your evidence in `C:\LabFiles\evidence` | It redacts tokens and card-like numbers, but read an export before you share it, because prompts and answers can carry customer details |
| The Dataverse permission model | Separate read and write roles, the column security profile **Contact Phone Protection**, and auditing | Start every new identity with no access and grant only what one tool needs |
| Your business case | The **== Business case ==** section of **Lab notes.txt** | Replace the lab's numbers with your own measurements before you show it to anyone, and confirm current prices and licensing with Microsoft |

The organization running this workshop receives the MCP server source, the Bicep templates, the API Management policies, the Dataverse solution, the agent definition and the Purview configuration runbook behind this lab, so you don't need to copy anything out of this environment. All of its data is synthetic: Relecloud Managed Services and its customers are fictional.

### Leave Your Environment As It Is

There's nothing to clean up, and you shouldn't delete or reset anything: the index, agent versions, MCP server revisions, roles, notes and evidence files are what the reviewers judge. They work in this environment for 24 hours after your lab window, and then the whole environment is deleted for you. Before the window closes, save **Lab notes.txt** with **Ctrl+S** and check that `C:\LabFiles\evidence` holds your evidence files. Don't run `Update-AgentDefinition.ps1 -Reset`, and don't roll back your MCP server.

### Support Contact

The CloudLabs support team is available 24/7, 365 days a year, via email and live chat.

- Email Support: cloudlabs-support@spektrasystems.com
- Live Chat Support: https://cloudlabs.ai/labs-support

When you contact support, include your Deployment ID: <inject key="DeploymentID" enableCopy="true"/>
