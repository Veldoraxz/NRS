// ignore_for_file: public_member_api_docs

class Checkout {
  Checkout({
    required this.id,
    required this.reservationId,
    required this.adminId,
    required this.checkedOutAt,
    this.deviceNotes,
  });

  factory Checkout.fromRow(List<dynamic> row) {
    return Checkout(
      id:            row[0] as String,
      reservationId: row[1] as String,
      adminId:       row[2] as String,
      deviceNotes:   row[3] as String?,
      checkedOutAt:  row[4] as DateTime,
    );
  }

  final String  id;
  final String  reservationId;
  final String  adminId;
  final String? deviceNotes;
  final DateTime checkedOutAt;

  Map<String, dynamic> toJson() => {
    'id':             id,
    'reservation_id': reservationId,
    'admin_id':       adminId,
    'device_notes':   deviceNotes,
    'checked_out_at': checkedOutAt.toIso8601String(),
  };
}
