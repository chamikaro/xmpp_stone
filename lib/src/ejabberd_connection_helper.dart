import 'package:xmpp_stone/xmpp_stone.dart';

/// Helper class to modify XmppAccountSettings for ejabberd compatibility
class EjabberdConnectionHelper {
  /// Apply ejabberd-compatible settings to XmppAccountSettings
  ///
  /// Call this before creating a Connection to ensure compatibility with ejabberd port 5222.
  /// This method doesn't require access to private fields or methods.
  static XmppAccountSettings prepareAccountForEjabberd(XmppAccountSettings account) {
    // Modify the publicly accessible properties

    // The library already has reconnection parameters we can adjust
    account.totalReconnections = 5;  // Increase reconnection attempts
    account.reconnectionTimeout = 2000;  // Longer timeout between attempts

    // Set stream management options
    account.ackEnabled = true;
    account.smResumable = true;

    return account;
  }

  /// Register a connection state listener to handle ejabberd-specific behaviors
  ///
  /// This is a workaround using the public API to achieve similar functionality
  /// as the private API patch we tried before.
  static void setupEjabberdCompatibility(Connection connection) {
    // Create a custom ConnectionStateChangedListener
    connection.connectionStateStream.listen((state) {
      // Handle specific states where we might need to adjust behavior
      if (state == XmppConnectionState.SocketOpened) {
        // The socket is opened but not yet secure
        // For ejabberd, we shouldn't need to do anything special here
      } else if (state == XmppConnectionState.DoneParsingFeatures) {
        // Features have been parsed, we could take action here if needed
      } else if (state == XmppConnectionState.StartTlsFailed) {
        // TLS negotiation failed
        Log.e("EjabberdHelper", "TLS negotiation failed, trying to reconnect");
        // Give the connection time to handle its own recovery
        Future.delayed(Duration(seconds: 2), () {
          if (connection.state != XmppConnectionState.Closed) {
            connection.connect();
          }
        });
      }
    });
  }
}

/// Extension methods for Connection to work better with ejabberd
extension EjabberdConnectionExtension on Connection {
  /// Connect with ejabberd compatibility
  void connectWithEjabberdCompat() {
    // Apply ejabberd-compatible settings to the account
    EjabberdConnectionHelper.prepareAccountForEjabberd(this.account);

    // Setup connection state handling for ejabberd
    EjabberdConnectionHelper.setupEjabberdCompatibility(this);

    // Connect normally
    this.connect();
  }
}