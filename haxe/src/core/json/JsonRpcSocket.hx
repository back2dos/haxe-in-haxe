package core.json;

import core.Json.JsonValue;

class JsonRpcSocket {
	public static function sendJson(socket:core.Socket, json:JsonValue):Void {
		socket.sendString(core.Json.stringOfJson(json));
	}

	public static function sendEvent(socket:core.Socket, event:String, data:Null<JsonValue>):Void {
		sendJson(socket, JsonRpc.notification(event, data));
	}
}
