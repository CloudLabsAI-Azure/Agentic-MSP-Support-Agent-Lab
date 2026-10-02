# Screenshot TODO

Every screenshot in the guide is still a pending marker. They need a pilot environment with the seeded Service Desk data, so they are captured during the pilot walk-through (`source: capture`) or reused from the standard CloudLabs getting-started set (`source: reuse`). When an image lands, save it in `Instructions/media/` under the ID below and replace the whole marker line with the embed, keeping its indentation:

```markdown
   ![Short descriptive alt text](./media/E1T1S1.png)
```

Capture rules: crop to the relevant blade, use a pilot tenant with no personal data, show the lab's own values (for example a DeploymentID-suffixed name), and draw numbered balloons wherever the step text carries bold **(1)**, **(2)** markers. Balloon count must equal marker count.

| ID | Page | Line | What the shot must show | Source |
|---|---|---|---|---|
| GS1 | `Instructions/getting-started.md` | 90 | Lab environment with the virtual machine on the left and the lab guide on the right | reuse |
| GS2 | `Instructions/getting-started.md` | 96 | Environment tab showing the lab credentials and resource details | reuse |
| GS3 | `Instructions/getting-started.md` | 102 | Split Window button in the top right corner of the lab guide | reuse |
| GS4 | `Instructions/getting-started.md` | 108 | Resources tab with the virtual machine Start, Stop, and Restart controls | reuse |
| GS5 | `Instructions/getting-started.md` | 116 | Zoom control next to the lab timer | reuse |
| GS6 | `Instructions/getting-started.md` | 125 | Lab Validation tab with the Validate button per step | reuse |
| GS7 | `Instructions/getting-started.md` | 153 | Sign-in screen with the username field highlighted | capture |
| GS8 | `Instructions/getting-started.md` | 159 | Sign-in screen with the Temporary Access Pass field highlighted | capture |
| GS9 | `Instructions/getting-started.md` | 177 | Resource groups page with the team resource group selected | capture |
| GS10 | `Instructions/getting-started.md` | 208 | PowerShell 7 window showing az account show output with the team account | capture |
| GS11 | `Instructions/getting-started.md` | 218 | Lab VM desktop with the lab shortcuts, Team environment.txt and Lab notes.txt | capture |
| E1T1S1 | `Instructions/exercise-1.md` | 51 | Team resource group Overview page listing its resources | capture |
| E1T1S2 | `Instructions/exercise-1.md` | 67 | Service Desk app Tickets list with the Open Tickets view and the row count | capture |
| E1T1S3 | `Instructions/exercise-1.md` | 71 | Ticket TCK-10489 form showing the SLA section | capture |
| E1T1S4 | `Instructions/exercise-1.md` | 77 | Foundry portal Build > Agents list with msp-support-agent | capture |
| E1T1S5 | `Instructions/exercise-1.md` | 87 | Agent playground with no tools and the agent's ungrounded answer | capture |
| E1T1S6 | `Instructions/exercise-1.md` | 101 | PowerShell output of Get-AgentIdentity.ps1 with the object ID and client ID | capture |
| E1T1S7 | `Instructions/exercise-1.md` | 107 | Microsoft Entra admin center Agent identities list filtered to the agent's object ID | capture |
| E1T1S9 | `Instructions/exercise-1.md` | 129 | PowerShell output of Invoke-McpTool.ps1 get_ticket for TCK-10489 | capture |
| E1T2S1 | `Instructions/exercise-1.md` | 153 | Power Apps environment selector with the Relecloud Service Desk environment | capture |
| E1T2S2 | `Instructions/exercise-1.md` | 162 | Knowledge Article table columns in Power Apps | capture |
| E1T2S8 | `Instructions/exercise-1.md` | 214 | Foundry Connected resources Add connection pane for Azure AI Search with keyless authentication | capture |
| E1T2S9 | `Instructions/exercise-1.md` | 220 | Load-SearchIndex.ps1 output with the count table and the match message | capture |
| E1T2S10 | `Instructions/exercise-1.md` | 226 | Azure AI Search Indexes page with the servicedesk-knowledge index and its document count | capture |
| E1T2S12 | `Instructions/exercise-1.md` | 254 | Agent playground showing the Azure AI Search tool and the grounded instructions | capture |
| E1T2S13 | `Instructions/exercise-1.md` | 264 | Grounded answer about Woodgrove Bank with a citation to the customer profile | capture |
| E1T3S2 | `Instructions/exercise-1.md` | 297 | Agent answer citing KB0007 with its resolution steps | capture |
| E1T4S5 | `Instructions/exercise-1.md` | 350 | Agent recommendation for Woodgrove Bank naming client 4.2.0 and firmware 10.1.4 | capture |
| E1T5S2 | `Instructions/exercise-1.md` | 380 | Agent explanation comparing the KB0058 and KB0031 applicability with Woodgrove Bank's versions | capture |
| E2T1S2 | `Instructions/exercise-2.md` | 43 | Agent answer listing three similar historical tickets with explained similarity | capture |
| E2T1S4 | `Instructions/exercise-2.md` | 51 | Historical ticket form with its resolution summary in the Service Desk app | capture |
| E2T2S2 | `Instructions/exercise-2.md` | 83 | Agent summary of Woodgrove Bank's six open tickets grouped by category with the recurring VPN issue flagged | capture |
| E2T2S3 | `Instructions/exercise-2.md` | 89 | Open Tickets view filtered on Woodgrove Bank showing six rows | capture |
| E2T3S3 | `Instructions/exercise-2.md` | 112 | Agent recommendation for TCK-10512 citing KB0133 and historical tickets | capture |
| E2T4S2 | `Instructions/exercise-2.md` | 144 | Agent list of the three tickets closest to SLA breach with business-hour figures | capture |
| E2T4S4 | `Instructions/exercise-2.md` | 152 | Open Tickets by SLA Remaining view in the Service Desk app | capture |
| E3T1S2 | `Instructions/exercise-3.md` | 41 | TOOLS.md read tools table open in Visual Studio Code | capture |
| E3T1S5 | `Instructions/exercise-3.md` | 61 | dataverse_repository.py get_ticket with the alternate key request in Visual Studio Code | capture |
| E3T2S2 | `Instructions/exercise-3.md` | 73 | Foundry Select a tool dialog with the Custom tab and Model Context Protocol (MCP) selected | capture |
| E3T2S3 | `Instructions/exercise-3.md` | 85 | Add Model Context Protocol tool form with the gateway URL, Microsoft Entra agent identity and audience | capture |
| E3T2S7 | `Instructions/exercise-3.md` | 107 | Playground tool approval prompt for get_ticket with its arguments | capture |
| E3T2S9 | `Instructions/exercise-3.md` | 123 | Log Analytics results for ApiManagementGatewayMCPLog with the get_ticket call | capture |
| E3T3S4 | `Instructions/exercise-3.md` | 174 | PowerShell output of the malformed get_ticket call with the validation message | capture |
| E3T4S3 | `Instructions/exercise-3.md` | 216 | Deploy-McpServer.ps1 output with the revision table and the cycle time | capture |
| E3T4S7 | `Instructions/exercise-3.md` | 238 | Container App Revisions and replicas page with the new revision running | capture |
| E4T1S3 | `Instructions/exercise-4.md` | 36 | Playground approval prompt for assign_ticket on TCK-10507 with its arguments | capture |
| E4T1S6 | `Instructions/exercise-4.md` | 50 | TCK-10507 related Ticket Notes with the agent's internal assignment note | capture |
| E4T1S7 | `Instructions/exercise-4.md` | 54 | TCK-10507 Audit History showing the change made by the id-mcp application user | capture |
| E4T2S2 | `Instructions/exercise-4.md` | 87 | Agent draft of a customer update for TCK-10489 without internal content | capture |
| E4T2S7 | `Instructions/exercise-4.md` | 119 | TCK-10489 Ticket Notes showing the new customer reply and the new internal note | capture |
| E4T3S3 | `Instructions/exercise-4.md` | 161 | Agent recommendation for TCK-10511 with category, priority, technician and sources | capture |
| E4T3S6 | `Instructions/exercise-4.md` | 175 | TCK-10511 form after triage and assignment with the SLA section filled in | capture |
| E4T4S5 | `Instructions/exercise-4.md` | 228 | PowerShell output of the rejected set_ticket_priority call with PRIORITY_NOT_ALLOWED | capture |
| E5T1S2 | `Instructions/exercise-5.md` | 30 | Resource group Check access result showing no role assignments for the agent identity | capture |
| E5T1S3 | `Instructions/exercise-5.md` | 41 | API Management MCP server policy with validate-azure-ad-token and the agent client ID | capture |
| E5T1S5 | `Instructions/exercise-5.md` | 47 | Application user details for id-mcp with the System Administrator role | capture |
| E5T2S2 | `Instructions/exercise-5.md` | 69 | Copy security role dialog for Service Desk Integration with the new role name | capture |
| E5T2S3 | `Instructions/exercise-5.md` | 75 | Security role editor with the Ticket table Write privilege set to None | capture |
| E5T2S4 | `Instructions/exercise-5.md` | 79 | Edit security roles pane for the MCP application user with only the least-privilege role selected | capture |
| E5T2S7 | `Instructions/exercise-5.md` | 99 | PowerShell output with error.dataverse showing 403, 0x80040220 and prvWritemsp_Ticket | capture |
| E5T3S2 | `Instructions/exercise-5.md` | 134 | Contact Email column with Enable column security selected under Advanced options | capture |
| E5T3S4 | `Instructions/exercise-5.md` | 148 | Agent answer reporting that contact email and phone details are restricted | capture |
| E5T3S7 | `Instructions/exercise-5.md` | 162 | Column security profile Users tab with the MCP application user added | capture |
| E5T3S8 | `Instructions/exercise-5.md` | 166 | Column security profile column permission for emailaddress1 with Read allowed | capture |
| E5T4S2 | `Instructions/exercise-5.md` | 199 | ContainerAppConsoleLogs result for the assign_ticket call with correlation_id and record_id | capture |
| E5T4S4 | `Instructions/exercise-5.md` | 215 | Foundry agent Traces conversation view with the assign_ticket tool call | capture |
| E5T4S5 | `Instructions/exercise-5.md` | 235 | TCK-10507 Audit History with the Assigned Technician change by the id-mcp application user | capture |
