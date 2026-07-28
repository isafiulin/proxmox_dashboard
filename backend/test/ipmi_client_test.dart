import 'package:neotelecom_backend/features/integrations/ipmi_client.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes Supermicro IPMI output into hardware inventory', () {
    const mc = '''
Firmware Revision         : 3.27
IPMI Version              : 2.0
Manufacturer Name         : Super Micro Computer Inc.
Product Name              : X10SLM-F
''';
    const chassis = '''
System Power         : on
Power Overload       : false
Main Power Fault     : false
Power Control Fault  : false
Chassis Intrusion    : inactive
Drive Fault          : false
Cooling/Fan Fault    : false
''';
    const sdr = '''
CPU Temp         | 01h | ok  |  3.1 | 48 degrees C
P1-DIMMA2 Temp   | B1h | ns  | 32.65 | No Reading
FAN1             | 41h | ok  | 29.1 | 1400 RPM
12V              | 30h | ok  |  7.17 | 12.26 Volts
Chassis Intru    | AAh | ok  | 23.1 |
''';
    const fru = '''
FRU Device Description : Builtin FRU Device (ID 0)
 Board Mfg             : Supermicro
 Board Serial          : ABC123
 Product Serial        : SYS123
''';

    final inventory = parseIpmiInventory(
      mcOutput: mc,
      chassisOutput: chassis,
      sdrOutput: sdr,
      selOutput: 'SEL has no entries',
      fruOutput: fru,
    );
    final systems = inventory['systems'] as List<Map<String, Object?>>;
    final temperatures =
        inventory['temperatures'] as List<Map<String, Object?>>;
    final fans = inventory['fans'] as List<Map<String, Object?>>;
    final thresholds =
        inventory['thresholdSensors'] as List<Map<String, Object?>>;

    expect((inventory['identity'] as Map)['model'], 'X10SLM-F');
    expect((inventory['identity'] as Map)['serialNumber'], 'SYS123');
    expect(systems.single['PowerState'], 'On');
    expect((systems.single['Status'] as Map)['Health'], 'OK');
    expect(temperatures, hasLength(2));
    expect(temperatures.first['ReadingCelsius'], 48);
    expect((temperatures.last['Status'] as Map)['State'], 'Absent');
    expect(fans.single['Reading'], 1400);
    expect(thresholds.single['ReadingValue'], 12.26);
    expect(inventory['logEntries'], isEmpty);
    expect(inventory['healthIssues'], isEmpty);
  });

  test('reports real IPMI sensor failures but ignores unavailable slots', () {
    final inventory = parseIpmiInventory(
      mcOutput: 'Product Name : server',
      chassisOutput: 'System Power : on',
      sdrOutput: '''
FAN1 | 41h | cr | 29.1 | 0 RPM
FAN2 | 42h | ns | 29.2 | No Reading
''',
      selOutput: 'SEL has no entries',
      fruOutput: '',
    );

    final issues = inventory['healthIssues'] as List<Map<String, Object?>>;
    expect(issues, hasLength(1));
    expect(issues.single['name'], 'FAN1');
    expect(issues.single['health'], 'Critical');
  });
}
