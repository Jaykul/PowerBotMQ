@{    # PowerShell is the "Context"    PowerShell = @{        # Brain is the configuration for the AI part ...        # So far there's not much here        Brain = @{
            Name = 'PowerBot'
        }
        # Slack is the Adapter        Slack = @{
            # Get this from slack's integration page.
            # Create a "Hubot" and copy the API Token
            Token = 'xoxb-.....'
            Network = 'slack://powershell.slack.com'
            Channel = 'testing'
            Nick = 'PowerBot'
        }
        IRC = @{
            # You need to do this:
            #  $Cfg = Get-PowerBotConfiguration
            #  $Cfg.PowerShell.Irc.Credential = Get-Credential
            #  $Cfg | Set-PowerBotConfiguration
            Credential = 'TestBot'
            RealName = 'PowerBot from Jaykul'
            Nick = 'TestBot'
            Network = 'irc://chat.freenode.net:8001'
            Channel = 'PowerBot'
        }
    }
}