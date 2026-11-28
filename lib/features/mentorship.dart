import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class Mentorship extends StatefulWidget {
  const Mentorship({super.key, required this.account});
  final Map<String, dynamic> account;
  @override
  State<Mentorship> createState() => _MentorshipState();
}

class _MentorshipState extends State<Mentorship> {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final mentors = <Map<String, dynamic>>[];
  String? cursor;
  String search = '';
  String? error;
  bool busy = false;
  bool loaded = false;
  bool incoming = false;
  int requestLimit = 25;
  bool get canMentor =>
      ['Senior Student', 'Alumni'].contains(widget.account['category']);
  bool get canRequest =>
      ['Junior Student', 'Senior Student'].contains(widget.account['category']);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<dynamic> call(String name, Map<String, dynamic> data) async {
    if (busy) return null;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      return (await FirebaseFunctions.instance.httpsCallable(name).call(data))
          .data;
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is FirebaseException ? e.message : 'Please try again.',
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load({bool reset = false}) async {
    final result = await call('listMentors', {'cursor': reset ? null : cursor});
    if (result == null || !mounted) return;
    setState(() {
      if (reset) mentors.clear();
      for (final item in result['mentors']) {
        final mentor = Map<String, dynamic>.from(item);
        if (mentor['id'] != uid &&
            !mentors.any((m) => m['id'] == mentor['id'])) {
          mentors.add(mentor);
        }
      }
      cursor = result['cursor'];
      loaded = true;
    });
  }

  Future<void> profile(Map<String, dynamic> mentor) async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(mentor['name']),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${mentor['category']} · ${mentor['department']}'),
                Text(mentor['jobTitle']),
                Text(mentor['company']),
                const SizedBox(height: 12),
                Text(mentor['bio']),
                Text('Skills: ${mentor['skills']}'),
                Text(
                  mentor['available'] == true
                      ? 'Available for mentorship'
                      : 'Not accepting requests',
                ),
                if (canRequest && mentor['available'] == true) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'How can this mentor help you?',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Write a request message.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (canRequest && mentor['available'] == true)
            TextButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Send request'),
            ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (message != null && mounted) {
      final result = await call('requestMentorship', {
        'mentorId': mentor['id'],
        'message': message,
      });
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mentorship request sent.')),
        );
      }
    }
  }

  Widget requests() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('mentorshipRequests')
        .where(incoming ? 'mentorId' : 'requesterId', isEqualTo: uid)
        .limit(requestLimit)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'Requests are unavailable. Please reconnect and try again.',
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final docs = snapshot.data!.docs;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (docs.isEmpty) const Text('No mentorship requests yet.'),
          for (final doc in docs)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.data()[incoming ? 'requesterName' : 'mentorName'],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(doc.data()['message']),
                    Text('Status: ${doc.data()['status']}'),
                    if (doc.data()['status'] == 'Accepted')
                      const Text(
                        'Mentorship accepted. Messaging will be available in a later update.',
                      ),
                    if (doc.data()['status'] == 'Pending')
                      Wrap(
                        children: [
                          for (final action
                              in incoming ? ['accept', 'reject'] : ['cancel'])
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => call('respondMentorship', {
                                      'id': doc.id,
                                      'action': action,
                                    }),
                              child: Text(
                                {
                                  'accept': 'Accept',
                                  'reject': 'Reject',
                                  'cancel': 'Cancel request',
                                }[action]!,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (docs.length == requestLimit)
            TextButton(
              onPressed: () => setState(() => requestLimit += 25),
              child: const Text('Load more requests'),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final matches = mentors
        .where(
          (m) => '${m['name']} ${m['skills']} ${m['department']}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mentorship', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Find guidance from senior students and approved alumni.'),
        if (canMentor)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Accepting mentorship requests'),
            value: widget.account['mentorshipAvailable'] != false,
            onChanged: busy
                ? null
                : (value) =>
                      call('setMentorshipAvailability', {'available': value}),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search loaded mentors by name, skill or department',
          ),
          onChanged: (value) => setState(() => search = value),
        ),
        TextButton(
          onPressed: busy ? null : () => load(reset: true),
          child: const Text('Refresh mentors'),
        ),
        if (loaded && matches.isEmpty)
          const Text('No matching mentors in the loaded results.'),
        for (final mentor in matches)
          Card(
            child: ListTile(
              title: Text(mentor['name']),
              subtitle: Text(
                '${mentor['category']} · ${mentor['department']}\n${mentor['available'] == true ? 'Available' : 'Unavailable'}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => profile(mentor),
            ),
          ),
        if (cursor != null)
          TextButton(
            onPressed: busy ? null : load,
            child: const Text('Load more mentors'),
          ),
        const SizedBox(height: 24),
        Text('My mentorships', style: Theme.of(context).textTheme.titleLarge),
        if (canMentor)
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Sent'),
                selected: !incoming,
                onSelected: (_) => setState(() {
                  incoming = false;
                  requestLimit = 25;
                }),
              ),
              ChoiceChip(
                label: const Text('Received'),
                selected: incoming,
                onSelected: (_) => setState(() {
                  incoming = true;
                  requestLimit = 25;
                }),
              ),
            ],
          ),
        requests(),
      ],
    );
  }
}
