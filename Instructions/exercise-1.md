# Exercise 1: Environment Verification and Grounding

### Estimated Duration: 65 minutes

## Scenario

Before Relecloud lets an agent near its queue, the automation team has to prove two things: that the team environment is complete, and that the agent answers from Relecloud's own Service Desk data rather than from general knowledge. Engineers lose a third of their handling time hunting through old tickets and articles; an agent that guesses would make that worse, not better.

## Overview

In this exercise, you verify every component of your team environment and record anything that is missing. You then build an Azure AI Search index over the Service Desk knowledge articles, tickets and customer profiles in Dataverse, load it, and connect it to the agent as its knowledge source. Finally, you test the grounded agent on simple questions, on an ambiguous case where two knowledge articles describe the same symptom, and on its ability to explain its own reasoning.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Verify the team environment
- Task 2: Connect the agent to the knowledge base
- Task 3: Test simple retrieval
- Task 4: Resolve an ambiguous case
- Task 5: Make the agent explain its reasoning

## Task 1: Verify the team environment

In this task, you will check each component of your team environment and record the result in your lab notes.

1. In the Azure portal, open your resource group and compare its resources with the list below. If some types are missing from the list, select **Manage view** > **Show hidden types**.

   ```
   <inject key="Resource Group Name" enableCopy="false"/>
   ```

   | Resource | Type | Role in the lab |
   |---|---|---|
   | **labvm-<inject key="DeploymentID" enableCopy="false"/>** | Virtual machine | The lab VM you are working on, with its disk, network interface, virtual network, network security group and public IP address |
   | **aif-msp-<inject key="DeploymentID" enableCopy="false"/>** | Foundry | The Microsoft Foundry resource, with the `gpt-5.4-mini` and `text-embedding-3-small` model deployments |
   | **proj-msp-<inject key="DeploymentID" enableCopy="false"/>** | Foundry project | The project that holds your agent |
   | **srch-msp-<inject key="DeploymentID" enableCopy="false"/>** | Search service | Azure AI Search, with no index yet |
   | **apim-msp-<inject key="DeploymentID" enableCopy="false"/>** | API Management service | The MCP gateway |
   | **cae-msp-<inject key="DeploymentID" enableCopy="false"/>** | Container Apps Environment | Runs the MCP server and sends its logs to Log Analytics |
   | **ca-mcp-<inject key="DeploymentID" enableCopy="false"/>** | Container App | The MCP server |
   | **<inject key="Container Registry Name" enableCopy="false"/>** | Container registry | Builds and stores MCP server images |
   | **<inject key="Key Vault Name" enableCopy="false"/>** | Key vault | Holds the gateway key the server checks |
   | **id-mcp-<inject key="DeploymentID" enableCopy="false"/>** | Managed Identity | The MCP server's identity, known to Dataverse as an application user |
   | **id-apim-<inject key="DeploymentID" enableCopy="false"/>** | Managed Identity | Lets API Management read the gateway key from Key Vault |
   | **log-msp-<inject key="DeploymentID" enableCopy="false"/>** | Log Analytics workspace | Collects gateway, MCP and container logs |
   | **appi-msp-<inject key="DeploymentID" enableCopy="false"/>** | Application Insights | Collects Foundry agent traces |

   In **Lab notes.txt**, next to **Resource group**, write **pass** or **fail** and anything that is missing.

   > **[SCREENSHOT PENDING: E1T1S1 | Team resource group Overview page listing its resources | source: capture]**

1. On the VM desktop, double-click the **Service Desk** shortcut and sign in with the team account if you are asked. Open each table below, select the view, and compare the row count at the bottom of the list. Use the area switcher at the bottom of the left navigation to move between the **Service Desk**, **Knowledge** and **Configuration** areas.

   | Navigation | View | Expected rows |
   |---|---|---|
   | **Work** > **Tickets** | **Open Tickets** | 42 |
   | **Work** > **Tickets** | **All Tickets** | 473 |
   | **Work** > **Ticket Notes** | **All Ticket Notes** | 1,161 |
   | **Customers** > **Accounts** | **Managed Customers** | 24 |
   | **Customers** > **Contacts** | **Customer Contacts** | 72 |
   | **Knowledge** area > **Knowledge Articles** | **All Articles** | 50 (49 Published, 1 Retired) |
   | **Configuration** area > **Technicians** | **Active Technicians** | 12 (Marcus Webb is not available) |

   > **Note:** The app's address is <inject key="Service Desk App URL" enableCopy="false"/>. If the desktop shortcut opens a different address, use the shortcut: it points to the environment that was actually created.

   > **[SCREENSHOT PENDING: E1T1S2 | Service Desk app Tickets list with the Open Tickets view and the row count | source: capture]**

1. Open ticket **TCK-10489** from the **Open Tickets** view and look at its **SLA** section. **SLA Target**, **SLA Elapsed** and **SLA Remaining** are in business hours, and **SLA Calculated On** is the moment the figures were taken. Record **pass** or **fail** next to **Service Desk app and seeded data** in your lab notes.

   > **[SCREENSHOT PENDING: E1T1S3 | Ticket TCK-10489 form showing the SLA section | source: capture]**

1. On the VM desktop, double-click the **Microsoft Foundry** shortcut and sign in with the team account if you are asked. In the project selector in the top banner, select **proj-msp-<inject key="DeploymentID" enableCopy="false"/>**. Select **Build (1)** in the top navigation, then **Agents (2)**, and select the agent **msp-support-agent (3)**.

   > **Note:** These steps use the current Foundry portal. If the portal opens in the classic experience, turn on the **New Foundry** toggle in the top banner. Portal labels change often; if a label in this guide differs slightly, look for the closest match.

   > **[SCREENSHOT PENDING: E1T1S4 | Foundry portal Build > Agents list with msp-support-agent | source: capture]**

1. On the **Playground** tab, look at the agent's configuration. It has a model and a short instruction, but no knowledge and no tools. Ask it a question about Relecloud's data:

   ```
   Which customers does Relecloud Managed Services support, and what SLA tier does Woodgrove Bank have?
   ```

   The agent can't answer from Relecloud's data yet, and its instruction tells it to say so. Record **pass** next to **Foundry agent** if the agent has no knowledge and no tools.

   > **[SCREENSHOT PENDING: E1T1S5 | Agent playground with no tools and the agent's ungrounded answer | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

   > **Note:** The playground runs evaluators on every answer by default, and those evaluations are billed and use your team's model capacity. Select the metrics control in the upper right of the playground and clear all evaluators. Do this once; the setting applies to the rest of the lab.

1. In PowerShell 7 on the VM, show your agent's Microsoft Entra agent identity:

   ```powershell
   C:\LabFiles\tools\Get-AgentIdentity.ps1
   ```

   **Agent identity object ID** is the identity's object ID in Microsoft Entra ID; **Agent identity client ID** is the application ID that appears in the tokens the agent presents to API Management. Copy both values into **Lab notes.txt**, next to **Agent identity object ID** and **Agent identity client ID**. You use the object ID again in Exercise 5.

   > **[SCREENSHOT PENDING: E1T1S6 | PowerShell output of Get-AgentIdentity.ps1 with the object ID and client ID | source: capture]**

1. On the VM desktop, double-click **Microsoft Entra admin center**. Go to **Entra ID** > **Agents** > **Agent identities**, search for the object ID you recorded, and open the agent identity. Record **pass** next to **Agent identity** in your lab notes.

   > **Note:** Viewing agent identities doesn't need an admin role. If your admin center shows **Agent ID** > **All agent identities** instead, use that path.

   > **[SCREENSHOT PENDING: E1T1S7 | Microsoft Entra admin center Agent identities list filtered to the agent's object ID | source: capture]**

1. In Microsoft Edge on the VM, open the MCP server's health endpoint. It needs no key:

   ```
   <inject key="MCP Server URL" enableCopy="false"/>/health?deep=true
   ```

   The response shows `"status": "ok"`, the server `version` (`1.0.0`), `"backend": "dataverse"` and `"dataverse": "reachable"`.

1. In PowerShell 7, list the reference tools through API Management, then invoke one read tool and confirm it returns real ticket data:

   ```powershell
   C:\LabFiles\tools\Invoke-McpTool.ps1 -List
   ```

   ```powershell
   C:\LabFiles\tools\Invoke-McpTool.ps1 get_ticket @{ ticket_number = 'TCK-10489' }
   ```

   The list shows seven read tools and five write tools. The call shows `isError: False` and ticket **TCK-10489**, *Claims team cannot open policy documents*, for **Humongous Insurance**, the same record you opened in the Service Desk app.

   > **[SCREENSHOT PENDING: E1T1S9 | PowerShell output of Invoke-McpTool.ps1 get_ticket for TCK-10489 | source: capture]**

   > **Note:** `Invoke-McpTool.ps1` calls the gateway's diagnostics API with an API Management subscription key. The agent uses a separate API on the same gateway that accepts only its agent identity.

1. Try to call the MCP server directly, around the gateway:

   ```powershell
   Invoke-RestMethod -Method Post -Uri '<inject key="MCP Server URL" enableCopy="false"/>/mcp' -ContentType 'application/json' -Body '{}'
   ```

   The server answers **401** with *Call this server through the Azure API Management gateway.* The gateway key lives in Key Vault, and API Management adds it to every call it forwards, so a caller that goes around the gateway is refused.

1. Complete the **Environment check** section of **Lab notes.txt**. If any check failed, tell your facilitator now and include your Deployment ID: <inject key="DeploymentID" enableCopy="true"/>

## Task 2: Connect the agent to the knowledge base

In this task, you will create a search index with the fields an answer needs to cite its source, load it from Dataverse, and add it to the agent as its knowledge source.

1. In Microsoft Edge on the VM, open Power Apps, and in the environment selector at the top right select **Relecloud Service Desk <inject key="DeploymentID" enableCopy="false"/>**:

   ```
   https://make.powerapps.com
   ```

   > **[SCREENSHOT PENDING: E1T2S1 | Power Apps environment selector with the Relecloud Service Desk environment | source: capture]**

1. Select **Tables**, search for **Knowledge Article**, open the table, and under **Schema** select **Columns**. Review the text columns that hold the knowledge:

   - **Article Number** and **Title**: what an answer cites
   - **Symptom**, **Cause** and **Resolution**: the content
   - **Applies To**, **Applies to Versions**, **Applies to SLA Tiers** and **Applies to Contract Types**: when the article is the right one
   - **Article Status**: **Retired** articles must never be recommended

   > **[SCREENSHOT PENDING: E1T2S2 | Knowledge Article table columns in Power Apps | source: capture]**

1. Review the **Ticket** and **Ticket Note** tables the same way. A ticket carries **Title**, **Description**, **Resolution Summary** and the SLA columns; a ticket note carries **Body** and **Internal Note**. The loader you run in this task indexes knowledge articles, tickets and customer profiles, and deliberately leaves out two things:

   | Left out | Why |
   |---|---|
   | **Ticket notes** | Internal notes hold billing disputes and blame that must never reach an answer. The agent reads notes only through a tool that withholds internal notes by default. |
   | **Contact email and phone numbers** | Personal data that answering a support question doesn't need. |

1. Open the index definition in Visual Studio Code and review the fields that make an answer checkable:

   ```powershell
   code C:\LabFiles\search\index-definition.json
   ```

   | Field | Purpose |
   |---|---|
   | `title` | The citation title, for example *KB0058: Remote Access tunnel resets hourly after Secure Gateway firmware 10.1* |
   | `url` | A link to the record in the Service Desk app, so a citation opens the source |
   | `sourceId` | The article number, ticket number or customer code |
   | `content` | The text the agent reads |
   | `docType`, `customerCode`, `slaTier`, `contractType`, `productVersion`, `articleStatus` | Filterable attributes that tell two similar documents apart |
   | `contentVector` | The embedding of `content`. The loader computes it with `text-embedding-3-small`; the index's vectorizer embeds each question the same way at query time, so vector and hybrid search work. |

   > **Note:** The Foundry Azure AI Search tool needs a retrievable `url` field, and optionally `title`, to produce citations. Without them the agent can answer but can't link to its source.

1. In PowerShell 7, create the index:

   ```powershell
   $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
   $token = az account get-access-token --resource https://search.azure.com --query accessToken --output tsv
   Invoke-RestMethod -Method Put -Uri "$($s.SearchEndpoint)/indexes/servicedesk-knowledge?api-version=2024-07-01" `
       -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' `
       -InFile C:\LabFiles\search\index-definition.json | Select-Object name, @{ n = 'fields'; e = { $_.fields.Count } }
   ```

   The output shows the index **servicedesk-knowledge** with **26** fields.

1. Start loading the index from Dataverse:

   ```powershell
   C:\LabFiles\search\Load-SearchIndex.ps1
   ```

   The script reads the tables, embeds every document and uploads it, then compares the counts. It takes around **3 to 6 minutes**, so leave it running and continue with the Foundry connection in the next three steps.

   > **Note:** Your embedding deployment accepts about 30,000 tokens a minute, so the script pauses when it is rate limited and prints *The embedding deployment is rate limiting; waiting ...*. That is expected; let it finish.

1. In the Foundry portal, select **Manage** in the top navigation, then **Project details**, and select the **Connected resources** tab.

1. Select **Add connection (1)**, select **Azure AI Search (2)**, browse for your search service **srch-msp-<inject key="DeploymentID" enableCopy="false"/> (3)**, and for **Authentication** choose the keyless **Microsoft Entra ID** option **(4)**. Select **Add connection (5)**.

   > **[SCREENSHOT PENDING: E1T2S8 | Foundry Connected resources Add connection pane for Azure AI Search with keyless authentication | source: capture]**

   > **Note:** With keyless authentication, Foundry queries the index with a managed identity: the project's, or the Foundry resource's system-assigned identity. Both already hold the **Search Index Data Contributor** and **Search Service Contributor** roles on your search service that the Azure AI Search tool requires, so no key is stored in the connection.

1. Go back to PowerShell 7. When the loader finishes, confirm that its last line reads **Document count matches the Dataverse data.** and that the index holds **548** documents: 50 knowledge articles, 473 tickets, 24 customer profiles and one SLA snapshot.

   > **[SCREENSHOT PENDING: E1T2S9 | Load-SearchIndex.ps1 output with the count table and the match message | source: capture]**

   > **Note:** Each customer profile also lists that customer's open tickets, and the SLA snapshot ranks every open ticket by remaining business hours and holds the SLA targets and priority rules. A search returns the few most relevant documents, not a sorted or complete list, so questions about "all open tickets for a customer" or "closest to breach" need a document that already holds the list.

1. In the Azure portal, open your search service **srch-msp-<inject key="DeploymentID" enableCopy="false"/>**, select **Search management** > **Indexes**, and confirm that **servicedesk-knowledge** shows 548 documents. Select the index, open **Search explorer**, search for `KB0058`, and look at the `title`, `url` and `sourceId` of the result.

   > **[SCREENSHOT PENDING: E1T2S10 | Azure AI Search Indexes page with the servicedesk-knowledge index and its document count | source: capture]**

1. Give the agent the index as its knowledge source, and replace its short instruction with grounded instructions:

   ```powershell
   C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge
   ```

   The script uses the Azure AI Search connection you created and creates a new version of the agent with this tool definition:

   ```json
   {
     "type": "azure_ai_search",
     "azure_ai_search": {
       "indexes": [ {
         "project_connection_id": "<your Azure AI Search connection>",
         "index_name": "servicedesk-knowledge",
         "query_type": "vector_semantic_hybrid",
         "top_k": 10
       } ]
     }
   }
   ```

   > **Note:** `vector_semantic_hybrid` combines keyword, vector and semantic ranking, so a question finds an article even when it uses different words. `top_k` sets how many documents each search returns.

1. In the Foundry portal, go back to **Build** > **Agents**, open **msp-support-agent**, and refresh the page. Confirm that the agent now lists the **Azure AI Search** tool for `servicedesk-knowledge`, and read the new **Instructions**. Note the rules about citing sources, saying *I can't find that in the Service Desk data*, choosing between articles and never quoting internal notes.

   > **[SCREENSHOT PENDING: E1T2S12 | Agent playground showing the Azure AI Search tool and the grounded instructions | source: capture]**

1. In the playground, start a new chat and ask a question that only your index can answer:

   ```
   Which Remote Access client version and Secure Gateway firmware does Woodgrove Bank run?
   ```

   Confirm that the answer is drawn from the index: Woodgrove Bank (CUST-007) runs **Remote Access client 4.2.0** and **Secure Gateway firmware 10.1.4**, and the answer carries a citation to the customer profile. Select the citation and check that it opens the Woodgrove Bank record in the Service Desk app.

   > **[SCREENSHOT PENDING: E1T2S13 | Grounded answer about Woodgrove Bank with a citation to the customer profile | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Knowledge index loaded and connected" is registered (validation-scripts/README.md). -->

## Task 3: Test simple retrieval

In this task, you will check that the grounded agent answers simple questions from the index, cites its sources, and says so when the data doesn't hold the answer.

1. In the playground, start a new chat and ask about a named customer:

   ```
   Summarize the profile of Humongous Insurance: SLA tier, contract type, managed seats, deployed product versions and account manager.
   ```

   **What this validates:** retrieval of a single record. Expect Humongous Insurance (CUST-013): **Platinum**, **Fully Managed**, **510** seats, Backup Agent **5.2.1**, Remote Access **4.2.0**, Secure Gateway **10.1.4**, Endpoint Agent **7.4.1**, account manager **Isabel Grant**, with a citation to the customer profile.

1. Ask about a known product issue:

   ```
   A file server backup failed overnight with RBA-1043, snapshot provider timed out. Which knowledge article applies, and what are the steps?
   ```

   **What this validates:** the agent cites the article by number and title. Expect **KB0007** *Backup job fails with RBA-1043: snapshot provider timed out*, with its steps. The agent must not recommend **KB0019**, which is **Retired**; if it mentions KB0019 at all, it should say that it is retired and superseded.

   > **[SCREENSHOT PENDING: E1T3S2 | Agent answer citing KB0007 with its resolution steps | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Ask a question the Service Desk data can't answer:

   ```
   What is Woodgrove Bank's monthly contract value?
   ```

   **What this validates:** the agent refuses to guess. Expect *I can't find that in the Service Desk data*, with a short note of what it looked for. Contract values are not in the data.

1. If an answer has no citation, or states a fact you can't find in the Service Desk app, record the question in **Lab notes.txt** under **Thin explanations to revisit in Exercise 5**.

### Success Criteria

- [ ] The customer profile answer matches the Humongous Insurance record and cites it
- [ ] The RBA-1043 answer cites KB0007 by number and title and doesn't recommend KB0019
- [ ] The contract value question is answered with *I can't find that in the Service Desk data*, not a number

## Task 4: Resolve an ambiguous case

In this task, you will make the agent choose between two knowledge articles that describe the same symptom with different resolutions, based on a customer attribute.

1. Start a new chat and ask the agent to find the conflicting articles:

   ```
   Find the knowledge articles about Remote Access users being disconnected roughly every hour. For each article, give the number, title, the versions it applies to, and the resolution.
   ```

   **What this validates:** the agent finds both articles. Expect **KB0031** *Remote Access client disconnects every 60 minutes (client 3.x)*, which says to upgrade the client to 4.2.0 and not to change IKE settings, and **KB0058** *Remote Access tunnel resets hourly after Secure Gateway firmware 10.1*, which says to raise the IKE phase 1 lifetime on the gateway to 28800 seconds and not to reinstall the client.

1. Identify the customer attribute that decides between them. Both articles share the symptom and the log line `RRA-4012 tunnel reset by peer`; they differ on **product version**: KB0031 applies to Remote Access client **3.8** and **3.9**, KB0058 to client **4.x** on Secure Gateway firmware **10.1**.

1. Ask for a recommendation for a named customer:

   ```
   Woodgrove Bank users are being disconnected from Remote Access every hour. Which knowledge article should we follow for Woodgrove Bank, and why?
   ```

1. Ask the same question for a customer on the older client:

   ```
   The same symptom is reported at Northwind Traders. Which article applies there, and why?
   ```

1. Check that each justification names the deciding attribute and the customer's actual value:

   | Customer | Remote Access client | Secure Gateway firmware | Article |
   |---|---|---|---|
   | Woodgrove Bank (CUST-007) | 4.2.0 | 10.1.4 | KB0058 |
   | Northwind Traders (CUST-003) | 3.9.2 | 9.6.2 | KB0031 |

   > **[SCREENSHOT PENDING: E1T4S5 | Agent recommendation for Woodgrove Bank naming client 4.2.0 and firmware 10.1.4 | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Verify the attributes in the Service Desk app: open **Customers** > **Accounts**, select the **Managed Customers** view, and compare the **Remote Access Client Version** and **Secure Gateway Firmware** columns for both customers. Then open **KB0058** in **Knowledge Articles** and read its **Applicability** section.

   > **Note:** The data holds more pairs like this. KB0012 and KB0013 split on **SLA tier**, and KB0044 and KB0045 split on **contract type**. If you have time, ask the agent how to handle a firewall rule request for Margie's Travel (Break-Fix) and for Woodgrove Bank (Fully Managed).

### Success Criteria

- [ ] The agent lists both KB0031 and KB0058 with their applicability
- [ ] The Woodgrove Bank recommendation is KB0058 and names client 4.2.0 and firmware 10.1.4 as the reason
- [ ] The Northwind Traders recommendation is KB0031 and names client 3.9.2 as the reason

## Task 5: Make the agent explain its reasoning

In this task, you will ask the agent to show its sources and its reasoning, and record any explanation that is too thin to trust.

1. In the same chat as the Woodgrove Bank recommendation, ask:

   ```
   List every source you used for your Woodgrove Bank recommendation, with the article, ticket or customer number for each.
   ```

1. Then ask why it preferred one article:

   ```
   Why did you prefer KB0058 over KB0031 for Woodgrove Bank? Quote the applicability you compared and the customer values you compared it with.
   ```

   > **[SCREENSHOT PENDING: E1T5S2 | Agent explanation comparing the KB0058 and KB0031 applicability with Woodgrove Bank's versions | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Judge the explanation. It is thin if it names no source, names a source but not the deciding attribute, or states a value you can't find on the record.

1. In PowerShell 7, get the current time in UTC:

   ```powershell
   (Get-Date).ToUniversalTime().ToString('u')
   ```

1. In **Lab notes.txt**, under **Thin explanations to revisit in Exercise 5**, record each thin explanation from this exercise with its question and the time. In Exercise 5 you open the agent trace for one of them and see what the agent actually retrieved.

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **A script says to run `az login` first:** sign in to the Azure CLI again as described on the getting-started page, then rerun the script.
- **Creating the index returns 403:** your role on the search service may still be propagating. Check that `az account show` shows the team account, wait two minutes and run the command again.
- **The loader stops with an error:** run `C:\LabFiles\search\Load-SearchIndex.ps1` again. It uploads with merge-or-upload, so a rerun is safe.
- **The agent answers without citations, or still says it has no access:** start a new chat. If the **Azure AI Search** tool isn't listed on the agent, run `C:\LabFiles\tools\Update-AgentDefinition.ps1 -Knowledge` again.
- **A Foundry portal label differs from this guide:** look for the closest match; the steps follow the current portal, which changes often.

</details>

## Summary

In this exercise, you have completed the following:

- Verified the resource group, the Service Desk app and its seeded data, the Foundry agent, its agent identity, and the MCP server through API Management
- Created the `servicedesk-knowledge` index with the fields needed to cite a source and loaded it from Dataverse
- Connected the index to the agent as its knowledge source with keyless authentication and grounded instructions
- Tested simple retrieval, an unanswerable question, and an ambiguous case decided by product version
- Asked the agent to explain its sources and recorded thin explanations for Exercise 5

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
