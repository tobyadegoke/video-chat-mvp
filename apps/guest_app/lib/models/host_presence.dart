enum HostStatus { offline, available, away, busy, live }

extension HostStatusExtension on HostStatus {
  String get value {
    switch (this) {
      case HostStatus.offline:
        return 'offline';
      case HostStatus.available:
        return 'available';
      case HostStatus.away:
        return 'away';
      case HostStatus.busy:
        return 'busy';
      case HostStatus.live:
        return 'live';
    }
  }
}

class HostPresence {
  final String id;
  final String hostId;
  final HostStatus status;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const HostPresence({
    required this.id,
    required this.hostId,
    required this.status,
    this.lastSeenAt,
    this.updatedAt,
    this.createdAt,
  });

  factory HostPresence.fromMap(Map<String, dynamic> map) {
    return HostPresence(
      id: map['id'] as String,
      hostId: map['host_id'] as String,
      status: _statusFromString(map['status'] as String?),
      lastSeenAt: map['last_seen_at'] != null
          ? DateTime.parse(map['last_seen_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  static HostStatus _statusFromString(String? value) {
    switch (value) {
      case 'available':
        return HostStatus.available;
      case 'away':
        return HostStatus.away;
      case 'busy':
        return HostStatus.busy;
      case 'live':
        return HostStatus.live;
      case 'offline':
      default:
        return HostStatus.offline;
    }
  }
}
