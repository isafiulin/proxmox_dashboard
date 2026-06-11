import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/snapshots/domain/data_snapshot.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';

void main() {
  test('builds resource history from proxmox ve snapshots', () {
    final snapshots = <DataSnapshot>[
      DataSnapshot(
        id: '1',
        sourceId: 'pve',
        sourceType: 'proxmox_ve',
        status: 'ok',
        collectedAt: DateTime(2026, 6, 5, 10),
        payload: const <String, Object?>{
          'resources': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'node',
              'cpu': 0.2,
              'mem': 50,
              'maxmem': 100,
            },
            <String, Object?>{
              'type': 'qemu',
              'cpu': 0.4,
              'mem': 20,
              'maxmem': 100,
            },
            <String, Object?>{'type': 'storage', 'disk': 70, 'maxdisk': 100},
          ],
        },
      ),
      DataSnapshot(
        id: '2',
        sourceId: 'pve',
        sourceType: 'proxmox_ve',
        status: 'ok',
        collectedAt: DateTime(2026, 6, 5, 11),
        payload: const <String, Object?>{
          'resources': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'node',
              'cpu': 0.6,
              'mem': 80,
              'maxmem': 100,
            },
            <String, Object?>{
              'type': 'lxc',
              'cpu': 0.1,
              'mem': 10,
              'maxmem': 100,
            },
            <String, Object?>{'type': 'storage', 'disk': 90, 'maxdisk': 100},
          ],
        },
      ),
    ];

    final report = buildResourceHistory(snapshots);

    expect(report.nodeCpu.map((point) => point.value), <double>[0.2, 0.6]);
    expect(report.nodeRam.map((point) => point.value), <double>[0.5, 0.8]);
    expect(report.guestCpu.map((point) => point.value), <double>[0.4, 0.1]);
    expect(report.guestRam.map((point) => point.value), <double>[0.2, 0.1]);
    expect(report.storageUsage.map((point) => point.value), <double>[0.7, 0.9]);
  });

  test('builds resource history for a single node', () {
    final snapshots = <DataSnapshot>[
      DataSnapshot(
        id: '1',
        sourceId: 'pve-a',
        sourceType: 'proxmox_ve',
        status: 'ok',
        collectedAt: DateTime(2026, 6, 5, 10),
        payload: const <String, Object?>{
          'resources': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'node',
              'node': 'n1',
              'cpu': 0.2,
              'mem': 50,
              'maxmem': 100,
            },
            <String, Object?>{
              'type': 'node',
              'node': 'n2',
              'cpu': 0.9,
              'mem': 90,
              'maxmem': 100,
            },
          ],
        },
      ),
      DataSnapshot(
        id: '2',
        sourceId: 'pve-a',
        sourceType: 'proxmox_ve',
        status: 'ok',
        collectedAt: DateTime(2026, 6, 5, 11),
        payload: const <String, Object?>{
          'resources': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'node',
              'node': 'n1',
              'cpu': 0.4,
              'mem': 70,
              'maxmem': 100,
            },
          ],
        },
      ),
    ];

    final report = buildNodeResourceHistory(
      snapshots,
      sourceId: 'pve-a',
      node: 'n1',
    );

    expect(report.cpu.map((point) => point.value), <double>[0.2, 0.4]);
    expect(report.ram.map((point) => point.value), <double>[0.5, 0.7]);
  });
}
