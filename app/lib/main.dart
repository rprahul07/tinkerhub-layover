import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/reactions.dart';
import 'data/session.dart';
import 'features/onboarding/join_screen.dart';
import 'features/shell/home_shell.dart';
import 'theme/tg_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await Session.init();
  Api.instance = Api(session);
  Reactions.instance = Reactions(Api.instance);
  runApp(const TravelgramApp());
}

class TravelgramApp extends StatelessWidget {
  const TravelgramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travelgram',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Everyone on Travelgram has a profile: following, "I'm going" and posting need it.
      home: ListenableBuilder(
        listenable: Session.instance,
        builder: (context, _) => Session.instance.creator == null ? const JoinScreen() : const HomeShell(),
      ),
    );
  }
}
