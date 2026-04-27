// lib/presentation/widgets/teacher_token_dialog.dart
//
// Diálogo "Mostrar token" para reservas de profesor.
// Visible para admin (en panel de Reservas) y para el propio profesor
// (desde el historial de reservas).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../infrastructure/api_client.dart';
import '../theme/theme_provider.dart';

class TeacherTokenDialog extends StatelessWidget {
  final String token;
  final String? expiresAt;
  final String? teacherName;

  const TeacherTokenDialog({
    super.key,
    required this.token,
    this.expiresAt,
    this.teacherName,
  });

  /// Pide el token al backend para `reservationId` (lo crea si no existe)
  /// y muestra el diálogo. Maneja errores con un SnackBar.
  static Future<void> fetchAndShow(
    BuildContext context, {
    required String reservationId,
    String? teacherName,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        '/reservations/$reservationId/tokens',
      );
      final data = res.data as Map<String, dynamic>;
      final token = data['token']?.toString() ?? '';
      final expires = data['expires_at']?.toString();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => TeacherTokenDialog(
          token: token,
          expiresAt: expires,
          teacherName: teacherName,
        ),
      );
    } on DioException catch (e) {
      if (!context.mounted) return;
      final msg = ((e.response?.data as Map?)?['error'] as String?) ??
          'No se pudo obtener el token';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  String _formatExpires(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: AppTheme.primaryBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Token de retiro',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                teacherName == null
                    ? 'Mostrá este código al admin '
                          'para que el alumno designado pueda retirar.'
                    : 'Compartilo con el alumno autorizado por '
                          '${teacherName!} para realizar el retiro.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    token,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      color: AppTheme.primaryBlue,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: Color(0xFF888888),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Expira: ${_formatExpires(expiresAt!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: token));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Token copiado al portapapeles.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar'),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
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
