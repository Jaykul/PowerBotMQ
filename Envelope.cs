using System;

namespace PoshCode
{
    public class Envelope : EventArgs
    {
        // This is the PubSub Subscription name (e.g.: for two bots on the same brain, use the same name)
        public string Context { get; set; }
        // This is the network name of the sender
        public string Network { get; set; }
        // This is the channel name of the sender
        public string Channel { get; set; }
        // This is the user name of the sender
        public string User { get; set; }
        // This is the message type (Message, Action, Reply, ???)
        public MessageType Type { get; set; }
        public string[] Message { get; set; }
    }

    public enum MessageType
    {
        Message,
        Reply,
        Topic,
        Action
    }
}