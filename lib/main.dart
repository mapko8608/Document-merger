import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel_plus/excel_plus.dart';

void main() {
  runApp(const DocumentMergerApp());
}

class DocumentMergerApp extends StatelessWidget {
  const DocumentMergerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Merger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class ImportedDocument {
  final String id;
  final PlatformFile file;

  ImportedDocument({
    required this.id,
    required this.file,
  });
}

class DocumentRow {
  String product;
  String dimensions;
  String quantity;
  String unit;
  String thickness;
  String material;
  String lengthMm;
  String source;
  String page;
  String originalText;

  // ID всех исходных документов, из которых получена позиция.
  Set<String> sourceIds;

  // Конкретные причины, по которым позицию нужно проверить.
  List<String> reviewReasons;

  // Отличаем длину из заявки от длины, установленной по умолчанию.
  bool lengthWasSpecified;

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
  });

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
      );

  bool get needsReview => reviewReasons.isNotEmpty;

  bool get isStraightDuct {
    final name = product.toLowerCase();

    final isDuctOrPipe =
        name.contains('воздуховод') ||
        name.contains('труба') ||
        name.contains('трубопровод');

    final isFitting = RegExp(
      r'отвод|тройник|переход|клапан|заглушка|врезка|'
      r'шумоглушитель|крышка|фланец|зонт|утка|'
      r'вставка|дроссель',
    ).hasMatch(name);

    return isDuctOrPipe && !isFitting;
  }

  bool get isRound {
    return RegExp(
      r'ø|⌀|ду\s*[-=]?\s*\d|'
      r'(?<![a-zа-я])d\s*[-=]?\s*\d',
      caseSensitive: false,
    ).hasMatch(dimensions);
  }

  String get calculatedPieces {
    final meters = double.tryParse(quantity.replaceAll(',', '.'));
    final length = double.tryParse(lengthMm.replaceAll(',', '.'));

    if (!isStraightDuct ||
        unit != 'м' ||
        meters == null ||
        length == null ||
        length <= 0) {
      return '';
    }

    return math.max(1, (meters * 1000 / length).ceil()).toString();
  }
}

class ParsedRow {
  final String product;
  final String dimensions;
  final String quantity;
  final String unit;
  final String thickness;
  final String material;
  final String lengthMm;
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

  // Значения по умолчанию.
  String roundLength = '3000';
  String rectangularLength = '1500';

  int documentCounter = 0;

  String createDocumentId() {
    documentCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$documentCounter';
  }

  Future<void> addDocuments() async {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xls', 'xlsx'],
    );

    if (pickedFiles == null || pickedFiles.isEmpty) return;

    final newDocuments = pickedFiles.map((file) {
      return ImportedDocument(
        id: createDocumentId(),
        file: file,
      );
    }).toList();

    setState(() {
      isImporting = true;
      documents.addAll(newDocuments);
    });

    int imported = 0;
    int failed = 0;

    for (final document in newDocuments) {
      final file = document.file;
      final extension = file.extension?.toLowerCase();

      if (extension == 'xlsx' || extension == 'xls') {
        try {
          final bytes = await file.readAsBytes();
          final workbook = Excel.decodeBytes(bytes);

          for (final sheetName in workbook.tables.keys) {
            final sheet = workbook[sheetName];

            if (sheet != null) {
              imported += importSheet(
                sheet.rows,
                file.name,
                sheetName,
                document.id,
              );
            }
          }
        } catch (e) {
          failed++;
          debugPrint('Ошибка чтения ${file.name}: $e');
        }
      }
    }

    if (!mounted) return;

    setState(() {
      isImporting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Добавлено документов: ${newDocuments.length}. '
          'Распознано строк Excel: $imported.'
          '${failed > 0 ? ' Ошибок чтения: $failed.' : ''}',
        ),
      ),
    );
  }

  int importSheet(
    List<List<Data?>> sheetRows,
    String fileName,
    String sheetName,
    String documentId,
  ) {
    int imported = 0;

    for (final row in sheetRows) {
      final cells = row
          .map((cell) => cell?.value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();

      if (cells.isEmpty) continue;

      final text = cells.join(' | ').trim();

      if (text.isEmpty || looksLikeHeader(text)) continue;

      final parsed = parseRow(text, cells);

      if (parsed.product.isEmpty &&
          parsed.dimensions.isEmpty &&
          parsed.quantity.isEmpty) {
        continue;
      }

      String length = parsed.lengthMm;

      final name = parsed.product.toLowerCase();
      final isStraight = (name.contains('воздуховод') ||
              name.contains('труба') ||
              name.contains('трубопровод')) &&
          !RegExp(
            r'отвод|тройник|переход|клапан|заглушка|врезка|'
            r'шумоглушитель|крышка|фланец|зонт|утка|'
            r'вставка|дроссель',
          ).hasMatch(name);

      if (length.isEmpty && isStraight) {
        final round = RegExp(
          r'ø|⌀|ду\s*[-=]?\s*\d|'
          r'(?<![a-zа-я])d\s*[-=]?\s*\d',
          caseSensitive: false,
        ).hasMatch(parsed.dimensions);

        length = round ? roundLength : rectangularLength;
      }

      rows.add(
        DocumentRow(
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
        ),
      );

      imported++;
    }

    return imported;
  }

  bool looksLikeHeader(String text) {
    final value = text.toLowerCase();

    final words = [
      'наименование',
      'название',
      'изделие',
      'размер',
      'количество',
      'кол-во',
      'толщина',
      'материал',
    ];

    int matches = 0;

    for (final word in words) {
      if (value.contains(word)) matches++;
    }

    return matches >= 2;
  }

  String normalizeUnit(String value) {
    final v = value.toLowerCase().replaceAll('.', '').trim();

    if ([
      'м',
      'метр',
      'метры',
      'метров',
      'пм',
      'погм',
      'погонный метр',
      'пог м',
    ].contains(v)) {
      return 'м';
    }

    if ([
      'шт',
      'штука',
      'штуки',
      'штук',
      'pcs',
      'pc',
    ].contains(v)) {
      return 'шт';
    }

    if ([
      'кг',
      'килограмм',
      'килограммы',
    ].contains(v)) {
      return 'кг';
    }

    if (['т', 'тонна', 'тонны'].contains(v)) return 'т';

    return '';
  }

  ParsedRow parseRow(String original, List<String> cells) {
    String working = original.replaceAll('\n', ' ').trim();

    String dimensions = '';
    String thickness = '';
    String material = '';
    String quantity = '';
    String unit = '';
    String lengthMm = '';

    bool lengthWasSpecified = false;

    final reasons = <String>[];

    // Размеры и диаметры.
    final dimensionRegex = RegExp(
      r'(?:Ø|⌀)\s*\d{2,4}(?:[.,]\d+)?'
      r'|(?:ду|d)\s*[-=]?\s*\d{2,4}'
      r'|\d{2,4}\s*[xх×*]\s*\d{2,4}'
      r'(?:\s*[xх×*]\s*\d{2,4})?',
      caseSensitive: false,
    );

    final dimensionMatches = dimensionRegex
        .allMatches(working)
        .map((m) => m.group(0)!.replaceAll(' ', ''))
        .toSet()
        .toList();

    if (dimensionMatches.isNotEmpty) {
      dimensions = dimensionMatches.join('; ');
      working = working.replaceAll(dimensionRegex, ' ');
    } else {
      reasons.add('Не распознаны размеры изделия');
    }

    // Толщина.
    final thicknessRegex = RegExp(
      r'(?:толщина(?:\s+стенки)?|стенка|'
      r'(?<![a-zа-я])b)'
      r'\s*[:=]?\s*(\d{1,2}[.,]\d{1,3})',
      caseSensitive: false,
    );

    final thicknessMatch = thicknessRegex.firstMatch(working);

    if (thicknessMatch != null) {
      thickness = thicknessMatch.group(1)!.replaceAll(',', '.');
      working = working.replaceFirst(thicknessRegex, ' ');
    } else {
      final decimalRegex = RegExp(
        r'(?<!\d)(\d{1,2}[.,]\d{1,3})(?!\d)',
      );

      final possible = decimalRegex.allMatches(working).where((m) {
        final number = double.tryParse(
          m.group(1)!.replaceAll(',', '.'),
        );

        return number != null && number >= 0.3 && number <= 3.0;
      }).toList();

      if (possible.length == 1) {
        thickness = possible.first.group(1)!.replaceAll(',', '.');

        working = working.replaceRange(
          possible.first.start,
          possible.first.end,
          ' ',
        );
      } else if (possible.length > 1) {
        reasons.add('Найдено несколько возможных значений толщины');
      } else {
        reasons.add('Не распознана толщина');
      }
    }

    // Материал.
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
      reasons.add('Не распознан материал');
    }

    // Явно указанная длина.
    final lengthRegex = RegExp(
      r'(?:длина|дл\.?|(?<![a-zа-я])l)'
      r'\s*[:=]?\s*(\d+(?:[.,]\d+)?)\s*(мм|mm|м|m)?',
      caseSensitive: false,
    );

    final lengthMatch = lengthRegex.firstMatch(working);

    if (lengthMatch != null) {
      final value = double.tryParse(
        lengthMatch.group(1)!.replaceAll(',', '.'),
      );

      if (value != null && value > 0) {
        final lengthUnit =
            (lengthMatch.group(2) ?? 'мм').toLowerCase();

        lengthMm = (lengthUnit == 'м' || lengthUnit == 'm'
                ? value * 1000
                : value)
            .toStringAsFixed(0);

        lengthWasSpecified = true;
        working = working.replaceFirst(lengthRegex, ' ');
      }
    }

    // Количество с единицей измерения.
    // Используется отрицательная проверка вместо \b,
    // чтобы корректно обрабатывать русские обозначения.
    final quantityRegex = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*'
      r'(погонных?\s*метр(?:а|ов)?|пог\.?\s*м|'
      r'метр(?:а|ов)?|мм|mm|м|m|шт\.?|штук|pcs?|кг|т)'
      r'(?![а-яa-z])',
      caseSensitive: false,
    );

    final quantityMatch = quantityRegex.firstMatch(working);

    if (quantityMatch != null) {
      quantity = quantityMatch.group(1)!.replaceAll(',', '.');
      unit = normalizeUnit(quantityMatch.group(2)!);
      working = working.replaceFirst(quantityRegex, ' ');
    }

    // Количество и единица в соседних ячейках.
    if (quantity.isEmpty) {
      for (int i = 0; i < cells.length; i++) {
        final currentUnit = normalizeUnit(cells[i]);

        if (currentUnit.isEmpty) continue;

        for (final index in [i - 1, i + 1]) {
          if (index < 0 || index >= cells.length) continue;

          final number = double.tryParse(
            cells[index].replaceAll(',', '.'),
          );

          if (number != null && number > 0) {
            quantity = number.toString();
            unit = currentUnit;
            break;
          }
        }

        if (quantity.isNotEmpty) break;
      }
    }

    // Явное поле количества.
    if (quantity.isEmpty) {
      final markedQuantity = RegExp(
        r'(?:кол-?во|количество|qty)\s*[:=]?\s*(\d+(?:[.,]\d+)?)',
        caseSensitive: false,
      );

      final match = markedQuantity.firstMatch(working);

      if (match != null) {
        quantity = match.group(1)!.replaceAll(',', '.');
        working = working.replaceFirst(markedQuantity, ' ');
      }
    }

    // Числовая ячейка без единицы измерения.
    if (quantity.isEmpty) {
      final numericCells = cells.where(
        (c) => RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(c.trim()),
      ).toList();

      if (numericCells.length == 1) {
        quantity = numericCells.first.replaceAll(',', '.');
        reasons.add('Количество найдено, но единица измерения не определена');
      } else if (numericCells.length > 1) {
        reasons.add('Найдено несколько возможных значений количества');
      } else {
        reasons.add('Не распознано количество');
      }
    }

    if (quantity.isNotEmpty && unit.isEmpty &&
        !reasons.contains(
          'Количество найдено, но единица измерения не определена',
        )) {
      reasons.add('Не определена единица измерения количества');
    }

    // Название изделия.
    String product = working
        .replaceAll('|', ' ')
        .replaceAll(RegExp(r'[,;]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    product = product.replaceAll(
      RegExp(
        r'^(?:наименование|изделие|название)\s*[:=]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    if (product.isEmpty) {
      product = original;
      reasons.add('Не распознано название изделия');
    }

    return ParsedRow(
      product: product,
      dimensions: dimensions,
      quantity: quantity,
      unit: unit,
      thickness: thickness,
      material: material,
      lengthMm: lengthMm,
      lengthWasSpecified: lengthWasSpecified,
      reviewReasons: reasons,
    );
  }  void updateDefaultLengths({
    String? newRoundLength,
    String? newRectangularLength,
  }) {
    setState(() {
      if (newRoundLength != null) {
        roundLength = newRoundLength;
      }

      if (newRectangularLength != null) {
        rectangularLength = newRectangularLength;
      }

      // Обновляем длину уже загруженных прямых воздуховодов и труб,
      // если длина не была явно указана в заявке.
      for (final row in rows) {
        if (!row.isStraightDuct || row.lengthWasSpecified) continue;

        row.lengthMm = row.isRound
            ? roundLength
            : rectangularLength;
      }
    });
  }

  Future<void> deleteDocument(ImportedDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text(
          'Документ «${document.file.name}» будет удалён из списка. '
          'Все позиции, полученные из него, также будут удалены. '
          'Позиции из других документов останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      documents.removeWhere((item) => item.id == document.id);

      rows.removeWhere(
        (row) => row.sourceIds.contains(document.id),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Документ и его позиции удалены'),
      ),
    );
  }

  void openTable() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TablePage(
          rows: rows,
          initialCount: rows.length,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }

  Widget lengthSelector({
    required String title,
    required String selected,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: options.map((value) {
            return ChoiceChip(
              label: Text('$value мм'),
              selected: selected == value,
              onSelected: (_) => onSelected(value),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обработка документов'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: isImporting ? null : addDocuments,
                icon: const Icon(Icons.add),
                label: const Text('Добавить документы'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: openTable,
                icon: const Icon(Icons.table_chart),
                label: Text(
                  'Открыть общую таблицу (${rows.length})',
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const Text(
                'Длина по умолчанию для прямых воздуховодов и труб',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              lengthSelector(
                title: 'Круглые',
                selected: roundLength,
                options: const ['3000', '1250'],
                onSelected: (value) {
                  updateDefaultLengths(newRoundLength: value);
                },
              ),
              const SizedBox(height: 12),
              lengthSelector(
                title: 'Прямоугольные',
                selected: rectangularLength,
                options: const ['1250', '1500'],
                onSelected: (value) {
                  updateDefaultLengths(newRectangularLength: value);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Если длина указана в заявке, используется она. '
                'Выбранная длина применяется только при отсутствии '
                'явного значения.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const Divider(height: 24),
              if (isImporting) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
              ],
              Text('Добавленные документы: ${documents.length}'),
              const SizedBox(height: 8),
              Expanded(
                child: documents.isEmpty
                    ? const Center(
                        child: Text('Документы пока не добавлены'),
                      )
                    : ListView.builder(
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final document = documents[index];
                          final file = document.file;

                          final count = rows.where(
                            (row) => row.sourceIds.contains(document.id),
                          ).length;

                          return Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.insert_drive_file,
                              ),
                              title: Text(file.name),
                              subtitle: Text(
                                '${file.extension?.toUpperCase() ?? 'Файл'}'
                                ' • Позиций: $count',
                              ),
                              trailing: IconButton(
                                tooltip: 'Удалить документ',
                                icon: const Icon(
                                  Icons.delete_outline,
                                ),
                                onPressed: isImporting
                                    ? null
                                    : () => deleteDocument(document),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Text(
                'PDF пока добавляется в список, но распознавание '
                'содержимого PDF ещё не подключено.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TablePage extends StatefulWidget {
  final List<DocumentRow> rows;
  final int initialCount;
  final VoidCallback onChanged;

  const TablePage({
    super.key,
    required this.rows,
    required this.initialCount,
    required this.onChanged,
  });

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

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Редактирование позиции'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              editField(product, 'Название изделия'),
              editField(dimensions, 'Размеры'),
              editField(quantity, 'Количество'),
              editField(unit, 'Единица измерения (м, шт, кг)'),
              editField(thickness, 'Толщина'),
              editField(material, 'Материал'),
              editField(length, 'Длина одного изделия (мм)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        row.product = product.text.trim();
        row.dimensions = dimensions.text.trim();
        row.quantity = quantity.text.trim();
        row.unit = unit.text.trim().toLowerCase();
        row.thickness = thickness.text.trim();
        row.material = material.text.trim();
        row.lengthMm = length.text.trim();

        // Ручное изменение длины считаем явным значением.
        row.lengthWasSpecified = row.lengthMm.isNotEmpty;

        // После ручного исправления снимаем предупреждения.
        row.reviewReasons.clear();
      });

      widget.onChanged();
    }

    product.dispose();
    dimensions.dispose();
    quantity.dispose();
    unit.dispose();
    thickness.dispose();
    material.dispose();
    length.dispose();
  }

  Widget editField(
    TextEditingController controller,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void deleteRow(int index) {
    setState(() {
      widget.rows.removeAt(index);
      previousRows = null;
    });

    widget.onChanged();
  }  void mergeDuplicates() {
    previousRows = widget.rows.map((row) => row.copy()).toList();

    final Map<String, List<DocumentRow>> groups = {};

    for (final row in widget.rows) {
      final key = [
        row.product.toLowerCase().trim(),
        row.dimensions.toLowerCase().trim(),
        row.thickness.toLowerCase().trim(),
        row.material.toLowerCase().trim(),
        row.unit.toLowerCase().trim(),
      ].join('|');

      groups.putIfAbsent(key, () => []).add(row);
    }

    final List<DocumentRow> merged = [];

    for (final group in groups.values) {
      if (group.length == 1) {
        merged.add(group.first);
        continue;
      }

      final quantities = group
          .map(
            (row) => double.tryParse(
              row.quantity.replaceAll(',', '.'),
            ),
          )
          .toList();

      if (quantities.any((value) => value == null)) {
        merged.addAll(group);
        continue;
      }

      final first = group.first.copy();

      final total = quantities.fold<double>(
        0,
        (sum, value) => sum + value!,
      );

      first.quantity = total.toString();

      first.source = group
          .map((row) => row.source)
          .where((value) => value.isNotEmpty)
          .toSet()
          .join('; ');

      first.page = group
          .map((row) => row.page)
          .where((value) => value.isNotEmpty)
          .toSet()
          .join('; ');

      first.originalText = group
          .map((row) => row.originalText)
          .where((value) => value.isNotEmpty)
          .join('\n---\n');

      first.sourceIds = group
          .expand((row) => row.sourceIds)
          .toSet();

      first.reviewReasons = group
          .expand((row) => row.reviewReasons)
          .toSet()
          .toList();

      merged.add(first);
    }

    setState(() {
      widget.rows
        ..clear()
        ..addAll(merged);
    });

    widget.onChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Объединение выполнено'),
      ),
    );
  }

  void undoMerge() {
    if (previousRows == null) return;

    setState(() {
      widget.rows
        ..clear()
        ..addAll(
          previousRows!.map((row) => row.copy()),
        );

      previousRows = null;
    });

    widget.onChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Объединение отменено'),
      ),
    );
  }

  Widget buildReviewInfo(DocumentRow row) {
    if (!row.needsReview) {
      return const Text(
        'Проверка не требуется',
        style: TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Требуется проверка:',
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...row.reviewReasons.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $reason',
                style: const TextStyle(
                  color: Colors.deepOrange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Общая таблица (${widget.rows.length})'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Позиций до объединения: ${widget.initialCount}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Позиций сейчас: ${widget.rows.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: widget.rows.isEmpty
                            ? null
                            : mergeDuplicates,
                        child: const Text('Объединить одинаковые'),
                      ),
                      OutlinedButton(
                        onPressed: previousRows == null
                            ? null
                            : undoMerge,
                        child: const Text('Отменить объединение'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.rows.isEmpty
                  ? const Center(
                      child: Text('Таблица пока пустая'),
                    )
                  : ListView.builder(
                      itemCount: widget.rows.length,
                      itemBuilder: (context, index) {
                        final row = widget.rows[index];
                        final pieces = row.calculatedPieces;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Icon(
                              row.needsReview
                                  ? Icons.warning_amber
                                  : Icons.check_circle_outline,
                              color: row.needsReview
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                            title: Text(row.product),
                            subtitle: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('Размеры: ${row.dimensions}'),
                                Text(
                                  'Количество: ${row.quantity} '
                                  '${row.unit}',
                                ),
                                if (pieces.isNotEmpty)
                                  Text(
                                    'Пересчёт: $pieces шт. '
                                    '(длина ${row.lengthMm} мм)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                Text('Длина: ${row.lengthMm} мм'),
                                Text('Толщина: ${row.thickness}'),
                                Text('Материал: ${row.material}'),
                                Text('Источник: ${row.source}'),
                                Text('Лист: ${row.page}'),
                                buildReviewInfo(row),
                                const SizedBox(height: 4),
                                const Text(
                                  'Нажмите на позицию, чтобы изменить её',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            onTap: () => editRow(row),
                            trailing: IconButton(
                              tooltip: 'Удалить позицию',
                              icon: const Icon(
                                Icons.delete_outline,
                              ),
                              onPressed: () => deleteRow(index),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
