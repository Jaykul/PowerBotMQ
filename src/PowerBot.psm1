Start-ZeroMqHub -Verbose
$PowerBotAdapters = "$PSScriptRoot\Adapters"
$PowerBotMQ = Resolve-Path $PSScriptRoot\PowerBotMQ.psm1

$GetAdapterNames = { (Get-ChildItem $PowerBotAdapters -File -Filter *.psm1 | Select -Expand BaseName) -replace "Adapter$" }

function Get-PowerBotConfiguration {
    Import-Configuration
}

function Set-PowerBotConfiguration {
    [CmdletBinding()]
    param(
        # Specifies the objects to export as metadata structures.
        # Enter a variable that contains the objects or type a command or expression that gets the objects.
        # You can also pipe objects to Export-Metadata.
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $InputObject
    )
    process {
        $Path = Get-StoragePath
        $InputObject | Export-Configuration $Path
    }
}

function Restart-Adapter {
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
    }

    process {
        foreach($Context in $Configuration.Keys) {
            foreach($Adapter in $Configuration.$Context.Keys) {
                foreach($FilterName in $Name) {
                    if(("${Context}-${Adapter}" -like $FilterName) -or ($FilterName -notmatch "-" -and "$Adapter" -like "${FilterName}")) {

                        foreach($AdapterFile in Get-ChildItem (Join-Path $PSScriptRoot\Adapters "${Adapter}Adapter.psm1")) {

                            $Job = Get-Job "${Context}-${Adapter}" -ErrorAction SilentlyContinue -ErrorVariable ObjectNotFound
                            if($ObjectNotFound -and $ObjectNotFound[0].CategoryInfo.Category -ne "ObjectNotFound") {
                                throw $ObjectNotFound[0]
                            }
                            if($Job.State -notin "Stopped","Failed") {
                                if($PSCmdlet.ShouldProcess( "Stopped the Job '${Context}-${Adapter}'",
                                                   "The '${Context}-${Adapter}' job is $($Job.State). Stop it?",
                                                   "Starting ${Context}-${Adapter} job" )) {
                                    $Job | Stop-Job
                                }
                            }

                            $Config = $Configuration.$Context.$Adapter

                            Write-Verbose "Start-Job ${Context}-${Adapter}`n$AdapterFile`n$($Config|Out-String)"

                            Start-Job -Name "${Context}-${Adapter}" -ScriptBlock {
                                param($Context, $PowerBotPath, $AdapterFilePath, $Config)
                                Import-Module $PowerBotPath, $AdapterFilePath
                                Start-Adapter -Context $Context @Config -Verbose
                            } -ArgumentList $Context, $PowerBotMQ, $AdapterFile.FullName, $Config
                        }
                    }
                }
            }
        }
    }
}

Microsoft.PowerShell.Core\Register-ArgumentCompleter -Command Start-Adapter -Parameter AdapterName -ScriptBlock $GetAdapterNames

Restart-Adapter *