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
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;
  // Guards the point-provider listener below against re-stamping this
  // field's own successful search result as if it were an externally-set
  // point (e.g. a map tap) — see that listener for why the distinction
  // matters.
  bool _settingFromSelf = false;

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
      _settingFromSelf = true;
      ref.read(provider.notifier).state = LatLon(result.lat, result.lon);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Tabbing to the next field blurs this one without firing onSubmitted,
    // so a typed address was silently left ungeocoded until the user came
    // back and clicked the search icon. Losing focus now searches too.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _submit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.target == SearchTarget.start ? startPointProvider : destinationPointProvider;
    ref.listen<LatLon?>(provider, (previous, next) {
      if (next == null) {
        // Cleared from elsewhere (shape-change-clears-destination, or the
        // reset action) — otherwise the pin disappears but the typed
        // address stays, which reads as a half-reset.
        _controller.clear();
        return;
      }
      if (_settingFromSelf) {
        // Our own _submit() just set this — the typed address is already
        // the right text, don't overwrite it with coordinates.
        _settingFromSelf = false;
        return;
      }
      // Set some other way (a map tap) — there's no address text for that,
      // so show coordinates rather than leaving stale/blank text next to a
      // pin that just appeared on the map.
      _controller.text = '${next.lat.toStringAsFixed(5)}, ${next.lon.toStringAsFixed(5)}';
    });
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
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
