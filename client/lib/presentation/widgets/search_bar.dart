import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/route.dart';
import '../../state/routing_providers.dart';

enum SearchTarget { start, destination }

/// FR34 — geocode search for start/destination entry (backed by ctp-service's
/// /geocode, itself OSMnx's Nominatim wrapper). Map-tap is the other input
/// path, handled directly in RouteMap.
class GeocodeSearchField extends ConsumerStatefulWidget {
  final String label;
  final SearchTarget target;

  const GeocodeSearchField({super.key, required this.label, required this.target});

  @override
  ConsumerState<GeocodeSearchField> createState() => _GeocodeSearchFieldState();
}

class _GeocodeSearchFieldState extends ConsumerState<GeocodeSearchField> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(routingClientProvider);
      final result = await client.geocode(query);
      final provider =
          widget.target == SearchTarget.start ? startPointProvider : destinationPointProvider;
      ref.read(provider.notifier).state = LatLon(result.lat, result.lon);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        errorText: _error,
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(icon: const Icon(Icons.search), onPressed: _submit),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}
