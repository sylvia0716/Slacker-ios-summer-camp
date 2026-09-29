const {test} = require('node:test');
const assert = require('node:assert/strict');
const {proStatusForUser} = require('./revenuecat-entitlement');

const check = (entitlement, status = 200) => proStatusForUser('firebase-user', {
  key: 'test-public-key', now: Date.parse('2026-09-29T00:00:00Z'),
  fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.revenuecat.com/v1/subscribers/firebase-user');
    assert.equal(options.headers.Authorization, 'Bearer test-public-key');
    return {ok: status === 200, status, json: async () => ({subscriber: {entitlements: entitlement}})};
  },
});

test('only a currently active Pro entitlement unlocks unlimited projects', async () => {
  assert.equal(await check({oops_bomb_pro: {expires_date: '2026-10-01T00:00:00Z'}}), 'active');
  assert.equal(await check({oops_bomb_pro: {expires_date: null}}), 'active');
  assert.equal(await check({oops_bomb_pro: {expires_date: '2026-09-01T00:00:00Z'}}), 'inactive');
  assert.equal(await check({oops_bomb_pro: {expires_date: '2026-09-01T00:00:00Z',
    grace_period_expires_date: '2026-10-01T00:00:00Z'}}), 'active');
  assert.equal(await check({}), 'inactive');
});

test('missing subscribers remain free; service failures are not treated as active', async () => {
  assert.equal(await check({}, 404), 'inactive');
  assert.equal(await check({}, 500), 'unknown');
  assert.equal(await proStatusForUser('firebase-user', {key: 'test-public-key', fetchImpl: async () => {throw Error('offline');}}), 'unknown');
});
