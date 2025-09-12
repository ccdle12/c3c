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

fn Pair{TcpSocket, TcpSocket}? socket_pair(AIFamily ai_family = os::AF_UNIX, AISockType ai_socktype = os::SOCK_STREAM)
{
    $if env::WIN32:
		Win32_WORD version = 0x0202;

		char[408] wsa_data;
		CInt wsa_error = win32::wsaStartup(version, &wsa_data);
		defer win32::wsaCleanup();

		// TODO: If I close this listening socket at the end of this function,
		// does connect socket still work?
		TcpServerSocket listen_socket = tcp::listen("127.0.0.1", 0, 0)!;

		TcpSocket socket;
		socket.ai_addrlen = listen_socket.ai_addr_storage.len;

		// TODO: Handle error
		int result = getsockname(listen_socket.sock, (SockAddrPtr) &socket.ai_addr_storage, &socket.ai_addrlen);
		libc::perror("error code");

		// NOTE:
		// lport_view[0] is the most significant byte
		// lport_view[1] is the least most significant byte
		char[] listen_port_view = socket.ai_addr_storage[2:2];
		int listen_port = (listen_port_view[0] << 8) + listen_port_view[1];

		TcpSocket send_sock = tcp::connect_async("127.0.0.1", listen_port)!;
		TcpSocket recv_sock = tcp::accept(&listen_socket)!;
		listen_socket.close()!;
    $else
		CInt[2] sockets;
		isz n = os::socketpair((CInt) ai_family, (CInt) ai_socktype, 0, &sockets);
		if (n < 0) return os::socket_error()?;

		Socket s_sock = { .sock = (net::os::NativeSocket) sockets[0] };
		TcpSocket send_sock = (TcpSocket) s_sock;

		Socket r_sock = { .sock = (net::os::NativeSocket) sockets[1] };
		TcpSocket recv_sock = (TcpSocket) r_sock;
	$endif

	return { .first = send_sock, .second = recv_sock };
}
