#region parameters
param (
    [Parameter(Mandatory=$true)][string]$policyDefRootFolder,
    [Parameter(Mandatory=$true)][string[]]$modifiedPolicies,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$policyMG,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$deployMG,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$deploySub

)
#endregion

#region variables
# PolicyDef class is used to store hash table of policy varaiables
class PolicyDef {
    [string]$PolicyName
    [string]$PolicyDisplayName
    [string]$PolicyDescription
    [string]$PolicyMode
    [string]$PolicyMetadata
    [string]$PolicyRule
    [string]$PolicyParameters
}
#endregion

#region select policy function
function Select-Policies {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)][string[]]$modifiedPolicies,
        [Parameter(Mandatory = $true)][string]$managementGroupName
    )

    $policyList = @()

    foreach ($modifiedPolicy in $modifiedPolicies) {

        $filePath = $policyDefRootFolder + $modifiedPolicy + "azurepolicy.json"

        Write-Host "##[debug] Evaluating file path: $filePath"

        $policyJson = Get-Content $filePath | ConvertFrom-Json

        $policyName = $policyJson.Name + " v" + $policyJson.properties.metadata.version
        $policyDisplayName = $policyJson.properties.displayName + " v" + $policyJson.properties.metadata.version

        $pd = Get-AzPolicyDefinition -Name $policyName `
                                     -ManagementGroupName $managementGroupName `
                                     -ErrorAction SilentlyContinue

        if ($pd.Properties.metadata.version -eq $policyJson.properties.metadata) {
            Write-Host "    ##[error] Version colision detected, commit needs to be reviewed"
            throw
        }
        else {
            Write-Host "    ##[debug] No version colision detected"
        }


        #declare new policyDef object
        $policy = New-Object -TypeName PolicyDef

        #set variables
        $policy.PolicyName = $policyName
        $policy.PolicyDisplayName = $policyDisplayName
        $policy.PolicyDescription = $policyJson.properties.description
        $policy.PolicyMode = $policyJson.properties.mode
        $policy.PolicyMetadata = $policyJson.properties.metadata | ConvertTo-Json -Depth 100
        $policy.PolicyRule = $policyJson.properties.policyRule | ConvertTo-Json -Depth 100
        $policy.PolicyParameters = $policyJson.properties.parameters | ConvertTo-Json -Depth 100
        $policyList += $policy
    }

    return $policyList
}
#endregion

#region add policy function
function Add-Policies {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)][PolicyDef[]]$policies,
        [Parameter(Mandatory = $false)][String]$managementGroupName,
        [Parameter(Mandatory = $false)][String]$subscriptionId
    )

    $policyDefList = @()
    foreach ($policy in $Policies) {

        $createPolicy = @{
            "Name" = $policy.PolicyName
            "Policy" = $policy.PolicyRule
            "Parameter" = $policy.PolicyParameters
            "DisplayName" = $policy.PolicyDisplayName
            "Description" = $policy.PolicyDescription
            "Metadata" = $policy.PolicyMetadata
        }

        Write-Host "    ##[debug] Checking deployment scope configuration..."

        if (($managementGroupName) -and ($subscriptionId)) {
            Write-Host "            ##[error] Configuration Error, DeployMG and DeploySub cannot both be populated"
            throw
        }

        Write-Host "    ##[debug] Formatting list of policy folders..."

        if ($managementGroupName) {
            Write-Host "        ##[debug] Setting ManagementGroupName: $managementGroupName"

            $mgObject = @{"ManagementGroupName" = $managementGroupName}
            
            $createPolicy += $mgObject
        }
        elseif ($subscriptionId) {
            Write-Host "        ##[debug] Setting SubscriptionID Name: $subscriptionId"

            $subObject = @{"SubscriptionId" = $subscriptionId}
            
            $createPolicy += $subObject
        }

        $policyName = $createPolicy.DisplayName

        Write-Host "    ##[debug] Processing policy definition for $policyName"

        $policyDef = New-AzPolicyDefinition @createPolicy

        $policyDefList += $policyDef
    }
    return $policyDefList
}
#endregion

Write-Host "##[section]Checking deployment scope configuration..."

#get list of policy folders
$policies = Select-Policies -modifiedPolicies $modifiedPolicies `
                            -managementGroupName $policyMG

Write-Host "##[debug] Names:" $policies.PolicyName
Write-Host "##[debug] Count:" $policies.count

Write-Host "##[section]Executing create policy..."

$policyDefinitions = Add-Policies -Policies $policies `
                                  -ManagementGroupName $deployMG `
                                  -SubscriptionId $deploySub
#endregion