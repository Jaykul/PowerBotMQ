$PowerBotAdapters = "$PSScriptRoot\Adapters"
$PowerBotMQ = Resolve-Path $PSScriptRoot\PowerBotMQ.psm1
$UserRoles = Resolve-Path $PSScriptRoot\UserRoles.psm1

$GetAdapterNames = { (Get-ChildItem $PowerBotAdapters -File -Filter *.psm1 | Select -Expand BaseName) -replace "Adapter$" }

function Get-BotConfig {
    Import-Configuration
}

function Set-BotConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Specifies the objects to export as metadata structures.
        # Enter a variable that contains the objects or type a command or expression that gets the objects.
        # You can also pipe objects to Export-Metadata.
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $InputObject
    )
    process {
        $Path = Join-Path (Get-StoragePath) "Configuration.psd1"
        $InputObject | Export-Metadata $Path
    }
}

function Restart-BotAdapter {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            if(Get-ChildItem $PowerBotAdapters -File -Filter "${_}*.psm1") {
                return $true
            } else {
                throw ("Invalid AdapterName. Valid names are " + (&$GetAdapterNames -join ", "))
            }
        })]
        [string[]]$Name
    )
    begin {
        $Configuration = Import-Configuration
        $StoragePath = Get-StoragePath
    }

    process {
        foreach($Context in $Configuration.Keys) {
            foreach($Adapter in $Configuration.$Context.Keys) {
                foreach($FilterName in $Name) {
                    if(("${Context}-${Adapter}" -like $FilterName) -or ($FilterName -notmatch "-" -and "$Adapter" -like "${FilterName}")) {
                        foreach($AdapterFile in Get-ChildItem (Join-Path $PSScriptRoot\Adapters "${Adapter}Adapter.psm1")) {
                            Write-Verbose "Restarting ${Context}-${Adapter} from $AdapterFile"

                            if($Job = Get-Job "${Context}-${Adapter}" -ErrorAction Ignore) {
                                if($Job.State -notin "Stopped","Failed") {
                                    if($PSCmdlet.ShouldProcess( "Stopped the Job '${Context}-${Adapter}'",
                                                    "The '${Context}-${Adapter}' job is $($Job.State). Stop it?",
                                                    "Starting ${Context}-${Adapter} job" )) {
                                        $Job | Stop-Job
                                    }
                                }
                            }

                            $Config = $Configuration.$Context.$Adapter

                            Write-Verbose "Start-Job ${Context}-${Adapter}`n$AdapterFile`n$($Config|Out-String)"

                            Start-Job -Name "${Context}-${Adapter}" -ScriptBlock {
                                param($PSModulePath, $Context, $Config, $StoragePath, $Configuration, [Parameter(ValueFromRemainingArguments)][string[]]$Modules)
                                $Env:PSModulePath = $PSModulePath
                                $global:BotStoragePath = $StoragePath
                                $global:BotConfig = $Configuration
                                Import-Module $Modules
                                Start-Adapter -Context $Context @Config -Verbose
                            } -ArgumentList $Env:PSModulePath, $Context, $Config, $StoragePath, $Configuration, $PowerBotMQ, $UserRoles, $AdapterFile.FullName
                        }
                    }
                }
            }
        }
    }
}

Microsoft.PowerShell.Core\Register-ArgumentCompleter -Command Restart-BotAdapter -Parameter AdapterName -ScriptBlock $GetAdapterNames

function Start-PowerBot {
    Start-ZeroMqHub
    PowerBot\Restart-BotAdapter *
}

Import-Module $UserRoles