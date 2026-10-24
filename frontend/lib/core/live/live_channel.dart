import 'package:web_socket_channel/web_socket_channel.dart';

/// The few things the live connection needs from a WebSocket, so that tests
/// can stand in a fake one and the rest of the code never touches the package.
abstract class LiveChannel {
  /// Completes when the server has accepted the connection; throws if it
  /// could not be made or was refused.
  Future<void> get ready;

  /// Text messages from the server. Ends when the connection closes.
  Stream<dynamic> get stream;

  void send(String text);

  Future<void> close();

  /// The code the connection was closed with, once it has closed (null when
  /// unknown, e.g. the network dropped).
  int? get closeCode;
}

typedef ChannelFactory = LiveChannel Function(Uri address);

/// The real thing, on every platform (desktop, mobile and web).
class WebSocketLiveChannel implements LiveChannel {
  WebSocketLiveChannel(Uri address)
      : _channel = WebSocketChannel.connect(address);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() => _channel.sink.close(1000);

  @override
  int? get closeCode => _channel.closeCode;
}
