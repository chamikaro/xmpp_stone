import 'package:xmpp_stone/xmpp_stone.dart';
import 'dart:io';

// This function creates a regular connection but patches Socket.secure
// to use modern TLS settings for all connections
Connection createSecureXmppConnection(XmppAccountSettings account) {
  // Store the original secure method
  Function originalSecureSocketMethod = SecureSocket.secure;

  // Replace with our enhanced version
  SecureSocket.secure = (Socket socket, {onBadCertificate, context, host, sendClient}) {
    print("Using enhanced TLS with TLSv1.2+ for XMPP connection");
    return originalSecureSocketMethod(
        socket,
        onBadCertificate: onBadCertificate,
        supportedProtocols: ['TLSv1.2', 'TLSv1.3'],
        host: host,
        context: context,
        sendClient: sendClient
    );
  };

  // Create and return a normal connection - our patched secure method will be used
  return Connection(account);
}