
// ignore_for_file: public_member_api_docs

class ReturnModel {
  ReturnModel({
    required this.id,
    required this.checkoutId,
    required this.adminId,
    required this.hasDamage,
    required this.returnedAt,
    this.deviceNotes,
  });

  factory ReturnModel.fromRow(List<dynamic> row) {
    return ReturnModel(
      id:           row[0] as String,
      checkoutId:   row[1] as String,
      adminId:      row[2] as String,
      deviceNotes:  row[3] as String?,
      hasDamage:    row[4] as bool,
      returnedAt:   row[5] as DateTime,
    );
  }

  final String  id;
  final String  checkoutId;
  final String  adminId;
  final String? deviceNotes;
  final bool    hasDamage;
  final DateTime returnedAt;

  Map<String, dynamic> toJson() => {
    'id':           id,
    'checkout_id':  checkoutId,
    'admin_id':     adminId,
    'device_notes': deviceNotes,
    'has_damage':   hasDamage,
    'returned_at':  returnedAt.toIso8601String(),
  };
}
