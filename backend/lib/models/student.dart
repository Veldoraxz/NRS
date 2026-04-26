// ignore_for_file: public_member_api_docs

class Student {
  Student({
    required this.id,
    required this.fullName,
    required this.email,
    required this.dni,
    required this.year,
    required this.division,
    required this.isActive,
    required this.createdAt,
    this.specialty,
  });

  factory Student.fromRow(List<dynamic> row) {
    return Student(
      id:        row[0] as String,
      fullName:  row[1] as String,
      email:     row[2] as String,
      dni:       row[3] as String,
      year:      row[4] as int,
      division:  row[5] as int,
      isActive:  row[6] as bool,
      createdAt: row[7] as DateTime,
      specialty: row[8] as String?,
    );
  }

  final String   id;
  final String   fullName;
  final String   email;
  final String   dni;
  final int      year;
  final int      division;
  final bool     isActive;
  final DateTime createdAt;
  final String?  specialty;

  /// Ciclo básico (1-3) no tiene especialidad.
  /// Ciclo superior (4-7) tiene especialidad obligatoria.
  String get cycle => year <= 3 ? 'ciclo_basico' : 'ciclo_superior';

  Map<String, dynamic> toJson() => {
    'id':         id,
    'full_name':  fullName,
    'email':      email,
    'dni':        dni,
    'year':       year,
    'division':   division,
    'is_active':  isActive,
    'created_at': createdAt.toIso8601String(),
    'specialty':  specialty ?? 'ciclo_basico',
    'cycle':      cycle,
  };
}
