import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const DocumentMergerApp());
}

class DocumentMergerApp extends StatelessWidget {
  const DocumentMergerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Merger',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class DocumentItem {
  final String name;
  final String extension;

  DocumentItem(this.name, this.extension);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<DocumentItem> documents = [];

  Future<void> addDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xls', 'xlsx'],
    );

    if (result == null) return;

    setState(() {
      for (final file in result.files) {
        documents.add(
          DocumentItem(
            file.name,
            file.extension?.toUpperCase() ?? '',
          ),
        );
      }
    });
  }

  IconData fileIcon(String extension) {
    if (extension == 'PDF') {
      return Icons.picture_as_pdf;
    }
    return Icons.table_chart;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Merger'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: addDocuments,
                icon: const Icon(Icons.add),
                label: const Text('Добавить документы'),
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Загруженные документы',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: documents.isEmpty
                  ? const Center(
                      child: Text('Документы пока не загружены'),
                    )
                  : ListView.builder(
                      itemCount: documents.length,
                      itemBuilder: (context, index) {
                        final item = documents[index];

                        return Card(
                          child: ListTile(
                            leading: Icon(
                              fileIcon(item.extension),
                              size: 32,
                            ),
                            title: Text(item.name),
                            subtitle: Text(item.extension),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                setState(() {
                                  documents.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: documents.isEmpty ? null : () {},
                icon: const Icon(Icons.table_chart),
                label: const Text('Открыть общую таблицу'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
