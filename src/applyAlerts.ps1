Import-Module Az.Monitor -RequiredVersion 5.1.0
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
        [string]$Type
    )
    switch ($Type) {
        "VM" { Get-AzVM -ResourceGroupName $global:resourceGroupName }
        "SQL" {
            $servers = Get-AzSqlServer -ResourceGroupName $global:resourceGroupName
            foreach ($server in $servers) {
                Get-AzSqlDatabase -ResourceGroupName $global:resourceGroupName -ServerName $server.ServerName
            }
        }
        default { Write-Host "Unknown resource type: $Type"; return $null }
    }
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
function Apply-AlertRules {
    param (
        $Resource,
        $AlertRules,
        $actionGroupId
    )

    foreach ($rule in $AlertRules) {
        # Create criteria object
        $criteria = New-AzMetricAlertRuleV2Criteria -MetricName $rule.metricName -Operator $rule.operator -Threshold $rule.threshold -TimeAggregation $rule.timeAggregation

        # Create alert rule
        New-AzMetricAlertRuleV2 -Name $rule.name -ResourceGroupName $Resource.ResourceGroupName -WindowSize $rule.windowSize -Frequency $rule.frequency -TargetResourceId $Resource.Id -Criteria $criteria -ActionGroupId $actionGroupId -Severity $rule.severity -Description $rule.description

        Write-Host "Metric alert rule '$($rule.name)' applied to $($Resource.Id)"
    }
}

# Main Script Execution
$config = Load-Configuration -ConfigPath $global:configPath
Write-Host "Calling Ensure-ActionGroupExists with Resource Group: $global:resourceGroupName and Config: $config"
$actionGroupId = Ensure-ActionGroupExists -resourceGroupName $global:resourceGroupName -config $config
Write-Host "Returned from Ensure-ActionGroupExists with Action Group ID: $actionGroupId"

foreach ($resourceConfig in $config.resources) {
    $resources = Get-ResourcesByType -Type $resourceConfig.type
    Write-Host "Resources: $resources" # Debugging line
    foreach ($resource in $resources) {
        $alertRules = $resourceConfig.alertRules
        Write-Host "Resource: $resource" # Debugging line
        Write-Host "Alert Rules: $alertRules" # Debugging line
        Apply-AlertRules -Resource $resource -AlertRules $alertRules -actionGroupId $actionGroupId
    }
}