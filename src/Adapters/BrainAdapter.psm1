#requires -Module PowerBotMQ
$Reactions = @{}

## If Jim Christopher's SQLite module is available, we'll use it
Import-Module -Name SQLitePSProvider -ErrorAction SilentlyContinue
if(!(Test-Path data:) -and (Microsoft.PowerShell.Core\Get-Command -Name Mount-SQLite)) {
    $DataDir = Get-StoragePath
    $BotDataFile = Join-Path $DataDir "botdata.sqlite"
    Mount-SQLite -Name data -DataSource ${BotDataFile}
} elseif(!(Test-Path data:)) {
    Write-Warning "No data drive, UserTracking and Roles disabled"
}

function Register-Reaction {
    #.Synopsis
    #   Register an automatic reaction for the bot
	[CmdletBinding()]
	param(
        # Regular Expression pattern to trigger this reaction
		[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		$Pattern,

        # Command to return when this reaction is triggered
		[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		$Command
	)
	process {
		Write-Verbose "Registering reaction trigger for '$Pattern'" -Verbose
		if(!$Reactions.Contains($Pattern)){
			$Reactions.$Pattern = @($Command)
		} else {
			$Reactions.$Pattern += $Command
		}
	}
}

function Unregister-Reaction {
    #.Synopsis
    #   Unregister an automatic reaction from the bot
	[CmdletBinding()]
	param(
        # The Regular Expression pattern of the reaction that you want to remove
		[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		$Pattern,

        # The Command of the pattern you want to remove
		[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		$Command
	)
	process {
		Write-Verbose "Removing reaction trigger for '$Pattern'" -Verbose
		if($Reactions.Contains($Pattern)){
			$Reactions.$Pattern = $Reactions.$Pattern | Where-Object { $_ -ne $Command }
		}
	}
}

function Get-Reaction {
    #.Synopsis
    #   Get a (list of) reaction(s) that are registered in this bot
    [CmdletBinding()]
    [OutputType([Hashtable], [Array])]
	param(
        # Optionally, the pattern you want the reaction(s) for
		[Parameter()]
		$Pattern
    )
    if($Pattern) {
        if($Reactions.Contains($Pattern)){
            $Reactions[$Pattern]
        }
    } else {
        $Reactions
    }
}

function Start-Adapter {
    #.Synopsis
    #   Start this adapter (mandatory adapter cmdlet)
    [CmdletBinding()]
    param(
        # The Context to start this adapter for. Generally, the channel name that's common across networks.
        # Defaults to "PowerShell"
        $Context = "PowerShell",

        # The Name of this adapter.
        # Defaults to "PowerBot"
        [String]$Name = "PowerBot"
    )

    if($Reactions.Count -eq 0) {
        Initialize-Adapter
    }

    $Reactions = Get-Reaction

    $Script:PowerBotName = $Name
    Register-Receiver $Context
    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {
            Write-Verbose "Receive-Message?"
            if($Message = Receive-Message) {
                $Message | Format-Table | Out-String | Write-Verbose
                foreach($KVP in $Reactions.GetEnumerator()) {
                    if($Message.Message -Join "`n" -Match $KVP.Key) {
                        foreach($Command in $KVP.Value) {
                            &$Command $Message
                        }
                    }
                }
            } else {
                Write-Verbose "No Message"
            }
        }
        $Character = $Host.UI.RawUI.ReadKey().Character
    }
}

function Initialize-Adapter {
    #.Synopsis
    #   Initialize the adapter (mandatory adapter cmdlet)
    param()

    Register-Reaction '^ping$' {
        param(
            [PoshCode.Envelope]$Message
        )
        process {
            Send-Message -Message "Pong" -Type $Message.Type -Context $Message.Context -Channel $Message.Channel
        }
    }
    Register-Reaction '^time$' {
        param(
            [PoshCode.Envelope]$Message
        )
        process {
            Send-Message -Message (Get-Date) -Type "Message" -Context $Message.Context -Channel $Message.Channel
        }
    }
    # TODO: Load more of these from files...
}

Export-ModuleMember -Function Register-Reaction, Unregister-Reaction, Get-Reaction, Start-Adapter