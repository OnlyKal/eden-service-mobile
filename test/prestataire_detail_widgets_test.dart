import 'package:eden_service_mobile/widgets/expandable_text.dart';
import 'package:eden_service_mobile/widgets/whatsapp_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Texte suffisamment long pour dépasser [lines] lignes sur 320 px de large.
String longText(int lines) => List.filled(
  lines,
  'Je suis un prestataire_experimenté disponible sur toute la ville.',
).join(' ');

Widget harness(Widget child) => MaterialApp(
  home: Scaffold(
    // Le texte déroulé peut dépasser la surface de test : on reproduit le
    // défilement de l'écran réelle (CustomScrollView).
    body: SingleChildScrollView(
      child: SizedBox(
        width: 320,
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      ),
    ),
  ),
);

/// Amène le bouton sous le doigt avant de le taper.
Future<void> tapToggle(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('ExpandableText', () {
    testWidgets('texte court : aucun bouton affiché', (tester) async {
      await tester.pumpWidget(harness(const ExpandableText(text: 'Bonjour.')));

      expect(find.text('Voir plus'), findsNothing);
      expect(find.text('Voir moins'), findsNothing);
      expect(find.text('Bonjour.'), findsOneWidget);
    });

    testWidgets('texte long : « Voir plus » puis « Voir moins »', (tester) async {
      await tester.pumpWidget(harness(ExpandableText(text: longText(12))));

      expect(find.text('Voir plus'), findsOneWidget);
      expect(find.text('Voir moins'), findsNothing);

      await tapToggle(tester, 'Voir plus');

      expect(find.text('Voir moins'), findsOneWidget);
      expect(find.text('Voir plus'), findsNothing);

      await tapToggle(tester, 'Voir moins');

      expect(find.text('Voir plus'), findsOneWidget);
    });

    testWidgets('le texte est tronqué puis complet', (tester) async {
      await tester.pumpWidget(harness(ExpandableText(text: longText(12))));

      Text textWidget() => tester.widget<Text>(find.byType(Text).first);
      final collapsed = textWidget();
      expect(collapsed.maxLines, 4);
      expect(collapsed.overflow, TextOverflow.ellipsis);

      await tapToggle(tester, 'Voir plus');

      final expanded = textWidget();
      expect(expanded.maxLines, isNull);
      expect(expanded.overflow, TextOverflow.clip);
    });

    testWidgets('texte très long : aucun débordement de rendu', (tester) async {
      await tester.pumpWidget(harness(ExpandableText(text: longText(40))));

      await tapToggle(tester, 'Voir plus');

      // Aucune exception de rendu (overflow) ne doit être levée.
      expect(tester.takeException(), isNull);
    });

    testWidgets('le nombre de lignes repliées est paramétrable', (tester) async {
      await tester.pumpWidget(
        harness(const ExpandableText(text: 'Texte', collapsedMaxLines: 2)),
      );

      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.maxLines, 2);
    });
  });

  group('WhatsappIcon', () {
    testWidgets('se rend à la taille demandée', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: WhatsappIcon(size: 26)),
          ),
        ),
      );

      final icon = tester.widget<WhatsappIcon>(find.byType(WhatsappIcon));
      expect(icon.size, 26);
      expect(find.byType(WhatsappIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
