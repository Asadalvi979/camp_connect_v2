import 'community_discussion.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CampusWorkspace extends StatefulWidget {
  const CampusWorkspace({
    super.key,
    required this.admin,
    required this.onLogout,
  });
  final bool admin;
  final Future<void> Function() onLogout;
  @override
  State<CampusWorkspace> createState() => _CampusWorkspaceState();
}

class _CampusWorkspaceState extends State<CampusWorkspace> {
  int selected = 0;
  int pageSize = 50;
  bool busy = false;
  String? error;
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  List<String> get labels => widget.admin
      ? ['Overview', 'Verification', 'Communities', 'Reports', 'Audit activity']
      : ['Home', 'Communities', 'Explore', 'Messages', 'Profile'];
  List<IconData> get icons => widget.admin
      ? [
          Icons.dashboard_outlined,
          Icons.verified_user_outlined,
          Icons.groups_outlined,
          Icons.flag_outlined,
          Icons.history,
        ]
      : [
          Icons.home_outlined,
          Icons.groups_outlined,
          Icons.explore_outlined,
          Icons.chat_bubble_outline,
          Icons.person_outline,
        ];

  Future<bool> call(String name, Map<String, dynamic> data) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseFunctions.instance.httpsCallable(name).call(data);
      return true;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FirebaseException
              ? e.message
              : 'Unable to complete the request. Please retry.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, String>?> edit(
    String title,
    Map<String, String> values,
  ) async {
    final controllers = values.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
    final key = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in controllers.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        controller: entry.value,
                        decoration: InputDecoration(labelText: entry.key),
                        maxLines:
                            entry.key == 'Bio' ||
                                entry.key == 'Description' ||
                                entry.key == 'Reason'
                            ? 3
                            : 1,
                        validator: (value) =>
                            [
                                  'Name',
                                  'Department',
                                  'Degree',
                                  'Graduation year',
                                  'Description',
                                  'Reason',
                                ].contains(entry.key) &&
                                (value ?? '').trim().isEmpty
                            ? 'This field is required.'
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(
                  context,
                  controllers.map(
                    (key, value) => MapEntry(key, value.text.trim()),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog route may still animate after its result is delivered.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  Widget records(
    Query<Map<String, dynamic>> query,
    Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) render,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: query.snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'Unable to load data. Check your connection and account access.',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          render(snapshot.data!.docs),
          if (snapshot.data!.docs.length == pageSize)
            TextButton(
              onPressed: () => setState(() => pageSize += 50),
              child: const Text('Load more'),
            ),
        ],
      );
    },
  );

  Widget communityList({bool dashboard = false}) => records(
    db
        .collection('communities')
        .where('status', isEqualTo: 'Active')
        .limit(pageSize),
    (communities) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.admin && !dashboard)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final values = await edit('Create community', {
                        'Name': '',
                        'Description': '',
                      });
                      if (values == null || !mounted) return;
                      final id = db.collection('communities').doc().id;
                      await call('createCommunity', {
                        'name': values['Name'],
                        'description': values['Description'],
                        'operationId': id,
                      });
                    },
              icon: const Icon(Icons.add),
              label: const Text('Create community'),
            ),
          ),
        if (communities.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No campus communities are available yet.'),
          ),
        for (final community in communities)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.data()['name'],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(community.data()['description']),

                  if (!widget.admin)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: db
                          .doc(
                            'accounts/${auth.currentUser!.uid}/memberships/${community.id}',
                          )
                          .snapshots(),
                      builder: (context, membership) {
                        if (membership.hasError) {
                          return const Text(
                            'Membership status is unavailable.',
                          );
                        }
                        if (!membership.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final joined = membership.data!.exists;
                        final discussion = TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CommunityDiscussion(
                                communityId: community.id,
                                name: community.data()['name'],
                                joined: joined,
                              ),
                            ),
                          ),
                          child: const Text('View discussion'),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              discussion,
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => call('setCommunityMembership', {
                                        'communityId': community.id,
                                        'join': !joined,
                                      }),
                                child: Text(
                                  joined
                                      ? 'Joined · Leave community'
                                      : 'Join community',
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget reviewQueue() => records(
    db
        .collection('accounts')
        .where(
          'status',
          whereIn: ['Pending Admin Review', 'Needs Information', 'Rejected'],
        )
        .limit(pageSize),
    (accounts) {
      final queue = accounts.where(
        (a) => [
          'Pending Admin Review',
          'Needs Information',
          'Rejected',
        ].contains(a.data()['status']),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (queue.isEmpty)
            const Text('There are no alumni applications awaiting review.'),
          for (final account in queue)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.data()['name'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${account.data()['cmsId']} · ${account.data()['email']}',
                    ),
                    Text(
                      '${account.data()['degree']} · ${account.data()['graduationYear']}',
                    ),
                    Text(account.data()['status']),
                    if (account.data()['reviewReason'] != null)
                      Text(account.data()['reviewReason']),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in {
                          'approve': 'Approve',
                          'information': 'Request information',
                          'reject': 'Reject',
                        }.entries)
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final values = await edit(
                                      '${entry.value} application',
                                      {
                                        entry.key == 'approve'
                                                ? 'Note (optional)'
                                                : 'Reason':
                                            '',
                                      },
                                    );
                                    if (values != null && mounted) {
                                      await call('reviewAlumni', {
                                        'uid': account.id,
                                        'decision': entry.key,
                                        'reason':
                                            values['Reason'] ??
                                            values['Note (optional)'] ??
                                            '',
                                      });
                                    }
                                  },
                            child: Text(entry.value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget member(Map<String, dynamic> account) {
    if (account['status'] != 'Active') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account['status'] ?? 'Account unavailable',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            account['reviewReason'] ??
                'Your graduation details are awaiting review.',
          ),
          if (account['status'] == 'Needs Information')
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final values = await edit('Update graduation details', {
                        'Degree': account['degree'] ?? '',
                        'Graduation year': account['graduationYear'] ?? '',
                      });
                      if (values != null && mounted) {
                        await call('resubmitAlumni', {
                          'degree': values['Degree'],
                          'graduationYear': values['Graduation year'],
                        });
                      }
                    },
              child: const Text('Submit information'),
            ),
          if (account['status'] == 'Rejected')
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'An administrator must reopen your application before you can submit updated details.',
              ),
            ),
        ],
      );
    }
    if (selected == 1) return communityList();
    if (selected == 2 || selected == 3) {
      return Text('${labels[selected]} is being prepared for your campus.');
    }
    if (selected == 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 32,
            child: Icon(Icons.person_outline, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            account['name'],
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(account['category']),
          Text(account['department'] ?? 'Add your department'),
          if (account['semester'] != null)
            Text('Semester ${account['semester']}'),
          if (account['category'] == 'Alumni')
            Text(
              '${account['degree']} · Class of ${account['graduationYear']}',
            ),
          const SizedBox(height: 20),
          Text(account['bio'] ?? ''),
          Text(account['skills'] ?? ''),
          if (account['category'] == 'Alumni')
            Text('${account['jobTitle'] ?? ''} ${account['company'] ?? ''}'),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    final values = await edit('Edit profile', {
                      'Name': account['name'],
                      'Department': account['department'] ?? '',
                      'Bio': account['bio'] ?? '',
                      'Skills': account['skills'] ?? '',
                      if (account['category'] == 'Alumni') ...{
                        'Company': account['company'] ?? '',
                        'Job title': account['jobTitle'] ?? '',
                      },
                    });
                    if (values != null && mounted) {
                      await call('saveProfile', {
                        'name': values['Name'],
                        'department': values['Department'],
                        'bio': values['Bio'],
                        'skills': values['Skills'],
                        'company': values['Company'] ?? '',
                        'jobTitle': values['Job title'] ?? '',
                      });
                    }
                  },
            child: const Text('Edit profile'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Semester and graduation details are verified academic information. Contact an administrator to correct them.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome, ${account['name']}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text('A little connection. A lot of possibilities.'),
        const SizedBox(height: 24),
        Text('Your campus', style: Theme.of(context).textTheme.titleLarge),
        communityList(dashboard: true),
      ],
    );
  }

  Widget reports() => records(
    db.collection('reports').where('status', isEqualTo: 'Open').limit(pageSize),
    (items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty) const Text('There are no open reports.'),
        for (final report in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Post report · ${report.data()['reason']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(report.data()['snapshot']),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => call('moderatePost', {
                                'reportId': report.id,
                                'decision': 'dismiss',
                              }),
                        child: const Text('Dismiss'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(130, 44),
                        ),
                        onPressed: busy
                            ? null
                            : () => call('moderatePost', {
                                'reportId': report.id,
                                'decision': 'remove',
                              }),
                        child: const Text('Remove post'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget adminBody() {
    if (selected == 1) return reviewQueue();
    if (selected == 2) return communityList();
    if (selected == 3) return reports();
    if (selected == 4) {
      return records(
        db
            .collection('auditLog')
            .orderBy('timestamp', descending: true)
            .limit(pageSize),
        (logs) => Column(
          children: [
            if (logs.isEmpty) const Text('No administrative activity yet.'),
            for (final log in logs)
              Card(
                child: ListTile(
                  title: Text(log.data()['action']),
                  subtitle: Text(
                    'Actor ${log.data()['actor']}\nTarget ${log.data()['target']}\n${(log.data()['timestamp'] as Timestamp?)?.toDate().toLocal() ?? ''}',
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Campus administration',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        records(
          db
              .collection('accounts')
              .where('status', isEqualTo: 'Pending Admin Review')
              .limit(pageSize),
          (accounts) => Card(
            child: ListTile(
              title: Text(
                '${accounts.length}${accounts.length == pageSize ? '+' : ''} pending alumni applications',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => selected = 1),
            ),
          ),
        ),
        const SizedBox(height: 24),
        communityList(dashboard: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final content = widget.admin
          ? adminBody()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: db.doc('accounts/${auth.currentUser!.uid}').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Unable to load your account. Please sign in again.',
                  );
                }
                if (!snapshot.hasData) return const CircularProgressIndicator();
                if (!snapshot.data!.exists) {
                  return const Text('Your account is unavailable.');
                }
                return member(snapshot.data!.data()!);
              },
            );
      return Scaffold(
        appBar: AppBar(
          title: Text(labels[selected]),
          actions: [
            TextButton(
              onPressed: widget.onLogout,
              child: const Text('Log out'),
            ),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              SizedBox(
                width: 240,
                child: Material(
                  color: Colors.white,
                  child: ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('CampConnect\nSAHIWAL CAMPUS'),
                      ),
                      for (var i = 0; i < labels.length; i++)
                        ListTile(
                          leading: Icon(icons[i]),
                          title: Text(labels[i]),
                          selected: selected == i,
                          onTap: () => setState(() => selected = i),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    content,
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: kIsWeb ? 40 : 0),
                child: NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() => selected = i),
                  destinations: [
                    for (var i = 0; i < labels.length; i++)
                      NavigationDestination(
                        icon: Icon(icons[i]),
                        label: labels[i],
                      ),
                  ],
                ),
              ),
      );
    },
  );
}
