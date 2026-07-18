/// The current observer configuration the home screen identifies against.
///
/// Defaults to a sensible location until M5 wires up device GPS / manual
/// entry. Exposed as a mutable [StateProvider] so the UI (and later the
/// location layer) can update it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/identify_config.dart';

/// A reasonable default until real location is available (central Stockholm).
const IdentifyConfig kDefaultConfig = IdentifyConfig(
  latitude: 59.3293,
  longitude: 18.0686,
);

final identifyConfigProvider = StateProvider<IdentifyConfig>(
  (ref) => kDefaultConfig,
);
