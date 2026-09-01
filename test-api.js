const jwt = require('jsonwebtoken');
const http = require('http');
require('dotenv').config();

const JWT_SECRET = process.env.JWT_SECRET || 'fallback_development_secret_change_in_prod';
const PORT = process.env.PORT || 8080;

const token = jwt.sign(
    { clientId: 'test_architect_client', role: 'admin' },
    JWT_SECRET,
    { expiresIn: '15m' }
);

console.log('🔑 Generated Test JWT:', token);

const postData = JSON.stringify({
    targetUrl: 'https://example.com/products/item-123',
    expectedFields: ['title', 'price', 'availability'],
    webhookUrl: 'https://webhook.site/test-endpoint',
    monitorMode: true
});

const options = {
    hostname: 'localhost',
    port: PORT,
    path: '/api/v1/scrape',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'Content-Length': Buffer.byteLength(postData)
    }
};

console.log('🚀 Starting local API server test...');

const req = http.request(options, (res) => {
    let responseBody = '';
    res.on('data', (chunk) => { responseBody += chunk; });
    res.on('end', () => {
        console.log(`\n📥 Response Status: ${res.statusCode}`);
        console.log(`📥 Response Body: ${responseBody}`);
    });
});

req.on('error', (e) => {
    console.error(`❌ Connection Error: ${e.message}. Is your server running? (Run 'npm run dev')`);
});

req.write(postData);
req.end();
