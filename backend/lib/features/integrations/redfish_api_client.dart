import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class RedfishApiClient {
  RedfishApiClient({required bool allowInsecureTls, required this.logger}) {
    _client
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 2;
    if (allowInsecureTls) {
      _client.badCertificateCallback = (_, __, ___) => true;
    }
  }

  final AppLogger logger;
  final HttpClient _client = HttpClient();
  final Map<String, ({DateTime storedAt, Map<String, Object?> data})>
      _inventoryCache = {};
  final Map<String, Future<Map<String, Object?>>> _activeInventory = {};

  Future<Map<String, Object?>> get(
    Source source,
    String credential,
    String path,
  ) async {
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await _getOnce(source, credential, path);
      } on RedfishApiException catch (error) {
        if (attempt > 0 || error.statusCode != null) {
          rethrow;
        }
        logger.warning('integration.redfish_request_retry', <String, Object?>{
          'sourceId': source.id,
          'path': path,
          'message': error.message,
        });
      }
    }
    throw RedfishApiException(
      'integration_request_failed',
      sourceId: source.id,
      path: path,
    );
  }

  Future<Map<String, Object?>> _getOnce(
    Source source,
    String credential,
    String path,
  ) async {
    final uri = _redfishUri(source.baseUrl, path);
    final stopwatch = Stopwatch()..start();
    try {
      final request =
          await _client.getUrl(uri).timeout(const Duration(seconds: 25));
      request.headers
        ..set(HttpHeaders.authorizationHeader, redfishAuthHeader(credential))
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decoder.bind(response).join();
      final Object? decoded;
      try {
        decoded = body.isEmpty ? <String, Object?>{} : jsonDecode(body);
      } on FormatException {
        throw RedfishApiException(
          'invalid_json_response',
          sourceId: source.id,
          path: path,
          statusCode: response.statusCode,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? decoded['error']?.toString() ?? decoded['message']?.toString()
            : null;
        throw RedfishApiException(
          'HTTP ${response.statusCode}: ${message ?? body}',
          sourceId: source.id,
          path: path,
          statusCode: response.statusCode,
        );
      }
      if (decoded is! Map) {
        throw RedfishApiException(
          'invalid_redfish_payload',
          sourceId: source.id,
          path: path,
          statusCode: response.statusCode,
        );
      }

      logger.info('integration.redfish_request', <String, Object?>{
        'sourceId': source.id,
        'path': path,
        'statusCode': response.statusCode,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      return decoded.cast<String, Object?>();
    } on Object catch (error, stackTrace) {
      if (error is RedfishApiException) {
        rethrow;
      }
      logger.error(
        'integration.redfish_request_error',
        <String, Object?>{
          'sourceId': source.id,
          'path': path,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
        error: error,
        stackTrace: stackTrace,
      );
      throw RedfishApiException(
        'integration_request_failed: $error',
        sourceId: source.id,
        path: path,
      );
    }
  }

  Future<Map<String, Object?>> inventory(
    Source source,
    String credential,
  ) {
    final cacheKey =
        '${source.id}\u0001${source.updatedAt.microsecondsSinceEpoch}';
    final cached = _inventoryCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) <
            const Duration(seconds: 30)) {
      return Future<Map<String, Object?>>.value(cached.data);
    }
    final active = _activeInventory[cacheKey];
    if (active != null) {
      return active;
    }
    final request = _loadInventory(source, credential);
    _activeInventory[cacheKey] = request;
    return request.then((data) {
      _inventoryCache[cacheKey] = (storedAt: DateTime.now(), data: data);
      return data;
    }).whenComplete(() => _activeInventory.remove(cacheKey));
  }

  Future<Map<String, Object?>> _loadInventory(
    Source source,
    String credential,
  ) async {
    final root = await get(source, credential, '/redfish/v1/');
    final errors = <Map<String, Object?>>[];
    final results = await Future.wait(<Future<List<Map<String, Object?>>>>[
      _members(source, credential, root['Systems'], 'systems', errors),
      _members(source, credential, root['Chassis'], 'chassis', errors),
      _members(source, credential, root['Managers'], 'managers', errors),
    ]);
    final systems = results[0];
    final chassis = results[1];
    final managers = results[2];
    final processors = await _collectionsFromParents(
      source,
      credential,
      systems,
      'Processors',
      'processors',
      errors,
    );
    final memory = await _collectionsFromParents(
      source,
      credential,
      systems,
      'Memory',
      'memory',
      errors,
    );
    final storage = await _collectionsFromParents(
      source,
      credential,
      systems,
      'Storage',
      'storage',
      errors,
    );
    final volumes = await _collectionsFromParents(
      source,
      credential,
      storage,
      'Volumes',
      'volumes',
      errors,
    );
    final drives = await _resourcesFromLinks(
      source,
      credential,
      <Object?>[
        for (final item in storage) ...?_asList(item['Drives']),
        for (final item in volumes)
          ...?_asList((item['Links'] as Map?)?['Drives']),
      ],
      'drives',
      errors,
    );
    final ethernetInterfaces = await _collectionsFromParents(
      source,
      credential,
      systems,
      'EthernetInterfaces',
      'ethernet_interfaces',
      errors,
    );
    final networkInterfaces = await _collectionsFromParents(
      source,
      credential,
      systems,
      'NetworkInterfaces',
      'network_interfaces',
      errors,
    );
    final thermal = await _linkedResources(
      source,
      credential,
      chassis,
      'Thermal',
      'thermal',
      errors,
    );
    final power = await _linkedResources(
      source,
      credential,
      chassis,
      'Power',
      'power',
      errors,
    );
    final networkAdapters = await _collectionsFromParents(
      source,
      credential,
      chassis,
      'NetworkAdapters',
      'network_adapters',
      errors,
    );
    final boards = await _collectionsFromDiscoveredLinks(
      source,
      credential,
      chassis,
      'Boards',
      'boards',
      errors,
    );
    final discreteSensors = await _resourcesFromDiscoveredLinks(
      source,
      credential,
      chassis,
      'DiscreteSensors',
      'discrete_sensors',
      errors,
    );
    final thresholdSensors = await _resourcesFromDiscoveredLinks(
      source,
      credential,
      chassis,
      'ThresholdSensors',
      'threshold_sensors',
      errors,
    );
    final updateServices = await _linkedResources(
      source,
      credential,
      <Map<String, Object?>>[root],
      'UpdateService',
      'update_service',
      errors,
    );
    final firmware = await _collectionsFromParents(
      source,
      credential,
      updateServices,
      'FirmwareInventory',
      'firmware',
      errors,
    );
    final logServices = await _collectionsFromParents(
      source,
      credential,
      systems,
      'LogServices',
      'log_services',
      errors,
    );
    final logEntries = await _recentLogEntries(
      source,
      credential,
      logServices,
      errors,
    );
    final temperatures = _nestedRows(thermal, 'Temperatures');
    final fans = _nestedRows(thermal, 'Fans');
    final powerControl = _nestedRows(power, 'PowerControl');
    final powerSupplies = _nestedRows(power, 'PowerSupplies');
    final storageControllers = _nestedRows(storage, 'StorageControllers');
    final discreteSensorRows = _nestedRows(discreteSensors, 'Sensors');
    final thresholdSensorRows = _nestedRows(thresholdSensors, 'Sensors');
    final healthIssues = _healthIssues(<String, List<Map<String, Object?>>>{
      'system': systems,
      'chassis': chassis,
      'manager': managers,
      'processor': processors,
      'memory': memory,
      'storage_controller': storageControllers,
      'volume': volumes,
      'drive': drives,
      'ethernet': ethernetInterfaces,
      'network_adapter': networkAdapters,
      'board': boards,
      'temperature': temperatures,
      'fan': fans,
      'power_supply': powerSupplies,
      'firmware': firmware,
    });

    return <String, Object?>{
      'identity': <String, Object?>{
        'redfishVersion': root['RedfishVersion'],
        'uuid': root['UUID'],
        'manufacturer': systems.firstOrNull?['Manufacturer'],
        'model': systems.firstOrNull?['Model'],
        'serialNumber': systems.firstOrNull?['SerialNumber'],
      },
      'systems': systems,
      'processors': processors,
      'memory': memory,
      'chassis': chassis,
      'managers': managers,
      'thermal': thermal,
      'temperatures': temperatures,
      'fans': fans,
      'power': power,
      'powerControl': powerControl,
      'powerSupplies': powerSupplies,
      'storage': storage,
      'storageControllers': storageControllers,
      'volumes': volumes,
      'drives': drives,
      'ethernetInterfaces': ethernetInterfaces,
      'networkInterfaces': networkInterfaces,
      'networkAdapters': networkAdapters,
      'boards': boards,
      'discreteSensors': discreteSensorRows,
      'thresholdSensors': thresholdSensorRows,
      'firmware': firmware,
      'logServices': logServices,
      'logEntries': logEntries,
      'healthIssues': healthIssues,
      'errors': errors,
    };
  }

  Future<List<Map<String, Object?>>> _members(Source source, String credential,
      Object? link, String operation, List<Map<String, Object?>> errors,
      {int maxPages = 10}) async {
    var nextPath = _odataPath(link);
    if (nextPath == null) {
      return <Map<String, Object?>>[];
    }
    final rows = <Map<String, Object?>>[];
    var page = 0;
    while (nextPath != null && page < maxPages) {
      try {
        final collection = await get(source, credential, nextPath);
        final memberLinks = collection['Members'];
        if (memberLinks is List) {
          rows.addAll(
            await _resourcesFromLinks(
              source,
              credential,
              memberLinks,
              operation,
              errors,
            ),
          );
        }
        nextPath = _stringValue(collection['Members@odata.nextLink']);
        page += 1;
      } on RedfishApiException catch (error) {
        errors.add(_errorRow(operation, error));
        break;
      }
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> _resourcesFromLinks(
    Source source,
    String credential,
    List<Object?> links,
    String operation,
    List<Map<String, Object?>> errors,
  ) async {
    final paths = links.map(_odataPath).whereType<String>().toSet().toList();
    final rows = <Map<String, Object?>>[];
    // ponytail: two-request batches protect older BMCs; make this configurable
    // only if mixed hardware proves one limit cannot serve all controllers.
    for (var offset = 0; offset < paths.length; offset += 2) {
      final batch = paths.skip(offset).take(2);
      final results = await Future.wait(
        batch.map((memberPath) async {
          try {
            return _withOemScalars(
              await get(source, credential, memberPath),
            );
          } on RedfishApiException catch (error) {
            errors.add(_errorRow(operation, error));
            return null;
          }
        }),
      );
      rows.addAll(results.whereType<Map<String, Object?>>());
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> _collectionsFromParents(
    Source source,
    String credential,
    List<Map<String, Object?>> parents,
    String linkName,
    String operation,
    List<Map<String, Object?>> errors,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final parent in parents) {
      rows.addAll(
        await _members(
          source,
          credential,
          parent[linkName],
          operation,
          errors,
        ),
      );
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> _collectionsFromDiscoveredLinks(
    Source source,
    String credential,
    List<Map<String, Object?>> parents,
    String linkName,
    String operation,
    List<Map<String, Object?>> errors,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final parent in parents) {
      rows.addAll(
        await _members(
          source,
          credential,
          _findLink(parent, linkName),
          operation,
          errors,
        ),
      );
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> _resourcesFromDiscoveredLinks(
    Source source,
    String credential,
    List<Map<String, Object?>> parents,
    String linkName,
    String operation,
    List<Map<String, Object?>> errors,
  ) {
    return _resourcesFromLinks(
      source,
      credential,
      parents.map((parent) => _findLink(parent, linkName)).toList(),
      operation,
      errors,
    );
  }

  Future<List<Map<String, Object?>>> _recentLogEntries(
    Source source,
    String credential,
    List<Map<String, Object?>> logServices,
    List<Map<String, Object?>> errors,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final service in logServices) {
      // ponytail: Huawei exposes 668+ entries as individual requests. The
      // newest 32 are enough for polling; persisted snapshots provide history.
      final entries = await _members(
        source,
        credential,
        service['Entries'],
        'log_entries',
        errors,
        maxPages: 1,
      );
      rows.addAll(entries.map(_normalizeLogEntry));
    }
    rows.sort(
      (left, right) => (right['Created']?.toString() ?? '').compareTo(
        left['Created']?.toString() ?? '',
      ),
    );
    return rows;
  }

  Future<List<Map<String, Object?>>> _linkedResources(
    Source source,
    String credential,
    List<Map<String, Object?>> parents,
    String linkName,
    String operation,
    List<Map<String, Object?>> errors,
  ) async {
    final rows = await Future.wait(
      parents.map((parent) async {
        final path = _odataPath(parent[linkName]);
        if (path == null) {
          return null;
        }
        try {
          return await get(source, credential, path);
        } on RedfishApiException catch (error) {
          errors.add(_errorRow(operation, error));
          return null;
        }
      }),
    );
    return rows.whereType<Map<String, Object?>>().toList();
  }
}

String redfishAuthHeader(String credential) {
  if (!isValidRedfishCredential(credential)) {
    throw const RedfishApiException('invalid_redfish_credentials');
  }
  return 'Basic ${base64Encode(utf8.encode(credential))}';
}

bool isValidRedfishCredential(String credential) {
  final separator = credential.indexOf(':');
  return separator > 0 && separator < credential.length - 1;
}

String? _odataPath(Object? value) {
  if (value is Map) {
    final path = value['@odata.id']?.toString().trim() ?? '';
    return path.isEmpty ? null : path;
  }
  return null;
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

List<Object?>? _asList(Object? value) => value is List ? value : null;

Object? _findLink(Object? value, String key) {
  if (value is Map) {
    if (value.containsKey(key) && _odataPath(value[key]) != null) {
      return value[key];
    }
    for (final child in value.values) {
      final found = _findLink(child, key);
      if (found != null) {
        return found;
      }
    }
  } else if (value is List) {
    for (final child in value) {
      final found = _findLink(child, key);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

List<Map<String, Object?>> _nestedRows(
  List<Map<String, Object?>> parents,
  String key,
) {
  final rows = <Map<String, Object?>>[];
  for (final parent in parents) {
    final children = parent[key];
    if (children is! List) {
      continue;
    }
    for (final child in children.whereType<Map>()) {
      rows.add(<String, Object?>{
        'parentId': parent['Id'],
        ..._withOemScalars(child.cast<String, Object?>()),
      });
    }
  }
  return rows;
}

Map<String, Object?> _withOemScalars(Map<String, Object?> row) {
  final result = <String, Object?>{...row};
  final oem = row['Oem'];
  if (oem is! Map) {
    return result;
  }
  for (final vendorData in oem.values.whereType<Map>()) {
    for (final entry in vendorData.entries) {
      final value = entry.value;
      if (value is String || value is num || value is bool) {
        final key = entry.key.toString();
        if (result[key] == null) {
          result[key] = value;
        }
      }
    }
  }
  return result;
}

List<Map<String, Object?>> _healthIssues(
  Map<String, List<Map<String, Object?>>> resources,
) {
  final issues = <Map<String, Object?>>[];
  for (final entry in resources.entries) {
    for (final resource in entry.value) {
      final status = resource['Status'];
      if (status is! Map) {
        continue;
      }
      final health = status['Health']?.toString().trim() ??
          status['HealthRollup']?.toString().trim() ??
          '';
      if (health.isEmpty ||
          health.toLowerCase() == 'ok' ||
          health.toLowerCase() == 'normal') {
        continue;
      }
      issues.add(<String, Object?>{
        'resourceType': entry.key,
        'resourceId': resource['Id'] ?? resource['MemberId'],
        'name': resource['Name'] ?? resource['DeviceLocator'],
        'health': health,
        'state': status['State'],
      });
    }
  }
  return issues;
}

Map<String, Object?> _normalizeLogEntry(Map<String, Object?> entry) {
  final severity = entry['Severity']?.toString().trim() ?? '';
  final messageId = entry['MessageId']?.toString().toLowerCase() ?? '';
  final message = entry['Message']?.toString().toLowerCase() ?? '';
  var normalizedSeverity = severity;
  if (normalizedSeverity.isEmpty || normalizedSeverity.toLowerCase() == 'ok') {
    final text = '$messageId $message';
    if (text.contains('critical') ||
        text.contains('inputlost') ||
        text.contains('out-of-range')) {
      normalizedSeverity = 'Critical';
    } else if (text.contains('fail') ||
        text.contains('error') ||
        text.contains('lost') ||
        text.contains('warning')) {
      normalizedSeverity = 'Warning';
    } else {
      normalizedSeverity = 'OK';
    }
  }
  return <String, Object?>{
    ...entry,
    'normalizedSeverity': normalizedSeverity,
  };
}

Map<String, Object?> _errorRow(
  String operation,
  RedfishApiException error,
) =>
    <String, Object?>{
      'operation': operation,
      'path': error.path,
      'statusCode': error.statusCode,
      'message': error.message,
    };

Uri _redfishUri(String baseUrl, String path) {
  final base = Uri.parse(baseUrl);
  final relative = Uri.parse(path);
  return base.replace(path: relative.path, query: relative.query);
}

class RedfishApiException implements Exception {
  const RedfishApiException(
    this.message, {
    this.sourceId,
    this.path,
    this.statusCode,
  });

  final String message;
  final String? sourceId;
  final String? path;
  final int? statusCode;

  @override
  String toString() => message;
}
