import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/scheduling/availability_page.dart';
import '../utils/components.dart';
import 'action_card.dart';

class VolunteerButton extends StatefulWidget {
  const VolunteerButton({
    super.key,
    required this.jobList,
  });

  final List jobList;

  @override
  State<VolunteerButton> createState() => _VolunteerButtonState();
}

class _VolunteerButtonState extends State<VolunteerButton> {
  late IconData shiftIcon;
  late String shiftLabel;
  bool shiftStarted = false;

  @override
  Widget build(BuildContext context) {
    DatabaseReference shiftRef = FirebaseDatabase.instance.ref("shifts/${FirebaseAuth.instance.currentUser!.uid}");

    return StreamBuilder(
      stream: shiftRef.onValue,
      builder: (context, shiftEvent) {
        if (shiftEvent.connectionState == ConnectionState.active) {
          if ((shiftEvent.data?.snapshot.value as Map?)?['onShift'] == true) {
            shiftStarted = true;
            shiftIcon = Icons.pause_rounded;
            shiftLabel = "End Shift";
          } else {
            shiftStarted = false;
            shiftIcon = Icons.play_arrow_rounded;
            shiftLabel = "Start Shift";
          }

          return ActionCard(
              icon: shiftIcon,
              text: shiftLabel,
              action: () async {
                Future<void> toggleShift(String meetUrl) async {
                  if (shiftStarted == false) {
                    shiftRef.set({"onShift": true});
                    final uri = Uri.parse(meetUrl);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    shiftRef.set({"onShift": false});
                  }
                }

                bool lessonRunning = false;
                String jobID = '';
                String meetUrl = '';

                // find lesson happening right now
                List<Appointment> upcomingLessons = [];
                for (Map<String, dynamic> job in widget.jobList) {
                  int dayOfWeek = DateTime.parse(job['lessonTimes']['start']).weekday;
                  String repeat = job['lessonTimes']['repeat'];

                  upcomingLessons.add(Appointment(
                      subject: job['Job Title'],
                      notes: job['Job Description'],
                      location: "2cousins Meeting",
                      id: job['ID'],
                      startTime: toLocalTime(DateTime.parse(job['lessonTimes']['start']), job['timezone']),
                      endTime: toLocalTime(DateTime.parse(job['lessonTimes']['end']), job['timezone']),
                      color: Theme.of(context).colorScheme.primary,
                      recurrenceRule: getRecurrenceRule(dayOfWeek: dayOfWeek, repeat: repeat)
                  ));
                }

                LessonDataSource dataSource = LessonDataSource(upcomingLessons);
                upcomingLessons = dataSource.getVisibleAppointments(DateTime.now(), '', DateTime.now().add(const Duration(minutes: 15))) ?? [];
                // ^^ can join up to 15 minutes before

                List<Appointment> toRemove = [];
                for (Appointment lesson in upcomingLessons) {
                  if (lesson.endTime.isBefore(DateTime.now())) {
                    toRemove.add(lesson);
                  }
                }
                upcomingLessons.removeWhere((element) => toRemove.contains(element));

                // set lesson running to true if any of the upcoming lessons are within 15 minutes of the current time
                if (upcomingLessons.isNotEmpty) {
                  Appointment lesson = upcomingLessons.first;
                  lessonRunning = true;
                  Map<String, dynamic> job = widget.jobList.firstWhere((element) => element['ID'] == lesson.id);
                  jobID = job['ID'];
                  meetUrl = job['meetUrl'];
                }

                // for (Map<String, dynamic> job in widget.jobList) {
                //   DateTime start = DateTime.parse(job['lessonTimes']['start']);
                //   DateTime end = DateTime.parse(job['lessonTimes']['end']);
                //   DateTime now = DateTime.now();
                //   if (now.isAfter(DateTime(
                //       now.year, now.month, now.day, start.hour, start.minute))
                //       && now.isBefore(DateTime(
                //           now.year, now.month, now.day, end.hour,
                //           end.minute))) {
                //     lessonRunning = true;
                //     jobID = job['ID'];
                //     meetUrl = job['meetUrl'];
                //   }
                // }

                // if we have started a lesson but the lesson has finished
                if (shiftStarted == true && lessonRunning == false) {
                  double minDifference = double.infinity;
                  // find the most recent lesson that happened
                  for (Map<String, dynamic> job in widget.jobList) {
                    // DateTime start = DateTime.parse(job['lessonTimes']['start']);
                    DateTime end = DateTime.parse(job['lessonTimes']['end']);
                    DateTime now = DateTime.now();
                    if (now.isAfter(DateTime(now.year, now.month, now.day, end.hour, end.minute))) {
                      int currDiff = end.difference(now).inMinutes;
                      if (minDifference > currDiff) {
                        minDifference = currDiff.toDouble();
                        jobID = job['ID'];
                      }
                    }
                  }
                }

                if (lessonRunning || shiftStarted) {
                  toggleShift(meetUrl);
                  FirebaseFunctions.instanceFor(
                      region: 'australia-southeast1')
                      .httpsCallable('startShift')
                      .call({
                    'jobID': jobID,
                    'starting': !shiftStarted
                  }).then((HttpsCallableResult value) {
                    debugPrint(value.data.toString());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          (value.data == null) ? "Shift ${shiftStarted ? "started!" : "ended!"}" : value.data.toString(),
                          style: TextStyle(color: Theme
                              .of(context)
                              .primaryColorLight),
                        ),
                        backgroundColor: Theme
                            .of(context)
                            .scaffoldBackgroundColor,
                      ),
                    );
                  });
                } else {
                  showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                            title: const Text('Error!'),
                            content: const Text(
                                'Volunteer hours cannot be contributed if a lesson is '
                                    'not currently running. You can join a lesson up to 15 minutes before it starts. '
                                    'Once your lesson has started, '
                                    'come back and start your shift again!'),
                            actions: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  textStyle: Theme
                                      .of(context)
                                      .textTheme
                                      .labelLarge,
                                ),
                                child: const Text('Okay'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ]);
                      });
                }
              },
              position: PositionPadding.start);
        } else {
          if (shiftStarted) {
            shiftIcon = Icons.pause_rounded;
            shiftLabel = "End Shift";
          } else {
            shiftIcon = Icons.play_arrow_rounded;
            shiftLabel = "Start Shift";
          }
          return ActionCard(
              icon: shiftIcon,
              text: shiftLabel,
              action: () {},
              position: PositionPadding.start);
        }
      }
    );
  }
}
