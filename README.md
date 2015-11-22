PowerBot
========

An chat bot for PowerShell using ZeroMQ, or rather ... a bridge bot with the possibility of adding triggers like Hubot's.

There are currently two protocol adapters (IRC and Slack), both written in PowerShell against .Net assemblies.  Technically these can be written in any language where there's a ZeroMQ library!

It's a bit of a mess, but for now I've pushed a lib folder full of stuff that should be NuGet packages: NetMQ, SlackAPI, and SmartIrc4net, plus their dependencies: Newtonsoft.Json, ServiceStack, Log4Net, WebSocket4Net, etc.

Still to come: the a binary project (PowerBot.csproj), plus my fork of @inumedia's SlackAPI, and @meebey's SmartIrc4Net .. and the build scripts and all that jazz. Also, I intend to figure out a way to use Hubot and/or Mmmbot adapters ...

If you want to write automation scripts against it, have a look at the "BrainAdapter.psm1" adapter. You don't have to add triggers to that (although you can) -- you could just implement your own "adapter" that talks back like the BrainAdapter does. :wink:


Getting Started
===============

Install the dependency [Configuration Module](https://github.com/PoshCode/Configuration) by running `Install-Module Configuration`

From the source, run `Setup.ps1` and `Build.ps1`, then import the module that was built `Import-Module PowerBot` (you might need to sepecify the version, like `-MinimumVersion 4.0.3`).

After importing the PowerBot module, you need to set up it's configuration once. Run `$config = Get-BotConfig` and then alter your `$config` as necessary, setting login credentials and channels as needed. 
Then, store the configuration by running: `$config | Set-BotConfig` -- this will store a `Configuration.psd1` file in your user data folder (i.e.: $Home\AppData\Roaming\WindowsPowerShell\HuddledMasses.org\PowerBot\Configuration.psd1) . 

Finally, run `Start-PowerBot`.

You can verify that everything is still running anytime, by checking the status of the jobs with `Get-Job` and even view verbose logging messages by calling `Receive-Job`.  If you need to restart an adapter for any reason, you can use `Restart-BotAdapter` with the name of the adapter (i.e. "Slack" or "IRC")
  