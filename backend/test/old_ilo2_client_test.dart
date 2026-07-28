import 'package:neotelecom_backend/features/integrations/old_ilo2_client.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes old iLO 2 CLP data into the Redfish-shaped inventory', () {
    const system = r'''
iLO 2 Advanced 1.78 at 15:43:13 Jun 10 2009
/system1
  Properties
    name=ProLiant DL360 G5
    enabledstate=enabled
    oemhp_PresentPower=222 Watts
/system1/cpu1
  Properties
    name=Intel Xeon
    speed=3000MHz
    healthstate=Ok
/system1/memory1
  Properties
    name=DIMM 1
    size=4GB
    healthstate=Degraded
/system1/powersupply1
  Properties
    name=Power Supply 1
    healthstate=NonCritical
''';
    const log = r'''
/system1/log1/record315
  Properties
    number=315
    severity=NonCritical
    date=06/10/2020
    time=01:58
    description=System Power Supply: General Failure (Power Supply
                 1)
''';

    final inventory = parseOldIlo2Inventory(system, log);
    final systems = inventory['systems'] as List<Map<String, Object?>>;
    final memory = inventory['memory'] as List<Map<String, Object?>>;
    final logs = inventory['logEntries'] as List<Map<String, Object?>>;
    final issues = inventory['healthIssues'] as List<Map<String, Object?>>;

    expect((inventory['identity'] as Map)['model'], 'ProLiant DL360 G5');
    expect(systems.single['PowerState'], 'On');
    expect(systems.single['PresentPowerWatts'], 222);
    expect(memory.single['CapacityMiB'], 4096);
    expect(logs.single['normalizedSeverity'], 'Warning');
    expect(logs.single['Message'], contains('Power Supply 1'));
    expect(issues.map((row) => row['resourceType']),
        containsAll(<String>['memory', 'power_supply']));
  });

  test('parses recursive iLO 2 output with short target headings', () {
    const system = r'''
/system1
  Targets
    cpu1
    memory1
    fan1
    sensor1
    powersupply1
  Properties
    name=ProLiant DL360 G5
    enabledstate=enabled
    oemhp_PresentPower=222 Watts
  Verbs
    cd version exit show set
cpu1
  Targets
  Properties
    name=Intel Xeon
    speed=3000MHz
    healthstate=Ok
  Verbs
    cd version exit show set
memory1
  Targets
  Properties
    name=DIMM 1
    size=4GB
    healthstate=Ok
  Verbs
    cd version exit show set
fan1
  Targets
  Properties
    name=Fan 1
    speed=42 percent
    healthstate=Ok
  Verbs
    cd version exit show set
sensor1
  Targets
  Properties
    name=Ambient Temperature
    currentreading=24 degrees C
    healthstate=Ok
  Verbs
    cd version exit show set
powersupply1
  Targets
  Properties
    name=Power Supply 1
    healthstate=NonCritical
  Verbs
    cd version exit show set
''';
    const log = r'''
/system1/log1
  Targets
    record314
    record315
  Properties
  Verbs
    cd version exit show set
record315
  Targets
  Properties
    number=315
    severity=NonCritical
    date=06/10/2020
    time=01:58
    description=System Power Supply: General Failure (Power Supply
                 1)
  Verbs
    cd version exit show set
''';

    final inventory = parseOldIlo2Inventory(system, log);

    expect((inventory['identity'] as Map)['model'], 'ProLiant DL360 G5');
    expect((inventory['systems'] as List).single['PowerState'], 'On');
    expect((inventory['processors'] as List), hasLength(1));
    expect((inventory['memory'] as List).single['CapacityMiB'], 4096);
    expect((inventory['fans'] as List), hasLength(1));
    expect((inventory['temperatures'] as List), hasLength(1));
    expect((inventory['powerSupplies'] as List), hasLength(1));
    expect((inventory['logEntries'] as List).single['Id'], '315');
  });
}
