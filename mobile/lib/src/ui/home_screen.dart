/// The app's single screen: a location chip, a big "what's overhead?"
/// button, and a result area that reflects the [IdentifyController] state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/config_provider.dart';
import '../state/identify_controller.dart';
import 'location_bar.dart';
import 'result_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(identifyControllerProvider);
    final config = ref.watch(identifyConfigProvider);
    final isLoading = state is IdentifyLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Sky Overhead')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LocationBar(),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isLoading
                    ? null
                    : () => ref
                        .read(identifyControllerProvider.notifier)
                        .identify(config),
                icon: const Icon(Icons.flight),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("What's overhead?"),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _ResultArea(key: ValueKey(state.runtimeType), state: state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultArea extends ConsumerWidget {
  final IdentifyUiState state;
  const _ResultArea({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (state) {
      case IdentifyIdle():
        return const _Centered(
          icon: Icons.travel_explore,
          title: 'Point at the sky',
          message: 'Tap the button to identify the aircraft overhead.',
        );
      case IdentifyLoading():
        return const _Centered(
          icon: null,
          title: 'Scanning the sky…',
          message: 'Looking up live traffic near you.',
          showSpinner: true,
        );
      case IdentifySuccess(:final result):
        if (result.hasCandidate) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [ResultCard(result: result)],
            ),
          );
        }
        return _Centered(
          icon: Icons.cloud_queue,
          title: 'Clear skies',
          message: result.message ?? 'No aircraft overhead right now.',
        );
      case IdentifyFailure(:final message):
        return _Centered(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: message,
          action: FilledButton.tonal(
            onPressed: () {
              final config = ref.read(identifyConfigProvider);
              ref.read(identifyControllerProvider.notifier).identify(config);
            },
            child: const Text('Try again'),
          ),
        );
    }
  }
}

class _Centered extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String message;
  final bool showSpinner;
  final Widget? action;

  const _Centered({
    required this.icon,
    required this.title,
    required this.message,
    this.showSpinner = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const CircularProgressIndicator()
          else if (icon != null)
            Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}
