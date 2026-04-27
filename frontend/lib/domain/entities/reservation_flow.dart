// lib/domain/entities/reservation_flow.dart
//
// Estado lógico de una reserva combinando status crudo y datos de checkout.

enum ReservationFlowState { pending, active, finalized, cancelled }

ReservationFlowState resolveReservationFlow(Map<String, dynamic> reservation) {
  final status     = reservation['status']?.toString().toLowerCase() ?? '';
  final checkoutId = reservation['checkout_id']?.toString();
  final returnedAt = reservation['returned_at']?.toString();

  if (status == 'cancelled') return ReservationFlowState.cancelled;

  final hasCheckout = checkoutId != null && checkoutId.isNotEmpty;
  final hasReturn   = returnedAt != null && returnedAt.isNotEmpty;

  if (hasCheckout && !hasReturn) return ReservationFlowState.active;
  if (status == 'pending' || status == 'confirmed') {
    return ReservationFlowState.pending;
  }
  return ReservationFlowState.finalized;
}
