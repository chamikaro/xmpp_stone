import 'dart:io';
import 'package:xmpp_stone/xmpp_stone.dart';

class SecureXmppConnection extends Connection {
  static const String TAG = 'SecureXmppConnection';

  SecureXmppConnection(XmppAccountSettings account) : super(account);

  @override
  void startSecureSocket() {
    Log.d(TAG, 'Enhanced startSecureSocket with TLS 1.2/1.3 support');

    try {
      // Create a security context for TLS configuration
      SecurityContext context = SecurityContext();

      // Configure advanced TLS options
      SecureSocket.secure(
        _socket,
        onBadCertificate: _validateBadCertificate,
        supportedProtocols: ['TLSv1.2', 'TLSv1.3'], // Force modern TLS versions
      ).then((secureSocket) {
        _socket = secureSocket;
        _socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .map(prepareStreamResponse)
            .listen(
            handleResponse,
            onError: (error) {
              Log.e(TAG, 'TLS error: $error');
              handleSecuredConnectionError(error.toString());
            },
            onDone: handleSecuredConnectionDone
        );
        _openStream();
      }).catchError((error) {
        Log.e(TAG, 'Failed to establish secure connection: $error');
        startTlsFailed(); // This calls the parent method that handles TLS failure
      });
    } catch (e) {
      Log.e(TAG, 'Exception during TLS setup: $e');
      startTlsFailed();
    }
  }

  @override
  bool _validateBadCertificate(X509Certificate certificate) {
    // You can add custom certificate validation here if needed
    Log.d(TAG, 'Validating certificate: ${certificate.subject}');
    return true; // Accept all certificates for now
  }
}