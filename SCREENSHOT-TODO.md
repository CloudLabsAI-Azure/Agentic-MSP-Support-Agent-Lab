# Screenshot TODO

Every screenshot in the guide is still a pending marker. They need a pilot environment with the seeded Service Desk data, so they are captured during the pilot walk-through (`source: capture`) or reused from the standard CloudLabs getting-started set (`source: reuse`). When an image lands, save it in `Instructions/media/` under the ID below and replace the whole marker line with the embed, keeping its indentation:

```markdown
   ![Short descriptive alt text](./media/E1T1S1.png)
```

Capture rules: crop to the relevant blade, use a pilot tenant with no personal data, show the lab's own values (for example a DeploymentID-suffixed name), and draw numbered balloons wherever the step text carries bold **(1)**, **(2)** markers. Balloon count must equal marker count.

| ID | Page | Line | What the shot must show | Source |
|---|---|---|---|---|
| GS1 | `Instructions/getting-started.md` | 101 | Lab environment with the virtual machine on the left and the lab guide on the right | reuse |
| GS2 | `Instructions/getting-started.md` | 107 | Environment tab showing the lab credentials and resource details | reuse |
| GS3 | `Instructions/getting-started.md` | 113 | Split Window button in the top right corner of the lab guide | reuse |
| GS4 | `Instructions/getting-started.md` | 119 | Resources tab with the virtual machine Start, Stop, and Restart controls | reuse |
| GS5 | `Instructions/getting-started.md` | 127 | Zoom control next to the lab timer | reuse |
| GS6 | `Instructions/getting-started.md` | 136 | Lab Validation tab with the Validate button per step | reuse |
| GS7 | `Instructions/getting-started.md` | 164 | Sign-in screen with the username field highlighted | capture |
| GS8 | `Instructions/getting-started.md` | 170 | Sign-in screen with the Temporary Access Pass field highlighted | capture |
| GS9 | `Instructions/getting-started.md` | 188 | Resource groups page with the team resource group selected | capture |
| GS10 | `Instructions/getting-started.md` | 219 | PowerShell 7 window showing az account show output with the team account | capture |
| GS11 | `Instructions/getting-started.md` | 229 | Lab VM desktop with the lab shortcuts, Team environment.txt and Lab notes.txt | capture |
| E1T1S2 | `Instructions/exercise-1.md` | 44 | Lab readiness check window with every component Ready | capture |
| E1T1S3 | `Instructions/exercise-1.md` | 68 | Service Desk app Tickets list with the Open Tickets view and the row count | capture |
| E1T1S4 | `Instructions/exercise-1.md` | 86 | Agent playground showing the servicedesk MCP tool and no knowledge source | capture |
| E1T1S5 | `Instructions/exercise-1.md` | 98 | Agent answer for TCK-10489 from the get_ticket tool | capture |
| E1T2S1 | `Instructions/exercise-1.md` | 146 | Knowledge Article table columns in Power Apps | capture |
| E1T2S3 | `Instructions/exercise-1.md` | 187 | Load-SearchIndex.ps1 output with the count table and the match message | capture |
| E1T2S4 | `Instructions/exercise-1.md` | 203 | Agent playground showing the Azure AI Search knowledge source and the grounded instructions | capture |
| E1T2S5 | `Instructions/exercise-1.md` | 213 | Grounded answer about Woodgrove Bank with a citation to the customer profile | capture |
| E1T3S2 | `Instructions/exercise-1.md` | 246 | Agent answer citing KB0007 with its resolution steps | capture |
| E1T4S2 | `Instructions/exercise-1.md` | 282 | Agent recommendation for Woodgrove Bank naming client 4.2.0 and firmware 10.1.4 | capture |
| E1T5S1 | `Instructions/exercise-1.md` | 313 | Agent explanation comparing the KB0058 and KB0031 applicability with Woodgrove Bank's versions | capture |
| E2T1S1 | `Instructions/exercise-2.md` | 28 | TCK-10514 in the Untriaged Tickets view with its description | capture |
| E2T1S3 | `Instructions/exercise-2.md` | 44 | Agent answer listing similar historical tickets with explained similarity | capture |
| E2T1S4 | `Instructions/exercise-2.md` | 72 | Historical ticket TCK-10035 with its related article KB0023 and resolution summary | capture |
| E2T2S3 | `Instructions/exercise-2.md` | 124 | Agent summary of Woodgrove Bank's open tickets and escalated history | capture |
| E2T2S4 | `Instructions/exercise-2.md` | 130 | Open Tickets view filtered on Woodgrove Bank showing six rows | capture |
| E2T3S2 | `Instructions/exercise-2.md` | 153 | Agent recommendation for TCK-10514 citing KB0023, historical tickets and the customer procedure | capture |
| E2T4S2 | `Instructions/exercise-2.md` | 197 | Agent list of the tickets closest to SLA breach with business-hour figures | capture |
| E2T4S3 | `Instructions/exercise-2.md` | 203 | TCK-10500 SLA section in the Service Desk app | capture |
| E3T1S2 | `Instructions/exercise-3.md` | 45 | Invoke-McpTool.ps1 -List output with the Kind and Approval columns | capture |
| E3T1S3 | `Instructions/exercise-3.md` | 60 | dataverse_repository.py get_ticket with the alternate key request in Visual Studio Code | capture |
| E3T2S2 | `Instructions/exercise-3.md` | 78 | Agent answer for TCK-10502 next to the ticket form in the Service Desk app | capture |
| E3T2S3 | `Instructions/exercise-3.md` | 94 | Show-McpServerLog.ps1 output with the get_ticket call and its correlation ID | capture |
| E3T3S3 | `Instructions/exercise-3.md` | 133 | INVALID_ARGUMENT error with details.violations for the malformed ticket number | capture |
| E3T4S3 | `Instructions/exercise-3.md` | 179 | Deploy-McpServer.ps1 output with the revision table and the cycle time | capture |
| E3T4S4 | `Instructions/exercise-3.md` | 187 | Container App Revisions and replicas page with the new revision running | capture |
| E4T1S2 | `Instructions/exercise-4.md` | 47 | Playground approval prompt for set_ticket_priority with its arguments | capture |
| E4T1S4 | `Instructions/exercise-4.md` | 64 | TCK-10501 with priority P3 and the audit note with the correlation ID | capture |
| E4T2S2 | `Instructions/exercise-4.md` | 89 | TCK-10489 Ticket Notes showing the new customer reply and the new internal note | capture |
| E4T2S3 | `Instructions/exercise-4.md` | 99 | Agent draft of a customer update for TCK-10489 without internal content | capture |
| E4T3S4 | `Instructions/exercise-4.md` | 160 | Approval prompt for triage_ticket on TCK-10514 with a reason that cites KB0023 | capture |
| E4T5S4 | `Instructions/exercise-4.md` | 284 | TCK-10514 Escalation section after the escalate_ticket call | capture |
| E5T1S1 | `Instructions/exercise-5.md` | 38 | Power Platform admin center Application users list with the MCP server's application user | capture |
| E5T2S1 | `Instructions/exercise-5.md` | 71 | Key vault Secrets list with mcp-backend-key | capture |
| E5T2S4 | `Instructions/exercise-5.md` | 96 | AZKVAuditLogs SecretGet rows for mcp-backend-key by the MCP server's managed identity | capture |
| E5T3S2 | `Instructions/exercise-5.md` | 108 | Service Desk Agent Write role with Ticket Write, Append and Append To at Business Unit level | capture |
| E5T3S4 | `Instructions/exercise-5.md` | 120 | Tool result with DATAVERSE_ACCESS_DENIED and the platform error under error.dataverse | capture |
| E5T4S2 | `Instructions/exercise-5.md` | 152 | Tier 1 Technician playground with the denied set_ticket_priority call | capture |
| E5T4S4 | `Instructions/exercise-5.md` | 161 | Show-McpServerLog.ps1 rows for the denied and the allowed set_ticket_priority calls | capture |
| E6T1S1 | `Instructions/exercise-6.md` | 31 | Column security profile with Read allowed on contact emailaddress1 | capture |
| E6T1S3 | `Instructions/exercise-6.md` | 43 | Agent answer reporting that contact mobile numbers are restricted | capture |
| E6T2S1 | `Instructions/exercise-6.md` | 65 | Purview DLP policy rule with the Credit Card Number sensitive information type | capture |
| E6T2S4 | `Instructions/exercise-6.md` | 93 | Agent answers with the withheld note and the label-protected document | capture |
| E6T2S5 | `Instructions/exercise-6.md` | 101 | Purview Activity explorer with the DLP rule matched event | capture |
| E6T3S5 | `Instructions/exercise-6.md` | 176 | Get-ActionTrail.ps1 timeline for the TCK-10501 priority change | capture |
| E7T1S2 | `Instructions/exercise-7.md` | 40 | Agent summary and recommendation for TCK-10515 with its sources | capture |
| E7T1S4 | `Instructions/exercise-7.md` | 60 | Get-ActionTrail.ps1 timeline for the TCK-10515 triage | capture |
