import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NabardApp());
}

class Question {
  final String id;
  final String grade;
  final String subject;
  final String question;
  final List<String> options;
  final int answer;
  final String explanation;

  const Question({
    required this.id,
    required this.grade,
    required this.subject,
    required this.question,
    required this.options,
    required this.answer,
    required this.explanation,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        grade: json['grade'] as String,
        subject: json['subject'] as String,
        question: json['question'] as String,
        options: (json['options'] as List).cast<String>(),
        answer: json['answer'] as int,
        explanation: (json['explanation'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'grade': grade,
        'subject': subject,
        'question': question,
        'options': options,
        'answer': answer,
        'explanation': explanation,
      };
}

class NabardApp extends StatelessWidget {
  const NabardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نبرد دانش‌آموزی',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157C8)),
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
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
  List<Question> _questions = [];
  bool _loading = true;
  String _grade = 'همه پایه‌ها';
  String _subject = 'همه درس‌ها';
  int _score = 0;
  int _answered = 0;
  int _bestScore = 0;
  Set<String> _answeredIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final raw = await rootBundle.loadString('assets/questions/questions.json');
      final list = (jsonDecode(raw) as List)
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _questions = list;
        _score = prefs.getInt('score') ?? 0;
        _answered = prefs.getInt('answered') ?? 0;
        _bestScore = prefs.getInt('bestScore') ?? 0;
        _answeredIds = (prefs.getStringList('answeredIds') ?? []).toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('بارگذاری سؤال‌ها انجام نشد: $e');
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('score', _score);
    await prefs.setInt('answered', _answered);
    await prefs.setInt('bestScore', _bestScore);
    await prefs.setStringList('answeredIds', _answeredIds.toList());
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<Question> get _filteredQuestions => _questions.where((q) {
        final gradeOk = _grade == 'همه پایه‌ها' || q.grade == _grade;
        final subjectOk = _subject == 'همه درس‌ها' || q.subject == _subject;
        return gradeOk && subjectOk;
      }).toList();

  Future<void> _startQuiz() async {
    final available = _filteredQuestions;
    if (available.isEmpty) {
      _message('برای این انتخاب هنوز سؤالی ثبت نشده است.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          questions: List.of(available)..shuffle(),
          onAnswer: (question, correct) async {
            setState(() {
              _answered++;
              _answeredIds.add(question.id);
              if (correct) _score += 10;
              if (_score > _bestScore) _bestScore = _score;
            });
            await _saveProgress();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'app': 'نبرد دانش‌آموزی',
      'formatVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'progress': {
        'score': _score,
        'answered': _answered,
        'bestScore': _bestScore,
        'answeredIds': _answeredIds.toList(),
      },
      'questions': _questions.map((q) => q.toJson()).toList(),
    };
    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/nabard-backup.json');
    await file.writeAsString(jsonText, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      text: 'نسخه پشتیبان بازی نبرد دانش‌آموزی',
    );
    // Keep prefs reference alive to make clear this operation exports local progress.
    await prefs.setString('lastBackupAt', DateTime.now().toIso8601String());
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final text = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final progress = decoded['progress'] as Map<String, dynamic>?;
      if (progress == null) throw const FormatException('ساختار فایل معتبر نیست');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('بازیابی نسخه پشتیبان'),
          content: const Text(
            'اطلاعات فعلی پیشرفت با اطلاعات داخل فایل جایگزین می‌شود. ادامه می‌دهید؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('بازیابی'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() {
        _score = (progress['score'] as num?)?.toInt() ?? 0;
        _answered = (progress['answered'] as num?)?.toInt() ?? 0;
        _bestScore = (progress['bestScore'] as num?)?.toInt() ?? 0;
        _answeredIds = ((progress['answeredIds'] as List?) ?? [])
            .map((e) => e.toString())
            .toSet();
      });
      await _saveProgress();
      _message('پیشرفت بازی با موفقیت بازیابی شد.');
    } catch (e) {
      _message('فایل پشتیبان قابل بازیابی نیست: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = <String>{
      'همه درس‌ها',
      ..._questions.map((q) => q.subject),
    }.toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نبرد دانش‌آموزی'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'بازیابی نسخه پشتیبان',
              onPressed: _importBackup,
              icon: const Icon(Icons.restore),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3157C8), Color(0xFF6787ED)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.school, color: Colors.white, size: 42),
                        const SizedBox(height: 12),
                        const Text(
                          'آماده‌ای دانشت را محک بزنی؟',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'بازی کاملاً آفلاین؛ بدون حساب کاربری و بدون اینترنت',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF3157C8),
                          ),
                          onPressed: _startQuiz,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('شروع مسابقه'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _statCard('امتیاز', '$_score', Icons.stars)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('پاسخ‌ها', '$_answered', Icons.quiz)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('بهترین', '$_bestScore', Icons.emoji_events)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'انتخاب مسابقه',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _grade,
                    decoration: const InputDecoration(
                      labelText: 'پایه تحصیلی',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: ['همه پایه‌ها', 'هفتم', 'هشتم', 'نهم']
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _grade = v ?? 'همه پایه‌ها'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _subject,
                    decoration: const InputDecoration(
                      labelText: 'درس',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: subjects
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _subject = v ?? 'همه درس‌ها'),
                  ),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: _exportBackup,
                    icon: const Icon(Icons.backup),
                    label: const Text('تهیه نسخه پشتیبان'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تعداد سؤال‌های داخل برنامه: ${_questions.length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'نسخه آغازین: سؤال‌ها داخل برنامه قرار دارند و برای بازی‌کردن نیازی به اینترنت نیست.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF3157C8)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  final List<Question> questions;
  final Future<void> Function(Question question, bool correct) onAnswer;

  const QuizPage({
    super.key,
    required this.questions,
    required this.onAnswer,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int _index = 0;
  int? _selected;
  bool _checked = false;
  int _correctCount = 0;

  Question get _current => widget.questions[_index];

  Future<void> _choose(int index) async {
    if (_checked) return;
    final correct = index == _current.answer;
    setState(() {
      _selected = index;
      _checked = true;
      if (correct) _correctCount++;
    });
    await widget.onAnswer(_current, correct);
  }

  void _next() {
    if (_index + 1 >= widget.questions.length) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('مسابقه تمام شد!'),
            content: Text(
              'تعداد پاسخ درست: $_correctCount از ${widget.questions.length}\n'
              'امتیاز این دور: ${_correctCount * 10}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(this.context);
                },
                child: const Text('بازگشت به خانه'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    setState(() {
      _index++;
      _selected = null;
      _checked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _current;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('سؤال ${_index + 1} از ${widget.questions.length}'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            LinearProgressIndicator(value: (_index + 1) / widget.questions.length),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(q.grade)),
                Chip(label: Text(q.subject)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              q.question,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 22),
            ...List.generate(q.options.length, (i) {
              final isCorrect = i == q.answer;
              final isSelected = i == _selected;
              Color? background;
              if (_checked && isCorrect) background = Colors.green.shade100;
              if (_checked && isSelected && !isCorrect) background = Colors.red.shade100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: background,
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(q.options[i], style: const TextStyle(fontSize: 17)),
                    leading: CircleAvatar(child: Text(String.fromCharCode(65 + i))),
                    trailing: _checked && isCorrect
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : (_checked && isSelected
                            ? const Icon(Icons.cancel, color: Colors.red)
                            : null),
                    onTap: _checked ? null : () => _choose(i),
                  ),
                ),
              );
            }),
            if (_checked) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selected == q.answer ? 'آفرین! پاسخ درست است.' : 'پاسخ درست: ${q.options[q.answer]}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (q.explanation.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(q.explanation),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.arrow_back),
                label: Text(_index + 1 == widget.questions.length ? 'پایان مسابقه' : 'سؤال بعدی'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
