// lib/presentation/widgets/device_card.dart
// Slot picker que consulta la disponibilidad real al backend.
// Restricciones reales del backend:
//   - Máx 14 días adelante
//   - Sin sábado/domingo
//   - Horario 07:30 – 22:00

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/auth_provider.dart';
import '../../application/providers/notebook_list_provider.dart';
import '../../application/providers/timer_provider.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/user.dart';
import '../theme/theme_provider.dart';

class DeviceCard extends ConsumerWidget {
  final Device device;
  final VoidCallback? onCancel;

  /// Si está presente, se invoca al tocar "Reservar". Útil para que el caller
  /// arme su propio flujo (por ejemplo el flujo de invitado en la home).
  final VoidCallback? onReserveTap;

  const DeviceCard({
    super.key,
    required this.device,
    this.onCancel,
    this.onReserveTap,
  });

  Future<void> _handleReserve(BuildContext context, WidgetRef ref) async {
    if (onReserveTap != null) {
      onReserveTap!();
      return;
    }
    await DeviceCardActions.startReservation(context, ref, device);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerSecs = ref.watch(timerProvider);
    final isAvailable = device.status == DeviceStatus.available;
    final isInUse = device.status == DeviceStatus.inUse;

    return Card(
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              device.model == DeviceModel.tv
                  ? Icons.tv
                  : Icons.laptop_chromebook,
              size: 32,
              color: isAvailable
                  ? AppTheme.primaryBlue
                  : AppTheme.textColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 6),
            Text(
              device.number,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            if (device.statusNotes != null) ...[
              const SizedBox(height: 2),
              Text(
                device.statusNotes!,
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.statusOff),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            _StatusBadge(status: device.status),

            // Cronómetro de tolerancia
            if (timerSecs > 0) ...[
              const SizedBox(height: 4),
              Text(
                _fmt(timerSecs),
                style: TextStyle(
                  color: timerSecs < 120
                      ? AppTheme.statusMaint
                      : AppTheme.statusInUse,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],

            const Spacer(),

            if (isAvailable) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleReserve(context, ref),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Reservar'),
                ),
              ),
            ],

            if (isInUse && onCancel != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusMaint,
                    side: const BorderSide(color: AppTheme.statusMaint),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

/// Helper público para disparar el flujo de reserva existente
/// (selector de fecha + slot picker + POST /reservations) sobre un dispositivo.
class DeviceCardActions {
  const DeviceCardActions._();

  static Future<void> startReservation(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final user = ref.read(authProvider).value;
    if (user == null) return;

    // El flujo individual reserva exactamente un dispositivo, igual para
    // alumno y profesor. Para múltiples dispositivos, el profesor usa el
    // botón de "Reserva múltiple" en el home.
    final selected = <Device>[device];

    // 2. Elegir fecha — máx 14 días, sin fines de semana.
    final today = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _nextWeekday(today),
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
      selectableDayPredicate: (d) =>
          d.weekday != DateTime.saturday && d.weekday != DateTime.sunday,
    );
    if (pickedDate == null || !context.mounted) return;

    // 3. Obtener slots ocupados del primer dispositivo (referencia).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Consultando disponibilidad...'),
            ]),
          ),
        ),
      ),
    );

    Set<String> blocked = {};
    try {
      blocked = await ref
          .read(notebookListProvider.notifier)
          .getBlockedSlots(selected.first.id, pickedDate);
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.of(context).pop();

    // 4. Selector de slot horario (retiro + devolución).
    final result = await SlotPickerDialog.show(
      context,
      day: pickedDate,
      blocked: blocked,
    );
    if (result == null || !context.mounted) return;

    // 5. Diálogo de revisión / confirmación previa.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ReservationReviewDialog(
        devices: selected,
        date: pickedDate,
        startTime: result.start,
        endTime: result.end,
        roleLabel: user.role == UserRole.teacher ? 'Profesor' : 'Alumno',
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // 6. Reservar según rol.
    try {
      if (user.role == UserRole.teacher) {
        await ref.read(notebookListProvider.notifier).reserveForTeacher(
              deviceType: device.model == DeviceModel.tv
                  ? 'television'
                  : 'notebook',
              deviceIds: selected.map((d) => d.id).toList(),
              date: pickedDate,
              startTime: result.start,
              endTime: result.end,
            );
      } else {
        await ref.read(notebookListProvider.notifier).reserveDevice(
              device.id,
              pickedDate,
              result.start,
              result.end,
            );
      }

      // Cronómetro visual de tolerancia (la auto-cancelación real
      // se hace en el backend a los 10 min del start_time).
      ref.read(timerProvider.notifier).startReservationTimer(() {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'La ventana de tolerancia (10 min) finalizó.',
            ),
            backgroundColor: AppTheme.statusMaint,
          ));
        }
      });

      if (context.mounted) {
        final summary = selected.length == 1
            ? selected.first.number
            : '${selected.length} dispositivos';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ $summary reservado para ${result.start}'),
          backgroundColor: AppTheme.statusAvailable,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppTheme.statusMaint,
        ));
      }
    }
  }

  static DateTime _nextWeekday(DateTime from) {
    var d = from;
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}

class _StatusBadge extends StatelessWidget {
  final DeviceStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DeviceStatus.available   => AppTheme.statusAvailable,
      DeviceStatus.inUse       => AppTheme.statusInUse,
      DeviceStatus.maintenance => AppTheme.statusMaint,
      DeviceStatus.outOfService => AppTheme.statusOff,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        Device.statusLabel(status),
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ─── Diálogo selector de slot horario ────────────────────────────────────────
// Slots de 1 hora. Horario backend: 07:30 – 22:00.
// Ocupados aparecen tachados y deshabilitados.

/// Diálogo de selección de horario con horarios predeterminados.
/// Permite elegir hora de retiro Y hora de devolución por separado.
/// Usado por todos los flujos de reserva (alumno, profesor, invitado).
class SlotPickerDialog extends StatefulWidget {
  final DateTime day;
  final Set<String> blocked;
  final String? initialStart;
  final String? initialEnd;

  const SlotPickerDialog({
    super.key,
    required this.day,
    this.blocked = const {},
    this.initialStart,
    this.initialEnd,
  });

  static Future<({String start, String end})?> show(
    BuildContext context, {
    required DateTime day,
    Set<String> blocked = const {},
    String? initialStart,
    String? initialEnd,
  }) {
    return showDialog<({String start, String end})>(
      context: context,
      builder: (_) => SlotPickerDialog(
        day: day,
        blocked: blocked,
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
  }

  @override
  State<SlotPickerDialog> createState() => _SlotPickerDialogState();
}

class _SlotPickerDialogState extends State<SlotPickerDialog> {
  // Backend: rango 07:30 – 22:00.
  // Inicios posibles: 07:30 + horarios en punto hasta 21:00.
  static const _startSlots = [
    '07:30', '08:00', '09:00', '10:00', '11:00', '12:00',
    '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
    '19:00', '20:00', '21:00',
  ];
  // Fines posibles: 08:00 hasta 22:00 (siempre después del inicio).
  static const _endSlots = [
    '08:00', '08:30', '09:00', '10:00', '11:00', '12:00',
    '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
    '19:00', '20:00', '21:00', '22:00',
  ];

  String? _start;
  String? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  int _toMinutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  bool _isPast(String slot) {
    final now = DateTime.now();
    final p = slot.split(':');
    final dt = DateTime(widget.day.year, widget.day.month, widget.day.day,
        int.parse(p[0]), int.parse(p[1]));
    return dt.isBefore(now);
  }

  bool _endIsValid(String end) {
    if (_start == null) return true;
    return _toMinutes(end) > _toMinutes(_start!);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final dateStr = '${_p(d.day)}/${_p(d.month)}/${d.year}';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        'Elegí horario — $dateStr',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SlotSectionLabel('Hora de retiro'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final slot in _startSlots)
                    _Chip(
                      label: slot,
                      isBlocked: widget.blocked.contains(slot),
                      isPast: _isPast(slot),
                      isSelected: _start == slot,
                      onTap: (widget.blocked.contains(slot) || _isPast(slot))
                          ? null
                          : () {
                              setState(() {
                                _start = slot;
                                if (_end != null && !_endIsValid(_end!)) {
                                  _end = null;
                                }
                              });
                            },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const _SlotSectionLabel('Hora de devolución'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final slot in _endSlots)
                    _Chip(
                      label: slot,
                      isBlocked: false,
                      // Inválido: si no eligió start, o si es <= start.
                      isPast: !_endIsValid(slot),
                      isSelected: _end == slot,
                      onTap: !_endIsValid(slot)
                          ? null
                          : () => setState(() => _end = slot),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: (_start == null || _end == null || !_endIsValid(_end!))
              ? null
              : () => Navigator.of(context).pop((
                    start: _start!,
                    end: _end!,
                  )),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _SlotSectionLabel extends StatelessWidget {
  final String text;
  const _SlotSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTheme.primaryBlue,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isBlocked;
  final bool isPast;
  final bool isSelected;
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.isBlocked,
    required this.isPast,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = isBlocked || isPast;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue
              : disabled
                  ? Colors.grey.shade100
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : disabled
                    ? Colors.grey.shade300
                    : AppTheme.secondaryBlue.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : disabled
                    ? Colors.grey.shade400
                    : AppTheme.textDark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: isBlocked ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo de revisión / confirmación previa ───────────────────────────────

class ReservationReviewDialog extends StatelessWidget {
  final List<Device> devices;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String roleLabel;

  const ReservationReviewDialog({
    required this.devices,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.roleLabel,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _devicesLabel() {
    if (devices.isEmpty) return '—';
    final isTv = devices.first.model == DeviceModel.tv;
    final type = isTv ? 'TV' : 'Notebook';
    if (devices.length == 1) {
      return '$type N° ${devices.first.number}';
    }
    return '${devices.length} notebooks: '
        '${devices.map((d) => d.number).join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: AppTheme.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Revisá tu reserva',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Antes de confirmar, asegurate de que los datos sean correctos.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          _ReviewRow(label: 'Tipo de usuario', value: roleLabel),
          _ReviewRow(label: 'Dispositivo(s)', value: _devicesLabel()),
          _ReviewRow(label: 'Fecha', value: _fmtDate(date)),
          _ReviewRow(
            label: 'Horario',
            value: '$startTime – $endTime',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: Color(0xFFB28704),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Si no retirás dentro de los 10 minutos del inicio, '
                    'la reserva se cancela automáticamente.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7C5500),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Volver'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirmar reserva'),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
