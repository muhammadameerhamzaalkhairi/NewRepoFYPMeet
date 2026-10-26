// Preserve the existing widget filename required by the feature spec.
// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';

class Livedetailmeetingcard extends StatelessWidget {
  final int number;
  final String title;
  final String status;
  final String supervisor;
  final String time;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onExpand;
  final String? timerText;
  final String? totalText;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;
  final bool canStart;
  final bool canEnd;
  final List<Map<String, dynamic>> students;

  const Livedetailmeetingcard({
    super.key,
    required this.number,
    required this.title,
    required this.status,
    required this.supervisor,
    required this.time,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.onExpand,
    this.timerText,
    this.totalText,
    this.onStart,
    this.onEnd,
    this.canStart = false,
    this.canEnd = false,
    this.students = const [],
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.toLowerCase();
    final timing = normalizedStatus == 'running'
        ? timerText
        : normalizedStatus == 'done'
        ? totalText
        : null;
    return GestureDetector(
      onTap: onTap,

      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFDDF35C) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(20),
        ),

        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 25,
                    height: 25,
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      color: Colors.white,
                      border: Border.all(),
                    ),
                    child: isSelected
                        ? Container(
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(50),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(width: 10),
                  CustomText(
                    text: number.toString(),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomText(
                          text: title,
                          height: 1,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        SizedBox(height: 5),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 219, 219, 219),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: CustomText(text: status, fontSize: 12),
                            ),

                            CustomText(
                              text: '$supervisor - $time',
                              fontSize: 12,
                            ),
                            if (timing != null)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(
                                    255,
                                    219,
                                    219,
                                    219,
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: CustomText(text: timing, fontSize: 12),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    // FIX: onPressed was null, so the arrow was disabled
                    child: IconButton(
                      onPressed: onExpand,
                      icon: isExpanded
                          ? Icon(
                              Icons.arrow_drop_up_rounded,
                              color: Colors.black,
                            )
                          : Icon(
                              Icons.arrow_drop_down_rounded,
                              color: Colors.black,
                            ),
                    ),
                  ),
                ],
              ),

              if (isExpanded) ...[
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomText(
                                  text:
                                      student['student_name']?.toString() ?? '',
                                  fontWeight: FontWeight.bold,
                                ),
                                CustomText(
                                  text: student['reg_no']?.toString() ?? '',
                                  fontSize: 12,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD6E6F7),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: CustomText(
                                text: student['tech']?.toString() ?? '',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              SizedBox(height: 10),

              isSelected &&
                      normalizedStatus != 'done' &&
                      normalizedStatus != 'skipped'
                  ? Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: Button(
                            text: 'End',
                            enabled: canEnd,
                            onTap: onEnd,
                          ),
                        ),
                        Expanded(
                          child: Button(
                            text: 'Start',
                            enabled: canStart,
                            onTap: onStart,
                          ),
                        ),
                      ],
                    )
                  : SizedBox(),
            ],
          ),
        ),
      ),
    );
  }
}
