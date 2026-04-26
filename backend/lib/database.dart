import 'package:postgres/postgres.dart';

Connection? _connection;

/// Returns a shared PostgreSQL connection for database access.
Future<Connection> getConnection() async {
  _connection ??= await Connection.open(
    Endpoint(
      host: 'localhost',
      database: 'nrs',
      username: 'postgres',
      password: '2007',
    ),
  );
  return _connection!;
}
