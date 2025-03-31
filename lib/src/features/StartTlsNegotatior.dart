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

class ImprovedStartTlsNegotiator extends Negotiator {
  static const TAG = 'ImprovedStartTlsNegotiator';
  final Connection _connection;
  late StreamSubscription<Nonza> subscription;
  Completer<bool>? _proceedCompleter;

  ImprovedStartTlsNegotiator(this._connection) {
    expectedName = 'StartTlsNegotiator';
    expectedNameSpace = 'urn:ietf:params:xml:ns:xmpp-tls';
    priorityLevel = 1;
  }

  @override
  List<Nonza> match(List<Nonza> requests) {
    var nonza = requests.firstWhereOrNull((request) =>
    request.name == 'starttls' &&
        request.getAttribute('xmlns')?.value == expectedNameSpace);

    if (nonza != null) {
      Log.d(TAG, "Matched starttls feature");
    }
    return nonza != null ? [nonza] : [];
  }

  @override
  void negotiate(List<Nonza> nonzas) {
    Log.d(TAG, 'Negotiating STARTTLS');
    state = NegotiatorState.NEGOTIATING;

    _proceedCompleter = Completer<bool>();

    // Listen for proceed or failure response
    subscription = _connection.inNonzasStream.listen(checkNonzas);

    // Send STARTTLS request
    Log.d(TAG, "Sending STARTTLS request");
    _connection.writeNonza(StartTlsResponse());

    // Wait for proceed with timeout
    Timer(Duration(seconds: 5), () {
      if (!_proceedCompleter!.isCompleted) {
        Log.d(TAG, "STARTTLS timeout - proceeding anyway");
        _proceedCompleter!.complete(true);
      }
    });

    // When we get proceed or timeout
    _proceedCompleter!.future.then((proceed) {
      if (proceed) {
        try {
          Log.d(TAG, "Starting TLS handshake");
          _connection.startSecureSocket();
          state = NegotiatorState.DONE_CLEAN_OTHERS;
        } catch (e) {
          Log.e(TAG, "Error starting secure socket: $e");
          _connection.startTlsFailed();
        }
      } else {
        Log.d(TAG, "STARTTLS failed or rejected");
        _connection.startTlsFailed();
      }
    });
  }

  void checkNonzas(Nonza nonza) {
    Log.d(TAG, "Received nonza: ${nonza.name}");

    if (nonza.name == 'proceed') {
      Log.d(TAG, "Received proceed response");
      if (!_proceedCompleter!.isCompleted) {
        _proceedCompleter!.complete(true);
      }
    } else if (nonza.name == 'failure') {
      Log.d(TAG, "Received failure response");
      if (!_proceedCompleter!.isCompleted) {
        _proceedCompleter!.complete(false);
      }
    }
  }
}

class StartTlsResponse extends Nonza {
  StartTlsResponse() {
    name = 'starttls';
    addAttribute(XmppAttribute('xmlns', 'urn:ietf:params:xml:ns:xmpp-tls'));
  }
}

class ForceAcceptingStartTlsNegotiator extends StartTlsNegotiator {
  static const TAG = 'ForceAcceptingStartTlsNegotiator';

  ForceAcceptingStartTlsNegotiator(Connection connection) : super(connection);

  @override
  void negotiate(List<Nonza> nonzas) {
    Log.d(TAG, 'negotiating starttls aggressively');
    Log.d(TAG, "STARTTLS: Beginning aggressive negotiation");
    state = NegotiatorState.NEGOTIATING;

    // Add this try-catch block for more detailed logging
    try {
      // First send the request
      Log.d(TAG, "STARTTLS: Sending request nonza");
      _connection.writeNonza(StartTlsResponse());
      Log.d(TAG, "STARTTLS: Request sent successfully");

      // Force TLS even without waiting for server response
      Log.d(TAG, "STARTTLS: Force starting TLS negotiation without waiting for response");
      Timer(Duration(milliseconds: 500), () {
        try {
          Log.d(TAG, "STARTTLS: Forcing secure socket after delay");
          _connection.startSecureSocket();
          state = NegotiatorState.DONE_CLEAN_OTHERS;
        } catch (e) {
          Log.d(TAG, "STARTTLS: Error during forced secure socket: $e");
        }
      });

      // Also set up normal response handling as backup
      subscription = _connection.inNonzasStream.listen(
              (nonza) {
            Log.d(TAG, "STARTTLS: Received nonza: ${nonza.name}");
            checkNonzas(nonza);
          },
          onError: (error) {
            Log.d(TAG, "STARTTLS: Error in nonza stream: $error");
          }
      );
    } catch (e) {
      Log.d(TAG, "STARTTLS: Exception during negotiation: $e");
    }
  }

  @override
  void checkNonzas(Nonza nonza) {
    Log.d(TAG, "STARTTLS: Processing nonza: ${nonza.name}");

    // If we get any response at all, try to secure the socket
    // This includes proceed, failure, or unexpected nonzas like stream
    try {
      Log.d(TAG, "STARTTLS: Attempting to secure socket after receiving ${nonza.name}");
      _connection.startSecureSocket();
      state = NegotiatorState.DONE_CLEAN_OTHERS;
      subscription.cancel();
    } catch (e) {
      Log.d(TAG, "STARTTLS: Error during secure socket attempt: $e");
    }
  }
}
