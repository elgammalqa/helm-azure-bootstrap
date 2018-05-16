<#
 .SYNOPSIS
    Generates the Helm secrets template file.
 .DESCRIPTION
    Generates the Helm secrets template file by retrieving values from configuration and Key Vault.
 .PARAMETER keyVaultName
    The name of the Azure key vault to read secrets from.
  .PARAMETER secretsTemplateFile
    The path to the secrets template file.
  .PARAMETER secretsOutputFile
    The path to generate the Helm secrets template file.
  .PARAMETER subscriptionId
    The Azure subscription id to log into if useAZ is true.
  .PARAMETER useAZ
    If set, use AZ CLI to fetch secret values.
  .PARAMETER base64Encode
    If set, base 64 encode templated string values.
#>

param(
    [parameter(Mandatory = $true)][string] $keyVaultName,
    [parameter(Mandatory = $true)][string] $secretsTemplateFile,
    [parameter(Mandatory = $true)][string] $secretsOutputFile,
    [string] $subscriptionId,
    [bool] $useAZ = $true,
    [bool] $base64Encode = $false
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

function GenerateAppSettingsSecret([string] $keyVaultName, [string]$secretsTemplateFile, [string]$secretsOutputFile, [bool]$base64Encode, [bool]$useAZ)
{
    $settingMap = @{}

    $content = Get-Content $secretsTemplateFile
    # Grab all templated (and non-templated) secrets values. Each is surrounded by a pair of '!'.
    $templateValues = ([Regex]::Matches($content, "!([^!]*)!")) | % { $_.Groups[1].Value }

    $replacements = @{}
    foreach ($templateValue in $templateValues)
    {
        # Fill out the templated value and encode in base64.
        $value = ReplaceTemplateValue -templateValue $templateValue -replacementMap $settingMap -keyVaultName $keyVaultName -base64Encode $base64Encode -useAZ $useAZ
        # Replace the entire quoted expression (and get rid of the '!').
        $replacements["!$templateValue!"] = $value
        Write-Host "Replaced ""$templateValue"" with $value"
    }

    $replacementText = ReplaceTxt -content (Get-Content $secretsTemplateFile) -replaceMap $replacements
    $replacementText | Set-Content $secretsOutputFile
    Write-Host "Generated secrets template at $secretsOutputFile" -ForegroundColor Green
}

. "${PSScriptRoot}\Utility.ps1"

if ($useAZ)
{
    # Within the RM context, we never use AZ CLI and we connect to Azure via Service Connections.
    AzLogin -subscriptionId $subscriptionId
}

GenerateAppSettingsSecret -keyVaultName $keyVaultName -secretsTemplateFile $secretsTemplateFile -secretsOutputFile $secretsOutputFile -base64Encode $base64Encode -useAZ $useAZ