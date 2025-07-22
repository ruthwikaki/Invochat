
import test from 'node:test';
import assert from 'node:assert/strict';

process.env.RESEND_API_KEY = '';
process.env.EMAIL_FROM = '';
const { sendPasswordResetEmail } = await import('../../src/services/email');

const origInfo = console.info;
const messages: string[] = [];
console.info = (msg: string) => { messages.push(msg); };

await sendPasswordResetEmail('a@example.com', 'https://example.com/reset');
console.info = origInfo;

test('sendPasswordResetEmail logs simulation when disabled', () => {
  assert.ok(messages.some(m => m.includes('[Email Simulation]')));
});
