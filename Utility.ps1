function AzLogin([string]$subscriptionId)
{
    Try
    {
        Write-Verbose "az account set -s $subscriptionId"
        az account set -s $subscriptionId
    }
    Catch
    {
        Write-Host "Failed to set operation context to subscription '$subscriptionId'. Please try to log in again..." -ForegroundColor Red
    }
}

function GetSecret([string]$secretName, [string]$keyVaultName, [bool]$useAZ, [bool]$silent = $false)
{
    if ($useAZ)
    {
        $secret = $(az keyvault secret show --vault-name $keyVaultName -n $secretName | ConvertFrom-Json).value
    }
    else
    {
        $secret = $(Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $secretName).SecretValueText
    }

    if ($secret -eq $null -And -Not $silent)
    {
        Write-Host "Secret '$secretName' does not exist in keyvault '$keyVaultName'" -Foreground red
        Write-Host "Error: $_" -Foreground red
        throw
    }

    return $secret
}

# Replaces a templated value with the real value encoded in base64.
#
# An example value for replacing from the specified Key Vault:
# [kv=Config-CodeSmartsAzureClientId]
#
# An example value for replacing from content of a local template file:
# [path=GenevaLogger\\genevaFiles\\fluentd.conf.tmpl]
# Note: The provided path is a relative path from the Deployment directory
#
# An example value for replacing from the replacement map:
# [projectCodeName]-[env]-cluster-[instanceNames.resourceInstanceName]-containers
function ReplaceTemplateValue([string]$template,[string]$templateValue, [string]$keyVaultName, $replacementMap, [bool]$useAZ=$true, [bool]$base64Encode=$true)
{
   $value = $templateValue
   $start = 0
   while(($start -lt $value.length) -and ($value.IndexOf("[", $start) -ge 0))
   {
       $start = $value.IndexOf("[")
       $end = $value.IndexOf("]") + 1
       if($end -lt $start)
       {
           break;
       }
       $replaceValue = $value.SubString($start, $end-$start)
       if ($replaceValue.StartsWith("[kv=") -or $replaceValue.StartsWith("[kvb64="))
       {
           $s = $replaceValue.IndexOf("=") + 1
           $e = $replaceValue.length - 1
           $secretName = $replaceValue.SubString($s, $e - $s)
           $replacement = GetSecret -secretName "$secretName" -keyVaultName $keyvaultName -useAZ $useAZ
           $value = $value.Replace($replaceValue, "$replacement")

           if ($replaceValue.StartsWith("[kvb64="))
           {
               $value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
           }
       }
       elseif ($replaceValue.StartsWith("[path="))
       {
           $deploymentRoot = "${PSScriptRoot}\..\"
           $s = $replaceValue.IndexOf("=") + 1
           $e = $replaceValue.length - 1
           $path = "${PSScriptRoot}\..\" + $replaceValue.SubString($s, $e - $s)
           $fileContent = ((Get-Content $path) -join "\r\n").Replace("`"", "\`"") + "\r\n";
           $replacement = ReplaceTxt -content $fileContent -replaceMap $replacementMap
           $value ="$value".replace($replaceValue, "`"$replacement`"")
           break;
       }
       else
       {
           $replacement = $replacementMap[$replaceValue]
           $value ="$value".replace($replaceValue, $replacement)
       }
       $start = $start + $replacement.length
   }

   if ($base64Encode)
   {
       $value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
   }

   return $value
}

function ReplaceTxt($content, $replaceMap)
{
    $newContent = $content
    foreach ($replaceTxt in $replaceMap.Keys)
    {
       $newContent = $newContent.replace($replaceTxt, $replaceMap.$replaceTxt)
    }
    return $newContent
}

function PropertyExists($obj, $property)
{
    return ($obj.PSobject.Properties | % {$_.Name}) -Contains $property
}