import 'package:postgres/postgres.dart';
import 'package:nrs_backend/config/env.dart';

Connection? _connection;

/// Parses a PostgreSQL connection string (DATABASE_URL) and returns connection parameters.
/// Supports format: postgresql://user:password@host:port/database
Map<String, dynamic> _parseConnectionUrl(String url) {
  final uri = Uri.parse(url);
  
  // Extract username and password from userInfo
  final userInfo = uri.userInfo.split(':');
  final username = userInfo[0];
  final password = userInfo.length > 1 ? userInfo[1] : '';
  
  // Extract host and port
  final host = uri.host;
  final port = uri.port > 0 ? uri.port : 5432;
  
  // Extract database name from path (remove leading slash)
  final database = uri.path.replaceFirst('/', '');
  
  return {
    'username': username,
    'password': password,
    'host': host,
    'port': port,
    'database': database,
  };
}

/// Returns a shared PostgreSQL connection for database access.
Future<Connection> getConnection() async {
  _connection ??= await Connection.open(
    Endpoint(
      host: _parseConnectionUrl(databaseUrl)['host'] as String,
      database: _parseConnectionUrl(databaseUrl)['database'] as String,
      username: _parseConnectionUrl(databaseUrl)['username'] as String,
      password: _parseConnectionUrl(databaseUrl)['password'] as String,
      port: _parseConnectionUrl(databaseUrl)['port'] as int,
    ),
  );
  return _connection!;
}
