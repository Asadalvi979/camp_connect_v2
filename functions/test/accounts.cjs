const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8088';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
initializeApp({projectId: 'demo-campconnect'});
const db = getFirestore();
const suffix = randomUUID().slice(0, 8);
async function signup(email) {
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password: 'TestPassword123!', returnSecureToken: true}),
  });
  const user = await response.json();
  assert.ok(user.idToken, JSON.stringify(user));
  return user;
}
async function call(name, user, data) {
  const response = await fetch(`http://127.0.0.1:5001/demo-campconnect/us-central1/${name}`, {
    method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${user.idToken}`},
    body: JSON.stringify({data}),
  });
  return response.json();
}
async function confirm(user) {
  const challenge = db.doc(`emailChallenges/${user.localId}`);
  assert.ok((await challenge.get()).exists);
  await challenge.update({hash: createHash('sha256').update(`${user.localId}:123456`).digest('hex')});
  assert.equal((await call('verifyEmailCode', user, {code: '111111'})).error.status, 'INVALID_ARGUMENT');
  assert.equal((await challenge.get()).data().attempts, 1);
  assert.equal((await call('verifyEmailCode', user, {code: '123456'})).result.verified, true);
  assert.equal((await challenge.get()).exists, false);
}
(async () => {
  const student = await signup(`${suffix}@student.riphahsahiwaledu.pk`);
  const cms = `F24-BSSE-${String(Math.floor(Math.random() * 10000)).padStart(4, '0')}`;
  const input = {name: 'Student Test', cmsId: cms, category: 'Student', semester: 4};
  assert.equal((await call('registerAccount', student, input)).result.sent, true);
  assert.equal((await call('registerAccount', student, input)).error.status, 'RESOURCE_EXHAUSTED');
  const duplicate = await signup(`duplicate-${suffix}@student.riphahsahiwaledu.pk`);
  assert.equal((await call('registerAccount', duplicate, input)).error.status, 'ALREADY_EXISTS');
  await confirm(student);
  assert.equal((await db.doc(`accounts/${student.localId}`).get()).data().status, 'Active');
  const alumni = await signup(`alumni-${suffix}@example.com`);
  assert.equal((await call('registerAccount', alumni, {name: 'Alumni Test', cmsId: cms.replace('F24', 'F20'), category: 'Alumni', degree: 'BSSE', graduationYear: '2024'})).result.sent, true);
  await confirm(alumni);
  assert.equal((await db.doc(`accounts/${alumni.localId}`).get()).data().status, 'Pending Admin Review');
  assert.equal((await call('reviewAlumni', student, {uid: alumni.localId, decision: 'approve'})).error.status, 'PERMISSION_DENIED');
  const admin = await signup(`admin-${suffix}@example.com`);
  await getAuth().setCustomUserClaims(admin.localId, {admin: true});
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email: `admin-${suffix}@example.com`, password: 'TestPassword123!', returnSecureToken: true}),
  });
  const signedAdmin = await response.json();
  assert.equal((await call('reviewAlumni', signedAdmin, {uid: alumni.localId, decision: 'approve'})).result.status, 'Active');
  const profile = {name: 'Updated Student', department: 'Software Engineering', bio: 'Building campus apps', skills: 'Flutter', company: '', jobTitle: '', status: 'Active', semester: 8};
  assert.equal((await call('saveProfile', student, profile)).result.saved, true);
  assert.equal((await db.doc(`accounts/${student.localId}`).get()).data().semester, 4);
  assert.equal((await call('createCommunity', student, {name: 'Denied', description: 'Denied', operationId: suffix})).error.status, 'PERMISSION_DENIED');
  const communityInput = {name: `Flutter Developers ${suffix}`, description: 'Learn and build together.', operationId: suffix};
  const community = (await call('createCommunity', signedAdmin, communityInput)).result.id;
  assert.equal((await call('createCommunity', signedAdmin, communityInput)).result.id, community);
  assert.equal((await call('setCommunityMembership', student, {communityId: community, join: true})).result.saved, true);
  assert.ok((await db.doc(`accounts/${student.localId}/memberships/${community}`).get()).exists);
  await call('setCommunityMembership', student, {communityId: community, join: false});
  assert.equal((await db.doc(`accounts/${student.localId}/memberships/${community}`).get()).exists, false);
  // An admin reopens a rejected application by requesting information.
  await db.doc(`accounts/${alumni.localId}`).update({status: 'Rejected'});
  assert.equal((await call('resubmitAlumni', alumni, {degree: 'BSSE', graduationYear: '2024'})).error.status, 'FAILED_PRECONDITION');
  assert.equal((await call('reviewAlumni', signedAdmin, {uid: alumni.localId, decision: 'information', reason: 'Confirm graduation year'})).result.status, 'Needs Information');
  assert.equal((await call('saveProfile', alumni, profile)).error.status, 'PERMISSION_DENIED');
  assert.equal((await call('setCommunityMembership', alumni, {communityId: community, join: true})).error.status, 'PERMISSION_DENIED');
  assert.equal((await call('resubmitAlumni', alumni, {degree: 'BSSE', graduationYear: '2023'})).result.submitted, true);
  assert.equal((await db.doc(`accounts/${alumni.localId}`).get()).data().status, 'Pending Admin Review');
  assert.equal((await call('reviewAlumni', signedAdmin, {uid: alumni.localId, decision: 'approve', reason: 'Verified'})).result.status, 'Active');
  const postInput = {communityId: community, title: 'Study circle', content: 'Bring your Flutter questions.', operationId: `post-${suffix}`};
  assert.equal((await call('publishPost', alumni, postInput)).error.status, 'PERMISSION_DENIED');
  await call('setCommunityMembership', student, {communityId: community, join: true});
  const postId = (await call('publishPost', student, postInput)).result.postId;
  assert.equal((await call('publishPost', student, postInput)).result.postId, postId);
  assert.equal((await call('editPost', alumni, {communityId: community, postId, title: 'Tampered', content: 'Tampered'})).error.status, 'PERMISSION_DENIED');
  assert.equal((await call('addComment', student, {communityId: community, postId, content: 'Count me in.', operationId: `comment-${suffix}`})).result.commentId.length, 64);
  assert.equal((await call('setPostReaction', student, {communityId: community, postId, helpful: true})).result.saved, true);
  assert.equal((await call('reportPost', alumni, {communityId: community, postId, reason: 'Spam'})).result.submitted, true);
  const reportId = require('node:crypto').createHash('sha256').update(`${alumni.localId}:${community}:${postId}`).digest('hex');
  assert.equal((await call('moderatePost', student, {reportId, decision: 'remove'})).error.status, 'PERMISSION_DENIED');
  assert.equal((await call('moderatePost', signedAdmin, {reportId, decision: 'remove'})).result.reviewed, true);
  assert.equal((await db.doc(`communities/${community}/posts/${postId}`).get()).data().status, 'Removed');
  // Deleted content must be inaccessible even by its exact document URL.
  const readDocument = path => fetch(`http://127.0.0.1:8088/v1/projects/demo-campconnect/databases/(default)/documents/${path}`, {headers: {Authorization: `Bearer ${student.idToken}`}});
  assert.equal((await readDocument(`communities/${community}/posts/${postId}`)).status, 403);
  const ownPost = (await call('publishPost', student, {...postInput, operationId: `delete-${suffix}`})).result.postId;
  const ownPath = `communities/${community}/posts/${ownPost}`;
  assert.equal((await readDocument(ownPath)).status, 200);
  const ownComment = (await call('addComment', student, {communityId: community, postId: ownPost, content: 'Temporary', operationId: `delete-comment-${suffix}`})).result.commentId;
  assert.equal((await call('editComment', student, {communityId: community, postId: ownPost, commentId: ownComment, remove: true, content: ''})).result.saved, true);
  assert.equal((await readDocument(`${ownPath}/comments/${ownComment}`)).status, 403);
  // This matches the UI delete payload, which intentionally has no title.
  assert.equal((await call('editPost', student, {communityId: community, postId: ownPost, remove: true, content: ''})).result.saved, true);
  assert.equal((await readDocument(ownPath)).status, 403);
  const unauthorized = await fetch(`http://127.0.0.1:8088/v1/projects/demo-campconnect/databases/(default)/documents/accounts/${alumni.localId}`, {headers: {Authorization: `Bearer ${student.idToken}`}});
  assert.equal(unauthorized.status, 403);
  console.log('PASS accounts, profiles, communities, posts, comments, reactions, reports, moderation and Firestore privacy');
})().catch(error => {console.error(error); process.exitCode = 1;});
