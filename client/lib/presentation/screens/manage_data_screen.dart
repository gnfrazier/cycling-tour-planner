import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/routing_providers.dart';

/// FR38 (first-start region) + FR39 (desktop pruning), scoped down: only NC
/// is wired to real (already-downloaded) data — WI/SoCal show as
/// "coming soon" rather than integrating live OpenTopography downloads.
class ManageDataScreen extends ConsumerWidget {
  const ManageDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloaded regions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('North Carolina'),
              subtitle: const Text(
                'Marion / western NC — street graph + GEDTM30 elevation, cached locally',
              ),
              trailing: TextButton(
                onPressed: () => _confirmClear(context, ref),
                child: const Text('Clear cache'),
              ),
            ),
          ),
          const _ComingSoonRegion(name: 'Wisconsin'),
          const _ComingSoonRegion(name: 'Southern California'),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cached NC data?'),
        content: const Text(
          'Deletes the locally cached street graph on disk. It will be re-fetched '
          'the next time the routing engine starts.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                final cleared = await ref.read(routingClientProvider).clearCache();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      cleared ? 'Cache cleared. Restart the backend to re-download.' : 'No cache to clear.',
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Could not clear cache: $e')));
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonRegion extends StatelessWidget {
  final String name;

  const _ComingSoonRegion({required this.name});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.hourglass_empty),
        title: Text(name),
        subtitle: const Text('Coming soon'),
        enabled: false,
      ),
    );
  }
}
