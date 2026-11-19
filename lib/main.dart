
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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

  DocumentRow({
    this.product = '',
    this.dimensions = '',
    this.quantity = '1',
    this.thickness = '',
    this.material = '',
    this.source = '',
    this.page = '',
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

  bool isLoading = false;

  Future<void> addDocuments() async {
    setState(() => isLoading = true);

    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xls', 'xlsx'],
      );

      if (pickedFiles.isEmpty) return;

      int imported = 0;
      int failed = 0;

      for (final file in pickedFiles) {
        documents.add(file);

        final extension = file.extension?.toLowerCase();

        if (extension == 'xls' || extension == 'xlsx') {
          try {
            final bytes = await file.readAsBytes();
            final workbook = Excel.decodeBytes(bytes);

            for (final sheetName in workbook.tables.keys) {
              final sheet = workbook[sheetName];

              if (sheet == null) continue;

              imported += importSheet(
                sheet.rows,
                file.name,
                sheetName,
              );
            }
          } catch (e) {
            failed++;
          }
        }
      }

      if (!mounted) return;

      setState(() {});

      String message = 'Добавлено позиций: $imported';

      if (failed > 0) {
        message += '. Не удалось прочитать файлов: $failed';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выбора файлов: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  int importSheet(
    List<List<Data?>> sheetRows,
    String fileName,
    String sheetName,
  ) {
    if (sheetRows.isEmpty) return 0;

    int imported = 0;
    int? headerIndex;
    final Map<String, int> columns = {};

    final aliases = {
      'product': [
        'изделие',
        'наименование',
        'название',
        'позиция',
        'деталь',
        'товар',
        'product',
        'name',
        'item',
      ],
      'dimensions': [
        'размер',
        'габарит',
        'сечение',
        'dimensions',
        'size',
      ],
      'quantity': [
        'количество',
        'кол-во',
        'колво',
        'qty',
        'quantity',
        'count',
        'штук',
      ],
      'thickness': [
        'толщина',
        'толщ',
        'thickness',
        'gauge',
      ],
      'material': [
        'материал',
        'марка стали',
        'material',
        'steel',
      ],
    };

    String normalize(String value) {
      return value
          .toLowerCase()
          .replaceAll('ё', 'е')
          .replaceAll(RegExp(r'[^a-zа-я0-9]'), '');
    }

    // Ищем строку с заголовками в первых 15 строках.
    int bestScore = 0;

    for (int r = 0; r < sheetRows.length && r < 15; r++) {
      final values = sheetRows[r]
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();

      final found = <String, int>{};

      for (int c = 0; c < values.length; c++) {
        final value = normalize(values[c]);

        for (final field in aliases.keys) {
          if (found.containsKey(field)) continue;

          final matches = aliases[field]!.any(
            (alias) => value.contains(normalize(alias)),
          );

          if (matches) {
            found[field] = c;
          }
        }
      }

      if (found.length > bestScore) {
        bestScore = found.length;
        headerIndex = r;
        columns
          ..clear()
          ..addAll(found);
      }
    }

    // Если заголовки не найдены, сохраняем содержимое строк
    // для последующей проверки пользователем.
    final startRow = headerIndex == null ? 0 : headerIndex + 1;

    for (int r = startRow; r < sheetRows.length; r++) {
      final values = sheetRows[r]
          .map((cell) => cell?.value?.toString().trim() ?? '')
          .toList();

      if (values.every((value) => value.isEmpty)) {
        continue;
      }

      String getValue(String field) {
        final index = columns[field];

        if (index == null || index >= values.length) {
          return '';
        }

        return values[index];
      }

      String product = getValue('product');

      // Если название не определено, сохраняем всю строку
      // в поле изделия, чтобы не потерять исходные данные.
      if (product.isEmpty) {
        product = values
            .where((value) => value.isNotEmpty)
            .join(' | ');
      }

      final dimensions = getValue('dimensions');
      final quantity = getValue('quantity');
      final thickness = getValue('thickness');
      final material = getValue('material');

      rows.add(
        DocumentRow(
          product: product,
          dimensions: dimensions,
          quantity: quantity.isEmpty ? '1' : quantity,
          thickness: thickness,
          material: material,
          source: fileName,
          page: sheetName,
        ),
      );

      imported++;
    }

    return imported;
  }

  void removeDocument(int index) {
    setState(() => documents.removeAt(index));
  }

  void addRow() {
    setState(() {
      rows.add(DocumentRow());
    });
  }

  void removeRow(int index) {
    setState(() => rows.removeAt(index));
  }

  void editRow(int index) {
    final row = rows[index];

    final productController = TextEditingController(text: row.product);
    final dimensionsController =
        TextEditingController(text: row.dimensions);
    final quantityController = TextEditingController(text: row.quantity);
    final thicknessController = TextEditingController(text: row.thickness);
    final materialController = TextEditingController(text: row.material);
    final sourceController = TextEditingController(text: row.source);
    final pageController = TextEditingController(text: row.page);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Редактирование позиции ${index + 1}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildField('Изделие', productController),
                buildField('Размеры', dimensionsController),
                buildField('Количество', quantityController),
                buildField('Толщина', thicknessController),
                buildField('Материал', materialController),
                buildField('Исходный файл', sourceController),
                buildField('Лист / страница', pageController),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  row.product = productController.text;
                  row.dimensions = dimensionsController.text;
                  row.quantity = quantityController.text;
                  row.thickness = thicknessController.text;
                  row.material = materialController.text;
                  row.source = sourceController.text;
                  row.page = pageController.text;
                });

                Navigator.pop(dialogContext);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  Widget buildField(
    String label,
    TextEditingController controller,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Merger'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : addDocuments,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить документы'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TablePage(
                          rows: rows,
                          onAddRow: addRow,
                          onEditRow: editRow,
                          onRemoveRow: removeRow,
                        ),
                      ),
                    );
                  },
                  child: const Text('Открыть общую таблицу'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Выбрано файлов: ${documents.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Позиций в таблице: ${rows.length}'),
              const SizedBox(height: 10),
              Expanded(
                child: documents.isEmpty
                    ? const Center(
                        child: Text('Документы пока не добавлены'),
                      )
                    : ListView.builder(
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final document = documents[index];
                          final isPdf = document.name
                              .toLowerCase()
                              .endsWith('.pdf');

                          return Card(
                            child: ListTile(
                              leading: Icon(
                                isPdf
                                    ? Icons.picture_as_pdf
                                    : Icons.table_chart,
                              ),
                              title: Text(
                                document.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                document.extension?.toUpperCase() ??
                                    'Документ',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => removeDocument(index),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
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
  final VoidCallback onAddRow;
  final Function(int) onEditRow;
  final Function(int) onRemoveRow;

  const TablePage({
    super.key,
    required this.rows,
    required this.onAddRow,
    required this.onEditRow,
    required this.onRemoveRow,
  });

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Общая таблица'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          widget.onAddRow();
          setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('Добавить строку'),
      ),
      body: widget.rows.isEmpty
          ? const Center(
              child: Text(
                'Таблица пока пустая.\n'
                'Добавьте Excel-файл или нажмите «Добавить строку».',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: 90,
              ),
              itemCount: widget.rows.length,
              itemBuilder: (context, index) {
                final row = widget.rows[index];

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      row.product.isEmpty
                          ? 'Новая позиция'
                          : row.product,
                    ),
                    subtitle: Text(
                      'Размеры: ${row.dimensions.isEmpty ? "—" : row.dimensions}\n'
                      'Количество: ${row.quantity}\n'
                      'Толщина: ${row.thickness.isEmpty ? "—" : row.thickness}\n'
                      'Материал: ${row.material.isEmpty ? "—" : row.material}\n'
                      'Источник: ${row.source.isEmpty ? "—" : row.source}\n'
                      'Лист / страница: ${row.page.isEmpty ? "—" : row.page}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          widget.onEditRow(index);
                          setState(() {});
                        } else if (value == 'delete') {
                          widget.onRemoveRow(index);
                          setState(() {});
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Редактировать'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
