// Sockets on the loopback interface, in one thread: the kernel completes a
// connection to a listening socket before accept is called. Ports and host
// names are not printed (they depend on the machine).
import sys.net.Host;
import sys.net.Socket;

class NetNatives {
	static function main() {
		var server = new Socket();
		server.bind(new Host("127.0.0.1"), 0);
		server.listen(4);
		var port = server.host().port;
		Sys.println(port > 0 && server.host().host.toString() == "127.0.0.1");
		var client = new Socket();
		client.connect(new Host("127.0.0.1"), port);
		var conn = server.accept();
		Sys.println(conn.peer().host.toString() + " " + (client.peer().port == port));
		client.setFastSend(true);
		client.output.writeString("ping\n");
		client.output.flush();
		Sys.println(conn.input.readLine());
		conn.output.writeString("pong and more\n");
		Sys.println(client.input.readLine());
		// select: the client has nothing to read, then has
		var r = Socket.select([client, conn], [], [], 0);
		Sys.println(r.read.length);
		conn.output.writeString("x");
		var r2 = Socket.select([client], [], [], 1.0);
		Sys.println(r2.read.length + " " + String.fromCharCode(client.input.readByte()));
		client.setBlocking(false);
		try {
			client.input.readByte();
			Sys.println("read without data");
		} catch (e:Dynamic) {
			Sys.println("blocked: " + Std.string(e));
		}
		client.setBlocking(true);
		client.setTimeout(0.05);
		try {
			client.input.readByte();
			Sys.println("read without data");
		} catch (e:Dynamic) {
			Sys.println("timeout: an exception");
		}
		conn.shutdown(false, true);
		try {
			client.input.readByte();
		} catch (e:haxe.io.Eof) {
			Sys.println("eof");
		} catch (e:Dynamic) {
			Sys.println("after shutdown: " + e);
		}
		client.close();
		conn.close();
		server.close();
		Sys.println(new Host("localhost").ip != 0 && Host.localhost().length > 0);
		Sys.println(new Host("127.0.0.1").reverse().length > 0);
		var refused = new Socket();
		try {
			refused.connect(new Host("127.0.0.1"), port);
			Sys.println("connected to a closed port");
		} catch (e:Dynamic) {
			Sys.println("refused");
		}
	}
}
