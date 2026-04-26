// ignore_for_file: public_member_api_docs

class Damage {
  Damage({
    required this.id,
    required this.dni,
    required this.returnId,
    required this.description,
    required this.createdAt,
  });

  factory Damage.fromRow(List<dynamic> row) {
    return Damage(
      id:          row[0] as String,
      dni:         row[1] as String,
      returnId:    row[2] as String,
      description: row[3] as String,
      createdAt:   row[4] as DateTime,
    );
  }

  final String   id;
  final String   dni;
  final String   returnId;
  final String   description;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id':          id,
    'dni':         dni,
    'return_id':   returnId,
    'description': description,
    'created_at':  createdAt.toIso8601String(),
  };
}
