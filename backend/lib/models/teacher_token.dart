// ignore_for_file: public_member_api_docs

class TeacherToken {
  TeacherToken({
    required this.id,
    required this.reservationId,
    required this.token,
    required this.used,
    required this.expiresAt,
  });

  factory TeacherToken.fromRow(List<dynamic> row) {
    return TeacherToken(
      id:            row[0] as String,
      reservationId: row[1] as String,
      token:         row[2] as String,
      used:          row[3] as bool,
      expiresAt:     row[4] as DateTime,
    );
  }

  final String   id;
  final String   reservationId;
  final String   token;
  final bool     used;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'id':             id,
    'reservation_id': reservationId,
    'token':          token,
    'used':           used,
    'expires_at':     expiresAt.toIso8601String(),
    'is_expired':     isExpired,
  };
}
