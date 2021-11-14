# region parameters
param (
    [Parameter(Mandatory=$true)][string]$rootFolder,
    [Parameter(Mandatory=$true)][string[]]$modifiedInitiatives,
    [Parameter(Mandatory=$true)][string]$managementGroupName
)
#endregion

$azPD = Get-AzPolicyDefinition -ManagementGroupName $managementGroupName

foreach ($modifiedInitiative in $modifiedInitiatives) {

    $filePath = $rootFolder + "\Initiatives\" + $modifiedInitiative + ".json"

    Write-Host "##[debug] File path: $filePath"

    $azureInitiative = Get-Content $filePath | ConvertFrom-Json

    $initiativeName = $azureInitiative.Name + " v" + $azureInitiative.properties.metadata.version
    $initiativeDisplayName = $azureInitiative.properties.displayName + " v" + $azureInitiative.properties.metadata.version

    <#
     logic for gated versioning of inititves, disabled 2/2/2021 by Dami & Adam
     manual version in properties.metadata.version will provide version feature if required

    $id = Get-AzPolicyDefinition -Name $initiativeName `
                                    -ManagementGroupName $managementGroupName `
                                    -ErrorAction SilentlyContinue

    if ($id.Properties.metadata.version -eq $azureInitiative.properties.metadata.version) {
        Write-Host "    ##[error] Version colision detected, commit needs to be reviewed"
        throw
    }
    else {
        Write-Host "    ##[debug] No version colision detected"
    }
    #>

    Write-Host "##[debug] Policy $($azurePolicy.properties.displayName)"

    $policyDefinitions = @()

    foreach ($policy in $azureInitiative.properties.PolicyDefinitions) {

        Write-Host "##[section] Processing $($policy.policyDefinitionName)"

        $policyLookup = $azPD | Where-Object {$_.Name -eq $policy.policyDefinitionName}

        if($policyLookup){
            Write-Host "##[debug] Policy found setting policyID"

            $policyLookup.ResourceId
        }
        else {
            Write-Host "##[error] Policy not found"

            throw
        }

        $pd = @{}

        $pd.policyDefinitionId = $policyLookup.ResourceId
        $pd.parameters = $policy.parameters
        $pd.policyDefinitionReferenceId = $policy.policyDefinitionReferenceId
        $pd.groupNames = $policy.groupNames

        $pd

        $policyDefinitions += $pd
    }

    $createInititative = @{}

    $createInititative = @{
        "Name" = $initiativeName
        "DisplayName" = $initiativeDisplayName
        "Description" = $azureInitiative.properties.description
        "Metadata" = ($azureInitiative.properties.metadata | ConvertTo-Json -Depth 100)
        "Parameter" = ($azureInitiative.properties.parameters | ConvertTo-Json -Depth 100)
        "PolicyDefinition" = ($policyDefinitions | ConvertTo-Json -Depth 100 -AsArray)
    }

    if((Get-AzSubscription).Count -gt 1) {
        Write-Host "##[debug] Adding Management Group to object..."

        $mgObject = @{"ManagementGroupName" = $managementGroupName}
        
        $createInititative += $mgObject
    }

    if(($azureInitiative.properties.policyDefinitionGroups).Count -gt 0) {
        Write-Host "##[debug] Adding Group Definition to object..."

        $gdObject = @{"GroupDefinition" = $azureInitiative.properties.policyDefinitionGroups | ConvertTo-Json -Depth 100 -AsArray}
        
        $createInititative += $gdObject
    }

    $initiativeName = $createInititative.Name

    Write-Host "##[debug] The following initiative is being created/updated:"

    Write-Host ($createInititative | Out-String)

    New-AzPolicySetDefinition @createInititative

    Write-Host "##[debug] Policy definition for $initiativeName was created/updated..."

}