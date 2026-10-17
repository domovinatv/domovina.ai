/// Native stub — cast iz preglednika postoji samo na webu.
library;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'remote_playback.dart';

VoidCallback bindRemotePlayback(
  Player player, {
  required void Function(RemoteTarget? target) onTarget,
  required void Function(RemoteState state) onState,
}) => () {};

Future<void> promptRemotePlayback(Player player) async {}
