#requires -Module PowerBotMQ
Add-Type -Path "$PSScriptRoot\..\lib\SlackAPI.dll"

$Network = "PowerShell.Slack.com"
$Channel = "testing"
$Context = "#PowerShell"
$Token = "xoxb-4017917578-FaJxFmRzkKIEqQAxg16hw8Bb"

Register-Receiver $Context

function Send-Message {
    #.Synopsis
    #  Sends a message to the IRC server
    [CmdletBinding()]
    param(
        # Who to send the message to (a channel or nickname)
        [Parameter(Position=0)]
        [String]$To = $Script:Channel,
       
        [Parameter()]
        [String]$From = $null,

        # The message to send
        [Parameter(Position=1, ValueFromPipeline=$true)]
        [String]$Message,
       
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

function Initialize-Adapter {
    $Script:Client = [SlackAPI.SlackSocketClient]::new($Token)
    $client.Connect()
    while(!$client.IsReady) { Start-Sleep -Milliseconds 40 }

    Unregister-Event -SourceIdentifier SlackHandler -ErrorAction SilentlyContinue
    $null = Register-ObjectEvent $client OnMessageReceived  -SourceIdentifier SlackHandler -Action { 
        $Client = $Event.SourceArgs[0]
        $Message = $EventArgs.Message
        if($Message.user -eq $Null -or $client.MySelf.id -eq $Message.user) {
            return
        }
        $Channel = if($Client.ChannelLookup.ContainsKey($Message.channel)) {
            $Client.ChannelLookup[$Message.channel].name
        } else {
            Write-Warning "Could not get channel from event, ignoring"
            return
        }
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
        PowerBotMQ\Send-Message -Type $MessageType -Context $Context -Channel $Channel -Network $Network -User $User -Message $Message.Text
    } -MessageData @{
        Context = $Context
        Network = $Network
    }
    return $Script:Client
}

function Start-Adapter {
    if(!$Script:Client) {
        $Script:Client = SlackAdapter\Initialize-Adapter
    }
    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {
            foreach($envelope in PowerBotMQ\Receive-Message -NotFromNetwork $Network -NotFromChannel $Channel -TimeoutMilliSeconds 100) {
                Write-Debug ($envelope.Network + " not ($Network) " + $envelope.Channel + " not ($Channel) " + $envelope.Message )
                foreach($Message in $envelope.Message) {
                    SlackAdapter\Send-Message -From $envelope.User -Message $Message -Type $envelope.Type
                }
            }
        }
        $Character = $Host.UI.RawUI.ReadKey().Character
    }
}