// lib/presentation/screens/home_screen.dart
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/providers/notebook_list_provider.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/reservation_flow.dart';
import '../../domain/entities/user.dart';
import '../../infrastructure/api_client.dart';
import '../widgets/device_card.dart';
import '../widgets/login_dialog.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/teacher_token_dialog.dart';
import 'admin_screen.dart';

final _filterAvailableProvider = StateProvider<bool>((ref) => false);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Filtros de tipo de dispositivo (sólo profesor).
  bool _showPc = true;
  bool _showTv = true;

  // ─── Helpers de UI compartidos ──────────────────────────────────────────────

  Widget _glass(Widget child, {EdgeInsets? padding, double radius = 20}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _background() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A0F1C), Color(0xFF1A2A44)],
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);
    final devicesAsync = ref.watch(notebookListProvider);

    final user = authAsync.valueOrNull;

    // Admin → pasar al panel admin.
    if (user != null && user.role == UserRole.admin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminScreen()),
        );
      });
      return const Scaffold(
        backgroundColor: Color(0xFF0A0F1C),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isLogged = user != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1C),
      body: Stack(
        children: [
          _background(),
          SafeArea(
            child: devicesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF00F2FF)),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (devices) =>
                  _buildContent(context, devices, user, isLogged),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Contenido principal ────────────────────────────────────────────────────

  Widget _buildContent(
    BuildContext context,
    List<Device> devices,
    User? user,
    bool isLogged,
  ) {
    final onlyAvailable = ref.watch(_filterAvailableProvider);
    final isTeacher = user?.role == UserRole.teacher;

    final visibleDevices = devices.where((d) {
      // Alumnos no ven TVs (solo notebooks).
      if (user?.role == UserRole.student && d.model == DeviceModel.tv) {
        return false;
      }
      if (onlyAvailable && d.status != DeviceStatus.available) return false;
      // Profesores filtran por tipo con checkboxes.
      if (isTeacher) {
        if (!_showPc && d.model == DeviceModel.notebook) return false;
        if (!_showTv && d.model == DeviceModel.tv) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        _buildTopBar(context, user),
        if (isLogged) _buildWelcomeBanner(user!),
        if (isLogged) _buildQuickLinks(user!),
        if (isTeacher) _buildTeacherDeviceTypeFilters(),
        Expanded(
          child: _buildGrid(visibleDevices, user, onlyAvailable),
        ),
      ],
    );
  }

  // ─── Top bar (siempre visible) ──────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, User? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Logo + nombre app.
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00F2FF).withValues(alpha: 0.4),
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.school_rounded,
                  size: 20,
                  color: Color(0xFF00F2FF),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Compu Escuela',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          // Único punto de acceso al perfil/login en la esquina superior derecha.
          IconButton(
            tooltip: user == null ? 'Iniciar sesión' : 'Perfil',
            icon: Icon(
              user == null
                  ? Icons.login_rounded
                  : Icons.account_circle_outlined,
              color: Colors.white70,
            ),
            onPressed: () {
              if (user == null) {
                LoginDialog.show(context);
              } else {
                ProfileSheet.show(context);
              }
            },
          ),
        ],
      ),
    );
  }

  // ─── Banner de bienvenida personalizado ────────────────────────────────────

  Widget _buildWelcomeBanner(User user) {
    final firstName = user.fullName.split(' ').first;
    final roleText = user.role == UserRole.teacher ? 'profesor' : 'alumno';
    final inactiveTag = (!user.isActive && user.role == UserRole.student)
        ? '  ·  Cuenta inactiva'
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF00F2FF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(user.fullName),
                  style: const TextStyle(
                    color: Color(0xFF00F2FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hola, $firstName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sesión iniciada como $roleText$inactiveTag',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // ─── Accesos rápidos cuando hay sesión iniciada ────────────────────────────

  Widget _buildQuickLinks(User user) {
    final isTeacher = user.role == UserRole.teacher;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            flex: isTeacher ? 2 : 1,
            child: _QuickLinkChip(
              icon: Icons.event_note_rounded,
              label: 'Mis reservas',
              onTap: () => _showMyReservations(context),
            ),
          ),
          if (isTeacher) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _QuickLinkChip(
                icon: Icons.dashboard_customize_rounded,
                label: 'Reserva múltiple',
                onTap: _runTeacherMultiReservation,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Filtros TV/PC para profesores ─────────────────────────────────────────

  Widget _buildTeacherDeviceTypeFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _DeviceTypeCheckbox(
            label: 'PC',
            icon: Icons.laptop_chromebook,
            value: _showPc,
            onChanged: (v) => setState(() => _showPc = v),
          ),
          const SizedBox(width: 12),
          _DeviceTypeCheckbox(
            label: 'TV',
            icon: Icons.tv_rounded,
            value: _showTv,
            onChanged: (v) => setState(() => _showTv = v),
          ),
        ],
      ),
    );
  }

  // ─── Grid de dispositivos ───────────────────────────────────────────────────

  Widget _buildGrid(List<Device> devices, User? user, bool onlyAvailable) {
    // Agrupar por tipo.
    final Map<String, List<Device>> groups = {};
    for (final d in devices) {
      final key = d.model == DeviceModel.tv ? 'Televisores' : 'Notebooks';
      groups.putIfAbsent(key, () => []).add(d);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Text(
                'Computadoras disponibles',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Text(
                'Solo libres',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Switch(
                value: onlyAvailable,
                onChanged: (v) =>
                    ref.read(_filterAvailableProvider.notifier).state = v,
                activeThumbColor: const Color(0xFF00F2FF),
                inactiveThumbColor: Colors.white38,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Text(
                      'No hay dispositivos para mostrar.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F2FF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entry.key.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF00F2FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entry.value.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                  itemBuilder: (_, i) {
                    final d = entry.value[i];
                    return DeviceCard(
                      device: d,
                      onReserveTap: () => _handleDeviceTap(d, user),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── Tap en una computadora ─────────────────────────────────────────────────

  Future<void> _handleDeviceTap(Device device, User? user) async {
    if (user == null) {
      // Guest → flujo de reserva + registro.
      await _runGuestReservationFlow(context, device);
      return;
    }
    // Logueado → flujo existente del DeviceCard.
    if (!context.mounted) return;
    await DeviceCardActions.startReservation(context, ref, device);
  }

  // ─── Mis reservas (historial / cancelación) ─────────────────────────────────

  Future<void> _showMyReservations(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MyReservationsSheet(),
    );
  }

  // ─── Flujo de "Reserva múltiple" para profesores ───────────────────────────

  Future<void> _runTeacherMultiReservation() async {
    // 1. Elegir fecha.
    final today = DateTime.now();
    var initial = today;
    while (initial.weekday == DateTime.saturday ||
        initial.weekday == DateTime.sunday) {
      initial = initial.add(const Duration(days: 1));
    }
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
      selectableDayPredicate: (d) =>
          d.weekday != DateTime.saturday && d.weekday != DateTime.sunday,
    );
    if (pickedDate == null || !mounted) return;

    // 2. Elegir horario de retiro y devolución.
    final slot = await SlotPickerDialog.show(context, day: pickedDate);
    if (slot == null || !mounted) return;

    // 3. Cargar reservas existentes para ese día y filtrar dispositivos
    //    libres en la ventana elegida.
    final allDevices =
        ref.read(notebookListProvider).valueOrNull ?? const <Device>[];
    List<Map<String, dynamic>> dayReservations = [];
    try {
      final res = await ApiClient.instance.get('/reservations/all');
      final list = res.data as List<dynamic>;
      final dayStr =
          '${pickedDate.year.toString().padLeft(4, '0')}-'
          '${pickedDate.month.toString().padLeft(2, '0')}-'
          '${pickedDate.day.toString().padLeft(2, '0')}';
      dayReservations = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) =>
              r['date']?.toString() == dayStr &&
              (r['status'] == 'pending' || r['status'] == 'confirmed'))
          .toList();
    } catch (_) {
      // Si falla, dejamos la lista vacía (asumimos disponibles).
    }
    if (!mounted) return;

    final reqStart = _toMinutes(slot.start);
    final reqEnd = _toMinutes(slot.end);

    final available = allDevices.where((d) {
      if (d.status != DeviceStatus.available) return false;
      final conflicts = dayReservations.where((r) => r['device_id'] == d.id);
      for (final r in conflicts) {
        final rs = _toMinutes(r['start_time']?.toString() ?? '');
        final re = _toMinutes(r['end_time']?.toString() ?? '');
        if (rs < reqEnd && re > reqStart) return false;
      }
      return true;
    }).toList();

    // 4. Seleccionar notebooks (multi) + TV (max 1) entre los disponibles.
    final selection = await showModalBottomSheet<_MultiReservationSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MultiReservationDevicePickerSheet(
        available: available,
        date: pickedDate,
        startTime: slot.start,
        endTime: slot.end,
      ),
    );
    if (selection == null ||
        (selection.notebooks.isEmpty && selection.tv == null) ||
        !mounted) {
      return;
    }

    // 5. Confirmar.
    final allSelected = [
      ...selection.notebooks,
      if (selection.tv != null) selection.tv!,
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ReservationReviewDialog(
        devices: allSelected,
        date: pickedDate,
        startTime: slot.start,
        endTime: slot.end,
        roleLabel: 'Profesor',
      ),
    );
    if (confirmed != true || !mounted) return;

    // 6. Enviar reserva(s). Notebooks y TV son endpoints separados en backend.
    final notifier = ref.read(notebookListProvider.notifier);
    final errors = <String>[];

    if (selection.notebooks.isNotEmpty) {
      try {
        await notifier.reserveForTeacher(
          deviceType: 'notebook',
          deviceIds: selection.notebooks.map((d) => d.id).toList(),
          date: pickedDate,
          startTime: slot.start,
          endTime: slot.end,
        );
      } catch (e) {
        errors.add('Notebooks: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
    if (selection.tv != null) {
      try {
        await notifier.reserveForTeacher(
          deviceType: 'television',
          deviceIds: [selection.tv!.id],
          date: pickedDate,
          startTime: slot.start,
          endTime: slot.end,
        );
      } catch (e) {
        errors.add('TV: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }

    if (!mounted) return;
    if (errors.isEmpty) {
      _toast(
        context,
        '✓ Reserva múltiple creada (${allSelected.length} dispositivos).',
      );
    } else {
      _toast(context, errors.join('\n'), isError: true);
    }
  }

  int _toMinutes(String hhmm) {
    if (hhmm.isEmpty) return 0;
    final p = hhmm.split(':');
    if (p.length < 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  // ─── Flujo de reserva como invitado ─────────────────────────────────────────

  Future<void> _runGuestReservationFlow(
    BuildContext context,
    Device device,
  ) async {
    // 1. Datos de reserva.
    final draft = await showModalBottomSheet<_GuestReservationDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GuestReservationFormSheet(device: device),
    );
    if (draft == null || !context.mounted) return;

    // 1.5 Revisión / confirmación previa.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ReservationReviewDialog(
        devices: [device],
        date: draft.date,
        startTime: draft.startTime,
        endTime: draft.endTime,
        roleLabel: 'Alumno',
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // 2. Datos de registro.
    final form = await showModalBottomSheet<_GuestRegistrationData>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _GuestRegistrationSheet(),
    );
    if (form == null || !context.mounted) return;

    // 3. Crear cuenta + iniciar sesión.
    try {
      await ApiClient.instance.post(
        '/students/register',
        data: {
          'full_name': form.fullName,
          'email': form.email,
          'dni': form.dni,
          'year': form.year,
          'division': form.division,
          if (form.year >= 4) 'specialty': form.specialty,
        },
      );
    } on DioException catch (e) {
      if (!context.mounted) return;
      _toast(
        context,
        ((e.response?.data as Map?)?['error'] as String?) ??
            'No se pudo crear la cuenta',
        isError: true,
      );
      return;
    }

    if (!context.mounted) return;

    // 4. Aviso de cuenta inactiva.
    final goAhead = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _InactiveAccountDialog(),
    );
    if (goAhead != true || !context.mounted) return;

    // 5. Login automático.
    try {
      await ref.read(authProvider.notifier).login(form.email, form.dni);
    } catch (e) {
      if (!context.mounted) return;
      _toast(
        context,
        'Cuenta creada, pero falló el inicio de sesión: $e',
        isError: true,
      );
      return;
    }

    // 6. Crear la reserva con los datos elegidos.
    try {
      await ref.read(notebookListProvider.notifier).reserveDevice(
            device.id,
            draft.date,
            draft.startTime,
            draft.endTime,
          );
    } catch (e) {
      if (!context.mounted) return;
      _toast(
        context,
        'No se pudo registrar la reserva: $e',
        isError: true,
      );
      return;
    }

    if (!context.mounted) return;
    _toast(
      context,
      '✓ Reserva registrada. La cuenta se activará al completarse.',
    );
  }

  void _toast(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFC62828)
            : const Color(0xFF2E7D32),
      ),
    );
  }
}

// ─── Checkbox compacto para filtrar tipo de dispositivo ──────────────────────

class _DeviceTypeCheckbox extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DeviceTypeCheckbox({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF00F2FF).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value
                ? const Color(0xFF00F2FF)
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: value ? const Color(0xFF00F2FF) : Colors.white60,
            ),
            const SizedBox(width: 6),
            Icon(
              icon,
              size: 14,
              color: value ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: value ? Colors.white : Colors.white60,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chip de acceso rápido ────────────────────────────────────────────────────

class _QuickLinkChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickLinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF00F2FF), size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sheet de mis reservas ───────────────────────────────────────────────────
//
// Muestra solo reservas activas o pendientes (oculta finalizadas y canceladas).
// Permite filtrar por fecha y por estado, y ordena por proximidad por defecto.

class _MyReservationsSheet extends ConsumerStatefulWidget {
  const _MyReservationsSheet();

  @override
  ConsumerState<_MyReservationsSheet> createState() =>
      _MyReservationsSheetState();
}

class _MyReservationsSheetState extends ConsumerState<_MyReservationsSheet> {
  late Future<List<Map<String, dynamic>>> _future;

  // Filtros
  DateTime? _filterDate;
  String _filterStatus = ''; // '', 'pending', 'active'

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await ApiClient.instance.get('/reservations');
    final list = res.data as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _cancel(String id) async {
    try {
      await ref.read(notebookListProvider.notifier).cancelReservation(id);
      setState(() => _future = _load());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Reserva cancelada.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFFC62828),
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _filterDate = picked);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool get _hasActiveFilters =>
      _filterDate != null || _filterStatus.isNotEmpty;

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> all) {
    final filtered = all.where((r) {
      final flow = resolveReservationFlow(r);
      // Solo mostramos pendientes o activas (oculta finalizadas y canceladas).
      if (flow != ReservationFlowState.pending &&
          flow != ReservationFlowState.active) {
        return false;
      }
      if (_filterStatus.isNotEmpty && flow.name != _filterStatus) {
        return false;
      }
      if (_filterDate != null) {
        final iso =
            '${_filterDate!.year.toString().padLeft(4, '0')}-'
            '${_filterDate!.month.toString().padLeft(2, '0')}-'
            '${_filterDate!.day.toString().padLeft(2, '0')}';
        if (r['date']?.toString() != iso) return false;
      }
      return true;
    }).toList();

    // Más próxima primero (ASC por fecha + start_time).
    filtered.sort((a, b) {
      final da = (a['date'] ?? '') + (a['start_time'] ?? '');
      final db = (b['date'] ?? '') + (b['start_time'] ?? '');
      return da.toString().compareTo(db.toString());
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1C).withValues(alpha: 0.92),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Mis reservas',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Filtros — todos en la misma fila horizontal y con la misma altura.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _MyResFilterChip(
                          icon: Icons.calendar_today_outlined,
                          label: _filterDate == null
                              ? 'Fecha'
                              : _fmtDate(_filterDate!),
                          active: _filterDate != null,
                          onTap: _pickDate,
                          onClear: _filterDate == null
                              ? null
                              : () => setState(() => _filterDate = null),
                        ),
                        const SizedBox(width: 8),
                        _MyResStatusDropdown(
                          value: _filterStatus,
                          onChanged: (v) =>
                              setState(() => _filterStatus = v),
                        ),
                        if (_hasActiveFilters) ...[
                          const SizedBox(width: 8),
                          _MyResFilterChip(
                            icon: Icons.filter_alt_off_outlined,
                            label: 'Limpiar',
                            active: false,
                            onTap: () => setState(() {
                              _filterDate = null;
                              _filterStatus = '';
                            }),
                            onClear: null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00F2FF),
                          ),
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snap.error}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      final items = _applyFilters(snap.data ?? []);
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            _hasActiveFilters
                                ? 'No hay reservas que coincidan con los filtros.'
                                : 'No tenés reservas pendientes.',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        );
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final item = items[i];
                          final id = item['id'] as String;
                          final isTeacher =
                              (item['booker_type']?.toString() ?? '') ==
                                  'teacher';
                          return _ReservationTile(
                            data: item,
                            onCancel: () => _cancel(id),
                            onShowToken: isTeacher
                                ? () => TeacherTokenDialog.fetchAndShow(
                                      context,
                                      reservationId: id,
                                      teacherName:
                                          item['teacher_name']?.toString(),
                                    )
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Tamaño y estilos compartidos entre todos los controles del filtro,
// para que fecha, estado y "limpiar" tengan exactamente el mismo grosor.
const double _kMyResFilterHeight = 36;
const double _kMyResFilterRadius = 10;
const double _kMyResFilterIconSize = 14;
const double _kMyResFilterFontSize = 12;
const Color _kMyResFilterAccent = Color(0xFF00F2FF);

BoxDecoration _myResFilterDecoration({required bool active}) {
  return BoxDecoration(
    color: active
        ? _kMyResFilterAccent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.05),
    borderRadius: BorderRadius.circular(_kMyResFilterRadius),
    border: Border.all(
      color: active
          ? _kMyResFilterAccent
          : Colors.white.withValues(alpha: 0.18),
    ),
  );
}

class _MyResFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _MyResFilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: _kMyResFilterHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _myResFilterDecoration(active: active),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: _kMyResFilterIconSize,
              color: active ? _kMyResFilterAccent : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: _kMyResFilterFontSize,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: const Icon(
                  Icons.close,
                  size: _kMyResFilterIconSize,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyResStatusDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _MyResStatusDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isActive = value.isNotEmpty;
    return Container(
      height: _kMyResFilterHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _myResFilterDecoration(active: isActive),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF101A2C),
          icon: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Colors.white70,
            ),
          ),
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontSize: _kMyResFilterFontSize,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('Estado: todos')),
            DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
            DropdownMenuItem(value: 'active', child: Text('Activa')),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCancel;
  final VoidCallback? onShowToken;
  const _ReservationTile({
    required this.data,
    required this.onCancel,
    this.onShowToken,
  });

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String? ?? '').toLowerCase();
    final canCancel = status == 'pending' || status == 'confirmed';
    final date = data['date']?.toString() ?? '—';
    final start = data['start_time']?.toString() ?? '';
    final end = data['end_time']?.toString() ?? '';
    final deviceNumber = data['device_number']?.toString() ?? '';
    final isTeacherReservation =
        (data['booker_type']?.toString().toLowerCase() ?? '') == 'teacher';
    final canShowToken = isTeacherReservation && canCancel;

    final (badgeColor, badgeLabel) = switch (status) {
      'pending' => (const Color(0xFF00F2FF), 'Pendiente'),
      'confirmed' => (const Color(0xFF00F2FF), 'Pendiente'),
      'cancelled' => (Colors.redAccent, 'Cancelada'),
      'expired' => (Colors.orangeAccent, 'Expirada'),
      'completed' => (Colors.greenAccent, 'Completada'),
      _ => (Colors.white54, status),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  deviceNumber.isEmpty ? 'Dispositivo' : 'N° $deviceNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$date  ·  $start – $end',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (canCancel) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canShowToken && onShowToken != null) ...[
                  OutlinedButton.icon(
                    onPressed: onShowToken,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                    label: const Text('Mostrar token'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00F2FF),
                      side: const BorderSide(color: Color(0xFF00F2FF)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancelar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Flujo de invitado: datos de reserva ─────────────────────────────────────

// ─── Modelo + sheet de selección para "Reserva múltiple" (profesor) ─────────

class _MultiReservationSelection {
  final List<Device> notebooks;
  final Device? tv;
  const _MultiReservationSelection({
    required this.notebooks,
    required this.tv,
  });
}

class _MultiReservationDevicePickerSheet extends StatefulWidget {
  final List<Device> available;
  final DateTime date;
  final String startTime;
  final String endTime;

  const _MultiReservationDevicePickerSheet({
    required this.available,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  @override
  State<_MultiReservationDevicePickerSheet> createState() =>
      _MultiReservationDevicePickerSheetState();
}

class _MultiReservationDevicePickerSheetState
    extends State<_MultiReservationDevicePickerSheet> {
  final Set<String> _selectedNotebooks = {};
  String? _selectedTvId;

  @override
  Widget build(BuildContext context) {
    final notebooks = widget.available
        .where((d) => d.model == DeviceModel.notebook)
        .toList();
    final tvs =
        widget.available.where((d) => d.model == DeviceModel.tv).toList();

    final dd = widget.date.day.toString().padLeft(2, '0');
    final mm = widget.date.month.toString().padLeft(2, '0');
    final canSubmit = _selectedNotebooks.isNotEmpty || _selectedTvId != null;

    return _GlassSheet(
      title: 'Seleccionar dispositivos',
      subtitle:
          '$dd/$mm/${widget.date.year} · ${widget.startTime} – ${widget.endTime}'
          ' · disponibles en ese horario',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notebooks.isEmpty && tvs.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'No hay dispositivos disponibles en ese horario.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
          ],
          if (notebooks.isNotEmpty) ...[
            const _FieldLabel('Notebooks (podés elegir varias)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: notebooks.map((d) {
                final isSel = _selectedNotebooks.contains(d.id);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSel) {
                        _selectedNotebooks.remove(d.id);
                      } else {
                        _selectedNotebooks.add(d.id);
                      }
                    });
                  },
                  child: _MultiSelectChip(
                    label: d.number,
                    icon: Icons.laptop_chromebook,
                    selected: isSel,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (tvs.isNotEmpty) ...[
            const _FieldLabel('Televisor (máx 1)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tvs.map((d) {
                final isSel = _selectedTvId == d.id;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTvId = isSel ? null : d.id;
                    });
                  },
                  child: _MultiSelectChip(
                    label: d.number,
                    icon: Icons.tv_rounded,
                    selected: isSel,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: !canSubmit
                        ? null
                        : () {
                            final selectedNotebooks = widget.available
                                .where((d) =>
                                    _selectedNotebooks.contains(d.id))
                                .toList();
                            final tv = _selectedTvId == null
                                ? null
                                : widget.available
                                    .firstWhere((d) => d.id == _selectedTvId);
                            Navigator.of(context).pop(
                              _MultiReservationSelection(
                                notebooks: selectedNotebooks,
                                tv: tv,
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Continuar'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MultiSelectChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  const _MultiSelectChip({
    required this.label,
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF00F2FF).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? const Color(0xFF00F2FF)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_circle_rounded : icon,
            size: 16,
            color: selected ? const Color(0xFF00F2FF) : Colors.white70,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestReservationDraft {
  final DateTime date;
  final String startTime;
  final String endTime;
  const _GuestReservationDraft({
    required this.date,
    required this.startTime,
    required this.endTime,
  });
}

class _GuestReservationFormSheet extends StatefulWidget {
  final Device device;
  const _GuestReservationFormSheet({required this.device});

  @override
  State<_GuestReservationFormSheet> createState() =>
      _GuestReservationFormSheetState();
}

class _GuestReservationFormSheetState
    extends State<_GuestReservationFormSheet> {
  DateTime? _date;
  String? _startTime;
  String? _endTime;

  bool get _isValid =>
      _date != null && _startTime != null && _endTime != null;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final today = DateTime.now();
    var initial = today;
    while (initial.weekday == DateTime.saturday ||
        initial.weekday == DateTime.sunday) {
      initial = initial.add(const Duration(days: 1));
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
      selectableDayPredicate: (d) =>
          d.weekday != DateTime.saturday && d.weekday != DateTime.sunday,
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        // Reseteamos los slots si cambia la fecha.
        _startTime = null;
        _endTime = null;
      });
    }
  }

  Future<void> _pickSlot() async {
    if (_date == null) {
      await _pickDate();
      if (_date == null) return;
    }
    if (!mounted) return;
    final result = await SlotPickerDialog.show(
      context,
      day: _date!,
      initialStart: _startTime,
      initialEnd: _endTime,
    );
    if (result != null) {
      setState(() {
        _startTime = result.start;
        _endTime = result.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassSheet(
      title: 'Datos de la reserva',
      subtitle:
          'Computadora N° ${widget.device.number} '
          '(${widget.device.model == DeviceModel.tv ? 'TV' : 'Notebook'})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('Día'),
          const SizedBox(height: 6),
          _GlassPickerField(
            icon: Icons.calendar_today_outlined,
            text: _date == null ? 'Elegí una fecha' : _fmtDate(_date!),
            onTap: _pickDate,
            isFilled: _date != null,
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Horario de retiro y devolución'),
          const SizedBox(height: 6),
          _GlassPickerField(
            icon: Icons.access_time_rounded,
            text: (_startTime == null || _endTime == null)
                ? 'Elegí horarios predeterminados'
                : '$_startTime  –  $_endTime',
            onTap: _pickSlot,
            isFilled: _startTime != null && _endTime != null,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: !_isValid
                        ? null
                        : () => Navigator.of(context).pop(
                              _GuestReservationDraft(
                                date: _date!,
                                startTime: _startTime!,
                                endTime: _endTime!,
                              ),
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Continuar'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Flujo de invitado: registro ─────────────────────────────────────────────

class _GuestRegistrationData {
  final String fullName;
  final String email;
  final String dni;
  final int year;
  final int division;
  final String? specialty;
  const _GuestRegistrationData({
    required this.fullName,
    required this.email,
    required this.dni,
    required this.year,
    required this.division,
    this.specialty,
  });
}

class _GuestRegistrationSheet extends StatefulWidget {
  const _GuestRegistrationSheet();

  @override
  State<_GuestRegistrationSheet> createState() =>
      _GuestRegistrationSheetState();
}

class _GuestRegistrationSheetState extends State<_GuestRegistrationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _dniCtrl = TextEditingController();
  int _year = 1;
  int _division = 1;
  String _specialty = 'programacion';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dniCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsSpecialty = _year >= 4;

    return _GlassSheet(
      title: 'Crear cuenta',
      subtitle: 'Completá tus datos para finalizar la reserva.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FieldLabel('Nombre y apellido'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _glassInputDeco(),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            const _FieldLabel('Email (Gmail)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _glassInputDeco(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requerido';
                if (!v.contains('@')) return 'Email inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            const _FieldLabel('DNI'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _dniCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: _glassInputDeco(),
              validator: (v) =>
                  (v == null || v.trim().length < 6) ? 'DNI inválido' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('Año'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        initialValue: _year,
                        dropdownColor: const Color(0xFF111A2C),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: _glassInputDeco(),
                        items: List.generate(
                          7,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}°'),
                          ),
                        ),
                        onChanged: (v) => setState(() => _year = v ?? 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('División'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        initialValue: _division,
                        dropdownColor: const Color(0xFF111A2C),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: _glassInputDeco(),
                        items: List.generate(
                          6,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}°'),
                          ),
                        ),
                        onChanged: (v) =>
                            setState(() => _division = v ?? 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (needsSpecialty) ...[
              const SizedBox(height: 12),
              const _FieldLabel('Especialidad'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _specialty,
                dropdownColor: const Color(0xFF111A2C),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _glassInputDeco(),
                items: const [
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
                onChanged: (v) =>
                    setState(() => _specialty = v ?? 'programacion'),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() != true) return;
                        Navigator.of(context).pop(
                          _GuestRegistrationData(
                            fullName: _nameCtrl.text.trim(),
                            email: _emailCtrl.text.trim(),
                            dni: _dniCtrl.text.trim(),
                            year: _year,
                            division: _division,
                            specialty: needsSpecialty ? _specialty : null,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Crear cuenta'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diálogo "cuenta inactiva" ───────────────────────────────────────────────

class _InactiveAccountDialog extends StatelessWidget {
  const _InactiveAccountDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB300).withValues(alpha: 0.18),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFFFB300),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Tu cuenta está inactiva',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tu cuenta se creó correctamente, pero queda inactiva hasta '
                  'que se complete esta primera reserva. Mientras esté '
                  'inactiva no podrás crear nuevas reservas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Continuar'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers compartidos para los sheets glass ───────────────────────────────

class _GlassSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _GlassSheet({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1C).withValues(alpha: 0.94),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _GlassPickerField extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool isFilled;
  const _GlassPickerField({
    required this.icon,
    required this.text,
    required this.onTap,
    required this.isFilled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFilled
                ? const Color(0xFF00F2FF).withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white60),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: isFilled ? Colors.white : Colors.white54,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _glassInputDeco() {
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF00F2FF), width: 1.2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
  );
}
