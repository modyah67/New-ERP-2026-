import 'dart:io';
import 'dart:convert';
import 'package:postgres/postgres.dart';

String decodeFile(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final codeUnits = <int>[];
    for (int i = 2; i < bytes.length - 1; i += 2) {
      codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }
  try {
    return utf8.decode(bytes);
  } catch (e) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

List<String> splitSqlStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  int i = 0;
  final length = sql.length;
  String? activeQuote; 
  
  while (i < length) {
    final char = sql[i];
    
    if (activeQuote == null && char == '-' && i + 1 < length && sql[i + 1] == '-') {
      while (i < length && sql[i] != '\n') {
        i++;
      }
      continue;
    }
    
    if (activeQuote == null && char == '/' && i + 1 < length && sql[i + 1] == '*') {
      i += 2;
      while (i + 1 < length && !(sql[i] == '*' && sql[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    
    if (char == '\$') {
      int j = i + 1;
      while (j < length && sql[j] != '\$') {
        final code = sql.codeUnitAt(j);
        if (!((code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95)) {
          break;
        }
        j++;
      }
      if (j < length && sql[j] == '\$') {
        final tag = sql.substring(i, j + 1);
        if (activeQuote == tag) {
          activeQuote = null;
        } else if (activeQuote == null) {
          activeQuote = tag;
        }
        buffer.write(tag);
        i = j + 1;
        continue;
      }
    }
    
    if ((char == "'" || char == '"') && activeQuote == null) {
      activeQuote = char;
    } else if (char == activeQuote) {
      bool escaped = false;
      int backslashes = 0;
      int k = i - 1;
      while (k >= 0 && sql[k] == '\\') {
        backslashes++;
        k--;
      }
      if (backslashes % 2 == 1) {
        escaped = true;
      }
      if (!escaped) {
        activeQuote = null;
      }
    }
    
    if (char == ';' && activeQuote == null) {
      buffer.write(char);
      final stmt = buffer.toString().trim();
      if (stmt.isNotEmpty) {
        statements.add(stmt);
      }
      buffer.clear();
    } else {
      buffer.write(char);
    }
    i++;
  }
  
  final rest = buffer.toString().trim();
  if (rest.isNotEmpty) {
    statements.add(rest);
  }
  return statements;
}

void main() async {
  try {
    final conn = await Connection.open(
      Endpoint(
        host: 'localhost',
        database: 'postgres',
        username: 'postgres',
        password: '123456',
        port: 5432
      ),
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );
    print('Connected successfully!');

    // Wipe database
    print('Wiping database...');
    final wipeStmts = splitSqlStatements("DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public;");
    for (final stmt in wipeStmts) {
      await conn.execute(stmt);
    }
    
    // Bootstrap Roles
    await conn.execute("""
      DO \$\$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
          CREATE ROLE anon;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
          CREATE ROLE authenticated;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
          CREATE ROLE service_role;
        END IF;
      END \$\$;
    """);

    await conn.execute("CREATE SCHEMA IF NOT EXISTS auth;");
    await conn.execute("CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), email TEXT, raw_user_meta_data JSONB);");
    await conn.execute("CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql AS \$\$ SELECT '00000000-0000-0000-0000-000000000000'::UUID; \$\$;");
    await conn.execute("CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql AS \$\$ SELECT 'authenticated'::TEXT; \$\$;");

    // List and sort migrations
    final dir = Directory('supabase/migrations');
    final files = dir.listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql') && (f.path.contains('2026') || f.path.contains('001') || f.path.contains('011')))
      .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    print('Found ${files.length} migration files.');

    for (final file in files) {
      final baseName = file.path.split(Platform.pathSeparator).last;
      if (baseName.compareTo('20260731000000_018_enterprise_posting_seed.sql') >= 0) {
        print('Stopping before migration 018: $baseName');
        break;
      }
      
      if (baseName.contains('diagnostic') || baseName.contains('verification_diagnostic')) {
        print('Skipping non-migration SQL: $baseName');
        continue;
      }

      print('Applying migration: $baseName');
      final sql = decodeFile(file);
      final stmts = splitSqlStatements(sql);
      for (final stmt in stmts) {
        try {
          await conn.execute(stmt);
        } catch (e) {
          print('FAILED STATEMENT: $stmt');
          rethrow;
        }
      }
    }

    print('\n=== Accounts Table Columns ===');
    final columnsRes = await conn.execute(
      "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'accounts' AND table_schema = 'public';"
    );
    for (final row in columnsRes) {
      print('${row[0]} (${row[1]})');
    }

    await conn.close();
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}
