import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_patch_workbench_dialog.dart';

void main() {
  testWidgets('renders an explicit operation editor and can add rows', (
    tester,
  ) async {
    final recipe = PromptRecipe.create(
      id: 'recipe-root',
      params: const ImageParams(prompt: '1girl, blue hair'),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: PromptPatchWorkbenchDialog(recipe: recipe)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-patch-workbench')),
      findsOneWidget,
    );
    expect(find.text('应用补丁'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text('添加操作'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(3));
  });
}
