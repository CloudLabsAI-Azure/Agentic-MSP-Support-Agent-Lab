# Validation scripts: registration checklist

These scripts back the placeholder validation tags in the lab guide (each tag's `step`
attribute still holds the authoring placeholder). Validations are registered on the CloudLabs
Template, not in the markdown. Register each script below, deploy the steps, then replace each
placeholder in the guide with the GUID the platform mints for that step.

## Register a step

Admin Portal > Template > **Edit** > **Course Details** tab > **Manage**, then for each row in
the table:

1. Under the **Module** for the exercise, add a **Labs/Lectures/Quizzes** item for the task
   (Type = `Lab`), then add a **Step**.
1. Set the step fields:
   - **Name:** the step name in the table
   - **Validation Type:** `Custom`
   - **Score:** the score in the table
   - **Script Type:** `PowerShellV2`
   - **Script:** paste the whole script file
   - **Parameters:** `GET-DEPLOYMENT-ID` mapped to `$DeploymentID` (every script uses only this)
   - **Run As:** `System`
1. After all steps are added, select **DEPLOY ALL STEPS**. Mapping takes 5 to 7 minutes.
1. Turn on **Enable Lab Validation** on the Template so learners see the **Lab Validation** tab.
1. Copy each step's GUID into the matching tag in the guide (file and task in the table).

| Module | Task | Step name | Script | Score | Guide location |
|---|---|---|---|---|---|
| Exercise 1 | Task 2 | Knowledge index loaded and connected | `ex1-task2-knowledge-index.ps1` | 10 | `Instructions/exercise-1.md`, end of Task 2 |
| Exercise 2 | Task 1 | Agent reads the new incident | `ex2-task1-new-incident.ps1` | 5 | `Instructions/exercise-2.md`, end of Task 1 |
| Exercise 3 | Task 2 | Agent calls a read tool through the gateway | `ex3-task2-agent-read-tool.ps1` | 5 | `Instructions/exercise-3.md`, end of Task 2 |
| Exercise 3 | Task 4 | Changed MCP server redeployed | `ex3-task4-redeploy.ps1` | 10 | `Instructions/exercise-3.md`, end of Task 4 |
| Exercise 4 | Task 1 | Write tool called with approval | `ex4-task1-write-approval.ps1` | 5 | `Instructions/exercise-4.md`, end of Task 1 |
| Exercise 4 | Task 2 | Customer reply and internal note separated | `ex4-task2-customer-reply.ps1` | 5 | `Instructions/exercise-4.md`, end of Task 2 |
| Exercise 4 | Task 3 | Grounded action on the new incident | `ex4-task3-grounded-action.ps1` | 10 | `Instructions/exercise-4.md`, end of Task 3 |
| Exercise 4 | Task 4 | Tool boundary tightened | `ex4-task4-limit-boundary.ps1` | 5 | `Instructions/exercise-4.md`, end of Task 4 |
| Exercise 4 | Task 5 | Scoped tool added and called | `ex4-task5-scoped-tool.ps1` | 10 | `Instructions/exercise-4.md`, end of Task 5 |
| Exercise 5 | Task 3 | Least-privilege boundary enforced by Dataverse | `ex5-task3-least-privilege.ps1` | 10 | `Instructions/exercise-5.md`, end of Task 3 |
| Exercise 5 | Task 4 | User-level authorization | `ex5-task4-user-authorization.ps1` | 10 | `Instructions/exercise-5.md`, end of Task 4 |
| Exercise 6 | Task 1 | Contact columns protected | `ex6-task1-column-security.ps1` | 5 | `Instructions/exercise-6.md`, end of Task 1 |
| Exercise 6 | Task 2 | Purview withholds sensitive content | `ex6-task2-purview.ps1` | 5 | `Instructions/exercise-6.md`, end of Task 2 |
| Exercise 7 | Task 1 | End-to-end scenario completed | `ex7-task1-end-to-end.ps1` | 5 | `Instructions/exercise-7.md`, end of Task 1 |

The scores add up to 100. Every exercise has at least one validated step. The remaining tasks
and the business case are conversational or manual (agent answers, trace reviews), so the
guide uses Expected results checklists there instead of platform validation.

## What the scripts rely on

- Resource names derive from the DeploymentID: `srch-msp-<DID>`, `aif-msp-<DID>`,
  `proj-msp-<DID>`, `ca-mcp-<DID>`, `log-msp-<DID>`, `apim-msp-<DID>`.
- The validation identity (Run As **System**) needs read access to the lab resource group,
  `listAdminKeys` on the search service and query access to the Log Analytics workspace.
  The CloudLabs service principal has these through its subscription role.
- Exercises 2 to 7 read the MCP server's own tool invocation log in `ContainerAppConsoleLogs`.
  Each tool call writes one JSON line with `tool`, `outcome`, `error_code`, `caller` (`agent`
  or `operator`), `user`, `correlation_id`, `authorization`, `dataverse`, `purview`, `record`
  and `arguments` (see the MCP server's README). Console logs can take a few minutes to arrive,
  so every script retries three times, 60 seconds apart, and the failure messages tell the
  learner to validate again shortly.
- The Container Apps diagnostic setting can take up to 90 minutes to deliver its first data in
  a new workspace. Provision the environments at least two hours before the event (see
  `setup/README.md`).

## Before the event

Run every step once against a pilot deployment with Template Audit > **+ADD** > Event Type
`Lab Test`, after walking the guide end to end, and confirm each step reports `Successful`.
