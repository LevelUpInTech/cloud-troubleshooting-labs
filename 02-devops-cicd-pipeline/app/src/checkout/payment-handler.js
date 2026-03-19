// This is the RENAMED file (was payment-processor.js, now payment-handler.js)
// The broken server.js still tries to import "payment-processor.js"
// which no longer exists — causing the crash.

function processPayment(order) {
  return {
    status: 'success',
    orderId: `ORD-${Date.now()}`,
    amount: order.amount,
    message: 'Payment processed successfully'
  };
}

module.exports = { processPayment };
