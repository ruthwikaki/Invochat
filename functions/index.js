
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.syncUserClaims = functions.firestore
  .document('user_profiles/{userId}')
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const data = change.after.exists ? change.after.data() : null;
    
    if (!data) {
      console.log(`User profile for ${userId} deleted, removing claims.`);
      await admin.auth().setCustomUserClaims(userId, null);
      return;
    }
    
    console.log(`Updating claims for ${userId}:`, { companyId: data.company_id, role: data.role });
    await admin.auth().setCustomUserClaims(userId, {
      companyId: data.company_id,
      role: data.role
    });
  });
