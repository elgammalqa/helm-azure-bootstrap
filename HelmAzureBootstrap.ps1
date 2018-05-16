param(
   [string] $root,
   [string] $chartDirectory,
   [switch] $secrets,
   [switch] $connect,
   [switch] $cleanUp
)

function FindSetting($line, $settingName)
{
    $regex = "$settingName" + ":(.*)"
    $search = [Regex]::Matches($line, $regex)
    if ($search.Success)
    {
        return $search.Groups[1].Value.Trim()
    }

    return $null
}

if (-Not $chartDirectory)
{
    $chartDirectory = $root
}
elseif (-Not [System.IO.Path]::IsPathRooted($chartDirectory))
{
    $chartDirectory = Join-Path $root $chartDirectory
}

$valuesFile = Join-Path $chartDirectory "values.yaml"
if (-Not (Test-Path $valuesFile))
{
    throw "Could not find values file at '$valuesFile'"
}

$valuesContent = Get-Content $valuesFile
$folder = $null
$subscriptionId = $null
$keyVaultName = $null
$base64EncodeStr = $null
$kubeConfigSecret = $null

Write-Host "Parsing '$valuesFile' for Helm bootstrap configuration values..." -ForegroundColor Green

# Parse values.yaml for files required by plugin.
foreach ($line in [System.IO.File]::ReadLines($valuesFile))
{
    if (!$folder)
    {
        $folder = FindSetting $line "folder"
    }

    if (!$subscriptionId)
    {
        $subscriptionId = FindSetting $line "subscriptionId"
    }

    if (!$keyVaultName)
    {
        $keyVaultName = FindSetting $line "keyVaultName"
    }

    if (!$kubeConfigSecret)
    {
        $kubeConfigSecret = FindSetting $line "kubeConfigSecret"
    }

    if (!$base64EncodeStr)
    {
        $base64EncodeStr = FindSetting $line "base64Encode"
        $base64Encode = $false
        if ($base64EncodeStr -eq "true")
        {
            $base64Encode = $true
        }
    }
}

if (!$folder)
{
    $folder =  "_templates"
}

if (!$subscriptionId)
{
    throw "Could not find value 'subcriptionId:{subIdValue}' in '$valuesFile'. Please add this configuration value."
}

if (!$keyVaultName)
{
    throw "Could not find value 'keyVaultName:{keyVaultName} in '$valuesFile'. Please add this configuration value."
}

Write-Host "Secrets templates folder: $folder" -ForegroundColor Cyan
Write-Host "Subscription id: $subscriptionId" -ForegroundColor Cyan
Write-Host "Key vault name: $keyVaultName" -ForegroundColor Cyan
Write-Host "Base64 encode: $base64Encode" -ForegroundColor Cyan
Write-Host "Kubeconfig secret name: $kubeConfigSecret" -ForegroundColor Cyan

$templatesInputFolder = Join-Path $chartDirectory $folder
$templatesOutputFolder = Join-Path $chartDirectory "templates"

if ($connect)
{
    . ${PSScriptRoot}\KubeConfigSetup.ps1 -keyVaultName $keyVaultName -kubeConfigSecretName $kubeConfigSecret -downloadKube
}

if ($secrets)
{
    Write-Host "Bootstrapping secrets..." -ForegroundColor Green
    $templates = Get-ChildItem -Recurse -Path $templatesInputFolder -Filter "*.yaml" | % { $_.FullName }
    foreach ($template in $templates)
    {
        $templateFileName = Split-Path $template -Leaf
        $outputFile = Join-Path $templatesOutputFolder $templateFileName
        . ${PSScriptRoot}\GenerateHelmSecretsTemplate.ps1 -keyVaultName $keyVaultName -secretsTemplateFile $template -secretsOutputFile $outputFile -subscriptionId $subscriptionId -useAZ $true -base64Encode $base64Encode
    }
}

if ($cleanUp)
{
    # Clean up generated secrets.
    $templates = Get-ChildItem -Recurse -Path $templatesInputFolder -Filter "*.yaml" | % { $_.FullName }
    foreach ($template in $templates)
    {
        $templateFileName = Split-Path $template -Leaf
        $outputFile = Join-Path $templatesOutputFolder $templateFileName
        if (Test-Path $outputFile)
        {
            Write-Host "Removed '$outputFile'"
            Remove-Item $outputFile
        }
    }

    # Clean up kubeconfig.
    . ${PSScriptRoot}\KubeConfigSetup.ps1 -keyVaultName $keyVaultName -kubeConfigSecretName $kubeConfigSecret -removeKube
}
