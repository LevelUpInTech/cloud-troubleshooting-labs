// Basic test suite — students should expand this
// This test catches the broken import that caused the production outage

const assert = require('assert');

console.log('Running unit tests...\n');

let passed = 0;
let failed = 0;

// Test 1: Server module loads without errors
try {
  require('../src/server.js');
  console.log('  PASS: server.js loads without errors');
  passed++;
} catch (e) {
  console.log(`  FAIL: server.js failed to load: ${e.message}`);
  failed++;
}

// Test 2: Verify all required modules exist
try {
  // This is the test that would have caught the bug!
  const fs = require('fs');
  const path = require('path');

  const modulesToCheck = [
    '../src/checkout/payment-handler.js',
  ];

  modulesToCheck.forEach(mod => {
    const fullPath = path.resolve(__dirname, mod);
    assert(fs.existsSync(fullPath), `Module not found: ${mod}`);
    require(fullPath); // Verify it actually loads
    console.log(`  PASS: ${mod} exists and loads`);
    passed++;
  });
} catch (e) {
  console.log(`  FAIL: Module check failed: ${e.message}`);
  failed++;
}

// Test 3: Verify no broken imports in server files
try {
  const fs = require('fs');
  const path = require('path');

  const serverFiles = [
    '../src/server.js',
  ];

  serverFiles.forEach(file => {
    const content = fs.readFileSync(path.resolve(__dirname, file), 'utf8');
    const requireMatches = content.match(/require\(['"]\.\/[^'"]+['"]\)/g) || [];

    requireMatches.forEach(req => {
      const modPath = req.match(/require\(['"]([^'"]+)['"]\)/)[1];
      const fullPath = path.resolve(path.dirname(path.resolve(__dirname, file)), modPath);

      // Check if file exists (with or without .js extension)
      const exists = fs.existsSync(fullPath) || fs.existsSync(fullPath + '.js');
      assert(exists, `Import ${modPath} in ${file} points to a missing file`);
      console.log(`  PASS: Import ${modPath} resolves correctly`);
      passed++;
    });
  });
} catch (e) {
  console.log(`  FAIL: Import verification failed: ${e.message}`);
  failed++;
}

console.log(`\nResults: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  console.log('\nTESTS FAILED — this build should NOT be deployed.');
  process.exit(1);
}

console.log('\nAll tests passed!');
process.exit(0);
