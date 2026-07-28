import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/features/integrations/redfish_api_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/sources/source_connection_tester.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Source source;
  final requestedPaths = <String>[];
  final requestedUris = <Uri>[];

  setUp(() async {
    requestedPaths.clear();
    requestedUris.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    source = Source(
      id: 'redfish-1',
      name: 'Huawei iBMC',
      type: 'redfish',
      baseUrl: 'http://${server.address.host}:${server.port}',
      credential: const EncryptedSecret(ciphertext: '', nonce: '', mac: ''),
      status: 'new',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      requestedUris.add(request.uri);
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          redfishAuthHeader('monitor:password:with-colon')) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final body = _responses[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('discovers standard Redfish inventory and follows resource links',
      () async {
    final client = RedfishApiClient(
      allowInsecureTls: false,
      logger: const AppLogger(enabled: false),
    );

    final inventory = await client.inventory(
      source,
      'monitor:password:with-colon',
    );

    expect(inventory['identity'], containsPair('model', '2288H V5'));
    expect(inventory['systems'], hasLength(1));
    expect(inventory['chassis'], hasLength(1));
    expect(inventory['managers'], hasLength(1));
    expect(inventory['thermal'], hasLength(1));
    expect(inventory['power'], hasLength(1));
    expect(inventory['processors'], hasLength(1));
    expect(inventory['memory'], hasLength(1));
    expect(inventory['storageControllers'], hasLength(1));
    expect(inventory['volumes'], hasLength(1));
    expect(inventory['drives'], hasLength(1));
    expect(inventory['firmware'], hasLength(1));
    expect(
      (inventory['logEntries'] as List).single,
      containsPair('normalizedSeverity', 'Warning'),
    );
    expect(
      (inventory['healthIssues'] as List).single,
      containsPair('name', 'PS2'),
    );
    expect(inventory['errors'], isEmpty);
    expect(requestedPaths, contains('/redfish/v1/Chassis/1/Thermal'));
    expect(
      requestedUris.firstWhere((uri) => uri.path == '/redfish/v1/').hasQuery,
      isFalse,
    );

    await client.inventory(source, 'monitor:password:with-colon');
    expect(
      requestedPaths.where((path) => path == '/redfish/v1/'),
      hasLength(1),
    );
  });

  test('rejects malformed basic credentials before making a request', () {
    expect(
      () => redfishAuthHeader('missing-separator'),
      throwsA(isA<RedfishApiException>()),
    );
  });

  test('connection test validates the Redfish service root', () async {
    final client = RedfishApiClient(
      allowInsecureTls: false,
      logger: const AppLogger(enabled: false),
    );
    final result = await SourceConnectionTester(
      allowInsecureTls: false,
      redfishClient: client,
    ).test(source, 'monitor:password:with-colon');

    expect(result.ok, isTrue);
    expect(result.status, 'ok');
    expect(result.message, contains('1.0.2'));
  });
}

const Map<String, Map<String, Object?>> _responses =
    <String, Map<String, Object?>>{
  '/redfish/v1/': <String, Object?>{
    'RedfishVersion': '1.0.2',
    'UUID': 'server-uuid',
    'Systems': <String, Object?>{'@odata.id': '/redfish/v1/Systems'},
    'Chassis': <String, Object?>{'@odata.id': '/redfish/v1/Chassis'},
    'Managers': <String, Object?>{'@odata.id': '/redfish/v1/Managers'},
    'UpdateService': <String, Object?>{
      '@odata.id': '/redfish/v1/UpdateService',
    },
  },
  '/redfish/v1/Systems': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Systems/1'},
    ],
  },
  '/redfish/v1/Systems/1': <String, Object?>{
    'Id': '1',
    'Manufacturer': 'Huawei',
    'Model': '2288H V5',
    'SerialNumber': 'serial-1',
    'PowerState': 'On',
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
    'Processors': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/Processors',
    },
    'Memory': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/Memory',
    },
    'Storage': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/Storage',
    },
    'EthernetInterfaces': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/EthernetInterfaces',
    },
    'LogServices': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/LogServices',
    },
  },
  '/redfish/v1/Systems/1/Processors': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Systems/1/Processors/1'},
    ],
  },
  '/redfish/v1/Systems/1/Processors/1': <String, Object?>{
    'Id': '1',
    'Name': 'CPU1',
    'TotalCores': 24,
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
  },
  '/redfish/v1/Systems/1/Memory': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Systems/1/Memory/DIMM1'},
    ],
  },
  '/redfish/v1/Systems/1/Memory/DIMM1': <String, Object?>{
    'Id': 'DIMM1',
    'CapacityMiB': 8192,
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
  },
  '/redfish/v1/Systems/1/Storage': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Systems/1/Storage/RAID1'},
    ],
  },
  '/redfish/v1/Systems/1/Storage/RAID1': <String, Object?>{
    'Id': 'RAID1',
    'StorageControllers': <Object?>[
      <String, Object?>{
        'MemberId': '0',
        'Name': 'RAID Controller',
        'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
      },
    ],
    'Volumes': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/Storage/RAID1/Volumes',
    },
    'Drives': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Chassis/1/Drives/Disk1'},
    ],
  },
  '/redfish/v1/Systems/1/Storage/RAID1/Volumes': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{
        '@odata.id': '/redfish/v1/Systems/1/Storage/RAID1/Volumes/Volume1',
      },
    ],
  },
  '/redfish/v1/Systems/1/Storage/RAID1/Volumes/Volume1': <String, Object?>{
    'Id': 'Volume1',
    'CapacityBytes': 1000,
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
  },
  '/redfish/v1/Chassis/1/Drives/Disk1': <String, Object?>{
    'Id': 'Disk1',
    'CapacityBytes': 1000,
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
  },
  '/redfish/v1/Systems/1/EthernetInterfaces': <String, Object?>{
    'Members': <Object?>[],
  },
  '/redfish/v1/Systems/1/LogServices': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{
        '@odata.id': '/redfish/v1/Systems/1/LogServices/Log1',
      },
    ],
  },
  '/redfish/v1/Systems/1/LogServices/Log1': <String, Object?>{
    'Id': 'Log1',
    'Entries': <String, Object?>{
      '@odata.id': '/redfish/v1/Systems/1/LogServices/Log1/Entries',
    },
  },
  '/redfish/v1/Systems/1/LogServices/Log1/Entries': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{
        '@odata.id': '/redfish/v1/Systems/1/LogServices/Log1/Entries/1',
      },
    ],
    'Members@odata.nextLink':
        '/redfish/v1/Systems/1/LogServices/Log1/Entries?skip=1',
  },
  '/redfish/v1/Systems/1/LogServices/Log1/Entries/1': <String, Object?>{
    'Id': '1',
    'Severity': 'OK',
    'MessageId': 'iBMCEvents.2.5.NTPSynchronizeTimeFailInfo',
    'Message': 'iBMC failed to synchronize time with the NTP server.',
  },
  '/redfish/v1/Chassis': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Chassis/1'},
    ],
  },
  '/redfish/v1/Chassis/1': <String, Object?>{
    'Id': '1',
    'Thermal': <String, Object?>{
      '@odata.id': '/redfish/v1/Chassis/1/Thermal',
    },
    'Power': <String, Object?>{
      '@odata.id': '/redfish/v1/Chassis/1/Power',
    },
  },
  '/redfish/v1/Chassis/1/Thermal': <String, Object?>{
    'Temperatures': <Object?>[],
    'Fans': <Object?>[],
  },
  '/redfish/v1/Chassis/1/Power': <String, Object?>{
    'PowerSupplies': <Object?>[
      <String, Object?>{
        'Name': 'PS2',
        'Status': <String, Object?>{'Health': 'Critical', 'State': 'Enabled'},
      },
    ],
  },
  '/redfish/v1/Managers': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{'@odata.id': '/redfish/v1/Managers/1'},
    ],
  },
  '/redfish/v1/Managers/1': <String, Object?>{
    'Id': '1',
    'FirmwareVersion': '3.01',
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
  },
  '/redfish/v1/UpdateService': <String, Object?>{
    'FirmwareInventory': <String, Object?>{
      '@odata.id': '/redfish/v1/UpdateService/FirmwareInventory',
    },
  },
  '/redfish/v1/UpdateService/FirmwareInventory': <String, Object?>{
    'Members': <Object?>[
      <String, Object?>{
        '@odata.id': '/redfish/v1/UpdateService/FirmwareInventory/Bios',
      },
    ],
  },
  '/redfish/v1/UpdateService/FirmwareInventory/Bios': <String, Object?>{
    'Id': 'Bios',
    'Version': '0.84',
    'Status': <String, Object?>{'Health': 'OK', 'State': 'Enabled'},
  },
};
