const express = require('express');

// ─── THIS IS THE BROKEN VERSION ───
// A developer renamed payment-processor.js to payment-handler.js
// but forgot to update the import below.
// The Docker build succeeds, but the app crashes at runtime.
//
// INSTRUCTIONS FOR STUDENTS:
// 1. First deploy the working version (server.js)
// 2. Then rename this file to server.js and push
// 3. Watch the pipeline deploy it to production
// 4. Observe the crash, diagnose it, roll back, then fix the pipeline

// This import will CRASH because the file doesn't exist
const paymentProcessor = require('./checkout/payment-processor.js');

const app = express();
const PORT = process.env.PORT || 3000;

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', version: '2.0.0' });
});

app.get('/checkout', (req, res) => {
  const result = paymentProcessor.processPayment({ amount: 127.50 });
  res.status(200).json(result);
});

app.get('/', (req, res) => {
  res.status(200).json({
    service: 'checkout-service',
    version: '2.0.0',
    endpoints: ['/health', '/checkout']
  });
});

app.listen(PORT, () => {
  console.log(`Checkout service v2.0.0 running on port ${PORT}`);
});
