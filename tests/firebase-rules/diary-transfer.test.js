const { describe, it, before, after, beforeEach } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

// These are rules/atomic-commit fixtures. Core and native encoding tests separately
// verify food snapshots, portion math and the production receipt contract.
describe('Diary transfer transaction permissions', () => {
    let testEnv;
    const sourceKey = '2026-10-29';
    const destinationKey = '2026-10-30';
    const food = { id: 'consumption-1', name: 'Oats', calories: 200, calcium: 140,
        sourceMetadata: { sourceType: 'userEntered', sourceName: 'Original label' } };
    const day = foods => ({ date: new Date('2026-10-29T12:00:00Z'), meals: [
        { id: 'meal-1', name: 'Breakfast', foodItems: foods },
    ], waterTracker: { totalOunces: 16, goalOunces: 64 } });

    before(async () => {
        testEnv = await initializeTestEnvironment({
            projectId: `${process.env.FIREBASE_RULES_TEST_PROJECT || 'myfitplate-test-project'}-transfer`,
            firestore: { rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8') },
        });
    });
    after(async () => { await testEnv.cleanup(); });
    beforeEach(async () => { await testEnv.clearFirestore(); });

    async function seed() {
        await testEnv.withSecurityRulesDisabled(async context => {
            const db = context.firestore();
            await db.doc(`users/alice/dailyLogs/${sourceKey}`).set(day([food]));
            await db.doc(`users/alice/dailyLogs/${destinationKey}`).set(day([]));
        });
    }

    async function move(db, destinationOwner = 'alice', operationID = 'stable-operation') {
        const source = db.doc(`users/alice/dailyLogs/${sourceKey}`);
        const destination = db.doc(`users/${destinationOwner}/dailyLogs/${destinationKey}`);
        const receipt = db.doc(`users/alice/diaryTransferReceipts/${operationID}`);
        return db.runTransaction(async transaction => {
            const accepted = await transaction.get(receipt);
            const sourceSnapshot = await transaction.get(source);
            const destinationSnapshot = await transaction.get(destination);
            if (accepted.exists) return false;
            const original = sourceSnapshot.data();
            const target = destinationSnapshot.exists ? destinationSnapshot.data() : day([]);
            const moving = original.meals[0].foodItems.find(item => item.id === food.id);
            assert.ok(moving, 'A source snapshot must exist before either day changes');
            original.meals[0].foodItems = original.meals[0].foodItems.filter(item => item.id !== food.id);
            target.meals[0].foodItems.push(moving);
            transaction.set(source, { meals: original.meals }, { merge: true });
            transaction.set(destination, { meals: target.meals }, { merge: true });
            transaction.set(receipt, { schemaVersion: 1, commandFingerprint: 'fixture-fingerprint', acceptedAt: new Date() });
            return true;
        });
    }

    it('commits source, destination and a stable owner receipt together and retries once', async () => {
        await seed();
        const db = testEnv.authenticatedContext('alice').firestore();
        assert.equal(await assertSucceeds(move(db)), true);
        assert.equal(await assertSucceeds(move(db)), false);
        assert.equal((await db.doc(`users/alice/dailyLogs/${sourceKey}`).get()).data().meals[0].foodItems.length, 0);
        const destination = (await db.doc(`users/alice/dailyLogs/${destinationKey}`).get()).data();
        assert.deepEqual(destination.meals[0].foodItems, [food]);
        assert.equal(destination.waterTracker.totalOunces, 16);
        assert.equal((await db.doc('users/alice/diaryTransferReceipts/stable-operation').get()).exists, true);
    });

    it('denies another owner and leaves the source and receipt untouched', async () => {
        await seed();
        const alice = testEnv.authenticatedContext('alice').firestore();
        await assertFails(move(alice, 'bob'));
        assert.deepEqual((await alice.doc(`users/alice/dailyLogs/${sourceKey}`).get()).data().meals[0].foodItems, [food]);
        assert.equal((await alice.doc('users/alice/diaryTransferReceipts/stable-operation').get()).exists, false);
        const bob = testEnv.authenticatedContext('bob').firestore();
        await assertFails(bob.doc('users/alice/diaryTransferReceipts/stable-operation').get());
        await assertFails(bob.doc('users/alice/diaryTransferReceipts/forged').set({ acceptedAt: new Date() }));
    });

    it('blocks an account deletion barrier without partially removing the source', async () => {
        await seed();
        await testEnv.withSecurityRulesDisabled(async context => {
            await context.firestore().doc('accountDeletionBarriers/alice').set({ status: 'deleting', updatedAt: new Date() });
        });
        await assertFails(move(testEnv.authenticatedContext('alice').firestore()));
        await testEnv.withSecurityRulesDisabled(async context => {
            const db = context.firestore();
            assert.deepEqual((await db.doc(`users/alice/dailyLogs/${sourceKey}`).get()).data().meals[0].foodItems, [food]);
            assert.equal((await db.doc(`users/alice/dailyLogs/${destinationKey}`).get()).data().meals[0].foodItems.length, 0);
            assert.equal((await db.doc('users/alice/diaryTransferReceipts/stable-operation').get()).exists, false);
        });
    });

    it('keeps legacy diary documents compatible without adding required transfer fields', async () => {
        const alice = testEnv.authenticatedContext('alice').firestore();
        const ref = alice.doc(`users/alice/dailyLogs/${sourceKey}`);
        await assertSucceeds(ref.set(day([food])));
        await assertSucceeds(ref.update({ totalCaloriesOverride: 700 }));
        const actual = (await assertSucceeds(ref.get())).data();
        assert.equal(actual.totalCaloriesOverride, 700);
        assert.equal(Object.hasOwn(actual, 'transferVersion'), false);
        await assertSucceeds(alice.doc('users/alice/diaryTransferReceipts/new-client').set({ acceptedAt: new Date() }));
        await assertSucceeds(ref.set(day([food]), { merge: true }));
        assert.equal((await alice.doc('users/alice/diaryTransferReceipts/new-client').get()).exists, true);
    });
});
