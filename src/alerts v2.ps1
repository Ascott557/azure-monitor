Import-Module Az.Monitor -Force
# Global Variables
$global:resourceGroupName = "Andre-AzureMonitor"
$global:workspaceName = "amworkspace"
$global:configPath = ".\src\alertConfig.json"
$global:location = "northeurope"


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
        [string]$ResourceType,
        [string]$ResourceGroupName
    )

    $resources = @()

    switch ($ResourceType) {
        "VM" {
            $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
            foreach ($vm in $vms) {
                $resources += $vm.Id
            }
        }
        "SQL" {
            $servers = Get-AzSqlServer -ResourceGroupName $ResourceGroupName
            foreach ($server in $servers) {
                # Add the server's resource ID
                $resources += $server.ResourceId

                # Correctly fetch and add the databases' resource IDs
                $databases = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $server.ServerName
                foreach ($database in $databases) {
                    # Ensure the subscription ID is correctly included
                    $dbResourceId = $database.ResourceId
                    $resources += $dbResourceId
                }
            }
        }
    }

    foreach ($resource in $resources) {
        Write-Host "Retrieved resource ID: $resource"
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
function Convert-ISO8601ToTimeSpan {
    param (
        [string]$Duration
    )
    $isoPattern = 'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?'
    $simplePattern = '^(\d+)([hms])$'

    if ($Duration -match $isoPattern) {
        $hours = [int]$matches[1]
        $minutes = [int]$matches[2]
        $seconds = [int]$matches[3]
        return New-TimeSpan -Hours $hours -Minutes $minutes -Seconds $seconds
    } elseif ($Duration -match $simplePattern) {
        switch ($matches[2]) {
            'h' { return New-TimeSpan -Hours $matches[1] }
            'm' { return New-TimeSpan -Minutes $matches[1] }
            's' { return New-TimeSpan -Seconds $matches[1] }
        }
    } else {
        throw "Invalid duration format: $Duration"
    }
}

function Create-Condition {
    param (
        [PSCustomObject]$rule
    )

    Write-Host "Operator: $($rule.operator)"

    # Create dimension object if your rule requires it
    $dimension = $null
    if ($rule.dimensions) {
        $dimension = New-AzScheduledQueryRuleDimensionObject -Name $rule.dimensions.name `
            -Operator $rule.dimensions.operator -Value $rule.dimensions.value
    }

    # Create condition object
    $condition = New-AzScheduledQueryRuleConditionObject -Query $rule.query `
        -TimeAggregation $rule.timeAggregation -MetricMeasureColumn $rule.metricMeasureColumn `
        -Operator $rule.operator -Threshold $rule.threshold `
        -FailingPeriodNumberOfEvaluationPeriod $rule.failingPeriodNumberOfEvaluationPeriod `
        -FailingPeriodMinFailingPeriodsToAlert $rule.failingPeriodMinFailingPeriodsToAlert

    if ($dimension) {
        $condition.Dimension = @($dimension)
    }

    return $condition
}

Import-Module Az.Monitor

# Assuming $resources holds the returned IDs from Get-ResourcesByType
$validResourceIds = $resources.Where({ $_ -ne '' })

foreach ($resourceId in $validResourceIds) {
    Write-Host "Valid Resource ID for Scope: $resourceId"
}

function Apply-AlertRules {
    param (
        $Resource,
        $AlertRules,
        $actionGroupId
    )

    foreach ($rule in $AlertRules) {
        try {
            if ($rule.query) {
                $evaluationFrequency = Convert-ISO8601ToTimeSpan -Duration $rule.evaluationFrequency
                $windowSize = Convert-ISO8601ToTimeSpan -Duration $rule.windowSize
                $condition = Create-Condition -rule $rule

                # Create scheduled query rule with CriterionAllOf
                Write-Host "Severity: $($rule.severity)" 
                Write-Host "Rule: $($rule.name), Severity: $($rule.severity)" 
                Write-Host "EvaluationFrequency: $($evaluationFrequency.TotalMinutes)"  
                Write-Host "ThresholdOperator: $($condition.ThresholdOperator)"            
                New-AzScheduledQueryRule -ResourceGroupName $global:resourceGroupName `
                    -Location $global:location -Name $rule.name -Description $rule.description `
                    -Enabled:$true -Scope $validResourceIds -CriterionAllOf @($condition) `
                    -ActionGroupResourceId @($actionGroupId) -Severity $rule.severity `
                    -WindowSize $windowSize -EvaluationFrequency $evaluationFrequency `
                    -DisplayName $rule.name

                Write-Host "Created query-based alert rule: $($rule.name)"
            }
        } catch {
            Write-Host "Error applying rule $($rule.name): $_"
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