/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

/**
$(ZMQD) – a thin wrapper around the low-level C API of the
$(LINK2 http://zeromq.org,$(ZMQ)) messaging framework.

Most functions in this module have a one-to-one relationship with functions
in the underlying C API.  Some adaptations have been made to make the API
safer, easier and more pleasant to use; most importantly:
$(UL
    $(LI
        Errors are signalled by means of exceptions rather than return
        codes.  In particular, the $(REF ZmqException) class provides
        a standard textual message for any error condition, but it also
        provides access to the $(D errno) code set by the C function
        that reported the error.)
    $(LI
        Functions are appropriately marked with $(D @safe), $(D pure)
        and $(D nothrow), thus facilitating their use in high-level D code.)
    $(LI
        Memory and resources (i.e. contexts, sockets and messages) are
        automatically managed, thus preventing leaks.)
    $(LI
        Context, socket and message options are implemented as properties.)
)
The names of functions and types in $(ZMQD) are very similar to those in
$(ZMQ), but they follow the D naming conventions.  Thus, the library should
feel both familiar to $(ZMQ) users and natural to D users.  A notable
deviation from the C API is that message parts are consistently called
"frames".  For example, $(D zmq_msg_send()) becomes $(D zmqd.Frame.send())
and so on.  (Multipart messages were a late addition to $(ZMQ), and the "msg"
function names were well established at that point.  The library's
developers have admitted that this is somewhat confusing, and the newer
CZMQ API consistently uses "frame" in function names.)

Due to the close correspondence with the C API, this documentation has
intentionally been kept sparse. There is really no reason to repeat the
contents of the $(ZMQAPI __start,$(ZMQ) reference manual) here.
Instead, the documentation for each function contains a "Corresponds to"
section that links to the appropriate pages in the $(ZMQ) reference.  Any
details given in the present documentation mostly concern the D-specific
adaptations that have been made.

Also note that the examples generally only use the INPROC transport.  The
reason for this is that the examples double as unittests, and we want to
avoid firewall troubles and other issues that could arise with the use of
network protocols such as TCP, PGM, etc., and the IPC protocol is not
supported on Windows.  Anyway, they are only short
snippets that demonstrate the syntax; for more comprehensive and realistic
examples, please refer to the $(LINK2 http://zguide.zeromq.org/page:all,
$(ZMQ) Guide).  Many of the examples in the Guide have been translated to
D, and can be found in the
$(LINK2 https://github.com/kyllingstad/zmqd/tree/master/examples,$(D examples))
subdirectory of the $(ZMQD) source repository.

Version:
    1.1.0 (compatible with $(ZMQ) >= 4.0.0)
Authors:
    $(LINK2 http://github.com/kyllingstad,Lars T. Kyllingstad)
Copyright:
    Copyright (c) 2013–2015, Lars T. Kyllingstad. All rights reserved.
License:
    $(ZMQD) is released under the terms of the
    $(LINK2 https://www.mozilla.org/MPL/2.0/index.txt,Mozilla Public License v. 2.0).$(BR)
    Please refer to the $(LINK2 http://zeromq.org/area:licensing,$(ZMQ) site)
    for details about $(ZMQ) licensing.
Macros:
    D      = <code>$0</code>
    EM     = <em>$0</em>
    LDOTS  = &hellip;
    QUOTE  = <blockquote>$0</blockquote>
    FREF   = $(D $(LINK2 #$1,$1()))
    REF    = $(D $(LINK2 #$1,$1))
    COREF  = $(D $(LINK2 http://dlang.org/phobos/core_$1.html#.$2,core.$1.$2))
    OBJREF = $(D $(LINK2 http://dlang.org/phobos/object.html#.$1,$1))
    STDREF = $(D $(LINK2 http://dlang.org/phobos/std_$1.html#.$2,std.$1.$2))
    ZMQ    = &#x2205;MQ
    ZMQAPI = $(LINK2 http://api.zeromq.org/4-0:$1,$+)
    ZMQD   = $(ZMQ)D
    ZMQREF = $(D $(ZMQAPI $1,$1))
*/
module zmqd;

import core.time;
import std.typecons;
import deimos.zmq.zmq;


version(Windows) {
    import std.c.windows.winsock: SOCKET;
}

// libsodium is enabled by default, since that is the case with ZeroMQ itself.
version (WithoutLibsodium) { } else version = WithLibsodium;

// Compatibility check
version(unittest) static this()
{
    import std.stdio: stderr;
    const v = zmqVersion();
    if (v.major != ZMQ_VERSION_MAJOR || v.minor != ZMQ_VERSION_MINOR) {
        stderr.writefln(
            "Warning: Potential ZeroMQ header/library incompatibility: "
            ~"The header (binding) is for version %d.%d.%d, "
            ~"while the library is version %d.%d.%d. Unittests may fail.",
            ZMQ_VERSION_MAJOR, ZMQ_VERSION_MINOR, ZMQ_VERSION_PATCH,
            v.major, v.minor, v.patch);
    }
    // Known incompatibilities
    import std.algorithm: min, max;
    const libVersion = ZMQ_MAKE_VERSION(v.major, v.minor, v.patch);
    const older = min(ZMQ_VERSION, libVersion);
    const newer = max(ZMQ_VERSION, libVersion);
    if (older < ZMQ_MAKE_VERSION(4, 1, 0) && newer >= ZMQ_MAKE_VERSION(4, 1, 0)) {
        stderr.writeln("Note: Version 4.1.0 is known to be ABI incompatible with older versions");
    } else if (older < ZMQ_MAKE_VERSION(4, 1, 1) && newer >= ZMQ_MAKE_VERSION(4, 1, 1)) {
        stderr.writeln("Note: Version 4.1.1 is known to be ABI incompatible with older versions");
    }
}


@safe:


/**
Reports the $(ZMQ) library version.

Returns:
    A $(STDREF typecons,Tuple) with three integer fields that represent the
    three versioning levels: $(D major), $(D minor) and $(D patch).
Corresponds_to:
    $(ZMQREF zmq_version())
*/
Tuple!(int, "major", int, "minor", int, "patch") zmqVersion() nothrow
{
    typeof(return) v;
    trusted!zmq_version(&v.major, &v.minor, &v.patch);
    return v;
}


/**
The various socket types.

These are described in the $(ZMQREF zmq_socket()) reference.
*/
enum SocketType
{
    req     = ZMQ_REQ,      /// Corresponds to $(D ZMQ_REQ)
    rep     = ZMQ_REP,      /// Corresponds to $(D ZMQ_REP)
    dealer  = ZMQ_DEALER,   /// Corresponds to $(D ZMQ_DEALER)
    router  = ZMQ_ROUTER,   /// Corresponds to $(D ZMQ_ROUTER)
    pub     = ZMQ_PUB,      /// Corresponds to $(D ZMQ_PUB)
    sub     = ZMQ_SUB,      /// Corresponds to $(D ZMQ_SUB)
    xpub    = ZMQ_XPUB,     /// Corresponds to $(D ZMQ_XPUB)
    xsub    = ZMQ_XSUB,     /// Corresponds to $(D ZMQ_XSUB)
    push    = ZMQ_PUSH,     /// Corresponds to $(D ZMQ_PUSH)
    pull    = ZMQ_PULL,     /// Corresponds to $(D ZMQ_PULL)
    pair    = ZMQ_PAIR,     /// Corresponds to $(D ZMQ_PAIR)
    stream  = ZMQ_STREAM,   /// Corresponds to $(D ZMQ_STREAM)
}


/// Security mechanisms.
enum Security
{
    /// $(ZMQAPI zmq_null,NULL): No security or confidentiality.
    none  = ZMQ_NULL,

    /// $(ZMQAPI zmq_plain,PLAIN): Clear-text authentication.
    plain = ZMQ_PLAIN,

    /// $(ZMQAPI zmq_curve,CURVE): Secure authentication and confidentiality.
    curve = ZMQ_CURVE,
}


/**
An object that encapsulates a $(ZMQ) socket.

A default-initialized $(D Socket) is not a valid $(ZMQ) socket; it
must always be explicitly initialized with a constructor (see
$(FREF _Socket.this)):
---
Socket s;                     // Not a valid socket yet
s = Socket(SocketType.push);  // ...but now it is.
---
This $(D struct) is noncopyable, which means that a socket is always
uniquely managed by a single $(D Socket) object.  Functions that will
inspect or use the socket, but not take ownership of it, should take
a $(D ref Socket) parameter.  Use $(STDREF algorithm,move) to move
a $(D Socket) to a different location (e.g. into a sink function that
takes it by value, or into a new variable).

The socket is automatically closed when the $(D Socket) object goes out
of scope.

Linger_period:
Note that Socket by default sets the socket's linger period to zero.
This deviates from the $(ZMQ) default (which is an infinite linger period).
*/
struct Socket
{
@safe:
    /**
    Creates a new $(ZMQ) socket.

    If $(D context) is not specified, the default context (as returned
    by $(FREF defaultContext)) is used.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_socket())
    */
    this(SocketType type)
    {
        this(defaultContext(), type);
    }

    /// ditto
    this(Context context, SocketType type)
    {
        m_context = context;
        m_type = type;
        m_socket = trusted!zmq_socket(context.handle, type);
        if (m_socket == null) {
            throw new ZmqException;
        }
        linger = 0.msecs;
    }

    /// With default context:
    unittest
    {
        auto sck = Socket(SocketType.push);
        assert (sck.initialized);
    }
    /// With explicit context:
    unittest
    {
        auto ctx = Context();
        auto sck = Socket(ctx, SocketType.push);
        assert (sck.initialized);
    }

    // Socket objects are noncopyable.
    @disable this(this);

    unittest // Verify that move semantics work.
    {
        import std.algorithm: move;
        struct SocketOwner
        {
            this(Socket s) { owned = trusted!move(s); }
            Socket owned;
        }
        auto socket = Socket(SocketType.req);
        const socketPtr = socket.handle;
        assert (socketPtr != null);

        auto owner = SocketOwner(trusted!move(socket));
        assert (socket.handle == null);
        assert (!socket.m_context.initialized);
        assert (owner.owned.handle == socketPtr);
        assert (owner.owned.m_context.initialized);
    }

    // Closes the socket on desctruction.
    ~this() nothrow { nothrowClose(); }

    /**
    Closes the $(ZMQ) socket.

    Note that the socket will be closed automatically upon destruction,
    so it is usually not necessary to call this method manually.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_close())
    */
    void close()
    {
        if (!nothrowClose()) throw new ZmqException;
    }

    ///
    unittest
    {
        auto s = Socket(SocketType.pair);
        assert (s.initialized);
        s.close();
        assert (!s.initialized);
    }

    /**
    Starts accepting incoming connections on $(D endpoint).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_bind())
    */
    void bind(const char[] endpoint)
    {
        if (trusted!zmq_bind(m_socket, zeroTermString(endpoint)) != 0) {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        auto s = Socket(SocketType.pub);
        s.bind("inproc://zmqd_bind_example");
    }

    /**
    Stops accepting incoming connections on $(D endpoint).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_unbind())
    */
    void unbind(const char[] endpoint)
    {
        if (trusted!zmq_unbind(m_socket, zeroTermString(endpoint)) != 0) {
            throw new ZmqException;
        }
    }

    // TODO: Remove version(Posix) and change to INPROC when updating to ZMQ 4.1.
    //       IPC does not work on Windows, and unbind() does not work with INPROC.
    //       See: https://github.com/zeromq/libzmq/issues/949
    ///
    version (Posix) unittest
    {
        auto s = Socket(SocketType.pub);
        s.bind("ipc://zmqd_unbind_example");
        // Do some work...
        s.unbind("ipc://zmqd_unbind_example");
    }

    /**
    Creates an outgoing connection to $(D endpoint).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_connect())
    */
    void connect(const char[] endpoint)
    {
        if (trusted!zmq_connect(m_socket, zeroTermString(endpoint)) != 0) {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        auto s = Socket(SocketType.sub);
        s.connect("inproc://zmqd_connect_example");
    }

    /**
    Disconnects the socket from $(D endpoint).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_disconnect())
    */
    void disconnect(const char[] endpoint)
    {
        if (trusted!zmq_disconnect(m_socket, zeroTermString(endpoint)) != 0) {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        auto s = Socket(SocketType.sub);
        s.connect("inproc://zmqd_disconnect_example");
        // Do some work...
        s.disconnect("inproc://zmqd_disconnect_example");
    }

    /**
    Sends a message frame.

    $(D _send) blocks until the frame has been queued on the socket.
    $(D trySend) performs the operation in non-blocking mode, and returns
    a $(D bool) value that signifies whether the frame was queued on the
    socket.

    The $(D more) parameter specifies whether this is a multipart message
    and there are more frames to follow.

    The $(D char[]) overload is a convenience function that simply casts
    the string argument to $(D ubyte[]).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_send()) (with the $(D ZMQ_DONTWAIT) flag, in the
        case of $(D trySend), and with the $(D ZMQ_SNDMORE) flag if
        $(D more == true)).
    */
    void send(const ubyte[] data, bool more = false)
    {
        immutable flags = more ? ZMQ_SNDMORE : 0;
        if (trusted!zmq_send(m_socket, data.ptr, data.length, flags) < 0) {
            throw new ZmqException;
        }
    }

    /// ditto
    void send(const char[] data, bool more = false)
    {
        send(cast(const(ubyte)[]) data, more);
    }

    /// ditto
    bool trySend(const ubyte[] data, bool more = false)
    {
        immutable flags = ZMQ_DONTWAIT | (more ? ZMQ_SNDMORE : 0);
        if (trusted!zmq_send(m_socket, data.ptr, data.length, flags) < 0) {
            import core.stdc.errno;
            if (errno == EAGAIN) return false;
            else throw new ZmqException;
        }
        return true;
    }

    /// ditto
    bool trySend(const char[] data, bool more = false)
    {
        return trySend(cast(const(ubyte)[]) data, more);
    }

    ///
    unittest
    {
        auto sck = Socket(SocketType.pub);
        sck.send(cast(ubyte[]) [11, 226, 92]);
        sck.send("Hello World!");
    }

    /**
    Sends a message frame.

    $(D _send) blocks until the frame has been queued on the socket.
    $(D trySend) performs the operation in non-blocking mode, and returns
    a $(D bool) value that signifies whether the frame was queued on the
    socket.

    The $(D more) parameter specifies whether this is a multipart message
    and there are more frames to follow.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_send()) (with the $(D ZMQ_DONTWAIT) flag, in the
        case of $(D trySend), and with the $(D ZMQ_SNDMORE) flag if
        $(D more == true)).
    */
    void send(ref Frame msg, bool more = false)
    {
        immutable flags = more ? ZMQ_SNDMORE : 0;
        if (trusted!zmq_msg_send(msg.handle, m_socket, flags) < 0) {
            throw new ZmqException;
        }
    }

    /// ditto
    bool trySend(ref Frame msg, bool more = false)
    {
        immutable flags = ZMQ_DONTWAIT | (more ? ZMQ_SNDMORE : 0);
        if (trusted!zmq_msg_send(msg.handle, m_socket, flags) < 0) {
            import core.stdc.errno;
            if (errno == EAGAIN) return false;
            else throw new ZmqException;
        }
        return true;
    }

    ///
    unittest
    {
        auto sck = Socket(SocketType.pub);
        auto msg = Frame(12);
        msg.data.asString()[] = "Hello World!";
        sck.send(msg);
    }

    /**
    Sends a constant-memory message frame.

    $(D _sendConst) blocks until the frame has been queued on the socket.
    $(D trySendConst) performs the operation in non-blocking mode, and returns
    a $(D bool) value that signifies whether the frame was queued on the
    socket.

    The $(D more) parameter specifies whether this is a multipart message
    and there are more frames to follow.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_send_const()) (with the $(D ZMQ_DONTWAIT) flag, in the
        case of $(D trySend), and with the $(D ZMQ_SNDMORE) flag if
        $(D more == true)).
    */
    void sendConst(immutable ubyte[] data, bool more = false)
    {
        immutable flags = more ? ZMQ_SNDMORE : 0;
        if (trusted!zmq_send_const(m_socket, data.ptr, data.length, flags) < 0) {
            throw new ZmqException;
        }
    }

    /// ditto
    void sendConst(string data, bool more = false)
    {
        sendConst(cast(immutable(ubyte)[]) data, more);
    }

    /// ditto
    bool trySendConst(immutable ubyte[] data, bool more = false)
    {
        immutable flags = ZMQ_DONTWAIT | (more ? ZMQ_SNDMORE : 0);
        if (trusted!zmq_send_const(m_socket, data.ptr, data.length, flags) < 0) {
            import core.stdc.errno;
            if (errno == EAGAIN) return false;
            else throw new ZmqException;
        }
        return true;
    }

    /// ditto
    bool trySendConst(string data, bool more = false)
    {
        return trySend(cast(immutable(ubyte)[]) data, more);
    }

    ///
    unittest
    {
        static immutable arr = cast(ubyte[]) [11, 226, 92];
        auto sck = Socket(SocketType.pub);
        sck.sendConst(arr);
        sck.sendConst("Hello World!");
    }

    /**
    Receives a message frame.

    $(D _receive) blocks until the request can be satisfied, and returns the
    number of bytes in the frame.
    $(D tryReceive) performs the operation in non-blocking mode, and returns
    a $(STDREF typecons,Tuple) which contains the size of the frame along
    with a $(D bool) value that signifies whether a frame was received.
    (If the latter is $(D false), the former is always set to zero.)

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_recv()) (with the $(D ZMQ_DONTWAIT) flag, in the case
        of $(D tryReceive)).

    */
    size_t receive(ubyte[] data)
    {
        immutable len = trusted!zmq_recv(m_socket, data.ptr, data.length, 0);
        if (len >= 0) {
            import std.conv;
            return to!size_t(len);
        } else {
            throw new ZmqException;
        }
    }

    /// ditto
    Tuple!(size_t, bool) tryReceive(ubyte[] data)
    {
        immutable len = trusted!zmq_recv(m_socket, data.ptr, data.length, ZMQ_DONTWAIT);
        if (len >= 0) {
            import std.conv;
            return typeof(return)(to!size_t(len), true);
        } else {
            import core.stdc.errno;
            if (errno == EAGAIN) {
                return typeof(return)(0, false);
            } else {
                throw new ZmqException;
            }
        }
    }

    ///
    unittest
    {
        // Sender
        auto snd = Socket(SocketType.req);
        snd.connect("inproc://zmqd_receive_example");
        snd.send("Hello World!");

        // Receiver
        import std.string: representation;
        auto rcv = Socket(SocketType.rep);
        rcv.bind("inproc://zmqd_receive_example");
        char[256] buf;
        immutable len  = rcv.receive(buf.representation);
        assert (buf[0 .. len] == "Hello World!");
    }

    @system unittest
    {
        auto snd = Socket(SocketType.pair);
        snd.bind("inproc://zmqd_tryReceive_example");
        auto rcv = Socket(SocketType.pair);
        rcv.connect("inproc://zmqd_tryReceive_example");

        ubyte[256] buf;
        auto r1 = rcv.tryReceive(buf);
        assert (!r1[1]);

        import core.thread, core.time, std.string;
        snd.send("Hello World!");
        Thread.sleep(100.msecs); // Wait for message to be transferred...
        auto r2 = rcv.tryReceive(buf);
        assert (r2[1] && buf[0 .. r2[0]] == "Hello World!".representation);
    }

    /**
    Receives a message frame.

    $(D _receive) blocks until the request can be satisfied, and returns the
    number of bytes in the frame.
    $(D tryReceive) performs the operation in non-blocking mode, and returns
    a $(STDREF typecons,Tuple) which contains the size of the frame along
    with a $(D bool) value that signifies whether a frame was received.
    (If the latter is $(D false), the former is always set to zero.)

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_recv()) (with the $(D ZMQ_DONTWAIT) flag, in the case
        of $(D tryReceive)).

    */
    size_t receive(ref Frame msg)
    {
        immutable len = trusted!zmq_msg_recv(msg.handle, m_socket, 0);
        if (len >= 0) {
            import std.conv;
            return to!size_t(len);
        } else {
            throw new ZmqException;
        }
    }

    /// ditto
    Tuple!(size_t, bool) tryReceive(ref Frame msg)
    {
        immutable len = trusted!zmq_msg_recv(msg.handle, m_socket, ZMQ_DONTWAIT);
        if (len >= 0) {
            import std.conv;
            return typeof(return)(to!size_t(len), true);
        } else {
            import core.stdc.errno;
            if (errno == EAGAIN) {
                return typeof(return)(0, false);
            } else {
                throw new ZmqException;
            }
        }
    }

    ///
    unittest
    {
        // Sender
        auto snd = Socket(SocketType.req);
        snd.connect("inproc://zmqd_msg_receive_example");
        snd.send("Hello World!");

        // Receiver
        import std.string: representation;
        auto rcv = Socket(SocketType.rep);
        rcv.bind("inproc://zmqd_msg_receive_example");
        auto msg = Frame();
        rcv.receive(msg);
        assert (msg.data.asString() == "Hello World!");
    }

    @system unittest
    {
        auto snd = Socket(SocketType.pair);
        snd.bind("inproc://zmqd_msg_tryReceive_example");
        auto rcv = Socket(SocketType.pair);
        rcv.connect("inproc://zmqd_msg_tryReceive_example");

        auto msg = Frame();
        auto r1 = rcv.tryReceive(msg);
        assert (!r1[1]);

        import core.thread, core.time, std.string;
        snd.send("Hello World!");
        Thread.sleep(100.msecs); // Wait for message to be transferred...
        auto r2 = rcv.tryReceive(msg);
        assert (r2[1] && msg.data[0 .. r2[0]] == "Hello World!".representation);
    }

    /**
    The socket _type.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_getsockopt()) with $(D ZMQ_TYPE).
    */
    @property SocketType type() { return getOption!SocketType(ZMQ_TYPE); }

    ///
    unittest
    {
        auto sck = Socket(SocketType.xpub);
        assert (sck.type == SocketType.xpub);
    }

    /**
    Whether there are _more message frames to follow.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_getsockopt()) with $(D ZMQ_RCVMORE).
    */
    @property bool more() { return !!getOption!int(ZMQ_RCVMORE); }

    // TODO: Better unittest/example
    unittest
    {
        auto sck = Socket(SocketType.req);
        assert (!sck.more);
    }

    /**
    Misc. socket options.

    Each of these has a one-to-one correspondence with an option passed to
    $(ZMQREF zmq_getsockopt()) and $(ZMQREF zmq_setsockopt()). For
    example, $(D identity) corresponds to $(D ZMQ_IDENTITY),
    $(D receiveBufferSize) corresponds to $(D ZMQ_RCVBUF), etc.

    Notes:
    $(UL
        $(LI For convenience, the setter for the $(D identity) property
            accepts strings.  To retrieve a string with the getter, use
            the $(FREF asString) function.
            ---
            sck.identity = "foobar";
            assert (sck.identity.asString() == "foobar");
            ---
            )
        $(LI The $(D linger), $(D receiveTimeout) and $(D sendTimeout)
            properties may have the special value $(COREF time,Duration.max),
            which in this context specifies an infinite duration.  This  is
            translated to an option value of -1 in the C API (and it is also
            the default value for all of them).)
        $(LI Some options have array type, and these allow the user to supply
            a buffer in which to store the value, to avoid a GC allocation.
            The return value is then a slice of this buffer.
            These are not marked as $(D @property), but are prefixed with
            "get" (e.g. $(D getIdentity())).  A user-supplied buffer is
            $(I required) for some options, namely $(D getPlainUsername())
            and $(D getPlainPassword()), and these do not have $(D @property)
            versions.  $(D getCurveXxxKey()) and $(D getCurveXxxKeyZ85())
            require buffers which are at least 32 and 41 bytes long,
            respectively.)
        $(LI The $(D ZMQ_SUBSCRIBE) and $(D ZMQ_UNSUBSCRIBE) options are
            treated differently from the others; see $(FREF Socket.subscribe)
            and $(FREF Socket.unsubscribe))
    )

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.$(BR)
        $(STDREF conv,ConvOverflowException) if a given $(D Duration) is
            longer than the number of milliseconds that will fit in an $(D int)
            (only applies to properties of $(COREF time,Duration) type).$(BR)
        $(COREF exception,RangeError) if the $(D dest) buffers passed to
            $(D getCurveXxxKey()) or $(D getCurveXxxKeyZ85()) are less than
            32 or 41 bytes long, respectively.
    Corresponds_to:
        $(ZMQREF zmq_getsockopt()) and $(ZMQREF zmq_setsockopt()).
    */
    @property int sendHWM() { return getOption!int(ZMQ_SNDHWM); }
    /// ditto
    @property void sendHWM(int value) { setOption(ZMQ_SNDHWM, value); }

    /// ditto
    @property int receiveHWM() { return getOption!int(ZMQ_RCVHWM); }
    /// ditto
    @property void receiveHWM(int value) { setOption(ZMQ_RCVHWM, value); }

    /// ditto
    @property ulong threadAffinity() { return getOption!ulong(ZMQ_AFFINITY); }
    /// ditto
    @property void threadAffinity(ulong value) { setOption(ZMQ_AFFINITY, value); }

    /// ditto
    @property ubyte[] identity() { return getIdentity(new ubyte[255]); }
    /// ditto
    ubyte[] getIdentity(ubyte[] dest) { return getArrayOption(ZMQ_IDENTITY, dest); }
    /// ditto
    @property void identity(const ubyte[] value) { setArrayOption(ZMQ_IDENTITY, value); }
    /// ditto
    @property void identity(const char[] value) { setArrayOption(ZMQ_IDENTITY, value); }

    /// ditto
    @property int rate() { return getOption!int(ZMQ_RATE); }
    /// ditto
    @property void rate(int value) { setOption(ZMQ_RATE, value); }

    /// ditto
    @property Duration recoveryInterval()
    {
        return msecs(getOption!int(ZMQ_RECOVERY_IVL));
    }
    /// ditto
    @property void recoveryInterval(Duration value)
    {
        import std.conv: to;
        setOption(ZMQ_RECOVERY_IVL, to!int(value.total!"msecs"()));
    }

    /// ditto
    @property int sendBufferSize() { return getOption!int(ZMQ_SNDBUF); }
    /// ditto
    @property void sendBufferSize(int value) { setOption(ZMQ_SNDBUF, value); }

    /// ditto
    @property int receiveBufferSize() { return getOption!int(ZMQ_RCVBUF); }
    /// ditto
    @property void receiveBufferSize(int value) { setOption(ZMQ_RCVBUF, value); }

    /// ditto
    @property Duration linger()
    {
        const auto value = getOption!int(ZMQ_LINGER);
        return value == -1 ? Duration.max : value.msecs;
    }
    /// ditto
    @property void linger(Duration value)
    {
        import std.conv: to;
        setOption(ZMQ_LINGER,
                  value == Duration.max ? -1 : to!int(value.total!"msecs"()));
    }

    /// ditto
    @property Duration reconnectionInterval()
    {
        return getOption!int(ZMQ_RECONNECT_IVL).msecs;
    }
    /// ditto
    @property void reconnectionInterval(Duration value)
    {
        import std.conv: to;
        setOption(ZMQ_RECONNECT_IVL, to!int(value.total!"msecs"()));
    }

    /// ditto
    @property Duration maxReconnectionInterval()
    {
        return getOption!int(ZMQ_RECONNECT_IVL_MAX).msecs;
    }
    /// ditto
    @property void maxReconnectionInterval(Duration value)
    {
        import std.conv: to;
        setOption(ZMQ_RECONNECT_IVL_MAX, to!int(value.total!"msecs"()));
    }

    /// ditto
    @property int backlog() { return getOption!int(ZMQ_BACKLOG); }
    /// ditto
    @property void backlog(int value) { setOption(ZMQ_BACKLOG, value); }

    /// ditto
    @property long maxMsgSize() { return getOption!long(ZMQ_MAXMSGSIZE); }
    /// ditto
    @property void maxMsgSize(long value) { setOption(ZMQ_MAXMSGSIZE, value); }

    /// ditto
    @property int multicastHops() { return getOption!int(ZMQ_MULTICAST_HOPS); }
    /// ditto
    @property void multicastHops(int value) { setOption(ZMQ_MULTICAST_HOPS, value); }

    /// ditto
    @property Duration receiveTimeout()
    {
        const value = getOption!int(ZMQ_RCVTIMEO);
        return value == -1 ? Duration.max : value.msecs;
    }
    /// ditto
    @property void receiveTimeout(Duration value)
    {
        import std.conv: to;
        setOption(ZMQ_RCVTIMEO,
                  value == Duration.max ? -1 : to!int(value.total!"msecs"()));
    }

    /// ditto
    @property Duration sendTimeout()
    {
        const value = getOption!int(ZMQ_SNDTIMEO);
        return value == -1 ? Duration.max : value.msecs;
    }
    /// ditto
    @property void sendTimeout(Duration value)
    {
        import std.conv: to;
        setOption(ZMQ_SNDTIMEO,
                  value == Duration.max ? -1 : to!int(value.total!"msecs"()));
    }

    /// ditto
    @property bool ipv6() { return !!getOption!int(ZMQ_IPV6); }
    /// ditto
    @property void ipv6(bool value) { setOption(ZMQ_IPV6, value ? 1 : 0); }

    /// ditto
    deprecated("Use !ipv6 instead")
    @property bool ipv4Only() { return !ipv6; }
    /// ditto
    deprecated("Use ipv6 = !value instead")
    @property void ipv4Only(bool value) { ipv6 = !value; }

    /// ditto
    @property bool immediate() { return !!getOption!int(ZMQ_IMMEDIATE); }
    /// ditto
    @property void immediate(bool value) { setOption!int(ZMQ_IMMEDIATE, value ? 1 : 0); }

    /// ditto
    deprecated("Use the 'immediate' property instead")
    @property bool delayAttachOnConnect() { return !!getOption!int(ZMQ_DELAY_ATTACH_ON_CONNECT); }
    /// ditto
    deprecated("Use the 'immediate' property instead")
    @property void delayAttachOnConnect(bool value) { setOption(ZMQ_DELAY_ATTACH_ON_CONNECT, value ? 1 : 0); }

    /// ditto
    @property FD fd() { return getOption!FD(ZMQ_FD); }

    /// ditto
    @property PollFlags events() { return getOption!PollFlags(ZMQ_EVENTS); }

    /// ditto
    @property char[] lastEndpoint() @trusted
    {
        // This function is not @safe because it calls a @system function
        // (zmq_getsockopt) and takes the address of a local (len).
        auto buf = new char[1024];
        size_t len = buf.length;
        if (zmq_getsockopt(m_socket, ZMQ_LAST_ENDPOINT, buf.ptr, &len) != 0) {
            throw new ZmqException;
        }
        return buf[0 .. len-1];
    }

    /// ditto
    @property void routerMandatory(bool value) { setOption(ZMQ_ROUTER_MANDATORY, value ? 1 : 0); }

    /// ditto
    @property void probeRouter(bool value) { setOption(ZMQ_PROBE_ROUTER, value ? 1 : 0); }

    /// ditto
    @property void xpubVerbose(bool value) { setOption(ZMQ_XPUB_VERBOSE, value ? 1 : 0); }

    /// ditto
    @property void reqCorrelate(bool value) { setOption(ZMQ_REQ_CORRELATE, value ? 1 : 0); }

    /// ditto
    @property void reqRelaxed(bool value) { setOption(ZMQ_REQ_RELAXED, value ? 1 : 0); }

    /// ditto
    @property int tcpKeepalive() { return getOption!int(ZMQ_TCP_KEEPALIVE); }
    /// ditto
    @property void tcpKeepalive(int value) { setOption(ZMQ_TCP_KEEPALIVE, value); }

    /// ditto
    @property int tcpKeepaliveIdle() { return getOption!int(ZMQ_TCP_KEEPALIVE_IDLE); }
    /// ditto
    @property void tcpKeepaliveIdle(int value) { setOption(ZMQ_TCP_KEEPALIVE_IDLE, value); }

    /// ditto
    @property int tcpKeepaliveCnt() { return getOption!int(ZMQ_TCP_KEEPALIVE_CNT); }
    /// ditto
    @property void tcpKeepaliveCnt(int value) { setOption(ZMQ_TCP_KEEPALIVE_CNT, value); }

    /// ditto
    @property int tcpKeepaliveIntvl() { return getOption!int(ZMQ_TCP_KEEPALIVE_INTVL); }
    /// ditto
    @property void tcpKeepaliveIntvl(int value) { setOption(ZMQ_TCP_KEEPALIVE_INTVL, value); }

    /// ditto
    @property Security mechanism()
    {
        import std.conv;
        return to!Security(getOption!int(ZMQ_MECHANISM));
    }

    /// ditto
    @property bool plainServer() { return !!getOption!int(ZMQ_PLAIN_SERVER); }
    /// ditto
    @property void plainServer(bool value) { setOption(ZMQ_PLAIN_SERVER, value ? 1 : 0); }

    /// ditto
    char[] getPlainUsername(char[] dest)
    {
        return getCStringOption(ZMQ_PLAIN_USERNAME, dest);
    }
    /// ditto
    @property void plainUsername(const(char)[] value)
    {
        setArrayOption(ZMQ_PLAIN_USERNAME, value);
    }

    /// ditto
    char[] getPlainPassword(char[] dest)
    {
        return getCStringOption(ZMQ_PLAIN_PASSWORD, dest);
    }
    /// ditto
    @property void plainPassword(const(char)[] value)
    {
        setArrayOption(ZMQ_PLAIN_PASSWORD, value);
    }

version (WithLibsodium) {

    /// ditto
    @property bool curveServer() { return !!getOption!int(ZMQ_CURVE_SERVER); }
    /// ditto
    @property void curveServer(bool value) { setOption(ZMQ_CURVE_SERVER, value ? 1 : 0); }

    /// ditto
    @property ubyte[] curvePublicKey()
    {
        return getCurvePublicKey(new ubyte[keyBufSizeBin]);
    }
    /// ditto
    ubyte[] getCurvePublicKey(ubyte[] dest)
    {
        return getCurveKey(ZMQ_CURVE_PUBLICKEY, dest);
    }
    /// ditto
    @property char[] curvePublicKeyZ85()
    {
        return getCurvePublicKeyZ85(new char[keyBufSizeZ85]);
    }
    /// ditto
    char[] getCurvePublicKeyZ85(char[] dest)
    {
        return getCurveKeyZ85(ZMQ_CURVE_PUBLICKEY, dest);
    }
    /// ditto
    @property void curvePublicKey(const(ubyte)[] value)
    {
        setCurveKey(ZMQ_CURVE_PUBLICKEY, value);
    }
    /// ditto
    @property void curvePublicKeyZ85(const(char)[] value)
    {
        setCurveKeyZ85(ZMQ_CURVE_PUBLICKEY, value);
    }

    /// ditto
    @property ubyte[] curveSecretKey()
    {
        return getCurveSecretKey(new ubyte[keyBufSizeBin]);
    }
    /// ditto
    ubyte[] getCurveSecretKey(ubyte[] dest)
    {
        return getCurveKey(ZMQ_CURVE_SECRETKEY, dest);
    }
    /// ditto
    @property char[] curveSecretKeyZ85()
    {
        return getCurveSecretKeyZ85(new char[keyBufSizeZ85]);
    }
    /// ditto
    char[] getCurveSecretKeyZ85(char[] dest)
    {
        return getCurveKeyZ85(ZMQ_CURVE_SECRETKEY, dest);
    }
    /// ditto
    @property void curveSecretKey(const(ubyte)[] value)
    {
        setCurveKey(ZMQ_CURVE_SECRETKEY, value);
    }
    /// ditto
    @property void curveSecretKeyZ85(const(char)[] value)
    {
        setCurveKeyZ85(ZMQ_CURVE_SECRETKEY, value);
    }

    /// ditto
    @property ubyte[] curveServerKey()
    {
        return getCurveServerKey(new ubyte[keyBufSizeBin]);
    }
    /// ditto
    ubyte[] getCurveServerKey(ubyte[] dest)
    {
        return getCurveKey(ZMQ_CURVE_SERVERKEY, dest);
    }
    /// ditto
    @property char[] curveServerKeyZ85()
    {
        return getCurveServerKeyZ85(new char[keyBufSizeZ85]);
    }
    /// ditto
    char[] getCurveServerKeyZ85(char[] dest)
    {
        return getCurveKeyZ85(ZMQ_CURVE_SERVERKEY, dest);
    }
    /// ditto
    @property void curveServerKey(const(ubyte)[] value)
    {
        setCurveKey(ZMQ_CURVE_SERVERKEY, value);
    }
    /// ditto
    @property void curveServerKeyZ85(const(char)[] value)
    {
        setCurveKeyZ85(ZMQ_CURVE_SERVERKEY, value);
    }

} // version (WithLibsodium)

    /// ditto
    @property char[] zapDomain() { return getZapDomain(new char[256]); }
    /// ditto
    char[] getZapDomain(char[] dest) { return getCStringOption(ZMQ_ZAP_DOMAIN, dest); }
    /// ditto
    @property void zapDomain(const char[] value) { setArrayOption(ZMQ_ZAP_DOMAIN, value); }

    /// ditto
    @property void conflate(bool value) { setOption(ZMQ_CONFLATE, value ? 1 : 0); }

    unittest
    {
        // We test all the socket options by checking that they have their default value.
        auto s = Socket(SocketType.xpub);
        const e = "inproc://unittest2";
        s.bind(e);
        import core.time;
        assert(s.type == SocketType.xpub);
        assert(s.sendHWM == 1000);
        assert(s.receiveHWM == 1000);
        assert(s.threadAffinity == 0);
        assert(s.identity == null);
        assert(s.rate == 100);
        assert(s.recoveryInterval == 10.seconds);
        assert(s.sendBufferSize == 0);
        assert(s.receiveBufferSize == 0);
        assert(s.linger == 0.hnsecs);
        assert(s.reconnectionInterval == 100.msecs);
        assert(s.maxReconnectionInterval == Duration.zero);
        assert(s.backlog == 100);
        assert(s.maxMsgSize == -1);
        assert(s.multicastHops == 1);
        assert(s.receiveTimeout == Duration.max);
        assert(s.sendTimeout == Duration.max);
        assert(!s.ipv6);
        assert(!s.immediate);
        version(Posix) {
            assert(s.fd > 2); // 0, 1 and 2 are the standard streams
        }
        assert(s.events == PollFlags.pollOut);
        assert(s.tcpKeepalive == -1);
        assert(s.tcpKeepaliveIdle == -1);
        assert(s.tcpKeepaliveCnt == -1);
        assert(s.tcpKeepaliveIntvl == -1);
        assert(s.mechanism == Security.none);
        assert(!s.plainServer);
        assert(s.getPlainUsername(new char[8]).length == 0);
        assert(s.getPlainPassword(new char[8]).length == 0);
        version (WithLibsodium) {
            assert(!s.curveServer);
        }
        assert(s.zapDomain.length == 0);

        // Test setters and getters together
        s.sendHWM = 500;
        assert(s.sendHWM == 500);
        s.receiveHWM = 600;
        assert(s.receiveHWM == 600);
        s.threadAffinity = 1;
        assert(s.threadAffinity == 1);
        s.identity = cast(ubyte[]) [ 65, 66, 67 ];
        assert(s.identity == [65, 66, 67]);
        s.identity = "foo";
        assert(s.identity == [102, 111, 111]);
        s.rate = 200;
        assert(s.rate == 200);
        s.recoveryInterval = 5.seconds;
        assert(s.recoveryInterval == 5_000.msecs);
        s.sendBufferSize = 500;
        assert(s.sendBufferSize == 500);
        s.receiveBufferSize = 600;
        assert(s.receiveBufferSize == 600);
        s.linger = Duration.zero;
        assert(s.linger == Duration.zero);
        s.linger = 100_000.usecs;
        assert(s.linger == 100.msecs);
        s.linger = Duration.max;
        assert(s.linger == Duration.max);
        s.reconnectionInterval = 200_000.usecs;
        assert(s.reconnectionInterval == 200.msecs);
        s.maxReconnectionInterval = 300_000.usecs;
        assert(s.maxReconnectionInterval == 300.msecs);
        s.backlog = 50;
        assert(s.backlog == 50);
        s.maxMsgSize = 1000;
        assert(s.maxMsgSize == 1000);
        s.multicastHops = 2;
        assert(s.multicastHops == 2);
        s.receiveTimeout = 3.seconds;
        assert(s.receiveTimeout == 3_000_000.usecs);
        s.receiveTimeout = Duration.max;
        assert(s.receiveTimeout == Duration.max);
        s.sendTimeout = 2_000_000.usecs;
        assert(s.sendTimeout == 2.seconds);
        s.sendTimeout = Duration.max;
        assert(s.sendTimeout == Duration.max);
        s.ipv6 = true;
        assert(s.ipv6);
        s.immediate = true;
        assert(s.immediate);
        s.tcpKeepalive = 1;
        assert(s.tcpKeepalive == 1);
        s.tcpKeepaliveIdle = 0;
        assert(s.tcpKeepaliveIdle == 0);
        s.tcpKeepaliveCnt = 1;
        assert(s.tcpKeepaliveCnt == 1);
        s.tcpKeepaliveIntvl = 0;
        assert(s.tcpKeepaliveIntvl == 0);
        s.plainServer = true;
        assert(s.mechanism == Security.plain);
        assert(s.plainServer);
        version (WithLibsodium) {
            assert(!s.curveServer);
            s.curveServer = true;
            assert(s.mechanism == Security.curve);
            assert(!s.plainServer);
            assert(s.curveServer);
        }
        s.plainServer = false;
        assert(s.mechanism == Security.none);
        assert(!s.plainServer);
        version (WithLibsodium) assert(!s.curveServer);
        s.plainUsername = "foobar";
        assert(s.getPlainUsername(new char[8]) == "foobar");
        assert(s.mechanism == Security.plain);
        s.plainUsername = null;
        assert(s.mechanism == Security.none);
        s.plainPassword = "xyz";
        assert(s.getPlainPassword(new char[8]) == "xyz");
        assert(s.mechanism == Security.plain);
        s.plainPassword = null;
        assert(s.mechanism == Security.none);
        s.zapDomain = "my_zap_domain";
        assert(s.zapDomain == "my_zap_domain");

        // Test write-only options
        s.conflate = true;
    }

    version (WithLibsodium) @system unittest
    {
        // The CURVE key options require some special setup, so we test them
        // separately.
        import std.array, std.range;
        auto binKey1 = iota(cast(ubyte) 0, cast(ubyte) 32).array();
        auto z85Key1 = z85Encode(binKey1);
        auto binKey2 = iota(cast(ubyte) 32, cast(ubyte) 64).array();
        auto z85Key2 = z85Encode(binKey2);
        auto zeroKey = repeat(cast(ubyte) 0).take(32).array();
        assert (z85Key1 != z85Key2);

        auto s = Socket(SocketType.req);
        s.curvePublicKey = zeroKey;
        s.curveSecretKey = zeroKey;
        s.curveServerKey = zeroKey;

        s.curvePublicKey = binKey1;
        assert (s.curvePublicKey == binKey1);
        assert (s.curvePublicKeyZ85 == z85Key1);
        s.curvePublicKeyZ85 = z85Key2;
        assert (s.curvePublicKey == binKey2);
        assert (s.curvePublicKeyZ85 == z85Key2);
        assert (s.curveSecretKey == zeroKey);
        assert (s.curveServerKey == zeroKey);
        s.curvePublicKey = zeroKey;

        s.curveSecretKey = binKey1;
        assert (s.curveSecretKey == binKey1);
        assert (s.curveSecretKeyZ85 == z85Key1);
        s.curveSecretKeyZ85 = z85Key2;
        assert (s.curveSecretKey == binKey2);
        assert (s.curveSecretKeyZ85 == z85Key2);
        assert (s.curvePublicKey == zeroKey);
        assert (s.curveServerKey == zeroKey);
        s.curveSecretKey = zeroKey;

        s.curveServerKey = binKey1;
        assert (s.curveServerKey == binKey1);
        assert (s.curveServerKeyZ85 == z85Key1);
        s.curveServerKeyZ85 = z85Key2;
        assert (s.curveServerKey == binKey2);
        assert (s.curveServerKeyZ85 == z85Key2);
        assert (s.curvePublicKey == zeroKey);
        assert (s.curveSecretKey == zeroKey);
        s.curveServerKey = zeroKey;
    }

    unittest
    {
        // Some options are only applicable to specific socket types.
        auto rt = Socket(SocketType.router);
        rt.routerMandatory = true;
        rt.probeRouter = true;
        auto xp = Socket(SocketType.xpub);
        xp.xpubVerbose = true;
        auto rq = Socket(SocketType.req);
        rq.reqCorrelate = true;
        rq.reqRelaxed = true;
    }

    deprecated unittest
    {
        // Test deprecated socket options
        auto s = Socket(SocketType.req);
        assert(s.ipv4Only);
        assert(!s.delayAttachOnConnect);

        // Test setters and getters together
        s.ipv4Only = false;
        assert(!s.ipv4Only);
        s.delayAttachOnConnect = true;
        assert(s.delayAttachOnConnect);
    }

    /**
    Establishes a message filter.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_setsockopt()) with $(D ZMQ_SUBSCRIBE).
    */
    void subscribe(const ubyte[] filterPrefix)
    {
        setArrayOption(ZMQ_SUBSCRIBE, filterPrefix);
    }
    /// ditto
    void subscribe(const  char[] filterPrefix)
    {
        setArrayOption(ZMQ_SUBSCRIBE, filterPrefix);
    }

    ///
    unittest
    {
        // Create a subscriber that accepts all messages that start with
        // the prefixes "foo" or "bar".
        auto sck = Socket(SocketType.sub);
        sck.subscribe("foo");
        sck.subscribe("bar");
    }

    @system unittest
    {
        void sleep(int ms) {
            import core.thread, core.time;
            Thread.sleep(dur!"msecs"(ms));
        }
        auto pub = Socket(SocketType.pub);
        pub.bind("inproc://zmqd_subscribe_unittest");
        auto sub = Socket(SocketType.sub);
        sub.connect("inproc://zmqd_subscribe_unittest");

        pub.send("Hello");
        sleep(100);
        sub.subscribe("He");
        sub.subscribe(cast(ubyte[])['W', 'o']);
        sleep(100);
        pub.send("Heeee");
        pub.send("World");
        sleep(100);
        ubyte[5] buf;
        sub.receive(buf);
        assert(buf.asString() == "Heeee");
        sub.receive(buf);
        assert(buf.asString() == "World");
    }

    /**
    Removes a message filter.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_setsockopt()) with $(D ZMQ_SUBSCRIBE).
    */
    void unsubscribe(const ubyte[] filterPrefix)
    {
        setArrayOption(ZMQ_UNSUBSCRIBE, filterPrefix);
    }
    /// ditto
    void unsubscribe(const char[] filterPrefix)
    {
        setArrayOption(ZMQ_UNSUBSCRIBE, filterPrefix);
    }

    ///
    unittest
    {
        // Subscribe to messages that start with "foo" or "bar".
        auto sck = Socket(SocketType.sub);
        sck.subscribe("foo");
        sck.subscribe("bar");
        // ...
        // From now on, only accept messages that start with "bar"
        sck.unsubscribe("foo");
    }

    /**
    Spawns a PAIR socket that publishes socket state changes (events) over
    the INPROC transport to the given endpoint.

    Which event types should be published may be selected by bitwise-ORing
    together different $(REF EventType) flags in the $(D event) parameter.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_socket_monitor())
    See_also:
        $(FREF receiveEvent), which receives and parses event messages.
    */
    void monitor(const char[] endpoint, EventType events = EventType.all)
    {
        if (trusted!zmq_socket_monitor(m_socket, zeroTermString(endpoint), events) < 0) {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        auto sck = Socket(SocketType.pub);
        sck.monitor("inproc://zmqd_monitor_unittest",
                    EventType.accepted | EventType.closed);
    }

    /**
    The $(D void*) pointer used by the underlying C API to refer to the socket.

    If the object has not been initialized, this function returns $(D null).
    */
    @property inout(void)* handle() inout pure nothrow
    {
        return m_socket;
    }

    /**
    Whether this $(REF Socket) object has been _initialized, i.e. whether it
    refers to a valid $(ZMQ) socket.
    */
    @property bool initialized() const pure nothrow
    {
        return m_socket != null;
    }

    ///
    unittest
    {
        Socket sck;
        assert (!sck.initialized);
        sck = Socket(SocketType.sub);
        assert (sck.initialized);
        sck.close();
        assert (!sck.initialized);
    }

private:
    // Helper function for ~this() and close()
    bool nothrowClose() nothrow
    {
        if (m_socket != null) {
            if (trusted!zmq_close(m_socket) != 0) return false;
            m_socket = null;
        }
        return true;
    }

    import std.traits;

    T getOption(T)(int option) @trusted
        if (isScalarType!T)
    {
        T buf;
        auto len = T.sizeof;
        if (zmq_getsockopt(m_socket, option, &buf, &len) != 0) {
            throw new ZmqException;
        }
        assert(len == T.sizeof);
        return buf;
    }

    void setOption(T)(int option, T value) @trusted
        if (isScalarType!T)
    {
        if (zmq_setsockopt(m_socket, option, &value, value.sizeof) != 0) {
            throw new ZmqException;
        }
    }

    T[] getArrayOption(T)(int option, T[] buf) @trusted
        if (isScalarType!T)
    {
        static assert (T.sizeof == 1);
        auto len = buf.length;
        if (zmq_getsockopt(m_socket, option, buf.ptr, &len) != 0) {
            throw new ZmqException;
        }
        return buf[0 .. len];
    }

    void setArrayOption()(int option, const void[] value)
    {
        if (trusted!zmq_setsockopt(m_socket, option, value.ptr, value.length) != 0) {
            throw new ZmqException;
        }
    }

    char[] getCStringOption(int option, char[] buf)
    {
        auto ret = getArrayOption(option, buf);
        assert (ret.length && ret[$-1] == '\0');
        return ret[0 .. $-1];
    }

version (WithLibsodium) {
    enum : size_t
    {
        keySizeBin    = 32,
        keyBufSizeBin = keySizeBin,
        keySizeZ85    = 40,
        keyBufSizeZ85 = keySizeZ85 + 1,
    }

    ubyte[] getCurveKey(int option, ubyte[] buf)
    {
        if (buf.length < keyBufSizeBin) {
            import core.exception: RangeError;
            throw new RangeError;
        }
        return getArrayOption(option, buf[0 .. keyBufSizeBin]);
    }

    char[] getCurveKeyZ85(int option, char[] buf)
    {
        if (buf.length < keyBufSizeZ85) {
            import core.exception: RangeError;
            throw new RangeError;
        }
        return getCStringOption(option, buf[0 .. keyBufSizeZ85]);
    }

    void setCurveKey(int option, const ubyte[] value)
    {
        if (value.length != keySizeBin) throw new Exception("Invalid key size");
        setArrayOption(option, value);
    }

    void setCurveKeyZ85(int option, const char[] value)
    {
        if (value.length != keySizeZ85) throw new Exception("Invalid key size");
        setArrayOption(option, value);
    }
} // version (WithLibsodium)

    Context m_context;
    SocketType m_type;
    void* m_socket;
}

unittest
{
    auto s1 = Socket(SocketType.pair);
    auto s2 = Socket(SocketType.pair);
    s1.bind("inproc://unittest");
    s2.connect("inproc://unittest");
    s1.send("Hello World!");
    ubyte[12] buf;
    const len = s2.receive(buf[]);
    assert (len == 12);
    assert (buf == "Hello World!");
}


version (Windows) {
    alias PlatformFD = SOCKET;
} else version (Posix) {
    alias PlatformFD = int;
}

/**
The native socket file descriptor type.

This is an alias for $(D SOCKET) on Windows and $(D int) on POSIX systems.
*/
alias FD = PlatformFD;


/**
Starts the built-in $(ZMQ) _proxy.

This function never returns normally, but it may throw an exception.  This could
happen if the context associated with either of the specified sockets is
manually destroyed in a different thread.

Throws:
    $(REF ZmqException) if $(ZMQ) reports an error.
Corresponds_to:
    $(ZMQREF zmq_proxy())
See_Also:
    $(FREF steerableProxy)
*/
void proxy(ref Socket frontend, ref Socket backend)
{
    const rc = trusted!zmq_proxy(frontend.handle, backend.handle, null);
    assert (rc == -1);
    throw new ZmqException;
}

/// ditto
void proxy(ref Socket frontend, ref Socket backend, ref Socket capture)
{
    const rc = trusted!zmq_proxy(frontend.handle, backend.handle, capture.handle);
    assert (rc == -1);
    throw new ZmqException;
}


/**
Starts the built-in $(ZMQ) proxy with _control flow.

Note that the order of the two last parameters is reversed compared to
$(ZMQREF zmq_proxy_steerable()).  That is, the $(D control) socket always
comes before the $(D capture) socket.  Furthermore, unlike in $(ZMQ),
$(D control) is mandatory.  (Without the _control socket one can simply
use $(FREF proxy).)

Throws:
    $(REF ZmqException) if $(ZMQ) reports an error.
Corresponds_to:
    $(ZMQREF zmq_proxy_steerable())
See_Also:
    $(FREF proxy)
*/
void steerableProxy(ref Socket frontend, ref Socket backend, ref Socket control)
{
    const rc = trusted!zmq_proxy_steerable(
        frontend.handle, backend.handle, null, control.handle);
    if (rc == -1) throw new ZmqException;
}

/// ditto
void steerableProxy(ref Socket frontend, ref Socket backend, ref Socket control, ref Socket capture)
{
    const rc = trusted!zmq_proxy_steerable(
        frontend.handle, backend.handle, capture.handle, control.handle);
    if (rc == -1) throw new ZmqException;
}

@system unittest
{
    import core.thread;
    auto t = new Thread(() {
        auto frontend = Socket(SocketType.router);
        frontend.bind("inproc://zmqd_steerableProxy_unittest_fe");
        auto backend  = Socket(SocketType.dealer);
        backend.bind("inproc://zmqd_steerableProxy_unittest_be");
        auto controllee = Socket(SocketType.pair);
        controllee.bind("inproc://zmqd_steerableProxy_unittest_ctl");
        steerableProxy(frontend, backend, controllee);
    });
    t.start();
    auto client = Socket(SocketType.req);
    client.connect("inproc://zmqd_steerableProxy_unittest_fe");
    auto server  = Socket(SocketType.rep);
    server.connect("inproc://zmqd_steerableProxy_unittest_be");
    auto controller = Socket(SocketType.pair);
    controller.connect("inproc://zmqd_steerableProxy_unittest_ctl");

    auto cf = Frame(1);
    cf.data[0] = 86;
    client.send(cf);
    auto sf = Frame();
    server.receive(sf);
    assert(sf.size == 1 && sf.data[0] == 86);
    sf.data[0] = 87;
    server.send(sf);
    client.receive(cf);
    assert(cf.size == 1 && cf.data[0] == 87);

    controller.send("TERMINATE");
    t.join();
}

@system unittest
{
    import core.thread;
    auto t = new Thread(() {
        auto frontend = Socket(SocketType.pull);
        frontend.bind("inproc://zmqd_steerableProxy2_unittest_fe");
        auto backend  = Socket(SocketType.push);
        backend.bind("inproc://zmqd_steerableProxy2_unittest_be");
        auto controllee = Socket(SocketType.pair);
        controllee.bind("inproc://zmqd_steerableProxy2_unittest_ctl");
        auto capture = Socket(SocketType.push);
        capture.bind("inproc://zmqd_steerableProxy2_unittest_cpt");
        steerableProxy(frontend, backend, controllee, capture);
    });
    t.start();
    auto client = Socket(SocketType.push);
    client.connect("inproc://zmqd_steerableProxy2_unittest_fe");
    auto server  = Socket(SocketType.pull);
    server.connect("inproc://zmqd_steerableProxy2_unittest_be");
    auto controller = Socket(SocketType.pair);
    controller.connect("inproc://zmqd_steerableProxy2_unittest_ctl");
    auto capturer = Socket(SocketType.pull);
    capturer.connect("inproc://zmqd_steerableProxy2_unittest_cpt");

    auto cf = Frame(1);
    cf.data[0] = 86;
    client.send(cf);
    auto sf = Frame();
    server.receive(sf);
    assert(sf.size == 1 && sf.data[0] == 86);
    auto pf = Frame();
    capturer.receive(pf);
    assert(pf.size == 1 && pf.data[0] == 86);

    controller.send("TERMINATE");
    t.join();
}


deprecated("zmqd.poll() has a new signature as of v0.4")
uint poll(zmq_pollitem_t[] items, Duration timeout = Duration.max)
{
    import std.conv: to;
    const n = trusted!zmq_poll(
        items.ptr,
        to!int(items.length),
        timeout == Duration.max ? -1 : to!int(timeout.total!"msecs"()));
    if (n < 0) throw new ZmqException;
    return cast(uint) n;
}


/**
Input/output multiplexing.

The $(D timeout) parameter may have the special value
$(COREF time,Duration.max), which in this context specifies an infinite
duration.  This is translated to an argument value of -1 in the C API.

Returns:
    The number of $(REF PollItem) structures with events signalled in
    $(REF PollItem.returnedEvents), or 0 if no events have been signalled.
Throws:
    $(REF ZmqException) if $(ZMQ) reports an error.
Corresponds_to:
    $(ZMQREF zmq_poll())
*/
uint poll(PollItem[] items, Duration timeout = Duration.max) @trusted
{
    // Here we use a trick where we pretend the array of PollItems is
    // actually an array of zmq_pollitem_t, to avoid an unnecessary
    // allocation.  For this to work, PollItem must have the exact
    // same size as zmq_pollitem_t.
    static assert (PollItem.sizeof == zmq_pollitem_t.sizeof);

    import std.conv: to;
    const n = zmq_poll(
        cast(zmq_pollitem_t*) items.ptr,
        to!int(items.length),
        timeout == Duration.max ? -1 : to!int(timeout.total!"msecs"()));
    if (n < 0) throw new ZmqException;
    return cast(uint) n;
}


///
@system unittest
{
    auto socket1 = zmqd.Socket(zmqd.SocketType.pull);
    socket1.bind("inproc://zmqd_poll_example");

    import std.socket;
    auto socket2 = new std.socket.Socket(
        AddressFamily.INET,
        std.socket.SocketType.DGRAM);
    socket2.bind(new InternetAddress(InternetAddress.ADDR_ANY, 5678));

    auto socket3 = zmqd.Socket(zmqd.SocketType.push);
    socket3.connect("inproc://zmqd_poll_example");
    socket3.send("test");

    import core.thread: Thread;
    Thread.sleep(10.msecs);

    auto items = [
        PollItem(socket1, PollFlags.pollIn),
        PollItem(socket2, PollFlags.pollIn | PollFlags.pollOut),
        PollItem(socket3, PollFlags.pollIn),
    ];

    const n = poll(items, 100.msecs);
    assert (n == 2);
    assert (items[0].returnedEvents == PollFlags.pollIn);
    assert (items[1].returnedEvents == PollFlags.pollOut);
    assert (items[2].returnedEvents == 0);
    socket2.close();
}


/**
$(FREF poll) event flags.

These are described in the $(ZMQREF zmq_poll()) manual.
*/
enum PollFlags
{
    pollIn = ZMQ_POLLIN,    /// Corresponds to $(D ZMQ_POLLIN)
    pollOut = ZMQ_POLLOUT,  /// Corresponds to $(D ZMQ_POLLOUT)
    pollErr = ZMQ_POLLERR,  /// Corresponds to $(D ZMQ_POLLERR)
}


/++
A structure that specifies a socket to be monitored by $(FREF poll) as well
as the events to poll for, and, when $(FREF poll) returns, the events that
occurred.

Warning:
    $(D PollItem) objects do not store $(STDREF socket,Socket) references,
    only the corresponding native file descriptors.  This means that the
    references have to be stored elsewhere, or the objects may be garbage
    collected, invalidating the sockets before or while $(FREF poll) executes.
    ---
    // Not OK
    auto p1 = PollItem(new std.socket.Socket(/*...*/), PollFlags.pollIn);

    // OK
    auto s = new std.socket.Socket(/*...*/);
    auto p2 = PollItem(s, PollFlags.pollIn);
    ---
Corresponds_to:
    $(D $(ZMQAPI zmq_poll,zmq_pollitem_t))
+/
struct PollItem
{
    /// Constructs a $(REF PollItem) for monitoring a $(ZMQ) socket.
    this(ref zmqd.Socket socket, PollFlags events) nothrow
    {
        m_pollItem = zmq_pollitem_t(socket.handle, 0, cast(short) events, 0);
    }

    import std.socket;
    /**
    Constructs a $(REF PollItem) for monitoring a standard socket referenced
    by a $(STDREF socket,Socket).
    */
    this(std.socket.Socket socket, PollFlags events) @system
    {
        this(socket.handle, events);
    }

    /**
    Constructs a $(REF PollItem) for monitoring a standard socket referenced
    by a native file descriptor.
    */
    this(FD fd, PollFlags events) pure nothrow
    {
        m_pollItem = zmq_pollitem_t(null, fd, cast(short) events, 0);
    }

    /**
    Requested events.

    Corresponds_to:
        $(D $(ZMQAPI zmq_poll,zmq_pollitem_t.events))
    */
    @property void requestedEvents(PollFlags events) pure nothrow
    {
        m_pollItem.events = cast(short) events;
    }

    /// ditto
    @property PollFlags requestedEvents() const pure nothrow
    {
        return cast(typeof(return)) m_pollItem.events;
    }

    /**
    Returned events.

    Corresponds_to:
        $(D $(ZMQAPI zmq_poll,zmq_pollitem_t.revents))
    */
    @property PollFlags returnedEvents() const pure nothrow
    {
        return cast(typeof(return)) m_pollItem.revents;
    }

private:
    zmq_pollitem_t m_pollItem;
}


/**
An object that encapsulates a $(ZMQ) message frame.

This $(D struct) is a wrapper around a $(D zmq_msg_t) object.
A default-initialized $(D Frame) is not a valid $(ZMQ) message frame; it
should always be explicitly initialized upon construction using
$(FREF _Frame.opCall).  Alternatively, it may be initialized later with
$(FREF _Frame.rebuild).
---
Frame msg1;                 // Invalid frame
auto msg2 = Frame();        // Empty frame
auto msg3 = Frame(1024);    // 1K frame
msg1.rebuild(2048);         // msg1 now has size 2K
msg2.rebuild(2048);         // ...and so does msg2
---
When a $(D Frame) goes out of scope, $(ZMQREF zmq_msg_close()) is
called on the underlying $(D zmq_msg_t).

A $(D Frame) cannot be copied by normal assignment; use $(FREF _Frame.copy)
for this.
*/
struct Frame
{
@safe:
    /**
    Initializes an empty $(ZMQ) message frame.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_init())
    */
    static Frame opCall()
    {
        Frame f;
        f.init();
        return f;
    }

    ///
    unittest
    {
        auto msg = Frame();
        assert(msg.size == 0);
    }

    /** $(DDOC_ANCHOR Frame.opCall_size)
    Initializes a $(ZMQ) message frame of a specified size.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_init_size())
    */
    static Frame opCall(size_t size)
    {
        Frame m;
        m.init(size);
        return m;
    }

    ///
    unittest
    {
        auto msg = Frame(123);
        assert(msg.size == 123);
    }

    /** $(DDOC_ANCHOR Frame.opCall_data)
    Initializes a $(ZMQ) message frame from a supplied buffer.

    Warning:
        Some care must be taken when using this function, as $(ZMQ) expects
        to take full ownership of the supplied buffer.  Client code should
        therefore avoid retaining any references to it, including slices that
        contain, overlap with or are contained in $(D data).
        $(ZMQ) makes no guarantee that the buffer is not modified,
        and it does not specify when the buffer is released.

        An additional complication is caused by the fact that most arrays in D
        are owned by the garbage collector.  This is solved by adding the array
        pointer as a new garbage collector root before passing it to
        $(ZMQREF zmq_msg_init_data()), thus preventing the GC from collecting
        it.  The root is then removed again in the deallocator callback
        function which is called by $(ZMQ) when it no longer requires
        the buffer, thus allowing the GC to collect it.
    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_init_data())
    */
    static Frame opCall(ubyte[] data)
    {
        Frame m;
        m.init(data);
        return m;
    }

    ///
    unittest
    {
        auto buf = new ubyte[123];
        auto msg = Frame(buf);
        assert(msg.size == buf.length);
        assert(msg.data.ptr == buf.ptr);
    }

    /**
    Reinitializes the Frame object as an empty message.

    This function will first call $(FREF Frame.close) to release the
    resources associated with the message frame, and then it will
    initialize it anew, exactly as if it were constructed  with
    $(D $(LINK2 #Frame.opCall,Frame())).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_close()) followed by $(ZMQREF zmq_msg_init())
    */
    void rebuild()
    {
        close();
        init();
    }

    ///
    unittest
    {
        auto msg = Frame(256);
        assert (msg.size == 256);
        msg.rebuild();
        assert (msg.size == 0);
    }

    /**
    Reinitializes the Frame object to a specified size.

    This function will first call $(FREF Frame.close) to release the
    resources associated with the message frame, and then it will
    initialize it anew, exactly as if it were constructed  with
    $(D $(LINK2 #Frame.opCall_size,Frame(size))).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_close()) followed by $(ZMQREF zmq_msg_init_size()).
    */
    void rebuild(size_t size)
    {
        close();
        init(size);
    }

    ///
    unittest
    {
        auto msg = Frame(256);
        assert (msg.size == 256);
        msg.rebuild(1024);
        assert (msg.size == 1024);
    }

    /**
    Reinitializes the Frame object from a supplied buffer.

    This function will first call $(FREF Frame.close) to release the
    resources associated with the message frame, and then it will
    initialize it anew, exactly as if it were constructed  with
    $(D $(LINK2 #Frame.opCall_data,Frame(data))).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_close()) followed by $(ZMQREF zmq_msg_init_data()).
    */
    void rebuild(ubyte[] data)
    {
        close();
        init(data);
    }

    ///
    unittest
    {
        auto msg = Frame(256);
        assert (msg.size == 256);
        auto buf = new ubyte[123];
        msg.rebuild(buf);
        assert(msg.size == buf.length);
        assert(msg.data.ptr == buf.ptr);
    }

    @disable this(this);

    /**
    Releases the $(ZMQ) message frame when the $(D Frame) is destroyed.

    This destructor never throws, which means that any errors will go
    undetected.  If this is undesirable, call $(FREF Frame.close) before
    the $(D Frame) is destroyed.

    Corresponds_to:
        $(ZMQREF zmq_msg_close())
    */
    ~this() nothrow
    {
        if (m_initialized) {
            immutable rc = trusted!zmq_msg_close(&m_msg);
            assert(rc == 0, "zmq_msg_close failed: Invalid message frame");
        }
    }

    /**
    Releases the $(ZMQ) message frame.

    Note that the frame will be automatically released when the $(D Frame)
    object is destroyed, so it is often not necessary to call this method
    manually.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_close())
    */
    void close()
    {
        if (m_initialized) {
            if (trusted!zmq_msg_close(&m_msg) != 0) {
                throw new ZmqException;
            }
            m_initialized = false;
        }
    }

    /**
    Copies frame content to another message frame.

    $(D copy()) returns a new $(D Frame) object, while $(D copyTo(dest))
    copies the contents of this $(D Frame) into $(D dest).  $(D dest) must
    be a valid (i.e. initialized) $(D Frame).

    Warning:
        These functions may not do what you think they do.  Please refer
        to $(ZMQAPI zmq_msg_copy(),the $(ZMQ) manual) for details.
    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_copy())
    */
    Frame copy()
        in { assert(m_initialized); }
        body
    {
        auto cp = Frame();
        copyTo(cp);
        return cp;
    }

    /// ditto
    void copyTo(ref Frame dest)
        in { assert(m_initialized); }
        body
    {
        if (trusted!zmq_msg_copy(&dest.m_msg, &m_msg) != 0) {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        import std.string: representation;
        auto msg1 = Frame(3);
        msg1.data[] = "foo".representation;
        auto msg2 = msg1.copy();
        assert (msg2.data.asString() == "foo");
    }

    /**
    Moves frame content to another message frame.

    $(D move()) returns a new $(D Frame) object, while $(D moveTo(dest))
    moves the contents of this $(D Frame) to $(D dest).  $(D dest) must
    be a valid (i.e. initialized) $(D Frame).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_msg_move())
    */
    Frame move()
        in { assert(m_initialized); }
        body
    {
        auto m = Frame();
        moveTo(m);
        return m;
    }

    /// ditto
    void moveTo(ref Frame dest)
        in { assert(m_initialized); }
        body
    {
        if (trusted!zmq_msg_move(&dest.m_msg, &m_msg) != 0) {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        import std.string: representation;
        auto msg1 = Frame(3);
        msg1.data[] = "foo".representation;
        auto msg2 = msg1.move();
        assert (msg1.size == 0);
        assert (msg2.data.asString() == "foo");
    }

    /**
    The message frame content size in bytes.

    Corresponds_to:
        $(ZMQREF zmq_msg_size())
    */
    @property size_t size() nothrow
        in { assert(m_initialized); }
        body
    {
        return trusted!zmq_msg_size(&m_msg);
    }

    ///
    unittest
    {
        auto msg = Frame(123);
        assert(msg.size == 123);
    }

    /**
    Retrieves the message frame content.

    Corresponds_to:
        $(ZMQREF zmq_msg_data())
    */
    @property ubyte[] data() @trusted nothrow
        in { assert(m_initialized); }
        body
    {
        return (cast(ubyte*) zmq_msg_data(&m_msg))[0 .. size];
    }

    ///
    unittest
    {
        import std.string: representation;
        auto msg = Frame(3);
        assert(msg.data.length == 3);
        msg.data[] = "foo".representation; // Slice operator -> array copy.
        assert(msg.data.asString() == "foo");
    }

    /**
    Whether there are more message frames to retrieve.

    Corresponds_to:
        $(ZMQREF zmq_msg_more())
    */
    @property bool more() nothrow
        in { assert(m_initialized); }
        body
    {
        return !!trusted!zmq_msg_more(&m_msg);
    }

    /**
    A pointer to the underlying $(D zmq_msg_t).
    */
    @property inout(zmq_msg_t)* handle() inout pure nothrow
    {
        return &m_msg;
    }

private:
    private void init()
        in { assert (!m_initialized); }
        out { assert (m_initialized); }
        body
    {
        if (trusted!zmq_msg_init(&m_msg) != 0) {
            throw new ZmqException;
        }
        m_initialized = true;
    }

    private void init(size_t size)
        in { assert (!m_initialized); }
        out { assert (m_initialized); }
        body
    {
        if (trusted!zmq_msg_init_size(&m_msg, size) != 0) {
            throw new ZmqException;
        }
        m_initialized = true;
    }

    private void init(ubyte[] data) @trusted
        in { assert (!m_initialized); }
        out { assert (m_initialized); }
        body
    {
        import core.memory;
        static extern(C) zmqd_Frame_init_data_free(void* dataPtr, void* block)
            @trusted nothrow
        {
            GC.removeRoot(dataPtr);
            GC.clrAttr(block, GC.BlkAttr.NO_MOVE);
        }

        GC.addRoot(data.ptr);
        scope(failure) GC.removeRoot(data.ptr);

        auto block = GC.addrOf(data.ptr);
        immutable movable = block && !(GC.getAttr(block) & GC.BlkAttr.NO_MOVE);
        GC.setAttr(block, GC.BlkAttr.NO_MOVE);
        scope(failure) if (movable) GC.clrAttr(block, GC.BlkAttr.NO_MOVE);

        if (trusted!zmq_msg_init_data(&m_msg, data.ptr, data.length,
                                      &zmqd_Frame_init_data_free, block) != 0) {
            throw new ZmqException;
        }
        m_initialized = true;
    }

    bool m_initialized;
    zmq_msg_t m_msg;
}

unittest
{
    const url = uniqueUrl("inproc");
    auto s1 = Socket(SocketType.pair);
    auto s2 = Socket(SocketType.pair);
    s1.bind(url);
    s2.connect(url);

    auto m1a = Frame(123);
    m1a.data[] = 'a';
    s1.send(m1a);
    auto m2a = Frame();
    s2.receive(m2a);
    assert(m2a.size == 123);
    foreach (e; m2a.data) assert(e == 'a');

    auto m1b = Frame(10);
    m1b.data[] = 'b';
    s1.send(m1b);
    auto m2b = Frame();
    s2.receive(m2b);
    assert(m2b.size == 10);
    foreach (e; m2b.data) assert(e == 'b');
}

deprecated("zmqd.Message has been renamed to zmqd.Frame") alias Message = Frame;


/**
A global context which is used by default by all sockets, unless they are
explicitly constructed with a different context.

The $(ZMQ) Guide $(LINK2 http://zguide.zeromq.org/page:all#Getting-the-Context-Right,
has the following to say) about context creation:
$(QUOTE
    You should create and use exactly one context in your process.
    [$(LDOTS)] If at runtime a process has two contexts, these are
    like separate $(ZMQ) instances. If that's explicitly what you
    want, OK, but otherwise remember: $(EM Do one $(D zmq_ctx_new())
    at the start of your main line code, and one $(D zmq_ctx_destroy())
    at the end.)
)
By using $(D defaultContext()), this is exactly what you achieve.  The
context is created the first time the function is called, and is
automatically destroyed when the program ends.

This function is thread safe.

Throws:
    $(REF ZmqException) if $(ZMQ) reports an error.
See_also:
    $(REF Context)
*/
Context defaultContext() @trusted
{
    // For future reference: This is the low-lock singleton pattern. See:
    // http://davesdprogramming.wordpress.com/2013/05/06/low-lock-singletons/
    static bool instantiated;
    __gshared Context ctx;
    if (!instantiated) {
        synchronized {
            if (!ctx.initialized) {
                ctx = Context();
            }
            instantiated = true;
        }
    }
    return ctx;
}

@system unittest
{
    import core.thread;
    Context c1, c2;
    auto t = new Thread(() { c1 = defaultContext(); });
    t.start();
    c2 = defaultContext();
    t.join();
    assert(c1.handle !is null);
    assert(c1.handle == c2.handle);
}


/**
An object that encapsulates a $(ZMQ) context.

In most programs, it is not necessary to use this type directly,
as $(REF Socket) will use a default global context if not explicitly
provided with one.  See $(FREF defaultContext) for details.

A default-initialized $(D Context) is not a valid $(ZMQ) context; it
must always be explicitly initialized with $(FREF _Context.opCall):
---
Context ctx;        // Not a valid context yet
ctx = Context();    // ...but now it is.
---
$(D Context) objects can be passed around by value, and two copies will
refer to the same context.  The underlying context is managed using
reference counting, so that when the last copy of a $(D Context) goes
out of scope, the context is automatically destroyed.  The reference
counting is performed in a thread safe manner, so that the same context
can be shared between multiple threads.  ($(ZMQ) guarantees the thread
safety of other context operations.)

See_also:
    $(FREF defaultContext)
*/
struct Context
{
@safe:
    /**
    Creates a new $(ZMQ) context.

    Returns:
        A $(REF Context) object that encapsulates the new context.
    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_ctx_new())
    */
    static Context opCall() @trusted // because of the cast
    {
        if (auto c = trusted!zmq_ctx_new()) {
            Context ctx;
            // Casting from/to shared is OK since ZMQ contexts are thread safe.
            static Exception release(shared(void)* ptr) @trusted nothrow
            {
                return zmq_ctx_term(cast(void*) ptr) == 0
                    ? null
                    : new ZmqException;
            }
            ctx.m_resource = SharedResource(cast(shared) c, &release);
            return ctx;
        } else {
            throw new ZmqException;
        }
    }

    ///
    unittest
    {
        auto ctx = Context();
        assert (ctx.initialized);
    }

    /**
    Detaches from the $(ZMQ) context.

    If this is the last reference to the context, it will be destroyed with
    $(ZMQREF zmq_ctx_destroy()).

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    */
    void detach()
    {
        m_resource.detach();
    }

    ///
    unittest
    {
        auto ctx = Context();
        assert (ctx.initialized);
        ctx.detach();
        assert (!ctx.initialized);
    }

    /**
    The number of I/O threads.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_ctx_get()) and $(ZMQREF zmq_ctx_set()) with
        $(D ZMQ_IO_THREADS).
    */
    @property int ioThreads()
    {
        return getOption(ZMQ_IO_THREADS);
    }

    /// ditto
    @property void ioThreads(int value)
    {
        setOption(ZMQ_IO_THREADS, value);
    }

    ///
    unittest
    {
        auto ctx = Context();
        ctx.ioThreads = 3;
        assert (ctx.ioThreads == 3);
    }

    /**
    The maximum number of sockets.

    Throws:
        $(REF ZmqException) if $(ZMQ) reports an error.
    Corresponds_to:
        $(ZMQREF zmq_ctx_get()) and $(ZMQREF zmq_ctx_set()) with
        $(D ZMQ_MAX_SOCKETS).
    */
    @property int maxSockets()
    {
        return getOption(ZMQ_MAX_SOCKETS);
    }

    /// ditto
    @property void maxSockets(int value)
    {
        setOption(ZMQ_MAX_SOCKETS, value);
    }

    ///
    unittest
    {
        auto ctx = Context();
        ctx.maxSockets = 512;
        assert (ctx.maxSockets == 512);
    }

    /**
    The $(D void*) pointer used by the underlying C API to refer to the context.

    If the object has not been initialized, this function returns $(D null).
    */
    @property inout(void)* handle() inout @trusted pure nothrow
    {
        // ZMQ contexts are thread safe, so casting away shared is OK.
        return cast(typeof(return)) m_resource.handle;
    }

    /**
    Whether this $(REF Context) object has been _initialized, i.e. whether it
    refers to a valid $(ZMQ) context.
    */
    @property bool initialized() const pure nothrow
    {
        return m_resource.handle != null;
    }

    ///
    unittest
    {
        Context ctx;
        assert (!ctx.initialized);
        ctx = Context();
        assert (ctx.initialized);
        ctx.detach();
        assert (!ctx.initialized);
    }

private:
    int getOption(int option)
    {
        immutable value = trusted!zmq_ctx_get(this.handle, option);
        if (value < 0) {
            throw new ZmqException;
        }
        return value;
    }

    void setOption(int option, int value)
    {
        if (trusted!zmq_ctx_set(this.handle, option, value) != 0) {
            throw new ZmqException;
        }
    }

    SharedResource m_resource;
}


/**
Socket event types.

These are used together with $(FREF Socket.monitor), and are described
in the $(ZMQREF zmq_socket_monitor()) reference.
*/
enum EventType
{
    connected       = ZMQ_EVENT_CONNECTED,      /// Corresponds to $(D ZMQ_EVENT_CONNECTED).
    connectDelayed  = ZMQ_EVENT_CONNECT_DELAYED,/// Corresponds to $(D ZMQ_EVENT_CONNECT_DELAYED).
    connectRetried  = ZMQ_EVENT_CONNECT_RETRIED,/// Corresponds to $(D ZMQ_EVENT_CONNECT_RETRIED).
    listening       = ZMQ_EVENT_LISTENING,      /// Corresponds to $(D ZMQ_EVENT_LISTENING).
    bindFailed      = ZMQ_EVENT_BIND_FAILED,    /// Corresponds to $(D ZMQ_EVENT_BIND_FAILED).
    accepted        = ZMQ_EVENT_ACCEPTED,       /// Corresponds to $(D ZMQ_EVENT_ACCEPTED).
    acceptFailed    = ZMQ_EVENT_ACCEPT_FAILED,  /// Corresponds to $(D ZMQ_EVENT_ACCEPT_FAILED).
    closed          = ZMQ_EVENT_CLOSED,         /// Corresponds to $(D ZMQ_EVENT_CLOSED).
    closeFailed     = ZMQ_EVENT_CLOSE_FAILED,   /// Corresponds to $(D ZMQ_EVENT_CLOSE_FAILED).
    disconnected    = ZMQ_EVENT_DISCONNECTED,   /// Corresponds to $(D ZMQ_EVENT_DISCONNECTED).
    all             = ZMQ_EVENT_ALL             /// Corresponds to $(D ZMQ_EVENT_ALL).
}


/**
Receives a message on the given socket and interprets it as a socket
state change event.

$(D socket) must be a PAIR socket which is connected to an endpoint
created via a $(FREF Socket.monitor) call.  $(D receiveEvent()) receives
one message on the socket, parses its contents according to the
specification in the $(ZMQREF zmq_socket_monitor()) reference,
and returns the event information as an $(REF Event) object.

Throws:
    $(REF ZmqException) if $(ZMQ) reports an error.$(BR)
    $(REF InvalidEventException) if the received message could not
    be interpreted as an event message.
See_also:
    $(FREF Socket.monitor), for monitoring socket state changes.
*/
Event receiveEvent(ref Socket socket) @system
{
    // The monitor event message format underwent some changes between ZMQ
    // versions 3.2, 3.3 (unreleased) and 4.0.  Furthermore, the zmq_event_t
    // type was removed as of ZMQ 4.1.  We try to support all versions >= 3.2.
    immutable ver = zmqVersion();
    immutable usePackedData = ver.major >= 4;
    immutable useNewLayout = ZMQ_MAKE_VERSION(ver.major, ver.minor, ver.patch)
        >= ZMQ_MAKE_VERSION(3, 3, 0);
    assert (useNewLayout || !usePackedData);

    struct OldEventStruct {
        int event;
        const(char*) addr;
        int value;
    }
    struct NewEventStruct {
        ushort event;
        int value;
    }
    immutable eventFrameSize =
        usePackedData ? (ushort.sizeof + int.sizeof)
                      : (useNewLayout ? NewEventStruct.sizeof : OldEventStruct.sizeof);

    auto eventFrame = Frame();
    if (socket.receive(eventFrame) != eventFrameSize) {
        throw new InvalidEventException;
    }
    const data = eventFrame.data.ptr;
    try {
        import std.conv: to;
        EventType event;
        int value;
        string addr;
        if (useNewLayout) {
            if (usePackedData) {
                event = to!EventType(*(cast(const(ushort)*) data));
                value = *(cast(const(int)*) data + ushort.sizeof);
            } else {
                const eventStruct = cast(const(NewEventStruct)*) data;
                event = to!EventType(eventStruct.event);
                value = eventStruct.value;
            }
            auto addrFrame = Frame();
            socket.receive(addrFrame);
            addr = (cast(char[]) addrFrame.data).idup;
        } else {
            const eventStruct = cast(const(OldEventStruct)*) data;
            event = to!EventType(eventStruct.event);
            value = eventStruct.value;
            addr = eventStruct.addr !is null
                ? to!string(eventStruct.addr)
                : null;
        }
        return Event(event, addr, value);
    } catch (Exception e) {
        // Any exception thrown within the try block signifies that there
        // is something wrong with the event message.
        throw new InvalidEventException;
    }
}

// TODO: Remove version(Posix) and change to INPROC when updating to ZMQ 4.1.
//       IPC does not work on Windows, and unbind() does not work with INPROC.
//       See: https://github.com/zeromq/libzmq/issues/949
version (Posix) @system unittest
{
    Event[] events;
    void eventCollector()
    {
        auto coll = Socket(SocketType.pair);
        coll.connect("inproc://zmqd_receiveEvent_unittest_monitor");
        do {
            events ~= receiveEvent(coll);
        } while (events[$-1].type != EventType.closed);
    }
    import core.thread;
    auto collector = new Thread(&eventCollector);
    collector.start();

    static void eventGenerator()
    {
        auto sck1 = Socket(SocketType.pair);
        sck1.monitor("inproc://zmqd_receiveEvent_unittest_monitor");
        sck1.bind("ipc://zmqd_receiveEvent_unittest");
        import core.time;
        Thread.sleep(100.msecs);
        auto sck2 = Socket(SocketType.pair);
        sck2.connect("ipc://zmqd_receiveEvent_unittest");
        Thread.sleep(100.msecs);
        sck2.disconnect("ipc://zmqd_receiveEvent_unittest");
        Thread.sleep(100.msecs);
        sck1.unbind("ipc://zmqd_receiveEvent_unittest");
    }
    eventGenerator();
    collector.join();
    assert (events.length == 3);
    foreach (ev; events) {
        assert (ev.address == "ipc://zmqd_receiveEvent_unittest");
    }
    assert (events[0].type == EventType.listening);
    assert (events[1].type == EventType.accepted);
    assert (events[2].type == EventType.closed);
    import std.exception;
    assertNotThrown!Error(events[0].fd);
    assertThrown!Error(events[0].errno);
    assertThrown!Error(events[0].interval);
}


/**
Information about a socket state change.

Corresponds_to:
    $(ZMQAPI zmq_socket_monitor,$(D zmq_event_t))
See_also:
    $(FREF receiveEvent)
*/
struct Event
{
    /**
    The event type.

    Corresponds_to:
        $(D zmq_event_t.event)
    */
    @property EventType type() const pure nothrow
    {
        return m_type;
    }

    /**
    The peer address.

    Corresponds_to:
        $(D zmq_event_t.data.xyz.addr), where $(D xyz) is the event-specific union.
    */
    @property string address() const pure nothrow
    {
        return m_address;
    }

    /**
    The socket file descriptor.

    This property function may only be called if $(REF Event.type) is one of:
    $(D connected), $(D listening), $(D accepted), $(D closed) or $(D disonnected).

    Throws:
        $(D Error) if the property is called for a wrong event type.
    Corresponds_to:
        $(D zmq_event_t.data.xyz.addr), where $(D xyz) is the event-specific union.
    */
    @property FD fd() const pure nothrow
    {
        final switch (m_type) {
            case EventType.connected     :
            case EventType.listening     :
            case EventType.accepted      :
            case EventType.closed        :
            case EventType.disconnected  : return cast(typeof(return)) m_value;
            case EventType.connectDelayed:
            case EventType.connectRetried:
            case EventType.bindFailed    :
            case EventType.acceptFailed  :
            case EventType.closeFailed   : throw invalidProperty();
            case EventType.all           :
        }
        assert (false);
    }

    /**
    The $(D errno) code for the error which triggered the event.

    This property function may only be called if $(REF Event.type) is either
    $(D bindFailed), $(D acceptFailed) or $(D closeFailed).

    Throws:
        $(D Error) if the property is called for a wrong event type.
    Corresponds_to:
        $(D zmq_event_t.data.xyz.addr), where $(D xyz) is the event-specific union.
    */
    @property int errno() const pure nothrow
    {
        final switch (m_type) {
            case EventType.bindFailed    :
            case EventType.acceptFailed  :
            case EventType.closeFailed   : return m_value;
            case EventType.connected     :
            case EventType.connectDelayed:
            case EventType.connectRetried:
            case EventType.listening     :
            case EventType.accepted      :
            case EventType.closed        :
            case EventType.disconnected  : throw invalidProperty();
            case EventType.all           :
        }
        assert (false);
    }

    /**
    The reconnect interval.

    This property function may only be called if $(REF Event.type) is
    $(D connectRetried).

    Throws:
        $(D Error) if the property is called for a wrong event type.
    Corresponds_to:
        $(D zmq_event_t.data.connect_retried.interval)
    */
    @property Duration interval() const pure nothrow
    {
        final switch (m_type) {
            case EventType.connectRetried: return m_value.msecs;
            case EventType.connected     :
            case EventType.connectDelayed:
            case EventType.listening     :
            case EventType.bindFailed    :
            case EventType.accepted      :
            case EventType.acceptFailed  :
            case EventType.closed        :
            case EventType.closeFailed   :
            case EventType.disconnected  : throw invalidProperty();
            case EventType.all           :
        }
        assert (false);
    }

private:
    this(EventType type, string address, int value) pure nothrow
    {
        m_type = type;
        m_address = address;
        m_value = value;
    }

    Error invalidProperty(string name = __FUNCTION__)() const pure nothrow
    {
        try {
            import std.conv: text;
            return new Error(text("Property '", name,
                                  "' not available for event type '",
                                  m_type, "'"));
        } catch (Exception e) {
            assert(false);
        }
    }

    EventType m_type;
    string m_address;
    int m_value;
}


version (WithLibsodium) {

/**
Encodes a binary key as Z85 printable text.

$(D dest) must be an array whose length is at least $(D 5*data.length/4 + 1),
which will be used to store the return value plus a terminating zero byte.
If $(D dest) is omitted, a new array will be created.

Returns:
    An array of size $(D 5*data.length/4) which contains the Z85-encoded text,
    excluding the terminating zero byte.  This will be a slice of $(D dest) if
    it is provided.
Throws:
    $(COREF exception,RangeError) if $(D dest) is given but is too small.$(BR)
    $(REF ZmqException) if $(ZMQ) reports an error (i.e., if data.length is not
    a multiple of 4).
Corresponds_to:
    $(ZMQREF zmq_z85_encode())
*/
char[] z85Encode(ubyte[] data, char[] dest)
// TODO: Make data const when we update to ZMQ 4.1
{
    import core.exception: RangeError;
    immutable len = 5 * data.length / 4;
    if (dest.length < len+1) throw new RangeError;
    if (trusted!zmq_z85_encode(dest.ptr, data.ptr, data.length) == null) {
        throw new ZmqException;
    }
    return dest[0 .. len];
}

/// ditto
char[] z85Encode(ubyte[] data)
{
    return z85Encode(data, new char[5*data.length/4 + 1]);
}

@system unittest // @system because of assertThrown
{
    // TODO: Make data immutable when we update to ZMQ 4.1
    auto data = cast(ubyte[])[0x86, 0x4f, 0xd2, 0x6f, 0xb5, 0x59, 0xf7, 0x5b];
    immutable encoded = "HelloWorld";
    assert (z85Encode(data) == encoded);

    auto buffer = new char[11];
    auto result = z85Encode(data, buffer);
    assert (result == encoded);
    assert (buffer.ptr == result.ptr);

    import core.exception: RangeError;
    import std.exception: assertThrown;
    assertThrown!RangeError(z85Encode(data, new char[10]));
    assertThrown!ZmqException(z85Encode(cast(ubyte[]) [ 1, 2, 3, 4, 5]));
}


/**
Decodes a binary key from Z85 printable text.

$(D dest) must be an array whose length is at least $(D 4*data.length/5),
which will be used to store the return value.
If $(D dest) is omitted, a new array will be created.

Note that $(ZMQREF zmq_z85_decode()) expects a zero-terminated string, so a zero
byte will be appended to $(D text) if it does not contain one already.  However,
this may trigger a (possibly unwanted) GC allocation.  To avoid this, either
make sure that the last character in $(D text) is $(D '\0'), or use
$(OBJREF assumeSafeAppend) on the array before calling this function.

Returns:
    An array of size $(D 4*data.length/5) which contains the decoded data.
    This will be a slice of $(D dest) if it is provided.
Throws:
    $(COREF exception,RangeError) if $(D dest) is given but is too small.$(BR)
    $(REF ZmqException) if $(ZMQ) reports an error (i.e., if data.length is not
    a multiple of 5).
Corresponds_to:
    $(ZMQREF zmq_z85_decode())
*/
ubyte[] z85Decode(char[] text, ubyte[] dest)
// TODO: Make text const when we update to ZMQ 4.1
{
    import core.exception: RangeError;
    immutable len = 4 * text.length/5;
    if (dest.length < len) throw new RangeError;
    if (text[$-1] != '\0') text ~= '\0';
    if (trusted!zmq_z85_decode(dest.ptr, text.ptr) == null) {
        throw new ZmqException;
    }
    return dest[0 .. len];
}

/// ditto
ubyte[] z85Decode(char[] text)
{
    return z85Decode(text, new ubyte[4*text.length/5]);
}

@system unittest // @system because of assertThrown
{
    // TODO: Make data immutable when we update to ZMQ 4.1
    auto text = "HelloWorld".dup;
    immutable decoded = cast(ubyte[])[0x86, 0x4f, 0xd2, 0x6f, 0xb5, 0x59, 0xf7, 0x5b];
    assert (z85Decode(text) == decoded);
    assert (z85Decode(text~'\0') == decoded);

    auto buffer = new ubyte[8];
    auto result = z85Decode(text, buffer);
    assert (result == decoded);
    assert (buffer.ptr == result.ptr);

    import core.exception: RangeError;
    import std.exception: assertThrown;
    assertThrown!RangeError(z85Decode(text, new ubyte[7]));
    assertThrown!ZmqException(z85Decode("SizeNotAMultipleOf5".dup));
}


/**
Generates a new CURVE key pair.

To avoid a memory allocation, preallocated buffers may optionally be supplied
for the two keys.  Each of these must have a length of at least 41 bytes, enough
for a 40-character Z85-encoded key plus a terminating zero byte.  If either
buffer is omitted/$(D null), a new one will be created.

Returns:
    A tuple that contains the two keys.  Each of these will have a length of
    40 characters, and will be slices of the input buffers if such have been
    provided.
Throws:
    $(COREF exception,RangeError) if $(D publicKeyBuf) or $(D secretKeyBuf) are
        not $(D null) but have a length of less than 41 characters.$(BR)
    $(REF ZmqException) if $(ZMQ) reports an error.
Corresponds_to:
    $(ZMQREF zmq_curve_keypair())
*/
Tuple!(char[], "publicKey", char[], "secretKey")
    curveKeyPair(char[] publicKeyBuf = null, char[] secretKeyBuf = null)
{
    import core.exception: RangeError;
    if (publicKeyBuf is null)           publicKeyBuf = new char[41];
    else if (publicKeyBuf.length < 41)  throw new RangeError;
    if (secretKeyBuf is null)           secretKeyBuf = new char[41];
    else if (secretKeyBuf.length < 41)  throw new RangeError;

    static if (ZMQ_VERSION < ZMQ_MAKE_VERSION(4, 1, 0)) {
        import deimos.zmq.utils: zmq_curve_keypair;
    }
    if (trusted!zmq_curve_keypair(publicKeyBuf.ptr, secretKeyBuf.ptr) != 0) {
        throw new ZmqException;
    }
    return typeof(return)(publicKeyBuf[0 .. 40], secretKeyBuf[0 .. 40]);
}

///
unittest
{
    auto server = Socket(SocketType.rep);
    auto serverKeys = curveKeyPair();
    server.curveServer = true;
    server.curveSecretKeyZ85 = serverKeys.secretKey;
    server.bind("inproc://curveKeyPair_test");

    auto client = Socket(SocketType.req);
    auto clientKeys = curveKeyPair();
    client.curvePublicKeyZ85 = clientKeys.publicKey;
    client.curveSecretKeyZ85 = clientKeys.secretKey;
    client.curveServerKeyZ85 = serverKeys.publicKey;
    client.connect("inproc://curveKeyPair_test");
    client.send("hello");

    ubyte[5] buf;
    assert (server.receive(buf) == 5);
    assert (buf.asString() == "hello");
}

@system unittest
{
    auto k1 = curveKeyPair();
    assert (k1.publicKey.length == 40);
    assert (k1.secretKey.length == 40);

    char[82] buf;
    auto k2 = curveKeyPair(buf[0 .. 41], buf[41 .. 82]);
    assert (k2.publicKey.length == 40);
    assert (k2.publicKey.ptr == buf.ptr);
    assert (k2.secretKey.length == 40);
    assert (k2.secretKey.ptr == buf.ptr + 41);

    char[82] backup = buf;
    import core.exception, std.exception;
    assertThrown!RangeError(curveKeyPair(buf[0 .. 40], buf[41 .. 82]));
    assertThrown!RangeError(curveKeyPair(buf[0 .. 41], buf[42 .. 82]));
    assert (backup[] == buf[]);
}

} //version (WithLibsodium)


/**
Utility function which interprets and validates a byte array as a UTF-8 string.

Most of $(ZMQD)'s message API deals in $(D ubyte[]) arrays, but very often,
the message _data contains plain text.  $(D asString()) allows for easy and
safe interpretation of raw _data as characters.  It checks that $(D data) is
a valid UTF-8 encoded string, and returns a $(D char[]) array that refers to
the same memory region.

Throws:
    $(STDREF utf,UTFException) if $(D data) is not a valid UTF-8 string.
See_also:
    $(STDREF string,representation), which performs the opposite operation.
*/
inout(char)[] asString(inout(ubyte)[] data) pure
{
    auto s = cast(typeof(return)) data;
    import std.utf: validate;
    validate(s);
    return s;
}

///
unittest
{
    auto s1 = Socket(SocketType.pair);
    s1.bind("inproc://zmqd_asString_example");
    auto s2 = Socket(SocketType.pair);
    s2.connect("inproc://zmqd_asString_example");

    auto msg = Frame(12);
    msg.data.asString()[] = "Hello World!";
    s1.send(msg);

    ubyte[12] buf;
    s2.receive(buf);
    assert(buf.asString() == "Hello World!");
}

unittest
{
    auto bytes = cast(ubyte[]) ['f', 'o', 'o'];
    auto text = bytes.asString();
    assert (text == "foo");
    assert (cast(void*) bytes.ptr == cast(void*) text.ptr);

    import std.exception: assertThrown;
    import std.utf: UTFException;
    auto b = cast(ubyte[]) [100, 252, 1];
    assertThrown!UTFException(asString(b));
}


/**
A class for exceptions thrown when any of the underlying $(ZMQ) C functions
report an error.

The exception provides a standard error message obtained with
$(ZMQREF zmq_strerror()), as well as the $(D errno) code set by the $(ZMQ)
function which reported the error.
*/
class ZmqException : Exception
{
    /**
    The $(D errno) code that was set by the $(ZMQ) function that reported
    the error.

    Corresponds_to:
        $(ZMQREF zmq_errno())
    */
    immutable int errno;

private:
    this(string file = __FILE__, int line = __LINE__) nothrow
    {
        import core.stdc.errno, std.conv;
        this.errno = core.stdc.errno.errno;
        string msg;
        try {
            msg = trusted!(to!string)(trusted!zmq_strerror(this.errno));
        } catch (Exception e) { /* We never get here */ }
        assert(msg.length);     // Still, let's assert as much.
        super(msg, file, line);
    }
}


/**
Exception thrown by $(FREF receiveEvent) on failure to interpret a
received message as an event description.
*/
class InvalidEventException : Exception
{
private:
    this(string file = __FILE__, int line = __LINE__) nothrow
    {
        super("The received message is not an event message", file, line);
    }
}


// =============================================================================
// Everything below is internal
// =============================================================================
private:


struct SharedResource
{
@safe:
    alias Exception function(shared(void)*) nothrow Release;

    this(shared(void)* ptr, Release release) nothrow
        in { assert(ptr); } body
    {
        m_payload = new shared(Payload)(1, ptr, release);
    }

    this(this) nothrow
    {
        if (m_payload) {
            incRefCount();
        }
    }

    ~this() nothrow
    {
        nothrowDetach();
    }

    ref SharedResource opAssign(SharedResource rhs)
    {
        detach();
        m_payload = rhs.m_payload;
        rhs.m_payload = null;
        return this;
    }

    void detach()
    {
        if (m_payload) {
            if (auto ex = nothrowDetach()) throw ex;
        }
    }

    @property inout(shared(void))* handle() inout pure nothrow
    {
        if (m_payload) {
            return m_payload.handle;
        } else {
            return null;
        }
    }

private:
    void incRefCount() @trusted nothrow
    {
        assert (m_payload !is null && m_payload.refCount > 0);
        import core.atomic: atomicOp;
        atomicOp!"+="(m_payload.refCount, 1);
    }

    int decRefCount() @trusted nothrow
    {
        assert (m_payload !is null && m_payload.refCount > 0);
        import core.atomic: atomicOp;
        return atomicOp!"-="(m_payload.refCount, 1);
    }

    Exception nothrowDetach() @trusted nothrow
        out { assert (m_payload is null); }
        body
    {
        if (m_payload) {
            scope(exit) m_payload = null;
            if (decRefCount() < 1) return m_payload.release(m_payload.handle);
        }
        return null;
    }

    struct Payload
    {
        int refCount;
        void* handle;
        Release release;
    }
    shared(Payload)* m_payload;

    invariant()
    {
        assert (m_payload is null || (m_payload.refCount > 0 &&
            m_payload.handle !is null && m_payload.release !is null));
    }
}

@system unittest
{
    import std.exception: assertNotThrown, assertThrown;
    static Exception myFree(shared(void)* p) @trusted nothrow
    {
        auto v = cast(shared(int)*) p;
        if (*v == 0) {
            return new Exception("double release");
        } else {
            *v = 0;
            return null;
        }
    }

    shared int i = 1;

    {
        // Test constructor and properties.
        auto ra = SharedResource(&i, &myFree);
        assert (i == 1);
        assert (ra.handle == &i);

        // Test postblit constructor
        auto rb = ra;
        assert (i == 1);
        assert (rb.handle == &i);

        {
            // Test properties and free() with default-initialized object.
            SharedResource rc;
            assert (rc.handle == null);
            assertNotThrown(rc.detach());

            // Test assignment, both with and without detachment
            rc = rb;
            assert (i == 1);
            assert (rc.handle == &i);

            shared int j = 2;
            auto rd = SharedResource(&j, &myFree);
            assert (rd.handle == &j);
            rd = rb;
            assert (j == 0);
            assert (i == 1);
            assert (rd.handle == &i);

            // Test explicit detach()
            shared int k = 3;
            auto re = SharedResource(&k, &myFree);
            assertNotThrown(re.detach());
            assert(k == 0);

            // Test failure to free and assign (myFree(&k) fails when k == 0)
            re = SharedResource(&k, &myFree);
            assertThrown!Exception(re.detach()); // We defined free(k == 0) as an error
            re = SharedResource(&k, &myFree);
            assertThrown!Exception(re = rb);
        }

        // i should not be "freed" yet
        assert (i == 1);
        assert (ra.handle == &i);
        assert (rb.handle == &i);
    }
    // ...but now it should.
    assert (i == 0);
}

// Thread safety test
@system unittest
{
    enum threadCount = 100;
    enum copyCount = 1000;
    static Exception myFree(shared(void)* p) @trusted nothrow
    {
        auto v = cast(shared(int)*) p;
        if (*v == 0) {
            return new Exception("double release");
        } else {
            *v = 0;
            return null;
        }
    }
    shared int raw = 1;
    {
        auto rs = SharedResource(&raw, &myFree);

        import core.thread;
        auto group = new ThreadGroup;
        foreach (i; 0 .. threadCount) {
            group.create(() {
                auto a = rs;
                foreach (j; 0 .. copyCount) {
                    auto b = a;
                    assert (b.handle == &raw);
                    assert (raw == 1);
                }
            });
        }
        group.joinAll();
        assert (rs.handle == &raw);
        assert (raw == 1);
    }
    assert (raw == 0);
}


version(unittest) private string uniqueUrl(string p, int n = __LINE__)
{
    import std.uuid;
    return p ~ "://" ~ randomUUID().toString();
}


private auto trusted(alias func, Args...)(auto ref Args args) @trusted
{
    return func(args);
}


// std.string.toStringz() is unsafe, so we provide our own implementation
// tailored to the string sizes we are likely to encounter here.
// Note that this implementation requires that the string be used immediately
// upon return, and not stored, as the buffer will be reused most of the time.
const(char)* zeroTermString(const char[] s) nothrow
{
    import std.algorithm: max;
    static char[] buf;
    immutable len = s.length + 1;
    if (buf.length < len) buf.length = max(len, 1023);
    buf[0 .. s.length] = s;
    buf[s.length] = '\0';
    return buf.ptr;
}

@system unittest
{
    auto c1 = zeroTermString("Hello World!");
    assert (c1[0 .. 13] == "Hello World!\0");
    auto c2 = zeroTermString("foo");
    assert (c2[0 .. 4] == "foo\0");
    assert (c1 == c2);
}
