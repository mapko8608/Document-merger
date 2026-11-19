
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

class DocumentRow {
  String product;
  String dimensions;
  String quantity;
  String thickness;
  String material;
  String source;
  String page;
  String originalText;
  bool needsReview;

  DocumentRow({
    required this.product,
    required this.dimensions,
    required this.quantity,
    required this.thickness,
    required this.material,
    required this.source,
    required this.page,
    required this.originalText,
    this.needsReview = false,
  });

  DocumentRow copy() {
    return DocumentRow(
      product: product,
      dimensions: dimensions,
      quantity: quantity,
      thickness: thickness,
      material: material,
      source: source,
      page: page,
      originalText: originalText,
      needsReview: needsReview,
    );
  }
}

class ParsedRow {
  final String product;
  final String dimensions;
  final String quantity;
  final String thickness;
  final String material;
  final bool needsReview;

  ParsedRow({
    required this.product,
    required this.dimensions,
    required this.quantity,
    required this.thickness,
    required this.material,
    required this.needsReview,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<PlatformFile> documents = [];
  final List<DocumentRow> rows = [];

  bool isImporting = false;

  Future<void> addDocuments() async {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xls', 'xlsx'],
    );

    if (pickedFiles == null || pickedFiles.isEmpty) return;

    setState(() {
      isImporting = true;
      documents.addAll(pickedFiles);
    });

    int imported = 0;

    for (final file in pickedFiles) {
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
              );
            }
          }
        } catch (e) {
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
          'Добавлено документов: ${pickedFiles.length}. '
          'Распознано строк Excel: $imported',
        ),
      ),
    );
  }

  int importSheet(
    List<List<Data?>> sheetRows,
    String fileName,
    String sheetName,
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

      rows.add(
        DocumentRow(
          product: parsed.product,
          dimensions: parsed.dimensions,
          quantity: parsed.quantity,
          thickness: parsed.thickness,
          material: parsed.material,
          source: fileName,
          page: sheetName,
          originalText: text,
          needsReview: parsed.needsReview,
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

  ParsedRow parseRow(String original, List<String> cells) {
    final text = original.replaceAll('\n', ' ').trim();
    String working = text;

    String dimensions = '';
    String thickness = '';
    String material = '';
    String quantity = '';

    bool needsReview = false;

    // Диаметры и размеры.
    // Примеры: Ø250, ⌀250, D250, Ду250, 500x300.
    final dimensionRegex = RegExp(
      r'(?:Ø|⌀)\s*\d{2,4}(?:[.,]\d+)?'
      r'|\b(?:ду|d)\s*[-=]?\s*\d{2,4}\b'
      r'|\d{2,4}\s*[xх×*]\s*\d{2,4}'
      r'(?:\s*[xх×*]\s*\d{2,4})?',
      caseSensitive: false,
    );

    final dimensionMatches = dimensionRegex
        .allMatches(working)
        .map((match) => match.group(0)!.replaceAll(' ', ''))
        .toSet()
        .toList();

    if (dimensionMatches.isNotEmpty) {
      dimensions = dimensionMatches.join('; ');
      working = working.replaceAll(dimensionRegex, ' ');
    }

    // Толщина с явным обозначением.
    final markedThickness = RegExp(
      r'(?:толщ(?:ина)?|(?<![а-яa-z])s|(?<![а-яa-z])t|δ)'
      r'\s*[:=]?\s*(\d{1,2}[.,]\d{1,3})',
      caseSensitive: false,
    );

    final markedMatch = markedThickness.firstMatch(working);

    if (markedMatch != null) {
      thickness = markedMatch.group(1)!.replaceAll(',', '.');
      working = working.replaceFirst(markedThickness, ' ');
    } else {
      // Без обозначения принимаем только вероятную толщину.
      final decimalRegex = RegExp(
        r'(?<!\d)(\d{1,2}[.,]\d{1,3})(?!\d)',
      );

      final decimalMatches = decimalRegex.allMatches(working).toList();

      final possibleThicknesses = <RegExpMatch>[];

      for (final match in decimalMatches) {
        final number = double.tryParse(
          match.group(1)!.replaceAll(',', '.'),
        );

        if (number != null && number >= 0.3 && number <= 3.0) {
          possibleThicknesses.add(match);
        }
      }

      if (possibleThicknesses.length == 1) {
        final match = possibleThicknesses.first;
        final number = double.parse(
          match.group(1)!.replaceAll(',', '.'),
        );

        thickness = number.toStringAsFixed(2);

        working = working.replaceRange(
          match.start,
          match.end,
          ' ',
        );
      } else if (possibleThicknesses.length > 1) {
        needsReview = true;
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

    // Количество по явным обозначениям.
    final quantityPatterns = [
      RegExp(
        r'(?:кол-?во|количество|qty)\s*[:=]?\s*(\d+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(\d+)\s*(?:шт\.?|штук|pcs?)\b',
        caseSensitive: false,
      ),
    ];

    for (final pattern in quantityPatterns) {
      final match = pattern.firstMatch(working);

      if (match != null) {
        quantity = match.group(1)!;
        working = working.replaceFirst(pattern, ' ');
        break;
      }
    }

    // Если количество записано отдельной ячейкой
    // без слов "шт." или "количество".
    if (quantity.isEmpty) {
      final numericCells = <String>[];

      for (final cell in cells) {
        final value = cell.trim();

        if (RegExp(r'^\d{1,5}$').hasMatch(value)) {
          numericCells.add(value);
        }
      }

      if (numericCells.length == 1) {
        quantity = numericCells.first;

        // Удаляем найденное количество из текста,
        // чтобы оно не попало в название изделия.
        final escaped = RegExp.escape(quantity);
        working = working.replaceFirst(
          RegExp(r'(?<!\d)' + escaped + r'(?!\d)'),
          ' ',
        );
      } else if (numericCells.length > 1) {
        needsReview = true;
      }
    }

    // Очищаем название.
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

    // Не угадываем отсутствующие параметры.
    if (product.isEmpty ||
        dimensions.isEmpty ||
        quantity.isEmpty ||
        thickness.isEmpty ||
        material.isEmpty) {
      needsReview = true;
    }

    if (product.isEmpty) {
      product = text;
      needsReview = true;
    }

    return ParsedRow(
      product: product,
      dimensions: dimensions,
      quantity: quantity,
      thickness: thickness,
      material: material,
      needsReview: needsReview,
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
                label: Text('Открыть общую таблицу (${rows.length})'),
              ),
              const SizedBox(height: 16),
              if (isImporting) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Добавленные документы: ${documents.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: documents.isEmpty
                    ? const Center(
                        child: Text('Документы пока не добавлены'),
                      )
                    : ListView.builder(
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final file = documents[index];

                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(file.name),
                              subtitle: Text(
                                file.extension?.toUpperCase() ?? 'Файл',
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Text(
                'PDF пока добавляется в список, '
                'но распознавание содержимого PDF ещё не подключено.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
    final thickness = TextEditingController(text: row.thickness);
    final material = TextEditingController(text: row.material);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Редактирование позиции'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                editField(product, 'Название изделия'),
                editField(dimensions, 'Размеры'),
                editField(quantity, 'Количество'),
                editField(thickness, 'Толщина'),
                editField(material, 'Материал'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        row.product = product.text;
        row.dimensions = dimensions.text;
        row.quantity = quantity.text;
        row.thickness = thickness.text;
        row.material = material.text;
        row.needsReview = false;
      });

      widget.onChanged();
    }

    product.dispose();
    dimensions.dispose();
    quantity.dispose();
    thickness.dispose();
    material.dispose();
  }

  Widget editField(TextEditingController controller, String label) {
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
    });

    widget.onChanged();
  }

  void mergeDuplicates() {
    previousRows = widget.rows.map((row) => row.copy()).toList();

    final Map<String, List<DocumentRow>> groups = {};

    // Прежнее правило:
    // название + размеры + толщина + материал.
    for (final row in widget.rows) {
      final key = [
        row.product.toLowerCase().trim(),
        row.dimensions.toLowerCase().trim(),
        row.thickness.toLowerCase().trim(),
        row.material.toLowerCase().trim(),
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
          .map((row) => int.tryParse(row.quantity))
          .toList();

      if (quantities.any((value) => value == null)) {
        merged.addAll(group);
        continue;
      }

      final first = group.first.copy();

      final total = quantities.fold<int>(
        0,
        (sum, value) => sum + value!,
      );

      first.quantity = total.toString();
      first.source = group.map((r) => r.source).toSet().join('; ');
      first.page = group.map((r) => r.page).toSet().join('; ');
      first.needsReview = group.any((r) => r.needsReview);

      merged.add(first);
    }

    setState(() {
      widget.rows
        ..clear()
        ..addAll(merged);
    });

    widget.onChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Объединение выполнено')),
    );
  }

  void undoMerge() {
    if (previousRows == null) return;

    setState(() {
      widget.rows
        ..clear()
        ..addAll(previousRows!.map((row) => row.copy()));

      previousRows = null;
    });

    widget.onChanged();
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
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Позиций после объединения: ${widget.rows.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: mergeDuplicates,
                        child: const Text('Объединить одинаковые'),
                      ),
                      OutlinedButton(
                        onPressed:
                            previousRows == null ? null : undoMerge,
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Размеры: ${row.dimensions}'),
                                Text('Количество: ${row.quantity}'),
                                Text('Толщина: ${row.thickness}'),
                                Text('Материал: ${row.material}'),
                                Text('Источник: ${row.source}'),
                                Text('Лист: ${row.page}'),
                                if (row.needsReview)
                                  const Text(
                                    'Проверить',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            isThreeLine: true,
                            onTap: () => editRow(row),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
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
