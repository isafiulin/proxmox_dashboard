import 'dart:async';
import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class IpmiClient {
  IpmiClient({required this.logger});

  final AppLogger logger;

  Future<Map<String, Object?>> inventory(
    Source source,
    String credential,
  ) async {
    final mc = await _run(source, credential, const <String>['mc', 'info']);
    final chassis =
        await _run(source, credential, const <String>['chassis', 'status']);
    final sdr = await _run(source, credential, const <String>['sdr', 'elist']);
    final sel = await _run(source, credential, const <String>['sel', 'elist']);
    final fru = await _run(source, credential, const <String>['fru']);
    final poh = await _runOptional(
      source,
      credential,
      const <String>['chassis', 'poh'],
    );
    final lan = await _runOptional(
      source,
      credential,
      const <String>['lan', 'print', '1'],
    );
    return parseIpmiInventory(
      mcOutput: mc,
      chassisOutput: chassis,
      sdrOutput: sdr,
      selOutput: sel,
      fruOutput: fru,
      pohOutput: poh,
      lanOutput: lan,
    );
  }

  Future<String> controllerInfo(Source source, String credential) =>
      _run(source, credential, const <String>['mc', 'info']);

  Future<String> _run(
    Source source,
    String credential,
    List<String> command,
  ) async {
    final uri = Uri.parse(source.baseUrl);
    final separator = credential.indexOf(':');
    if (uri.scheme != 'ipmi' ||
        uri.host.isEmpty ||
        separator < 1 ||
        separator == credential.length - 1) {
      throw const IpmiException('invalid_ipmi_configuration');
    }
    final username = credential.substring(0, separator);
    final password = credential.substring(separator + 1);
    final stopwatch = Stopwatch()..start();
    final result = await Process.run(
      'ipmitool',
      <String>[
        '-I',
        'lanplus',
        '-H',
        uri.host,
        if (uri.hasPort) ...<String>['-p', '${uri.port}'],
        '-U',
        username,
        '-E',
        ...command,
      ],
      environment: <String, String>{'IPMI_PASSWORD': password},
    ).timeout(const Duration(seconds: 35));
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString().trim();
    if (result.exitCode != 0) {
      logger.warning('integration.ipmi_error', <String, Object?>{
        'sourceId': source.id,
        'command': command.join(' '),
        'exitCode': result.exitCode,
        'durationMs': stopwatch.elapsedMilliseconds,
        'stderr': stderr,
      });
      throw IpmiException(stderr.isEmpty ? 'ipmi_command_failed' : stderr);
    }
    logger.info('integration.ipmi_request', <String, Object?>{
      'sourceId': source.id,
      'command': command.join(' '),
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    return stdout;
  }

  Future<String> _runOptional(
    Source source,
    String credential,
    List<String> command,
  ) async {
    try {
      return await _run(source, credential, command);
    } on Object catch (error) {
      logger.warning('integration.ipmi_optional_skipped', <String, Object?>{
        'sourceId': source.id,
        'command': command.join(' '),
        'error': error.toString(),
      });
      return '';
    }
  }
}

Map<String, Object?> parseIpmiInventory({
  required String mcOutput,
  required String chassisOutput,
  required String sdrOutput,
  required String selOutput,
  required String fruOutput,
  String pohOutput = '',
  String lanOutput = '',
}) {
  final mc = _keyValues(mcOutput);
  final chassis = _keyValues(chassisOutput);
  final sensors = _parseSdr(sdrOutput);
  final lan = _keyValues(lanOutput);
  final temperatures = <Map<String, Object?>>[];
  final fans = <Map<String, Object?>>[];
  final discreteSensors = <Map<String, Object?>>[];
  final thresholdSensors = <Map<String, Object?>>[];
  for (final sensor in sensors) {
    final status = sensor['Status'];
    if (status is Map && status['State'] == 'Absent') continue;
    final reading = sensor['reading']?.toString() ?? '';
    final units = sensor['ReadingUnits']?.toString() ?? '';
    if (reading.toLowerCase().contains('degrees c') ||
        sensor['Name'].toString().toLowerCase().contains('temp')) {
      temperatures.add(<String, Object?>{
        ...sensor,
        'ReadingCelsius': _number(reading),
      });
    } else if (units == 'RPM' || reading.toUpperCase().contains('RPM')) {
      fans.add(<String, Object?>{
        ...sensor,
        'Reading': _number(reading),
      });
    } else if (_number(reading) != null) {
      thresholdSensors.add(<String, Object?>{
        ...sensor,
        'ReadingValue': _decimal(reading),
      });
    } else {
      discreteSensors.add(sensor);
    }
  }
  final systemHealth = _systemHealth(chassis);
  final systems = <Map<String, Object?>>[
    <String, Object?>{
      'Id': 'system1',
      'Name': mc['Product Name'] ?? 'IPMI managed server',
      'Manufacturer': mc['Manufacturer Name'],
      'Model': mc['Product Name'],
      'SerialNumber': _firstFruValue(fruOutput, 'Product Serial'),
      'PowerState': _isTrue(chassis['System Power']) ? 'On' : 'Off',
      'Status': <String, Object?>{
        'Health': systemHealth,
        'State': 'Enabled',
      },
    },
  ];
  final healthIssues = <Map<String, Object?>>[];
  if (systemHealth != 'OK') {
    healthIssues.add(<String, Object?>{
      'resourceType': 'system',
      'resourceId': 'system1',
      'name': mc['Product Name'],
      'health': systemHealth,
      'state': 'Enabled',
    });
  }
  for (final sensor in sensors) {
    final status = sensor['Status'];
    final health = status is Map ? status['Health']?.toString() : null;
    if (health != null && health != 'OK') {
      healthIssues.add(<String, Object?>{
        'resourceType': 'sensor',
        'resourceId': sensor['Id'],
        'name': sensor['Name'],
        'health': health,
        'state': status is Map ? status['State'] : null,
      });
    }
  }
  final fruRows = _parseFru(fruOutput);
  final firmware = <Map<String, Object?>>[
    <String, Object?>{
      'Id': 'bmc',
      'Name': 'BMC firmware',
      'Version': mc['Firmware Revision'],
      'Status': const <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
    },
  ];

  return <String, Object?>{
    'identity': <String, Object?>{
      'manufacturer': mc['Manufacturer Name'],
      'model': mc['Product Name'],
      'serialNumber': _firstFruValue(fruOutput, 'Product Serial'),
      'controller': 'ipmi',
      'ipmiVersion': mc['IPMI Version'],
    },
    'systems': systems,
    'processors': const <Map<String, Object?>>[],
    'memory': const <Map<String, Object?>>[],
    'chassis': <Map<String, Object?>>[
      <String, Object?>{
        'Id': 'chassis1',
        'Name': 'Chassis',
        'Intrusion': chassis['Chassis Intrusion'],
        'DriveFault': chassis['Drive Fault'],
        'CoolingFanFault': chassis['Cooling/Fan Fault'],
        'PowerOnHours': _powerOnHours(pohOutput),
        'Status': <String, Object?>{
          'Health': systemHealth,
          'State': 'Enabled',
        },
      },
    ],
    'managers': <Map<String, Object?>>[
      <String, Object?>{
        'Id': 'bmc',
        'Name': mc['Manufacturer Name'] ?? 'BMC',
        'Model': mc['Product Name'],
        'FirmwareVersion': mc['Firmware Revision'],
        'IPMIVersion': mc['IPMI Version'],
        'Status': const <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
      },
    ],
    'thermal': const <Map<String, Object?>>[],
    'temperatures': temperatures,
    'fans': fans,
    'power': const <Map<String, Object?>>[],
    'powerControl': <Map<String, Object?>>[
      <String, Object?>{
        'Name': 'Server power',
        'PowerState': _isTrue(chassis['System Power']) ? 'On' : 'Off',
      },
    ],
    'powerSupplies': const <Map<String, Object?>>[],
    'storage': const <Map<String, Object?>>[],
    'storageControllers': const <Map<String, Object?>>[],
    'volumes': const <Map<String, Object?>>[],
    'drives': const <Map<String, Object?>>[],
    'ethernetInterfaces':
        lan['IP Address'] == null && lan['MAC Address'] == null
            ? const <Map<String, Object?>>[]
            : <Map<String, Object?>>[
                <String, Object?>{
                  'Id': 'bmc-lan1',
                  'Name': 'BMC LAN 1',
                  'MACAddress': lan['MAC Address'],
                  'IPv4Address': lan['IP Address'],
                  'AddressSource': lan['IP Address Source'],
                  'SubnetMask': lan['Subnet Mask'],
                  'Gateway': lan['Default Gateway IP'],
                  'Status': const <String, Object?>{
                    'Health': 'OK',
                    'State': 'Enabled',
                  },
                },
              ],
    'networkInterfaces': const <Map<String, Object?>>[],
    'networkAdapters': const <Map<String, Object?>>[],
    'boards': fruRows,
    'discreteSensors': discreteSensors,
    'thresholdSensors': thresholdSensors,
    'firmware': firmware,
    'logServices': const <Map<String, Object?>>[],
    'logEntries': _parseSel(selOutput),
    'healthIssues': healthIssues,
    'errors': const <Map<String, Object?>>[],
  };
}

Map<String, String> _keyValues(String output) {
  final result = <String, String>{};
  for (final line in output.split('\n')) {
    final separator = line.indexOf(':');
    if (separator < 1) continue;
    result[line.substring(0, separator).trim()] =
        line.substring(separator + 1).trim();
  }
  return result;
}

List<Map<String, Object?>> _parseSdr(String output) {
  final rows = <Map<String, Object?>>[];
  for (final line in output.split('\n')) {
    final columns = line.split('|').map((item) => item.trim()).toList();
    if (columns.length < 4) continue;
    final name = columns[0];
    final state = columns[2].toLowerCase();
    final reading = columns.length > 4 ? columns.sublist(4).join(' | ') : '';
    final unavailable = state == 'ns' || reading.toLowerCase() == 'no reading';
    final health = unavailable || state == 'ok'
        ? 'OK'
        : state.contains('cr') || state.contains('nr')
            ? 'Critical'
            : 'Warning';
    rows.add(<String, Object?>{
      'Id': columns[1],
      'Name': name,
      'SensorNumber': columns[1],
      'Entity': columns[3],
      'reading': reading,
      'ReadingUnits': _readingUnits(reading),
      'RawState': state,
      'Status': <String, Object?>{
        'Health': health,
        'State': unavailable ? 'Absent' : 'Enabled',
      },
    });
  }
  return rows;
}

List<Map<String, Object?>> _parseSel(String output) {
  if (output.toLowerCase().contains('sel has no entries')) {
    return <Map<String, Object?>>[];
  }
  final rows = <Map<String, Object?>>[];
  for (final line in output.split('\n')) {
    final columns = line.split('|').map((item) => item.trim()).toList();
    if (columns.length < 4) continue;
    final message = columns.skip(3).join(' | ');
    final text = message.toLowerCase();
    final severity = text.contains('critical') ||
            text.contains('failure') ||
            text.contains('non-recoverable')
        ? 'Critical'
        : text.contains('warning') || text.contains('non-critical')
            ? 'Warning'
            : 'OK';
    rows.add(<String, Object?>{
      'Id': columns[0],
      'Created': _ipmiDateTime(columns[1], columns[2]),
      'Severity': severity,
      'normalizedSeverity': severity,
      'Message': message,
      'MessageId': 'IPMI.SEL.${columns[0]}',
    });
  }
  rows.sort((left, right) => (right['Created']?.toString() ?? '')
      .compareTo(left['Created']?.toString() ?? ''));
  return rows;
}

List<Map<String, Object?>> _parseFru(String output) {
  final rows = <Map<String, Object?>>[];
  Map<String, Object?>? current;
  for (final line in output.split('\n')) {
    final separator = line.indexOf(':');
    if (separator < 1) continue;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    if (key == 'FRU Device Description') {
      current = <String, Object?>{
        'Id': 'fru${rows.length + 1}',
        'Name': value,
        'Status': const <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
      };
      rows.add(current);
    } else if (current != null && value.isNotEmpty) {
      current[key.replaceAll(' ', '')] = value;
      if (key == 'Board Mfg') current['Manufacturer'] = value;
      if (key == 'Board Product' || key == 'Product Name') {
        current['Model'] = value;
      }
    }
  }
  return rows;
}

String? _firstFruValue(String output, String key) {
  final match =
      RegExp('^\\s*${RegExp.escape(key)}\\s*:\\s*(.+)\\s*\$', multiLine: true)
          .firstMatch(output);
  final value = match?.group(1)?.trim();
  return value == null || value.isEmpty ? null : value;
}

String _systemHealth(Map<String, String> chassis) {
  if (_isTrue(chassis['Main Power Fault']) ||
      _isTrue(chassis['Power Control Fault'])) {
    return 'Critical';
  }
  if (_isTrue(chassis['Power Overload']) ||
      _isTrue(chassis['Drive Fault']) ||
      _isTrue(chassis['Cooling/Fan Fault'])) {
    return 'Warning';
  }
  return 'OK';
}

bool _isTrue(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == 'true' || normalized == 'on' || normalized == 'active';
}

String? _readingUnits(String reading) {
  final lower = reading.toLowerCase();
  if (lower.contains('degrees c')) return 'Celsius';
  if (lower.contains('rpm')) return 'RPM';
  if (lower.contains('volts')) return 'Volts';
  return null;
}

int? _number(String value) {
  final match = RegExp(r'-?\d+').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(0)!);
}

double? _decimal(String value) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
  return match == null ? null : double.tryParse(match.group(0)!);
}

int? _powerOnHours(String output) {
  final match = RegExp(r'(\d+)\s+days?,\s*(\d+)\s+hours?')
      .firstMatch(output.toLowerCase());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 24 + int.parse(match.group(2)!);
}

String _ipmiDateTime(String date, String time) {
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(date);
  if (match == null) return '$date $time'.trim();
  return '${match.group(3)}-${match.group(1)!.padLeft(2, '0')}-${match.group(2)!.padLeft(2, '0')}T$time';
}

class IpmiException implements Exception {
  const IpmiException(this.message);

  final String message;

  @override
  String toString() => message;
}
