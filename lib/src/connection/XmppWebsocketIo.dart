import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';

import 'package:xmpp_stone/src/connection/XmppWebsocketApi.dart';
import '../logger/Log.dart';

export 'XmppWebsocketApi.dart';

XmppWebSocket createSocket() {
  return XmppWebSocketIo();
}

// This function is used by Connection to determine if STARTTLS should be used
// We've modified it to always return false, allowing our custom account setting to control it instead
bool isTlsRequired() {
  return false; // Modified to allow our custom account setting to control this
}

class XmppWebSocketIo extends XmppWebSocket {
  static String TAG = 'XmppWebSocketIo';
  Socket? _socket;
  late String Function(String event) _map;

  XmppWebSocketIo();

  @override
  Future<XmppWebSocket> connect<S>(String host, int port,
      {String Function(String event)? map, List<String>? wsProtocols, String? wsPath}) async {
    await Socket.connect(host, port).then((Socket socket) {
      _socket = socket;

      if (map != null) {
        _map = map;
      } else {
        _map = (element) => element;
      }
    });

    return Future.value(this);
  }

  @override
  void close() {
    _socket!.close();
  }

  @override
  void write(Object? message) {
    _socket!.write(message);
  }

  @override
  StreamSubscription<String> listen(void Function(String event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _socket!.cast<List<int>>().transform(utf8.decoder).map(_map).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError);
  }

  @override
  Future<SecureSocket?> secure({
    host,
    SecurityContext? context,
    bool Function(X509Certificate certificate)? onBadCertificate,
    List<String>? supportedProtocols}) {

    Log.d(TAG, "XmppWebSocketIo: Starting TLS handshake with force-accept");

    try {
      // Create a security context that's more permissive
      SecurityContext securityContext = SecurityContext.defaultContext;

      return SecureSocket.secure(
          _socket!,
          // Always accept any certificate
          onBadCertificate: (cert) {
            Log.d(TAG, "Accepting certificate: ${cert.subject}");
            return true; // Accept all certificates
          },
          supportedProtocols: ['tlsv1.3', 'tlsv1.2', 'tlsv1.1', 'tlsv1']
      );
    } catch (e) {
      Log.d(TAG, "Exception during TLS setup: $e");
      throw e;
    }
  }

  @override
  String getStreamOpeningElement(String domain) {
    return """<?xml version='1.0'?><stream:stream xmlns='jabber:client' version='1.0' xmlns:stream='http://etherx.jabber.org/streams' to='$domain' xml:lang='en'>""";
  }
}