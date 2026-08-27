import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  print('=== Database Refactoring Tool ===');

  final migrationsDir = Directory('supabase/migrations');
  final archiveDir = Directory('supabase/migrations_archive');

  if (!archiveDir.existsSync()) {
    archiveDir.createSync(recursive: true);
  }

  // 1. Get all files in supabase/migrations
  final files = migrationsDir.listSync().whereType<File>().toList();
  
  // Sort files numerically by prefix
  files.sort((a, b) {
    final aName = p.basename(a.path);
    final bName = p.basename(b.path);
    return _getMigrationNumber(aName).compareTo(_getMigrationNumber(bName));
  });

  final activeSchemaFiles = <File>[];
  final seedFiles = <File>[];

  // Identifiers for files to skip or handle separately
  final deprecatedIds = {
    '00001_initial_schema.sql',
    '011_schema_alignment.sql',
    '011_schema_alignment_fixed.sql',
    '010_rpc_functions.sql', // overridden by FIXED
  };

  for (final file in files) {
    final name = p.basename(file.path);
    
    // Check if it's a migration file (starts with digits)
    final isMigration = RegExp(r'^\d+_').hasMatch(name) || RegExp(r'^SEED_').hasMatch(name) || RegExp(r'^WIPE_').hasMatch(name) || RegExp(r'^VERIFY_').hasMatch(name);
    if (!isMigration) continue;

    // Skip deprecated ones
    if (deprecatedIds.contains(name)) {
      print('Skipping deprecated migration: $name');
      continue;
    }

    final numVal = _getMigrationNumber(name);
    // Skip 001-007 (since 008 drops everything anyway)
    if (numVal > 0 && numVal < 8) {
      print('Skipping legacy pre-008 migration: $name');
      continue;
    }

    // Classify seeds vs schema
    if (name.contains('seed') || name.contains('SEED') || name == '009_seed_data.sql' || name == '025_seed_exchange_rates.sql' || name == '117_seed_fruit_types.sql' || name == '281_seed_required_accounts.sql' || name == '284_full_accounts_seed.sql') {
      seedFiles.add(file);
    } else if (name == 'WIPE_RUNTIME_DATA.sql' || name == 'WIPE_ALL_DATA.sql' || name == 'VERIFY_DATABASE.sql') {
      // These are capital helper files
      continue;
    } else {
      activeSchemaFiles.add(file);
    }
  }

  print('\nFound ${activeSchemaFiles.length} active schema migrations.');
  print('Found ${seedFiles.length} seed files.');

  // 2. Compile Schema SQL
  final schemaBuffer = StringBuffer();
  schemaBuffer.writeln('-- ============================================================================');
  schemaBuffer.writeln('-- FRUITY FARMS ERP - CANONICAL DATABASE SCHEMA');
  schemaBuffer.writeln('-- Generated: ${DateTime.now().toIso8601String()}');
  schemaBuffer.writeln('-- Represents the compiled final state of the database from scratch.');
  schemaBuffer.writeln('-- ============================================================================');
  schemaBuffer.writeln();
  schemaBuffer.writeln('BEGIN;');
  schemaBuffer.writeln();

  for (final file in activeSchemaFiles) {
    final name = p.basename(file.path);
    schemaBuffer.writeln('-- ============================================================');
    schemaBuffer.writeln('-- MIGRATION: $name');
    schemaBuffer.writeln('-- ============================================================');
    final content = await file.readAsString();
    
    // Strip transactions from individual files to compile them into a single transaction
    var cleanContent = content
        .replaceAll(RegExp(r'^\s*BEGIN\s*;', caseSensitive: false, multiLine: true), '')
        .replaceAll(RegExp(r'^\s*COMMIT\s*;', caseSensitive: false, multiLine: true), '');
    
    schemaBuffer.writeln(cleanContent);
    schemaBuffer.writeln();
  }

  schemaBuffer.writeln('COMMIT;');

  // 3. Write compiled schema.sql and initial_schema.sql
  final schemaFile = File('supabase/schema.sql');
  schemaFile.writeAsStringSync(schemaBuffer.toString());
  print('\nCreated supabase/schema.sql (${schemaFile.lengthSync()} bytes)');

  final initialMigrationDir = Directory('supabase/migrations');
  if (!initialMigrationDir.existsSync()) {
    initialMigrationDir.createSync(recursive: true);
  }
  
  final initialMigrationFile = File('supabase/migrations/20260721000000_initial_schema.sql');
  initialMigrationFile.writeAsStringSync(schemaBuffer.toString());
  print('Created supabase/migrations/20260721000000_initial_schema.sql (${initialMigrationFile.lengthSync()} bytes)');

  // 4. Archive Historical Migrations
  print('\nArchiving historical migrations...');
  for (final file in files) {
    final name = p.basename(file.path);
    // Copy to archive
    final dest = File(p.join(archiveDir.path, name));
    dest.writeAsBytesSync(file.readAsBytesSync());
    // Delete original from migrations folder
    file.deleteSync();
  }
  print('Successfully moved all migrations to migrations_archive/');

  // Put initial schema migration back in the migrations folder
  initialMigrationFile.writeAsStringSync(schemaBuffer.toString());

  // 5. Generate Seeds
  final seedsDir = Directory('supabase/seeds');
  if (!seedsDir.existsSync()) {
    seedsDir.createSync(recursive: true);
  }

  // Create required seed
  final requiredSeedFile = File('supabase/seeds/seed_required.sql');
  final masterSeedSource = File('supabase/migrations_archive/SEED_MASTER_DATA.sql');
  if (masterSeedSource.existsSync()) {
    requiredSeedFile.writeAsStringSync(masterSeedSource.readAsStringSync());
    print('Created seeds/seed_required.sql from SEED_MASTER_DATA.sql');
  } else {
    // Fallback if not found
    requiredSeedFile.writeAsStringSync('-- Required seeds go here');
    print('Created blank seeds/seed_required.sql');
  }

  // Create demo seed
  final demoSeedFile = File('supabase/seeds/seed_demo.sql');
  final demoSeedBuffer = StringBuffer();
  demoSeedBuffer.writeln('-- ============================================================');
  demoSeedBuffer.writeln('-- Fruity Farms ERP - Demo Seeding Data');
  demoSeedBuffer.writeln('-- ============================================================');
  demoSeedBuffer.writeln('BEGIN;');
  demoSeedBuffer.writeln();

  for (final file in seedFiles) {
    final name = p.basename(file.path);
    if (name.contains('SEED_MASTER_DATA') || name.contains('required')) continue;
    demoSeedBuffer.writeln('-- ==========================================');
    demoSeedBuffer.writeln('-- Demo Data from: $name');
    demoSeedBuffer.writeln('-- ==========================================');
    demoSeedBuffer.writeln(file.readAsStringSync());
    demoSeedBuffer.writeln();
  }
  demoSeedBuffer.writeln('COMMIT;');
  demoSeedFile.writeAsStringSync(demoSeedBuffer.toString());
  print('Created seeds/seed_demo.sql (${demoSeedFile.lengthSync()} bytes)');

  // 6. Generate Runtime Wipe Script
  final scriptsDir = Directory('supabase/scripts');
  if (!scriptsDir.existsSync()) {
    scriptsDir.createSync(recursive: true);
  }
  final wipeFile = File('supabase/scripts/wipe_runtime.sql');
  final originalWipeSource = File('supabase/migrations_archive/WIPE_RUNTIME_DATA.sql');
  if (originalWipeSource.existsSync()) {
    wipeFile.writeAsStringSync(originalWipeSource.readAsStringSync());
    print('Created scripts/wipe_runtime.sql from WIPE_RUNTIME_DATA.sql');
  } else {
    wipeFile.writeAsStringSync('-- Wipe runtime data');
    print('Created blank scripts/wipe_runtime.sql');
  }

  print('\n=== Refactoring completed successfully! ===');
}

int _getMigrationNumber(String filename) {
  final match = RegExp(r'^(\d+)').firstMatch(filename);
  if (match != null) {
    return int.parse(match.group(1)!);
  }
  return 999999; // Non-migration scripts sorted last
}
