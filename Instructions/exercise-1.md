# Exercise 1: Environment Readiness and Grounding the Agent

### Estimated Duration: 35 minutes

## Scenario

"Can the agent answer from our own data, and show us where every answer came from?" Relecloud's service desk manager asks it first, because last quarter's review found that technicians spent about a third of their handling time searching 500 past tickets, 120 knowledge articles and 36 customer documents. An agent that answers from the model's general knowledge would be worse than no agent: it would sound right and be wrong about Relecloud's customers. In this exercise you confirm that your environment is ready, build the search index the agent grounds on, and prove that every answer cites a Relecloud record, including when two articles disagree.

## Overview

In this exercise, you check every component of your environment with the readiness check, then build the `servicedesk-knowledge` index from the Service Desk content that provisioning exported to Blob Storage and add it to `msp-support-agent` as a knowledge source. You test retrieval on simple questions, resolve an ambiguous case where two articles conflict until you apply the customer's own product versions, and ask the agent to explain which sources it used.

![Five steps from the exported Service Desk records to a cited answer: review the export, create the index with citation fields, load and count, add the index to the agent, and ask with citations, with an ambiguous case resolved by Woodgrove Bank's product versions](./media/exercise-1-grounding.png)

How to read this diagram: the five numbered steps across the top are Task 2 of this exercise. The terminal types the script that creates and loads the index, and the lower lane shows the data moving from Dataverse through the Blob container `servicedesk-export` and the indexer into `servicedesk-knowledge`, and from there to `msp-support-agent`. The note at the bottom plays Task 4: two articles describe the same hourly Remote Access drop, and Woodgrove Bank's product versions select KB0058, not KB0031.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Verify Readiness
- Task 2: Connect the Agent to the Knowledge Base
- Task 3: Test Retrieval on Simple Questions
- Task 4: Resolve an Ambiguous Case
- Task 5: Explain the Reasoning

## Task 1: Verify Readiness

In this task, you will confirm that every component responds before you build anything. If any check fails, stop and contact support rather than working around it.

1. Sign in with your Senior Technician credentials and launch your assigned lab. You did this on the getting-started page: the VM is open, and the Azure portal and the Azure CLI are signed in as <inject key="AzureAdUserEmail" enableCopy="false"/>. Use this account for the whole lab unless a step says otherwise.

1. Run the readiness check on your lab VM desktop and confirm every component reports ready. Double-click **Lab readiness check** on the desktop. It needs no sign-in: it checks the environment with the lab VM's own identity and prints one row per component.

   | Component | What it checked |
   |---|---|
   | **Golden Environment** | The environment was built from Golden Environment **v1.0** |
   | **Azure resources** | The resource group holds the Container App, API Management, Foundry, AI Search, the storage account, Key Vault and the container registry |
   | **Service Desk app and data** | The app exists and every seeded table holds the expected rows, plus the two new incidents |
   | **Tier 1 Technician** | The second identity is a user of the Service Desk environment with the read-only **Service Desk Tier 1 Technician** role |
   | **Foundry agent** | `msp-support-agent` has its Microsoft Entra Agent ID, the two Service Desk MCP tools, and no knowledge source |
   | **MCP connections** | The connections `servicedesk-read` and `servicedesk-write` use OAuth identity passthrough to your API Management gateway |
   | **MCP server** | `/health` is ok, the server read its gateway key from Key Vault, and it acts on behalf of the signed-in user |
   | **Baseline read tool** | `get_ticket` for TCK-10524 returned real ticket data through API Management |
   | **Search export** | The export you index in Task 2 holds the expected 753 documents |
   | **Microsoft Purview** | The sensitivity label and the data loss prevention policy are in place |

   Every row shows **Ready**, and the last line reads *Every component is ready. You can start Exercise 1.* In **Lab notes.txt**, next to **Readiness check and Golden Environment version**, record the result and **v1.0**.

   > **[SCREENSHOT PENDING: E1T1S2 | Lab readiness check window with every component Ready | source: capture]**

   > **Important:** If any row shows **Not ready**, stop here and contact support with a screenshot of the table and your Deployment ID: <inject key="DeploymentID" enableCopy="true"/>. Don't work around a failed component.

1. Open the Service Desk app and confirm the seeded data is present: customer profiles and procedures, knowledge articles, technicians, SLA definitions and historical tickets. On the VM desktop, double-click the **Service Desk** shortcut, and sign in as the Senior Technician if you are asked. Open each table below, select the view, and compare the row count at the bottom of the list. Use the area switcher at the bottom of the left navigation to move between the **Service Desk**, **Knowledge** and **Configuration** areas.

   | Navigation | View | Expected rows |
   |---|---|---|
   | **Customers** > **Accounts** | **Managed Customers** | 24 customer profiles |
   | **Customers** > **Customer Procedures** | **Customer Procedures** | 63 agreed procedures |
   | **Customers** > **Customer Documents** | **All Customer Documents** | 36 (24 support policies, 6 escalation procedures, 6 configuration notes) |
   | **Customers** > **Contacts** | **Customer Contacts** | 72 |
   | **Knowledge** area > **Knowledge Articles** | **All Articles** | 120 (117 Published, 2 Draft, 1 Retired) |
   | **Knowledge** area > **Runbooks** | **All Runbooks** | 12 |
   | **Configuration** area > **Technicians** | **Active Technicians** | 15 in four teams (Marcus Webb is on leave) |
   | **Configuration** area > **SLA Policies** | the default view | 16 SLA definitions (four tiers by four priorities) |
   | **Work** > **Tickets** | **All Tickets** | 562: 500 historical, 60 open and 2 new incidents |
   | **Work** > **Tickets** | **Open Tickets** | 62 |
   | **Work** > **Tickets** | **Untriaged Tickets** | 5, including the two new incidents **TCK-10561** and **TCK-10562** |
   | **Work** > **Ticket Notes** | **All Ticket Notes** | 1,436 |

   Then open ticket **TCK-10540** from the **Open Tickets** view and look at its **SLA** section. **SLA Target (business hours)**, **SLA Elapsed (business hours)** and **SLA Remaining (business hours)** count business hours only (Monday to Friday, 08:00 to 18:00 UTC), and **SLA Calculated On (UTC)** is the moment the figures were taken.

   > **Note:** The app's address is <inject key="Service Desk App URL" enableCopy="false"/>. If the desktop shortcut opens a different address, use the shortcut: it points to the environment that was actually created.

   > **[SCREENSHOT PENDING: E1T1S3 | Service Desk app Tickets list with the Open Tickets view and its row count | source: capture]**

1. Open your Foundry project and confirm the agent exists with its Microsoft Entra Agent ID, no knowledge source and only the baseline MCP tools. On the desktop, double-click **Microsoft Foundry**, select your project **<inject key="Foundry Project Name" enableCopy="false"/>**, select **Build**, and then select **msp-support-agent**. On the **Playground** tab, expand **Tools**: it lists **servicedesk-read** and **servicedesk-write** and no knowledge tool. Then, in PowerShell 7, run the following command, which reads the agent's Entra Agent ID from the Foundry API:

   ```powershell
   C:\LabFiles\tools\Get-AgentIdentity.ps1
   ```

   The output shows the agent identity's client ID and object ID. In a new tab, open the Microsoft Entra admin center at `https://entra.microsoft.com`, select **Entra ID** > **Agents** > **Agent identities**, and search for the object ID: the agent is listed with its own identity, separate from yours. In **Lab notes.txt**, next to **Agent ID (client ID)**, record the client ID.

   > **[SCREENSHOT PENDING: E1T1S4 | Agent playground Tools section listing servicedesk-read and servicedesk-write with no knowledge source | source: capture]**

   > **Note:** Viewing agent identities needs no administrator role. The Foundry portal does not show the agent identity itself, which is why the script reads it from the agent's definition.

1. Invoke one baseline read tool through Azure API Management and confirm it returns real ticket data. Run the following command, which calls `get_ticket` through the gateway's diagnostics API:

   ```powershell
   C:\LabFiles\tools\Invoke-McpTool.ps1 get_ticket @{ ticket_number = 'TCK-10524' }
   ```

   The result is **TCK-10524** from **Humongous Insurance**, *Claims team cannot open policy documents*, with its status, priority, SLA figures and a `correlation_id`. In **Lab notes.txt**, next to **Baseline read tool: ticket and correlation ID**, record both.

   > **[SCREENSHOT PENDING: E1T1S5 | PowerShell 7 window with the get_ticket result for TCK-10524 and its correlation_id | source: capture]**

### Expected results

- [ ] Every readiness row shows **Ready**, and you recorded the result and Golden Environment **v1.0**
- [ ] The Service Desk app views show the row counts in the table above
- [ ] `msp-support-agent` lists **servicedesk-read** and **servicedesk-write** and no knowledge tool, and you recorded its Agent ID
- [ ] `get_ticket` returned **TCK-10524** from **Humongous Insurance** with a `correlation_id`

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| A readiness row shows **Not ready** | A component failed during provisioning | Stop and contact support with the table and your Deployment ID |
| The Service Desk app asks you to sign in again or shows an access error | The app opened with another account | Sign out of the app, sign in as the Senior Technician, and open the shortcut again |
| `Invoke-McpTool.ps1` reports that it can't read the subscription key | The Azure CLI sign-in expired | Run `az login` again as the Senior Technician and repeat the command |

## Task 2: Connect the Agent to the Knowledge Base

In this task, you will build the index the agent grounds on. Azure AI Search is provisioned but holds no index: nothing is grounded until you build one.

1. Review the customer documentation, knowledge articles and ticket history, and identify which fields carry text worth retrieving. Provisioning exported the Service Desk content to the Blob container **<inject key="Export Container" enableCopy="false"/>** in the storage account **<inject key="Storage Account Name" enableCopy="false"/>**, one JSON file per document. In File Explorer, open `C:\LabFiles\search\sample-documents` and open `kb-KB0058.json` in Visual Studio Code. Then run the following command, which shows the field list the index will use and what each field is for, without creating anything:

   ```powershell
   C:\LabFiles\tools\New-KnowledgeIndex.ps1 -ReviewOnly
   ```

   Notice the split. `content` carries the text worth retrieving: an article's symptom, cause and resolution, a document's body, a ticket's description and resolution. `title`, `url` and `sourceId` carry no searchable text, but they are what the agent cites. Fields such as `customerCode`, `slaTier` and `articleStatus` let a query filter.

   > **[SCREENSHOT PENDING: E1T2S1 | New-KnowledgeIndex.ps1 -ReviewOnly output listing the fields and their purpose | source: capture]**

1. Create an Azure AI Search index with the fields your agent needs to cite a source, not just answer from it. In Visual Studio Code, open `C:\LabFiles\search\index-definition.json` and find the fields `title`, `url` and `sourceId`: each is **retrievable**, so the index returns them with every result. Then run the following command, which checks the definition and creates the index, a data source for the export container, an embedding skillset and an indexer:

   ```powershell
   C:\LabFiles\tools\New-KnowledgeIndex.ps1
   ```

   > **Note:** The search service reads the export with its own managed identity, and the embedding skill calls `text-embedding-3-small` on your Foundry resource the same way. No key is stored anywhere.

1. Load the content into the index and confirm the document count matches the seeded data. The script runs the indexer `servicedesk-export-indexer` and shows its progress, which takes about three to five minutes. When it finishes, it compares the index with the export manifest and reports **753** documents: 120 knowledge articles, 36 customer documents, 12 runbooks, 560 tickets, 24 customer profiles and 1 SLA snapshot. The two new incidents are not in the index. In the Azure portal, open your search service **<inject key="AI Search Service Name" enableCopy="false"/>**, select **Search management** > **Indexes**, and confirm that **servicedesk-knowledge** shows **753** documents. In **Lab notes.txt**, next to **Index document count**, record **753**.

   > **[SCREENSHOT PENDING: E1T2S3 | Azure AI Search Indexes page with servicedesk-knowledge and 753 documents | source: capture]**

   > **Note:** The portal can take a minute to update its document count. If it shows fewer than 753, select **Refresh**. The script's own count, which queries the index directly, is the one that matters.

1. Add the search index as a knowledge source on your Foundry agent. Run the following command, which saves a new version of `msp-support-agent` with the Azure AI Search tool on `servicedesk-knowledge` and the grounded instructions that tell the agent to cite every source, and keeps both MCP tools exactly as they are:

   ```powershell
   C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions
   ```

   In the Foundry portal, refresh the **Playground** tab of **msp-support-agent** and expand **Tools**: it now lists the Azure AI Search tool with **servicedesk-knowledge**, as well as **servicedesk-read** and **servicedesk-write**.

   > **[SCREENSHOT PENDING: E1T2S4 | Agent playground Tools section with the Azure AI Search tool and both MCP tools | source: capture]**

   > **Note:** The script uses the search connection that provisioning created, because creating connections needs a role you don't hold. Agent versions can't be edited, so every change creates a new version, and the agent serves the latest one.

1. Run a first query and confirm the answer draws on indexed content rather than on the model's own training. In the **Playground** chat, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   A backup job fails with error RBA-1043. What causes it, and what is Relecloud's fix?
   ```

   **Expected Output:** the cause is a pending restart after patching that leaves the Volume Shadow Copy writers in a failed or waiting state, so the snapshot does not finish within the default 600-second timeout. The fix starts with `vssadmin list writers`, then a restart in the next approved maintenance window, or a temporary snapshot timeout of 1,200 seconds if the backup can't wait. The answer cites **KB0007**, *Backup job fails with RBA-1043: snapshot provider timed out*, with a link to the article in the Service Desk app.

   **What this validates:** the agent answers from Relecloud's own article, not from general knowledge, and the citation fields you kept retrievable reach the answer.

   > **[SCREENSHOT PENDING: E1T2S5 | Playground answer about RBA-1043 citing KB0007 | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   Select the citation link: it opens KB0007 in the Service Desk app. In **Lab notes.txt**, next to **First grounded answer: article cited**, record **KB0007**.

### Expected results

- [ ] The index **servicedesk-knowledge** holds **753** documents, and the two new incidents are not among them
- [ ] `msp-support-agent` lists the Azure AI Search tool and both MCP tools
- [ ] The RBA-1043 answer cites **KB0007**, and its link opens the article

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `New-KnowledgeIndex.ps1` reports a permission error | Your Azure CLI sign-in is not the Senior Technician, or it expired | Run `az login` as the Senior Technician and run the script again; it resumes safely |
| The indexer is still running when the script stops waiting | Embedding 753 documents takes longer at busy times | Run the script again; it waits for the run in progress instead of starting another |
| The answer has no citation | The agent still serves a version without the grounded instructions | Select **New chat**; if it persists, run `Update-AgentDefinition.ps1 -Instructions` again |

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

## Task 3: Test Retrieval on Simple Questions

In this task, you will prove that the grounding works before you trust it with anything harder.

1. Ask about a named customer and confirm the answer references that customer's own profile and procedures. Select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   What does Relecloud manage for Woodgrove Bank, and which agreed procedures apply to it?
   ```

   **Expected Output:** Woodgrove Bank (CUST-007) is a **Platinum**, **Fully Managed** customer with 380 seats at a head office and five branches, and its account manager is Isabel Grant. It runs Backup Agent 5.2.1, Remote Access client 4.2.0, Secure Gateway firmware 10.1.4 and Endpoint Agent 7.4.0. Its procedures are **CUST-007-PR1** *Escalation contacts* (Elif Evans first, then Tomas Eriksen, for P1 and P2), **CUST-007-PR2** *Change and maintenance window* (Tuesday and Thursday, 20:00 to 23:00 local time) and **CUST-007-PR3** *Branch and mortgage team connectivity* (Remote Access problems for the mortgage team or branch managers are P2). The answer cites the customer profile and documents such as **CDOC-007** *Support policy: Woodgrove Bank* and **CDOC-025** *Escalation procedure: Woodgrove Bank*.

   **What this validates:** the answer comes from Woodgrove Bank's own profile, procedures and documents, not from a generic description of a bank.

   > **[SCREENSHOT PENDING: E1T3S1 | Answer about Woodgrove Bank citing its profile and documents | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Ask about a known product issue and confirm a specific knowledge article is cited by title or identifier. Enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Remote Access users at a customer on client 3.9 are disconnected about every hour. Which knowledge article covers this?
   ```

   **Expected Output:** **KB0031**, *Remote Access client disconnects every 60 minutes (client 3.x)*, cited by its number and title, which applies to Remote Access client 3.8.x and 3.9.x.

   **What this validates:** the agent names the specific article and the version range it applies to.

   > **[SCREENSHOT PENDING: E1T3S2 | Answer citing KB0031 with the client 3.8.x and 3.9.x range | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Ask a question the seeded data cannot answer and confirm the agent says so rather than inventing a response. Enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   What is Woodgrove Bank's annual IT budget?
   ```

   **Expected Output:** the agent says that Relecloud's Service Desk data does not contain Woodgrove Bank's IT budget, and suggests where the answer might come from, for example the account manager. It does not give a number.

   **What this validates:** the agent tells you when the data runs out instead of making something up, the behavior you need before you let it act.

   > **[SCREENSHOT PENDING: E1T3S3 | Answer saying the data does not contain Woodgrove Bank's IT budget | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

### Expected results

- [ ] The Woodgrove Bank answer names its tier, contract, versions and the three procedures, and cites Woodgrove's own records
- [ ] The Remote Access answer cites **KB0031**
- [ ] The budget question gets an answer that says the data does not contain it, with no invented number

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The Woodgrove Bank answer is generic and cites nothing | The chat still uses the agent version without the knowledge tool, or the index is not loaded | Select **New chat**. Check that **Tools** lists the Azure AI Search tool and that **servicedesk-knowledge** shows **753** documents (Task 2) |
| The client 3.9 question returns KB0058 | The answer matched the symptom but not the version | Ask a follow-up: *Which of those articles applies to Remote Access client 3.9?* |
| The agent gives a budget figure | The model answered from its own knowledge instead of the index | Select **New chat** and ask again. If it persists, run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions` again: the grounded instructions tell the agent to say when the data does not contain an answer |

## Task 4: Resolve an Ambiguous Case

In this task, you will see why grounding needs customer context: the dataset deliberately contains articles that conflict unless the customer's attributes are applied.

1. Find two knowledge articles that address the same symptom with different resolutions. In the playground, select **New chat**, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Which knowledge articles cover Remote Access users being disconnected about every hour with error RRA-4012? List each one with what it applies to and its fix.
   ```

   **Expected Output:** two articles. **KB0031**, *Remote Access client disconnects every 60 minutes (client 3.x)*, applies to Remote Access client 3.8.x and 3.9.x, and its fix is to upgrade the client to 4.2.0 with no gateway change. **KB0058**, *Remote Access tunnel resets hourly after Secure Gateway firmware 10.1*, applies to Secure Gateway firmware 10.1.x with client 4.x, and its fix is a change to the gateway's IKE phase 1 lifetime in the customer's change window.

   **What this validates:** the same symptom has two different, mutually exclusive fixes, so the agent can't answer correctly without knowing the customer.

   In the Service Desk app, switch to the **Knowledge** area, open **Knowledge Articles**, open **KB0031** and **KB0058**, and compare their **Applies to** fields.

   > **[SCREENSHOT PENDING: E1T4S1 | KB0031 and KB0058 in the Service Desk app with their Applies to fields | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Ask the agent to recommend one of them for a specific named customer. In the playground, select **New chat** so the earlier answer doesn't steer this one, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   Woodgrove Bank's branch managers lose Remote Access about every hour. Which article should the technician follow, KB0031 or KB0058?
   ```

   **Expected Output:** **KB0058**, *Remote Access tunnel resets hourly after Secure Gateway firmware 10.1*, because Woodgrove Bank runs Secure Gateway firmware **10.1.4** and Remote Access client **4.2.0**. KB0031 applies only to clients 3.8.x and 3.9.x, such as A. Datum Corporation's 3.9.2.

   **What this validates:** the agent resolves the conflict with the customer's own product versions instead of picking the first match.

   > **[SCREENSHOT PENDING: E1T4S2 | Answer recommending KB0058 for Woodgrove Bank with the firmware and client versions | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Confirm the justification names the customer attribute that decides it, such as SLA tier, product version or contract type. Here the deciding attributes are the **Secure Gateway firmware** and **Remote Access client** versions on Woodgrove Bank's profile. In **Lab notes.txt**, next to **Ambiguous case: articles, recommendation and deciding attribute**, record **KB0031 and KB0058, KB0058, Secure Gateway firmware 10.1.4 with client 4.2.0**.

### Expected results

- [ ] The agent found **KB0031** and **KB0058**, and you compared their **Applies to** fields in the Service Desk app
- [ ] The agent recommends **KB0058** for Woodgrove Bank and names the firmware and client versions as the reason

### Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The agent lists only one article | The search returned the closest match for one wording of the symptom | Ask a follow-up: *Is there another article for the same RRA-4012 symptom?* |
| The agent recommends KB0031 for Woodgrove Bank | It did not check the customer's product versions | Ask it to read Woodgrove Bank's profile (CUST-007) for the Remote Access client and Secure Gateway firmware versions, and to recommend again |

## Task 5: Explain the Reasoning

In this task, you will ask the agent to show its sources. Whatever the agent cannot explain here is what you will struggle to audit later.

1. Ask the agent to list every source it used for the previous answer and why it preferred them. In the same chat, enter the following prompt, and press **Enter**.

   **Prompt:**

   ```
   List every source you used for that recommendation, with its identifier, and say why you preferred each one over the others.
   ```

   **Expected Output:** a list that includes **KB0058**, **KB0031** and Woodgrove Bank's customer profile (and possibly **CDOC-031**, the Secure Gateway configuration notes, or an open Woodgrove ticket such as **TCK-10548**), each with its identifier and a reason: KB0058 matches Woodgrove's firmware and client versions, KB0031 was rejected because of the client version, and the profile supplied the versions.

   **What this validates:** every claim in the recommendation traces to a record you can open.

   > **[SCREENSHOT PENDING: E1T5S1 | List of sources with identifiers and reasons | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Note where the explanation is thin or unverifiable, and keep that note for Exercise 6. For example, a reason with no identifier behind it, or a source you can't open. In **Lab notes.txt**, next to **Thin or unverifiable reasoning to revisit in Exercise 6**, record what you found, or **none**.

### Expected results

- [ ] The agent listed its sources with identifiers and a reason for each
- [ ] You recorded any thin or unverifiable reasoning in **Lab notes.txt**

## Success Criteria

You have completed this exercise when:

- [ ] Every readiness row was **Ready**, and the Service Desk app showed the seeded counts
- [ ] **servicedesk-knowledge** holds **753** documents and is a knowledge source of `msp-support-agent`, alongside both MCP tools
- [ ] Grounded answers cite the right records: **KB0007**, Woodgrove Bank's own profile and documents, **KB0031**, and **KB0058** for Woodgrove Bank
- [ ] **Lab notes.txt** holds the readiness result, the Agent ID, the baseline correlation ID, the index count, the ambiguous case and your notes on thin reasoning
- [ ] Negative check: asked for Woodgrove Bank's IT budget, the agent said the data does not contain it instead of inventing a figure

## Apply It in Production

**What you built:**

- A grounding index over an MSP's own articles, customer documents and ticket history, with citation fields that link every answer to its source record.
- An agent that resolves conflicting guidance with the customer's own attributes, and says when the data runs out.

**Decisions to make before production:**

1. **What to index.** Ticket notes, contact details and confidential documents stay out of this index. Decide per data type, and keep anything that needs per-user access behind a tool that enforces it instead of in a shared index.
1. **Freshness.** This lab indexes a snapshot. In production, choose between a scheduled indexer, change tracking on the source, or push updates, and decide how stale an answer may be.
1. **Chunking.** One record per document keeps citations exact here. Long manuals need chunking, which trades citation precision for recall.
1. **Grounding rules.** Instructions that require citations and an "I don't know" answer are part of the product. Test them with unanswerable questions before every release.

**Production checklist:**

- [ ] The search service and storage use managed identities and role-based access only, with no keys
- [ ] Indexers run on a schedule or on change, with failures alerted
- [ ] The agent's instructions require a citation for every claim and a refusal when the data is silent
- [ ] Conflicting or retired articles are marked so the agent can filter them
- [ ] Retrieval quality is tested with a fixed question set, such as the five scripted questions in this lab's acceptance tests

**Common pitfalls:**

| Pitfall | How to avoid it |
|---|---|
| The agent answers from general knowledge when retrieval returns nothing | Require citations in the instructions and test with questions the data cannot answer |
| Citations point nowhere because the index dropped the URL field | Keep `title`, `url` and an identifier retrievable, and check one citation link before every release |

## Knowledge Check

**Question 1:** The index stores `title`, `url` and `sourceId`, but the agent never searches those fields. Why are they in the index at all?

<details>
<summary>Show the answer</summary>

Because the agent can only cite what a search result returns. Retrievable `title`, `url` and `sourceId` fields travel with every result into the answer, so each claim links to the record it came from.

</details>

**Question 2:** Why are the two new incidents, TCK-10561 and TCK-10562, missing from the index?

<details>
<summary>Show the answer</summary>

Provisioning loaded them after the export, on purpose. In Exercises 2 and 7 the agent must reach them through the MCP tools, as it would a ticket that arrived after the last indexing run.

</details>

**Question 3:** KB0031 and KB0058 describe the same symptom. What decides which one the agent should recommend?

<details>
<summary>Show the answer</summary>

The customer's own attributes, here the Remote Access client version and the Secure Gateway firmware on the customer profile. Woodgrove Bank runs client 4.2.0 and firmware 10.1.4, so KB0058 applies.

</details>

## Summary

In this exercise, you have completed the following:

- Verified every component of your environment with the readiness check and the Service Desk app's seeded counts.
- Built the **servicedesk-knowledge** index from the Blob export with citation fields, and confirmed all 753 documents.
- Added the index to **msp-support-agent** as a knowledge source, keeping both MCP tools.
- Tested grounded retrieval on a customer, a product issue and an unanswerable question.
- Resolved an ambiguous case with the customer's product versions and asked the agent to explain its sources.

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
