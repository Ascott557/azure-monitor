Import-Module Az.Monitor -Force
# Global Variables
$global:resourceGroupName = "Andre-AzureMonitor"
$global:workspaceName = "amworkspace"
$global:configPath = ".\src\alertConfig.json"
$global:location = "global"


# Function to Load Configuration from JSON
function Load-Configuration {
    param (
        [string]$ConfigPath
    )
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    Write-Host "Loaded configuration: $config"
    return $config
}
function Get-ResourcesByType {
    param (
        $ResourceType,
        $ResourceGroupName
    )

    $resources = @()

    switch ($ResourceType) {
        "VM" {
            $resources += Get-AzVM -ResourceGroupName $ResourceGroupName
        }
        "SQL" {
            # Get all SQL servers in the resource group
            $servers = Get-AzSqlServer -ResourceGroupName $ResourceGroupName
            # For each server, get all databases and add them to the resources
            foreach ($server in $servers) {
                $resources += Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $server.ServerName
            }
        }
        # Add more resource types as needed
    }

    # Print out the resources for debugging
    Write-Host "Resources of type ${ResourceType}:"
    foreach ($resource in $resources) {
        Write-Host "Name: $($resource.Name), Id: $($resource.Id)"
    }

    return $resources
}


# Function to Ensure Action Group Exists
function Ensure-ActionGroupExists {
    param (
        [string]$resourceGroupName,
        [pscustomobject]$config
    )
    $actionGroupName = $config.actionGroupName
    $email = $config.email
    # Create an IEmailReceiver object for each email address
    $emailReceiver = New-AzActionGroupReceiver -Name "Primary Email" -EmailAddress $email
    # Existing logic to check and create action group
    try {
        $actionGroup = Get-AzActionGroup -Name $actionGroupName -ResourceGroupName $resourceGroupName -ErrorAction Stop -Verbose
    } catch {
        Write-Host "Action Group '$actionGroupName' not found. Creating..."
        $emailReceiver = @(
            @{
                name = "Primary Email";
                emailAddress = $email;
            }
        )
        Write-Host "Resource Group Name: $resourceGroupName" # Debugging line
        Write-Host "Action Group Name: $actionGroupName" # Debugging line
        Write-Host "Email Receiver: $emailReceiver" # 
        $actionGroup = New-AzActionGroup -ResourceGroupName $resourceGroupName -Name $actionGroupName -ShortName ($actionGroupName.Substring(0, [math]::Min(12, $actionGroupName.Length))) -Location $global:location -EmailReceiver $emailReceiver -Enabled -ErrorAction Stop -Verbose
        Write-Host "Action Group ID: $($actionGroup.Id)" # Debugging line

    }
    return $actionGroup.Id
}
# # Function to Fetch Resources
# function Get-ResourcesByType {
#     param ($Type)
#     # Fetch resources based on type (VM, SQL, etc.)
# }
# Function to Apply Alert Rules

# Import the module
Import-Module Az.Monitor

function Apply-AlertRules {
    param (
        $Resource,
        $AlertRules,
        $actionGroupId
    )

    foreach ($rule in $AlertRules) {
        # Check if evaluationFrequency is not null
        if ($null -eq $rule.evaluationFrequency) {
            Write-Host "Evaluation frequency for rule $($rule.name) is null. Skipping this rule."
            continue
        }

        # Create criteria object
        $criteria = New-AzMetricAlertRuleV2Criteria -MetricName $rule.metricName -Operator $rule.operator -Threshold $rule.threshold -TimeAggregation $rule.timeAggregation

        # Convert windowSize and evaluationFrequency to TimeSpan
        $windowSize = New-TimeSpan -Minutes ([int]$rule.windowSize.TrimEnd('m'))
        $evaluationFrequency = New-TimeSpan -Minutes ([int]$rule.evaluationFrequency.TrimEnd('m'))

        # Create alert rule
        if (![string]::IsNullOrEmpty($Resource.Id)) {
            Add-AzMetricAlertRuleV2 -Name $rule.name -ResourceGroupName $Resource.ResourceGroupName -WindowSize $windowSize -Frequency $evaluationFrequency -TargetResourceId $Resource.Id -Criteria $criteria -ActionGroupId $actionGroupId -Severity $rule.severity -Description $rule.description
            Write-Host "Metric alert rule '$($rule.name)' applied to $($Resource.Id)"
        } else {
            throw "Resource Id for rule '$($rule.name)' is null or empty."
        }
    }
}
# Main Script Execution
$config = Load-Configuration -ConfigPath $global:configPath
Write-Host "Loaded configuration: $($config | ConvertTo-Json -Depth 5)"
Write-Host "Calling Ensure-ActionGroupExists with Resource Group: $global:resourceGroupName and Config: $config"
$actionGroupId = Ensure-ActionGroupExists -resourceGroupName $global:resourceGroupName -config $config
Write-Host "Returned from Ensure-ActionGroupExists with Action Group ID: $actionGroupId"

foreach ($resourceConfig in $config.resources) {
    $resources = Get-ResourcesByType -ResourceType $resourceConfig.type -ResourceGroupName $global:resourceGroupName
    Write-Host "Resources: $resources" # Debugging line
    foreach ($resource in $resources) {
        $alertRules = $resourceConfig.alertRules
        Write-Host "Resource: $resource" # Debugging line
        Write-Host "Alert Rules: $alertRules" # Debugging line
        Apply-AlertRules -Resource $resource -AlertRules $alertRules -actionGroupId $actionGroupId
    }
}