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

  const DeviceCard({
    super.key,
    required this.device,
    this.onCancel,
  });

  Future<void> _handleReserve(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authProvider).value;
    if (user == null) return;

    // 1. Elegir fecha — máx 14 días, sin fines de semana
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

    // 2. Obtener slots ocupados del backend
    showDialog(
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
          .getBlockedSlots(device.id, pickedDate);
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.of(context).pop();

    // 3. Selector de slot horario
    final result = await showDialog<({String start, String end})>(
      context: context,
      builder: (ctx) =>
          _SlotPickerDialog(day: pickedDate, blocked: blocked),
    );
    if (result == null || !context.mounted) return;

    // 4. Reservar según rol
    try {
      if (user.role == UserRole.teacher) {
        await ref.read(notebookListProvider.notifier).reserveForTeacher(
              deviceType: device.model == DeviceModel.tv ? 'television' : 'notebook',
              deviceIds: [device.id],
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

      // Iniciar cronómetro de tolerancia de 10 min
      ref.read(timerProvider.notifier).startReservationTimer(() {
        ref.read(notebookListProvider.notifier).cancelReservation(device.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Reserva expirada por inactividad (10 min).'),
            backgroundColor: AppTheme.statusMaint,
          ));
        }
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ ${device.number} reservado para ${result.start}'),
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

  DateTime _nextWeekday(DateTime from) {
    var d = from;
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
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

class _SlotPickerDialog extends StatefulWidget {
  final DateTime day;
  final Set<String> blocked;
  const _SlotPickerDialog({required this.day, required this.blocked});

  @override
  State<_SlotPickerDialog> createState() => _SlotPickerDialogState();
}

class _SlotPickerDialogState extends State<_SlotPickerDialog> {
  int? _sel;

  // Slots del backend: 07:30 a 21:00 (end = slot + 1h, máx 22:00)
  static const _slots = [
    '07:30', '08:00', '09:00', '10:00', '11:00', '12:00',
    '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
    '19:00', '20:00', '21:00',
  ];

  bool _isPast(String slot) {
    final now = DateTime.now();
    final p = slot.split(':');
    final dt = DateTime(widget.day.year, widget.day.month,
        widget.day.day, int.parse(p[0]), int.parse(p[1]));
    return dt.isBefore(now);
  }

  String _endTime(String start) {
    final p = start.split(':');
    final h = int.parse(p[0]) + 1;
    return '${h.toString().padLeft(2, '0')}:${p[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final dateStr = '${_p(d.day)}/${_p(d.month)}/${d.year}';

    return AlertDialog(
      title: Text('Elegí un horario — $dateStr',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 300,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < _slots.length; i++)
              _Chip(
                label: _slots[i],
                isBlocked: widget.blocked.contains(_slots[i]),
                isPast: _isPast(_slots[i]),
                isSelected: _sel == i,
                onTap: (widget.blocked.contains(_slots[i]) ||
                        _isPast(_slots[i]))
                    ? null
                    : () => setState(() => _sel = i),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _sel == null
              ? null
              : () => Navigator.of(context).pop((
                    start: _slots[_sel!],
                    end: _endTime(_slots[_sel!]),
                  )),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }

  String _p(int n) => n.toString().padLeft(2, '0');
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