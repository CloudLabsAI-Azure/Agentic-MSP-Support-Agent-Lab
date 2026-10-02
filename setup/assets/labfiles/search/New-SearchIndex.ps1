#Requires -Version 7.0
<#
.SYNOPSIS
    Creates (or updates) the servicedesk-knowledge index on your Azure AI Search service from
    C:\LabFiles\search\index-definition.json, and shows its fields.

.DESCRIPTION
    Sends the index definition to the search service with your own Azure CLI sign-in (you hold
    the Search Service Contributor role on it). Running it again updates the index in place.
    Run 'az login' first.

.EXAMPLE
    C:\LabFiles\search\New-SearchIndex.ps1
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\team-settings.json',
    [string]$DefinitionPath = 'C:\LabFiles\search\index-definition.json'
)

$ErrorActionPreference = 'Stop'
$settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
$definition = Get-Content $DefinitionPath -Raw | ConvertFrom-Json
$token = az account get-access-token --resource 'https://search.azure.com' --query accessToken --output tsv 2>$null
if (-not $token) { throw "Run 'az login' first." }
$index = Invoke-RestMethod -Method Put -Uri "$($settings.SearchEndpoint)/indexes/$($definition.name)?api-version=2024-07-01" `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -InFile $DefinitionPath
Write-Host "Index '$($index.name)' is ready on $($settings.SearchService) with $($index.fields.Count) fields." -ForegroundColor Green
$index.fields | ForEach-Object {
    [pscustomobject]@{
        Field = $_.name; Type = $_.type; Key = [bool]$_.key; Searchable = [bool]$_.searchable
        Filterable = [bool]$_.filterable; Retrievable = ($_.retrievable -ne $false)
    }
} | Format-Table -AutoSize
