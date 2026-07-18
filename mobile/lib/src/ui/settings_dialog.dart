/// A settings dialog for the two identification tuning knobs that were
/// previously only reachable via [IdentifyConfig] defaults: the horizontal
/// search radius and the minimum elevation angle considered "overhead".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/identify_config.dart';
import '../state/config_provider.dart';

/// Opens the settings dialog and, on save, writes the updated radius and
/// minimum elevation back into [identifyConfigProvider].
Future<void> showSettingsDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(identifyConfigProvider);
  final result = await showDialog<IdentifyConfig>(
    context: context,
    builder: (_) => _SettingsDialog(current: current),
  );
  if (result != null) {
    ref.read(identifyConfigProvider.notifier).state = result;
  }
}

class _SettingsDialog extends StatefulWidget {
  final IdentifyConfig current;
  const _SettingsDialog({required this.current});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  // OpenSky-friendly radius range, matching IdentifyConfig.effectiveRadiusKm.
  static const double _minRadiusKm = 1.0;
  static const double _maxRadiusKm = 50.0;
  // Elevation angle above the horizon, 0 (horizon) .. 90 (straight up).
  static const double _minElevation = 0.0;
  static const double _maxElevation = 90.0;

  late double _radiusKm;
  late double _minElevationDeg;

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.current.searchRadiusKm.clamp(_minRadiusKm, _maxRadiusKm);
    _minElevationDeg =
        widget.current.minElevationDeg.clamp(_minElevation, _maxElevation);
  }

  void _submit() {
    final config = widget.current.copyWith(
      searchRadiusKm: _radiusKm,
      minElevationDeg: _minElevationDeg,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Search radius', style: theme.textTheme.titleSmall),
          Text(
            '${_radiusKm.toStringAsFixed(0)} km',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: _radiusKm,
            min: _minRadiusKm,
            max: _maxRadiusKm,
            divisions: (_maxRadiusKm - _minRadiusKm).round(),
            label: '${_radiusKm.toStringAsFixed(0)} km',
            onChanged: (v) => setState(() => _radiusKm = v),
          ),
          const SizedBox(height: 16),
          Text('Minimum elevation', style: theme.textTheme.titleSmall),
          Text(
            '${_minElevationDeg.toStringAsFixed(0)}° above the horizon',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: _minElevationDeg,
            min: _minElevation,
            max: _maxElevation,
            divisions: (_maxElevation - _minElevation).round(),
            label: '${_minElevationDeg.toStringAsFixed(0)}°',
            onChanged: (v) => setState(() => _minElevationDeg = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
