import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/route.dart';
import '../../domain/trip.dart';
import '../../state/routing_providers.dart';
import '../../state/trip_providers.dart';

String _displayText(Waypoint w) =>
    w.label ?? '${w.coord.lat.toStringAsFixed(5)}, ${w.coord.lon.toStringAsFixed(5)}';

/// FR10 — ordered waypoint entry: reorderable rows, each resolvable via
/// geocode search or "locate on map" (tapping the map while a row's pin icon
/// is active fills that row — see TripMap._handleTap). A trailing row adds a
/// new waypoint the same way; tapping the map with no row active appends
/// instead of editing one.
class WaypointList extends ConsumerWidget {
  const WaypointList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waypoints = ref.watch(waypointsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (waypoints.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: waypoints.length,
            onReorderItem: (oldIndex, newIndex) =>
                ref.read(waypointsProvider.notifier).reorder(oldIndex, newIndex),
            // Keyed by position, not by Waypoint identity: updateAt() always
            // replaces the waypoint at an index with a new immutable
            // instance, so an identity-based key would force a full
            // remount (losing focus/in-progress typing) on every edit. The
            // waypoints listener below keeps a row's text in sync with
            // whichever waypoint now occupies its position, including
            // across a reorder.
            itemBuilder: (context, index) => _WaypointRow(key: ValueKey('waypoint-row-$index'), index: index),
          ),
        const SizedBox(height: 8),
        const _AddWaypointRow(),
        const SizedBox(height: 4),
        const Text('(or tap the map)', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _WaypointRow extends ConsumerStatefulWidget {
  final int index;
  const _WaypointRow({required super.key, required this.index});

  @override
  ConsumerState<_WaypointRow> createState() => _WaypointRowState();
}

class _WaypointRowState extends ConsumerState<_WaypointRow> {
  late final TextEditingController _controller;
  bool _loading = false;
  String? _error;
  // Guards the waypoints listener below against re-stamping this row's own
  // just-resolved search text — same role as GeocodeSearchField's flag.
  bool _settingFromSelf = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayText(ref.read(waypointsProvider)[widget.index]));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
      _settingFromSelf = true;
      ref.read(waypointsProvider.notifier).updateAt(widget.index, LatLon(result.lat, result.lon), label: query);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(waypointsProvider, (previous, next) {
      if (widget.index >= next.length) return;
      if (_settingFromSelf) {
        _settingFromSelf = false;
        return;
      }
      // Set some other way (a map tap via TripMap) — refresh this row's text
      // to the new coordinates rather than leaving the old address showing.
      final text = _displayText(next[widget.index]);
      if (_controller.text != text) _controller.text = text;
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.drag_handle)),
          ),
          CircleAvatar(radius: 12, child: Text(waypointLetter(widget.index), style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _error,
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(icon: const Icon(Icons.search, size: 18), onPressed: _submit),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Locate on map',
            onPressed: () => ref.read(activeWaypointSlotProvider.notifier).state = widget.index,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove waypoint',
            onPressed: () => ref.read(waypointsProvider.notifier).removeAt(widget.index),
          ),
        ],
      ),
    );
  }
}

class _AddWaypointRow extends ConsumerStatefulWidget {
  const _AddWaypointRow();

  @override
  ConsumerState<_AddWaypointRow> createState() => _AddWaypointRowState();
}

class _AddWaypointRowState extends ConsumerState<_AddWaypointRow> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
      ref.read(waypointsProvider.notifier).add(LatLon(result.lat, result.lon), label: query);
      _controller.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Add waypoint',
        border: const OutlineInputBorder(),
        errorText: _error,
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(icon: const Icon(Icons.add), onPressed: _submit),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}
