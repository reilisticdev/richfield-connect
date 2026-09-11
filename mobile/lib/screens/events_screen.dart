// mobile/lib/screens/events_screen.dart
//
// Every upcoming official Richfield event, soonest first. The Feed banner
// only has room for one event, so until this screen existed any other event
// an administrator published was unreachable from the app (Keshav's QA
// pass, 2026-09-11: three events published on the web admin, one visible on
// the phone). Opened from the banner's "See all events" and from the account
// menu, so it stays reachable after the banner is dismissed.
//
// Only published events that haven't started are listed. events' SELECT
// policy already hides drafts from non-administrators; FeedService filters
// on status too, so an administrator's phone doesn't list drafts either.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/auth_error_mapper.dart';
import '../services/feed_service.dart';
import '../widgets/time_labels.dart' show eventDateLabel;

const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _feedService = FeedService(Supabase.instance.client);

  /// Null until the first load succeeds; an empty list means none upcoming.
  List<Map<String, dynamic>>? _events;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await _feedService.fetchUpcomingEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = AuthErrorMapper.fromAny(e);
      // A failed pull-to-refresh keeps the list already on screen.
      if (_events != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Events', style: AppText.headlineSm()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : events == null
              ? Center(
                  child: SingleChildScrollView(
                    child: _Message(
                      icon: Icons.cloud_off_outlined,
                      title: 'Couldn\'t load events',
                      body: _error ?? 'Please try again.',
                      actionLabel: 'Try again',
                      onAction: _load,
                    ),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _content(events)),
    );
  }

  Widget _content(List<Map<String, dynamic>> events) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, AppSpace.xxl),
      children: [
        Text('Upcoming Richfield events', style: AppText.headlineMd()),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Official events published by Richfield, soonest first.',
          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpace.base),
        if (events.isEmpty)
          const _Message(
            icon: Icons.event_busy_outlined,
            title: 'No upcoming events',
            body: 'Events appear here as soon as Richfield publishes them. Pull down to refresh.',
          )
        else ...[
          Text(
            '${events.length} ${events.length == 1 ? 'event' : 'events'}',
            style: AppText.headlineSm(),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final event in events) ...[
            _EventCard(event: event),
            const SizedBox(height: AppSpace.md),
          ],
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(event['event_date'] as String? ?? '')?.toLocal();
    final title = (event['title'] as String?)?.trim() ?? '';
    final location = (event['location'] as String?)?.trim() ?? '';
    final description = (event['description'] as String?)?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(AppSpace.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (date != null) ...[
            _DateBlock(date: date),
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? 'Richfield event' : title, style: AppText.labelLg()),
                if (date != null) ...[
                  const SizedBox(height: 4),
                  _detail(Icons.schedule, eventDateLabel(date)),
                ],
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _detail(Icons.location_on_outlined, location),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(description, style: AppText.bodySm()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: AppText.bodySm(color: AppColors.onSurfaceVariant))),
      ],
    );
  }
}

/// Calendar-style day/month tile, so the list scans by date at a glance.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Text(_months[date.month - 1], style: AppText.labelMd(color: AppColors.primary)),
          Text('${date.day}', style: AppText.headlineSm(color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: AppSpace.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: AppSpace.sm),
          Text(title, textAlign: TextAlign.center, style: AppText.headlineSm()),
          const SizedBox(height: AppSpace.xs),
          Text(body, textAlign: TextAlign.center, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
