import 'package:flutter/material.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';

class ImportScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  final ValueChanged<bool> onBusyChanged;

  const ImportScreen({
    super.key,
    required this.onNavigate,
    required this.onBusyChanged,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String step = 'Step 1 of 2';
  bool isUploaded = false;
  String fileName = '';
  bool isError = false;
  String errorText = '';
  String summary = '';
  String meetingTitle = '';
  String alreadyAddedText = '';
  bool alreadyAdded = false;
  bool canImport = false;
  bool busy = false;
  List<Map<String, dynamic>> rows = [];

  String cellText(Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    return v.toString().trim();
  }

  // cell ki date -> '2026-10-13'
  String? cellDate(Data? cell) {
    final v = cell?.value;
    if (v is DateCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is DateTimeCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    return null;
  }

  // cell ka time -> '11:00'
  String? cellTime(Data? cell) {
    final v = cell?.value;
    if (v is TimeCellValue) {
      return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }
    if (v is DateTimeCellValue) {
      return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }
    return null;
  }

  Future<void> pickFile() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (!mounted) return;

      // user ne cancel kar diya
      if (file == null) return;

      setState(() {
        step = 'Step 1 of 2';
        isUploaded = false;
        canImport = false;
        isError = false;
        errorText = '';
        alreadyAddedText = '';
        alreadyAdded = false;
        rows = [];
        fileName = '';
        summary = '';
        meetingTitle = '';
      });
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        throw const FormatException('No worksheet was found in this file.');
      }
      final sheet = excel.tables[excel.tables.keys.first]!;
      final sheetRows = sheet.rows;
      final title = sheetRows.isEmpty || sheetRows.first.isEmpty
          ? ''
          : cellText(sheetRows.first.first);
      final parsedTitle = title.isEmpty
          ? file.name.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '')
          : title;

      final list = <Map<String, dynamic>>[];

      int groupNo = 0;
      String lastRow = '';
      String lastDate = '';

      for (var index = 0; index < sheetRows.length; index++) {
        final row = sheetRows[index];
        if (row.length < 8) continue;

        final date = cellDate(row[7]);
        final time = cellTime(row[6]);

        if (date == null || time == null) continue;
        final requiredCells = {
          1: 'a reg #',
          2: 'a student name',
          3: 'a supervisor',
          4: 'a project',
        };
        for (final entry in requiredCells.entries) {
          if (cellText(row[entry.key]).isEmpty) {
            throw FormatException(
              'Row ${index + 1} is missing ${entry.value}.',
            );
          }
        }
        final key = '$date|$time|${cellText(row[4])}|${cellText(row[3])}';

        if (date != lastDate) {
          groupNo = 0;
          lastDate = date;
        }

        if (key != lastRow) {
          groupNo++;
          lastRow = key;
        }

        list.add({
          'group_no': groupNo,
          'meeting_date': date,
          'meeting_time': time,
          'project': cellText(row[4]),
          'supervisor': cellText(row[3]),
          'reg_no': cellText(row[1]),
          'student_name': cellText(row[2]),
          'tech': cellText(row[5]),
        });
      }
      if (list.isEmpty) {
        throw const FormatException('No valid rows were found in this file.');
      }

      final dates = list.map((r) => r['meeting_date'] as String).toSet();
      final days = dates.length;
      final groups = list
          .map(
            (r) =>
                '${r['meeting_date']}|${r['meeting_time']}|${r['project']}|${r['supervisor']}',
          )
          .toSet()
          .length;

      final existingDates = await MeetingService.fetchExistingDates(
        parsedTitle,
        dates.toList(),
      );
      if (!mounted) return;
      final existingCount = dates.intersection(existingDates).length;
      setState(() {
        rows = list;
        meetingTitle = parsedTitle;
        fileName = file.name;
        summary = '$days days | $groups groups | ${list.length} students';
        isUploaded = true;
        isError = false;
        step = 'Step 2 of 2';
        alreadyAdded = existingCount == days;
        alreadyAddedText = alreadyAdded
            ? 'Already added'
            : existingCount > 0
            ? '$existingCount of $days days already added. The rest will be imported.'
            : '';
        canImport = !alreadyAdded;
      });
    } on PostgrestException catch (e) {
      showImportError(e.message);
    } on FormatException catch (e) {
      showImportError(e.message);
    } catch (e) {
      showImportError('Error: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showImportError(String message) {
    if (!mounted) return;
    setState(() {
      isError = true;
      errorText = message;
      canImport = false;
    });
  }

  Future<void> confirmImport() async {
    if (!canImport || busy) return;
    setState(() => busy = true);
    try {
      widget.onBusyChanged(true);
      final result = await MeetingService.importSchedule(meetingTitle, rows);
      if (!mounted) return;
      if (result.isEmpty) {
        throw const FormatException('No import result was returned.');
      }
      if (result.every((item) => item['already_added'] == true)) {
        setState(() {
          alreadyAdded = true;
          alreadyAddedText = 'Already added';
          canImport = false;
        });
        return;
      }
      final added = result
          .where((item) => item['already_added'] != true)
          .length;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$added meeting(s) added')));
      setState(() {
        step = 'Step 1 of 2';
        isUploaded = false;
        canImport = false;
        isError = false;
        fileName = '';
        meetingTitle = '';
        summary = '';
        rows = [];
        errorText = '';
        alreadyAddedText = '';
        alreadyAdded = false;
      });
      widget.onBusyChanged(false);
      widget.onNavigate(kMeetings);
    } on PostgrestException catch (e) {
      showImportError(e.message);
    } on FormatException catch (e) {
      showImportError(e.message);
    } catch (e) {
      showImportError('Import error: $e');
    } finally {
      widget.onBusyChanged(false);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(18, 60, 18, 18),
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(text: step),
                CustomText(
                  text: 'Import schedule',
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),

                SizedBox(height: 10),

                GestureDetector(
                  onTap: busy ? null : pickFile,
                  child: AnimatedContainer(
                    width: double.infinity,
                    padding: EdgeInsets.all(48),
                    duration: Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        children: [
                          isUploaded
                              ? Column(
                                  children: [
                                    CustomText(
                                      text: fileName,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    CustomText(text: summary),
                                    if (alreadyAddedText.isNotEmpty)
                                      CustomText(
                                        text: alreadyAddedText,
                                        color: alreadyAdded ? Colors.red : null,
                                      ),
                                    CustomText(
                                      text: 'Tap to choose another Excel file',
                                    ),
                                  ],
                                )
                              : CustomText(text: 'Tap to upload Excel file'),
                        ],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 10),

                isError
                    ? AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 255, 223, 221),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: CustomText(text: errorText, color: Colors.red),
                      )
                    : SizedBox(),
                SizedBox(height: 10),
                Button(
                  enabled: canImport && !busy,
                  text: 'Confirm import',
                  onTap: confirmImport,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
