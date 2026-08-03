package unit;

import core.Socket;
import haxe.io.Bytes;

class SocketTest {
	public static function main():Void {
		var bytes = Bytes.alloc(4);
		Socket.writeI32(bytes, 0, 0x12345678);
		if (bytes.get(0) != 0x78 || bytes.get(1) != 0x56 || bytes.get(2) != 0x34 || bytes.get(3) != 0x12) throw "Socket length encoding failed";
		if (Socket.readByte(bytes, 2) != 0x34 || Socket.readUi16(bytes, 0) != 0x5678) throw "Socket length decoding failed";
	}
}
