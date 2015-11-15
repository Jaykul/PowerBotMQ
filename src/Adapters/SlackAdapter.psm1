#requires -Module PowerBotMQ
Add-Type -Path "$PSScriptRoot\..\lib\SlackAPI.dll"

function Send-Message {
    #.Synopsis
    #  Sends a message to the IRC server
    [CmdletBinding()]
    param(
        # Who to send the message to (a channel or nickname)
        [Parameter(Position=0)]
        [String]$To = $Script:Channel,

        # The message to send
        [Parameter(Position=1, ValueFromPipeline=$true)]
        [String]$Message,

        [Parameter()]
        [String]$From = $Script:Nick,

        # How to send the message
        [PoshCode.MessageType]$Type = "Message"
    )
    process {
        if(!$client.ChannelLookup.ContainsKey($to)) {
            $to = $client.Channels.where{$_.name -eq $to}.id
        }
        Write-Verbose "Send-SlackMessage -To $to -Message $Message"
        if($Type -eq "Action") {
            $Message = "_${Message}_"
        }
        $client.PostMessage($null, $to, $Message, $From)
    }
}

function InitializeAdapter {
    #.Synopsis
    #   Initialize the adapter (internal initialization from start-adapter)
    [CmdletBinding()]
    param(
        # The unique name that connects all the Adapter jobs
        [Parameter(Mandatory, Position=0)]
        [string]$Context,

        # The network connection information, e.g.: irc://chat.freenode.net:8001/PowerBot
        [Parameter(Mandatory, Position=1)]
        [Uri]$Network,

        # The channels you want to connect to
        [Parameter(Mandatory)]
        [string]$Channel,

        # The credentials (if any) needed to connect
        [Parameter(Mandatory)]
        [String]$Token
    )
    end {
        Register-Receiver $Context
        Write-Verbose "Start-Adapter -Context $Context -Network $Network.Host -Channel $Channel -Token $Token"

        $Script:Client = [SlackAPI.SlackSocketClient]::new($Token)
        $client.Connect()
        while(!$client.IsReady) { Start-Sleep -Milliseconds 40 }

        Unregister-Event -SourceIdentifier SlackHandler -ErrorAction SilentlyContinue
        $null = Register-ObjectEvent $client OnMessageReceived  -SourceIdentifier SlackHandler -Action {
            $Client = $Event.SourceArgs[0]
            $Message = $EventArgs.Message
            if($Null -eq $Message.user -or $client.MySelf.id -eq $Message.user) {
                return
            }
            $Channel = if($Client.ChannelLookup.ContainsKey($Message.channel)) {
                $Client.ChannelLookup[$Message.channel].name
            } else {
                Write-Warning "Could not get channel from event, ignoring"
                return
            }

            # Slack bots get invited into channels ...
            # Including channels we don't care about (or that are part of another "Context")
            if($Event.MessageData.Channel -eq $Channel) {
                $User = if($Client.UserLookup.ContainsKey($Message.user)) {
                    $Lookup = $Client.UserLookup[$Message.user]
                    if($Lookup.name) { $Lookup.name } else { $Lookup.id }
                } else {
                    $Message.user
                }
                $MessageType = "Message"
                if($Message.subtype -eq "me_message") { $MessageType = "Action" }
    
                $Context = $Event.MessageData.Context
                $Network = $Event.MessageData.Network
                
                Write-Debug "FROM SLACK: $Context $Network\$Channel <${User}|$($Message.user)> $($Message.Text)"
                # Write-Debug $($Message | Format-List | Out-String)

                $Text = $Message.Text
                # Strip the slack code delimiter backticks
                $Text = $Text -replace '[\r\n\s]*```[\r\n\s]*(.*)[\r\n\s]*```[\r\n\s]*',"`n`$1`n"
                $Text = $Text -replace '```(.*)```',"  `$1  "
                
                PowerBotMQ\Send-Message -Type $MessageType -Context $Context -Channel $Channel -Network $Network -DisplayName $User -AuthenticatedUser $Message.user -Message $Text
            }
        } -MessageData @{
            Channel = $Channel
            Context = $Context
            Network = $Network.Host
        }
        return $Script:Client
    }
}

function Start-Adapter {
    #.Synopsis
    #   Start this adapter (mandatory adapter cmdlet)
    [CmdletBinding()]
    param(
        # The unique name that connects all the Adapter jobs
        [Parameter(Mandatory, Position=0)]
        [string]$Context,

        # The network connection information, e.g.: irc://chat.freenode.net:8001/PowerBot
        [Parameter(Mandatory, Position=1)]
        [Uri]$Network,

        # The channels you want to connect to
        [string]$Channel = $( $Network.Segments.Trim('/').Split(',',[StringSplitOptions]::RemoveEmptyEntries) | ? { $_ } ),

        # The credentials (if any) needed to connect
        [String]$Token = $(if($Network.UserInfo){ $Network.UserInfo }),

        # Nickname for the user
        [Parameter(Mandatory)]
        [string]$Nick
    )

    Write-Verbose "Start-Adapter -Context $Context -Network $Network -Channel $Channel -Token $Token"
    $Script:Nick = $Nick

    if(!$Script:Client) {
        $Script:Client = InitializeAdapter -Context $Context -Network $Network -Channel $Channel -Token $Token
    }

    $Network = $Network.Scheme + "://" + $Network.Host

    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {
            foreach($envelope in PowerBotMQ\Receive-Message -NotFromNetwork $Network.Host -NotFromChannel $Channel -TimeoutMilliSeconds 100) {
                Write-Debug ($envelope.Network + " not ($($Network.Host)) " + $envelope.Channel + " not ($Channel) " + $envelope.Message )
                foreach($Message in $envelope.Message) {
                    SlackAdapter\Send-Message -To $Channel -From $envelope.User -Message $Message -Type $envelope.Type
                }
            }
        }
        $Character = $Host.UI.RawUI.ReadKey().Character
    }
}

Export-ModuleMember -Function "Send-Message", "Start-Adapter"