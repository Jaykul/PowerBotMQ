@{
    # PowerShell is the "Context"
    PowerShell = @{
        # Brain is the configuration for the AI part ...
        # So far there's not much here
        Brain = @{
            Name = 'PowerBot'
            Roles = @("Owner", "Admin", "User", "Guest")
        }
        Command = @{
            Name = 'PowerBot'
            CommandPrefix = '>'
            RoleWhiteList = @{
                Owner = @{
                    "PowerBot\UserRoles" = "Add-Role","Remove-Role"
                }
                Admin = @{
                    "Microsoft.PowerShell.Utility" = "New-Alias"
                    "Compliment"="Update-Compliment","Remove-Compliment"
                }
                User  = @{
                    "Bing"="*"
                    "Math"="Invoke-MathEvaluator"
                    "WebQueries"="*"
                    "Strings"= "Join-String", "Split-String", "Replace-String", "Format-Csv"
                    "FAQ"="*"
                    "Compliment"="Get-Compliment","Add-Compliment"
                    "CreditTracking"="*"
                    "Microsoft.PowerShell.Utility" = "Format-Wide", "Format-List", "Format-Table", "Select-Object", "Sort-Object", "Get-Random", "Out-String"
                }
                Guest = @{
                    "PowerBot\UserRoles" = "Get-Role"
                    "PowerBot\BotCommands" = "Get-Help"
                }
            }
        }
        # Slack is the Adapter
        Slack = @{
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