import 'dart:async';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:xmpp_stone/src/Connection.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/nonzas/Nonza.dart';
import 'package:xmpp_stone/src/features/Negotiator.dart';

import '../logger/Log.dart';

class StartTlsNegotiator extends Negotiator {
  static const TAG = 'StartTlsNegotiator';
  final Connection _connection;
  late StreamSubscription<Nonza> subscription;

  StartTlsNegotiator(this._connection) {
    expectedName = 'StartTlsNegotiator';
    expectedNameSpace = 'urn:ietf:params:xml:ns:xmpp-tls';
    priorityLevel = 1;
  }

  @override
  void negotiate(List<Nonza> nonzas) {
    Log.d(TAG, 'negotiating starttls');
    Log.d(TAG, "STARTTLS: Beginning negotiation");
    state = NegotiatorState.NEGOTIATING;

    // Add this try-catch block for more detailed logging
    try {
      subscription = _connection.inNonzasStream.listen(
              (nonza) {
                Log.d(TAG, "STARTTLS: Received nonza: ${nonza.name}");
            checkNonzas(nonza);
          },
          onError: (error) {
            Log.d(TAG, "STARTTLS: Error in nonza stream: $error");
          },
          onDone: () {
            Log.d(TAG, "STARTTLS: Nonza stream done");
          }
      );

      Log.d(TAG, "STARTTLS: Sending request nonza");
      _connection.writeNonza(StartTlsResponse());
      Log.d(TAG, "STARTTLS: Request sent successfully");
    } catch (e) {
      Log.d(TAG, "STARTTLS: Exception during negotiation: $e");
    }
  }

  void checkNonzas(Nonza nonza) {
    Log.d(TAG, "STARTTLS: Processing nonza: ${nonza.name}");

    if (nonza.name == 'proceed') {
      Log.d(TAG, "STARTTLS: Received proceed, starting TLS handshake");
      try {
        _connection.startSecureSocket();
        Log.d(TAG, "STARTTLS: Called startSecureSocket successfully");
        state = NegotiatorState.DONE_CLEAN_OTHERS;
        subscription.cancel();
      } catch (e) {
        Log.d(TAG, "STARTTLS: Error during secure socket start: $e");
      }
    } else if (nonza.name == 'failure') {
      Log.d(TAG, "STARTTLS: Received failure nonza");
      _connection.startTlsFailed();
    } else {
      Log.d(TAG, "STARTTLS: Received unexpected nonza: ${nonza.name}");
    }
  }

  @override
  List<Nonza> match(List<Nonza> requests) {
    var nonza = requests.firstWhereOrNull((request) =>
    request.name == 'starttls' &&
        request.getAttribute('xmlns')?.value == expectedNameSpace);

    if (nonza != null) {
      Log.d(TAG, "STARTTLS: Matched starttls feature");
    }

    return nonza != null ? [nonza] : [];
  }
}

class StartTlsResponse extends Nonza {
  StartTlsResponse() {
    name = 'starttls';
    addAttribute(XmppAttribute('xmlns', 'urn:ietf:params:xml:ns:xmpp-tls'));
  }
}
