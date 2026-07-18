/// The observer-location row: current coordinates, a "use my location"
/// action, and a manual-entry fallback.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/identify_config.dart';
import '../state/config_provider.dart';
import '../state/location_controller.dart';

class LocationBar extends ConsumerWidget {
  const LocationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(identifyConfigProvider);
    final locationState = ref.watch(locationControllerProvider);
    final locating = locationState is LocationLocating;

    // Surface location failures as a SnackBar, then reset the controller.
    ref.listen<LocationUiState>(locationControllerProvider, (previous, next) {
      if (next is LocationFailed) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(next.message)));
        ref.read(locationControllerProvider.notifier).clearError();
      }
    });

    final coords =
        '${config.latitude.toStringAsFixed(4)}, ${config.longitude.toStringAsFixed(4)}';

    return Row(
      children: [
        Expanded(
          child: Chip(
            avatar: const Icon(Icons.my_location, size: 18),
            label: Text('Observing from $coords'),
          ),
        ),
        IconButton(
          tooltip: 'Use my location',
          onPressed: locating
              ? null
              : () => ref
                  .read(locationControllerProvider.notifier)
                  .useCurrentLocation(),
          icon: locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.gps_fixed),
        ),
        IconButton(
          tooltip: 'Enter location',
          onPressed: () => _editLocation(context, ref, config),
          icon: const Icon(Icons.edit_location_alt_outlined),
        ),
      ],
    );
  }

  Future<void> _editLocation(
    BuildContext context,
    WidgetRef ref,
    IdentifyConfig current,
  ) async {
    final result = await showDialog<IdentifyConfig>(
      context: context,
      builder: (_) => _ManualLocationDialog(current: current),
    );
    if (result != null) {
      ref.read(identifyConfigProvider.notifier).state = result;
    }
  }
}

class _ManualLocationDialog extends StatefulWidget {
  final IdentifyConfig current;
  const _ManualLocationDialog({required this.current});

  @override
  State<_ManualLocationDialog> createState() => _ManualLocationDialogState();
}

class _ManualLocationDialogState extends State<_ManualLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lat;
  late final TextEditingController _lon;

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(text: widget.current.latitude.toString());
    _lon = TextEditingController(text: widget.current.longitude.toString());
  }

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  String? _validate(String? value, double min, double max) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a number';
    if (parsed < min || parsed > max) return 'Must be between $min and $max';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final config = widget.current.copyWith(
      latitude: double.parse(_lat.text.trim()),
      longitude: double.parse(_lon.text.trim()),
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );
    final inputFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
    ];

    return AlertDialog(
      title: const Text('Enter location'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _lat,
              keyboardType: numeric,
              inputFormatters: inputFormatters,
              decoration: const InputDecoration(labelText: 'Latitude'),
              validator: (v) => _validate(v, -90.0, 90.0),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _lon,
              keyboardType: numeric,
              inputFormatters: inputFormatters,
              decoration: const InputDecoration(labelText: 'Longitude'),
              validator: (v) => _validate(v, -180.0, 180.0),
            ),
          ],
        ),
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
