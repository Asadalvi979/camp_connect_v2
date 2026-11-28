const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {randomInt, createHash} = require('node:crypto');

initializeApp();
const db = getFirestore();
const digest = value => createHash('sha256').update(value).digest('hex');

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in again.');
  return request.auth.uid;
}

// Numeric email delivery is deliberately unavailable outside the local emulator
// until a verified email provider is configured.
exports.registerAccount = onCall(async request => {
  const uid = requireUser(request);
  if (process.env.FUNCTIONS_EMULATOR !== 'true') {
    throw new HttpsError('failed-precondition', 'Email delivery is not configured.');
  }
  const user = await getAuth().getUser(uid);
  const data = request.data;
  const cmsId = String(data.cmsId || '').trim().toUpperCase();
  const name = String(data.name || '').trim();
  const semester = Number(data.semester);
  const alumni = data.category === 'Alumni';
  if (!/^[A-Z]\d{2}-[A-Z]{2,10}-\d{4}$/.test(cmsId) || !name || name.length > 100) {
    throw new HttpsError('invalid-argument', 'Enter your name and a valid CMS ID.');
  }
  if (!alumni && (!Number.isInteger(semester) || semester < 1 || semester > 8 ||
      user.email?.split('@')[1]?.toLowerCase() !== 'student.riphahsahiwal.edu.pk')) {
    throw new HttpsError('invalid-argument', 'Use your university email and semester 1–8.');
  }
  if (alumni && (!String(data.degree || '').trim() || !/^\d{4}$/.test(String(data.graduationYear)))) {
    throw new HttpsError('invalid-argument', 'Enter your degree and graduation year.');
  }
  const account = db.doc(`accounts/${uid}`);
  const reservation = db.doc(`cmsReservations/${cmsId}`);
  const otp = db.doc(`emailChallenges/${uid}`);
  const code = String(randomInt(100000, 1000000));
  await db.runTransaction(async tx => {
    const [existing, reserved, challenge] = await Promise.all([
      tx.get(account), tx.get(reservation), tx.get(otp),
    ]);
    if (reserved.exists && reserved.data().uid !== uid) {
      throw new HttpsError('already-exists', 'This CMS ID is already registered.');
    }
    if (existing.exists && existing.data().cmsId !== cmsId) {
      throw new HttpsError('failed-precondition', 'Your CMS ID is already reserved.');
    }
    if (existing.exists && existing.data().status !== 'Pending Email Verification') {
      throw new HttpsError('failed-precondition', 'Your email is already verified.');
    }
    if (challenge.exists && Date.now() - challenge.data().sentAt.toMillis() < 60000) {
      throw new HttpsError('resource-exhausted', 'Wait one minute before requesting another code.');
    }
    tx.set(reservation, {uid});
    tx.set(account, {
      name, cmsId, email: user.email, category: alumni ? 'Alumni' : semester <= 4 ? 'Junior Student' : 'Senior Student',
      semester: alumni ? null : semester, degree: String(data.degree || ''),
      graduationYear: alumni ? String(data.graduationYear) : null,
      status: 'Pending Email Verification',
    });
    tx.set(otp, {hash: digest(`${uid}:${code}`), attempts: 0,
      sentAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() + 300000)});
  });
  console.log(`EMULATOR ONLY — verification code for ${uid}: ${code}`);
  return {sent: true};
});

exports.verifyEmailCode = onCall(async request => {
  const uid = requireUser(request);
  const error = await db.runTransaction(async tx => {
    const ref = db.doc(`emailChallenges/${uid}`);
    const accountRef = db.doc(`accounts/${uid}`);
    const [challenge, account] = await Promise.all([tx.get(ref), tx.get(accountRef)]);
    if (!account.exists) return 'Register your account first.';
    if (!challenge.exists && account.data().status !== 'Pending Email Verification') return null;
    if (!challenge.exists) return 'Request a new verification code.';
    const data = challenge.data();
    if (data.attempts >= 5 || data.expiresAt.toMillis() < Date.now()) return 'Code expired or attempt limit reached.';
    if (data.hash !== digest(`${uid}:${String(request.data.code)}`)) {
      tx.update(ref, {attempts: data.attempts + 1});
      return 'That code did not work. Try again.';
    }
    tx.update(accountRef, {status: account.data().category === 'Alumni' ? 'Pending Admin Review' : 'Active'});
    tx.delete(ref);
    return null;
  });
  if (error) throw new HttpsError('invalid-argument', error);
  await getAuth().updateUser(uid, {emailVerified: true});
  return {verified: true};
});

exports.reviewAlumni = onCall(async request => {
  const actor = requireUser(request);
  if (request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  const {uid, decision, reason} = request.data;
  const states = {approve: 'Active', reject: 'Rejected', information: 'Needs Information'};
  if (typeof uid !== 'string' || !states[decision] ||
      (decision !== 'approve' && !String(reason || '').trim())) {
    throw new HttpsError('invalid-argument', 'Provide a valid review decision and reason.');
  }
  await db.runTransaction(async tx => {
    const ref = db.doc(`accounts/${uid}`);
    const snapshot = await tx.get(ref);
    if (!snapshot.exists || snapshot.data().category !== 'Alumni' ||
        !['Pending Admin Review', 'Needs Information', 'Rejected'].includes(snapshot.data().status)) {
      throw new HttpsError('failed-precondition', 'This application is not awaiting review.');
    }
    tx.update(ref, {status: states[decision], reviewReason: String(reason || ''), reviewedAt: Timestamp.now()});
    tx.create(db.collection('auditLog').doc(), {actor, action: decision, target: uid, timestamp: Timestamp.now()});
  });
  return {status: states[decision]};
});

function text(value, limit = 200) {
  if (typeof value !== 'string' || value.trim().length > limit) {
    throw new HttpsError('invalid-argument', 'Please check the submitted fields.');
  }
  return value.trim();
}

exports.saveProfile = onCall(async request => {
  const uid = requireUser(request);
  const data = request.data;
  const fields = {
    name: text(data.name, 100), department: text(data.department, 100),
    bio: text(data.bio, 1000), skills: text(data.skills, 500),
    company: text(data.company, 100), jobTitle: text(data.jobTitle, 100),
  };
  if (!fields.name || !fields.department) throw new HttpsError('invalid-argument', 'Name and department are required.');
  await db.runTransaction(async tx => {
    const ref = db.doc(`accounts/${uid}`);
    const account = await tx.get(ref);
    if (!account.exists || account.data().status !== 'Active') throw new HttpsError('permission-denied', 'An active account is required.');
    tx.update(ref, fields);
    tx.set(db.doc(`profiles/${uid}`), {...fields, category: account.data().category,
      semester: account.data().semester, degree: account.data().degree,
      graduationYear: account.data().graduationYear});
  });
  return {saved: true};
});

exports.resubmitAlumni = onCall(async request => {
  const uid = requireUser(request);
  const degree = text(request.data.degree, 100);
  const graduationYear = text(request.data.graduationYear, 4);
  if (!degree || !/^\d{4}$/.test(graduationYear)) throw new HttpsError('invalid-argument', 'Enter your degree and graduation year.');
  await db.runTransaction(async tx => {
    const ref = db.doc(`accounts/${uid}`);
    const account = await tx.get(ref);
    if (!account.exists || account.data().category !== 'Alumni' || account.data().status !== 'Needs Information') {
      throw new HttpsError('failed-precondition', 'An administrator must request information before resubmission.');
    }
    tx.update(ref, {degree, graduationYear, status: 'Pending Admin Review', resubmittedAt: Timestamp.now()});
  });
  return {submitted: true};
});

exports.createCommunity = onCall(async request => {
  const actor = requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access is required.');
  const name = text(request.data.name, 100);
  const description = text(request.data.description, 1000);
  const operationId = text(request.data.operationId, 100);
  if (!name || !description || !/^[a-zA-Z0-9-]+$/.test(operationId)) throw new HttpsError('invalid-argument', 'Name and description are required.');
  const id = digest(`${actor}:${operationId}`);
  await db.runTransaction(async tx => {
    const ref = db.doc(`communities/${id}`);
    const nameRef = db.doc(`communityNames/${digest(name.toLowerCase())}`);
    const [existing, reserved] = await Promise.all([tx.get(ref), tx.get(nameRef)]);
    if (existing.exists) return;
    if (reserved.exists) throw new HttpsError('already-exists', 'A community with this name already exists.');
    tx.create(nameRef, {communityId: id});
    tx.create(ref, {name, description, status: 'Active', createdBy: actor, createdAt: Timestamp.now()});
    tx.create(db.collection('auditLog').doc(), {actor, action: 'createCommunity', target: id, timestamp: Timestamp.now()});
  });
  return {id};
});

exports.setCommunityMembership = onCall(async request => {
  const uid = requireUser(request);
  const communityId = text(request.data.communityId, 100);
  if (!/^[a-zA-Z0-9-]+$/.test(communityId) || typeof request.data.join !== 'boolean') throw new HttpsError('invalid-argument', 'Invalid membership request.');
  await db.runTransaction(async tx => {
    const [account, community] = await Promise.all([tx.get(db.doc(`accounts/${uid}`)), tx.get(db.doc(`communities/${communityId}`))]);
    if (!account.exists || account.data().status !== 'Active') throw new HttpsError('permission-denied', 'An active account is required.');
    if (!community.exists || community.data().status !== 'Active') throw new HttpsError('not-found', 'This community is unavailable.');
    const ref = db.doc(`accounts/${uid}/memberships/${communityId}`);
    if (request.data.join) tx.set(ref, {communityId, joinedAt: Timestamp.now()});
    else tx.delete(ref);
  });
  return {saved: true};
});

async function activeMember(uid) {
  const account = await db.doc(`accounts/${uid}`).get();
  if (!account.exists || account.data().status !== 'Active') {
    throw new HttpsError('permission-denied', 'An active account is required.');
  }
  return account.data();
}

async function communityAccess(uid, communityId) {
  const [account, community, membership] = await Promise.all([
    activeMember(uid), db.doc(`communities/${communityId}`).get(),
    db.doc(`accounts/${uid}/memberships/${communityId}`).get(),
  ]);
  if (!community.exists || community.data().status !== 'Active') {
    throw new HttpsError('not-found', 'Community unavailable.');
  }
  if (!membership.exists) throw new HttpsError('permission-denied', 'Join the community first.');
  return account;
}

function communityId(value) {
  const id = text(value, 100);
  if (!/^[A-Za-z0-9-]+$/.test(id)) throw new HttpsError('invalid-argument', 'Invalid community.');
  return id;
}

exports.publishPost = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.communityId);
  const author = await communityAccess(uid, id);
  const title = text(request.data.title, 150);
  const content = text(request.data.content, 3000);
  const operationId = text(request.data.operationId, 100);
  if (!content || !/^[A-Za-z0-9-]+$/.test(operationId)) {
    throw new HttpsError('invalid-argument', 'Write a post before publishing.');
  }
  const postId = digest(`${uid}:${operationId}`);
  const ref = db.doc(`communities/${id}/posts/${postId}`);
  await db.runTransaction(async tx => {
    const existing = await tx.get(ref);
    if (!existing.exists) tx.create(ref, {title, content, authorId: uid,
      authorName: author.name, communityId: id, status: 'Published',
      createdAt: Timestamp.now(), updatedAt: Timestamp.now()});
  });
  return {postId};
});

exports.editPost = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.communityId);
  const postId = communityId(request.data.postId);
  await activeMember(uid);
  const ref = db.doc(`communities/${id}/posts/${postId}`);
  const content = text(request.data.content, 3000);
  const title = request.data.remove === true ? '' : text(request.data.title, 150);
  if (!content && !request.data.remove) throw new HttpsError('invalid-argument', 'Post content is required.');
  await db.runTransaction(async tx => {
    const post = await tx.get(ref);
    if (!post.exists || post.data().authorId !== uid || post.data().status !== 'Published') {
      throw new HttpsError('permission-denied', 'You can edit your own published post.');
    }
    tx.update(ref, request.data.remove ? {status: 'Removed', updatedAt: Timestamp.now()} : {title, content, updatedAt: Timestamp.now()});
  });
  return {saved: true};
});

exports.addComment = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.communityId);
  const postId = communityId(request.data.postId);
  const author = await communityAccess(uid, id);
  const content = text(request.data.content, 1500);
  const operationId = text(request.data.operationId, 100);
  if (!content || !/^[A-Za-z0-9-]+$/.test(operationId)) throw new HttpsError('invalid-argument', 'Write a comment.');
  const commentId = digest(`${uid}:${operationId}`);
  await db.runTransaction(async tx => {
    const post = await tx.get(db.doc(`communities/${id}/posts/${postId}`));
    if (!post.exists || post.data().status !== 'Published') throw new HttpsError('not-found', 'Post unavailable.');
    const ref = db.doc(`communities/${id}/posts/${postId}/comments/${commentId}`);
    const existing = await tx.get(ref);
    if (!existing.exists) tx.create(ref, {authorId: uid, authorName: author.name,
      content, status: 'Published', createdAt: Timestamp.now(), updatedAt: Timestamp.now()});
  });
  return {commentId};
});

exports.editComment = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.communityId);
  const postId = communityId(request.data.postId);
  const commentId = communityId(request.data.commentId);
  await activeMember(uid);
  const content = text(request.data.content, 1500);
  if (!content && !request.data.remove) throw new HttpsError('invalid-argument', 'Comment content is required.');
  await db.runTransaction(async tx => {
    const ref = db.doc(`communities/${id}/posts/${postId}/comments/${commentId}`);
    const comment = await tx.get(ref);
    if (!comment.exists || comment.data().authorId !== uid || comment.data().status !== 'Published') {
      throw new HttpsError('permission-denied', 'You can edit your own published comment.');
    }
    tx.update(ref, request.data.remove ? {status: 'Removed', updatedAt: Timestamp.now()} : {content, updatedAt: Timestamp.now()});
  });
  return {saved: true};
});

exports.setPostReaction = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.communityId);
  const postId = communityId(request.data.postId);
  await communityAccess(uid, id);
  if (typeof request.data.helpful !== 'boolean') throw new HttpsError('invalid-argument', 'Invalid reaction.');
  await db.runTransaction(async tx => {
    const post = await tx.get(db.doc(`communities/${id}/posts/${postId}`));
    if (!post.exists || post.data().status !== 'Published') throw new HttpsError('not-found', 'Post unavailable.');
    const ref = db.doc(`communities/${id}/posts/${postId}/reactions/${uid}`);
    if (request.data.helpful) tx.set(ref, {userId: uid, createdAt: Timestamp.now()});
    else tx.delete(ref);
  });
  return {saved: true};
});

exports.reportPost = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.communityId);
  const postId = communityId(request.data.postId);
  await activeMember(uid);
  const reason = text(request.data.reason, 100);
  if (!reason) throw new HttpsError('invalid-argument', 'Select a report reason.');
  const post = await db.doc(`communities/${id}/posts/${postId}`).get();
  if (!post.exists || post.data().status !== 'Published') throw new HttpsError('not-found', 'Post unavailable.');
  const reportId = digest(`${uid}:${id}:${postId}`);
  await db.doc(`reports/${reportId}`).create({reporterId: uid, communityId: id,
    postId, reason, status: 'Open', snapshot: post.data().content,
    createdAt: Timestamp.now()}).catch(error => {
    if (error.code !== 6) throw error;
  });
  return {submitted: true};
});

exports.moderatePost = onCall(async request => {
  const actor = requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access is required.');
  const reportId = communityId(request.data.reportId);
  const decision = request.data.decision;
  if (!['dismiss', 'remove'].includes(decision)) throw new HttpsError('invalid-argument', 'Invalid decision.');
  await db.runTransaction(async tx => {
    const ref = db.doc(`reports/${reportId}`);
    const report = await tx.get(ref);
    if (!report.exists || report.data().status !== 'Open') throw new HttpsError('failed-precondition', 'Report already reviewed.');
    const postRef = db.doc(`communities/${report.data().communityId}/posts/${report.data().postId}`);
    if (decision === 'remove') {
      const post = await tx.get(postRef);
      if (post.exists) tx.update(postRef, {status: 'Removed', updatedAt: Timestamp.now()});
    }
    tx.update(ref, {status: decision === 'remove' ? 'Actioned' : 'Dismissed',
      resolution: decision, resolvedBy: actor, resolvedAt: Timestamp.now()});
    tx.create(db.collection('auditLog').doc(), {actor, action: `report:${decision}`,
      target: reportId, timestamp: Timestamp.now()});
  });
  return {reviewed: true};
});

// Mentorship defaults can be configured before deployment.
const mentorshipLimit = Math.max(1, Number(process.env.MENTORSHIP_PENDING_LIMIT) || 5);
const mentorshipCooldownMs = Math.max(0, Number(process.env.MENTORSHIP_COOLDOWN_DAYS) || 7) * 86400000;
const mentorEligible = account => account.status === 'Active' && ['Senior Student', 'Alumni'].includes(account.category);
exports.listMentors = onCall(async request => {
  await activeMember(requireUser(request));
  let query = db.collection('accounts').where('status', '==', 'Active')
    .where('category', 'in', ['Senior Student', 'Alumni']).orderBy('__name__').limit(30);
  if (request.data?.cursor) query = query.startAfter(text(request.data.cursor, 128));
  const result = await query.get();
  return {mentors: result.docs.map(doc => {
    const a = doc.data();
    return {id: doc.id, name: a.name, category: a.category, department: a.department || '',
      skills: a.skills || '', bio: a.bio || '', company: a.company || '', jobTitle: a.jobTitle || '',
      available: a.mentorshipAvailable !== false};
  }), cursor: result.size === 30 ? result.docs[result.size - 1].id : null};
});
exports.setMentorshipAvailability = onCall(async request => {
  const uid = requireUser(request);
  if (typeof request.data.available !== 'boolean') throw new HttpsError('invalid-argument', 'Choose availability.');
  await db.runTransaction(async tx => {
    const ref = db.doc(`accounts/${uid}`);
    const account = await tx.get(ref);
    if (!account.exists || !mentorEligible(account.data())) throw new HttpsError('permission-denied', 'An active mentor account is required.');
    tx.update(ref, {mentorshipAvailable: request.data.available});
  });
  return {saved: true};
});
exports.requestMentorship = onCall(async request => {
  const uid = requireUser(request);
  const mentorId = text(request.data.mentorId, 128);
  const message = text(request.data.message, 1000);
  if (!mentorId || mentorId.includes('/') || mentorId === uid || !message) throw new HttpsError('invalid-argument', 'Choose another mentor and write a request message.');
  const id = digest(`${uid}:${mentorId}`);
  await db.runTransaction(async tx => {
    const senderRef = db.doc(`accounts/${uid}`);
    const ref = db.doc(`mentorshipRequests/${id}`);
    const [sender, mentor, existing, pending] = await Promise.all([
      tx.get(senderRef), tx.get(db.doc(`accounts/${mentorId}`)), tx.get(ref),
      tx.get(db.collection('mentorshipRequests').where('requesterId', '==', uid).where('status', '==', 'Pending')),
    ]);
    if (!sender.exists || sender.data().status !== 'Active' || !['Junior Student', 'Senior Student'].includes(sender.data().category)) throw new HttpsError('permission-denied', 'An active student account is required.');
    if (!mentor.exists || !mentorEligible(mentor.data()) || mentor.data().mentorshipAvailable === false) throw new HttpsError('failed-precondition', 'This mentor is currently unavailable.');
    if (existing.exists && ['Pending', 'Accepted'].includes(existing.data().status)) throw new HttpsError('already-exists', 'You already have a pending or accepted request with this mentor.');
    if (existing.exists && existing.data().status === 'Rejected' && Date.now() - existing.data().updatedAt.toMillis() < mentorshipCooldownMs) throw new HttpsError('failed-precondition', 'Please wait before requesting this mentor again.');
    if (pending.size >= mentorshipLimit) throw new HttpsError('resource-exhausted', `You can have up to ${mentorshipLimit} pending requests.`);
    tx.set(ref, {requesterId: uid, mentorId, requesterName: sender.data().name, mentorName: mentor.data().name,
      message, status: 'Pending', conversationAuthorized: false, createdAt: Timestamp.now(), updatedAt: Timestamp.now()});
    // Serialize concurrent requests from one student, including requests to different mentors.
    tx.update(senderRef, {lastMentorshipRequestAt: Timestamp.now()});
  });
  return {id};
});
exports.respondMentorship = onCall(async request => {
  const uid = requireUser(request);
  const id = communityId(request.data.id);
  const action = request.data.action;
  if (!['accept', 'reject', 'cancel'].includes(action)) throw new HttpsError('invalid-argument', 'Invalid action.');
  await db.runTransaction(async tx => {
    const ref = db.doc(`mentorshipRequests/${id}`);
    const [account, record] = await Promise.all([tx.get(db.doc(`accounts/${uid}`)), tx.get(ref)]);
    if (!account.exists || account.data().status !== 'Active' || !record.exists) throw new HttpsError('permission-denied', 'Request unavailable.');
    const data = record.data();
    if ((action === 'cancel' ? data.requesterId : data.mentorId) !== uid) throw new HttpsError('permission-denied', 'You cannot change this request.');
    if (data.status !== 'Pending') throw new HttpsError('failed-precondition', 'This request has already been resolved.');
    if (action !== 'cancel') {
      const student = await tx.get(db.doc(`accounts/${data.requesterId}`));
      if (!mentorEligible(account.data()) || !student.exists || student.data().status !== 'Active') throw new HttpsError('failed-precondition', 'Both accounts must be eligible and active.');
    }
    const status = {accept: 'Accepted', reject: 'Rejected', cancel: 'Cancelled'}[action];
    tx.update(ref, {status, conversationAuthorized: action === 'accept', updatedAt: Timestamp.now()});
  });
  return {saved: true};
});
