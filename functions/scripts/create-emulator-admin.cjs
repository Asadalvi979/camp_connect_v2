// Local emulator bootstrap only. Credentials are supplied by the developer.
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
if (process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') {
  throw new Error('Set FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 for this local-only script.');
}
if (!process.env.CAMP_ADMIN_EMAIL || !process.env.CAMP_ADMIN_PASSWORD) {
  throw new Error('Set CAMP_ADMIN_EMAIL and CAMP_ADMIN_PASSWORD locally.');
}
initializeApp({projectId: 'demo-campconnect'});
(async () => {
  const auth = getAuth();
  let user;
  try { user = await auth.getUserByEmail(process.env.CAMP_ADMIN_EMAIL); }
  catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  if (!user) user = await auth.createUser({email: process.env.CAMP_ADMIN_EMAIL, password: process.env.CAMP_ADMIN_PASSWORD, emailVerified: true});
  await auth.setCustomUserClaims(user.uid, {...user.customClaims, admin: true});
  console.log('Local administrator ready. Sign out and sign in to refresh permissions.');
})().catch(error => {console.error(error.message); process.exitCode = 1;});
