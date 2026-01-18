import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/compute_precache_requests.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/battlebox_doc.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/rich_text_value.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_inline_parser.dart';

void main() {
  test('precache walks plainlist and efn contents', () {
    final doc = BattleBoxDoc(
      id: 'doc_1',
      title: 'Test',
      sections: const [
        SingleFieldSection(
          id: 'result',
          label: 'Result',
          value: RichTextValue(
            '{{Plainlist| * {{flagicon|USA}} US }} {{Efn|Note {{flagicon|GBR}}}}',
          ),
        ),
      ],
    );

    final usecase = const ComputePrecacheRequests(WikitextInlineParser());
    final requests = usecase(
      doc: doc,
      fontSizes: [14],
      devicePixelRatio: 1.0,
    );

    final iconCodes = requests
        .whereType<FlagIconRequest>()
        .map((request) => request.code)
        .toSet();

    expect(iconCodes, containsAll(['USA', 'GBR']));
  });
}
