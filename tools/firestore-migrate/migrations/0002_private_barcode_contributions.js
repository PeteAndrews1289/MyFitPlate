'use strict';

const supportedLengths = new Set([8, 12, 13, 14]);

function validGTIN(value) {
  if (typeof value !== 'string' || !supportedLengths.has(value.length) || !/^[0-9]+$/.test(value)) {
    return false;
  }
  const checkDigit = Number(value[value.length - 1]);
  const payload = value.slice(0, -1).split('').reverse();
  const weightedSum = payload.reduce(
    (sum, digit, index) => sum + Number(digit) * (index % 2 === 0 ? 3 : 1),
    0
  );
  return (10 - (weightedSum % 10)) % 10 === checkDigit;
}

function finiteNumber(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function privateContribution(barcode, data) {
  if (
    !validGTIN(barcode) ||
    typeof data.createdBy !== 'string' || data.createdBy.length === 0 ||
    typeof data.name !== 'string' || data.name.trim().length === 0 || data.name.trim().length > 140 ||
    typeof data.servingSize !== 'string' || data.servingSize.trim().length === 0 ||
    data.servingSize.trim().length > 80 ||
    !finiteNumber(data.calories, 0, 5000) ||
    !finiteNumber(data.protein, 0, 1000) ||
    !finiteNumber(data.carbs, 0, 1000) ||
    !finiteNumber(data.fats, 0, 1000) ||
    !finiteNumber(data.servingWeight, 10, 5000) ||
    (data.fiber !== undefined && !finiteNumber(data.fiber, 0, 1000))
  ) {
    return undefined;
  }

  return {
    schemaVersion: 1,
    barcode,
    name: data.name.trim(),
    calories: data.calories,
    protein: data.protein,
    carbs: data.carbs,
    fats: data.fats,
    ...(data.fiber === undefined ? {} : { fiber: data.fiber }),
    servingSize: data.servingSize.trim(),
    servingWeight: data.servingWeight,
    updatedAt: data.updatedAt || new Date(),
  };
}

module.exports = {
  id: '0002',
  name: 'move legacy barcode corrections into private user paths',

  async up(db, { dryRun, log }) {
    const snapshot = await db.collection('barcodes').get();
    let changed = 0;
    let skipped = 0;

    for (const document of snapshot.docs) {
      const legacy = document.data() || {};
      const contribution = privateContribution(document.id, legacy);
      if (contribution === undefined) {
        skipped += 1;
        continue;
      }

      const privateRef = db.collection(`users/${legacy.createdBy}/barcodeContributions`).doc(document.id);
      if (!dryRun) {
        const existing = await privateRef.get();
        if (!existing.exists) {
          await privateRef.set(contribution);
        }
        await document.ref.delete();
      }
      changed += 1;
    }

    log(`${dryRun ? 'would move' : 'moved'} ${changed} legacy correction(s); skipped ${skipped}`);
    return changed;
  },

  privateContribution,
  validGTIN,
};
