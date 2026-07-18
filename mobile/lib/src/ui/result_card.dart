/// The card shown when an aircraft is identified overhead.
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'format.dart' as fmt;

class ResultCard extends StatelessWidget {
  final IdentifyResult result;

  const ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final candidate = result.candidate!;
    final theme = Theme.of(context);
    final subtitle = fmt.aircraftSubtitle(candidate);
    final origin = fmt.airportLabel(candidate.origin);
    final destination = fmt.airportLabel(candidate.destination);
    final hasRoute = origin != null || destination != null;
    final airline = candidate.airline?.trim();
    final operator =
        (airline != null && airline.isNotEmpty) ? airline : candidate.registeredOwnerOperator?.trim();
    final unavailable =
        candidate.enrichmentStatus == EnrichmentStatus.unavailable;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidate.photoUrl != null && candidate.photoUrl!.isNotEmpty)
            _Photo(url: candidate.photoUrl!),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        fmt.candidateHeadline(candidate),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _ConfidenceBadge(confidence: result.confidence),
                  ],
                ),
                if (operator != null && operator.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(operator, style: theme.textTheme.titleMedium),
                ],
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                ],
                if (hasRoute) ...[
                  const SizedBox(height: 8),
                  _RouteLine(
                    icon: Icons.flight_takeoff,
                    label: origin ?? 'Unknown origin',
                  ),
                  const SizedBox(height: 4),
                  _RouteLine(
                    icon: Icons.flight_land,
                    label: destination ?? 'Unknown destination',
                  ),
                ],
                const SizedBox(height: 16),
                _Metrics(candidate: candidate),
                if (unavailable) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Aircraft details are unavailable right now — position is '
                    'from live tracking.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  final String url;
  const _Photo({required this.url});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.flight, size: 48),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RouteLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  final Candidate candidate;
  const _Metrics({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final speed = fmt.speedText(candidate.speedMps);
    final metrics = <(IconData, String, String)>[
      (Icons.height, 'Elevation', fmt.elevationText(candidate.elevationDeg)),
      (Icons.explore, 'Bearing', fmt.bearingText(candidate.bearingDeg)),
      (Icons.straighten, 'Distance', fmt.distanceText(candidate.distanceKm)),
      (
        Icons.terrain,
        'Altitude',
        fmt.altitudeText(candidate.altitudeM, candidate.altitudeSource),
      ),
      if (speed != null) (Icons.speed, 'Speed', speed),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        for (final (icon, label, value) in metrics)
          _Metric(icon: icon, label: label, value: value),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final Confidence confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (confidence) {
      Confidence.high => (scheme.primaryContainer, scheme.onPrimaryContainer),
      Confidence.medium => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      Confidence.ambiguous => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      Confidence.none => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        fmt.confidenceLabel(confidence),
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
