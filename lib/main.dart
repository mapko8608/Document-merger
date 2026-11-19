
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<PlatformFile> documents = [];
  bool isLoading = false;

  Future<void> addDocuments() async {
    setState(() {
      isLoading = true;
    });

    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xls', 'xlsx'],
      );

      if (!mounted) return;

      setState(() {
        documents.addAll(pickedFiles);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка выбора файлов: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void removeDocument(int index) {
    setState(() {
      documents.removeAt(index);
    });
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
                onPressed: isLoading ? null : addDocuments,
                icon: const Icon(Icons.add),
                label: const Text('Добавить документы'),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Выбрано файлов: ${documents.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: documents.isEmpty
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Обработка документов будет добавлена следующим этапом',
                            ),
                          ),
                        );
                      },
                child: const Text('Открыть общую таблицу'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
