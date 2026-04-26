// ignore_for_file: public_member_api_docs

class Teacher {
  Teacher({
    required this.id,
    required this.fullName,
    required this.email,
    required this.dni,
    required this.createdAt,
    required this.isActive,
  });

  factory Teacher.fromRow(List<dynamic> row) {
    return Teacher(
      id:        row[0] as String,
      fullName:  row[1] as String,
      email:     row[2] as String,
      dni:       row[3] as String,
      createdAt: row[4] as DateTime,
      isActive:  row[5] as bool,
    );
  }

  final String   id;
  final String   fullName;
  final String   email;
  final String   dni;
  final DateTime createdAt;
  final bool     isActive;

  Map<String, dynamic> toJson() => {
    'id':         id,
    'full_name':  fullName,
    'email':      email,
    'dni':        dni,
    'created_at': createdAt.toIso8601String(),
    'is_active':  isActive,
  };
}
