using System;

namespace PoshCode
{
    public class Envelope : EventArgs
    {
        public Envelope() {
            Timestamp = DateTimeOffset.Now;
        }
        
        // This is the PubSub Subscription name (e.g.: for two bots on the same brain, use the same name)
        public string Context { get; set; }
        // This is the network name of the sender
        public string Network { get; set; }
        // This is the channel name of the sender
        public string Channel { get; set; }
        // This is the user name of the sender
        public string DisplayName { get; set; }
        // This indicates whether the user is an authenticated user
        public string AuthenticatedUser { get; set; }
        // Timestamp for the message
        public DateTimeOffset Timestamp { get; set; }
        // This is the message type (Message, Action, Reply, ???)
        public MessageType Type { get; set; }
        // This is the actual content of the envelope :)
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