import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/notebook_list_provider.dart';
import '../../application/providers/auth_provider.dart';
import '../../domain/entities/user.dart';
import '../../domain/entities/device.dart';
import '../widgets/device_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final notebooksAsync = ref.watch(notebookListProvider);

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  ref.read(authProvider.notifier).login('alumno@nrs.com', '12345678', UserRole.student);
                },
                child: const Text('Simular Login Alumno'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(authProvider.notifier).login('docente@nrs.com', '87654321', UserRole.teacher);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Simular Login Docente'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(authProvider.notifier).login('admin@nrs.com', '00000000', UserRole.admin);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Simular Login Admin'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('NRS - Home (${user.role.name})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: notebooksAsync.when(
        data: (devices) {
          if (user.role == UserRole.admin) {
            return _buildAdminView(context, ref, devices);
          } else {
            return _buildUserGrid(context, devices, user);
          }
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildUserGrid(BuildContext context, List<Device> devices, User user) {
    // Filtrar dispositivos según el rol
    final visibleDevices = devices.where((device) {
      if (user.role == UserRole.student && device.model == DeviceModel.tv) {
        return false; // Alumnos no ven TVs
      }
      return true; // Docentes ven todo
    }).toList();

    return Column(
      children: [
        if (!user.isActive)
          Container(
            color: Colors.orange.withOpacity(0.2),
            padding: const EdgeInsets.all(12),
            child: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cuenta en Aire. Tu cuenta se activará tras tu primer retiro físico.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.0, // Hace las tarjetas cuadradas
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: visibleDevices.length,
            itemBuilder: (context, index) {
              return DeviceCard(
                device: visibleDevices[index],
                onReserve: () {
                  // La lógica de DatePicker se maneja dentro de DeviceCard, aquí podemos añadir cualquier otra lógica central
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdminView(BuildContext context, WidgetRef ref, List<Device> devices) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Modelo')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Usuario Asignado')),
          DataColumn(label: Text('Acciones')),
        ],
        rows: devices.map((device) {
          return DataRow(cells: [
            DataCell(Text(device.id)),
            DataCell(Text(device.model.name)),
            DataCell(Text(device.status.name)),
            DataCell(Text(device.currentUserEmail ?? '-')),
            DataCell(Row(
              children: [
                if (device.status == DeviceStatus.available)
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Retiro aprobado para ${device.id}.')),
                      );
                      ref.read(notebookListProvider.notifier).updateDeviceStatus(
                        device.id, 
                        DeviceStatus.inUse,
                        userEmail: 'alumno@nrs.com', // Simulación del usuario que lo pidió
                      );
                    },
                    child: const Text('Aprobar Retiro'),
                  )
                else if (device.status == DeviceStatus.inUse)
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Dispositivo ${device.id} devuelto.')),
                      );
                      ref.read(notebookListProvider.notifier).returnDevice(device.id);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Devuelto'),
                  )
                else
                  const SizedBox(width: 120), // Placeholder para mantener alineación

                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.build),
                  onPressed: () {
                    // Cambiar a mantenimiento
                    ref.read(notebookListProvider.notifier).updateDeviceStatus(
                      device.id, 
                      device.status == DeviceStatus.maintenance 
                        ? DeviceStatus.available 
                        : DeviceStatus.maintenance,
                    );
                  },
                ),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }
}
