import test from 'node:test';
import assert from 'node:assert/strict';

test('mismatched passwords stay in the form, retain values, and make no network request', async () => {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, {
      type: 'password', value: '', hidden: false, textContent: '', dataset: {}, attributes: {}, listeners: {},
      addEventListener(type, handler) { this.listeners[type] = handler; },
      setAttribute(key, value) { this.attributes[key] = value; },
      removeAttribute(key) { delete this.attributes[key]; },
      focus() {}, reset() {},
    });
    return elements.get(id);
  };
  const originals = Object.fromEntries(['document', 'location', 'fetch'].map(key => [key, globalThis[key]]));
  let requests = 0;
  globalThis.document = {documentElement: {}, getElementById: element, querySelector: () => element('card'), querySelectorAll: () => []};
  globalThis.location = {hostname: '127.0.0.1', search: '?preview=ready&lang=zh-Hant'};
  globalThis.fetch = async () => { requests++; throw new Error('Unexpected request'); };
  try {
    await import('../public/app.js');
    element('password').value = 'sample-password';
    element('confirmation').value = 'different-password';
    element('confirmation').listeners.blur();
    assert.equal(element('form-error').hidden, false);
    assert.equal(element('card').dataset.state, 'ready');
    await element('reset-form').listeners.submit({preventDefault() {}});
    assert.equal(element('form-error').textContent, '兩次輸入的密碼不一致。');
    assert.equal(element('reset-form').hidden, false);
    assert.equal(element('card').dataset.state, 'ready');
    assert.equal(element('password').value, 'sample-password');
    assert.equal(element('confirmation').value, 'different-password');
    assert.equal(requests, 0);
    element('language').value = 'en';
    element('language').listeners.change();
    assert.equal(element('form-error').textContent, 'The passwords do not match.');
    assert.equal(element('password').value, 'sample-password');
    assert.equal(element('confirmation').value, 'different-password');
    assert.equal(element('card').dataset.state, 'ready');
    assert.equal(globalThis.document.documentElement.lang, 'en');
    assert.equal(requests, 0);
    element('confirmation').value = 'sample-password';
    element('reset-form').listeners.input();
    assert.equal(element('form-error').hidden, true);
    assert.equal(element('confirmation').attributes['aria-invalid'], undefined);
  } finally {
    for (const [key, value] of Object.entries(originals)) {
      if (value === undefined) delete globalThis[key]; else globalThis[key] = value;
    }
  }
});
