'use strict';

// Minimal in-memory stand-in for the Firestore Admin SDK — just enough of the
// surface the migration runner and migrations use (collection/doc/get/set/update).
// Lets us unit-test migration logic with zero dependencies and no emulator/Java.

class FakeFirestore {
  constructor(seed = {}) {
    // store[collectionPath][docId] = data object
    this.store = {};
    for (const [coll, docs] of Object.entries(seed)) {
      this.store[coll] = {};
      for (const [id, data] of Object.entries(docs)) this.store[coll][id] = { ...data };
    }
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  _docs(path) {
    this.store[path] = this.store[path] || {};
    return this.store[path];
  }
}

class FakeCollectionRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.db, this.path, id);
  }

  async get() {
    const docs = Object.entries(this.db._docs(this.path)).map(
      ([id, data]) => new FakeDocSnap(this.db, this.path, id, data)
    );
    return {
      docs,
      size: docs.length,
      empty: docs.length === 0,
      forEach: (fn) => docs.forEach(fn),
    };
  }
}

class FakeDocRef {
  constructor(db, path, id) {
    this.db = db;
    this.path = path;
    this.id = id;
  }

  async get() {
    const data = this.db._docs(this.path)[this.id];
    return new FakeDocSnap(this.db, this.path, this.id, data);
  }

  async set(data, opts = {}) {
    const docs = this.db._docs(this.path);
    docs[this.id] = opts.merge ? { ...(docs[this.id] || {}), ...data } : { ...data };
  }

  async update(data) {
    const docs = this.db._docs(this.path);
    if (docs[this.id] === undefined) {
      throw new Error(`No document to update at ${this.path}/${this.id}`);
    }
    docs[this.id] = { ...docs[this.id], ...data };
  }
}

class FakeDocSnap {
  constructor(db, path, id, data) {
    this.id = id;
    this._data = data;
    this.exists = data !== undefined;
    this.ref = new FakeDocRef(db, path, id);
  }

  data() {
    return this._data === undefined ? undefined : { ...this._data };
  }
}

module.exports = { FakeFirestore };
