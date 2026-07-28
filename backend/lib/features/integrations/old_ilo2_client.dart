import 'dart:async';
import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class OldIlo2Client {
  OldIlo2Client({required this.logger});

  final AppLogger logger;

  Future<Map<String, Object?>> inventory(
    Source source,
    String credential,
  ) async {
    final systemOutput = await _run(source, credential, 'show /system1 -all');
    final logOutput = await _run(source, credential, 'show /system1/log1 -all');
    return parseOldIlo2Inventory(systemOutput, logOutput);
  }

  Future<String> systemSummary(Source source, String credential) =>
      _run(source, credential, 'show /system1');

  Future<String> _run(
    Source source,
    String credential,
    String command,
  ) async {
    final uri = Uri.parse(source.baseUrl);
    final separator = credential.indexOf(':');
    if (uri.scheme != 'ssh' ||
        uri.host.isEmpty ||
        separator < 1 ||
        separator == credential.length - 1) {
      throw OldIlo2Exception('invalid_old_ilo2_configuration');
    }
    final username = credential.substring(0, separator);
    final password = credential.substring(separator + 1);
    final port = uri.hasPort ? uri.port : 22;
    final packagedAskpass = File('/app/bin/ssh_askpass.sh');
    final askpassPath = packagedAskpass.existsSync()
        ? packagedAskpass.path
        : '${Directory.current.path}/bin/ssh_askpass.sh';
    final stopwatch = Stopwatch()..start();
    // ponytail: iLO 2 only offers this fixed legacy SSH suite. Keep it scoped
    // to this adapter; replacing the controller is the security upgrade path.
    final result = await Process.run(
      'ssh',
      <String>[
        '-T',
        '-p',
        '$port',
        '-o',
        'ConnectTimeout=15',
        '-o',
        'ConnectionAttempts=1',
        '-o',
        'StrictHostKeyChecking=accept-new',
        '-o',
        'KexAlgorithms=diffie-hellman-group1-sha1',
        '-o',
        'HostKeyAlgorithms=ssh-rsa',
        '-o',
        'Ciphers=aes128-cbc',
        '-o',
        'MACs=hmac-sha1',
        '-o',
        'PubkeyAuthentication=no',
        '-o',
        'PreferredAuthentications=password',
        '$username@${uri.host}',
        command,
      ],
      environment: <String, String>{
        'DISPLAY': ':0',
        'SSH_ASKPASS_REQUIRE': 'force',
        'SSH_ASKPASS': askpassPath,
        'OLD_ILO2_PASSWORD': password,
      },
    ).timeout(const Duration(seconds: 45));
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString().trim();
    if (result.exitCode != 0 ||
        !stdout.contains('status_tag=COMMAND COMPLETED')) {
      logger.warning('integration.old_ilo2_error', <String, Object?>{
        'sourceId': source.id,
        'command': command,
        'exitCode': result.exitCode,
        'durationMs': stopwatch.elapsedMilliseconds,
        'stderr': stderr,
      });
      throw OldIlo2Exception(
        stderr.isEmpty ? 'old_ilo2_command_failed' : stderr,
      );
    }
    logger.info('integration.old_ilo2_request', <String, Object?>{
      'sourceId': source.id,
      'command': command,
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    return stdout;
  }
}

Map<String, Object?> parseOldIlo2Inventory(
  String systemOutput,
  String logOutput,
) {
  final resources = _parseClpResources(systemOutput);
  final root = resources['/system1'] ?? <String, String>{};
  final systems = <Map<String, Object?>>[
    <String, Object?>{
      'Id': 'system1',
      'Name': root['name'] ?? 'HP ProLiant',
      'Manufacturer': 'HPE',
      'Model': root['name'],
      'PowerState': _powerState(root['enabledstate']),
      'Status': _status(root),
      'PresentPowerWatts': _number(root['oemhp_PresentPower']),
      'AveragePowerWatts': _number(root['oemhp_AveragePower']),
      'MaxPowerWatts': _number(root['oemhp_MaxPower']),
      'MinPowerWatts': _number(root['oemhp_MinPower']),
    },
  ];
  final processors = _rows(resources, '/system1/cpu', (path, row) {
    return <String, Object?>{
      'Id': _leaf(path),
      'Name': row['name'] ?? _leaf(path),
      'Socket': _leaf(path),
      'Model': row['model'],
      'MaxSpeedMHz': _number(row['speed']),
      'TotalCores': _number(row['cores']),
      'Status': _status(row),
      ..._rawScalars(row),
    };
  });
  final memory = _rows(resources, '/system1/memory', (path, row) {
    return <String, Object?>{
      'Id': _leaf(path),
      'Name': row['name'] ?? _leaf(path),
      'DeviceLocator': _leaf(path),
      'CapacityMiB': _memoryMiB(row),
      'OperatingSpeedMhz': _number(row['speed']),
      'Status': _status(row),
      ..._rawScalars(row),
    };
  });
  final fans = _rows(resources, '/system1/fan', (path, row) {
    return <String, Object?>{
      'Id': _leaf(path),
      'Name': row['name'] ?? _leaf(path),
      'Reading': _number(row['speed'] ?? row['reading']),
      'ReadingUnits': row['units'],
      'Status': _status(row),
      ..._rawScalars(row),
    };
  });
  final temperatures = _rows(resources, '/system1/sensor', (path, row) {
    return <String, Object?>{
      'Id': _leaf(path),
      'Name': row['name'] ?? _leaf(path),
      'ReadingCelsius': _number(
        row['currentreading'] ?? row['reading'] ?? row['value'],
      ),
      'Status': _status(row),
      ..._rawScalars(row),
    };
  });
  final powerSupplies = _rows(resources, '/system1/powersupply', (path, row) {
    return <String, Object?>{
      'Id': _leaf(path),
      'Name': row['name'] ?? _leaf(path),
      'Model': row['model'],
      'PowerCapacityWatts': _number(row['capacity'] ?? row['maxpower']),
      'Status': _status(row),
      ..._rawScalars(row),
    };
  });
  final firmwareRows = _rows(resources, '/system1/firmware', (path, row) {
    return <String, Object?>{
      'Id': _leaf(path),
      'Name': row['name'] ?? 'System ROM',
      'Version': row['version'],
      'ReleaseDate': row['date'],
      'Status': _status(row),
      ..._rawScalars(row),
    };
  });
  final managerMatch = RegExp(
    r'iLO 2 Advanced\s+([^\s]+)',
    caseSensitive: false,
  ).firstMatch(systemOutput);
  final managers = <Map<String, Object?>>[
    <String, Object?>{
      'Id': 'ilo2',
      'Name': 'HP iLO 2',
      'Model': 'iLO 2 Advanced',
      'FirmwareVersion': managerMatch?.group(1),
      'Status': const <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
    },
  ];
  final logEntries = _parseClpResources(logOutput)
      .entries
      .where((entry) => entry.key.startsWith('/system1/log1/record'))
      .map((entry) => _logEntry(entry.key, entry.value))
      .toList()
    ..sort((left, right) => (right['Created']?.toString() ?? '')
        .compareTo(left['Created']?.toString() ?? ''));
  final healthResources = <String, List<Map<String, Object?>>>{
    'system': systems,
    'processor': processors,
    'memory': memory,
    'temperature': temperatures,
    'fan': fans,
    'power_supply': powerSupplies,
  };
  final healthIssues = <Map<String, Object?>>[];
  for (final entry in healthResources.entries) {
    for (final row in entry.value) {
      final status = row['Status'];
      final health = status is Map ? status['Health']?.toString() ?? '' : '';
      if (health.isNotEmpty && health != 'OK') {
        healthIssues.add(<String, Object?>{
          'resourceType': entry.key,
          'resourceId': row['Id'],
          'name': row['Name'],
          'health': health,
          'state': status is Map ? status['State'] : null,
        });
      }
    }
  }

  return <String, Object?>{
    'identity': <String, Object?>{
      'manufacturer': 'HPE',
      'model': root['name'],
      'serialNumber': root['serialnumber'] ?? root['number'],
      'controller': 'old_ilo2',
    },
    'systems': systems,
    'processors': processors,
    'memory': memory,
    'chassis': const <Map<String, Object?>>[],
    'managers': managers,
    'thermal': const <Map<String, Object?>>[],
    'temperatures': temperatures,
    'fans': fans,
    'power': const <Map<String, Object?>>[],
    'powerControl': <Map<String, Object?>>[
      <String, Object?>{
        'Name': 'Server power',
        'PowerConsumedWatts': _number(root['oemhp_PresentPower']),
        'PowerState': _powerState(root['enabledstate']),
      },
    ],
    'powerSupplies': powerSupplies,
    'storage': const <Map<String, Object?>>[],
    'storageControllers': const <Map<String, Object?>>[],
    'volumes': const <Map<String, Object?>>[],
    'drives': _rows(
        resources,
        '/system1/drives',
        (path, row) => <String, Object?>{
              'Id': _leaf(path),
              'Name': row['name'] ?? _leaf(path),
              'Status': _status(row),
              ..._rawScalars(row),
            }),
    'ethernetInterfaces': const <Map<String, Object?>>[],
    'networkInterfaces': const <Map<String, Object?>>[],
    'networkAdapters': const <Map<String, Object?>>[],
    'boards': const <Map<String, Object?>>[],
    'discreteSensors': const <Map<String, Object?>>[],
    'thresholdSensors': temperatures,
    'firmware': firmwareRows,
    'logServices': const <Map<String, Object?>>[],
    'logEntries': logEntries,
    'healthIssues': healthIssues,
    'errors': const <Map<String, Object?>>[],
  };
}

Map<String, Map<String, String>> _parseClpResources(String output) {
  final result = <String, Map<String, String>>{};
  String? rootPath;
  String? path;
  String? lastKey;
  var section = '';
  for (final rawLine in output.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    final trimmed = line.trim();
    if (trimmed.startsWith('/') && !trimmed.contains(' ')) {
      rootPath = trimmed;
      path = trimmed;
      result.putIfAbsent(path, () => <String, String>{});
      section = '';
      lastKey = null;
      continue;
    }
    if (trimmed == 'Properties') {
      section = 'properties';
      lastKey = null;
      continue;
    }
    if (trimmed == 'Targets') {
      section = 'targets';
      lastKey = null;
      continue;
    }
    if (trimmed == 'Verbs') {
      section = 'verbs';
      lastKey = null;
      continue;
    }
    if (section != 'properties' && section != 'targets' && rootPath != null) {
      final nestedPath = _nestedClpPath(rootPath, trimmed);
      if (nestedPath != null) {
        path = nestedPath;
        result.putIfAbsent(path, () => <String, String>{});
        section = '';
        lastKey = null;
        continue;
      }
    }
    if (section != 'properties' || path == null || trimmed.isEmpty) continue;
    final separator = trimmed.indexOf('=');
    if (separator > 0) {
      lastKey = trimmed.substring(0, separator);
      result[path]![lastKey] = trimmed.substring(separator + 1).trim();
    } else if (lastKey != null) {
      result[path]![lastKey] = '${result[path]![lastKey]} $trimmed'.trim();
    }
  }
  return result;
}

String? _nestedClpPath(String rootPath, String token) {
  // ponytail: iLO 2 has no schema endpoint; this is the finite set of useful
  // direct CLP targets. Add a target here if another firmware exposes one.
  if (rootPath == '/system1/log1' && RegExp(r'^record\d+$').hasMatch(token)) {
    return '$rootPath/$token';
  }
  if (rootPath != '/system1') return null;
  if (token == 'drives' ||
      RegExp(
        r'^(?:firmware|bootconfig|log|led|oemhp_vsp|cpu|memory|slot|fan|sensor|powersupply)\d+$',
      ).hasMatch(token)) {
    return '$rootPath/$token';
  }
  return null;
}

List<Map<String, Object?>> _rows(
  Map<String, Map<String, String>> resources,
  String prefix,
  Map<String, Object?> Function(String path, Map<String, String> row) convert,
) =>
    resources.entries
        .where((entry) => entry.key.startsWith(prefix))
        .map((entry) => convert(entry.key, entry.value))
        .toList();

Map<String, Object?> _logEntry(String path, Map<String, String> row) {
  final severity = row['severity'] ?? 'Unknown';
  final normalized = switch (severity.toLowerCase()) {
    'critical' => 'Critical',
    'noncritical' || 'warning' => 'Warning',
    _ => 'OK',
  };
  final date = row['date'] ?? '';
  final time = row['time'] ?? '';
  return <String, Object?>{
    'Id': row['number'] ?? _leaf(path),
    'Created': _created(date, time),
    'Severity': severity,
    'normalizedSeverity': normalized,
    'Message': row['description'],
    'MessageId': 'ILO2.IML.${row['number'] ?? _leaf(path)}',
  };
}

String _created(String date, String time) {
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(date);
  if (match == null) return '$date $time'.trim();
  return '${match.group(3)}-${match.group(1)!.padLeft(2, '0')}-${match.group(2)!.padLeft(2, '0')}T${time.padLeft(5, '0')}:00';
}

Map<String, Object?> _status(Map<String, String> row) {
  final raw =
      (row['healthstate'] ?? row['operationalstatus'] ?? row['status'] ?? 'OK')
          .trim();
  final lower = raw.toLowerCase();
  final health = lower == 'ok' || lower == 'normal' || lower == 'enabled'
      ? 'OK'
      : lower.contains('critical') || lower.contains('error')
          ? 'Critical'
          : 'Warning';
  return <String, Object?>{
    'Health': health,
    'State': row['enabledstate'] ?? row['operationalstatus'] ?? raw,
  };
}

Map<String, Object?> _rawScalars(Map<String, String> row) =>
    <String, Object?>{for (final entry in row.entries) entry.key: entry.value};

int? _memoryMiB(Map<String, String> row) {
  final value = row['size'] ?? row['capacity'] ?? row['totalmemory'];
  if (value == null) return null;
  final number = _number(value);
  if (number == null) return null;
  final lower = value.toLowerCase();
  return lower.contains('gb') ? number * 1024 : number;
}

int? _number(String? value) {
  final match = RegExp(r'-?\d+').firstMatch(value ?? '');
  return match == null ? null : int.tryParse(match.group(0)!);
}

String _powerState(String? value) =>
    value?.toLowerCase() == 'enabled' ? 'On' : 'Off';

String _leaf(String path) => path.split('/').last;

class OldIlo2Exception implements Exception {
  const OldIlo2Exception(this.message);

  final String message;

  @override
  String toString() => message;
}
