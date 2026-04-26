import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/database.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _getAll(),
    HttpMethod.post => _create(context),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _getAll() async {
  final conn = await getConnection();
  final result = await conn.execute(
    'SELECT * FROM notebooks ORDER BY created_at DESC',
  );
  
  final notebooks = result.map((row) => {
    'id': row[0],
    'title': row[1],
    'content': row[2],
    'created_at': row[3]?.toString(),
  }).toList();

  return Response.json(body: notebooks);
}

Future<Response> _create(RequestContext context) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final conn = await getConnection();

  await conn.execute(
    'INSERT INTO notebooks (title, content) VALUES (@title, @content)',
    parameters: {'title': body['title'], 'content': body['content']},
  );

  return Response.json(body: {'message': 'Notebook creada'}, statusCode: 201);
}
