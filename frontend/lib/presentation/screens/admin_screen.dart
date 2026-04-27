// lib/presentation/screens/admin_screen.dart
// Tabs: Dispositivos | Reservas | Usuarios
// El tab Usuarios es la réplica exacta de nrs_usuarios_panel.html

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/notebook_list_provider.dart';
import '../../domain/entities/device.dart';
import '../../infrastructure/api_client.dart';
import '../theme/theme_provider.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/teacher_token_dialog.dart';

final _allReservationsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(notebookListProvider.notifier).getAllReservations();
});

enum _ReservationFlowState { pending, active, finalized, cancelled }

/// Convierte la clave de especialidad guardada en la DB
/// (`programacion`, `electronica`, `construcciones`, `ciclo_basico`)
/// en una etiqueta legible y con acentos.
String _specialtyLabel(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'programacion':
      return 'Programación';
    case 'electronica':
      return 'Electrónica';
    case 'construcciones':
      return 'Construcciones';
    case 'ciclo_basico':
    case '':
    case null:
      return 'Ciclo Básico';
    default:
      // Fallback: capitaliza la primera letra de lo que venga.
      final s = raw!.trim();
      return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
  }
}

class _HeaderSectionMetric {
  final String key;
  final String label;

  const _HeaderSectionMetric({required this.key, required this.label});
}

const _kHeaderSectionMetrics = <_HeaderSectionMetric>[
  _HeaderSectionMetric(key: 'ciclo_basico', label: 'Ciclo Básico'),
  _HeaderSectionMetric(key: 'programacion', label: 'Programación'),
  _HeaderSectionMetric(key: 'electronica', label: 'Electrónica'),
  _HeaderSectionMetric(key: 'construcciones', label: 'Construcciones'),
];

Map<String, int> _emptyHeaderSectionCounts() => {
  for (final metric in _kHeaderSectionMetrics) metric.key: 0,
};

Map<String, int> _activeCheckoutsBySection(
  List<Map<String, dynamic>> reservations,
) {
  final counts = _emptyHeaderSectionCounts();

  for (final reservation in reservations) {
    if (reservation['booker_type']?.toString().toLowerCase() != 'student') {
      continue;
    }
    if (_resolveReservationFlow(reservation) != _ReservationFlowState.active) {
      continue;
    }

    final specialtyRaw = reservation['student_specialty']?.toString().trim();
    final specialty = specialtyRaw == null || specialtyRaw.isEmpty
        ? 'ciclo_basico'
        : specialtyRaw.toLowerCase();

    if (counts.containsKey(specialty)) {
      counts[specialty] = counts[specialty]! + 1;
    }
  }

  return counts;
}

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
    _tabs = TabController(length: 3, vsync: this); // ← 3 tabs
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reservationsAsync = ref.watch(_allReservationsProvider);
    final sectionCounts = reservationsAsync.when(
      data: _activeCheckoutsBySection,
      loading: _emptyHeaderSectionCounts,
      error: (_, _) => _emptyHeaderSectionCounts(),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('NRS — Panel Admin'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(150),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 5),
                child: Row(
                  children: [
                    for (var i = 0; i < _kHeaderSectionMetrics.length; i++) ...[
                      Expanded(
                        child: _HeaderSectionCard(
                          metric: _kHeaderSectionMetrics[i],
                          count:
                              sectionCounts[_kHeaderSectionMetrics[i].key] ?? 0,
                        ),
                      ),
                      if (i != _kHeaderSectionMetrics.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(
                    text: 'Dispositivos',
                    icon: Icon(Icons.laptop_chromebook, size: 16),
                  ),
                  Tab(
                    text: 'Reservas',
                    icon: Icon(Icons.calendar_today, size: 16),
                  ),
                  Tab(
                    text: 'Usuarios',
                    icon: Icon(Icons.people_rounded, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: TextButton.icon(
              onPressed: () => _showResetCycleDialog(context, ref),
              icon: const Icon(
                Icons.delete_sweep_outlined,
                color: Colors.white,
                size: 20,
              ),
              label: const Text(
                'Fin de ciclo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Perfil',
            onPressed: () => ProfileSheet.show(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DevicesTab(),
          _ReservationsTab(),
          _UsuariosTab(), // ← nuevo
        ],
      ),
    );
  }

  Future<void> _showResetCycleDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ResetCycleDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ApiClient.instance.post(
        '/admin/reset',
        data: {'confirm': 'RESET_ANUAL_CONFIRMADO'},
      );
      if (!context.mounted) return;
      ref.read(notebookListProvider.notifier).refresh();
      ref.invalidate(_allReservationsProvider);
      ref.invalidate(_studentsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Fin de ciclo lectivo aplicado.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al aplicar fin de ciclo: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

_ReservationFlowState _resolveReservationFlow(
  Map<String, dynamic> reservation,
) {
  final status = reservation['status']?.toString().toLowerCase() ?? '';
  final checkoutId = reservation['checkout_id']?.toString();
  final returnedAt = reservation['returned_at']?.toString();

  if (status == 'cancelled') return _ReservationFlowState.cancelled;

  final hasCheckout = checkoutId != null && checkoutId.isNotEmpty;
  final hasReturn = returnedAt != null && returnedAt.isNotEmpty;

  if (hasCheckout && !hasReturn) return _ReservationFlowState.active;
  if (status == 'pending' || status == 'confirmed') {
    return _ReservationFlowState.pending;
  }
  return _ReservationFlowState.finalized;
}

// ─── Tab Dispositivos ─────────────────────────────────────────────────────────

class _DevicesTab extends ConsumerStatefulWidget {
  const _DevicesTab();

  @override
  ConsumerState<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends ConsumerState<_DevicesTab> {
  String _searchDevices = '';
  String _filterType = ''; // '', 'notebook', 'television'
  String _filterStatus = ''; // '', 'available', 'in_use', 'maintenance', 'out_of_service'

  bool _matchesFilters(Device d) {
    final q = _searchDevices.trim().toLowerCase();
    if (q.isNotEmpty) {
      final number = d.number.toLowerCase();
      final notes = (d.statusNotes ?? '').toLowerCase();
      if (!number.contains(q) && !notes.contains(q)) return false;
    }

    if (_filterType.isNotEmpty) {
      final isTv = d.model == DeviceModel.tv;
      if (_filterType == 'television' && !isTv) return false;
      if (_filterType == 'notebook' && isTv) return false;
    }

    if (_filterStatus.isNotEmpty) {
      final apiStatus = Device.statusToApi(d.status);
      if (apiStatus != _filterStatus) return false;
    }

    return true;
  }

  bool get _hasActiveFilters =>
      _searchDevices.isNotEmpty ||
      _filterType.isNotEmpty ||
      _filterStatus.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _searchDevices = '';
      _filterType = '';
      _filterStatus = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notebookListProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$err',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  ref.read(notebookListProvider.notifier).refresh(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (devices) {
        final filtered = devices.where(_matchesFilters).toList();
        return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Icon(
                              Icons.computer_outlined,
                              color: AppTheme.secondaryBlue,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dispositivos',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _hasActiveFilters
                                    ? '${filtered.length} de ${devices.length} dispositivos'
                                    : '${devices.length} dispositivos',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textColor.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showAddEditDeviceDialog(context, ref),
                          child: Ink(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryBlue,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.secondaryBlue.withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _DeviceFiltersBar(
                    search: _searchDevices,
                    type: _filterType,
                    status: _filterStatus,
                    hasActiveFilters: _hasActiveFilters,
                    onSearchChanged: (v) =>
                        setState(() => _searchDevices = v),
                    onTypeChanged: (v) => setState(() => _filterType = v),
                    onStatusChanged: (v) =>
                        setState(() => _filterStatus = v),
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 24,
                              ),
                              child: Center(
                                child: Text(
                                  devices.isEmpty
                                      ? 'No hay dispositivos registrados.'
                                      : 'Ningún dispositivo coincide con los filtros aplicados.',
                                  style: TextStyle(
                                    color: AppTheme.textColor.withValues(
                                      alpha: 0.75,
                                    ),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.black.withValues(alpha: 0.08),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth:
                                  MediaQuery.of(context).size.width * 0.85,
                            ),
                            child: DataTable(
                              horizontalMargin: 28,
                              columnSpacing: 16,
                              headingRowHeight: 56,
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 60,
                              headingRowColor: WidgetStateProperty.all(
                                Colors.white,
                              ),
                              dataRowColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.hovered)) {
                                  return AppTheme.cardColor.withValues(
                                    alpha: 0.35,
                                  );
                                }
                                return Colors.white;
                              }),
                              headingTextStyle: const TextStyle(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 0.4,
                              ),
                              columns: const [
                                DataColumn(label: Text('NÚMERO')),
                                DataColumn(label: Text('TIPO')),
                                DataColumn(label: Text('ESTADO')),
                                DataColumn(label: Text('NOTAS')),
                                DataColumn(label: Text('ACCIONES')),
                              ],
                              rows: filtered
                                  .map((d) => _deviceRow(context, ref, d))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 28,
                      runSpacing: 16,
                      children: [
                        const _LegendItem(
                          icon: Icons.build,
                          color: Color(0xFFB8BDC7),
                          title: 'Mantenimiento (deshabilitado)',
                          subtitle:
                              'No disponible cuando el dispositivo está en uso.',
                        ),
                        const _LegendItem(
                          icon: Icons.build,
                          color: AppTheme.statusMaint,
                          title: 'Mantenimiento',
                          subtitle: 'Poner el dispositivo en mantenimiento.',
                        ),
                        const _LegendItem(
                          icon: Icons.edit,
                          color: AppTheme.primaryBlue,
                          title: 'Editar',
                          subtitle: 'Modificar número o notas.',
                        ),
                        const _LegendItem(
                          icon: Icons.delete,
                          color: Colors.red,
                          title: 'Eliminar',
                          subtitle: 'Eliminar dispositivo.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      },
    );
  }

  DataRow _deviceRow(BuildContext context, WidgetRef ref, Device device) {
    return DataRow(
      cells: [
        DataCell(
          Text(
            device.number,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textColor,
            ),
          ),
        ),
        DataCell(
          Text(
            device.model == DeviceModel.tv ? 'TV' : 'PC',
            style: const TextStyle(
              color: AppTheme.textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DataCell(_StatusBadge(status: device.status)),
        DataCell(
          Text(
            device.statusNotes ?? '—',
            style: TextStyle(
              color: AppTheme.textColor.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ),
        DataCell(_ActionButtons(device: device, context: context, ref: ref)),
      ],
    );
  }

  void _showAddEditDeviceDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AddEditDeviceDialog(
        device: null,
        onSave: (number, type, notes) async {
          try {
            await ref
                .read(notebookListProvider.notifier)
                .createDevice(number: number, type: type, statusNotes: notes);
            if (ctx.mounted) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✓ Dispositivo agregado.'),
                  backgroundColor: AppTheme.statusAvailable,
                ),
              );
            }
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString().replaceAll('Exception: ', '')),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
        },
      ),
    );
  }
}

// ─── Botones de acción (Dispositivos) ────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final Device device;
  final BuildContext context;
  final WidgetRef ref;

  const _ActionButtons({
    required this.device,
    required this.context,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInUse = device.status == DeviceStatus.inUse;
    final isMaintenance = device.status == DeviceStatus.maintenance;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isInUse
              ? 'No disponible: dispositivo en uso'
              : isMaintenance
                  ? 'Marcar como disponible'
                  : 'Poner en mantenimiento',
          child: _ActionIconButton(
            icon: Icons.build_outlined,
            color: isInUse ? const Color(0xFFB8BDC7) : AppTheme.statusMaint,
            onPressed: isInUse
                ? null
                : () async {
                    final newStatus = device.status == DeviceStatus.maintenance
                        ? DeviceStatus.available
                        : DeviceStatus.maintenance;
                    try {
                      await ref
                          .read(notebookListProvider.notifier)
                          .updateDeviceStatus(device.id, newStatus);
                    } catch (e) {
                      if (this.context.mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceAll('Exception: ', ''),
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Editar dispositivo',
          child: _ActionIconButton(
            icon: Icons.edit_outlined,
            color: AppTheme.primaryBlue,
            onPressed: () => _showEditDeviceDialog(context, ref),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Eliminar dispositivo',
          child: _ActionIconButton(
            icon: Icons.delete_outline_rounded,
            color: Colors.red,
            onPressed: () => _showDeleteConfirmation(context, ref),
          ),
        ),
      ],
    );
  }

  void _showEditDeviceDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AddEditDeviceDialog(
        device: device,
        onSave: (number, _, notes) async {
          try {
            await ref
                .read(notebookListProvider.notifier)
                .updateDevice(
                  id: device.id,
                  number: number,
                  statusNotes: notes,
                );
            if (ctx.mounted) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✓ Dispositivo actualizado.'),
                  backgroundColor: AppTheme.statusAvailable,
                ),
              );
            }
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString().replaceAll('Exception: ', '')),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar dispositivo'),
        content: Text(
          '¿Estás seguro de que deseas eliminar el dispositivo ${device.number}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(notebookListProvider.notifier)
                    .deleteDevice(device.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✓ Dispositivo eliminado.'),
                      backgroundColor: AppTheme.statusAvailable,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ─── Formulario Agregar/Editar Dispositivo ─────────────────────────────────

class _AddEditDeviceDialog extends StatefulWidget {
  final Device? device;
  final Function(String number, String type, String? notes) onSave;

  const _AddEditDeviceDialog({required this.device, required this.onSave});

  @override
  State<_AddEditDeviceDialog> createState() => _AddEditDeviceDialogState();
}

class _AddEditDeviceDialogState extends State<_AddEditDeviceDialog> {
  late TextEditingController _numberCtrl;
  late TextEditingController _notesCtrl;
  String _deviceType = 'notebook';

  @override
  void initState() {
    super.initState();
    _numberCtrl = TextEditingController(text: widget.device?.number ?? '');
    _notesCtrl = TextEditingController(text: widget.device?.statusNotes ?? '');
    if (widget.device != null) {
      _deviceType = widget.device!.model == DeviceModel.tv
          ? 'television'
          : 'notebook';
    }
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.device != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 370),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Editar dispositivo' : 'Agregar dispositivo',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 20,
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DialogFieldLabel('Nombre (Número de PC/TV) *'),
              const SizedBox(height: 8),
              TextField(
                controller: _numberCtrl,
                decoration: const InputDecoration(hintText: 'Ej. CI-NB-0015'),
              ),
              const SizedBox(height: 20),
              _DialogFieldLabel('Tipo *'),
              const SizedBox(height: 8),
              if (!isEditing)
                DropdownButtonFormField<String>(
                  initialValue: _deviceType,
                  decoration: const InputDecoration(
                    hintText: 'Seleccionar tipo',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'notebook', child: Text('PC')),
                    DropdownMenuItem(value: 'television', child: Text('TV')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _deviceType = v);
                  },
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    _deviceType == 'television' ? 'TV' : 'PC',
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const _DialogFieldLabel('Notas (opcional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Ej. Ubicación, características, etc.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () {
                      final number = _numberCtrl.text.trim();
                      if (number.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('El nombre es requerido'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      widget.onSave(
                        number,
                        _deviceType,
                        _notesCtrl.text.trim().isEmpty
                            ? null
                            : _notesCtrl.text.trim(),
                      );
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tab Reservas ─────────────────────────────────────────────────────────────

class _ReservationsTab extends ConsumerStatefulWidget {
  const _ReservationsTab();

  @override
  ConsumerState<_ReservationsTab> createState() => _ReservationsTabState();
}

class _ReservationsTabState extends ConsumerState<_ReservationsTab> {
  String _searchReservas = '';
  DateTime? _filterDate;
  TimeOfDay? _filterStartTime;
  TimeOfDay? _filterEndTime;
  String _filterEstado = ''; // '', 'pending', 'active', 'finalized', 'cancelled'
  String _filterTipo = '';   // '', 'student', 'teacher'

  bool _matchesFilters(Map<String, dynamic> r) {
    final q = _searchReservas.trim().toLowerCase();
    if (q.isNotEmpty) {
      final isTeacher = r['booker_type'] == 'teacher';
      final name = (isTeacher ? r['teacher_name'] : r['student_name'])
              ?.toString()
              .toLowerCase() ??
          '';
      final dni = (isTeacher ? r['teacher_dni'] : r['student_dni'])
              ?.toString()
              .toLowerCase() ??
          '';
      final email = (isTeacher ? r['teacher_email'] : r['student_email'])
              ?.toString()
              .toLowerCase() ??
          '';
      final deviceNumber =
          r['device_number']?.toString().toLowerCase() ?? '';

      final matches = name.contains(q) ||
          dni.contains(q) ||
          email.contains(q) ||
          deviceNumber.contains(q);
      if (!matches) return false;
    }

    if (_filterTipo.isNotEmpty && r['booker_type'] != _filterTipo) {
      return false;
    }

    if (_filterEstado.isNotEmpty &&
        _resolveReservationFlow(r).name != _filterEstado) {
      return false;
    }

    if (_filterDate != null) {
      final d = _filterDate!;
      final iso =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (r['date']?.toString() != iso) return false;
    }

    if (_filterStartTime != null) {
      final start = _parseTime(r['start_time']?.toString());
      if (start == null) return false;
      if (_compareTime(start, _filterStartTime!) < 0) return false;
    }

    if (_filterEndTime != null) {
      final end = _parseTime(r['end_time']?.toString());
      if (end == null) return false;
      if (_compareTime(end, _filterEndTime!) > 0) return false;
    }

    return true;
  }

  TimeOfDay? _parseTime(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  int _compareTime(TimeOfDay a, TimeOfDay b) {
    final am = a.hour * 60 + a.minute;
    final bm = b.hour * 60 + b.minute;
    return am.compareTo(bm);
  }

  void _clearFilters() {
    setState(() {
      _searchReservas = '';
      _filterDate = null;
      _filterStartTime = null;
      _filterEndTime = null;
      _filterEstado = '';
      _filterTipo = '';
    });
  }

  bool get _hasActiveFilters =>
      _searchReservas.isNotEmpty ||
      _filterDate != null ||
      _filterStartTime != null ||
      _filterEndTime != null ||
      _filterEstado.isNotEmpty ||
      _filterTipo.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final reservationsAsync = ref.watch(_allReservationsProvider);

    return reservationsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$err',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(_allReservationsProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (reservations) {
        final filtered = reservations.where(_matchesFilters).toList();
        return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.cardColor,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(
                          Icons.calendar_today_outlined,
                          color: AppTheme.secondaryBlue,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reservas',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _hasActiveFilters
                                ? '${filtered.length} de ${reservations.length} reservas'
                                : '${reservations.length} reservas',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ReservationFiltersBar(
                    search: _searchReservas,
                    date: _filterDate,
                    startTime: _filterStartTime,
                    endTime: _filterEndTime,
                    estado: _filterEstado,
                    tipo: _filterTipo,
                    hasActiveFilters: _hasActiveFilters,
                    onSearchChanged: (v) =>
                        setState(() => _searchReservas = v),
                    onDateChanged: (v) => setState(() => _filterDate = v),
                    onStartTimeChanged: (v) =>
                        setState(() => _filterStartTime = v),
                    onEndTimeChanged: (v) =>
                        setState(() => _filterEndTime = v),
                    onEstadoChanged: (v) => setState(() => _filterEstado = v),
                    onTipoChanged: (v) => setState(() => _filterTipo = v),
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 24,
                              ),
                              child: Center(
                                child: Text(
                                  reservations.isEmpty
                                      ? 'No hay reservas registradas.'
                                      : 'Ninguna reserva coincide con los filtros aplicados.',
                                  style: TextStyle(
                                    color: AppTheme.textColor.withValues(
                                      alpha: 0.75,
                                    ),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.black.withValues(
                                      alpha: 0.08,
                                    ),
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth:
                                          MediaQuery.of(context).size.width *
                                          0.85,
                                    ),
                                  child: DataTable(
                                    horizontalMargin: 28,
                                    columnSpacing: 16,
                                    headingRowHeight: 56,
                                    dataRowMinHeight: 64,
                                    dataRowMaxHeight: 70,
                                    headingRowColor: WidgetStateProperty.all(
                                      Colors.white,
                                    ),
                                    dataRowColor:
                                        WidgetStateProperty.resolveWith((
                                          states,
                                        ) {
                                          if (states.contains(
                                            WidgetState.hovered,
                                          )) {
                                            return AppTheme.cardColor
                                                .withValues(alpha: 0.35);
                                          }
                                          return Colors.white;
                                        }),
                                    headingTextStyle: const TextStyle(
                                      color: AppTheme.primaryBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      letterSpacing: 0.4,
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('RESERVANTE')),
                                      DataColumn(label: Text('TIPO')),
                                      DataColumn(label: Text('DISPOSITIVO')),
                                      DataColumn(label: Text('FECHA')),
                                      DataColumn(label: Text('INICIO')),
                                      DataColumn(label: Text('FIN')),
                                      DataColumn(label: Text('ESTADO')),
                                      DataColumn(
                                        label: Align(
                                          alignment: Alignment.centerRight,
                                          child: Text('ACCIONES'),
                                        ),
                                      ),
                                    ],
                                    rows: filtered
                                        .map((r) => _reservationRow(context, r))
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          )
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppTheme.primaryBlue.withValues(alpha: 0.9),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Las acciones disponibles dependen del estado actual de la reserva.',
                            style: TextStyle(
                              color: AppTheme.textColor.withValues(alpha: 0.84),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      },
    );
  }

  DataRow _reservationRow(
    BuildContext context,
    Map<String, dynamic> reservation,
  ) {
    final isTeacher = reservation['booker_type'] == 'teacher';
    final typeLabel = isTeacher ? 'Profesor' : 'Estudiante';
    final nameRaw = isTeacher
        ? reservation['teacher_name']
        : reservation['student_name'];
    final reservantName = (nameRaw?.toString().trim().isNotEmpty ?? false)
        ? nameRaw.toString().trim()
        : 'Sin nombre';
    final flowState = _resolveReservationFlow(reservation);

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reservantName,
                style: const TextStyle(
                  color: AppTheme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                typeLabel,
                style: TextStyle(
                  color: AppTheme.textColor.withValues(alpha: 0.58),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        DataCell(_BookerTypeBadge(typeLabel: typeLabel, isTeacher: isTeacher)),
        DataCell(
          Text(
            _formatDeviceLabel(reservation),
            style: const TextStyle(
              color: AppTheme.textColor,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
        DataCell(
          Text(
            reservation['date']?.toString() ?? '—',
            style: const TextStyle(color: AppTheme.textColor, fontSize: 13),
          ),
        ),
        DataCell(
          Text(
            reservation['start_time']?.toString() ?? '—',
            style: const TextStyle(color: AppTheme.textColor, fontSize: 13),
          ),
        ),
        DataCell(
          Text(
            reservation['end_time']?.toString() ?? '—',
            style: const TextStyle(color: AppTheme.textColor, fontSize: 13),
          ),
        ),
        DataCell(_ReservationFlowBadge(flowState: flowState)),
        DataCell(
          Align(
            alignment: Alignment.centerRight,
            child: _ReservationActionButtons(
              reservation: reservation,
              flowState: flowState,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDeviceLabel(Map<String, dynamic> reservation) {
    final number = reservation['device_number']?.toString().trim() ?? '';
    final rawType = reservation['device_type']?.toString();
    final fallbackId = reservation['device_id']?.toString() ?? '—';

    final typeLabel = switch (rawType) {
      'television' => 'TV',
      'notebook' => 'PC',
      _ => '',
    };

    if (number.isEmpty) {
      if (typeLabel.isEmpty) return fallbackId;
      return '$fallbackId ($typeLabel)';
    }
    if (typeLabel.isEmpty) return number;
    return '$number ($typeLabel)';
  }
}

// ─── Tab Usuarios ─────────────────────────────────────────────────────────────

// Colores del HTML
const _kPrimary = Color(0xFF1565C0);
const _kBgCard = Colors.white;
const _kBorder = Color(0xFFE8E8E8);
const _kBorderTable = Color(0xFFE8ECF4);
const _kText1 = Color(0xFF1A1A2E);
const _kText3 = Color(0xFF555555);
const _kText4 = Color(0xFF888888);

// ─── Providers ───────────────────────────────────────────────────────────────

final _teachersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final res = await ApiClient.instance.get('/admin/teachers');
  return (res.data as List).cast<Map<String, dynamic>>();
});

final _studentsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final res = await ApiClient.instance.get('/admin/students');
  return (res.data as List).cast<Map<String, dynamic>>();
});

// Helpers
String _initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

final _kAvatarPalette = const [
  (Color(0xFFE3F2FD), Color(0xFF1565C0)),
  (Color(0xFFFCE4EC), Color(0xFFC62828)),
  (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
  (Color(0xFFFFF3E0), Color(0xFFE65100)),
  (Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
  (Color(0xFFE0F7FA), Color(0xFF006064)),
];

(Color, Color) _avatarColors(String id) {
  final idx = id.codeUnits.fold(0, (a, b) => a + b) % _kAvatarPalette.length;
  return _kAvatarPalette[idx];
}

class _UsuariosTab extends ConsumerStatefulWidget {
  const _UsuariosTab();

  @override
  ConsumerState<_UsuariosTab> createState() => _UsuariosTabState();
}

class _UsuariosTabState extends ConsumerState<_UsuariosTab>
    with SingleTickerProviderStateMixin {
  late final TabController _inner;
  String _searchAlumnos = '';
  String _searchProfesores = '';

  // Filtros alumnos. '' significa "todos".
  String _filterYear = '';
  String _filterDiv = '';
  String _filterSpec = '';

  @override
  void initState() {
    super.initState();
    // 0 = Alumnos, 1 = Profesores
    _inner = TabController(length: 2, vsync: this);
    _inner.addListener(_onInnerTabChanged);
  }

  void _onInnerTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inner.dispose();
    super.dispose();
  }

  // ── API helpers ──────────────────────────────────────────────────────────

  Future<void> _addTeacher(String fullName, String email, String dni) async {
    await ApiClient.instance.post(
      '/teachers',
      data: {'full_name': fullName, 'email': email, 'dni': dni},
    );
    ref.invalidate(_teachersProvider);
  }

  Future<void> _editTeacher(
    String id,
    String fullName,
    String email,
    String dni,
  ) async {
    await ApiClient.instance.patch(
      '/admin/teachers/$id',
      data: {'full_name': fullName, 'email': email, 'dni': dni},
    );
    ref.invalidate(_teachersProvider);
  }

  Future<void> _deleteTeacher(String id) async {
    await ApiClient.instance.delete('/admin/teachers/$id');
    ref.invalidate(_teachersProvider);
  }

  Future<void> _editStudent(
    String id,
    String fullName,
    String email,
    String dni,
    int year,
    int division,
    String specialty,
  ) async {
    await ApiClient.instance.patch(
      '/admin/students/$id',
      data: {
        'full_name': fullName,
        'email': email,
        'dni': dni,
        'year': year,
        'division': division,
        'specialty': specialty,
      },
    );
    ref.invalidate(_studentsProvider);
  }

  Future<void> _deleteStudent(String id) async {
    await ApiClient.instance.delete('/admin/students/$id');
    ref.invalidate(_studentsProvider);
  }

  Future<void> _changeStudentStatus(
    Map<String, dynamic> s,
    String action,
  ) async {
    final id = s['id'] as String;
    await ApiClient.instance.patch(
      '/admin/students/$id',
      data: {'action': action},
    );
    ref.invalidate(_studentsProvider);
  }

  // ── Diálogo agregar/editar profesor ─────────────────────────────────────

  Future<void> _showTeacherDialog({Map<String, dynamic>? teacher}) async {
    final nameCtrl = TextEditingController(text: teacher?['full_name'] ?? '');
    final emailCtrl = TextEditingController(text: teacher?['email'] ?? '');
    final dniCtrl = TextEditingController(text: teacher?['dni'] ?? '');
    final isEditing = teacher != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _UserFormDialog(
        title: isEditing ? 'Editar profesor' : 'Agregar profesor',
        nameCtrl: nameCtrl,
        emailCtrl: emailCtrl,
        dniCtrl: dniCtrl,
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (isEditing) {
        await _editTeacher(
          teacher['id'] as String,
          nameCtrl.text.trim(),
          emailCtrl.text.trim(),
          dniCtrl.text.trim(),
        );
      } else {
        await _addTeacher(
          nameCtrl.text.trim(),
          emailCtrl.text.trim(),
          dniCtrl.text.trim(),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? '✓ Profesor actualizado.' : '✓ Profesor agregado.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Diálogo editar alumno ────────────────────────────────────────────────

  Future<void> _showStudentDialog(Map<String, dynamic> s) async {
    final nameCtrl = TextEditingController(text: s['full_name'] ?? '');
    final emailCtrl = TextEditingController(text: s['email'] ?? '');
    final dniCtrl = TextEditingController(text: s['dni'] ?? '');
    int year = (s['year'] as int?) ?? 1;
    int division = (s['division'] as int?) ?? 1;
    String specialty = (s['specialty'] as String?) ?? 'ciclo_basico';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _StudentFormDialog(
        nameCtrl: nameCtrl,
        emailCtrl: emailCtrl,
        dniCtrl: dniCtrl,
        initialYear: year,
        initialDiv: division,
        initialSpec: specialty,
        onChanged: (y, d, sp) {
          year = y;
          division = d;
          specialty = sp;
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _editStudent(
        s['id'] as String,
        nameCtrl.text.trim(),
        emailCtrl.text.trim(),
        dniCtrl.text.trim(),
        year,
        division,
        specialty,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Alumno actualizado.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Diálogo confirmar eliminación ────────────────────────────────────────

  Future<bool> _confirmDelete(String nombre) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar eliminación'),
            content: Text(
              '¿Eliminar a $nombre? Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Cambiar estado alumno (toggle directo) ───────────────────────────────

  Future<void> _toggleStudentStatus(Map<String, dynamic> s) async {
    final activo = s['is_active'] as bool;
    final action = activo ? 'deactivate' : 'activate';

    try {
      await _changeStudentStatus(s, action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              activo ? '✓ Alumno desactivado.' : '✓ Alumno activado.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final teachersAsync = ref.watch(_teachersProvider);
    final studentsAsync = ref.watch(_studentsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _kBgCard,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabecera (sin botón de recarga) ──────────────────────
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.people_rounded,
                        color: _kPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Usuarios',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: _kText1,
                            ),
                          ),
                          SizedBox(height: 1),
                          Text(
                            'Gestioná los usuarios del sistema.',
                            style: TextStyle(fontSize: 12, color: _kText4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Tabs internos: Alumnos / Profesores ───────────────────
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _kBorder, width: 1.5),
                    ),
                  ),
                  child: TabBar(
                    controller: _inner,
                    labelColor: _kPrimary,
                    unselectedLabelColor: _kText4,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    indicatorColor: _kPrimary,
                    indicatorWeight: 2.5,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_rounded, size: 15),
                            SizedBox(width: 6),
                            Text('Alumnos'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.school_rounded, size: 15),
                            SizedBox(width: 6),
                            Text('Profesores'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_inner.index == 0)
                  // ── Tab Alumnos ──────────────────────────────────────
                  studentsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Error: $e',
                                style: const TextStyle(color: _kText3),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () =>
                                    ref.invalidate(_studentsProvider),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                        data: (students) {
                          final filtered = students.where((s) {
                            final q = _searchAlumnos.toLowerCase();
                            final matchesQuery =
                                (s['full_name'] as String)
                                    .toLowerCase()
                                    .contains(q) ||
                                (s['email'] as String).toLowerCase().contains(
                                  q,
                                ) ||
                                (s['dni'] as String).toLowerCase().contains(q);

                            final yearVal = (s['year'] as int?) ?? 0;
                            final divVal = (s['division'] as int?) ?? 0;
                            final specVal =
                                (s['specialty'] as String?) ?? 'ciclo_basico';

                            final matchesYear =
                                _filterYear.isEmpty ||
                                _filterYear == yearVal.toString();
                            final matchesDiv =
                                _filterDiv.isEmpty ||
                                _filterDiv == divVal.toString();
                            final matchesSpec =
                                _filterSpec.isEmpty || _filterSpec == specVal;

                            return matchesQuery &&
                                matchesYear &&
                                matchesDiv &&
                                matchesSpec;
                          }).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.people_rounded,
                                    size: 15,
                                    color: _kText4,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${filtered.length} alumnos',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _kText3,
                                    ),
                                  ),
                                  const Spacer(),
                                  _FilterDropdown(
                                    width: 100,
                                    hint: 'Año',
                                    value: _filterYear,
                                    options: [
                                      const _FilterOption('', 'Todos'),
                                      for (var i = 1; i <= 7; i++)
                                        _FilterOption('$i', '$i°'),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _filterYear = v),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterDropdown(
                                    width: 110,
                                    hint: 'División',
                                    value: _filterDiv,
                                    options: [
                                      const _FilterOption('', 'Todas'),
                                      for (var i = 1; i <= 6; i++)
                                        _FilterOption('$i', '$i°'),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _filterDiv = v),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterDropdown(
                                    width: 170,
                                    hint: 'Especialidad',
                                    value: _filterSpec,
                                    options: const [
                                      _FilterOption('', 'Todas'),
                                      _FilterOption(
                                        'ciclo_basico',
                                        'Ciclo Básico',
                                      ),
                                      _FilterOption(
                                        'programacion',
                                        'Programación',
                                      ),
                                      _FilterOption(
                                        'electronica',
                                        'Electrónica',
                                      ),
                                      _FilterOption(
                                        'construcciones',
                                        'Construcciones',
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _filterSpec = v),
                                  ),
                                  const SizedBox(width: 8),
                                  _SearchBox(
                                    hint: 'Buscar por nombre, email o DNI...',
                                    onChanged: (v) =>
                                        setState(() => _searchAlumnos = v),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Table(
                                      columnWidths: const {
                                        0: FlexColumnWidth(200),
                                        1: FlexColumnWidth(120),
                                        2: FlexColumnWidth(190),
                                        3: FlexColumnWidth(80),
                                        4: FlexColumnWidth(120),
                                        5: FlexColumnWidth(120),
                                        6: FlexColumnWidth(130),
                                      },
                                      children: [
                                        TableRow(
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: _kBorderTable,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          children: const [
                                            _ThCell('Nombre y Apellido'),
                                            _ThCell('DNI'),
                                            _ThCell('Email'),
                                            _ThCell('Año/Div'),
                                            _ThCell('Especialidad'),
                                            _ThCell('Estado'),
                                            _ThCell('Acciones'),
                                          ],
                                        ),
                                        ...filtered.asMap().entries.map((e) {
                                          final s = e.value;
                                          final isLast =
                                              e.key == filtered.length - 1;
                                          final name = s['full_name'] as String;
                                          final email = s['email'] as String;
                                          final dni =
                                              s['dni'] as String? ?? '—';
                                          final activo = s['is_active'] as bool;
                                          final id = s['id'] as String;
                                          final year = s['year'] as int? ?? 0;
                                          final div =
                                              s['division'] as int? ?? 0;
                                          final spec =
                                              s['specialty'] as String? ?? '—';
                                          final dmg =
                                              s['damage_count'] as int? ?? 0;
                                          final inWatchlist =
                                              s['in_watchlist'] as bool? ??
                                              false;
                                          final (bg, fg) = _avatarColors(id);

                                          return TableRow(
                                            decoration: isLast
                                                ? null
                                                : const BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: _kBorderTable,
                                                      ),
                                                    ),
                                                  ),
                                            children: [
                                              // Nombre + badge daños
                                              _TdPadding(
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 30,
                                                      height: 30,
                                                      decoration: BoxDecoration(
                                                        color: bg,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          _initials(name),
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: fg,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: _kText1,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (dmg > 0)
                                                      Tooltip(
                                                        message:
                                                            '$dmg daño${dmg > 1 ? 's' : ''} registrado${dmg > 1 ? 's' : ''}',
                                                        child: Container(
                                                          margin:
                                                              const EdgeInsets.only(
                                                                left: 4,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 5,
                                                                vertical: 1,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .red
                                                                .shade50,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            border: Border.all(
                                                              color: Colors
                                                                  .red
                                                                  .shade200,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            '⚠ $dmg',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors
                                                                  .red
                                                                  .shade700,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              // DNI
                                              _TdPadding(
                                                child: Text(
                                                  dni,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kText3,
                                                  ),
                                                ),
                                              ),
                                              // Email
                                              _TdPadding(
                                                child: Text(
                                                  email,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kText3,
                                                  ),
                                                ),
                                              ),
                                              // Año/Div
                                              _TdPadding(
                                                child: Text(
                                                  '$year°/$div°',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kText3,
                                                  ),
                                                ),
                                              ),
                                              // Especialidad
                                              _TdPadding(
                                                child: Text(
                                                  _specialtyLabel(spec),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kText3,
                                                  ),
                                                ),
                                              ),
                                              // Estado
                                              _TdPadding(
                                                child: _StudentStatusBadge(
                                                  activo: activo,
                                                  inWatchlist: inWatchlist,
                                                ),
                                              ),
                                              // Acciones
                                              _TdPadding(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Tooltip(
                                                      message: 'Editar',
                                                      child: _UserActionBtn(
                                                        icon:
                                                            Icons.edit_outlined,
                                                        borderColor:
                                                            const Color(
                                                              0xFFBBDEFB,
                                                            ),
                                                        iconColor: _kPrimary,
                                                        onTap: () =>
                                                            _showStudentDialog(
                                                              s,
                                                            ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Tooltip(
                                                      message: 'Cambiar estado',
                                                      child: _UserActionBtn(
                                                        icon: activo
                                                            ? Icons
                                                                  .block_rounded
                                                            : Icons
                                                                  .check_circle_outline_rounded,
                                                        borderColor: activo
                                                            ? const Color(
                                                                0xFFFFCDD2,
                                                              )
                                                            : const Color(
                                                                0xFFC8E6C9,
                                                              ),
                                                        iconColor: activo
                                                            ? Colors.red
                                                            : Colors.green,
                                                        onTap: () =>
                                                            _toggleStudentStatus(
                                                              s,
                                                            ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Tooltip(
                                                      message: 'Eliminar',
                                                      child: _UserActionBtn(
                                                        icon: Icons
                                                            .delete_outline_rounded,
                                                        borderColor:
                                                            const Color(
                                                              0xFFFFCDD2,
                                                            ),
                                                        iconColor: Colors.red,
                                                        onTap: () async {
                                                          final ok =
                                                              await _confirmDelete(
                                                                name,
                                                              );
                                                          if (ok) {
                                                            await _deleteStudent(
                                                              id,
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      )
                else
                  // ── Tab Profesores ───────────────────────────────────
                  teachersAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Error: $e',
                                style: const TextStyle(color: _kText3),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () =>
                                    ref.invalidate(_teachersProvider),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                        data: (teachers) {
                          final filtered = teachers.where((t) {
                            final q = _searchProfesores.toLowerCase();
                            return (t['full_name'] as String)
                                    .toLowerCase()
                                    .contains(q) ||
                                (t['email'] as String).toLowerCase().contains(
                                  q,
                                ) ||
                                (t['dni'] as String? ?? '')
                                    .toLowerCase()
                                    .contains(q);
                          }).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.school_rounded,
                                    size: 15,
                                    color: _kText4,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${filtered.length} profesores',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _kText3,
                                    ),
                                  ),
                                  const Spacer(),
                                  _SearchBox(
                                    hint: 'Buscar por nombre, email o DNI...',
                                    onChanged: (v) =>
                                        setState(() => _searchProfesores = v),
                                  ),
                                  const SizedBox(width: 10),
                                  // Botón agregar profesor
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _showTeacherDialog(),
                                      child: Ink(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppTheme.secondaryBlue,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.secondaryBlue
                                                  .withValues(alpha: 0.28),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.add,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Table(
                                      columnWidths: const {
                                        0: FlexColumnWidth(200),
                                        1: FlexColumnWidth(120),
                                        2: FlexColumnWidth(200),
                                        3: FlexColumnWidth(110),
                                      },
                                      children: [
                                        TableRow(
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: _kBorderTable,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          children: const [
                                            _ThCell('Nombre y Apellido'),
                                            _ThCell('DNI'),
                                            _ThCell('Email'),
                                            _ThCell('Acciones'),
                                          ],
                                        ),
                                        ...filtered.asMap().entries.map((e) {
                                          final t = e.value;
                                          final isLast =
                                              e.key == filtered.length - 1;
                                          final name = t['full_name'] as String;
                                          final email = t['email'] as String;
                                          final dni =
                                              t['dni'] as String? ?? '—';
                                          final id = t['id'] as String;
                                          final (bg, fg) = _avatarColors(id);

                                          return TableRow(
                                            decoration: isLast
                                                ? null
                                                : const BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: _kBorderTable,
                                                      ),
                                                    ),
                                                  ),
                                            children: [
                                              // Nombre
                                              _TdPadding(
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 30,
                                                      height: 30,
                                                      decoration: BoxDecoration(
                                                        color: bg,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          _initials(name),
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: fg,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: _kText1,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // DNI
                                              _TdPadding(
                                                child: Text(
                                                  dni,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kText3,
                                                  ),
                                                ),
                                              ),
                                              // Email
                                              _TdPadding(
                                                child: Text(
                                                  email,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kText3,
                                                  ),
                                                ),
                                              ),
                                              // Acciones
                                              _TdPadding(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Tooltip(
                                                      message: 'Editar',
                                                      child: _UserActionBtn(
                                                        icon:
                                                            Icons.edit_outlined,
                                                        borderColor:
                                                            const Color(
                                                              0xFFBBDEFB,
                                                            ),
                                                        iconColor: _kPrimary,
                                                        onTap: () =>
                                                            _showTeacherDialog(
                                                              teacher: t,
                                                            ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Tooltip(
                                                      message: 'Eliminar',
                                                      child: _UserActionBtn(
                                                        icon: Icons
                                                            .delete_outline_rounded,
                                                        borderColor:
                                                            const Color(
                                                              0xFFFFCDD2,
                                                            ),
                                                        iconColor: Colors.red,
                                                        onTap: () async {
                                                          final ok =
                                                              await _confirmDelete(
                                                                name,
                                                              );
                                                          if (ok) {
                                                            await _deleteTeacher(
                                                              id,
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo fin de ciclo lectivo ────────────────────────────────────────────

class _ResetCycleDialog extends StatefulWidget {
  const _ResetCycleDialog();

  @override
  State<_ResetCycleDialog> createState() => _ResetCycleDialogState();
}

class _ResetCycleDialogState extends State<_ResetCycleDialog> {
  bool _loading = false;

  static const _deleted = [
    ('Reservas', 'Todas las reservas registradas.'),
    ('Retiros y devoluciones', 'Historial de checkouts y returns.'),
    ('Daños', 'Reportes de daño asociados a devoluciones.'),
    ('Notificaciones', 'Avisos generados por el sistema.'),
    ('Tokens de profesores', 'Enlaces de invitación pendientes.'),
    ('Alumnos', 'Todos los registros de alumnos.'),
  ];

  static const _preserved = [
    'Profesores',
    'Watchlist (sanciones por daño)',
    'Dispositivos',
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFEBEE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFC62828),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Fin de ciclo lectivo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _kText1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Esta acción vacía la base de datos al cierre del ciclo lectivo. '
                'Los siguientes datos se eliminarán de forma definitiva:',
                style: TextStyle(
                  fontSize: 13,
                  color: _kText3,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              // Lista de datos a eliminar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7F7),
                  border: Border.all(color: const Color(0xFFFFCDD2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in _deleted)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Color(0xFFC62828),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: _kText1,
                                    height: 1.35,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '${entry.$1}: ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: entry.$2,
                                      style: const TextStyle(color: _kText3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Se preservarán:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kText1,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  border: Border.all(color: const Color(0xFFC8E6C9)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in _preserved)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Color(0xFF2E7D32),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              p,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _kText1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Aviso destacado en rojo
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEF9A9A), width: 1.4),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFC62828),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Esta acción es IRREVERSIBLE y no se puede deshacer.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFC62828),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() => _loading = true);
                            Navigator.pop(context, true);
                          },
                    icon: _loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                          ),
                    label: const Text('Eliminar datos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo agregar/editar profesor ─────────────────────────────────────────

class _UserFormDialog extends StatelessWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController dniCtrl;

  const _UserFormDialog({
    required this.title,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.dniCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _kText1,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _DialogFieldLabel('Nombre completo *'),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: 'Ej. Juan García'),
              ),
              const SizedBox(height: 14),
              const _DialogFieldLabel('Email *'),
              const SizedBox(height: 6),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  hintText: 'Ej. juan@escuela.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              const _DialogFieldLabel('DNI *'),
              const SizedBox(height: 6),
              TextField(
                controller: dniCtrl,
                decoration: const InputDecoration(hintText: 'Ej. 30123456'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (nameCtrl.text.trim().isEmpty ||
                          emailCtrl.text.trim().isEmpty ||
                          dniCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Todos los campos son requeridos'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo editar alumno ────────────────────────────────────────────────────

class _StudentFormDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController dniCtrl;
  final int initialYear;
  final int initialDiv;
  final String initialSpec;
  final void Function(int year, int div, String spec) onChanged;

  const _StudentFormDialog({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.dniCtrl,
    required this.initialYear,
    required this.initialDiv,
    required this.initialSpec,
    required this.onChanged,
  });

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  late int _year;
  late int _div;
  late String _spec;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _div = widget.initialDiv;
    _spec = widget.initialSpec;
  }

  void _notify() => widget.onChanged(_year, _div, _spec);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Editar alumno',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _kText1,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _DialogFieldLabel('Nombre completo *'),
              const SizedBox(height: 6),
              TextField(
                controller: widget.nameCtrl,
                decoration: const InputDecoration(hintText: 'Ej. Ana García'),
              ),
              const SizedBox(height: 14),
              const _DialogFieldLabel('Email *'),
              const SizedBox(height: 6),
              TextField(
                controller: widget.emailCtrl,
                decoration: const InputDecoration(hintText: 'Ej. ana@mail.com'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              const _DialogFieldLabel('DNI *'),
              const SizedBox(height: 6),
              TextField(
                controller: widget.dniCtrl,
                decoration: const InputDecoration(hintText: 'Ej. 12345678'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel('Año'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<int>(
                          initialValue: _year,
                          decoration: const InputDecoration(),
                          items: List.generate(
                            7,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}°'),
                            ),
                          ),
                          onChanged: (v) {
                            if (v != null) setState(() => _year = v);
                            _notify();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel('División'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<int>(
                          initialValue: _div,
                          decoration: const InputDecoration(),
                          items: List.generate(
                            6,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}°'),
                            ),
                          ),
                          onChanged: (v) {
                            if (v != null) setState(() => _div = v);
                            _notify();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _DialogFieldLabel('Especialidad'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _spec,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(
                    value: 'ciclo_basico',
                    child: Text('Ciclo Básico'),
                  ),
                  DropdownMenuItem(
                    value: 'programacion',
                    child: Text('Programación'),
                  ),
                  DropdownMenuItem(
                    value: 'electronica',
                    child: Text('Electrónica'),
                  ),
                  DropdownMenuItem(
                    value: 'construcciones',
                    child: Text('Construcciones'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _spec = v);
                  _notify();
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Badge de estado de alumno ────────────────────────────────────────────────

class _StudentStatusBadge extends StatelessWidget {
  final bool activo;
  final bool inWatchlist;
  const _StudentStatusBadge({required this.activo, required this.inWatchlist});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = activo
        ? (const Color(0xFFE8F5E9), const Color(0xFF2E7D32), '● Activo')
        : inWatchlist
        ? (
            const Color(0xFFFFF3E0),
            const Color(0xFFE65100),
            '● Inactivo (watchlist)',
          )
        : (const Color(0xFFFCE4EC), const Color(0xFFC62828), '● Inactivo');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}

// ─── Botón de acción de usuario ───────────────────────────────────────────────

class _UserActionBtn extends StatelessWidget {
  final IconData icon;
  final Color borderColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _UserActionBtn({
    required this.icon,
    required this.borderColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}

// ─── Botones de acción (Reservas) ────────────────────────────────────────────

class _ReservationActionButtons extends ConsumerWidget {
  final Map<String, dynamic> reservation;
  final _ReservationFlowState flowState;

  const _ReservationActionButtons({
    required this.reservation,
    required this.flowState,
  });

  static const Color _disabledColor = Color(0xFFB8BDC7);

  String get _reservationId => reservation['id']?.toString() ?? '';

  String? get _checkoutId {
    final checkoutId = reservation['checkout_id']?.toString();
    if (checkoutId == null || checkoutId.isEmpty) return null;
    return checkoutId;
  }

  bool get _canCheckout => flowState == _ReservationFlowState.pending;
  bool get _canReturn => flowState == _ReservationFlowState.active;
  bool get _canCancel => flowState == _ReservationFlowState.pending;
  bool get _isTeacher => reservation['booker_type'] == 'teacher';
  bool get _canShowToken => _isTeacher && _canCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isTeacher) ...[
          Tooltip(
            message: _canShowToken
                ? 'Mostrar token de retiro'
                : 'Solo disponible cuando está pendiente',
            child: _ActionIconButton(
              icon: Icons.qr_code_2_rounded,
              color: _canShowToken
                  ? AppTheme.primaryBlue
                  : _disabledColor,
              onPressed: _canShowToken
                  ? () => _handleShowToken(context, ref)
                  : null,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Tooltip(
          message: _canCheckout
              ? 'Registrar retirada'
              : 'Solo disponible cuando está pendiente',
          child: _ActionIconButton(
            icon: Icons.login_rounded,
            color: _canCheckout ? AppTheme.secondaryBlue : _disabledColor,
            onPressed: _canCheckout
                ? () => _handleCheckout(context, ref)
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: _canReturn
              ? 'Registrar devuelta'
              : 'Solo disponible cuando está activa',
          child: _ActionIconButton(
            icon: Icons.assignment_returned_rounded,
            color: _canReturn ? AppTheme.statusAvailable : _disabledColor,
            onPressed: _canReturn ? () => _handleReturn(context, ref) : null,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: _canCancel
              ? 'Cancelar reserva'
              : 'Solo disponible cuando está pendiente',
          child: _ActionIconButton(
            icon: Icons.delete_outline_rounded,
            color: _canCancel ? Colors.red : _disabledColor,
            onPressed: _canCancel ? () => _handleCancel(context, ref) : null,
          ),
        ),
      ],
    );
  }

  Future<void> _handleShowToken(BuildContext context, WidgetRef ref) async {
    if (_reservationId.isEmpty) return;
    await TeacherTokenDialog.fetchAndShow(
      context,
      reservationId: _reservationId,
      teacherName: reservation['teacher_name']?.toString(),
    );
  }

  Future<void> _handleCheckout(BuildContext context, WidgetRef ref) async {
    if (_reservationId.isEmpty) return;
    try {
      final notifier = ref.read(notebookListProvider.notifier);
      final result = await notifier.approveCheckout(
        reservationId: _reservationId,
      );
      if (!context.mounted) return;

      if (result['requires_confirmation'] == true) {
        final message =
            result['message']?.toString() ??
            'El alumno no está activado. ¿Deseás confirmar la retirada?';
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar retirada'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        final confirmedResult = await notifier.approveCheckout(
          reservationId: _reservationId,
          confirm: true,
        );
        if (!context.mounted) return;
        _showCheckoutSuccess(context, confirmedResult);
      } else {
        _showCheckoutSuccess(context, result);
      }
      ref.invalidate(_allReservationsProvider);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  Future<void> _handleReturn(BuildContext context, WidgetRef ref) async {
    final checkoutId = _checkoutId;
    if (checkoutId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró el checkout para esta reserva.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    try {
      await ref
          .read(notebookListProvider.notifier)
          .processReturn(checkoutId: checkoutId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Devolución registrada.'),
          backgroundColor: AppTheme.statusAvailable,
        ),
      );
      ref.invalidate(_allReservationsProvider);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  Future<void> _handleCancel(BuildContext context, WidgetRef ref) async {
    if (_reservationId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: const Text('¿Querés cancelar esta reserva?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(notebookListProvider.notifier)
          .cancelReservation(_reservationId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Reserva cancelada.'),
          backgroundColor: AppTheme.statusAvailable,
        ),
      );
      ref.invalidate(_allReservationsProvider);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  void _showCheckoutSuccess(BuildContext context, Map<String, dynamic> result) {
    final studentActivated = result['student_activated'] == true;
    final message = studentActivated
        ? '✓ Retirada registrada y alumno activado.'
        : '✓ Retirada registrada.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.statusAvailable,
      ),
    );
  }

  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES (definiciones faltantes)
// ─────────────────────────────────────────────────────────────────────────────

// ─── _HeaderSectionCard ───────────────────────────────────────────────────────

class _HeaderSectionCard extends StatelessWidget {
  final _HeaderSectionMetric metric;
  final int count;

  const _HeaderSectionCard({required this.metric, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── _LegendItem ──────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _LegendItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textColor,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── _StatusBadge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final DeviceStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      DeviceStatus.available => (
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
          '● Disponible',
        ),
      DeviceStatus.inUse => (
          const Color(0xFFE3F2FD),
          AppTheme.primaryBlue,
          '● En uso',
        ),
      DeviceStatus.maintenance => (
          const Color(0xFFFFF3E0),
          AppTheme.statusMaint,
          '● Mantenimiento',
        ),
      _ => (
          const Color(0xFFF5F5F5),
          Colors.grey,
          '● Desconocido',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

// ─── _ActionIconButton ────────────────────────────────────────────────────────

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final iconColor = disabled ? color.withValues(alpha: 0.4) : color;
    final borderColor = disabled
        ? const Color(0xFFE0E0E0)
        : Color.alphaBlend(color.withValues(alpha: 0.35), Colors.white);

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}

// ─── _DialogFieldLabel ────────────────────────────────────────────────────────

class _DialogFieldLabel extends StatelessWidget {
  final String text;

  const _DialogFieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textColor,
      ),
    );
  }
}

// ─── _BookerTypeBadge ─────────────────────────────────────────────────────────

class _BookerTypeBadge extends StatelessWidget {
  final String typeLabel;
  final bool isTeacher;

  const _BookerTypeBadge({required this.typeLabel, required this.isTeacher});

  @override
  Widget build(BuildContext context) {
    final bg = isTeacher ? const Color(0xFFE3F2FD) : const Color(0xFFF3E5F5);
    final fg = isTeacher ? AppTheme.primaryBlue : const Color(0xFF6A1B9A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        typeLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

// ─── _ReservationFlowBadge ────────────────────────────────────────────────────

class _ReservationFlowBadge extends StatelessWidget {
  final _ReservationFlowState flowState;

  const _ReservationFlowBadge({required this.flowState});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (flowState) {
      _ReservationFlowState.pending => (
          const Color(0xFFFFF9C4),
          const Color(0xFFF57F17),
          '● Pendiente',
        ),
      _ReservationFlowState.active => (
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
          '● Activa',
        ),
      _ReservationFlowState.finalized => (
          const Color(0xFFE3F2FD),
          AppTheme.primaryBlue,
          '● Finalizada',
        ),
      _ReservationFlowState.cancelled => (
          const Color(0xFFFCE4EC),
          const Color(0xFFC62828),
          '● Cancelada',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

// ─── _SearchBox ───────────────────────────────────────────────────────────────

class _FilterOption {
  final String value;
  final String label;
  const _FilterOption(this.value, this.label);
}

class _FilterDropdown extends StatelessWidget {
  final String hint;
  final String value;
  final List<_FilterOption> options;
  final ValueChanged<String> onChanged;
  final double width;

  const _FilterDropdown({
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 36,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        style: const TextStyle(fontSize: 13, color: _kText1),
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: _kText4,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: _kText4),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kPrimary),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        items: options
            .map(
              (o) => DropdownMenuItem<String>(
                value: o.value,
                child: Text(
                  o.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: o.value.isEmpty ? _kText4 : _kText1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (v) => onChanged(v ?? ''),
      ),
    );
  }
}

class _DateFilterField extends StatelessWidget {
  final String hint;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final double width;

  const _DateFilterField({
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.width,
  });

  String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return SizedBox(
      width: width,
      height: 36,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: hasValue ? _kPrimary : _kBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: _kText4,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasValue ? _format(value!) : hint,
                  style: TextStyle(
                    fontSize: 13,
                    color: hasValue ? _kText1 : _kText4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasValue)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(null),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 15, color: _kText4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeFilterField extends StatelessWidget {
  final String hint;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?> onChanged;
  final double width;

  const _TimeFilterField({
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.width,
  });

  String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return SizedBox(
      width: width,
      height: 36,
      child: GestureDetector(
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: value ?? TimeOfDay.now(),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
              child: child ?? const SizedBox.shrink(),
            ),
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: hasValue ? _kPrimary : _kBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 15,
                color: _kText4,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasValue ? _format(value!) : hint,
                  style: TextStyle(
                    fontSize: 13,
                    color: hasValue ? _kText1 : _kText4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasValue)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(null),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 15, color: _kText4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceFiltersBar extends StatelessWidget {
  final String search;
  final String type;
  final String status;
  final bool hasActiveFilters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onClear;

  const _DeviceFiltersBar({
    required this.search,
    required this.type,
    required this.status,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SearchBox(
          hint: 'Buscar por número o notas...',
          onChanged: onSearchChanged,
        ),
        _FilterDropdown(
          width: 130,
          hint: 'Tipo',
          value: type,
          options: const [
            _FilterOption('', 'Todos'),
            _FilterOption('notebook', 'PC'),
            _FilterOption('television', 'TV'),
          ],
          onChanged: onTypeChanged,
        ),
        _FilterDropdown(
          width: 170,
          hint: 'Estado',
          value: status,
          options: const [
            _FilterOption('', 'Todos'),
            _FilterOption('available', 'Disponible'),
            _FilterOption('in_use', 'En Uso'),
            _FilterOption('maintenance', 'Mantenimiento'),
            _FilterOption('out_of_service', 'Fuera de Servicio'),
          ],
          onChanged: onStatusChanged,
        ),
        if (hasActiveFilters)
          SizedBox(
            height: 36,
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Limpiar'),
              style: TextButton.styleFrom(
                foregroundColor: _kText3,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReservationFiltersBar extends StatelessWidget {
  final String search;
  final DateTime? date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String estado;
  final String tipo;
  final bool hasActiveFilters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<DateTime?> onDateChanged;
  final ValueChanged<TimeOfDay?> onStartTimeChanged;
  final ValueChanged<TimeOfDay?> onEndTimeChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onTipoChanged;
  final VoidCallback onClear;

  const _ReservationFiltersBar({
    required this.search,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.estado,
    required this.tipo,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onDateChanged,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.onEstadoChanged,
    required this.onTipoChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SearchBox(
          hint: 'Buscar por nombre, DNI, email o N° dispositivo...',
          onChanged: onSearchChanged,
        ),
        _DateFilterField(
          width: 150,
          hint: 'Fecha',
          value: date,
          onChanged: onDateChanged,
        ),
        _TimeFilterField(
          width: 130,
          hint: 'Inicio desde',
          value: startTime,
          onChanged: onStartTimeChanged,
        ),
        _TimeFilterField(
          width: 130,
          hint: 'Fin hasta',
          value: endTime,
          onChanged: onEndTimeChanged,
        ),
        _FilterDropdown(
          width: 150,
          hint: 'Estado',
          value: estado,
          options: const [
            _FilterOption('', 'Todos'),
            _FilterOption('pending', 'Pendiente'),
            _FilterOption('active', 'Activa'),
            _FilterOption('finalized', 'Finalizada'),
            _FilterOption('cancelled', 'Cancelada'),
          ],
          onChanged: onEstadoChanged,
        ),
        _FilterDropdown(
          width: 140,
          hint: 'Tipo',
          value: tipo,
          options: const [
            _FilterOption('', 'Todos'),
            _FilterOption('student', 'Estudiante'),
            _FilterOption('teacher', 'Profesor'),
          ],
          onChanged: onTipoChanged,
        ),
        if (hasActiveFilters)
          SizedBox(
            height: 36,
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Limpiar'),
              style: TextButton.styleFrom(
                foregroundColor: _kText3,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _SearchBox({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 36,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: _kText4),
          prefixIcon: const Icon(Icons.search, size: 18, color: _kText4),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kPrimary),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}

// ─── _ThCell ──────────────────────────────────────────────────────────────────

class _ThCell extends StatelessWidget {
  final String text;

  const _ThCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kPrimary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── _TdPadding ───────────────────────────────────────────────────────────────

class _TdPadding extends StatelessWidget {
  final Widget child;

  const _TdPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
  }
}