using System;
using System.Management.Automation;
using System.Threading;
using NetMQ;
using NetMQ.zmq;

namespace PoshCode
{

    /// <summary>
    /// Forwards messages bidirectionally between two sockets. You can also specify a control socket tn which proxied messages will be sent.
    /// </summary>
    /// <remarks>
    /// This class must be explicitly started by calling <see cref="Start"/>. If an external <see cref="Poller"/> has been specified,
    /// then that call will block until <see cref="Stop"/> is called.
    /// <para/>
    /// If using an external <see cref="Poller"/>, ensure the front and back end sockets have been added to it.
    /// <para/>
    /// Users of this class must call <see cref="Stop"/> when messages should no longer be proxied.
    /// </remarks>
    public class ZeroMqHub : Job
    {
        private readonly NetMQTimer _heartbeat;
        private readonly NetMQSocket _subscriber;
        private readonly NetMQSocket _publisher;
        private readonly NetMQSocket _control;
        private Poller _poller;

        private const int NotStarted = 0;
        private const int Running = 1;
        private const int Stopped = 4;

        private int _state = NotStarted;
        private readonly string _publisherAddress;
        private readonly string _subscriberAddress;
        private bool _isDisposed;
        private string _status;


        //public enum ProxyState
        //{
        //	Stopped = Stopped,
        //	Starting = NotStarted,
        //	Started = Running,
        //	Stopping = Stopping
        //}

        public NetMQSocket Subscriber { get { return _subscriber; } }
        public NetMQSocket Publisher { get { return _publisher; } }

        /// <summary>
        /// Create a new instance of a Proxy (NetMQ.Proxy)
        /// with the given sockets to serve as a front-end, a back-end, and a control socket.
        /// </summary>
        /// <param name="publisherAddress">the address that messages will be forwarded from</param>
        /// <param name="subscriberAddress">the address that messages should be sent to</param>
        /// <param name="heartbeat">the timespan at which to send HEARTBEAT messages (in milliseconds) - you can set this to zero if not needed</param>
        /// <param name="control">this socket will have messages also sent to it - you can set this to null if not needed</param>
        public ZeroMqHub(string publisherAddress, string subscriberAddress, int heartbeat = 0, NetMQSocket control = null)
        {
            _subscriberAddress = subscriberAddress;
            _publisherAddress = publisherAddress;
            var context = NetMQContext.Create();
            _subscriber = context.CreateXSubscriberSocket();
            _publisher = context.CreateXPublisherSocket();
            _control = control;

            if (heartbeat > 0)
            {
                _heartbeat = new NetMQTimer(heartbeat);
                _heartbeat.Elapsed += (s, a) => _publisher.Send("HEARTBEAT");
            }

            Name = "XPub-XSub";
            PSJobTypeName = typeof(ZeroMqHub).Name;

            _subscriber.Bind(subscriberAddress);
            _publisher.Bind(publisherAddress);
        }

        /// <summary>
        /// Start proxying messages between the front and back ends.
        /// </summary>
        /// <exception cref="InvalidOperationException">The proxy has already been started.</exception>
        public void Start()
        {
            _status = "Attempting to start";
            if (Interlocked.CompareExchange(ref _state, Running, NotStarted) != NotStarted)
            {
                throw new InvalidOperationException("ZeroMQ XPub-XSub hub has already been started");
            }
            _status = "Starting";

            _subscriber.ReceiveReady += OnSubscriberReady;
            _publisher.ReceiveReady += OnPublisherReady;

            _poller = new Poller(_subscriber, _publisher);
            if (_heartbeat != null)
            {
                _poller.AddTimer(_heartbeat);
            }

            this.SetJobState(JobState.Running);
            _status = "Started";
            _poller.PollTillCancelledNonBlocking();
            _status = "Running Until Canceled";
        }

        public override string ToString()
        {
            return JobStateInfo.State + " ZeroMqHub from (XSub): " + _subscriberAddress + " to (XPub): " + _publisherAddress;
        }

        /// <summary>
        /// Stops the proxy, blocking until the underlying <see cref="Poller"/> has completed.
        /// </summary>
        /// <exception cref="InvalidOperationException">The proxy has not been started.</exception>
        public override void StopJob()
        {
            _status = "Attempting to stop";
            if (Interlocked.CompareExchange(ref _state, Stopped, Running) != Running)
            {
                throw new InvalidOperationException("Proxy is not Running");
            }
            this.SetJobState(JobState.Stopping);
            _status = "Stopping";
            StopHeartBeat();
            _status = "Stopping: Waiting for poller";

            _poller.CancelAndJoin();
            _poller.Dispose();
            _poller = null;
            _status = "Stopping: Clean Up";

            _subscriber.ReceiveReady -= OnSubscriberReady;
            _publisher.ReceiveReady -= OnPublisherReady;

            this.SetJobState(JobState.Stopped);
            _status = "Stopped";
        }

        public void StopHeartBeat()
        {
            if (_heartbeat != null)
            {
                _poller.RemoveTimer(_heartbeat);
                _status = "No heartbeat!";
            }
        }

        private void OnSubscriberReady(object sender, NetMQSocketEventArgs e)
        {
            ProxyBetween(_subscriber, _publisher, _control);
        }

        private void OnPublisherReady(object sender, NetMQSocketEventArgs e)
        {
            ProxyBetween(_publisher, _subscriber, _control);
        }

        private static void ProxyBetween(NetMQSocket from, NetMQSocket to, NetMQSocket control)
        {
            var msg = new Msg();
            msg.InitEmpty();

            var copy = new Msg();
            copy.InitEmpty();

            while (true)
            {
                from.Receive(ref msg);
                var more = msg.HasMore;

                if (control != null)
                {
                    copy.Copy(ref msg);

                    control.Send(ref copy, more ? SendReceiveOptions.SendMore : SendReceiveOptions.None);
                }

                to.Send(ref msg, more ? SendReceiveOptions.SendMore : SendReceiveOptions.None);

                if (!more)
                    break;
            }

            copy.Close();
            msg.Close();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !this._isDisposed)
            {
                StopJob();

                _subscriber.Dispose();
                _publisher.Dispose();

                this._isDisposed = true;
            }
            base.Dispose(disposing);
        }

        public override bool HasMoreData
        {
            get { return _subscriber.HasIn; }
        }

        public override string Location
        {
            get { return "XPub: " + _publisherAddress + " XSub: " + _subscriberAddress; }
        }

        public override string StatusMessage
        {
            get { return _status; }
        }
    }
}
