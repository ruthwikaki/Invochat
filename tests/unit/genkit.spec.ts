
import test from 'node:test';
import assert from 'node:assert/strict';

process.env.GOOGLE_API_KEY = '';
const { testGenkitConnection } = await import('../../src/services/genkit');

test('testGenkitConnection fails when not configured', async () => {
  const result = await testGenkitConnection();
  assert.equal(result.isConfigured, false);
  assert.equal(result.success, false);
});
