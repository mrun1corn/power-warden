import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../domain/models/anomaly_incident.dart';
import 'theme.dart';

/// Sentinel Incident Log — the trust-builder screen.
/// Every anomaly detection is shown with its evidence: peak current,
/// temperature, diagnosis, culprit process, and remediation state.
class IncidentsScreen extends StatefulWidget {
  final Future<List<AnomalyIncident>> Function() loadIncidents;

  const IncidentsScreen({super.key, required this.loadIncidents});

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  List<AnomalyIncident> _incidents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Silent refresh after the first load — no spinner flash on pull-to-refresh
    if (_incidents.isEmpty) setState(() => _isLoading = true);
    final incidents = await widget.loadIncidents();
    if (mounted) {
      setState(() {
        _incidents = incidents;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident Log'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _incidents.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(Icons.verified_user_rounded,
                            size: 64,
                            color: AppTheme.healthColor(theme.brightness).withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No incidents detected',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The sentinel is watching. Any runaway drain,\nthermal event, or rogue process will be logged here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _incidents.length,
                      itemBuilder: (context, i) =>
                          _IncidentCard(incident: _incidents[i]),
                    ),
            ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final AnomalyIncident incident;

  const _IncidentCard({required this.incident});

  Color _severityColor(BuildContext context) {
    final b = Theme.of(context).brightness;
    switch (incident.severity) {
      case AnomalySeverity.mild:
        return AppTheme.healthColor(b);
      case AnomalySeverity.moderate:
        return AppTheme.warningColor(b);
      case AnomalySeverity.critical:
        return AppTheme.criticalColor(b);
    }
  }

  IconData _severityIcon() {
    switch (incident.severity) {
      case AnomalySeverity.mild:
        return Icons.info_rounded;
      case AnomalySeverity.moderate:
        return Icons.warning_amber_rounded;
      case AnomalySeverity.critical:
        return Icons.dangerous_rounded;
    }
  }

  String _severityLabel() =>
      incident.severity.name[0].toUpperCase() + incident.severity.name.substring(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _severityColor(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showEvidence(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_severityIcon(), color: color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      incident.diagnosis,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _severityLabel(),
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _evidenceChip(
                    context,
                    Icons.flash_on_rounded,
                    '${incident.peakCurrentMa.abs()} mA peak',
                  ),
                  const SizedBox(width: 8),
                  _evidenceChip(
                    context,
                    Icons.thermostat_rounded,
                    '${incident.maxTemperatureCelsius.toStringAsFixed(1)}°C',
                  ),
                  if (incident.culpritPackage != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _evidenceChip(
                        context,
                        Icons.bug_report_rounded,
                        incident.culpritPackage!,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    PowerFormatters.timestamp(incident.startTime),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (incident.isRemediated)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 14,
                            color: AppTheme.healthColor(theme.brightness)),
                        const SizedBox(width: 4),
                        Text('Remediated',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.healthColor(theme.brightness),
                            )),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _evidenceChip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.textTheme.bodySmall?.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showEvidence(BuildContext context) {
    final theme = Theme.of(context);
    final color = _severityColor(context);
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              width: 40,
              height: 4,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Icon(_severityIcon(), color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    incident.diagnosis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _evidenceRow(context, 'Detected',
                PowerFormatters.timestamp(incident.startTime)),
            if (incident.endTime != null)
              _evidenceRow(context, 'Resolved',
                  PowerFormatters.timestamp(incident.endTime!)),
            _evidenceRow(context, 'Severity', _severityLabel()),
            _evidenceRow(
                context, 'Peak current', '${incident.peakCurrentMa.abs()} mA'),
            _evidenceRow(context, 'Max temperature',
                '${incident.maxTemperatureCelsius.toStringAsFixed(1)}°C'),
            if (incident.culpritPackage != null)
              _evidenceRow(context, 'Culprit process', incident.culpritPackage!),
            if (incident.culpritThread != null)
              _evidenceRow(context, 'Culprit thread', incident.culpritThread!),
            _evidenceRow(
                context, 'Remediated', incident.isRemediated ? 'Yes' : 'No'),
            if (incident.recommendedAction != null) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RECOMMENDED ACTION',
                          style: theme.textTheme.labelSmall),
                      const SizedBox(height: 8),
                      Text(incident.recommendedAction!,
                          style: theme.textTheme.bodyLarge),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _evidenceRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
