import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'discovery_types.dart';

/// True: this platform can search the network.
const bool discoverySearchSupported = true;

/// Broadcasts [request] to UDP [port] on every local network and collects
/// the answers that arrive within [timeout]. The question is repeated a
/// couple of times because UDP may lose a packet. Never throws: any problem
/// just means fewer (or no) answers.
Future<List<UdpReply>> udpDiscover({
  required List<int> request,
  required int port,
  required Duration timeout,
}) async {
  final replies = <UdpReply>[];
  RawDatagramSocket? opened;
  StreamSubscription<RawSocketEvent>? subscription;
  final timers = <Timer>[];

  try {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    opened = socket;
    socket.broadcastEnabled = true;

    final targets = await _broadcastTargets();

    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }

      Datagram? datagram = socket.receive();

      while (datagram != null) {
        replies.add(UdpReply(datagram.data, datagram.address.address));
        datagram = socket.receive();
      }
    });

    void send() {
      for (final target in targets) {
        try {
          socket.send(request, target, port);
        } catch (error) {
          debugPrint('[Discovery] could not send to ${target.address}: $error');
        }
      }
    }

    send();
    timers.add(Timer(const Duration(milliseconds: 500), send));
    timers.add(Timer(const Duration(milliseconds: 1500), send));

    await Future<void>.delayed(timeout);
  } catch (error) {
    debugPrint('[Discovery] search failed: $error');
  } finally {
    for (final timer in timers) {
      timer.cancel();
    }

    await subscription?.cancel();
    opened?.close();
  }

  return replies;
}

/// The general broadcast address plus, for every IPv4 network this device is
/// on, that network's own broadcast address (assuming a /24, the usual home
/// and office size). Some devices drop the general one.
Future<List<InternetAddress>> _broadcastTargets() async {
  final targets = <InternetAddress>[InternetAddress('255.255.255.255')];

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');

        if (parts.length != 4 ||
            address.isLoopback ||
            address.address.startsWith('169.254.')) {
          continue;
        }

        final broadcast = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');

        if (!targets.contains(broadcast)) {
          targets.add(broadcast);
        }
      }
    }
  } catch (error) {
    debugPrint('[Discovery] could not list the networks: $error');
  }

  return targets;
}
