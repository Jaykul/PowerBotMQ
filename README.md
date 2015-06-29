PowerBot
========

An chat bot for PowerShell using ZeroMQ, or rather ... a bridge bot with the possibility of adding triggers like Hubot's.

There are currently two protocol adapters (IRC and Slack), both written in PowerShell against .Net assemblies.  Technically these can be written in any language where there's a ZeroMQ library!

It's a bit of a mess, but for now I've pushed a lib folder full of stuff that should be NuGet packages: NetMQ, SlackAPI, and SmartIrc4net, plus their dependencies: Newtonsoft.Json, ServiceStack, Log4Net, WebSocket4Net, etc.

Still to come: the a binary project (PowerBot.csproj), plus my fork of @inumedia's SlackAPI, and @meebey's SmartIrc4Net .. and the build scripts and all that jazz. Also, I intend to figure out a way to use Hubot and/or Mmmbot adapters ...

If you want to write automation scripts against it, have a look at the "TheBrain.psm1" adapter. You don't have to add triggers to that (although you can) -- you could just implement your own "adapter" that talks back like TheBrain does. :wink: