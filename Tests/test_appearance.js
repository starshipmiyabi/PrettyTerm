'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const project = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(project, 'Resources/index.html'), 'utf8');
const nativeSource = fs.readFileSync(path.join(project, 'Sources/PrettyTerm.m'), 'utf8');

test('conversation renderer declares a complete dark appearance', () => {
  assert.match(html, /color-scheme:\s*light dark/);
  assert.match(html, /@media\s*\(prefers-color-scheme:\s*dark\)/);
  assert.match(html, /@media[\s\S]*--canvas:\s*#[0-9a-f]{6}/i);
  assert.match(html, /@media[\s\S]*--paper:\s*#[0-9a-f]{6}/i);
  assert.match(html, /@media[\s\S]*--ink:\s*#[0-9a-f]{6}/i);
});

test('conversation and native surfaces use the warm beige and deep-orange palette', () => {
  assert.match(html, /--canvas:\s*#f4ecde/i);
  assert.match(html, /--blue:\s*#a34717/i);
  assert.match(html, /@media[\s\S]*--canvas:\s*#211912/i);
  assert.match(html, /@media[\s\S]*--blue:\s*#e58a49/i);
  assert.match(nativeSource, /PTWarmCanvasColor/);
  assert.match(nativeSource, /PTWarmAccentColor/);
});

test('turn edit summaries expose a warm review card', () => {
  assert.match(html, /\.edit-summary\s*\{/);
  assert.match(html, /\.open-local-review\s*\{/);
  assert.match(html, /\.edit-review-label/);
});

test('local WebView content is isolated from network and dynamic MathJax packages', () => {
  assert.match(html, /Content-Security-Policy/);
  assert.match(html, /connect-src 'none'/);
  assert.match(html, /object-src 'none'/);
  assert.match(html, /packages:\s*\{\s*'\[-\]'\s*:\s*\['require', 'autoload'\]\s*\}/);
  assert.match(html, /loader:\s*\{\s*load:\s*\[\]\s*\}/);
});

test('native chrome does not use fixed light surfaces or fixed dark title text', () => {
  assert.doesNotMatch(nativeSource, /layer\.backgroundColor\s*=\s*PTColor\(0\.9/);
  assert.doesNotMatch(nativeSource, /color:PTColor\(0\.(?:08|10|12),/);
  assert.match(nativeSource, /PTAppearanceSurfaceView/);
});

test('collapsed long replies keep their summary in normal layout flow', () => {
  const summaryRules = Array.from(
    html.matchAll(/details\.long-content\s*>\s*summary\s*\{([^}]*)\}/g),
    match => match[1]
  );
  assert.ok(summaryRules.length > 0, 'long-content summary rule must exist');
  assert.ok(summaryRules.every(rule => !/position:\s*absolute/.test(rule)),
    'no long-content summary rule may remove the closed summary from layout flow');
});

test('assistant quote menu has native-like light and dark styling', () => {
  assert.match(html, /\.quote-menu\s*\{/);
  assert.match(html, /backdrop-filter:\s*blur/);
  assert.match(html, /@media[\s\S]*\.quote-menu\s*\{/);
});
