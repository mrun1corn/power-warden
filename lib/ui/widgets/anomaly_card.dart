import 'package:flutter/material.dart';
import '../../domain/models/anomaly_incident.dart';
import '../theme.dart';

/// Streamlined, modern Incident Card for Sentinel Log.
/// Emphasizes clear human readability, exact time epoch, peak impact,
/// and instant 1-tap mitigation without technical visual clutter.
class AnomalyCard extends StatelessWidget {
  final AnomalyIncident incident;
  final VoidCallback? onRemediate;

  const AnomalyCard({
    super.key,
    required this.incident,
    this.onRemediate,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (incident.severity) {
      AnomalySeverity.mild => AppTheme.amber,
      AnomalySeverity.moderate => Colors.orangeAccent,
      AnomalySeverity.critical => AppTheme.crimson,
    };

    final culprit = incident.culpritPackage ?? incident.culpritThread;
    final friendlyCulprit = culprit?.split('.').last.replaceAll('_', ' ').toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: incident.severity == AnomalySeverity.critical
              ? AppTheme.crimson.withOpacity(0.4)
              : AppTheme.surfaceBorder,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Severity pill, Time, Peak mA
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: severityColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  incident.severity.name.toUpperCase(),
                  style: TextStyle(
                    color: severityColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '•  ${_formatTime(incident.startTime)}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${incident.peakCurrentMa} mA',
                    style: TextStyle(
                      color: severityColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Plain diagnosis headline
            Text(
              incident.diagnosis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),

            // Culprit action banner if an app is pinpointed
            if (culprit != null && culprit.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.chargingCyan),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            friendlyCulprit ?? 'ROGUE BACKGROUND THREAD',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            culprit,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onRemediate != null)
                      SizedBox(
                        height: 28,
                        child: ElevatedButton(
                          onPressed: incident.isRemediated ? null : onRemediate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: incident.isRemediated
                                ? AppTheme.surfaceBorder
                                : AppTheme.crimson.withOpacity(0.2),
                            foregroundColor: incident.isRemediated ? AppTheme.textMuted : AppTheme.crimson,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(
                            incident.isRemediated ? 'TAMED' : 'STOP APP',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
