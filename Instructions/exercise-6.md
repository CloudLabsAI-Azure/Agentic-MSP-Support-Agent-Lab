# Exercise 6: Data Protection and Auditability

### Estimated Duration: 45 minutes

## Scenario

Relecloud holds data about its customers that an agent should never repeat: contact details that answering a ticket doesn't need, card numbers that a customer read out over the phone and a technician typed into a note, and configuration documents that carry a sensitivity label. The security team also wants to follow any single agent action from the request to the database record without anyone stitching logs together by hand.

## Overview

In this exercise, you restrict what the agent can return with Dataverse column security, and see the agent report the limitation instead of filling the gap. You review the Microsoft Purview DLP policy and the sensitivity label that protect support data, ask the agent for protected content, and find the DLP event in Purview. Finally, you follow one approved write from Exercise 4 through Application Insights, the gateway and MCP server logs, and the Dataverse audit history, using one correlation identifier.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Restrict What the Agent Can Return
- Task 2: Apply Microsoft Purview Data Protection
- Task 3: Trace a Single Action End to End

## Task 1: Restrict What the Agent Can Return

In this task, you will choose between platform control, application control, or both. Be able to argue which you would trust an agent with.

1. Apply a Dataverse column security profile to the contact fields, a filter at the MCP server or gateway, or both. Use the platform control: column security.

   - First see what the agent returns today. In the playground, start a new chat and send *List the contacts at Humongous Insurance with their email addresses and mobile numbers.* The agent lists three contacts with both.
   - In Power Apps (`https://make.powerapps.com`, your environment **Relecloud Service Desk <inject key="DeploymentID" enableCopy="false"/>**), select **Tables**, open **Contact**, and under **Schema** select **Columns**. Open **Email**, expand **Advanced options**, select **Enable column security**, and select **Save**. Secure **Mobile Phone** the same way.
   - In the **Power Platform admin center**, open your environment > **Settings** > **Users + permissions** > **Column security profiles**, select **New Profile**, name it `Service Desk Agent contact access`, and select **Save**. Open the profile, select the **Users** tab, select **+ Add Users**, search for the MCP server's application user by its client ID, <inject key="MCP Backend Identity Client ID" enableCopy="true"/>, and select **Add**. On the **Column Permission** tab, select **emailaddress1** on the **contact** table, select **Edit**, set **Read** to **Allowed**, and select **Save**. Leave **mobilephone** not allowed.

   > **[SCREENSHOT PENDING: E6T1S1 | Column security profile with Read allowed on contact emailaddress1 | source: capture]**

   > **Note:** A filter in the MCP server, for example dropping a column in `get_customer_contacts`, or at the gateway would be application control: it protects only that path. Column security is enforced by Dataverse for every caller: this agent, the Service Desk app, any other tool and any future client.

1. Ask the agent a question that would previously have returned the protected content. Wait about a minute, start a new chat, so the agent can't reuse its first answer, and send:

   ```
   List the contacts at Humongous Insurance with their email addresses and mobile numbers.
   ```

1. Confirm the content is withheld or masked, and that the agent reports the limitation rather than substituting something plausible. The email addresses come back, because the profile lets the MCP server read them; the mobile numbers come back empty and are named in `withheld_fields`. The agent says the mobile numbers are restricted, not that the contacts have none, and doesn't guess them. Open the same contacts in the Service Desk app: you still see every value, because the Senior Technician holds System Administrator. Dataverse checks a secured column for both the impersonated user and the identity making the call, so the agent sees less than you do. In **Lab notes.txt**, next to **What the agent could not return**, record what it said, and one sentence on which control you would trust an agent with, and why.

   > **[SCREENSHOT PENDING: E6T1S3 | Agent answer reporting that contact mobile numbers are restricted | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Contact columns protected" is registered (validation-scripts/README.md). -->

## Task 2: Apply Microsoft Purview Data Protection

In this task, you will apply sensitive information detection, classification and DLP to the agent's interactions.

1. Review the Microsoft Purview DLP policy and the sensitive information types it detects in support data.

   - On the VM desktop, double-click **Microsoft Purview** and sign in as the Senior Technician. Go to **Data loss prevention** > **Policies** and open the lab's policy for the **Relecloud Service Desk Purview Integration** app. Its rule detects the sensitive information type **Credit Card Number** and blocks the content.
   - In Visual Studio Code, open `src/servicedesk_mcp/purview.py` in your MCP server. Before a tool returns ticket text, notes or a customer document to the agent, the server sends it to the Purview `processContent` API for the signed-in user and your agent, and withholds whatever the policy blocks. If Purview can't be reached, the server withholds the content: no answer is not a yes. In Microsoft Edge, open <inject key="MCP Server URL" enableCopy="false"/>/health: `purview` is `enabled`.

   > **[SCREENSHOT PENDING: E6T2S1 | Purview DLP policy rule with the Credit Card Number sensitive information type | source: capture]**

1. Review the sensitivity label applied to a seeded customer configuration document. In the Service Desk app, open **Customers** > **Accounts** > **Woodgrove Bank**, and in the **Timeline** find the note with the attachment **Woodgrove-Bank-Secure-Gateway-configuration.docx**. Download it, then read the label it carries:

   ```powershell
   C:\LabFiles\tools\Get-DocumentLabel.ps1 -Path "$HOME\Downloads\Woodgrove-Bank-Secure-Gateway-configuration.docx"
   ```

   The document carries the label **Confidential**, applied when the environment was prepared. Office records a label in the file's own properties, so it travels with the document wherever it is stored; in Word, the sensitivity bar shows it. The MCP server never returns a document with this label to the agent: the label is listed in the Container App's `PURVIEW_RESTRICTED_LABELS` setting.

1. Ask the agent for content that contains a seeded sensitive value or comes from the labelled document. Start a new chat and send:

   ```
   Show me all the notes on TCK-10486, including the internal notes.
   ```

   Then send:

   ```
   Get Woodgrove Bank's Secure Gateway configuration document and summarise its IKE settings.
   ```

1. Confirm the response is blocked or redacted according to the policy and the label.

   - **TCK-10486:** the internal note in which a finance director read out the company card is withheld: the tool returns it with `body` empty and `withheld_by` naming the Purview DLP policy, and `withheld_by_policy` is `1`. The agent says one note is protected by policy and doesn't guess its content. No card number appears in the answer.
   - **The configuration document:** the tool returns `CONTENT_BLOCKED_BY_LABEL`: the document carries the label **Confidential**, which doesn't allow its content to be returned to an AI agent. The agent says the document is protected and must be opened by an authorized person.
   - In the Visual Studio Code terminal, run `.\scripts\Show-McpServerLog.ps1`: the **get_ticket_notes** row shows **DecidedBy** `purview` and the **get_customer_document** row shows **Outcome** `blocked` and **DecidedBy** `sensitivity label`.

   > **[SCREENSHOT PENDING: E6T2S4 | Agent answers with the withheld note and the label-protected document | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Find the matching DLP event in Microsoft Purview. In the Purview portal, open **Data loss prevention** > **Activity explorer**, filter **Activity** on **DLP rule matched**, and find the event for the Senior Technician at the time of your TCK-10486 question: it names the policy, the rule, the sensitive information type **Credit Card Number** and the app. Record the policy, the sensitive information type and the event time in **Lab notes.txt** next to **Microsoft Purview**.

   > **Note:** Purview events can take up to 30 minutes to appear in Activity explorer. If the event isn't there yet, continue with Task 3 and come back.

   > **[SCREENSHOT PENDING: E6T2S5 | Purview Activity explorer with the DLP rule matched event | source: capture]**

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Purview withholds sensitive content" is registered (validation-scripts/README.md). -->

## Task 3: Trace a Single Action End to End

In this task, you will follow one request through the architecture. One correlation identifier links every step of a request.

1. Choose one approved write action from Exercise 4 and note its correlation identifier. Use the priority change on **TCK-10501** from Exercise 4 Task 1: its correlation identifier is in **Lab notes.txt**, next to **Approved write**. You can also read it on the ticket: open **TCK-10501** in the Service Desk app, and in the **Traceability** section copy **Last Correlation ID**.

1. Find the user request and the agent's tool decision in Application Insights. Open the Log Analytics workspace **log-msp-<inject key="DeploymentID" enableCopy="false"/>**, select **Logs**, switch the editor to **KQL mode** if it opens in simple mode, replace `<correlation ID>` with yours, and run:

   ```kql
   let id = "<correlation ID>";
   AppGenAIContent
   | where TimeGenerated > ago(1d)
   | where ToolCallResult has id
   | project TimeGenerated, TraceId, AgentName, ToolCallArguments, ToolCallResult
   ```

   The row is the agent's call to **set_ticket_priority**: its arguments are the tool decision, and its result ends with your correlation identifier. Copy its **TraceId**, then list the whole agent run, from the user's request to the answer:

   ```kql
   AppDependencies
   | where TimeGenerated > ago(1d)
   | where OperationId == "<TraceId>"
   | project TimeGenerated, Name, DurationMs, Success
   | order by TimeGenerated asc
   ```

   > **Note:** You can see the same run in the Foundry portal, on the agent's **Traces** tab: open the conversation and select the **set_ticket_priority** tool call.

1. Find the matching MCP tool call, its authorization result and the backend API call in the logs:

   ```kql
   let id = "<correlation ID>";
   union
       (ApiManagementGatewayLogs | where CorrelationId == id
        | project TimeGenerated, Hop = "API Management", Detail = strcat(Method, " ", Url, " ", ResponseCode)),
       (ContainerAppConsoleLogs | where Log has id | extend e = parse_json(Log) | where tostring(e.event) == "tool_call"
        | project TimeGenerated, Hop = "MCP server", Detail = strcat(tostring(e.tool), " ", tostring(e.user.name), " ",
                  tostring(e.authorization), " ", tostring(e.dataverse)))
   | order by TimeGenerated asc
   ```

   The gateway row has your correlation identifier as its **CorrelationId**. The MCP server row shows the user, the authorization result (`allowed`, decided by `dataverse`, acting as `user`) and the backend calls: a `PATCH` on `spk_tickets` and a `POST` on `spk_ticketnotes`, each with its HTTP status and Dataverse request ID, made on behalf of the user.

1. Find the Dataverse audit record for the change and the outcome returned to the user. In the Service Desk app, open **TCK-10501**, select **Related** > **Audit History**, and find the **Priority** change from **P4 Low** to **P3 Medium**, attributed to the Senior Technician. The outcome returned to the user is the tool result, `ok` with the change, the audit note and the correlation identifier, and the agent's answer in the playground.

1. Assemble the full trail: who asked, which agent, which tool, what was authorized, what changed and what was returned. In PowerShell 7, run:

   ```powershell
   C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId <correlation ID>
   ```

   The script looks the identifier up at every hop and prints one timeline. In **Lab notes.txt**, next to **End-to-end trail**, complete:

   | Question | Your answer, from the trail |
   |---|---|
   | Who asked | The Senior Technician (from the MCP server's log line and the audit history) |
   | Which agent | `msp-support-agent` and its Entra Agent ID (the `agent` field of the log line) |
   | Which tool | `set_ticket_priority`, with its arguments (Application Insights and the log line) |
   | What was authorized | Allowed by Dataverse, acting as the user (the `authorization` field) |
   | What changed | Priority P4 to P3 and the SLA columns on TCK-10501, plus an audit note (Dataverse audit history) |
   | What was returned | The tool result with the correlation identifier, and the agent's answer |

   Every hop carries the same identifier, so no join is made by hand.

   > **[SCREENSHOT PENDING: E6T3S5 | Get-ActionTrail.ps1 timeline for the TCK-10501 priority change | source: capture]**

### Expected results

- [ ] Application Insights shows the set_ticket_priority call with your correlation identifier in its result
- [ ] The gateway log, the MCP server log and the ticket's Last Correlation ID carry the same identifier
- [ ] The Dataverse audit history shows the change attributed to the Senior Technician
- [ ] Your notes answer who asked, which agent, which tool, what was authorized, what changed and what was returned

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The agent still returns mobile numbers:** wait a minute after securing the column and start a new chat. Check that **Mobile Phone** shows column security enabled, and that the profile doesn't allow **mobilephone**.
- **The agent returns no email addresses either:** check that the profile allows **Read** on **emailaddress1** and that the MCP server's application user is on the profile's **Users** tab.
- **The note on TCK-10486 isn't withheld:** open the MCP server's `/health`; if `purview` isn't `enabled`, contact support.
- **A tool returns `PURVIEW_UNAVAILABLE`:** Purview couldn't check the content, so the server withheld it. Try once more; if it persists, contact support.
- **A log query returns nothing:** logs take 5 to 15 minutes to arrive. Widen the time range and try again later.

</details>

## Summary

In this exercise, you have completed the following:

- Secured contact columns in Dataverse, granted the agent's identity one of them, and saw the agent report the withheld values instead of guessing
- Reviewed the Purview DLP policy and the sensitivity label on a customer document, saw a card number withheld and a labelled document blocked, and found the DLP event in Purview
- Followed one approved write through Application Insights, the gateway and MCP server logs and the Dataverse audit history with one correlation identifier

#### You have successfully completed this exercise. Click **Next >>** from the lower right corner to proceed to the next exercise.
