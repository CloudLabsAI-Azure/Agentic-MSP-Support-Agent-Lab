# Exercise 5: Security, Governance, and Audit

### Estimated Duration: 45 minutes

## Scenario

Relecloud's security team has one question before the pilot: when the agent changes a ticket, what stops it from doing more, and can anyone prove afterwards what happened? Today the honest answer is uncomfortable. The agent can do anything the MCP server's identity can do, and that identity is a Dataverse System Administrator. In this exercise, the automation team puts the permission model in place and follows one action from the agent's answer to the database record.

## Overview

In this exercise, you compare the agent's own identity with the backend identity it acts through, and see why the backend's permissions are the ones that matter. You replace the backend's System Administrator role with a least-privilege Dataverse role and prove that Dataverse itself refuses a forbidden action. You protect contact data with column security, and finally you trace the assignment you made in Exercise 4 across the agent trace, the gateway log, the MCP server log and the Dataverse audit record.

## Objectives

In this exercise, you will complete the following tasks:

- Task 1: Compare the agent identity with the backend identity
- Task 2: Enforce a least-privilege boundary in Dataverse
- Task 3: Protect contact data
- Task 4: Trace one action end to end

## Task 1: Compare the agent identity with the backend identity

In this task, you will list what the agent's Entra Agent ID can do and what the Dataverse application user behind the MCP server can do, and state what that means.

1. In the Microsoft Entra admin center, go to **Entra ID** > **Agents** > **Agent identities**, search for the agent identity object ID in **Lab notes.txt**, and open it. It is an agent identity created from a blueprint; it has no credentials of its own.

1. In the Azure portal, open your resource group, select **Access control (IAM)**, select **Check access**, and search for the agent identity's object ID. The agent identity has no Azure role assignments on your resources.

   > **[SCREENSHOT PENDING: E5T1S2 | Resource group Check access result showing no role assignments for the agent identity | source: capture]**

   If **Check access** doesn't find the agent identity, list its role assignments in PowerShell 7 instead. An empty result means it has no role assignments on your resource group:

   ```powershell
   $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
   az role assignment list --resource-group $s.ResourceGroup --include-inherited --query "[?principalId=='$($s.AgentIdentityObjectId)'].{role:roleDefinitionName, scope:scope}" --output table
   ```

1. Open the API Management service **apim-msp-<inject key="DeploymentID" enableCopy="false"/>**, select **APIs** > **MCP servers**, select **Service Desk MCP**, and open its **Policies**. The `validate-azure-ad-token` policy accepts only tokens whose client application ID is `{{agent-client-id}}` and whose audience is the gateway's. Under **Named values**, `agent-client-id` holds your agent identity's client ID. Calling this API is the only thing the agent identity is allowed to do.

   > **[SCREENSHOT PENDING: E5T1S3 | API Management MCP server policy with validate-azure-ad-token and the agent client ID | source: capture]**

1. Open the **Power Platform admin center** shortcut, select **Manage** > **Environments**, and select **Relecloud Service Desk <inject key="DeploymentID" enableCopy="false"/>**. Select **Settings**, expand **Users + permissions**, and select **Application users**.

1. Select the application user whose application ID is the MCP backend identity's client ID, <inject key="MCP Backend Identity Client ID" enableCopy="true"/>, and select **Details**. The list shows the value in the **App ID** column, and **Details** calls it **Microsoft Entra application ID**. Its **Assigned security roles** show **System Administrator**: every table, every operation including delete, plus customization.

   > **[SCREENSHOT PENDING: E5T1S5 | Application user details for id-mcp with the System Administrator role | source: capture]**

1. In **Lab notes.txt**, fill in **Agent identity permissions**, **MCP application user permissions** and **One sentence on inherited permissions**. For example: *The agent can do whatever the MCP server's identity can do through the tools, so the backend's Dataverse role, not the agent identity, is the real limit on the agent.*

## Task 2: Enforce a least-privilege boundary in Dataverse

In this task, you will decide what the agent may do, build a Dataverse security role that allows only that, assign it to the MCP identity, and capture the error Dataverse returns for a forbidden action.

1. Decide the boundary for the pilot. Write it in **Lab notes.txt** next to **Least-privilege boundary**:

   *During the pilot, the agent may read service desk data and add notes to tickets, but it may not change a ticket's status, priority, category or assignment. Technicians make those changes.*

   > **Note:** The denial must come from Dataverse, not from the MCP server's code. A rule in code protects only the callers that go through that code; a Dataverse role protects the data from every caller that uses this identity.

1. In the Power Platform admin center, in your environment's **Settings**, select **Users + permissions** > **Security roles**. Select the role **Service Desk Integration** and, on the command bar, select **Copy security role**. Name the copy:

   ```
   Service Desk Agent (least privilege)
   ```

   Select **Copy**.

   > **[SCREENSHOT PENDING: E5T2S2 | Copy security role dialog for Service Desk Integration with the new role name | source: capture]**

   > **Note:** **Service Desk Integration** is a reference role that holds exactly what the MCP server needs: read on every Service Desk table, write on tickets and notes, and the append rights that link notes to tickets. Nobody holds it yet.

1. Open **Service Desk Agent (least privilege)**. Search for the **Ticket** table, select it, and set **Write** to **None**. Leave **Read**, **Append** and **Append To** at **Organization**. Check that the **Ticket Note** table still has **Create**, **Read**, **Write**, **Append** and **Append To** at **Organization**. Select **Save + close**.

   > **[SCREENSHOT PENDING: E5T2S3 | Security role editor with the Ticket table Write privilege set to None | source: capture]**

1. Select **Users + permissions** > **Application users**, select the MCP application user, and select **Edit security roles**. Select **Service Desk Agent (least privilege)**, clear **System Administrator**, and select **Save**.

   > **[SCREENSHOT PENDING: E5T2S4 | Edit security roles pane for the MCP application user with only the least-privilege role selected | source: capture]**

1. Wait about one minute for the role change to take effect.

1. In the agent playground, start a new chat and attempt the forbidden action:

   ```
   TCK-10509 is waiting for the customer to tell us the calendar name. Change its status to Waiting on Customer.
   ```

   Approve **update_ticket_status**. The tool returns `DATAVERSE_ACCESS_DENIED`, and the agent should report that the change isn't permitted rather than retry or look for another way.

1. Capture the platform's own error. In the Visual Studio Code terminal, make the same call through the diagnostics API:

   ```powershell
   .\scripts\Invoke-McpTool.ps1 update_ticket_status @{ ticket_number = 'TCK-10509'; status = 'Waiting on Customer'; reason = 'Least-privilege test from the operator API.' }
   ```

   Under `error.dataverse` you see Dataverse's answer: `status` **403**, `code` **0x80040220**, and a message saying the principal is missing the **prvWritemsp_Ticket** privilege. Record the code and message in **Lab notes.txt** next to **Platform error captured**. If `code` is empty, record the status and the message; they carry the same answer.

   > **[SCREENSHOT PENDING: E5T2S7 | PowerShell output with error.dataverse showing 403, 0x80040220 and prvWritemsp_Ticket | source: capture]**

1. Confirm that the allowed action still works:

   ```
   Add an internal note to TCK-10509: status change to Waiting on Customer requested; a technician needs to apply it.
   ```

   Approve **add_ticket_note**. The note is created: the role still allows notes.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Dataverse denies the forbidden action" is registered (validation-scripts/README.md). -->

## Task 3: Protect contact data

In this task, you will secure contact columns in Dataverse, see the agent receive withheld values and say so, and then grant the agent read access to one column only.

> **Important:** Complete Task 2 first. Column security doesn't apply to an identity that holds the System Administrator role, so the MCP application user must hold only **Service Desk Agent (least privilege)** before you start.

1. In the playground, start a new chat and send:

   ```
   List the contacts at Woodgrove Bank with their email addresses and phone numbers.
   ```

   Approve **get_customer_contacts**. The agent lists three contacts with email, business phone and mobile numbers.

1. In Power Apps, select **Tables**, open the **Contact** table, and under **Schema** select **Columns**. Open **Email**, expand **Advanced options**, and under **General** select **Enable column security**. Select **Save**.

   > **[SCREENSHOT PENDING: E5T3S2 | Contact Email column with Enable column security selected under Advanced options | source: capture]**

1. Secure **Business Phone** and **Mobile Phone** the same way.

   > **Note:** If **Enable column security** is unavailable for a column, Dataverse doesn't allow that column to be secured; skip it and note in **Lab notes.txt** which columns you secured.

1. Wait about one minute, then start a new chat, so that the agent can't reuse its first answer, and ask the same question again:

   ```
   List the contacts at Woodgrove Bank with their email addresses and phone numbers.
   ```

   The tool now returns the secured values as empty and names them in `withheld_fields`. The agent should say that the details are restricted, not that the contacts have no email or phone, and must not guess them.

   > **[SCREENSHOT PENDING: E5T3S4 | Agent answer reporting that contact email and phone details are restricted | source: capture]**

   > **Note:** The provided screenshot is for your reference; the output you receive may vary.

1. Open the same contacts in the Service Desk app. You still see every value, because column security never applies to users with the System Administrator role, and your team account has it. That is also why Task 2 had to take System Administrator away from the MCP identity first.

1. Grant the agent the one column it needs. In the Power Platform admin center, in your environment's **Settings**, select **Users + permissions** > **Column security profiles**, select **New Profile**, enter the name below and select **Save**:

   ```
   Service Desk Agent contact access
   ```

1. Open the profile, select the **Users** tab, select **+ Add Users**, search for the MCP application user by its client ID, <inject key="MCP Backend Identity Client ID" enableCopy="true"/>, and select **Add**.

   > **[SCREENSHOT PENDING: E5T3S7 | Column security profile Users tab with the MCP application user added | source: capture]**

1. Select the **Column Permission** tab, select **emailaddress1** on the **contact** table, and select **Edit**. If Email couldn't be secured, select the first column you did secure instead. Set **Read** to **Allowed**, leave the other permissions **Not Allowed**, and select **Save**.

   > **[SCREENSHOT PENDING: E5T3S8 | Column security profile column permission for emailaddress1 with Read allowed | source: capture]**

1. Wait about one minute, start a new chat and ask the same question again. The column you allowed is back, normally the email addresses; the other secured columns are still withheld.

> **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
> - Hit the Validate button for the corresponding task. If you receive a success message, you can proceed to the next task.
> - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
> - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help.

<validation step="REPLACE-WITH-VALIDATION-GUID" />

<!-- TODO: replace with the GUID minted when "Contact columns protected" is registered (validation-scripts/README.md). -->

## Task 4: Trace one action end to end

In this task, you will find the assignment of TCK-10507 from Exercise 4 in four records, join them, and state which join you had to make by hand.

1. Open **Lab notes.txt** and find the **Time of the assign_ticket write on TCK-10507**.

1. Start with the MCP server's own log, which carries the most identifiers. In the Azure portal, open the Log Analytics workspace **log-msp-<inject key="DeploymentID" enableCopy="false"/>**, select **Logs**, and run:

   ```kql
   ContainerAppConsoleLogs
   | where TimeGenerated > ago(1d)
   | extend j = parse_json(Log)
   | where tostring(j.event) == "tool_call" and tostring(j.tool) == "assign_ticket"
   | where tostring(j.arguments.ticket_number) == "TCK-10507"
   | project TimeGenerated, caller = tostring(j.caller), outcome = tostring(j.outcome),
             correlation_id = tostring(j.correlation_id), record_id = tostring(j.record.id), dataverse = j.dataverse
   ```

   Note the **correlation_id**, the **record_id** of the ticket row, and the `PATCH msp_tickets(...)` entry in **dataverse** with its Dataverse request ID.

   > **[SCREENSHOT PENDING: E5T4S2 | ContainerAppConsoleLogs result for the assign_ticket call with correlation_id and record_id | source: capture]**

1. Find the same call in the gateway's MCP log:

   ```kql
   ApiManagementGatewayMCPLog
   | where TimeGenerated > ago(1d)
   | where Method == "tools/call" and ToolName == "assign_ticket"
   | project TimeGenerated, ToolName, SessionId, CorrelationId, ClientName, AuthenticationMethod
   | order by TimeGenerated desc
   ```

   One row has a **CorrelationId** equal to the server's **correlation_id**: API Management sends its request ID to the server in a header and the server logs it, so this join is exact. Check whether **SessionId** is populated and note what it contains; with this stateless server it is normally empty.

1. Find the agent's side of the action. In the Foundry portal, open **msp-support-agent** and select the **Traces** tab. Find the conversation from the write time, open it, and select the **assign_ticket** tool call. Note its time, arguments and trace ID.

   > **[SCREENSHOT PENDING: E5T4S4 | Foundry agent Traces conversation view with the assign_ticket tool call | source: capture]**

   > **Note:** If the **Traces** tab is slow to load, query the tool spans in Log Analytics instead. The first query lists the spans; the second shows their arguments and results, which Application Insights has stored in the separate `AppGenAIContent` table since 30 September 2026.

   ```kql
   AppDependencies
   | where TimeGenerated > ago(1d)
   | where Name has "execute_tool" or Name has "ExecuteTool" or tostring(Properties["gen_ai.operation.name"]) == "execute_tool"
   | project TimeGenerated, Name, OperationId, DurationMs, Success
   ```

   ```kql
   AppGenAIContent
   | where TimeGenerated > ago(1d)
   | where isnotempty(ToolCallArguments)
   | project TimeGenerated, TraceId, SpanId, AgentName, ToolCallArguments, ToolCallResult
   ```

1. Find the database side. In the Service Desk app, open **TCK-10507**, select **Related** > **Audit History**, and find the **Assigned Technician** change at the write time, made by the **id-mcp-<inject key="DeploymentID" enableCopy="false"/>** application user.

   > **[SCREENSHOT PENDING: E5T4S5 | TCK-10507 Audit History with the Assigned Technician change by the id-mcp application user | source: capture]**

1. Join the four records:

   | Hop | Record | Its identifier | Joined to the next hop by |
   |---|---|---|---|
   | Agent | Trace span for the assign_ticket tool call | Trace ID | Time, tool name and arguments, by hand |
   | Gateway | ApiManagementGatewayMCPLog row | CorrelationId | CorrelationId equals the server's correlation_id, exact |
   | MCP server | ContainerAppConsoleLogs tool_call line | correlation_id, record_id, Dataverse request ID | record_id is the audited ticket row; time matches |
   | Dataverse | Audit History entry | Audit record on TCK-10507 | |

1. In **Lab notes.txt**, next to **Trace join**, state which join was manual and why. In this lab the agent-to-gateway join is manual: the agent's trace ID doesn't appear in the gateway's MCP log, and a stateless server has no MCP session to match, so you match on time, tool name and arguments. If **SessionId** was populated in your gateway query, note what it contained. Note also what the Dataverse record attributes the change to: the MCP server's identity, not the agent or the person who asked.

1. If you have time, open the trace for one of the thin explanations you recorded in Exercise 1, using its time. Look at the **azure_ai_search** call and the documents it returned, and compare them with what the agent claimed. Note what would have made that explanation trustworthy; you discuss it in the wrap-up.

### Success Criteria

- [ ] You found the assign_ticket action in all four records
- [ ] The gateway CorrelationId matches the MCP server's correlation_id
- [ ] Your notes state that the agent-to-gateway join is manual, and why

## Troubleshooting

<details>
<summary>Select to show fixes for common problems in this exercise</summary>

- **The forbidden status change still succeeds:** the role change hasn't applied yet, or System Administrator is still assigned. Check that the MCP application user holds only **Service Desk Agent (least privilege)**, wait a minute, start a new chat and try again.
- **The agent still shows email and phone values after you secured them:** check that Task 2 removed System Administrator from the MCP application user, wait a minute, and ask in a new chat. If the values are still visible, in Power Apps select **Solutions** > **Publish all customizations** and ask again.
- **Check access or the Application users list doesn't show the identity you search for:** search by the full ID, not by name, and use the PowerShell fallback in Task 1.
- **A log query returns no rows:** gateway and server logs take 5 to 15 minutes to arrive, and agent traces a few minutes. Widen the time range to `ago(2d)` and try again.
- **Audit History shows no entry for TCK-10507:** confirm the Exercise 4 assignment happened (the ticket shows **Lucas Moreau** as **Assigned Technician**). Audit records stay with the ticket, so a missing entry means the write didn't happen.

</details>

## Clean up

You don't need to delete anything. CloudLabs removes your Azure resources when the lab ends, and the delivery team removes the Power Platform developer environment. Before you leave, sign out of the Foundry portal, the Service Desk app and the admin centers in the VM browser, and close **Lab notes.txt** after copying anything you want to keep.

## Summary

In this exercise, you have completed the following:

- Compared the agent's Entra Agent ID with the MCP server's Dataverse application user and recorded why the backend's permissions are the real limit
- Replaced System Administrator with a least-privilege Dataverse role and captured the platform's own denial of a forbidden action
- Secured contact columns, saw the agent report withheld values, and granted it read access to one column through a column security profile
- Traced one agent action across the agent trace, the gateway log, the MCP server log and the Dataverse audit record, and identified the manual join

## Conclusion

Congratulations! You have built a grounded service desk agent for Relecloud Managed Services, connected it to live data through governed MCP tools, let it act on tickets, and put a permission model and an audit trail around it. Along the way you saw where control actually sits: the agent's instructions guide it, the tool code and the approval prompt check it, and the Dataverse role of the identity it acts through decides what it can do.

For the wrap-up discussion with your facilitator, bring your **Lab notes.txt** and consider:

- Which explanation from Exercise 1 was thinnest, and what would fix it: better data, better instructions, or a different tool?
- What else would you move from instructions into code, and from code into Dataverse?
- How would you close the manual join between the agent and the gateway before going to production?
