import 'package:xmpp_stone/src/data/Jid.dart';

class XmppAccountSettings {
  String name;
  String username;
  String domain;
  String? resource = '';
  String password;
  String? host;
  int port;
  String? wsPath;
  List<String>? wsProtocols;
  int totalReconnections = 3;
  int reconnectionTimeout = 1000;
  bool ackEnabled = true;
  bool smResumable = true;

  // Added STARTTLS support
  bool requireTlsNegotiation = false; // Force STARTTLS negotiation
  bool allowSelfSignedCertificates = false; // Accept self-signed certificates
  bool allowPlainAuth = true; // Allow authentication without TLS

  XmppAccountSettings(
      this.name,
      this.username,
      this.domain,
      this.password,
      this.port,
      {
        this.host,
        this.resource,
        this.wsPath,
        this.wsProtocols,
        this.requireTlsNegotiation = false,
        this.allowSelfSignedCertificates = false,
        this.allowPlainAuth = true,
      }
      );

  Jid get fullJid => Jid(username, domain, resource);

  /// for `port` setting by default used default XMPP port 5222, for the Web platform set it manually via [XmppAccountSettings.port]
  static XmppAccountSettings fromJid(String jid, String password) {
    var fullJid = Jid.fromFullJid(jid);
    var accountSettings =
    XmppAccountSettings(jid, fullJid.local, fullJid.domain, password, 5222);
    if (fullJid.resource != null && fullJid.resource!.isNotEmpty) {
      accountSettings.resource = fullJid.resource;
    }

    return accountSettings;
  }
}