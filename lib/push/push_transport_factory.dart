/// Web i ostale platforme bez `dart:io` nemaju push (plan §4.1) — tamo se
/// Firebase ne uvozi ni ne inicijalizira.
library;

import 'package:podcast_core/podcast_core.dart';

Future<PushTransport?> createPushTransport() async => null;
