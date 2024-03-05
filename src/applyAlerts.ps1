Import-Module Az.Monitor -ErrorAction SilentlyContinue
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
        $actionGroup = Get-AzActionGroup -Name $actionGroupName -ResourceGroupName $resourceGroupName -ErrorAction Stop
    } catch {
        Write-Host "Action Group '$actionGroupName' not found. Creating..."
        $emailReceiver = @(
            @{
                name = "Primary Email";
                emailAddress = $email;
            }
        )
        $actionGroup = New-AzActionGroup -ResourceGroupName $resourceGroupName -Name $actionGroupName -ShortName ($actionGroupName.Substring(0, [math]::Min(12, $actionGroupName.Length))) -Location $global:location -EmailReceiver $emailReceiver -ErrorAction Stop
    }
    return $actionGroup.Id
}
# # Function to Fetch Resources
# function Get-ResourcesByType {
#     param ($Type)
#     # Fetch resources based on type (VM, SQL, etc.)
# }

# # Function to Apply Alert Rules
function Apply-AlertRules {
    param (
        $Resource,
        $AlertRules,
        $actionGroupId
    )
    foreach ($rule in $AlertRules) {
        # Implement logic to create/update alert rules using New-AzMetricAlertRule or similar
        Write-Host "Applying $($rule.name) to $($Resource.Name)"
    }
}



# Main Script Execution
$config = Load-Configuration -ConfigPath $global:configPath
Write-Host "Config: $config"
$actionGroupId = Ensure-ActionGroupExists -resourceGroupName $global:resourceGroupName -config $config

foreach ($resourceConfig in $config.resources) {
    $resources = Get-ResourcesByType -Type $resourceConfig.type
    foreach ($resource in $resources) {
        Apply-AlertRules -Resource $resource -AlertRules $resourceConfig.alertRules
    }
}
