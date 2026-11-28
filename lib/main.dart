import 'features/campus_workspace.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

const teal = Color(0xFF107D78);
const navy = Color(0xFF18324F);
const configuredEmulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-campconnect-api-key',
      appId: '1:123456789:web:campconnect',
      messagingSenderId: '123456789',
      projectId: 'demo-campconnect',
    ),
  );
  const host = configuredEmulatorHost;
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8088);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CampConnect',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'Inter',
      visualDensity: VisualDensity.standard,
      colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal),
      scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'Inter',
        bodyColor: navy,
        displayColor: navy,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFDDE3EA)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ),
    home: const AccountFlow(),
  );
}

class AccountFlow extends StatefulWidget {
  const AccountFlow({super.key});
  @override
  State<AccountFlow> createState() => _AccountFlowState();
}

class _AccountFlowState extends State<AccountFlow> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final cms = TextEditingController();
  final cmsNumber = TextEditingController();
  final degree = TextEditingController();
  final year = TextEditingController();
  final code = TextEditingController();
  String page = 'login';
  String category = 'Student';
  int semester = 1;
  String? selectedSession;
  String? selectedCourse;
  static const courses = <String, String>{
    'BSSE': 'BS Software Engineering',
    'BSCS': 'BS Computer Science',
    'BSAI': 'BS Artificial Intelligence',
    'BSIT': 'BS Information Technology',
    'BBA': 'Business Administration',
    'PHARMD': 'Pharm-D',
    'DPT': 'Doctor of Physical Therapy',
  };
  String get completeCmsId =>
      '${selectedSession ?? ''}-${selectedCourse ?? ''}-${cmsNumber.text.trim()}';
  bool terms = false;
  bool busy = false;
  bool isAdmin = false;
  String? feedback;
  Map<String, dynamic>? account;

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        perform(() async {
          final user = await FirebaseAuth.instance.authStateChanges().first;
          if (user != null) {
            email.text = user.email ?? '';
            await refreshAccount();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      email,
      password,
      name,
      cms,
      cmsNumber,
      degree,
      year,
      code,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void go(String next) => setState(() {
    page = next;
    feedback = null;
  });

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      await action();
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => feedback =
              error.code == 'network-request-failed' ||
                  (error.message ?? '').contains('network AuthError')
              ? 'Firebase Auth connection failed. Configured emulator: $configuredEmulatorHost:9099. Keep the emulators running. For Chrome on the same computer, use EMULATOR_HOST=127.0.0.1.'
              : error.message ?? 'Unable to connect. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => feedback =
              'Unable to connect. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refreshAccount() async {
    final user = FirebaseAuth.instance.currentUser!;
    final token = await user.getIdTokenResult(true);
    if (!mounted) return;
    isAdmin = token.claims?['admin'] == true;
    if (isAdmin) {
      go('campus');
      return;
    }
    final uid = user.uid;
    final snapshot = await FirebaseFirestore.instance
        .doc('accounts/$uid')
        .get(const GetOptions(source: Source.server));
    if (!mounted) return;
    setState(() {
      account = snapshot.data();
      if (account != null) {
        name.text = account!['name'] ?? '';
        cms.text = account!['cmsId'] ?? '';
        degree.text = account!['degree'] ?? '';
        year.text = account!['graduationYear'] ?? '';
        semester = account!['semester'] ?? 1;
        category = account!['category'] == 'Alumni'
            ? 'Alumni'
            : semester <= 4
            ? 'Student'
            : 'Senior';
      }
      page = account == null
          ? 'register'
          : account!['status'] == 'Pending Email Verification'
          ? 'otp'
          : 'campus';
    });
  }

  Future<void> register() async {
    if (!form.currentState!.validate()) {
      setState(
        () => feedback = category == 'Alumni'
            ? 'Please correct the highlighted fields above.'
            : 'Please correct the highlighted fields above. Use an email ending in @student.riphahsahiwal.edu.pk.',
      );
      return;
    }
    if (!terms) {
      setState(() => feedback = 'Please accept the Terms and Privacy Policy.');
      return;
    }
    await perform(() async {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null &&
          auth.currentUser!.email?.toLowerCase() !=
              email.text.trim().toLowerCase()) {
        throw FirebaseAuthException(
          code: 'email-mismatch',
          message: 'Log out and register again to use another email address.',
        );
      }
      if (auth.currentUser == null) {
        await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
      await FirebaseFunctions.instance.httpsCallable('registerAccount').call({
        'name': name.text.trim(),
        'cmsId': completeCmsId,
        'category': category,
        'semester': semester,
        'degree': degree.text.trim(),
        'graduationYear': year.text.trim(),
      });
      if (mounted) go('otp');
    });
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
    TextInputType? keyboard,
    String? Function(String)? check,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey(label),
          controller: controller,
          obscureText: secret,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: secret
                ? 'Enter your password'
                : label == 'Email address'
                ? 'you@example.com'
                : label,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFDDE3EA)),
            ),
          ),
          validator: (value) =>
              check?.call(value?.trim() ?? '') ??
              ((value ?? '').trim().isEmpty ? 'This field is required.' : null),
        ),
      ],
    ),
  );

  Widget action(String label, VoidCallback onPressed) =>
      FilledButton(onPressed: busy ? null : onPressed, child: Text(label));

  Widget content() {
    switch (page) {
      case 'register':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create your account to learn, connect and collaborate.',
            ),
            const SizedBox(height: 24),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'Student', label: Text('Student')),
                  ButtonSegment(value: 'Senior', label: Text('Senior')),
                  ButtonSegment(value: 'Alumni', label: Text('Alumni')),
                ],
                selected: {category},
                onSelectionChanged: busy
                    ? null
                    : (value) => setState(() {
                        category = value.first;
                        semester = category == 'Senior' ? 5 : 1;
                      }),
              ),
            ),
            const SizedBox(height: 24),
            field('Full name', name),
            DropdownButtonFormField<String>(
              key: const ValueKey('Session'),
              initialValue: selectedSession,
              decoration: const InputDecoration(labelText: 'Session'),
              items: [
                for (var year = DateTime.now().year + 1; year >= 2022; year--)
                  for (final term in ['F', 'S'])
                    DropdownMenuItem(
                      value: '$term${(year % 100).toString().padLeft(2, '0')}',
                      child: Text(
                        '$term${(year % 100).toString().padLeft(2, '0')}',
                      ),
                    ),
              ],
              onChanged: (value) => setState(() => selectedSession = value),
              validator: (value) =>
                  value == null ? 'Select your session.' : null,
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              key: const ValueKey('Course'),
              isExpanded: true,
              initialValue: selectedCourse,
              decoration: const InputDecoration(labelText: 'Course'),
              items: [
                for (final entry in courses.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.key == 'PHARMD' ? 'Pharm-D' : entry.key),
                  ),
              ],
              onChanged: (value) => setState(() => selectedCourse = value),
              validator: (value) =>
                  value == null ? 'Select your course.' : null,
            ),
            const SizedBox(height: 18),
            TextFormField(
              key: const ValueKey('CMS number'),
              controller: cmsNumber,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'CMS number',
                prefixText: selectedSession == null || selectedCourse == null
                    ? null
                    : '$selectedSession-$selectedCourse-',
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) => RegExp(r'^\d{4}$').hasMatch(value ?? '')
                  ? null
                  : 'Enter your four-digit CMS number.',
            ),
            Text(
              'Complete CMS ID: ${selectedSession ?? '___'}-${selectedCourse ?? '____'}-${cmsNumber.text.isEmpty ? '____' : cmsNumber.text}',
            ),
            const SizedBox(height: 18),
            field(
              category == 'Alumni' ? 'Personal email' : 'University email',
              email,
              keyboard: TextInputType.emailAddress,
              check: (value) =>
                  (category == 'Alumni'
                      ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                      : RegExp(
                          r'^[^@\s]+@student\.riphahsahiwal\.edu\.pk$',
                          caseSensitive: false,
                        ).hasMatch(value))
                  ? null
                  : 'Enter a valid ${category == 'Alumni' ? 'personal' : 'university'} email.',
            ),
            field(
              'Password',
              password,
              secret: true,
              check: (value) =>
                  value.length >= 8 ? null : 'Use at least 8 characters.',
            ),
            if (category != 'Alumni') ...[
              DropdownButtonFormField<int>(
                key: ValueKey(category),
                isExpanded: true,
                initialValue: semester,
                decoration: const InputDecoration(labelText: 'Semester'),
                items: List.generate(
                  8,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text(
                      '${index + 1} · ${index < 4 ? 'Junior' : 'Senior'} Student',
                    ),
                  ),
                ),
                onChanged: (value) => setState(() {
                  semester = value!;
                  category = semester <= 4 ? 'Student' : 'Senior';
                }),
              ),
            ] else ...[
              field('Degree', degree),
              field(
                'Graduation year',
                year,
                keyboard: TextInputType.number,
                check: (value) => RegExp(r'^\d{4}$').hasMatch(value)
                    ? null
                    : 'Enter a four-digit year.',
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: terms,
              onChanged: (value) => setState(() => terms = value!),
              title: const Text('I agree to the Terms and Privacy Policy'),
            ),
            action('Continue', register),
            TextButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) go('login');
                    }),
              child: const Text('Back to login'),
            ),
          ],
        );
      case 'otp':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter your six-digit email verification code.'),
            const SizedBox(height: 24),
            field(
              'Verification code',
              code,
              keyboard: TextInputType.number,
              check: (value) => RegExp(r'^\d{6}$').hasMatch(value)
                  ? null
                  : 'Enter six digits.',
            ),
            action('Verify email', () {
              if (form.currentState!.validate()) {
                perform(() async {
                  await FirebaseFunctions.instance
                      .httpsCallable('verifyEmailCode')
                      .call({'code': code.text.trim()});
                  await refreshAccount();
                });
              }
            }),
            TextButton(
              onPressed: busy ? null : () => go('register'),
              child: const Text('Resend code / edit details'),
            ),
          ],
        );
      case 'reset':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your account email. We will send a secure password reset link.',
            ),
            const SizedBox(height: 24),
            field('Email address', email, keyboard: TextInputType.emailAddress),
            action('Send reset link', () {
              if (form.currentState!.validate()) {
                perform(() async {
                  await FirebaseAuth.instance.sendPasswordResetEmail(
                    email: email.text.trim(),
                  );
                  if (mounted) {
                    setState(
                      () => feedback = 'If this email has an account, a reset link has been requested.',
                    );
                  }
                });
              }
            }),
            TextButton(
              onPressed: busy ? null : () => go('login'),
              child: const Text('Back to login'),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Your campus community is waiting.'),
            const SizedBox(height: 28),
            field('Email address', email, keyboard: TextInputType.emailAddress),
            field('Password', password, secret: true),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => go('reset'),
                child: const Text('Forgot password?'),
              ),
            ),
            action('Log in', () {
              if (form.currentState!.validate()) {
                perform(() async {
                  await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: email.text.trim(),
                    password: password.text,
                  );
                  await refreshAccount();
                });
              }
            }),
            TextButton(
              onPressed: busy ? null : () => go('register'),
              child: const Text('New here? Create an account'),
            ),
            const SizedBox(height: 20),
            const Card(
              color: Color(0xFFE7F3F0),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Campus members only\nRiphah International University, Sahiwal',
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (page == 'campus') {
      return CampusWorkspace(
        admin: isAdmin,
        onLogout: () async {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            password.clear();
            go('login');
          }
        },
      );
    }
    final title = {
      'login': 'Welcome back',
      'register': 'Join your campus',
      'otp': 'Check your inbox',
      'reset': 'Forgot your password?',
      'status': account?['status'] == 'Active'
          ? 'Your campus account'
          : 'Your review is underway',
    }[page]!;
    final formWidget = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (MediaQuery.sizeOf(context).width < 900)
                  const Text(
                    'CampConnect',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                const SizedBox(height: 36),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                content(),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (feedback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        feedback!,
                        style: const TextStyle(color: Color(0xFFB33B42)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) return formWidget;
            return Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    color: navy,
                    padding: const EdgeInsets.all(64),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CampConnect',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        Text(
                          'Your campus.\nYour people.\nYour next chapter.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          'Connect with students, learn from alumni and build something together.',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        SizedBox(height: 40),
                        Text(
                          'Riphah International University\nSahiwal campus',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Material(color: Colors.white, child: formWidget),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
