const { assert, expect } = require('chai');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

let testEnv;

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
    
    // MARK: - Unauthenticated
    describe('Unauthenticated access', () => {
        it('should deny read to posts for unauthenticated users', async () => {
            const unauth = testEnv.unauthenticatedContext();
            const ref = unauth.firestore().collection('posts').doc('post1');
            await assertFails(ref.get());
        });
    });
});
