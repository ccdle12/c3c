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

		CInt wsa_error = win32::wsaStartup(version, &wsa_data);
		if (wsa_error > 0) return os::socket_error()?;
		defer (catch err)
		{
			win32::wsaCleanup();
		}

		TcpServerSocket listen_sock = tcp::listen("127.0.0.1", 0, 0)!;
		defer (catch err)
		{
			listen_sock.close();
		}

		TcpSocket listen_sock_info;
		listen_sock_info.ai_addrlen = listen_sock.ai_addr_storage.len;

		// TODO: Rename result to something more accurate
		int result = os::getsockname(listen_sock.sock, (SockAddrPtr) &listen_sock_info.ai_addr_storage,  &listen_sock_info.ai_addrlen);
		if (result < 0) return os::socket_error()?;

		char[] listen_port_bytes = listen_sock_info.ai_addr_storage[2:2];
		char msb = listen_port_bytes[0];
		char lsb = listen_port_bytes[1];
		int listen_port = (msb << 8) | lsb;

		// TODO: 2025.10.08 - defer catch send_sock
		TcpSocket send_sock = tcp::connect_async("127.0.0.1", listen_port)!;
		defer (catch err)
		{
			send_sock.close();
		}
		// TODO: 2025.10.08 - defer catch recv_sock
		TcpSocket recv_sock = tcp::accept(&listen_sock)!;
		defer (catch err)
		{
			recv_sock.close();
		}

		// TODO: 2025.10.08 - defer catch close
        listen_sock.close()!;
	$else
		CInt[2] sockets;

		// TODO: Should protocol (os::SOCK_STREAM) be an AISockType instead of CINT?
		// - It seems like SOCK_STREAM is passed to functions that need an AISockTypel
		// - AISockType is probbly an alias for CInt, not sure if I can use that since its supposed to be an external function to  C, but if its an alias, maybe its fine?
		// - Same with AIFamily which is AF_UNIX, maybe I can use that and I don't need to do an explict cast?
		isz n = os::socketpair((CInt) os::AF_UNIX, (CInt) os::SOCK_STREAM, 0, &sockets);
		// TODO: Is this the right error to throw?
		// TODO: Maybe we need to make the errors a lot more detailed? e.g. certain numbers mean certain things?
		if (n < 0) return os::socket_error()?;

		// TODO: This needs to be renamed, s_sock isn't enough detail
		// Maybe:
		// - Socket send_sock
		// - TcpSocket tcp_send_sock
		//
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

fn void? TcpSocketPair.free(&self)
{
    self.send.close()!;
    self.recv.close()!;

    $if env::WIN32:
        win32::wsaCleanup();
    $endif
}
