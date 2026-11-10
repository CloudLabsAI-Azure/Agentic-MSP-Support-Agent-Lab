#Requires -Version 7.0
<#
.SYNOPSIS
    Shows your agent's Microsoft Entra Agent ID, its tools, and which identity each hop of a tool
    call uses (Exercise 5, Task 1).

.DESCRIPTION
    Reads the agent from your Foundry project:
        GET {project endpoint}/agents/{agent name}?api-version=v1
    and prints its instance_identity. principal_id is the Agent ID's object ID, the value you search
    for in the Microsoft Entra admin center; client_id is its application ID. Foundry creates this
    identity with the agent, and it starts with no permissions of its own.

    It then prints the identity map of one tool call: who signs in, which identity the gateway sees,
    and which identity reaches Dataverse. The Service Desk MCP connections use OAuth identity
    passthrough: the gateway receives your own token, so Dataverse decides each call with your
    security role. The agent's ID travels in the MCP server's log line for every call. The Azure AI
    Search tool uses the project connection's identity, not the Agent ID.

    Read-only: it changes nothing. Uses your own Azure CLI sign-in: run 'az login' first.

.PARAMETER PassThru
    Also returns the values as an object, for use in your own scripts.

.EXAMPLE
    C:\LabFiles\tools\Get-AgentIdentity.ps1
#>
[CmdletBinding()]
param(
    [switch]$PassThru,
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json'
)

$ErrorActionPreference = 'Stop'

function Write-Section([string]$Text) { Write-Host ''; Write-Host "==== $Text" -ForegroundColor Cyan }
function Write-Caution([string]$Text) { Write-Host "  [check] $Text" -ForegroundColor Yellow }
function Stop-Script([string]$Text) { Write-Host ''; Write-Host "Stopped: $Text" -ForegroundColor Red; exit 1 }

function Read-LabSettings([string]$Path, [string[]]$Required) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "The lab settings file $Path was not found. Lab provisioning writes it; contact CloudLabs support if it is missing." }
    try { $s = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "The lab settings file $Path is not valid JSON ($($_.Exception.Message)). Contact CloudLabs support." }
    $missing = @($Required | Where-Object { -not $s.PSObject.Properties[$_] -or [string]::IsNullOrWhiteSpace([string]$s.$_) })
    if ($missing.Count) { throw "The lab settings file $Path has no value for: $($missing -join ', '). Contact CloudLabs support." }
    return $s
}

function Get-AzCliToken([string]$Resource, [string]$TenantId) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found on this machine. Use the lab VM, where it is installed.' }
    $cliArgs = @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv')
    if ($TenantId) { $cliArgs += @('--tenant', $TenantId) }
    $token = & az @cliArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$token")) {
        throw "Azure CLI has no sign-in for your lab tenant. Run 'az login', sign in as the Senior Technician, and run this script again."
    }
    return ("$token").Trim()
}

function Get-ToolNames($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value.PSObject.Properties['tool_names']) { return @($Value.tool_names) }
    return @($Value)
}

function Format-Approval($Value) {
    if ($null -eq $Value) { return 'always (default)' }
    if ($Value -is [string]) { return $Value }
    $parts = @()
    if ($Value.PSObject.Properties['always']) { $parts += "always for $(@(Get-ToolNames $Value.always).Count) tool(s)" }
    if ($Value.PSObject.Properties['never']) { $parts += "never for $(@(Get-ToolNames $Value.never).Count) tool(s)" }
    return ($parts -join ', ')
}

try {
    $settings = Read-LabSettings $SettingsPath @('FoundryProjectEndpoint', 'AgentName')
    $token = Get-AzCliToken 'https://ai.azure.com' $settings.TenantId
    $endpoint = ([string]$settings.FoundryProjectEndpoint).TrimEnd('/')
    $agent = Invoke-RestMethod -Uri "$endpoint/agents/$($settings.AgentName)?api-version=v1" -Headers @{ Authorization = "Bearer $token" } `
        -SkipHttpErrorCheck -StatusCodeVariable httpStatus -TimeoutSec 60
    if ([int]$httpStatus -eq 404) { throw "The agent $($settings.AgentName) was not found in your project. Contact CloudLabs support." }
    if ([int]$httpStatus -in 401, 403) { throw "Your account may not read agents in this project (HTTP $httpStatus). Sign in with 'az login' as the Senior Technician, who holds Foundry User on the project." }
    if ([int]$httpStatus -ge 400) { throw "Reading the agent failed (HTTP $httpStatus): $($agent.error.message)" }

    $identity = $agent.instance_identity
    $blueprint = if ($agent.blueprint) { $agent.blueprint } else { $agent.blueprint_reference }
    $latest = $agent.versions.latest
    $objectId = [string]$identity.principal_id
    $clientId = [string]$identity.client_id

    Write-Section "The agent and its Microsoft Entra Agent ID"
    [pscustomobject][ordered]@{
        'Agent name'                   = $agent.name
        'Latest version'               = $latest.version
        'Model deployment'             = $latest.definition.model
        'Agent ID object ID'           = if ($objectId) { $objectId } else { '(none: the agent has no Entra Agent ID)' }
        'Agent ID client ID'           = if ($clientId) { $clientId } else { '(none)' }
        'Agent blueprint client ID'    = if ($blueprint.client_id) { $blueprint.client_id } elseif ($blueprint.blueprint_id) { $blueprint.blueprint_id } else { '(not returned)' }
    } | Format-List | Out-String | Write-Host
    if (-not $objectId) { Write-Caution 'The agent has no instance_identity. Contact CloudLabs support: every lab agent gets its own Entra Agent ID when it is created.' }
    if ($settings.AgentId -and $clientId -and $settings.AgentId -ne $clientId) {
        Write-Caution "lab-settings.json records the Agent ID client ID $($settings.AgentId), but the agent now has $clientId. The MCP server's log lines use the value it was configured with; tell CloudLabs support."
    }
    if ($settings.AgentIdentityObjectId -and $objectId -and $settings.AgentIdentityObjectId -ne $objectId) {
        Write-Caution "lab-settings.json records the object ID $($settings.AgentIdentityObjectId), but the agent now has $objectId."
    }

    Write-Section 'Its tools (latest version)'
    $rows = foreach ($t in @($latest.definition.tools)) {
        if (-not $t) { continue }
        if ($t.type -eq 'mcp') {
            $allowed = @(Get-ToolNames $t.allowed_tools)
            [pscustomobject]@{ Tool = $t.server_label; Kind = 'MCP server'; Connection = $t.project_connection_id; Approval = Format-Approval $t.require_approval
                               'Reaches' = $t.server_url; Scope = if ($allowed.Count) { "$($allowed.Count) allowed tools" } else { 'every tool the endpoint lists' } }
        }
        elseif ($t.type -eq 'azure_ai_search') {
            $ix = @($t.azure_ai_search.indexes) | Select-Object -First 1
            [pscustomobject]@{ Tool = 'Azure AI Search'; Kind = 'Knowledge'; Connection = ([string]$ix.project_connection_id).Split('/')[-1]; Approval = 'not used'
                               'Reaches' = $ix.index_name; Scope = $ix.query_type }
        }
        else { [pscustomobject]@{ Tool = $t.type; Kind = $t.type; Connection = ''; Approval = ''; 'Reaches' = ''; Scope = '' } }
    }
    $rows | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host

    Write-Section 'Which identity each hop of a Service Desk tool call uses'
    $mcpIdentity = if ($settings.McpBackendIdentityClientId) { "managed identity, client ID $($settings.McpBackendIdentityClientId)" } else { 'its user-assigned managed identity' }
    @(
        [pscustomobject]@{ Hop = '1. You'; Identity = "The technician who signs in to Microsoft Foundry ($(if ($settings.SeniorUser) { $settings.SeniorUser } else { 'Senior Technician' }))"; 'What it allows' = 'Chatting with the agent and approving each write' }
        [pscustomobject]@{ Hop = '2. The agent'; Identity = "Its own Entra Agent ID ($(if ($objectId) { "object ID $objectId" } else { 'none' }))"; 'What it allows' = 'Nothing by itself: it starts with no permissions. The MCP server records its ID in every log line' }
        [pscustomobject]@{ Hop = '3. The MCP connections'; Identity = "OAuth identity passthrough on $($settings.McpReadConnection) and $($settings.McpWriteConnection)"; 'What it allows' = 'Sends your own token, issued for the gateway, with each tool call' }
        [pscustomobject]@{ Hop = '4. API Management'; Identity = "Validates your token$(if ($settings.McpGatewayAudience) { " (audience $($settings.McpGatewayAudience))" })"; 'What it allows' = 'Passes on who you are and adds the correlation ID; refuses calls without a valid token' }
        [pscustomobject]@{ Hop = '5. MCP server'; Identity = "Container App $($settings.ContainerApp), $mcpIdentity"; 'What it allows' = 'Reads its backend key from Key Vault; is the Dataverse application user' }
        [pscustomobject]@{ Hop = '6. Dataverse'; Identity = 'Your user, through the application user acting on your behalf'; 'What it allows' = 'Only what both your security role and the application user''s role allow' }
    ) | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host
    Write-Host '  The Azure AI Search tool is different: it reads the index through the project connection ''search'' (Microsoft Entra ID), not through the Agent ID.'

    Write-Section 'See it in the Microsoft Entra admin center'
    Write-Host '  Open https://entra.microsoft.com and browse to Entra ID > Agents > Agent identities.'
    if ($objectId) { Write-Host "  Search for the object ID $objectId (searching by object ID is reliable; the display name Foundry gives the identity can vary)." }
    Write-Host '  Viewing agent identities needs no administrator role. The agent''s sign-in logs need the Reports Reader role, which lab accounts do not hold.'

    if ($PassThru) {
        return [pscustomobject]@{
            AgentName = $agent.name; AgentVersion = $latest.version; AgentIdObjectId = $objectId; AgentIdClientId = $clientId
            BlueprintClientId = $blueprint.client_id; Tools = @($rows)
        }
    }
}
catch {
    Write-Verbose ($_ | Out-String)
    Stop-Script $_.Exception.Message
}
