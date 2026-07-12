const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

let testEnv;

const barcode = '0123456789012';

const validAggregateData = () => ({
    schemaVersion: 1,
    modelVersion: 'community_consensus_v1',
    status: 'published',
    barcode,
    name: 'Protein Bar',
    calories: 210,
    protein: 20,
    carbs: 22,
    fats: 7,
    fiber: 3,
    servingSize: '1 bar (60g)',
    servingWeight: 60,
    contributorCount: 3,
    agreementCount: 3,
    conflictCount: 0,
    agreementRatio: 1,
    revision: 1,
    updatedAt: new Date(),
});

const privateContributionData = () => ({
    schemaVersion: 1,
    barcode,
    name: 'Protein Bar',
    calories: 210,
    protein: 20,
    carbs: 22,
    fats: 7,
    fiber: 3,
    servingSize: '1 bar (60g)',
    servingWeight: 60,
    updatedAt: new Date(),
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
    describe('Community Barcode Corrections', () => {
        it('should permanently deny the legacy contributor-owned pool', async () => {
            const ref = testEnv.authenticatedContext('alice')
                .firestore().collection('barcodes').doc(barcode);
            await assertFails(ref.get());
            await assertFails(ref.set({ createdBy: 'alice' }));
        });

        it('should force private contribution creation and updates through Admin callables', async () => {
            const ref = testEnv.authenticatedContext('alice')
                .firestore().collection('users').doc('alice')
                .collection('barcodeContributions').doc(barcode);
            await assertFails(ref.set(privateContributionData()));
            await assertFails(ref.update({ calories: 220 }));
        });

        it('should let an owner read or withdraw only their own private contribution', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('users').doc('alice')
                    .collection('barcodeContributions').doc(barcode)
                    .set(privateContributionData());
            });

            const aliceRef = testEnv.authenticatedContext('alice')
                .firestore().collection('users').doc('alice')
                .collection('barcodeContributions').doc(barcode);
            const bobRef = testEnv.authenticatedContext('bob')
                .firestore().collection('users').doc('alice')
                .collection('barcodeContributions').doc(barcode);
            await assertSucceeds(aliceRef.get());
            await assertFails(bobRef.get());
            await assertSucceeds(aliceRef.delete());
        });

        it('should allow a known validated aggregate only when the private config enables reads', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: false });
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set(validAggregateData());
            });

            const ref = testEnv.authenticatedContext('alice')
                .firestore().collection('communityBarcodeAggregates').doc(barcode);
            await assertSucceeds(ref.get());
        });

        it('should deny aggregate reads when config is missing, disabled, or killed', async () => {
            const alice = testEnv.authenticatedContext('alice');
            const ref = alice.firestore().collection('communityBarcodeAggregates').doc(barcode);
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set(validAggregateData());
            });
            await assertFails(ref.get());

            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: true });
            });
            await assertFails(ref.get());
        });

        it('should reject under-threshold or identifier-bearing aggregate documents', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: false });
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set({
                        ...validAggregateData(),
                        contributorCount: 2,
                        agreementCount: 2,
                        createdBy: 'private-user',
                    });
            });

            const ref = testEnv.authenticatedContext('alice')
                .firestore().collection('communityBarcodeAggregates').doc(barcode);
            await assertFails(ref.get());
        });

        it('should reject an aggregate whose published ratio disagrees with its counts', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: false });
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set({ ...validAggregateData(), agreementRatio: 0.9 });
            });

            const ref = testEnv.authenticatedContext('alice')
                .firestore().collection('communityBarcodeAggregates').doc(barcode);
            await assertFails(ref.get());
        });

        it('should validate rounded ratios even with a large contributor set', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: false });
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set({
                        ...validAggregateData(),
                        contributorCount: 101,
                        agreementCount: 70,
                        conflictCount: 31,
                        agreementRatio: 0.693,
                    });
            });

            const ref = testEnv.authenticatedContext('alice')
                .firestore().collection('communityBarcodeAggregates').doc(barcode);
            await assertSucceeds(ref.get());
        });

        it('should forbid aggregate listing and every client write', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: false });
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set(validAggregateData());
            });

            const collection = testEnv.authenticatedContext('alice')
                .firestore().collection('communityBarcodeAggregates');
            await assertFails(collection.get());
            await assertFails(collection.doc(barcode).set(validAggregateData()));
            await assertFails(collection.doc(barcode).delete());
        });

        it('should deny unauthenticated aggregate reads', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('internalConfig')
                    .doc('communityBarcodeAggregation')
                    .set({ publicReadsEnabled: true, aggregationEnabled: true, killSwitch: false });
                await context.firestore().collection('communityBarcodeAggregates')
                    .doc(barcode).set(validAggregateData());
            });
            const ref = testEnv.unauthenticatedContext()
                .firestore().collection('communityBarcodeAggregates').doc(barcode);
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
