// ignore_for_file: public_member_api_docs

class Device {
  Device({
    required this.id,
    required this.number,
    required this.type,
    required this.status,
    required this.createdAt,
    this.statusNotes,
  });

  factory Device.fromRow(List<dynamic> row) {
    return Device(
      id: row[0] as String,
      number: row[1] as String,
      type: row[2] as String,
      status: row[3] as String,
      statusNotes: row[4] as String?,
      createdAt: row[5] as DateTime,
    );
  }

  final String id;
  final String number;
  final String type;
  final String status;
  final String? statusNotes;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'type': type,
    'status': status,
    'status_notes': statusNotes,
    'created_at': createdAt.toIso8601String(),
  };
}
