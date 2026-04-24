import 'package:flutter/material.dart';
import '../../domain/entities/device.dart';
import '../theme/theme_provider.dart';

class DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback? onReserve;

  const DeviceCard({
    Key? key,
    required this.device,
    this.onReserve,
  }) : super(key: key);

  Future<void> _selectDateTime(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (pickedTime != null && onReserve != null) {
        onReserve!();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reserva agendada para ${pickedDate.day}/${pickedDate.month}/${pickedDate.year} a las ${pickedTime.format(context)}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = device.status == DeviceStatus.inUse;
    final isAvailable = device.status == DeviceStatus.available;

    return Card(
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              device.model == DeviceModel.tv ? Icons.tv : Icons.laptop_chromebook,
              size: 32,
              color: isActive ? AppTheme.accentColor : AppTheme.textColor.withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              device.id,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getModelName(),
              style: const TextStyle(color: AppTheme.textColor, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getStatusColor(device.status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getStatusText(device.status),
                style: TextStyle(
                  color: _getStatusColor(device.status),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (isAvailable && onReserve != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _selectDateTime(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text('Reservar', style: TextStyle(fontSize: 12)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  String _getModelName() {
    switch (device.model) {
      case DeviceModel.conectarIgualdad:
        return 'Conectar Igualdad';
      case DeviceModel.cx:
        return 'CX';
      case DeviceModel.tv:
        return 'Televisor';
    }
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.available:
        return AppTheme.accentColor;
      case DeviceStatus.inUse:
        return Colors.orange;
      case DeviceStatus.maintenance:
        return Colors.redAccent;
      case DeviceStatus.outOfService:
        return Colors.grey;
    }
  }

  String _getStatusText(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.available:
        return 'Disponible';
      case DeviceStatus.inUse:
        return 'En Uso';
      case DeviceStatus.maintenance:
        return 'Mantenimiento';
      case DeviceStatus.outOfService:
        return 'Fuera de Servicio';
    }
  }
}
