module std::net::tcp @if(os::SUPPORTS_INET);
import std::net @public;
import std::time, libc;
import std::collections;
import std::os::win32;

typedef TcpSocket = inline Socket;
typedef TcpServerSocket = inline Socket;

fn TcpSocket? connect(String host, uint port, Duration timeout = time::DURATION_ZERO, SocketOption... options, IpProtocol ip_protocol = UNSPECIFIED)
{
	AddrInfo* ai =  net::addrinfo(host, port, ip_protocol.ai_family, os::SOCK_STREAM)!;
	defer os::freeaddrinfo(ai);
	if (timeout > time::DURATION_ZERO)
	{
		return (TcpSocket)net::connect_with_timeout_from_addrinfo(ai, options, timeout)!;
	}
	return connect_to(ai, ...options);
}

fn TcpSocket? connect_async(String host, uint port, SocketOption... options, IpProtocol ip_protocol = UNSPECIFIED)
{
	AddrInfo* ai = net::addrinfo(host, port, ip_protocol.ai_family, os::SOCK_STREAM)!;
	defer os::freeaddrinfo(ai);
	return connect_async_to(ai, ...options);
}

fn TcpSocket? connect_to(AddrInfo* ai, SocketOption... options)
{
	return (TcpSocket)net::connect_from_addrinfo(ai, options);
}

fn TcpSocket? connect_async_to(AddrInfo* ai, SocketOption... options)
{
	return (TcpSocket)net::connect_async_from_addrinfo(ai, options);
}

fn TcpServerSocket? listen(String host, uint port, uint backlog, SocketOption... options, IpProtocol ip_protocol = UNSPECIFIED)
{
	AddrInfo* ai = net::addrinfo(host, port, ip_protocol.ai_family, os::SOCK_STREAM)!;
	defer os::freeaddrinfo(ai);
	return listen_to(ai, backlog, ...options);
}

fn TcpSocket? accept(TcpServerSocket* server_socket)
{
	TcpSocket socket;
	socket.ai_addrlen = socket.ai_addr_storage.len;
	socket.sock = os::accept(server_socket.sock, (SockAddrPtr)&socket.ai_addr_storage, &socket.ai_addrlen);
	if (!socket.sock.is_valid()) return net::ACCEPT_FAILED?;
	return socket;
}

fn TcpServerSocket? listen_to(AddrInfo* ai, uint backlog, SocketOption... options)
{
	net::@loop_over_ai(ai; NativeSocket sockfd, AddrInfo* ai_candidate)
	{
		net::apply_sockoptions(sockfd, options)!;
		bool err = os::bind(sockfd, ai_candidate.ai_addr, ai_candidate.ai_addrlen) || os::listen(sockfd, backlog);
		if (!err) return (TcpServerSocket)net::new_socket(sockfd, ai_candidate);
	};
	return os::socket_error()?;
}


// TODO: Is there a better way to do this - create a SocketPair alias or typdef? can I then reference things to free?
struct TcpSocketPair
{
    TcpSocket send;
    TcpSocket recv;
}

fn TcpSocketPair*? TcpSocketPair.init(&self)
{
	$if env::WIN32:
		Win32_WORD version = 0x0202;

		// TODO: If I'm not using this, should I just pass &&char[408] inplace or
		// something indicating its a variable that is unused?
		char[408] wsa_data;

		// TODO: Handle this error if wsaStartup did not work.
		// - What the errors I need to handle?
		CInt wsa_error = win32::wsaStartup(version, &wsa_data);

		// TODO: Maybe change this to listen_sock?
		TcpServerSocket listen_socket = tcp::listen("127.0.0.1", 0, 0)!;

		// TODO: Rename this to listen_sock_info?
		TcpSocket lsocket_info;
		lsocket_info.ai_addrlen = listen_socket.ai_addr_storage.len;

		// TODO: Handle error
		// - What are the errors that need to be handled?
		// - Catch error, close listen socket and return error.
		int result = getsockname(listen_socket.sock, (SockAddrPtr) &lsocket_info.ai_addr_storage, &lsocket_info.ai_addrlen);
		libc::perror("error code");

		// TODO: Is there an in-built way to do this in C??? or maybe an inbuilt function in C3???
		// TODO: Rename this to listen_port_bytes
		// NOTE:
		// lport_view[0] is the most significant byte
		// lport_view[1] is the least most significant byte
		char[] listen_port_view = lsocket_info.ai_addr_storage[2:2];
		int listen_port = (listen_port_view[0] << 8) + listen_port_view[1];

		// TODO:
		// - Catch errors and close listening socket and return error.
		TcpSocket send_sock = tcp::connect_async("127.0.0.1", listen_port)!;
		TcpSocket recv_sock = tcp::accept(&listen_socket)!;

		// TODO: Can I do close on error as well or something?
        listen_socket.close()!;
	$else
		CInt[2] sockets;

		// TODO: Should protocol (os::SOCK_STREAM) be an AI_Protocol instead of CINT?
		// - It seems like SOCK_STREAM is passed to functions that need an AISockType
		// - AISockType is probbly an alias for CInt, not sure if I can use that since its supposed to be an external function to  C, but if its an alias, maybe its fine?
		// - Same with AIFamily which is AF_UNIX, maybe I can use that and I don't need to do an explict cast?
		isz n = os::socketpair((CInt) os::AF_UNIX, (CInt) os::SOCK_STREAM, 0, &sockets);
		// TODO: Is this the right error to throw?
		// TODO: Maybe we need to make the errors a lot more detailed? e.g. certain numbers mean certain things?
		if (n < 0) return os::socket_error()?;

		// TODO: This needs to be renamed, s_sock isn't enough detail
		// - It's going from CInt -> os::NativeSocket -> Socket -> TcpSocket
		Socket s_sock = { .sock = (net::os::NativeSocket) sockets[0] };
		TcpSocket send_sock = (TcpSocket) s_sock;

		// TODO: This needs to be renamed, r_sock isn't enough detail
		Socket r_sock = { .sock = (net::os::NativeSocket) sockets[1] };
		TcpSocket recv_sock = (TcpSocket) r_sock;
	$endif

    *self = { .send = send_sock,  .recv = recv_sock };
    return self;
}

// TODO: Can this lead to double frees?
// - Call free twice
// - Call close on send manually and then call free again.
fn void TcpSocketPair.free(&self)
{
	// TODO: Rethrow this error.
    self.send.close()!!;
    self.recv.close()!!;

    $if env::WIN32:
        win32::wsaCleanup();
    $endif
}
