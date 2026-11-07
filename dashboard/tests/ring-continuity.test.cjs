// Lifecycle tests for the production motion controller, using a small DOM/WAAPI
// double. Visual placement is checked separately in the browser.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');
const source = readFileSync(join(__dirname, '../web/app.js'), 'utf8');
const controller = source.slice(source.indexOf('class RingContinuity {'), source.indexOf('const RING_CONTINUITY ='));

function fixture({ reduced = false, loaded = true, visible = true, width = 390 } = {}) {
  const listeners = {}, nodes = [];
  const animation = (keys) => ({ keys, cancelled: false, onfinish: null, cancel() { this.cancelled = true; } });
  class Node {
    constructor() {
      this.classes = new Set(); this.children = []; this.style = {}; this.hidden = false;
      this.complete = loaded; this.naturalWidth = loaded ? 1254 : 0; this.offsetWidth = 230;
      this.classList = { add: v => this.classes.add(v), remove: v => this.classes.delete(v) };
      nodes.push(this);
    }
    setAttribute() {}
    replaceChildren(...children) { this.children = children; }
    querySelector() { return this; }
    getClientRects() { return visible ? [1] : []; }
    getBoundingClientRect() { return { left: 100, top: 100, width: 230, height: 230, bottom: 330, right: 330 }; }
    animate(keys) { return animation(keys); }
    decode() { return Promise.resolve(); }
  }
  const placements = Object.fromEntries(['home', 'ring', 'settings'].map(section => [section, new Node()]));
  const document = {
    hidden: false, body: { append() {} }, createElement: () => new Node(),
    addEventListener: (name, fn) => { listeners[name] = fn; },
    querySelectorAll: selector => selector === '.ring-in-flight'
      ? nodes.filter(n => n.classes.has('ring-in-flight'))
      : [placements[selector.match(/"(.*?)"/)[1]]]
  };
  const media = { matches: reduced, addEventListener: (_, fn) => { listeners.motion = fn; } };
  const browserWindow = { scrollX: 0, scrollY: 0, addEventListener: (name, fn) => { listeners[name] = fn; } };
  const context = vm.createContext({ document, Image: Node, matchMedia: () => media, innerWidth: width, innerHeight: 844,
    window: browserWindow });
  vm.runInContext(controller + '\nthis.controller = new RingContinuity();', context);
  const motion = context.controller;
  return { motion, placements, listeners, media, document, browserWindow, start(from = 'home', to = 'ring') {
    motion.move(from, to, motion.capture(from));
  } };
}

test('one travelling ring replaces both placements, then restores the destination', () => {
  const f = fixture(); f.start();
  assert.equal(f.motion.stage.hidden, false);
  assert.equal(f.placements.home.classes.has('ring-in-flight'), true);
  assert.equal(f.placements.ring.classes.has('ring-in-flight'), true);
  const animations = [...f.motion.animations];
  animations[0].onfinish();
  assert.equal(f.motion.stage.hidden, true);
  assert.equal(f.motion.stage.children.length, 0);
  assert.equal(f.placements.ring.classes.size, 0);
  assert.ok(animations.every(a => a.cancelled));
});

test('rapid retargeting releases the previous images before the next trip', () => {
  const f = fixture(); f.start(); const previous = [...f.motion.animations];
  f.motion.finish(); f.start('ring', 'settings');
  assert.ok(previous.every(a => a.cancelled));
  assert.equal(f.placements.home.classes.size, 0);
  assert.equal(f.placements.settings.classes.has('ring-in-flight'), true);
  f.motion.finish(); assert.equal(f.placements.settings.classes.size, 0);
});

for (const event of ['resize', 'scroll', 'pagehide', 'motion', 'visibilitychange']) {
  test(`${event} interruption never leaves a ring invisible`, () => {
    const f = fixture(); f.start(); f.document.hidden = true; f.browserWindow.scrollY = 100; f.listeners[event]();
    assert.equal(f.motion.stage.hidden, true);
    assert.ok(Object.values(f.placements).every(n => n.classes.size === 0));
  });
}

test('Reduce Motion, missing assets and offscreen sources skip travel', () => {
  for (const options of [{ reduced: true }, { loaded: false }, { visible: false }]) {
    const f = fixture(options); f.start();
    assert.equal(f.motion.stage.hidden, true);
    assert.equal(f.motion.animations.length, 0);
    assert.ok(Object.values(f.placements).every(n => n.classes.size === 0));
  }
});


test('scaled placements use viewport bounds rather than layout-pixel width', () => {
  const f = fixture();
  f.placements.home.offsetWidth = 230;
  f.placements.home.getBoundingClientRect = () => ({left:80,top:140,width:184,height:184,right:264,bottom:324});
  f.placements.ring.offsetWidth = 280;
  f.placements.ring.getBoundingClientRect = () => ({left:70,top:120,width:224,height:224,right:294,bottom:344});
  const captured = f.motion.capture('home');
  assert.equal(captured.size, 184, 'The overlay must share viewport units with getBoundingClientRect');
  f.motion.move('home', 'ring', captured);
  const final = f.motion.animations[0].keys.at(-1).transform;
  assert.match(final, /^translate3d\(90px,140px,0\)/);
  assert.ok(final.endsWith(`scale(${224 / 184})`));
  f.motion.finish();
});

test('every responsive destination is the final animation center, without a handoff offset', () => {
  for (const width of [320,375,390,428,768]) {
    const f = fixture({width});
    f.placements.home.getBoundingClientRect = () => ({left:width-190,top:140,width:170,height:170,right:width-20,bottom:310});
    const left = (width-218)/2, top = 120;
    f.placements.ring.getBoundingClientRect = () => ({left,top,width:218,height:218,right:left+218,bottom:top+218});
    f.start();
    const transform = f.motion.animations[0].keys.at(-1).transform;
    const [, x, y] = transform.match(/^translate3d\(([-.\d]+)px,([-.\d]+)px,0\)/).map(Number);
    assert.equal(x + 85, left + 109);
    assert.equal(y + 85, top + 109);
    f.motion.finish();
  }
});
