// mobile/lib/services/connections_service.dart
//
// The professional connection model (guidelines 2.4): send, accept, decline
// and remove connection requests, plus people search and suggestions.
//
// connections has TWO foreign keys to profiles (requester_id, addressee_id),
// so every embed names its constraint — a bare profiles(...) embed is
// ambiguous and PostgREST rejects it (PGRST201).
//
// The rules live in the database (migration 026): only the requester can
// create a request, only the addressee can accept or decline it, and either
// side can remove it. Nothing here re-implements those checks.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_error_mapper.dart';

enum RelationStatus { none, pendingOutgoing, pendingIncoming, connected }

class PersonSummary {
  const PersonSummary({
    required this.id,
    this.firstName = '',
    this.lastName = '',
    this.role = '',
    this.headline = '',
    this.avatarPath,
  });

  factory PersonSummary.fromRow(Map<String, dynamic> row, {String idKey = 'id'}) => PersonSummary(
        id: row[idKey] as String,
        firstName: (row['first_name'] as String?)?.trim() ?? '',
        lastName: (row['last_name'] as String?)?.trim() ?? '',
        role: row['role'] as String? ?? '',
        headline: (row['professional_headline'] as String?)?.trim() ?? '',
        avatarPath: row['avatar_path'] as String?,
      );

  final String id;
  final String firstName;
  final String lastName;
  final String role;
  final String headline;
  final String? avatarPath;

  String get name {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? 'Richfield member' : full;
  }

  String get roleLabel {
    switch (role) {
      case 'student':
        return 'Student';
      case 'alumni':
        return 'Alumni';
      case 'business':
        return 'Recruiter';
      case 'administrator':
        return 'Richfield staff';
      default:
        return '';
    }
  }

  /// Headline when there is one, otherwise the role — never an empty line.
  String get subtitle => headline.isNotEmpty ? headline : roleLabel;
}

class ConnectionEdge {
  const ConnectionEdge({
    required this.id,
    required this.status,
    required this.outgoing,
    required this.person,
  });

  final String id;

  /// 'pending' | 'accepted' | 'declined'
  final String status;

  /// True when the signed-in user sent the request.
  final bool outgoing;

  final PersonSummary person;
}

class NetworkSnapshot {
  NetworkSnapshot(this.edges);

  final List<ConnectionEdge> edges;

  List<ConnectionEdge> get connected => edges.where((e) => e.status == 'accepted').toList();
  List<ConnectionEdge> get incoming =>
      edges.where((e) => e.status == 'pending' && !e.outgoing).toList();
  List<ConnectionEdge> get outgoing =>
      edges.where((e) => e.status == 'pending' && e.outgoing).toList();

  ConnectionEdge? edgeWith(String personId) {
    for (final edge in edges) {
      if (edge.person.id == personId) return edge;
    }
    return null;
  }

  RelationStatus statusWith(String personId) {
    final edge = edgeWith(personId);
    if (edge == null) return RelationStatus.none;
    if (edge.status == 'accepted') return RelationStatus.connected;
    // A declined request stays "pending" to the person who sent it — telling
    // someone they were declined isn't how professional networks behave — and
    // stays acceptable for the person who declined it, in case they change
    // their mind (the addressee may still set it to 'accepted').
    return edge.outgoing ? RelationStatus.pendingOutgoing : RelationStatus.pendingIncoming;
  }
}

class SuggestedPerson {
  const SuggestedPerson({
    required this.person,
    required this.sharedSkills,
    required this.sameProgramme,
  });

  final PersonSummary person;
  final int sharedSkills;
  final bool sameProgramme;

  String get reason {
    final skills = '$sharedSkills shared skill${sharedSkills == 1 ? '' : 's'}';
    if (sameProgramme && sharedSkills > 0) return 'Same programme • $skills';
    if (sameProgramme) return 'Same programme';
    if (sharedSkills > 0) return skills;
    return person.subtitle;
  }
}

/// Connection errors worth their own wording; everything else goes through
/// AuthErrorMapper.
String connectionErrorMessage(Object error) {
  if (error is PostgrestException && error.code == '23505') {
    return 'You already have a connection or a pending request with this person.';
  }
  return AuthErrorMapper.fromAny(error);
}

class ConnectionsService {
  ConnectionsService(this._client);

  final SupabaseClient _client;

  static const personFields = 'id, first_name, last_name, role, professional_headline, avatar_path';

  Future<NetworkSnapshot> load(String me) async {
    final rows = await _client
        .from('connections')
        .select('id, status, requester_id, addressee_id, '
            'requester:profiles!connections_requester_id_fkey($personFields), '
            'addressee:profiles!connections_addressee_id_fkey($personFields)')
        .order('created_at', ascending: false);

    final edges = <ConnectionEdge>[];
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final outgoing = row['requester_id'] == me;
      final other = (outgoing ? row['addressee'] : row['requester']) as Map<String, dynamic>?;
      // Null when the other account is no longer active: profiles RLS hides it.
      if (other == null) continue;
      edges.add(ConnectionEdge(
        id: row['id'] as String,
        status: row['status'] as String? ?? 'pending',
        outgoing: outgoing,
        person: PersonSummary.fromRow(other),
      ));
    }
    return NetworkSnapshot(edges);
  }

  /// get_connection_suggestions() ranks by same programme, then shared skills,
  /// and already excludes anyone you have any connection row with.
  Future<List<SuggestedPerson>> suggestions({int limit = 20}) async {
    final rows = await _client.rpc('get_connection_suggestions', params: {'max_results': limit});
    return List<Map<String, dynamic>>.from(rows as List)
        .map((r) => SuggestedPerson(
              person: PersonSummary.fromRow(r, idKey: 'suggested_id'),
              sharedSkills: (r['shared_skills'] as num?)?.toInt() ?? 0,
              sameProgramme: r['same_programme'] as bool? ?? false,
            ))
        .toList();
  }

  /// Name / headline search over active, non-admin members.
  Future<List<PersonSummary>> search({required String me, required String query}) async {
    // Strip the characters PostgREST's or=() syntax treats as structure.
    final terms = query
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[,()*%\\:."]'), '').trim())
        .where((t) => t.length >= 2)
        .toList();
    if (terms.isEmpty) return const [];

    final first = terms.first;
    final rows = await _client
        .from('profiles')
        .select(personFields)
        .or('first_name.ilike.*$first*,last_name.ilike.*$first*,professional_headline.ilike.*$first*')
        .neq('id', me)
        .neq('role', 'administrator')
        .eq('account_status', 'active')
        .limit(30);

    // The server matched the first word; narrow by the rest here, so
    // "thabo nd" finds Thabo Ndlovu without needing a full-text index.
    return List<Map<String, dynamic>>.from(rows as List)
        .map((r) => PersonSummary.fromRow(r))
        .where((p) {
      final haystack = '${p.firstName} ${p.lastName} ${p.headline}'.toLowerCase();
      return terms.every((t) => haystack.contains(t.toLowerCase()));
    }).toList();
  }

  Future<bool> isConnected({required String me, required String personId}) async {
    final rows = await _client
        .from('connections')
        .select('id')
        .eq('status', 'accepted')
        .or('and(requester_id.eq.$me,addressee_id.eq.$personId),'
            'and(requester_id.eq.$personId,addressee_id.eq.$me)')
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<void> sendRequest({required String me, required String personId}) async {
    await _client.from('connections').insert({'requester_id': me, 'addressee_id': personId});
  }

  /// .select().single(): an UPDATE that RLS filters to zero rows succeeds
  /// silently, and "Accepted!" for a request that wasn't is worse than an error.
  Future<void> respond({required String connectionId, required bool accept}) async {
    await _client
        .from('connections')
        .update({'status': accept ? 'accepted' : 'declined'})
        .eq('id', connectionId)
        .select('id')
        .single();
  }

  /// Withdraws a request you sent, or removes an existing connection.
  Future<void> remove(String connectionId) async {
    await _client.from('connections').delete().eq('id', connectionId).select('id').single();
  }
}
