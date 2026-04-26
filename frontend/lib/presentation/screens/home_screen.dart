// lib/presentation/screens/home_screen.dart
// Combina login y vista de dispositivos tal como en el proyecto original.
// Alumno: solo notebooks, 1 reserva por día.
// Docente: notebooks + TVs, puede reservar múltiples.
// Admin: redirige a AdminScreen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/auth_provider.dart';
import '../../application/providers/notebook_list_provider.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/user.dart';
import '../widgets/device_card.dart';
import '../theme/theme_provider.dart';
import 'admin_screen.dart';

final _filterTypeProvider = StateProvider<String>((ref) => 'Todos');
final _filterAvailableProvider = StateProvider<bool>((ref) => false);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  UserRole _role = UserRole.student;
  String? _loginError;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {
      setState(() => _loginError = 'Completá todos los campos.');
      return;
    }
    setState(() {
      _isLoading = true;
      _loginError = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(_emailCtrl.text.trim(), _passwordCtrl.text, _role);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loginError = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);
    final devicesAsync = ref.watch(notebookListProvider);

    return authAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (user) {
        // ── No logueado → pantalla de login ──────────────────────────────────
        if (user == null) return _buildLogin();

        // ── Admin → AdminScreen ───────────────────────────────────────────────
        if (user.role == UserRole.admin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ── Alumno / Docente ──────────────────────────────────────────────────
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 36,
                  errorBuilder: (context2, error, stackTrace) =>
                      const Icon(Icons.school, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  'NRS (${user.role == UserRole.teacher ? "Docente" : "Alumno"})',
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle, size: 28),
                onSelected: (v) {
                  if (v == 'logout') {
                    ref.read(authProvider.notifier).logout();
                  }
                },
                itemBuilder: (menuCtx) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      user.email,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text(
                      'Cerrar Sesión',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: devicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 16),
                  Text('$err', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(notebookListProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
            data: (devices) => _buildGrid(context, devices, user),
          ),
        );
      },
    );
  }

  // ─── Pantalla de login ───────────────────────────────────────────────────────

  Widget _buildLogin() {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/logo.png',
                  width: 100,
                  height: 100,
                  errorBuilder: (ctx, err, st) => const Icon(
                    Icons.school,
                    size: 100,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'NRS — Iniciar Sesión',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 28),

                // Email
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 14),

                // Contraseña / DNI
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'DNI (contraseña)',
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 14),

                // Selector de rol
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(
                      value: UserRole.student,
                      child: Text('Alumno'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.teacher,
                      child: Text('Docente'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.admin,
                      child: Text('Administrador'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),

                if (_loginError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _loginError!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Ingresar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Grilla de dispositivos ──────────────────────────────────────────────────

  Widget _buildGrid(BuildContext context, List<Device> devices, User user) {
    final filterType = ref.watch(_filterTypeProvider);
    final onlyAvailable = ref.watch(_filterAvailableProvider);

    final visible = devices.where((d) {
      if (user.role == UserRole.student && d.model == DeviceModel.tv) {
        return false;
      }
      if (onlyAvailable && d.status != DeviceStatus.available) {
        return false;
      }
      if (filterType == 'Computadoras' && d.model == DeviceModel.tv) {
        return false;
      }
      if (filterType == 'Televisores' && d.model != DeviceModel.tv) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Banner cuenta en aire
        if (user.isPendingActivation)
          Container(
            color: AppTheme.warningColor.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.warningColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cuenta en Aire — se activará tras tu primer retiro físico aprobado por el admin.',
                    style: TextStyle(
                      color: AppTheme.warningColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Filtros
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (user.role == UserRole.teacher) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Todos', label: Text('Todos')),
                    ButtonSegment(value: 'Computadoras', label: Text('PC')),
                    ButtonSegment(value: 'Televisores', label: Text('TV')),
                  ],
                  selected: {filterType},
                  onSelectionChanged: (s) =>
                      ref.read(_filterTypeProvider.notifier).state = s.first,
                ),
                const SizedBox(width: 12),
              ],
              FilterChip(
                label: const Text('Solo Disponibles'),
                selected: onlyAvailable,
                onSelected: (v) =>
                    ref.read(_filterAvailableProvider.notifier).state = v,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(notebookListProvider.notifier).refresh(),
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),

        // Grilla
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No hay dispositivos disponibles.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.95,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final device = visible[i];
                    return DeviceCard(
                      device: device,
                      onCancel: device.status == DeviceStatus.inUse
                          ? () async {
                              try {
                                // En este punto solo tenemos el device.id,
                                // no el reservation_id.
                                // El cancel real necesita el reservation_id.
                                // Mostramos mensaje informativo.
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Para cancelar, usá la sección "Mis Reservas".',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            }
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
