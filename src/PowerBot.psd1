@{

# These modules will be processed when the module manifest is loaded.
ModuleToProcess = 'PowerBot.psm1'

# This GUID is used to uniquely identify this module.
GUID = '58d14559-327c-4be5-92d3-e7be1edf35dd'

# The author of this module.
Author = 'Joel Bennett'

# The company or vendor for this module.
CompanyName = 'http://HuddledMasses.org'

# The copyright statement for this module.
Copyright = '(c) 2014, Joel Bennett'

# The version of this module.
ModuleVersion = '4.0.2'

# A description of this module.
Description = 'PowerBot: the PowerShell IRC Bot'

# The minimum version of PowerShell needed to use this module.
PowerShellVersion = '5.0'

# The CLR version required to use this module.
CLRVersion = '4.0'

# Functions to export from this manifest.
FunctionsToExport = 'Restart-Adapter','Start-ZeroMqHub','Get-PowerBotConfiguration','Set-PowerBotConfiguration'

# Aliases to export from this manifest.
# AliasesToExport = ''

# Variables to export from this manifest.
#VariablesToExport = ''

# Cmdlets to export from this manifest.
#CmdletsToExport = ''

# This is a list of other modules that must be loaded before this module.
RequiredModules = @(@{ModuleName='Configuration';ModuleVersion='0.2'})
NestedModules = 'PowerBotMQ.psm1'

# The script files (.ps1) that are loaded before this module.
ScriptsToProcess = @()

# The type files (.ps1xml) loaded by this module.
TypesToProcess = @()

# The format files (.ps1xml) loaded by this module.
FormatsToProcess = @()

FileList = @(
    'PowerBot.psd1', 'PowerBot.psm1', 'PowerBotMQ.psm1',
    'Configuration.psd1', 'ReadMe.md', 'LICENSE',
    'Adapters\BrainAdapter.psm1','Adapters\IrcAdapter.psm1','Adapters\SlackAdapter.psm1',

    'lib\PowerBot.dll','lib\NetMQ.dll','lib\AsyncIO.dll',
    'lib\SlackAPI.dll',
    'lib\log4net.dll','lib\Meebey.SmartIrc4net.dll','lib\Newtonsoft.Json.dll',
    'lib\StarkSoftProxy.dll','lib\WebSocket4Net.dll'
)

# A list of assemblies that must be loaded before this module can work.
RequiredAssemblies = '.\lib\PowerBot.dll' # Meebey.SmartIrc4net, Version=0.4.5, Culture=neutral, PublicKeyToken=null

PrivateData = @{
    # PSData is module packaging and gallery metadata embedded in PrivateData
    # It's for the PowerShellGet module
    # We had to do this because it's the only place we're allowed to extend the manifest
    # https://connect.microsoft.com/PowerShell/feedback/details/421837
    PSData = @{
        # Keyword tags to help users find this module via navigations and search.
        Tags = @('IRC','Slack','Bot','PowerBot')

        # The web address of this module's project or support homepage.
        ProjectUri = "https://github.com/Jaykul/PowerBot"

        # The web address of this module's license. Points to a page that's embeddable and linkable.
        LicenseUri = "http://opensource.org/licenses/GPL-2.0"

        # Release notes for this particular version of the module
        ReleaseNotes = "First public release (now with config)!"
    }
}
}
