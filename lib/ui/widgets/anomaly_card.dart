import 'package:flutter/material.dart';
import '../../domain/models/anomaly_incident.dart';
import '../theme.dart';

/// Incident card displaying runaway drain culprit and one-tap remediation.
class AnomalyCard extends StatelessWidget {
  final AnomalyIncident incident;
  final VoidCallback? onRemediate;

  const AnomalyCard({
    super.key,
    required this.incident,
    this.onRemediate,
  });

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (incident.severity) {
      AnomalySeverity.mild => AppTheme.amber,
      AnomalySeverity.moderate => Colors.orangeAccent,
      AnomalySeverity.critical => AppTheme.crimson,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: severityColor.withOpacity(0.5), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: severityColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    incident.severity.name.toUpperCase(),
                    style: TextStyle(
                      color: severityColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Peak: ${incident.peakCurrentMa} mA',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              incident.diagnosis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                height: 1.3,
              ),
            ),
            if (incident.culpritPackage != null || incident.culpritThread != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        incident.culpritPackage ?? incident.culpritThread ?? '',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onRemediate != null && !incident.isRemediated)
                      InkWell(
                        onTap: onRemediate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.crimson.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'TAME APP',
                            style: TextStyle(
                              color: AppTheme.crimson,
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
