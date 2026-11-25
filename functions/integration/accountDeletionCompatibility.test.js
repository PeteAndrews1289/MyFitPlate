const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");

// The production handlers below remove Auth users and recursively delete Firestore data.
// Run them only against both local emulators, in a synthetic project of our own.
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8080");
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, "127.0.0.1:9099");
const projectId = "demo-myfitplate-release-compatibility";
process.env.GCLOUD_PROJECT = projectId;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});

const {deleteUserData, purgeCompletedAccountDeletionBarriers} = require("../lib/index.js");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

test("2.3 and 2.4 deletion requests and an interrupted deletion preserve the other account", async () => {
  const db = getFirestore();
  const auth = getAuth();
  const survivor = await auth.createUser({uid: randomUUID()});
  const program = db.doc(`users/${survivor.uid}/workoutPrograms/phul`);
  const diary = db.doc(`users/${survivor.uid}/dailyLogs/2026-11-01`);
  const progress = {name: "PHUL", completedWorkouts: 39};
  const log = {meals: [{name: "Lunch"}], waterTracker: {totalOunces: 16}};
  await program.set(progress);
  await diary.set(log);

  for (const client of ["2.3", "2.4", "interrupted"]) {
    const {uid} = await auth.createUser({uid: randomUUID()});
    const profile = db.doc(`users/${uid}`);
    const session = profile.collection("workoutSessionLogs").doc("training");
    const barrier = db.doc(`accountDeletionBarriers/${uid}`);
    await profile.set({activeProgramID: "phul"});
    await session.set({routineID: "lower-power"});
    if (client === "interrupted") {
      await barrier.set({status: "deleting", nextAttemptAt: Timestamp.fromMillis(1)});
      await purgeCompletedAccountDeletionBarriers.run({scheduleTime: new Date().toISOString()});
    } else {
      const identity = {uid, token: {auth_time: Math.floor(Date.now() / 1000)}};
      if (client === "2.4") {
        await assert.rejects(deleteUserData.run({auth: identity, data: {expectedUserID: survivor.uid}}),
          {code: "permission-denied"});
        assert.equal((await barrier.get()).exists, false);
      }
      const data = client === "2.3" ? null : {expectedUserID: uid};
      assert.deepEqual(await deleteUserData.run({auth: identity, data}), {deleted: true});
    }
    await assert.rejects(auth.getUser(uid), {code: "auth/user-not-found"});
    assert.equal((await profile.get()).exists, false);
    assert.equal((await session.get()).exists, false);
    assert.equal((await barrier.get()).get("status"), "complete");
  }
  assert.equal((await auth.getUser(survivor.uid)).uid, survivor.uid);
  assert.deepEqual((await program.get()).data(), progress);
  assert.deepEqual((await diary.get()).data(), log);
});
