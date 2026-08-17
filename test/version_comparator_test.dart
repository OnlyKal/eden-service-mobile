import 'package:flutter_test/flutter_test.dart';
import 'package:eden_service_mobile/core/utils/version_comparator.dart';

void main() {
  group('VersionComparator.compare', () {
    test('compare des versions simples', () {
      expect(VersionComparator.compare('405', '405'), 0);
      expect(VersionComparator.compare('1.0.5', '1.0.5'), 0);
      expect(VersionComparator.compare('1.0.5', '1.0.10'), -1);
      expect(VersionComparator.compare('1.0.10', '1.0.5'), 1);
    });

    test('compare des versions avec préfixe v', () {
      expect(VersionComparator.compare('v1.0.5', '1.0.5'), 0);
      expect(VersionComparator.compare('V2.0.0', '2.0.0'), 0);
      expect(VersionComparator.compare('v1.0.5', '1.0.10'), -1);
    });

    test('compare des versions avec suffixes', () {
      expect(VersionComparator.compare('1.0.0-beta', '1.0.0'), 0);
      expect(VersionComparator.compare('1.0.0+123', '1.0.0'), 0);
      expect(VersionComparator.compare('1.0.0-beta+123', '1.0.0'), 0);
    });

    test('compare des versions de longueurs différentes', () {
      expect(VersionComparator.compare('1.0', '1.0.0'), 0);
      expect(VersionComparator.compare('1.0.5', '1.0'), 1);
      expect(VersionComparator.compare('1.0', '1.0.5'), -1);
      expect(VersionComparator.compare('405', '405.0'), 0);
    });

    test('compare des versions numériques vs chaînes', () {
      expect(VersionComparator.compare('405', '406'), -1);
      expect(VersionComparator.compare('406', '405'), 1);
      expect(VersionComparator.compare('405', '405'), 0);
    });

    test('gère les versions vides ou invalides', () {
      expect(VersionComparator.compare('', ''), 0);
      expect(VersionComparator.compare('', '1.0.0'), -1);
      expect(VersionComparator.compare('abc', '1.0.0'), -1);
      expect(VersionComparator.compare('1.0.0', 'abc'), 1);
    });
  });

  group('VersionComparator helpers', () {
    test('isLower', () {
      expect(VersionComparator.isLower('1.0.5', '1.0.10'), true);
      expect(VersionComparator.isLower('1.0.10', '1.0.5'), false);
      expect(VersionComparator.isLower('405', '406'), true);
    });

    test('isHigher', () {
      expect(VersionComparator.isHigher('1.0.10', '1.0.5'), true);
      expect(VersionComparator.isHigher('1.0.5', '1.0.10'), false);
      expect(VersionComparator.isHigher('406', '405'), true);
    });

    test('isEqual', () {
      expect(VersionComparator.isEqual('405', '405'), true);
      expect(VersionComparator.isEqual('1.0.5', '1.0.5'), true);
      expect(VersionComparator.isEqual('405', '406'), false);
    });

    test('isLowerOrEqual', () {
      expect(VersionComparator.isLowerOrEqual('1.0.5', '1.0.10'), true);
      expect(VersionComparator.isLowerOrEqual('1.0.5', '1.0.5'), true);
      expect(VersionComparator.isLowerOrEqual('1.0.10', '1.0.5'), false);
    });

    test('isHigherOrEqual', () {
      expect(VersionComparator.isHigherOrEqual('1.0.10', '1.0.5'), true);
      expect(VersionComparator.isHigherOrEqual('1.0.5', '1.0.5'), true);
      expect(VersionComparator.isHigherOrEqual('1.0.5', '1.0.10'), false);
    });
  });
}