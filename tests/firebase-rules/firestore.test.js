const { assert, expect } = require('chai');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

let testEnv;

const validBarcodeData = (createdBy = 'alice') => ({
    name: 'Protein Bar',
    calories: 210,
    protein: 20,
    carbs: 22,
    fats: 7,
    fiber: 3,
    servingSize: '1 bar (60g)',
    servingWeight: 60,
    createdBy,
});

describe('MyFitPlate Firestore Rules', () => {

    before(async () => {
        testEnv = await initializeTestEnvironment({
            projectId: "myfitplate-test-project",
            firestore: {
                rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
            },
        });
    });

    after(async () => {
        await testEnv.cleanup();
    });

    beforeEach(async () => {
        await testEnv.clearFirestore();
    });

    // MARK: - Users Collection
    describe('Users Collection', () => {
        it('should allow users to read their own document', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('users').doc('alice');
            await assertSucceeds(ref.get());
        });

        it('should deny users reading other users documents', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('users').doc('bob');
            await assertFails(ref.get());
        });

        it('should allow users to write to their own document', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('users').doc('alice');
            await assertSucceeds(ref.set({ name: 'Alice' }));
        });

        it('should deny users writing to other users documents', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('users').doc('bob');
            await assertFails(ref.set({ name: 'Bob by Alice' }));
        });

        it('should allow users to write to their own subcollections', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('users').doc('alice').collection('dailyLogs').doc('log1');
            await assertSucceeds(ref.set({ calories: 500 }));
        });

        it('should deny users writing to other users subcollections', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('users').doc('bob').collection('dailyLogs').doc('log1');
            await assertFails(ref.set({ calories: 500 }));
        });
    });

    // MARK: - Posts Collection
    describe('Posts Collection', () => {
        it('should allow any signed in user to read posts', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('posts').doc('post1');
            await assertSucceeds(ref.get());
        });

        it('should allow authors to create posts', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('posts').doc('post1');
            await assertSucceeds(ref.set({ authorID: 'alice', content: 'hello' }));
        });

        it('should deny users creating posts with someone elses authorID', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('posts').doc('post1');
            await assertFails(ref.set({ authorID: 'bob', content: 'hello' }));
        });
    });

    // MARK: - Groups Collection
    describe('Groups Collection', () => {
        it('should allow signed in users to read groups', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('groups').doc('group1');
            await assertSucceeds(ref.get());
        });

        it('should allow users to create groups if they are creator', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('groups').doc('group1');
            await assertSucceeds(ref.set({ creatorID: 'alice', name: 'My Group' }));
        });

        it('should deny users creating groups with someone elses creatorID', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('groups').doc('group1');
            await assertFails(ref.set({ creatorID: 'bob', name: 'Bob Group' }));
        });
    });

    // MARK: - Community Barcode Corrections
    describe('Barcode Collection', () => {
        it('should allow a signed-in user to create a complete validated GTIN entry', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('barcodes').doc('0123456789012');
            await assertSucceeds(ref.set(validBarcodeData()));
        });

        it('should reject malformed barcode ids and incomplete serving evidence', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const malformed = alice.firestore().collection('barcodes').doc('12345');
            await assertFails(malformed.set(validBarcodeData()));

            const incomplete = alice.firestore().collection('barcodes').doc('0123456789012');
            const data = validBarcodeData();
            delete data.servingWeight;
            await assertFails(incomplete.set(data));
        });

        it('should reject forged ownership and unknown fields', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const forged = alice.firestore().collection('barcodes').doc('0123456789012');
            await assertFails(forged.set(validBarcodeData('bob')));
            await assertFails(forged.set({ ...validBarcodeData(), moderationBypass: true }));
        });

        it('should allow only the original contributor to update an entry', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('barcodes').doc('0123456789012').set(validBarcodeData());
            });

            const aliceRef = testEnv.authenticatedContext('alice')
                .firestore().collection('barcodes').doc('0123456789012');
            const bobRef = testEnv.authenticatedContext('bob')
                .firestore().collection('barcodes').doc('0123456789012');

            await assertSucceeds(aliceRef.set({ ...validBarcodeData(), calories: 220 }));
            await assertFails(bobRef.set(validBarcodeData('bob')));
        });

        it('should deny unauthenticated reads', async () => {
            const ref = testEnv.unauthenticatedContext()
                .firestore().collection('barcodes').doc('0123456789012');
            await assertFails(ref.get());
        });
    });
    
    // MARK: - Unauthenticated
    describe('Unauthenticated access', () => {
        it('should deny read to posts for unauthenticated users', async () => {
            const unauth = testEnv.unauthenticatedContext();
            const ref = unauth.firestore().collection('posts').doc('post1');
            await assertFails(ref.get());
        });
    });
});
