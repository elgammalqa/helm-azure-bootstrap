<#
 .SYNOPSIS
    Downloads a kubeconfig from Key Vault and sets it as cluster connection context in the RM. 
 .DESCRIPTION
    Downloads a kubeconfig from Key Vault and sets it as cluster connection context in the RM.
  .PARAMETER keyVaultName
    The name of the Key Vault the kubeconfig secret resides in
  .PARAMETER kubeConfigSecretName
    The name of the kubeconfig secret
  .PARAMETER useAZ
    Whether or not to download the kubeconfig secret with AZ CLI vs. Azure Powershell
  .PARAMETER downloadKube
    The switch to set up the kubeconfig as the current cluster connection context
  .PARAMETER removeKube
    The switch to clean up the kubeconfig retrieved via --setKube
#>
param(
    [string] $keyVaultName,
    [parameter(Mandatory = $true)][string] $kubeConfigSecretName,
    [bool] $useAZ = $true,
    [switch] $downloadKube,
    [switch] $removeKube
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction']='Stop'

. "${PSScriptRoot}\Utility.ps1"

function SetKubeConfig($keyVaultName, $kubeConfigSecretName, $useAZ)
{
    $outputFile = "${PSScriptRoot}\$kubeConfigSecretName.kubeconfig"
    Write-Host "Downloading kubeconfig from secret '$kubeConfigSecretName' in Key Vault '$keyVaultName'..." -Foreground Green
    $encodedConfig = GetSecret -secretName $kubeConfigSecretName -keyvaultName $keyVaultName -useAZ $useAZ
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedConfig)) | Set-Content $outputFile
    Write-Host "Generated kubeconfig at '$outputFile'"
    Write-Host "##vso[task.setvariable variable=kubeconfig]$outputFile" 
}

function CleanUpKubeConfig($kubeConfigSecretName)
{
    if (Test-Path "${PSScriptRoot}\$kubeConfigSecretName.kubeconfig")
    {
        Remove-Item ${PSScriptRoot}\$kubeConfigSecretName.kubeconfig
        Write-Host "Removed kubeconfig '$kubeConfigSecretName.kubeconfig' at '${PSScriptRoot}'"
    }
}

if ($downloadKube)
{
    SetKubeConfig -keyVaultName $keyVaultName -kubeConfigSecretName $kubeConfigSecretName -useAZ $useAZ
}

if ($removeKube)
{
    CleanUpKubeConfig -kubeConfigSecretName $kubeConfigSecretName
}