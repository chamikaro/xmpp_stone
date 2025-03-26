import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xmpp_stone/xmpp_stone.dart';

/// A client for ejabberd XMPP servers configured with specific port 5222 settings.
/// This client ensures compatibility with ejabberd's specific TLS requirements.
class EjabberdClient {
  static const String TAG = 'EjabberdClient';

  /// The underlying XMPP connection
  final Connection _connection;

  /// The connection state stream
  Stream<XmppConnectionState> get connectionStateStream =>
      _connection.connectionStateStream;

  /// Get the current connection
  Connection get connection => _connection;

  /// Get the message handler for receiving messages
  MessageHandler get messageHandler =>
      MessageHandler.getInstance(_connection);

  /// Get presence manager
  PresenceManager get presenceManager =>
      PresenceManager.getInstance(_connection);

  /// Get roster manager
  RosterManager get rosterManager =>
      RosterManager.getInstance(_connection);

  /// Create a new ejabberd client
  ///
  /// Parameters:
  /// - [username]: JID username
  /// - [domain]: JID domain
  /// - [password]: Password for authentication
  /// - [host]: Server hostname (optional, defaults to domain)
  /// - [resource]: JID resource (optional)
  /// - [nickname]: User nickname (optional)
  /// - [environment]: Environment variables map (optional)
  EjabberdClient._internal(this._connection);

  /// Create a new ejabberd client
  static EjabberdClient create({
    required String username,
    required String domain,
    required String password,
    String? host,
    String? resource,
    String? nickname,
    Map<String, String>? environment,
  }) {
    // Use provided environment or system environment
    final env = environment ?? Platform.environment;

    // Create XMPP account settings
    final account = XmppAccountSettings(
      nickname ?? username,
      username,
      domain,
      password,
      5222,
      host: host ?? domain,
      resource: resource,
    );

    // Create connection with the account
    final connection = Connection(account);

    // Apply ejabberd-specific patches
    _patchConnection(connection, env);

    return EjabberdClient._internal(connection);
  }

  /// Apply ejabberd-specific patches to the connection
  static void _patchConnection(Connection connection, Map<String, String> env) {
    // Store the original method reference to preserve any existing functionality
    final originalStartSecureSocket = connection.startSecureSocket;

    // Override the startSecureSocket method with our ejabberd-compatible implementation
    connection.startSecureSocket = () {
      Log.d(TAG, 'Using ejabberd-compatible TLS handshake');

      // Extract TLS settings from environment to match ejabberd template
      final starttlsRequired = env['EJABBERD_STARTTLS'] == 'true';

      final protocolOptions = <String>['no_sslv2', 'no_sslv3'];

      if (env['EJABBERD_PROTOCOL_OPTIONS_TLSV1'] != 'true') {
        protocolOptions.add('no_tlsv1');
      }

      if (env['EJABBERD_PROTOCOL_OPTIONS_TLSV1_1'] == 'false') {
        protocolOptions.add('no_tlsv1_1');
      }

      final ciphers = env['EJABBERD_CIPHERS'] ?? 'HIGH:!aNULL:!3DES';

      // Create security context if DH parameters are needed
      SecurityContext? securityContext;
      if (env['EJABBERD_DHPARAM'] == 'true') {
        try {
          securityContext = SecurityContext();
          final dhFilePath = '/opt/ejabberd/ssl/dh.dhpem';
          securityContext.setTrustedCertificatesBytes(
              File(dhFilePath).readAsBytesSync());
          Log.d(TAG, 'Applied DH parameters from: $dhFilePath');
        } catch (e) {
          Log.e(TAG, 'Error loading DH parameters: $e');
        }
      }

      // Log the TLS settings
      Log.d(TAG, 'STARTTLS required: $starttlsRequired');
      Log.d(TAG, 'Protocol options: $protocolOptions');
      Log.d(TAG, 'Using ciphers: $ciphers');

      // Get the socket from the connection
      final socket = connection._socket;
      if (socket == null) {
        Log.e(TAG, 'Socket is null, cannot secure');
        return;
      }

      // Execute the security handshake
      socket.secure(
        context: securityContext,
        onBadCertificate: (cert) => true,  // Accept all certificates for simplicity
      ).then((secureSocket) {
        if (secureSocket == null) return;

        secureSocket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .map(connection.prepareStreamResponse)
            .listen(connection.handleResponse,
            onError: (error) => connection.handleSecuredConnectionError(error.toString()),
            onDone: connection.handleSecuredConnectionDone);
        connection._openStream();
      });
    };

    // Only apply TLS if required
    final originalIsTlsRequired = connection.isTlsRequired;
    connection.isTlsRequired = () {
      return env['EJABBERD_STARTTLS'] == 'true' || originalIsTlsRequired();
    };
  }

  /// Connect to the server
  void connect() {
    _connection.connect();
  }

  /// Disconnect from the server
  void disconnect() {
    _connection.close();
  }

  /// Send a message to a user or room
  void sendMessage(String to, String content, {MessageStanzaType type = MessageStanzaType.CHAT}) {
    final stanzaId = DateTime.now().millisecondsSinceEpoch.toString();

    final messageStanza = MessageStanza(stanzaId, type)
      ..addAttribute(XmppAttribute('to', to))
      ..addAttribute(XmppAttribute('from', _connection.fullJid.toString()))
      ..addChild(XmppElement()
        ..name = 'body'
        ..textValue = content);

    _connection.writeStanza(messageStanza);
  }

  /// Send a structured message as JSON
  void sendJsonMessage(String to, Map<String, dynamic> jsonData, {MessageStanzaType type = MessageStanzaType.CHAT}) {
    sendMessage(to, jsonEncode(jsonData), type: type);
  }

  /// Join a Multi-User Chat (MUC) room
  void joinRoom(String roomId, String nickname) {
    final domain = _connection.fullJid.domain;
    final occupantJID = '$roomId@conference.$domain/$nickname';

    final presenceStanza = PresenceStanza()
      ..addAttribute(XmppAttribute('to', occupantJID))
      ..addAttribute(XmppAttribute('from', _connection.fullJid.toString()))
      ..addAttribute(XmppAttribute('id', 'join-${DateTime.now().millisecondsSinceEpoch}'))
      ..addChild(XmppElement()
        ..name = 'x'
        ..addAttribute(XmppAttribute('xmlns', 'http://jabber.org/protocol/muc')));

    _connection.writeStanza(presenceStanza);
  }

  /// Send a message to a Multi-User Chat (MUC) room
  void sendRoomMessage(String roomId, String content) {
    final domain = _connection.fullJid.domain;
    sendMessage('$roomId@conference.$domain', content, type: MessageStanzaType.GROUPCHAT);
  }

  /// Send a structured message to a Multi-User Chat (MUC) room as JSON
  void sendRoomJsonMessage(String roomId, Map<String, dynamic> jsonData) {
    final domain = _connection.fullJid.domain;
    sendJsonMessage('$roomId@conference.$domain', jsonData, type: MessageStanzaType.GROUPCHAT);
  }

  /// Listen for messages with a callback
  StreamSubscription<AbstractStanza?> onMessage(Function(Message? message) callback) {
    return messageHandler.messagesStream.listen((message) {
      callback(message);
    });
  }

  /// Listen for connection state changes with a callback
  StreamSubscription<XmppConnectionState> onConnectionStateChanged(
      Function(XmppConnectionState state) callback) {
    return connectionStateStream.listen(callback);
  }
}

/// Example usage:
///
/// ```dart
/// // Create the client
/// final client = EjabberdClient.create(
///   username: 'user',
///   domain: 'example.com',
///   password: 'password',
/// );
///
/// // Listen for connection state changes
/// client.onConnectionStateChanged((state) {
///   print('Connection state: $state');
///
///   if (state == XmppConnectionState.Ready) {
///     // Join a room when connected
///     client.joinRoom('room123', 'Nickname');
///
///     // Send a message to the room
///     client.sendRoomMessage('room123', 'Hello everyone!');
///   }
/// });
///
/// // Listen for messages
/// client.onMessage((message) {
///   if (message?.body != null) {
///     print('Received message: ${message!.body}');
///   }
/// });
///
/// // Connect to the server
/// client.connect();
/// ```