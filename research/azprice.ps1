# Helper for the Azure Retail Prices API (public, no auth).
# Usage: . .\azprice.ps1 ; Get-AzPrice -Filter "..." -OutName "vm" [-Currency USD]
# Raw API responses are saved next to the research notes, where the cost estimate cites them.
$Global:AzPriceDir = Join-Path $PSScriptRoot 'pricing-raw-swedencentral'

function Get-AzPrice {
    param(
        [Parameter(Mandatory)] [string] $Filter,
        [string] $OutName,
        [string] $Currency = 'USD',
        [string] $ApiVersion = '2023-01-01-preview',
        [int] $MaxPages = 50
    )
    $base = 'https://prices.azure.com/api/retail/prices'
    $enc = [uri]::EscapeDataString($Filter)
    $url = "$($base)?api-version=$ApiVersion&currencyCode='$Currency'&`$filter=$enc"
    $all = New-Object System.Collections.Generic.List[object]
    $pages = 0
    while ($url -and $pages -lt $MaxPages) {
        $resp = Invoke-RestMethod -Uri $url -Method Get
        foreach ($i in $resp.Items) { $all.Add($i) }
        $url = $resp.NextPageLink
        $pages++
    }
    if ($OutName) {
        $obj = [ordered]@{
            retrievedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            api          = $base
            apiVersion   = $ApiVersion
            currencyCode = $Currency
            filter       = $Filter
            pages        = $pages
            count        = $all.Count
            Items        = $all
        }
        $path = Join-Path $Global:AzPriceDir ("pricing-raw-$OutName.json")
        $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8
    }
    return $all
}

function Show-AzPrice {
    param([Parameter(ValueFromPipeline)] $InputObject, [switch] $NoSort)
    begin { $rows = @() }
    process { $rows += $InputObject }
    end {
        if (-not $NoSort) { $rows = $rows | Sort-Object armRegionName, productName, skuName, meterName, tierMinimumUnits }
        foreach ($x in $rows) {
            $eff = ''
            if ($x.effectiveStartDate) { $eff = ([datetime]$x.effectiveStartDate).ToString('yyyy-MM-dd') }
            '{0} | {1} | {2} | {3} | {4} | {5} | {6} | tierMin={7} | {8} | eff={9} | primary={10} | armSku={11}' -f `
                $x.armRegionName, $x.serviceName, $x.productName, $x.skuName, $x.meterName, $x.unitOfMeasure, `
                ([decimal]$x.retailPrice).ToString(), $x.tierMinimumUnits, $x.type, $eff, $x.isPrimaryMeterRegion, $x.armSkuName
        }
    }
}
