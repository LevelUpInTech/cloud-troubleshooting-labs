const express = require('express');

// ─── THIS IS THE WORKING VERSION ───
// The "broken" version is in src/server-broken.js
// Students will swap this file to simulate the broken deploy,
// then troubleshoot and fix it.

const app = express();
const PORT = process.env.PORT || 3000;

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Checkout endpoint
app.get('/checkout', (req, res) => {
  res.status(200).json({
    message: 'Checkout service is running',
    cart: { items: 3, total: '$127.50' }
  });
});

// Homepage
app.get('/', (req, res) => {
  res.status(200).json({
    service: 'checkout-service',
    version: '1.0.0',
    endpoints: ['/health', '/checkout']
  });
});

app.listen(PORT, () => {
  console.log(`Checkout service running on port ${PORT}`);
});
