import 'dart:io';
import 'dart:convert';
import 'package:postgres/postgres.dart';

void main() async {
  final psqlPath = r'C:\Program Files\PostgreSQL\17\bin\psql.exe';
  
  try {
    // 1. Clean and Bootstrap database using Dart Connection
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
    print('Connected to database to initialize clean environment...');
    
    print('Wiping public schema...');
    await conn.execute("DROP SCHEMA IF EXISTS public CASCADE;");
    await conn.execute("CREATE SCHEMA public;");
    await conn.execute("GRANT ALL ON SCHEMA public TO postgres;");
    await conn.execute("GRANT ALL ON SCHEMA public TO public;");
    
    print('Bootstrapping auth schema, functions, and roles...');
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
    await conn.execute("CREATE OR REPLACE FUNCTION auth.jwt() RETURNS JSONB LANGUAGE sql AS \$\$ SELECT '{\"role\": \"authenticated\"}'::JSONB; \$\$;");
    
    await conn.close();
    print('Clean slate bootstrapped successfully.');

    // 2. List and Sort migrations
    final dir = Directory('supabase/migrations');
    final files = dir.listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql') && (f.path.contains('2026') || f.path.contains('001') || f.path.contains('011')))
      .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    print('Found ${files.length} migration files.');

    for (final file in files) {
      final baseName = file.path.split(Platform.pathSeparator).last;
      if (baseName.compareTo('20260731000000_020_rpc_build_cost_allocation.sql') > 0) {
        break;
      }
      
      if (baseName.contains('diagnostic') || baseName.contains('verification_diagnostic')) {
        continue;
      }

      print('Applying migration via psql: $baseName');
      final processResult = await Process.run(
        psqlPath,
        [
          '-h', 'localhost',
          '-U', 'postgres',
          '-d', 'postgres',
          '-p', '5432',
          '-f', file.path,
        ],
        environment: {'PGPASSWORD': '123456'},
      );

      if (processResult.stdout.toString().trim().isNotEmpty) {
        print('STDOUT:\n${processResult.stdout}');
      }
      if (processResult.stderr.toString().trim().isNotEmpty) {
        print('STDERR:\n${processResult.stderr}');
      }
    }

    // 3. Connect to perform checks
    final connTest = await Connection.open(
      Endpoint(
        host: 'localhost',
        database: 'postgres',
        username: 'postgres',
        password: '123456',
        port: 5432
      ),
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );

    // Verify posting_profiles, posting_profile_rules, document_posting_templates, sys_document_types
    final profilesRes = await connTest.execute("SELECT COUNT(*) FROM public.posting_profiles;");
    final profileRulesRes = await connTest.execute("SELECT COUNT(*) FROM public.posting_profile_rules;");
    final templatesRes = await connTest.execute("SELECT COUNT(*) FROM public.document_posting_templates;");
    final docTypesRes = await connTest.execute("SELECT COUNT(*) FROM public.sys_document_types WHERE is_active = true;");

    final profilesCount = (profilesRes.first.first as num).toInt();
    final profileRulesCount = (profileRulesRes.first.first as num).toInt();
    final templatesCount = (templatesRes.first.first as num).toInt();
    final docTypesCount = (docTypesRes.first.first as num).toInt();

    print('\nSeeded Data Check:');
    print('- posting_profiles: $profilesCount rows');
    print('- posting_profile_rules: $profileRulesCount rows');
    print('- document_posting_templates: $templatesCount rows');
    print('- active sys_document_types: $docTypesCount rows');

    await connTest.close();
  } catch (e, st) {
    print('Unhandled exception: $e\n$st');
  }
}
