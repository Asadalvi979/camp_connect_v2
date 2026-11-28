import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommunityDiscussion extends StatefulWidget {
  const CommunityDiscussion({
    super.key,
    required this.communityId,
    required this.name,
    required this.joined,
  });
  final String communityId;
  final String name;
  final bool joined;
  @override
  State<CommunityDiscussion> createState() => _CommunityDiscussionState();
}

class _CommunityDiscussionState extends State<CommunityDiscussion> {
  bool busy = false;
  String? error;
  int pageSize = 25;
  final db = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser!.uid;

  Future<bool> invoke(String name, Map<String, dynamic> data) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseFunctions.instance.httpsCallable(name).call({
        'communityId': widget.communityId,
        ...data,
      });
      return true;
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception is FirebaseException
              ? exception.message
              : 'Please try again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, String>?> compose(
    String heading,
    Map<String, String> initial,
  ) async {
    final controllers = initial.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(heading),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in controllers.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      controller: item.value,
                      decoration: InputDecoration(labelText: item.key),
                      maxLines: item.key == 'Content' ? 5 : 1,
                      validator: (value) =>
                          item.key == 'Content' && (value ?? '').trim().isEmpty
                          ? 'Write something first.'
                          : null,
                    ),
                  ),
              ],
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
              if (form.currentState!.validate()) {
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
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  Future<void> publish() async {
    final values = await compose('Create post', {'Title': '', 'Content': ''});
    if (values == null || !mounted) return;
    await invoke('publishPost', {
      'title': values['Title'],
      'content': values['Content'],
      'operationId': db.collection('operations').doc().id,
    });
  }

  Future<void> report(String postId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report post'),
        children: [
          for (final reason in [
            'Spam or misleading content',
            'Harassment or abuse',
            'Inappropriate content',
            'Other',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason),
              child: Text(reason),
            ),
        ],
      ),
    );
    if (reason != null && mounted) {
      await invoke('reportPost', {'postId': postId, 'reason': reason});
    }
  }

  Widget comments(
    String postId,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db
        .collection('communities/${widget.communityId}/posts/$postId/comments')
        .where('status', isEqualTo: 'Published')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Comments are unavailable.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final comment in snapshot.data!.docs.where(
            (item) => item.data()['status'] == 'Published',
          ))
            ListTile(
              title: Text(comment.data()['authorName']),
              subtitle: Text(comment.data()['content']),
              trailing: comment.data()['authorId'] == uid
                  ? PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'remove') {
                          await invoke('editComment', {
                            'postId': postId,
                            'commentId': comment.id,
                            'remove': true,
                            'content': '',
                          });
                          return;
                        }
                        final values = await compose('Edit comment', {
                          'Content': comment.data()['content'],
                        });
                        if (values != null && mounted) {
                          await invoke('editComment', {
                            'postId': postId,
                            'commentId': comment.id,
                            'content': values['Content'],
                          });
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'remove', child: Text('Delete')),
                      ],
                    )
                  : null,
            ),
          if (widget.joined)
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final values = await compose('Add comment', {
                        'Content': '',
                      });
                      if (values != null && mounted) {
                        await invoke('addComment', {
                          'postId': postId,
                          'content': values['Content'],
                          'operationId': db.collection('operations').doc().id,
                        });
                      }
                    },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Add comment'),
            ),
        ],
      );
    },
  );

  Widget post(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (data['status'] != 'Published') return const SizedBox.shrink();
    final base = 'communities/${widget.communityId}/posts/${document.id}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['authorName'],
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if ((data['title'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  data['title'],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(data['content']),
            ),
            Wrap(
              spacing: 10,
              children: [
                if (widget.joined)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: db.doc('$base/reactions/$uid').snapshots(),
                    builder: (context, snapshot) => TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => invoke('setPostReaction', {
                              'postId': document.id,
                              'helpful': !(snapshot.data?.exists ?? false),
                            }),
                      icon: Icon(
                        snapshot.data?.exists == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                      label: const Text('Helpful'),
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(
                    () => expanded[document.id] =
                        !(expanded[document.id] ?? false),
                  ),
                  child: const Text('Comments'),
                ),
                TextButton(
                  onPressed: () => report(document.id),
                  child: const Text('Report'),
                ),
                if (data['authorId'] == uid)
                  PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'remove') {
                        await invoke('editPost', {
                          'postId': document.id,
                          'remove': true,
                          'content': '',
                        });
                        return;
                      }
                      final values = await compose('Edit post', {
                        'Title': data['title'],
                        'Content': data['content'],
                      });
                      if (values != null && mounted) {
                        await invoke('editPost', {
                          'postId': document.id,
                          'title': values['Title'],
                          'content': values['Content'],
                        });
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'remove', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            if (expanded[document.id] == true) comments(document.id),
          ],
        ),
      ),
    );
  }

  final Map<String, bool> expanded = {};
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.joined)
          FilledButton.icon(
            onPressed: busy ? null : publish,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Share with the community'),
          ),
        if (!widget.joined)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Join this community to post and comment.'),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('communities/${widget.communityId}/posts')
              .where('status', isEqualTo: 'Published')
              .orderBy('createdAt', descending: true)
              .limit(pageSize)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Posts are unavailable.');
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                if (snapshot.data!.docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No discussions yet. Start one for your community.',
                    ),
                  ),
                for (final document in snapshot.data!.docs) post(document),
                if (snapshot.data!.docs.length == pageSize)
                  TextButton(
                    onPressed: () => setState(() => pageSize += 25),
                    child: const Text('Load more'),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
