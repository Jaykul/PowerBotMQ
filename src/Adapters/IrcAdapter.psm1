#requires -Module PowerBotMQ
using namespace System.Management.Automation
Add-Type -Path "$PSScriptRoot\..\lib\Meebey.SmartIrc4net.dll"

${AuthenticatedUsers} = @{}


function Send-Message {
    #.Synopsis
    #  Sends a message to the IRC server
    [CmdletBinding()]
    param(
        # Who to send the message to (a channel or nickname)
        [Parameter(Position=0)]
        [String]$To,

        # The message to send
        [Parameter(Position=1, ValueFromPipeline=$true)]
        [String]$Message,

        [Parameter()]
        [String]$From,
        
        # How to send the message: Message, Reply, Topic, Action
        [PoshCode.MessageType]$Type = "Message"
    )
    process {
        Write-Verbose "Send-IrcMessage $Message"

        foreach($Line in $Message.Trim() -split "\s*[\r\n]+\s*" | Where { ![string]::IsNullOrEmpty($_) }) {
            # Figure out how many characters we can put in our message
            $MaxLength = 497 - $To.Length - $script:client.Who.Length
            
            [string]$msg = if($From) {
                "<{0}>" -f ($From -replace "^(.)", "`$1$([char]0x200C)")
            }
            
            foreach($word in $Line.Trim() -split " ") {
                if($MaxLength -lt ($msg.Length + $word.Length)) {
                    Write-Verbose "SendMessage( '$Type', '$To', '$Message' )"
                    $script:client.SendMessage("$Type", $To, $msg.Trim())

                    [string]$msg = if($From) {
                        "<{0}>" -f ($From -replace "^(.)", "`$1$([char]0x200C)")
                    }
                }
                $msg += " " + $word
            }
            Write-Verbose "SendMessage( '$Type', '$To', '$Message' )"
            $script:client.SendMessage("$Type", $To, $msg.Trim())
        }
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
        [AllowNull()]
        [Credential()]
        [PSCredential]$Credential,

        # Nickname for the user
        [Parameter(Mandatory)]
        [string[]]$Nick,

        [Parameter(Mandatory)]
        [string]$RealName
    )
    end {

        $script:client = New-Object Meebey.SmartIrc4net.IrcClient -Property @{
            # TODO: Expose these options to configuration
            AutoRejoin = $true
            AutoRejoinOnKick = $false
            AutoRelogin = $true
            AutoReconnect = $true
            AutoRetry = $true
            AutoRetryDelay = 60
            SendDelay = 400
            Encoding = [Text.Encoding]::UTF8
            # SmartIrc will track channels for us
            ActiveChannelSyncing = $true
        }

        Write-Verbose "InitializeAdapter -Context $Context -Network $($Network.Authority) -Channel $Channel -Credential $Credential -Nick $Nick -RealName $RealName"

        # This causes errors to show up in the console
        $script:client.Add_OnError( {Write-Error "Error $($_.ErrorMessage)"} )
        # This give us the option of seeing every line as verbose output
        # $script:client.Add_OnReadLine( {Write-Verbose "ReadLine $($_.Line)" -Verbose} )

        ## UserModeChange (this happens, among other things, when we first go online, so it's a good time to join channels)
        $script:client.Add_OnUserModeChange( {
            Write-Verbose "RfcJoin $Channel" -Verbose
            $script:client.RfcJoin( $Channel )
        } )

        

        
        
        $script:client.Add_OnWho( {OnWho} )
        $script:client.Add_OnJoin( {OnJoin} )
        $script:client.Add_OnPart( {OnPart} )
        $script:client.Add_OnNickChange( {OnNickChange} )
        $script:client.Add_OnLoggedIn( {OnLoggedIn} )

        ## FOR DEBUGGING: repeat every line as verbose output
        # $script:client.Add_OnReadLine( {Write-Verbose $_.Line} )

        # We handle commands on query (private) messages or on channel messages
        # $script:client.Add_OnQueryMessage( {Write-Verbose "QUERY: $($_ | Fl * |Out-String)" } )
        $script:client.Add_OnChannelMessage( {
            $Authenticated = ${AuthenticatedUsers}.($_.Data.Nick)
            Write-Verbose "IRC1: $Context $($Network.Host)\$($_.Data.Channel) MESSAGE <$($_.Data.Nick)> $($_.Data.Message) (AUTH: $Authenticated)"
            if(!$Authenticated) {
                $script:client.rfcWhoIs($_.Data.Nick)
            }
        
            PowerBotMQ\Send-Message -Type "Message" -Context $Context -Channel $_.Data.Channel -Network "$($Network.Host)" -DisplayName $_.Data.Nick -AuthenticatedUser $Authenticated -Message $_.Data.Message
        } )

        $script:client.Add_OnChannelAction( {
            $Flag = [char][byte]1
            $Message = $_.Data.Message -replace "${Flag}ACTION (.*)${Flag}",'$1'
            $Authenticated = ${AuthenticatedUsers}.($_.Data.Nick)
            Write-Verbose "IRC1: $Context $($Network.Host)\$($_.Data.Channel) ACTION <$($_.Data.Nick)> $Message (AUTH: $Authenticated)"
            if(!$Authenticated) {
                $script:client.rfcWhoIs($_.Data.Nick)
            }
            
            PowerBotMQ\Send-Message -Type "Action" -Context $Context -Channel $_.Data.Channel -Network "$($Network.Host)" -DisplayName $_.Data.Nick -AuthenticatedUser $Authenticated -Message $Message
        } )

        # Unregister-Event -SourceIdentifier IrcHandler -ErrorAction SilentlyContinue
        # $null = Register-ObjectEvent $client OnChannelMessage -SourceIdentifier IrcHandler -Action {
        #     $Client = $Event.SourceArgs[0]
        #     $Data = $EventArgs.Data
        #
        #     $Context = $Event.MessageData.Context
        #     $Network = $Event.MessageData.Network
        #     Write-Verbose "IRC2: $Context $Host\$($Data.Channel) <$($Data.Nick)> $($Data.Message)"
        #     $Authenticated = ${AuthenticatedUsers}.($_.Data.Nick)
        #     if(!$Authenticated) {
        #         $Client.rfcWhoIs($Data.Nick)
        #     }            
        #     PowerBotMQ\Send-Message -Type "Message" -Context $Context -Channel $Channel -Network $Network -DisplayName $Data.Nick -Message -AuthenticatedUser $Authenticated -Message $Data.Message
        # } -MessageData @{
        #     Context = $Context
        #     Network = "$($Network.Host)"
        # }

        # Connect to the server
        $script:client.Connect($Network.Host, $Network.Port)

        # Login to the server
        if($Credential) {
            $script:client.Login($nick, $realname, 0, $Credential.GetNetworkCredential().UserName, $Credential.GetNetworkCredential().Password)
        } else {
            $script:client.Login($nick, $realname, 0, $nick[0])
        }


        return $script:client
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
        [AllowNull()]
        [Credential()]
        [PSCredential]$Credential = $(if($Network.UserInfo){$Network.UserInfo}),

        # Nickname for the user
        [string[]]$Nick = @("PowerBot", "PowerBotMQ"),

        [string]$RealName = "$Nick PowerBot <http://GitHub.com/Jaykul/PowerBotMQ>"
    )
    $Channel = $Channel -replace "^#*","#"

    Register-Receiver $Context
    Write-Verbose "Start-Adapter -Context $Context -Network $Network -Channel $Channel -Credential $Credential -Nick $Nick -RealName $RealName"
    if(!$Script:Client) {
        $Script:Client = InitializeAdapter -Context $Context -Network $Network -Channel $Channel -Credential $Credential -Nick $Nick -RealName $RealName
    }

    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {

            $script:client.Listen($false)
            foreach($envelope in PowerBotMQ\Receive-Message -NotFromNetwork $Network.Host -NotFromChannel $Channel -TimeoutMilliSeconds 100) {
                Write-Debug ($envelope.Network + " not $($Network.Host) " + $envelope.Channel + " not ($Channel) " + $envelope.Message )
                foreach($Message in $envelope.Message) {
                    if($Envelope.Network -eq "Robot") {
                        IrcAdapter\Send-Message -To $Channel -Type $envelope.Type -Message $Message
                    } else {
                        IrcAdapter\Send-Message -To $Channel -Type $envelope.Type -Message $Message -From $envelope.User
                    }
                }
            }
        }
        $Character = $Host.UI.RawUI.ReadKey().Character
    }
}

Export-ModuleMember -Function "Send-Message", "Start-Adapter"





function OnWho {
    Write-Verbose "Who: $Context $($_.Nick)!$($_.Ident)@$($_.Host)"
    # Write-Verbose $(($_ | Format-List | Out-String -Stream) -join "`n")
    if($script:client.IsMe($_.Nick)) {
        $script:client | Add-Member NoteProperty Who "$($_.Nick)!$($_.Ident)@$($_.Host)"
        $script:client.Remove_OnWho( {OnWho} )
    }    
}

function OnJoin {
    param($Source, $EventArgs)
    Write-Verbose ("Join: " + $Nick)
    if($script:client.Nicknames -notcontains $Nick) {
        $script:client.rfcWhoIs($Nick)
    }
}

function OnPart {
    param($Source, $EventArgs)
    Write-Verbose ("Part: '" + $EventArgs.Who + "' just departed " + $EventArgs.Channel + "' saying '" + $EventArgs.PartMessage + "'")
    if(${AuthenticatedUsers}.ContainsKey($Nick)) {
        $null = ${AuthenticatedUsers}.Remove($Nick)
    }
}

function OnNickChange {
    param($Source, $EventArgs)
    Write-Verbose ("Nick: '" + $EventArgs.OldNickname + "' is now '" + $EventArgs.NewNickname + "'")

    if(${AuthenticatedUsers}.ContainsKey($EventArgs.OldNickname)) {
        ${AuthenticatedUsers}.($EventArgs.NewNickname) = ${AuthenticatedUsers}.($EventArgs.OldNickname)
        $null = ${AuthenticatedUsers}.Remove($EventArgs.OldNickname)
    }
}

function OnLoggedIn {
    # .Synopsis
    #    Track the nicknames of logged-in users
    # .Description
    #    For dancer (the IRCD for FreeNode) 
    #    As part of the WHOIS response, we get a Reply with ID 330
    #    Which maps the nick to the account name it's logged in as
    Write-Verbose ("'" + $_.Nick + "' is logged in as '"+ $_.Account + "'")
    ${AuthenticatedUsers}.($_.Nick) = $_.Account
}

# A NOTE ABOUT MESSAGE LENGTH:
   
   #IRC max length is 512, minus the CR LF and other headers ... 
   # In practice, it looks like this:
   # :Nick!Ident@Host PRIVMSG #Powershell :Your Message Here
   ###### The part that never changes is the 512-2 (for the \r\n) 
   ###### And the "PRIVMSG" and extra spaces and colons
   # So that inflexible part of the header is:
   #     1 = ":".Length
   #     9 = " PRIVMSG ".Length 
   #     2 = " :".Length
   # So therefore our hard-coded magic number is:
   #     498 = 510 - 12
   # (I take an extra one off for good luck: 510 - 13)
   
   # In a real world example with my host mask and "Shelly" as the nick and user id:
     # Host     : geoshell/dev/Jaykul
     # Ident    : ~Shelly
     # Nick     : Shelly
   # We calculate the mask in our OnWho:
     # Mask     : Shelly!~Shelly@geoshell/dev/Jaykul
   
   # So if the "$Sender" is "#PowerShell" our header is:
   #     57 = ":Shelly!~Shelly@geoshell/dev/Jaykul PRIVMSG #Powershell :".Length
     # As we said before/, 12 is constant
     #     12 = ":" + " PRIVMSG " + " :"
     # And our Who.Mask ends up as:
     #     34 = "Shelly!~Shelly@geoshell/dev/Jaykul".Length 
     # And our Sender.Length is:
     #     11 = "#Powershell".Length
     # The resulting MaxLength would be 
     #    452 = 497 - 11 - 34
     # Which is one less than the real MaxLength:
     #    453 = 512 - 2 - 57 