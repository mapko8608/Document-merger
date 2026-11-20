import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel_plus/excel_plus.dart';

void main() => runApp(const DocumentMergerApp());

class DocumentMergerApp extends StatelessWidget {
  const DocumentMergerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Document Merger',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: const HomePage(),
      );
}

class ImportedDocument {
  final String id;
  final PlatformFile file;
  ImportedDocument({required this.id, required this.file});
}

class DocumentRow {
  String product, dimensions, quantity, unit, thickness, material;
  String lengthMm, source, page, originalText;
  Set<String> sourceIds;
  List<String> reviewReasons;
  bool lengthWasSpecified;

  // Количество и исходные сведения хранятся отдельно по каждому документу.
  Map<String, double> quantitiesBySource;
  Map<String, String> sourcesById;
  Map<String, String> pagesById;
  Map<String, String> textsById;

  DocumentRow({
    required this.product,
    required this.dimensions,
    required this.quantity,
    required this.unit,
    required this.thickness,
    required this.material,
    required this.lengthMm,
    required this.source,
    required this.page,
    required this.originalText,
    required this.sourceIds,
    required this.reviewReasons,
    this.lengthWasSpecified = false,
    Map<String, double>? quantitiesBySource,
    Map<String, String>? sourcesById,
    Map<String, String>? pagesById,
    Map<String, String>? textsById,
  })  : quantitiesBySource = quantitiesBySource ?? {},
        sourcesById = sourcesById ?? {},
        pagesById = pagesById ?? {},
        textsById = textsById ?? {};

  DocumentRow copy() => DocumentRow(
        product: product,
        dimensions: dimensions,
        quantity: quantity,
        unit: unit,
        thickness: thickness,
        material: material,
        lengthMm: lengthMm,
        source: source,
        page: page,
        originalText: originalText,
        sourceIds: Set<String>.from(sourceIds),
        reviewReasons: List<String>.from(reviewReasons),
        lengthWasSpecified: lengthWasSpecified,
        quantitiesBySource: Map<String, double>.from(quantitiesBySource),
        sourcesById: Map<String, String>.from(sourcesById),
        pagesById: Map<String, String>.from(pagesById),
        textsById: Map<String, String>.from(textsById),
      );

  bool get needsReview => reviewReasons.isNotEmpty;

  bool get isStraightDuct {
    final name = product.toLowerCase();
    final duct = name.contains('воздуховод') ||
        name.contains('труба') ||
        name.contains('трубопровод');
    final fitting = RegExp(
      r'отвод|тройник|переход|клапан|заглушка|врезка|шумоглушитель|'
      r'крышка|фланец|зонт|утка|вставка|дроссель',
    ).hasMatch(name);
    return duct && !fitting;
  }

  bool get isRound => RegExp(
        r'ø|⌀|ду\s*[-=]?\s*\d|(?<![a-zа-я])d\s*[-=]?\s*\d',
        caseSensitive: false,
      ).hasMatch(dimensions);

  String get calculatedPieces {
    final meters = double.tryParse(quantity.replaceAll(',', '.'));
    final length = double.tryParse(lengthMm.replaceAll(',', '.'));
    if (!isStraightDuct || unit != 'м' || meters == null ||
        length == null || length <= 0) return '';
    return math.max(1, (meters * 1000 / length).ceil()).toString();
  }

  void refreshSourceText() {
    source = sourcesById.values.toSet().join('; ');
    page = pagesById.values.toSet().join('; ');
    originalText = textsById.values.join('\n---\n');
    sourceIds = quantitiesBySource.keys.toSet();
    final total = quantitiesBySource.values.fold<double>(0, (a, b) => a + b);
    quantity = total.toString();
  }
}

class ParsedRow {
  final String product, dimensions, quantity, unit, thickness, material, lengthMm;
  final bool lengthWasSpecified;
  final List<String> reviewReasons;
  ParsedRow({
    required this.product,
    required this.dimensions,
    required this.quantity,
    required this.unit,
    required this.thickness,
    required this.material,
    required this.lengthMm,
    required this.lengthWasSpecified,
    required this.reviewReasons,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ImportedDocument> documents = [];
  final List<DocumentRow> rows = [];
  bool isImporting = false;
  String roundLength = '3000';
  String rectangularLength = '1500';
  int documentCounter = 0;

  String createDocumentId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${++documentCounter}';

  Future<void> addDocuments() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xls', 'xlsx'],
    );
    if (picked == null || picked.isEmpty) return;

    final added = picked.map((f) => ImportedDocument(
      id: createDocumentId(), file: f,
    )).toList();

    setState(() {
      isImporting = true;
      documents.addAll(added);
    });

    int imported = 0, failed = 0;
    for (final doc in added) {
      final ext = doc.file.extension?.toLowerCase();
      if (ext == 'xlsx' || ext == 'xls') {
        try {
          final workbook = Excel.decodeBytes(await doc.file.readAsBytes());
          // Не загружаем сводные листы вида «наименование / Сумма - Кол-во».
          final candidates = <String>[];
          for (final name in workbook.tables.keys) {
            final sheet = workbook[name];
            if (sheet == null || sheet.rows.isEmpty) continue;
            final firstRows = sheet.rows.take(8).map((r) =>
              r.map((c) => c?.value?.toString().toLowerCase() ?? '').join(' ')
            ).join(' ');
            final summary = firstRows.contains('сумма - кол-во') ||
                firstRows.contains('сумма-кол-во');
            if (!summary) candidates.add(name);
          }
          for (final name in candidates) {
            final sheet = workbook[name];
            if (sheet != null) {
              imported += importSheet(sheet.rows, doc.file.name, name, doc.id);
            }
          }
        } catch (e) {
          failed++;
          debugPrint('Ошибка чтения ${doc.file.name}: $e');
        }
      }
    }

    if (!mounted) return;
    setState(() => isImporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Добавлено документов: ${added.length}. '
          'Распознано строк Excel: $imported.'
          '${failed > 0 ? ' Ошибок чтения: $failed.' : ''}'),
    ));
  }

  int importSheet(List<List<Data?>> sheetRows, String fileName,
      String sheetName, String documentId) {
    int imported = 0;
    for (final row in sheetRows) {
      // Пустые ячейки не удаляем: их позиции важны для количества и единицы.
      final cells = row.map((c) => c?.value?.toString().trim() ?? '').toList();
      if (cells.every((v) => v.isEmpty)) continue;
      final text = cells.where((v) => v.isNotEmpty).join(' | ').trim();
      if (text.isEmpty || looksLikeHeader(text)) continue;
      final parsed = parseRow(text, cells);
      if (parsed.product.isEmpty && parsed.dimensions.isEmpty &&
          parsed.quantity.isEmpty) continue;

      final name = parsed.product.toLowerCase();
      final straight = (name.contains('воздуховод') || name.contains('труба') ||
              name.contains('трубопровод')) &&
          !RegExp(r'отвод|тройник|переход|клапан|заглушка|врезка|'
              r'шумоглушитель|крышка|фланец|зонт|утка|вставка|дроссель')
              .hasMatch(name);
      var length = parsed.lengthMm;
      if (length.isEmpty && straight) {
        final round = RegExp(r'ø|⌀|ду\s*[-=]?\s*\d|'
          r'(?<![a-zа-я])d\s*[-=]?\s*\d', caseSensitive: false)
          .hasMatch(parsed.dimensions);
        length = round ? roundLength : rectangularLength;
      }

      final amount = double.tryParse(parsed.quantity.replaceAll(',', '.'));
      rows.add(DocumentRow(
        product: parsed.product,
        dimensions: parsed.dimensions,
        quantity: parsed.quantity,
        unit: parsed.unit,
        thickness: parsed.thickness,
        material: parsed.material,
        lengthMm: length,
        source: fileName,
        page: sheetName,
        originalText: text,
        sourceIds: {documentId},
        reviewReasons: List<String>.from(parsed.reviewReasons),
        lengthWasSpecified: parsed.lengthWasSpecified,
        quantitiesBySource: amount == null ? {} : {documentId: amount},
        sourcesById: {documentId: fileName},
        pagesById: {documentId: sheetName},
        textsById: {documentId: text},
      ));
      imported++;
    }
    return imported;
  }

  bool looksLikeHeader(String text) {
    final v = text.toLowerCase();
    final words = ['наименование', 'название', 'изделие', 'размер',
      'количество', 'кол-во', 'толщина', 'материал'];
    return words.where(v.contains).length >= 2;
  }

  String normalizeUnit(String value) {
    final v = value.toLowerCase().replaceAll('.', '').trim();
    if (['м', 'метр', 'метры', 'метров', 'пм', 'погм',
      'погонный метр', 'пог м'].contains(v)) return 'м';
    if (['шт', 'штука', 'штуки', 'штук', 'pcs', 'pc'].contains(v)) return 'шт';
    if (['кг', 'килограмм', 'килограммы'].contains(v)) return 'кг';
    if (['т', 'тонна', 'тонны'].contains(v)) return 'т';
    return '';
  }

  ParsedRow parseRow(String original, List<String> cells) {
    var working = original.replaceAll('\n', ' ').trim();
    var dimensions = '', thickness = '', quantity = '', unit = '', lengthMm = '';
    var material = '';
    var lengthWasSpecified = false;
    final reasons = <String>[];

    // Коды круглых и прямоугольных дросселей также содержат размер.
    final codeRound = RegExp(r'\bДК\s*[- ]\s*(\d{2,4})\b',
        caseSensitive: false).firstMatch(working);
    final codeRect = RegExp(r'\bДКП\s*[- ]\s*(\d{2,4})\s*[хx×]\s*(\d{2,4})\b',
        caseSensitive: false).firstMatch(working);

    final dimPattern = RegExp(
      r'(?:Ø|⌀)\s*\d{2,4}(?:[.,]\d+)?'
      r'|(?:ду|d)\s*[-=]?\s*\d{2,4}'
      r'|\d{2,4}\s*[xх×*]\s*\d{2,4}(?:\s*[xх×*]\s*\d{2,4})?',
      caseSensitive: false,
    );
    final found = dimPattern.allMatches(working)
        .map((m) => m.group(0)!.replaceAll(' ', '').replaceAll('х', '×')
            .replaceAll('x', '×'))
        .toList();
    if (found.isNotEmpty) {
      dimensions = found.toSet().join('; ');
      working = working.replaceAll(dimPattern, ' ');
    }
    if (codeRound != null) {
      dimensions = 'Ø${codeRound.group(1)}';
      working = working.replaceFirst(codeRound.group(0)!, ' ');
    } else if (codeRect != null) {
      dimensions = '${codeRect.group(1)}×${codeRect.group(2)}';
      working = working.replaceFirst(codeRect.group(0)!, ' ');
    }
    if (dimensions.isEmpty) reasons.add('Не распознаны размеры изделия');

    // Толщина: только явные обозначения b= / толщина / стенка.
    // Не ищем произвольные десятичные числа: ОВ2.0 — номер раздела, не толщина.
    final thicknessPattern = RegExp(
      r'(?:толщина(?:\s+стенки)?|стенка|(?<![a-zа-я])b)'
      r'\s*[:=]?\s*(\d{1,2}[.,]\d{1,3})',
      caseSensitive: false,
    );
    final thicknessMatch = thicknessPattern.firstMatch(working);
    if (thicknessMatch != null) {
      thickness = thicknessMatch.group(1)!.replaceAll(',', '.');
      working = working.replaceFirst(thicknessPattern, ' ');
    } else {
      reasons.add('Не распознана толщина');
    }

    final materialPatterns = [
      RegExp(r'нержав(?:еющая)?\s*сталь', caseSensitive: false),
      RegExp(r'нерж\.?', caseSensitive: false),
      RegExp(r'оцинк(?:ованная|ованной|ованный)?', caseSensitive: false),
      RegExp(r'ст\.?\s*оц\.?', caseSensitive: false),
      RegExp(r'черная\s*сталь', caseSensitive: false),
      RegExp(r'алюмини(?:й|евая|евый)', caseSensitive: false),
      RegExp(r'\baisi\s*\d{3,4}\b', caseSensitive: false),
      RegExp(r'\bdx51\b', caseSensitive: false),
    ];
    for (final pattern in materialPatterns) {
      final match = pattern.firstMatch(working);
      if (match != null) {
        material = match.group(0)!.trim();
        working = working.replaceFirst(pattern, ' ');
        break;
      }
    }
    if (material.isEmpty) {
      material = 'Оцинкованная сталь';
    }

    final lengthPattern = RegExp(
      r'(?:длина|дл\.?|(?<![a-zа-я])l)\s*[:=]?\s*'
      r'(\d+(?:[.,]\d+)?)\s*(мм|mm|м|m)?',
      caseSensitive: false,
    );
    final lm = lengthPattern.firstMatch(working);
    if (lm != null) {
      final value = double.tryParse(lm.group(1)!.replaceAll(',', '.'));
      if (value != null && value > 0) {
        final u = (lm.group(2) ?? 'мм').toLowerCase();
        lengthMm = (u == 'м' || u == 'm' ? value * 1000 : value)
            .toStringAsFixed(0);
        lengthWasSpecified = true;
        working = working.replaceFirst(lengthPattern, ' ');
      }
    }

    // Сначала используем соседнюю исходную ячейку: сохраняем позиции колонок.
    for (var i = 0; i < cells.length; i++) {
      final u = normalizeUnit(cells[i]);
      if (u.isEmpty) continue;
      for (final j in [i + 1, i - 1]) {
        if (j < 0 || j >= cells.length) continue;
        final n = double.tryParse(cells[j].replaceAll(',', '.'));
        if (n != null && n > 0) {
          quantity = n.toString();
          unit = u;
          break;
        }
      }
      if (quantity.isNotEmpty) break;
    }

    final qtyPattern = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(погонных?\s*метр(?:а|ов)?|пог\.?\s*м|'
      r'метр(?:а|ов)?|мм|mm|м|m|шт\.?|штук|pcs?|кг|т)(?![а-яa-z])',
      caseSensitive: false,
    );
    if (quantity.isEmpty) {
      final qm = qtyPattern.firstMatch(working);
      if (qm != null) {
        quantity = qm.group(1)!.replaceAll(',', '.');
        unit = normalizeUnit(qm.group(2)!);
        working = working.replaceFirst(qtyPattern, ' ');
      }
    }

    if (quantity.isEmpty) {
      final marked = RegExp(
        r'(?:кол-?во|количество|qty)\s*[:=]?\s*(\d+(?:[.,]\d+)?)',
        caseSensitive: false,
      ).firstMatch(working);
      if (marked != null) {
        quantity = marked.group(1)!.replaceAll(',', '.');
        working = working.replaceFirst(marked.group(0)!, ' ');
      }
    }

    if (quantity.isEmpty) {
      // Числовые ячейки: исключаем номера позиций и десятичные значения.
      final nums = cells.where((c) =>
        RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(c.trim()) &&
        !RegExp(r'^\d+[.,]\d+$').hasMatch(c.trim())).toList();
      if (nums.length == 1) {
        quantity = nums.first;
        reasons.add('Количество найдено, но единица измерения не определена');
      } else {
        reasons.add('Не распознано количество');
      }
    }
    if (quantity.isNotEmpty && unit.isEmpty &&
        !reasons.contains('Количество найдено, но единица измерения не определена')) {
      reasons.add('Не определена единица измерения количества');
    }

    var product = working.replaceAll('|', ' ')
        .replaceAll(RegExp(r'[,;]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    product = product.replaceAll(RegExp(
      r'^(?:наименование|изделие|название)\s*[:=]?\s*',
      caseSensitive: false), '').trim();
    // Убираем служебный код раздела в начале строки.
    product = product.replaceFirst(RegExp(r'^ОВ\s*\d+(?:[.,]\d+)?\s*'),
        '').trim();
    if (product.isEmpty) {
      product = original.trim();
      reasons.add('Не распознано название изделия');
    }

    return ParsedRow(
      product: product, dimensions: dimensions, quantity: quantity, unit: unit,
      thickness: thickness, material: material, lengthMm: lengthMm,
      lengthWasSpecified: lengthWasSpecified, reviewReasons: reasons,
    );
  }

  void updateDefaultLengths({String? newRoundLength, String? newRectangularLength}) {
    setState(() {
      if (newRoundLength != null) roundLength = newRoundLength;
      if (newRectangularLength != null) rectangularLength = newRectangularLength;
      for (final row in rows) {
        if (!row.isStraightDuct || row.lengthWasSpecified) continue;
        row.lengthMm = row.isRound ? roundLength : rectangularLength;
      }
    });
  }

  Future<void> deleteDocument(ImportedDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text('Документ «${document.file.name}» и полученные из него '
            'данные будут удалены. Данные из остальных документов сохранятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      documents.removeWhere((d) => d.id == document.id);
      for (var i = rows.length - 1; i >= 0; i--) {
        final row = rows[i];
        row.quantitiesBySource.remove(document.id);
        row.sourcesById.remove(document.id);
        row.pagesById.remove(document.id);
        row.textsById.remove(document.id);
        if (row.quantitiesBySource.isEmpty && row.sourceIds.contains(document.id)) {
          rows.removeAt(i);
        } else if (row.sourceIds.contains(document.id)) {
          row.refreshSourceText();
        } else if (row.sourceIds.isEmpty) {
          // Необъединённые строки старого формата.
          rows.removeAt(i);
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Документ и его вклад удалены')),
    );
  }

  void openTable() => Navigator.push(context, MaterialPageRoute(
    builder: (_) => TablePage(rows: rows, initialCount: rows.length,
      onChanged: () => setState(() {})),
  ));

  Widget lengthSelector({required String title, required String selected,
    required List<String> options, required ValueChanged<String> onSelected}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: options.map((v) => ChoiceChip(
        label: Text('$v мм'), selected: selected == v,
        onSelected: (_) => onSelected(v),
      )).toList()),
    ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Обработка документов')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(onPressed: isImporting ? null : addDocuments,
          icon: const Icon(Icons.add), label: const Text('Добавить документы')),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(onPressed: openTable,
          icon: const Icon(Icons.table_chart),
          label: Text('Открыть общую таблицу (${rows.length})')),
        const SizedBox(height: 16),
        const Divider(),
        const Text('Длина по умолчанию для прямых воздуховодов и труб',
          style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        lengthSelector(title: 'Круглые', selected: roundLength,
          options: const ['3000', '1250'],
          onSelected: (v) => updateDefaultLengths(newRoundLength: v)),
        const SizedBox(height: 12),
        lengthSelector(title: 'Прямоугольные', selected: rectangularLength,
          options: const ['1250', '1500'],
          onSelected: (v) => updateDefaultLengths(newRectangularLength: v)),
        const SizedBox(height: 8),
        const Text('Явная длина из заявки имеет приоритет над выбранной длиной.',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
        const Divider(height: 24),
        if (isImporting) ...[
          const LinearProgressIndicator(), const SizedBox(height: 8),
        ],
        Text('Добавленные документы: ${documents.length}'),
        const SizedBox(height: 8),
        Expanded(child: documents.isEmpty
          ? const Center(child: Text('Документы пока не добавлены'))
          : ListView.builder(itemCount: documents.length, itemBuilder: (ctx, i) {
              final d = documents[i];
              final count = rows.where((r) => r.sourceIds.contains(d.id)).length;
              return Card(child: ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(d.file.name),
                subtitle: Text('${d.file.extension?.toUpperCase() ?? 'Файл'} • Позиций: $count'),
                trailing: IconButton(
                  tooltip: 'Удалить документ',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: isImporting ? null : () => deleteDocument(d)),
              ));
            })),
        const Text('PDF пока добавляется в список, распознавание его содержимого не подключено.',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    )),
  );
}

class TablePage extends StatefulWidget {
  final List<DocumentRow> rows;
  final int initialCount;
  final VoidCallback onChanged;
  const TablePage({super.key, required this.rows, required this.initialCount,
    required this.onChanged});
  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  List<DocumentRow>? previousRows;

  Future<void> editRow(DocumentRow row) async {
    final product = TextEditingController(text: row.product);
    final dimensions = TextEditingController(text: row.dimensions);
    final quantity = TextEditingController(text: row.quantity);
    final unit = TextEditingController(text: row.unit);
    final thickness = TextEditingController(text: row.thickness);
    final material = TextEditingController(text: row.material);
    final length = TextEditingController(text: row.lengthMm);

    final result = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('Редактирование позиции'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
            editField(product, 'Название изделия'),
            editField(dimensions, 'Размеры'),
            editField(quantity, 'Количество'),
            editField(unit, 'Единица измерения (м, шт, кг)'),
            editField(thickness, 'Толщина'),
            editField(material, 'Материал'),
            editField(length, 'Длина одного изделия (мм)'),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить')),
        ],
      ));
    if (result == true && mounted) {
      setState(() {
        row.product = product.text.trim();
        row.dimensions = dimensions.text.trim();
        row.quantity = quantity.text.trim();
        row.unit = unit.text.trim().toLowerCase();
        row.thickness = thickness.text.trim();
        row.material = material.text.trim();
        row.lengthMm = length.text.trim();
        row.lengthWasSpecified = row.lengthMm.isNotEmpty;
        row.reviewReasons.clear();
        // Ручное редактирование объединённой строки фиксирует единый итог.
        row.quantitiesBySource.clear();
        row.sourceIds.clear();
      });
      widget.onChanged();
    }
    product.dispose(); dimensions.dispose(); quantity.dispose(); unit.dispose();
    thickness.dispose(); material.dispose(); length.dispose();
  }

  Widget editField(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, decoration: InputDecoration(
      labelText: label, border: const OutlineInputBorder())),
  );

  void deleteRow(int index) {
    setState(() { widget.rows.removeAt(index); previousRows = null; });
    widget.onChanged();
  }

  void mergeDuplicates() {
    previousRows = widget.rows.map((r) => r.copy()).toList();
    final groups = <String, List<DocumentRow>>{};
    for (final row in widget.rows) {
      final key = [
        row.product.toLowerCase().trim(),
        normalizeDimensions(row.dimensions),
        row.thickness.toLowerCase().trim(),
        row.material.toLowerCase().trim(),
        row.unit.toLowerCase().trim(),
      ].join('|');
      groups.putIfAbsent(key, () => []).add(row);
    }

    final merged = <DocumentRow>[];
    for (final group in groups.values) {
      if (group.length == 1) { merged.add(group.first); continue; }
      final amounts = group.map((r) =>
        double.tryParse(r.quantity.replaceAll(',', '.'))).toList();
      if (amounts.any((v) => v == null)) { merged.addAll(group); continue; }

      final first = group.first.copy();
      final sourceAmounts = <String, double>{};
      final sourceNames = <String, String>{};
      final sourcePages = <String, String>{};
      final sourceTexts = <String, String>{};
      for (final row in group) {
        if (row.quantitiesBySource.isNotEmpty) {
          row.quantitiesBySource.forEach((id, value) {
            sourceAmounts[id] = (sourceAmounts[id] ?? 0) + value;
          });
          sourceNames.addAll(row.sourcesById);
          sourcePages.addAll(row.pagesById);
          sourceTexts.addAll(row.textsById);
        } else {
          // Поддержка строки, вручную изменённой до объединения.
          for (final id in row.sourceIds) {
            sourceAmounts[id] = (sourceAmounts[id] ?? 0) +
              (double.tryParse(row.quantity.replaceAll(',', '.')) ?? 0) /
              math.max(1, row.sourceIds.length);
            sourceNames[id] = row.source;
            sourcePages[id] = row.page;
            sourceTexts[id] = row.originalText;
          }
        }
      }
      first.quantitiesBySource = sourceAmounts;
      first.sourcesById = sourceNames;
      first.pagesById = sourcePages;
      first.textsById = sourceTexts;
      first.refreshSourceText();
      first.reviewReasons = group.expand((r) => r.reviewReasons).toSet().toList();
      merged.add(first);
    }

    setState(() {
      widget.rows..clear()..addAll(merged);
    });
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Объединение выполнено')),
    );
  }

  String normalizeDimensions(String value) {
    return value.toLowerCase().replaceAll('х', 'x')
      .replaceAll('×', 'x').replaceAll('*', 'x')
      .replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');
  }

  void undoMerge() {
    if (previousRows == null) return;
    setState(() {
      widget.rows..clear()..addAll(previousRows!.map((r) => r.copy()));
      previousRows = null;
    });
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Объединение отменено')),
    );
  }

  Widget buildReviewInfo(DocumentRow row) {
    if (!row.needsReview) return const Text('Проверка не требуется',
      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600));
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Требуется проверка:', style: TextStyle(
          color: Colors.orange, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...row.reviewReasons.map((reason) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('• $reason', style: const TextStyle(color: Colors.deepOrange)),
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Общая таблица (${widget.rows.length})')),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Позиций до объединения: ${widget.initialCount}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Позиций сейчас: ${widget.rows.length}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(onPressed: widget.rows.isEmpty ? null : mergeDuplicates,
              child: const Text('Объединить одинаковые')),
            OutlinedButton(onPressed: previousRows == null ? null : undoMerge,
              child: const Text('Отменить объединение')),
          ]),
        ],
      )),
      Expanded(child: widget.rows.isEmpty
        ? const Center(child: Text('Таблица пока пустая'))
        : ListView.builder(itemCount: widget.rows.length, itemBuilder: (ctx, i) {
            final row = widget.rows[i];
            final pieces = row.calculatedPieces;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: Icon(row.needsReview ? Icons.warning_amber :
                  Icons.check_circle_outline,
                  color: row.needsReview ? Colors.orange : Colors.green),
                title: Text(row.product),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Размеры: ${row.dimensions}'),
                  Text('Количество: ${row.quantity} ${row.unit}'),
                  if (pieces.isNotEmpty) Text('Пересчёт: $pieces шт. (длина ${row.lengthMm} мм)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Длина: ${row.lengthMm} мм'),
                  Text('Толщина: ${row.thickness}'),
                  Text('Материал: ${row.material}'),
                  Text('Источник: ${row.source}'),
                  Text('Лист: ${row.page}'),
                  buildReviewInfo(row),
                  const SizedBox(height: 4),
                  const Text('Нажмите на позицию, чтобы изменить её',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                isThreeLine: true,
                onTap: () => editRow(row),
                trailing: IconButton(icon: const Icon(Icons.delete_outline),
                  tooltip: 'Удалить позицию', onPressed: () => deleteRow(i)),
              ),
            );
          })),
    ])),
  );
}
