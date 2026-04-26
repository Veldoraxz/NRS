// lib/presentation/screens/admin_screen.dart
// Tabla técnica con:
//   - ID, número, tipo, estado, notas
//   - Aprobar Retiro (POST /checkouts) → maneja cuenta en aire (HTTP 202)
//   - Registrar Devolución (POST /returns)
//   - Toggle mantenimiento / fuera de servicio (PUT /devices/{id}/status)
// Tab "Todas las Reservas" → GET /reservations/all

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/auth_provider.dart';
import '../../application/providers/notebook_list_provider.dart';
import '../../domain/entities/device.dart';
import '../theme/theme_provider.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NRS — Panel Admin'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Dispositivos', icon: Icon(Icons.laptop_chromebook, size: 16)),
            Tab(text: 'Reservas',     icon: Icon(Icons.calendar_today,   size: 16)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(notebookListProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DevicesTab(),
          _ReservationsTab(),
        ],
      ),
    );
  }
}

// ─── Tab Dispositivos ────────────────────────────────────────────────────────

class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notebookListProvider);

    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Text('$err',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () =>
                ref.read(notebookListProvider.notifier).refresh(),
            child: const Text('Reintentar'),
          ),
        ]),
      ),
      data: (devices) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('${devices.length} dispositivos',
                  style: const TextStyle(
                      color: AppTheme.textColor,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  columns: const [
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('NÚMERO')),
                    DataColumn(label: Text('TIPO')),
                    DataColumn(label: Text('ESTADO')),
                    DataColumn(label: Text('NOTAS')),
                    DataColumn(label: Text('ACCIONES')),
                  ],
                  rows: devices
                      .map((d) => _deviceRow(context, ref, d))
                      .toList(),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  DataRow _deviceRow(
      BuildContext context, WidgetRef ref, Device device) {
    return DataRow(cells: [
      DataCell(SelectableText(
        device.id,
        style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontFamily: 'monospace'),
      )),
      DataCell(Text(device.number,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor))),
      DataCell(Text(
        device.model == DeviceModel.tv ? 'Televisor' : 'Notebook',
        style: const TextStyle(color: AppTheme.textColor),
      )),
      DataCell(_StatusBadge(status: device.status)),
      DataCell(Text(
        device.statusNotes ?? '—',
        style: const TextStyle(
            color: AppTheme.textColor, fontSize: 12),
      )),
      DataCell(_ActionButtons(device: device)),
    ]);
  }
}

// ─── Botones de acción ────────────────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final Device device;
  const _ActionButtons({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Aprobar Retiro (POST /checkouts)
      if (device.status == DeviceStatus.available)
        _SmallButton(
          label: 'Aprobar Retiro',
          color: AppTheme.primaryBlue,
          onTap: () => _showCheckoutDialog(context, ref),
        )
      else if (device.status == DeviceStatus.inUse)
        _SmallButton(
          label: 'Devuelto',
          color: AppTheme.statusAvailable,
          onTap: () => _showReturnDialog(context, ref),
        )
      else
        const SizedBox(width: 110),

      const SizedBox(width: 6),

      // Toggle mantenimiento (local, no persiste como status en backend)
      Tooltip(
        message: device.status == DeviceStatus.maintenance
            ? 'Quitar mantenimiento'
            : 'Poner en mantenimiento',
        child: IconButton(
          icon: Icon(Icons.build,
              size: 18,
              color: device.status == DeviceStatus.maintenance
                  ? AppTheme.statusMaint
                  : Colors.grey.shade400),
          onPressed: () async {
            final ns = device.status == DeviceStatus.maintenance
                ? DeviceStatus.available
                : DeviceStatus.maintenance;
            await ref
                .read(notebookListProvider.notifier)
                .updateDeviceStatus(device.id, ns);
          },
        ),
      ),

      // Fuera de servicio (PUT /devices/{id}/status con out_of_service)
      Tooltip(
        message: device.status == DeviceStatus.outOfService
            ? 'Restaurar servicio'
            : 'Dar de baja',
        child: IconButton(
          icon: Icon(Icons.cancel_outlined,
              size: 18,
              color: device.status == DeviceStatus.outOfService
                  ? AppTheme.statusOff
                  : Colors.grey.shade400),
          onPressed: () async {
            final ns = device.status == DeviceStatus.outOfService
                ? DeviceStatus.available
                : DeviceStatus.outOfService;
            await ref
                .read(notebookListProvider.notifier)
                .updateDeviceStatus(device.id, ns);
          },
        ),
      ),
    ]);
  }

  // ─── Dialogo Aprobar Retiro ──────────────────────────────────────────────────

  void _showCheckoutDialog(BuildContext context, WidgetRef ref) {
    final reservationIdCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprobar Retiro'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: reservationIdCtrl,
            decoration:
                const InputDecoration(labelText: 'ID de Reserva'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesCtrl,
            decoration: const InputDecoration(
                labelText: 'Notas del dispositivo (opcional)'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doCheckout(
                context,
                ref,
                reservationIdCtrl.text.trim(),
                notesCtrl.text.trim().isEmpty
                    ? null
                    : notesCtrl.text.trim(),
              );
            },
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }

  Future<void> _doCheckout(BuildContext context, WidgetRef ref,
      String reservationId, String? notes) async {
    try {
      final result = await ref
          .read(notebookListProvider.notifier)
          .approveCheckout(
              reservationId: reservationId, deviceNotes: notes);

      // HTTP 202 — alumno inactivo, requiere confirmación
      if (result['requires_confirmation'] == true) {
        if (!context.mounted) return;
        final student =
            result['student'] as Map<String, dynamic>? ?? {};
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar Activación de Cuenta'),
            content: Text(
              '${result['message']}\n\n'
              'Alumno: ${student['full_name']}\n'
              'DNI: ${student['dni']}\n'
              'Email: ${student['email']}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar y Activar'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          final r2 = await ref
              .read(notebookListProvider.notifier)
              .approveCheckout(
                  reservationId: reservationId,
                  deviceNotes: notes,
                  confirm: true);
          if (r2['student_activated'] == true) {
            ref.read(authProvider.notifier).activateAccount();
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('✓ Checkout aprobado. Cuenta activada.'),
              backgroundColor: AppTheme.statusAvailable,
            ));
          }
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Retiro aprobado.'),
          backgroundColor: AppTheme.statusAvailable,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  // ─── Diálogo Devolución ──────────────────────────────────────────────────────

  void _showReturnDialog(BuildContext context, WidgetRef ref) {
    final checkoutIdCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final damageCtrl = TextEditingController();
    bool hasDamage = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Registrar Devolución'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: checkoutIdCtrl,
              decoration:
                  const InputDecoration(labelText: 'ID de Checkout'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notas del dispositivo (opcional)'),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('¿Hay daño?'),
              value: hasDamage,
              onChanged: (v) => setState(() => hasDamage = v ?? false),
              contentPadding: EdgeInsets.zero,
            ),
            if (hasDamage)
              TextField(
                controller: damageCtrl,
                decoration: const InputDecoration(
                    labelText: 'Descripción del daño'),
              ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(notebookListProvider.notifier)
                      .processReturn(
                        checkoutId: checkoutIdCtrl.text.trim(),
                        deviceNotes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                        hasDamage: hasDamage,
                        damageDescription: hasDamage
                            ? damageCtrl.text.trim()
                            : null,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(
                      content: Text('✓ Devolución registrada.'),
                      backgroundColor: AppTheme.statusAvailable,
                    ));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(
                      content: Text(
                          e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.redAccent,
                    ));
                  }
                }
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab Reservas ─────────────────────────────────────────────────────────────

class _ReservationsTab extends ConsumerWidget {
  const _ReservationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future:
          ref.read(notebookListProvider.notifier).getAllReservations(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        final data = snap.data ?? [];
        if (data.isEmpty) {
          return const Center(child: Text('No hay reservas.'));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
              columns: const [
                DataColumn(label: Text('ID')),
                DataColumn(label: Text('TIPO')),
                DataColumn(label: Text('RESERVANTE')),
                DataColumn(label: Text('DISPOSITIVO')),
                DataColumn(label: Text('FECHA')),
                DataColumn(label: Text('INICIO')),
                DataColumn(label: Text('FIN')),
                DataColumn(label: Text('ESTADO')),
              ],
              rows: data.map((r) {
                final name = (r['student_name'] ??
                        r['teacher_name'] ??
                        '—') as String;
                return DataRow(cells: [
                  DataCell(SelectableText(r['id'] as String,
                      style: const TextStyle(
                          fontSize: 9, fontFamily: 'monospace'))),
                  DataCell(Text(r['booker_type'] as String,
                      style: const TextStyle(fontSize: 11))),
                  DataCell(Text(name,
                      style: const TextStyle(fontSize: 11))),
                  DataCell(Text(r['device_id'] as String,
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace'))),
                  DataCell(Text(r['date'] as String,
                      style: const TextStyle(fontSize: 11))),
                  DataCell(Text(r['start_time'] as String,
                      style: const TextStyle(fontSize: 11))),
                  DataCell(Text(r['end_time'] as String,
                      style: const TextStyle(fontSize: 11))),
                  DataCell(_ReservationStatusBadge(
                      status: r['status'] as String)),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final DeviceStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DeviceStatus.available    => AppTheme.statusAvailable,
      DeviceStatus.inUse        => AppTheme.statusInUse,
      DeviceStatus.maintenance  => AppTheme.statusMaint,
      DeviceStatus.outOfService => AppTheme.statusOff,
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(Device.statusLabel(status),
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11)),
    );
  }
}

class _ReservationStatusBadge extends StatelessWidget {
  final String status;
  const _ReservationStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending'   => AppTheme.statusInUse,
      'confirmed' => AppTheme.primaryBlue,
      'completed' => AppTheme.statusAvailable,
      'cancelled' => AppTheme.statusOff,
      'expired'   => AppTheme.statusMaint,
      _           => AppTheme.statusOff,
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 10)),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SmallButton(
      {required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}