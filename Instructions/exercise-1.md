# Exercise 1: Environment Readiness and Grounding the Agent

### Estimated Duration: 50 minutes

## Scenario

Before Relecloud lets an agent near its queue, the automation team has to prove two things: that the team environment is complete, and that the agent answers from Relecloud's own Service Desk data rather than from general knowledge. Engineers lose a third of their handling time hunting through old tickets, runbooks and articles; an agent that guesses would make that worse, not better.

## Overview

In this exercise, you confirm that every component of your team environment responds before you build anything. You then build an Azure AI Search index over the Service Desk content (knowledge articles, runbooks, customer profiles and procedures, and the ticket history), load it, and connect it to the agent as its knowledge source. Finally, you test the grounded agent on simple questions, on an ambiguous case where two knowledge articles describe the same symptom, and on its ability to explain its own reasoning.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Verify Readiness
- Task 2: Connect the Agent to the Knowledge Base
- Task 3: Test Retrieval on Simple Questions
- Task 4: Resolve an Ambiguous Case
- Task 5: Explain the Reasoning

## Task 1: Verify Readiness

In this task, you will confirm every component responds before building anything. If any check fails, stop and contact support rather than working around it.

1. Sign in with your team's **Senior Technician** credentials and launch your assigned lab. You did this on the getting-started page: the VM is open, the Azure portal and the Azure CLI are signed in as <inject key="AzureAdUserEmail" enableCopy="false"/>. Use this account for the whole lab unless a step says otherwise.

1. Run the readiness check on your lab VM desktop and confirm every component reports ready. Double-click **Lab readiness check** on the desktop. It needs no sign-in: it checks the environment with the lab VM's own identity and prints one row per component.

   | Component | What it checked |
   |---|---|
   | **Azure resources** | The resource group holds the Container App, API Management, Foundry, AI Search, Key Vault and Container Registry |
   | **Service Desk app and data** | The app exists and every seeded table holds the expected rows, plus the two new incidents |
   | **Tier 1 Technician** | The second identity is a user of the Service Desk environment with the read-only **Service Desk Tier 1 Technician** role |
   | **Foundry agent** | `msp-support-agent` has its Microsoft Entra Agent ID and the Service Desk MCP tool, and no knowledge source |
   | **MCP connection** | The project connection `servicedesk-mcp` uses OAuth identity passthrough to your API Management gateway |
   | **MCP server** | `/health` is ok, the server read its gateway key from Key Vault, and it acts on behalf of the signed-in user |
   | **Baseline read tool** | `get_ticket` for TCK-10489 returned real ticket data through API Management |
   | **Search content** | The export you load into the index in Task 2 holds the expected 561 documents |

   Every row shows **Ready**, and the last line reads *Every component is ready. You can start Exercise 1.* In **Lab notes.txt**, next to **Readiness check**, record the result.

   > **[SCREENSHOT PENDING: E1T1S2 | Lab readiness check window with every component Ready | source: capture]**

   > **Important:** If any row shows **Not ready**, stop here and contact support with a screenshot of the table and your Deployment ID: <inject key="DeploymentID" enableCopy="true"/>. Don't work around a failed component.

1. Open the Service Desk app and confirm the seeded data is present: customer profiles and procedures, knowledge articles, technicians, SLA definitions and historical tickets. On the VM desktop, double-click the **Service Desk** shortcut and sign in as the Senior Technician if you are asked. Open each table below, select the view, and compare the row count at the bottom of the list. Use the area switcher at the bottom of the left navigation to move between the **Service Desk**, **Knowledge** and **Configuration** areas.

   | Navigation | View | Expected rows |
   |---|---|---|
   | **Customers** > **Accounts** | **Managed Customers** | 24 customer profiles |
   | **Customers** > **Customer Procedures** | **Customer Procedures** | 63 agreed procedures (escalation contacts, change windows, billing and data handling rules) |
   | **Customers** > **Contacts** | **Customer Contacts** | 72 |
   | **Knowledge** area > **Knowledge Articles** | **All Articles** | 50 (49 Published, 1 Retired) |
   | **Knowledge** area > **Runbooks** | **All Runbooks** | 12 |
   | **Configuration** area > **Technicians** | **Active Technicians** | 12 (Marcus Webb is not available) |
   | **Configuration** area > **SLA Policies** | the default view | 16 SLA definitions (4 tiers by 4 priorities) |
   | **Work** > **Tickets** | **All Tickets** | 476 historical and open tickets |
   | **Work** > **Tickets** | **Open Tickets** | 45 |
   | **Work** > **Tickets** | **Untriaged Tickets** | 5, including the two new incidents **TCK-10514** and **TCK-10515** |
   | **Work** > **Ticket Notes** | **All Ticket Notes** | 1,203 |

   Then open ticket **TCK-10489** from the **Open Tickets** view and look at its **SLA** section. **SLA Target**, **SLA Elapsed** and **SLA Remaining** are in business hours, and **SLA Calculated On** is the moment the figures were taken.

   > **Note:** The app's address is <inject key="Service Desk App URL" enableCopy="false"/>. If the desktop shortcut opens a different address, use the shortcut: it points to the environment that was actually created.

   > **[SCREENSHOT PENDING: E1T1S3 | Service Desk app Tickets list with the Open Tickets view and the row count | source: capture]**

1. Open your Foundry project and confirm the agent exists with its Microsoft Entra Agent ID, no knowledge source and only the baseline MCP tools.

   - On the VM desktop, double-click the **Microsoft Foundry** shortcut and sign in as the Senior Technician if you are asked. In the project selector in the top banner, select **proj-msp-<inject key="DeploymentID" enableCopy="false"/>**. Select **Build (1)** in the top navigation, then **Agents (2)**, and select the agent **msp-support-agent (3)**.
   - On the **Playground** tab, look at the agent's configuration: a model, short baseline instructions, no **Knowledge**, and one tool, the Service Desk MCP server **servicedesk**, reached through the connection **<inject key="MCP Connection Name" enableCopy="false"/>**.
   - In PowerShell 7 on the VM, show the agent's identity:

     ```powershell
     C:\LabFiles\tools\Get-AgentIdentity.ps1
     ```

     **Entra Agent ID object ID** is the agent's identity in Microsoft Entra ID; you look it up in Exercise 5.

   > **Note:** These steps use the current Foundry portal. If the portal opens in the classic experience, turn on the **New Foundry** toggle in the top banner. Portal labels change often; if a label in this guide differs slightly, look for the closest match.

   > **Note:** The playground runs evaluators on every answer by default, and those evaluations are billed and use your team's model capacity. Select the metrics control in the upper right of the playground and clear all evaluators. Do this once; the setting applies to the rest of the lab.

   > **[SCREENSHOT PENDING: E1T1S4 | Agent playground showing the servicedesk MCP tool and no knowledge source | source: capture]**

1. Invoke one baseline read tool through Azure API Management and confirm it returns real ticket data. In the playground, start a new chat and send:

   ```
   Use the Service Desk tools to get ticket TCK-10489 and tell me its status, priority, assigned technician and SLA remaining.
   ```

   The first time you use the tool, the playground shows a consent request for the Service Desk connection. Select **Open consent**, sign in as the Senior Technician, accept, close the confirmation window, and send the message again if the playground asks you to. You consent once; the agent then calls the gateway with your own token.

   The agent calls **get_ticket** without asking for approval, because read tools never need it. Expect **TCK-10489** *Claims team cannot open policy documents* for **Humongous Insurance**: **In Progress**, **P2 High**, **Daniel Cho**, **1.0** of 8 business hours remaining. Compare it with the record you opened in the Service Desk app.

   > **[SCREENSHOT PENDING: E1T1S5 | Agent answer for TCK-10489 from the get_ticket tool | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

### Expected results

- [ ] The readiness check reports every component **Ready**
- [ ] The Service Desk app row counts match the table above
- [ ] The agent has its Entra Agent ID, the **servicedesk** MCP tool and no knowledge source
- [ ] get_ticket returned the live TCK-10489 record, and its details match the app

## Task 2: Connect the Agent to the Knowledge Base

In this task, you will build the agent's knowledge source. Azure AI Search is provisioned but holds no index; nothing is grounded until you build one.

1. Review the customer documentation, knowledge articles and ticket history, and identify which fields carry text worth retrieving.

   - In Microsoft Edge on the VM, open Power Apps and, in the environment selector at the top right, select **Relecloud Service Desk <inject key="DeploymentID" enableCopy="false"/>**:

     ```
     https://make.powerapps.com
     ```

   - Select **Tables** and review the columns of these tables (open the table, then **Schema** > **Columns**):

     | Table | Text worth retrieving | Attributes that tell similar records apart |
     |---|---|---|
     | **Knowledge Article** | **Title**, **Symptom**, **Cause**, **Resolution** | **Applies to Versions**, **Applies to SLA Tiers**, **Applies to Contract Types**, **Article Status** |
     | **Runbook** | **Name**, **Trigger**, **Steps**, **Escalation Path** | **Category**, **Product**, **Related Articles** |
     | **Account** and **Customer Procedure** | **Description** (profile), procedure **Details** | **SLA Tier**, **Contract Type**, product versions |
     | **Ticket** | **Title**, **Description**, **Resolution Summary** | **Category**, **Priority**, **Product Version**, **Related Article**, escalation and SLA columns |

   - Open the content the index is loaded from, which provisioning exported from your Dataverse environment:

     ```powershell
     code C:\LabFiles\search\export\documents.json
     ```

     Each document has a `content` text and the attributes from the table. Three things are deliberately left out:

     | Left out | Why |
     |---|---|
     | **Ticket notes** | Internal notes hold billing disputes, blame and even card details that must never reach an answer. The agent reads notes only through a tool that withholds internal notes by default. |
     | **Contact email and phone numbers** | Personal data that answering a support question doesn't need. |
     | **Customer documents** | Configuration documents carry sensitivity labels. You see what happens when the agent asks for one in Exercise 6. |

     The two new incidents are not in the export either: provisioning exported the content before it loaded them, so your agent has never seen them. You use them in Exercises 2 and 7.

   > **[SCREENSHOT PENDING: E1T2S1 | Knowledge Article table columns in Power Apps | source: capture]**

1. Create an Azure AI Search index with the fields your agent needs to cite a source, not just answer from it.

   - Open the index definition in Visual Studio Code:

     ```powershell
     code C:\LabFiles\search\index-definition.json
     ```

     | Field | Purpose |
     |---|---|
     | `title` | The citation title, for example *KB0058: Remote Access tunnel resets hourly after Secure Gateway firmware 10.1* |
     | `url` | A link to the record in the Service Desk app, so a citation opens the source |
     | `sourceId` | The article number, runbook code, ticket number or customer code |
     | `content` | The text the agent reads |
     | `docType`, `customerCode`, `slaTier`, `contractType`, `productVersion`, `articleStatus` | Filterable attributes that tell two similar documents apart |
     | `contentVector` | The embedding of `content`. The loader computes it with `text-embedding-3-small`; the index's vectorizer embeds each question the same way at query time, so vector and hybrid search work. |

   - In PowerShell 7, create the index:

     ```powershell
     C:\LabFiles\search\New-SearchIndex.ps1
     ```

     The output reports the index **servicedesk-knowledge** with **26** fields and lists them.

   > **Note:** The Foundry Azure AI Search tool needs a retrievable `url` field, and optionally `title`, to produce citations. Without them the agent can answer but can't link to its source.

1. Load the content into the index and confirm the document count matches the seeded data. In PowerShell 7, run:

   ```powershell
   C:\LabFiles\search\Load-SearchIndex.ps1
   ```

   The script embeds every document, uploads it, and compares the counts. It takes around **3 to 6 minutes**; while it runs, start the next step. When it finishes, its last line reads **Document count matches the seeded data.** and the index holds **561** documents: 50 knowledge articles, 12 runbooks, 474 tickets, 24 customer profiles and one SLA snapshot. In the Azure portal, open **srch-msp-<inject key="DeploymentID" enableCopy="false"/>** > **Search management** > **Indexes** and confirm that **servicedesk-knowledge** shows 561 documents.

   > **Note:** Your embedding deployment accepts about 30,000 tokens a minute, so the script pauses when it is rate limited and prints *The embedding deployment is rate limiting; waiting ...*. That is expected; let it finish.

   > **Note:** Each customer profile also lists the customer's procedures and open tickets, and the SLA snapshot ranks every open ticket by remaining business hours and holds the SLA targets and priority rules. A search returns the few most relevant documents, not a sorted or complete list, so questions about "all open tickets for a customer" or "closest to breach" need a document that already holds the list.

   > **[SCREENSHOT PENDING: E1T2S3 | Load-SearchIndex.ps1 output with the count table and the match message | source: capture]**

1. Add the search index as a knowledge source on your Foundry agent.

   - In the Foundry portal, select **Manage** in the top navigation, then **Project details**, and select the **Connected resources** tab. Select **Add connection (1)**, select **Azure AI Search (2)**, browse for your search service **srch-msp-<inject key="DeploymentID" enableCopy="false"/> (3)**, and for **Authentication** choose the keyless **Microsoft Entra ID** option **(4)**. Select **Add connection (5)**.
   - Go back to **Build** > **Agents** > **msp-support-agent**. On the **Playground** tab, under **Knowledge**, select **Add**, choose **Azure AI Search**, select the connection you created and the index **servicedesk-knowledge**, and choose the hybrid search type (vector and semantic) if it is offered.
   - Replace the agent's **Instructions** with the grounded instructions: in Visual Studio Code, open `C:\LabFiles\agent\instructions-grounded.md`, copy all of it, paste it over the current instructions, and select **Save**. Read the rules about citing sources, saying *I can't find that in the Service Desk data*, choosing between articles, and never quoting internal notes.

   > **Note:** If your portal doesn't offer these options, run the fallback in PowerShell 7 instead. It creates the same knowledge tool on `servicedesk-knowledge` (hybrid search, 10 results), keeps the Service Desk MCP tool, and applies the grounded instructions:

   ```powershell
   C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge
   ```

   > **Note:** With keyless authentication, Foundry queries the index with a managed identity that already holds the search roles the tool requires, so no key is stored in the connection.

   > **[SCREENSHOT PENDING: E1T2S4 | Agent playground showing the Azure AI Search knowledge source and the grounded instructions | source: capture]**

1. Run a first query and confirm the answer draws on indexed content rather than on the model's own training. Start a new chat and ask a question that only your index can answer:

   ```
   Which Remote Access client version and Secure Gateway firmware does Woodgrove Bank run, and which procedures has Relecloud agreed with them?
   ```

   Confirm the answer: Woodgrove Bank (CUST-007) runs **Remote Access client 4.2.0** and **Secure Gateway firmware 10.1.4**, and its procedures are **escalation contacts** (the IT manager first, then the executive sponsor), the **change and maintenance window** (Tuesday and Thursday, 20:00 to 23:00), and **branch and mortgage team connectivity** (Remote Access problems for those teams are P2). The answer carries a citation to the customer profile; select it and check that it opens the Woodgrove Bank record in the Service Desk app.

   > **[SCREENSHOT PENDING: E1T2S5 | Grounded answer about Woodgrove Bank with a citation to the customer profile | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Knowledge index loaded and connected" is registered (validation-scripts/README.md). -->

## Task 3: Test Retrieval on Simple Questions

In this task, you will prove the grounding works before you trust it with anything harder.

1. Ask about a named customer and confirm the answer references that customer's own profile and procedures. Start a new chat and send:

   ```
   Summarize the profile of Humongous Insurance: SLA tier, contract type, managed seats, deployed product versions, account manager, and the procedures Relecloud has agreed with them.
   ```

   Expect Humongous Insurance (CUST-013): **Platinum**, **Fully Managed**, **510** seats, Backup Agent **5.2.1**, Remote Access **4.2.0**, Secure Gateway **10.1.4**, Endpoint Agent **7.4.1**, account manager **Isabel Grant**, and three procedures: **escalation contacts** (Kofi Kim, then Alma Ivanova), the **change and maintenance window**, and **claims intake hours** (an outage of the document management application from 08:00 to 18:00 is P2 or higher, and service credits need the account manager's approval). The answer cites the customer profile.

1. Ask about a known product issue and confirm a specific knowledge article is cited by title or identifier:

   ```
   A file server backup failed overnight with RBA-1043, snapshot provider timed out. Which knowledge article applies, and what are the steps?
   ```

   Expect **KB0007** *Backup job fails with RBA-1043: snapshot provider timed out*, with its steps, and possibly the runbook **RB-001** *Backup failure triage*. The agent must not recommend **KB0019**, which is **Retired**; if it mentions KB0019 at all, it should say that it is retired.

   > **[SCREENSHOT PENDING: E1T3S2 | Agent answer citing KB0007 with its resolution steps | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Ask a question the seeded data cannot answer and confirm the agent says so rather than inventing a response:

   ```
   What is Woodgrove Bank's monthly contract value?
   ```

   Expect *I can't find that in the Service Desk data*, with a short note of what it looked for. Contract values are not in the data. If an answer in this task has no citation, or states a fact you can't find in the Service Desk app, record the question in **Lab notes.txt** under **Thin explanations to revisit in Exercise 6**.

### Expected results

- [ ] The customer answer matches the Humongous Insurance record, includes its procedures, and cites the profile
- [ ] The RBA-1043 answer cites KB0007 by number and title and doesn't recommend KB0019
- [ ] The contract value question is answered with *I can't find that in the Service Desk data*, not a number

## Task 4: Resolve an Ambiguous Case

In this task, you will make the agent choose between knowledge articles that conflict unless customer context is applied. The dataset contains them deliberately.

1. Find two knowledge articles that address the same symptom with different resolutions. Start a new chat and send:

   ```
   Find the knowledge articles about Remote Access users being disconnected roughly every hour. For each article, give the number, title, the versions it applies to, and the resolution.
   ```

   Expect **KB0031** *Remote Access client disconnects every 60 minutes (client 3.x)*, which says to upgrade the client to 4.2.0 and not to change IKE settings, and **KB0058** *Remote Access tunnel resets hourly after Secure Gateway firmware 10.1*, which says to set the IKE phase 1 lifetime on the gateway to 28800 seconds and not to reinstall the client. Both describe the same symptom and the same log line, `RRA-4012 tunnel reset by peer`.

1. Ask the agent to recommend one of them for a specific named customer:

   ```
   Woodgrove Bank users are being disconnected from Remote Access every hour. Which knowledge article should we follow for Woodgrove Bank, and why? Then answer the same question for A. Datum Corporation.
   ```

   > **[SCREENSHOT PENDING: E1T4S2 | Agent recommendation for Woodgrove Bank naming client 4.2.0 and firmware 10.1.4 | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Confirm the justification names the customer attribute that decides it, such as SLA tier, product version or contract type. Here it is the **product version**:

   | Customer | Remote Access client | Secure Gateway firmware | Article |
   |---|---|---|---|
   | Woodgrove Bank (CUST-007) | 4.2.0 | 10.1.4 | KB0058 |
   | A. Datum Corporation (CUST-019) | 3.9.2 | 9.6.2 | KB0031 |

   Verify the attributes in the Service Desk app: open **Customers** > **Accounts**, select the **Managed Customers** view, and compare the **Remote Access Client Version** and **Secure Gateway Firmware** columns. Then open **KB0058** in **Knowledge Articles** and read its **Applicability** section.

   > **Note:** The data holds more pairs like this. KB0012 and KB0013 split on **SLA tier**, and KB0044 and KB0045 split on **contract type**. If you have time, ask the agent how to handle a firewall rule request for Margie's Travel (Break-Fix) and for Woodgrove Bank (Fully Managed).

### Expected results

- [ ] The agent lists both KB0031 and KB0058 with their applicability
- [ ] The Woodgrove Bank recommendation is KB0058 and names client 4.2.0 and firmware 10.1.4 as the reason
- [ ] The A. Datum Corporation recommendation is KB0031 and names client 3.9.2 as the reason

## Task 5: Explain the Reasoning

In this task, you will ask the agent to show its sources. Whatever the agent cannot explain here is what you will struggle to audit later.

1. Ask the agent to list every source it used for the previous answer and why it preferred them. In the same chat, send:

   ```
   List every source you used for your Woodgrove Bank recommendation, with the article, ticket or customer number for each, and explain why you preferred KB0058 over KB0031. Quote the applicability you compared and the customer values you compared it with.
   ```

   > **[SCREENSHOT PENDING: E1T5S1 | Agent explanation comparing the KB0058 and KB0031 applicability with Woodgrove Bank's versions | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Note where the explanation is thin or unverifiable, and keep that note for Exercise 6. An explanation is thin if it names no source, names a source but not the deciding attribute, or states a value you can't find on the record. In **Lab notes.txt**, under **Thin explanations to revisit in Exercise 6**, record each one with its question and the time in UTC, which you can get in PowerShell 7 with `(Get-Date).ToUniversalTime()`. In Exercise 6 you follow one request through every log.

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The readiness check reports a component Not ready:** contact support with the table and your Deployment ID. Don't continue until it is fixed.
- **A script says to run `az login` first:** sign in to the Azure CLI again as described on the getting-started page, then rerun the script.
- **The consent window fails with a redirect error:** contact support; the Service Desk connection's redirect address is registered once for the tenant.
- **Creating the index returns 403:** your role on the search service may still be propagating. Check that `az account show` shows the Senior Technician, wait two minutes and run the script again.
- **The loader stops with an error:** run `C:\LabFiles\search\Load-SearchIndex.ps1` again. It uploads with merge-or-upload, so a rerun is safe.
- **The agent answers without citations:** start a new chat. If the **Azure AI Search** knowledge isn't listed on the agent, run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge`.
- **A Foundry portal label differs from this guide:** look for the closest match; the steps follow the current portal, which changes often.

</details>

## Summary

In this exercise, you have completed the following:

- Confirmed with the readiness check that every component of the environment is ready, and checked the seeded data, the agent and a baseline read tool yourself
- Reviewed which Service Desk fields carry retrievable text and which content is deliberately left out
- Created the `servicedesk-knowledge` index with the fields needed to cite a source, and loaded 561 documents
- Connected the index to the agent as its knowledge source with keyless authentication and grounded instructions
- Tested simple retrieval, an unanswerable question, and an ambiguous case decided by product version
- Asked the agent to explain its sources and recorded thin explanations for Exercise 6

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
