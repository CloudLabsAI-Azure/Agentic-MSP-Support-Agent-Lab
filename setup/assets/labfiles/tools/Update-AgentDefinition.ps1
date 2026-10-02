#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a new version of your Foundry agent with the lab's instructions and tools.

.DESCRIPTION
    -Knowledge  Exercise 1: instructions from C:\LabFiles\agent\instructions-ex1.md and the
                Azure AI Search tool on index servicedesk-knowledge (query type
                vector_semantic_hybrid, 10 results). Uses the Azure AI Search connection you
                created in the Foundry portal; creates 'servicedesk-search' (Microsoft Entra ID,
                keyless) only if the project has none for your search service.
    -Tools      Fallback for Exercise 3, if the portal does not offer the MCP tool options in
                the guide: instructions from instructions-ex3.md, the Azure AI Search tool, and
                the Service Desk MCP tool behind API Management. Reuses a RemoteTool connection
                to your gateway if one exists, otherwise creates 'servicedesk-mcp' with
                authentication by the agent identity and audience = the MCP gateway audience.

    A new version replaces the tool list of the previous one, so always pass the switch for
    the exercise you are in. The agent's endpoint serves the latest version.
    Uses your own Azure CLI sign-in: run 'az login' first.
#>
[CmdletBinding()]
param(
    [switch]$Knowledge,
    [switch]$Tools,
    [string]$SettingsPath = 'C:\LabFiles\team-settings.json'
)

$ErrorActionPreference = 'Stop'
if (-not ($Knowledge -or $Tools)) { throw 'Pass -Knowledge (Exercise 1) or -Tools (Exercise 3 fallback).' }
$s = Get-Content $SettingsPath -Raw | ConvertFrom-Json
$project = "/subscriptions/$($s.SubscriptionId)/resourceGroups/$($s.ResourceGroup)/providers/Microsoft.CognitiveServices/accounts/$($s.FoundryResource)/projects/$($s.FoundryProject)"

function Find-Connection([string]$category, [string]$target) {
    $list = az rest --method get --uri "https://management.azure.com$project/connections?api-version=2025-06-01" | ConvertFrom-Json
    if ($LASTEXITCODE) { throw "Could not list the project connections. Run 'az login' and try again." }
    return $list.value | Where-Object {
        $_.properties.category -eq $category -and "$($_.properties.target)".TrimEnd('/') -eq $target.TrimEnd('/')
    } | Select-Object -First 1
}

function New-Connection([string]$name, [hashtable]$properties, [string]$apiVersion) {
    $file = New-TemporaryFile
    try {
        @{ properties = $properties } | ConvertTo-Json -Depth 10 | Set-Content $file -Encoding utf8
        az rest --method put --uri "https://management.azure.com$project/connections/$($name)?api-version=$apiVersion" --body "@$file" --output none
        if ($LASTEXITCODE) { throw "Creating connection $name failed" }
    }
    finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    Write-Host "Created project connection '$name'." -ForegroundColor DarkGray
    return @{ name = $name; id = "$project/connections/$name" }
}

$toolDefs = @()
$search = Find-Connection 'CognitiveSearch' $s.SearchEndpoint
$search = if ($search) {
    Write-Host "Using the Azure AI Search connection '$($search.name)'." -ForegroundColor DarkGray
    @{ name = $search.name; id = $search.id }
} else {
    New-Connection 'servicedesk-search' @{ category = 'CognitiveSearch'; target = $s.SearchEndpoint; authType = 'AAD' } '2025-06-01'
}
$toolDefs += @{ type = 'azure_ai_search'; azure_ai_search = @{ indexes = @(@{
    project_connection_id = $search.id; index_name = $s.SearchIndex; query_type = 'vector_semantic_hybrid'; top_k = 10 }) } }

if ($Tools) {
    $mcp = Find-Connection 'RemoteTool' $s.McpGatewayUrl
    $mcpName = if ($mcp) {
        Write-Host "Using the MCP connection '$($mcp.name)'." -ForegroundColor DarkGray
        $mcp.name
    } else {
        (New-Connection 'servicedesk-mcp' @{ category = 'RemoteTool'; target = $s.McpGatewayUrl; authType = 'AgenticIdentityToken'
            audience = $s.McpGatewayAudience; isSharedToAll = $true; metadata = @{ ApiType = 'Azure' } } '2025-10-01-preview').name
    }
    $toolDefs += @{ type = 'mcp'; server_label = 'servicedesk'; server_url = $s.McpGatewayUrl
        project_connection_id = $mcpName; require_approval = 'always' }
}

$instructionsFile = if ($Tools) { 'C:\LabFiles\agent\instructions-ex3.md' } else { 'C:\LabFiles\agent\instructions-ex1.md' }
$body = @{ definition = @{ kind = 'prompt'; model = $s.ChatDeployment; instructions = (Get-Content $instructionsFile -Raw); tools = $toolDefs } } |
    ConvertTo-Json -Depth 12
$token = az account get-access-token --resource 'https://ai.azure.com' --query accessToken --output tsv
if (-not $token) { throw "Run 'az login' first." }
$version = Invoke-RestMethod -Method Post -Uri "$($s.FoundryProjectEndpoint)/agents/$($s.AgentName)/versions?api-version=v1" `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
Write-Host ("Created version {0} of {1} with tools: {2}." -f $version.version, $s.AgentName, (($toolDefs | ForEach-Object type) -join ', ')) -ForegroundColor Green
