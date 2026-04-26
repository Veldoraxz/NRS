// ignore_for_file: public_member_api_docs

class Watchlist {
  Watchlist({
    required this.id,
    required this.dni,
    required this.fullName,
    required this.damageCount,
    required this.active,
    required this.updatedAt,
  });

  factory Watchlist.fromRow(List<dynamic> row) {
    return Watchlist(
      id:          row[0] as String,
      dni:         row[1] as String,
      fullName:    row[2] as String,
      damageCount: row[3] as int,
      active:      row[4] as bool,
      updatedAt:   row[5] as DateTime,
    );
  }

  final String   id;
  final String   dni;
  final String   fullName;
  final int      damageCount;
  final bool     active;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id':           id,
    'dni':          dni,
    'full_name':    fullName,
    'damage_count': damageCount,
    'active':       active,
    'updated_at':   updatedAt.toIso8601String(),
  };
}
