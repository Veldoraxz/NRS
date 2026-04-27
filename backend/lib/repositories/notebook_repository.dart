import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nrs_backend/config/env.dart';

/// Base URL da API local de notebooks.
String get baseUrl => apiBaseUrl;

/// Obtiene la lista de notebooks desde la API local.
Future<List<dynamic>> getNotebooks() async {
  final response = await http.get(Uri.parse('$baseUrl/notebooks'));
  return jsonDecode(response.body) as List<dynamic>;
}

/// Crea una nueva notebook en la API local.
Future<void> createNotebook(String title, String content) async {
  await http.post(
    Uri.parse('$baseUrl/notebooks'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'title': title, 'content': content}),
  );
}
