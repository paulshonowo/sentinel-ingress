const axios = require('axios');
const jwt = require('jsonwebtoken');

const INGRESS_URL = process.env.INGRESS_URL || 'https://sentinel-ingress-px4lrqvuya-uc.a.run.app';
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
  console.error('❌ Error: JWT_SECRET environment variable is required.');
  process.exit(1);
}

function generateToken() {
  const payload = {
    iss: 'sentinel-test-suite',
    sub: 'integration-test-runner',
    role: 'admin',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (60 * 15)
  };
  return jwt.sign(payload, JWT_SECRET, { algorithm: 'HS256' });
}

async function sendJob(testName, payload, token) {
  console.log(`\n--------------------------------------------------`);
  console.log(`🚀 [TEST] ${testName}`);
  console.log(`--------------------------------------------------`);
  console.log(`Payload:`, JSON.stringify(payload, null, 2));

  try {
    const response = await axios.post(`${INGRESS_URL}/api/v1/scrape`, payload, {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      timeout: 10000
    });

    console.log(`✅ [INGRESS ACCEPTED] Status: ${response.status} ${response.statusText}`);
    console.log(`   Response Body:`, response.data);
    return response.data;
  } catch (error) {
    if (error.response) {
      console.error(`❌ [INGRESS REJECTED] Status: ${error.response.status}`);
      console.error(`   Error Data:`, error.response.data);
    } else {
      console.error(`❌ [NETWORK ERROR] ${error.message}`);
    }
    return null;
  }
}

async function runE2ETestSuite() {
  console.log(`==================================================`);
  console.log(`  SENTINEL PIPELINE END-TO-END INTEGRATION TEST   `);
  console.log(`==================================================`);
  console.log(`Target Ingress Endpoint: ${INGRESS_URL}\n`);

  const token = generateToken();

  // Test 1: Valid Scrape Job (Happy Path)
  const validJobId = `valid-job-${Date.now()}`;
  await sendJob('1. Valid Scrape Job (Happy Path)', {
    job_id: validJobId,
    targetUrl: 'https://httpbin.org/get',
    webhookUrl: 'https://httpbin.org/post'
  }, token);

  await new Promise(r => setTimeout(r, 2000));

  // Test 2: Failing Worker Payload (Pub/Sub Ingress accepts, but target times out -> Worker NACK -> DLQ)
  const dlqJobId = `dlq-job-${Date.now()}`;
  await sendJob('2. Unreachable Target Payload (Ingress accepts, Worker times out & NACKs to DLQ)', {
    job_id: dlqJobId,
    targetUrl: 'http://10.255.255.1:81', // Non-routable IP to force worker failure
    metadata: { testReason: 'Force worker connection failure to test 5-attempt retry and DLQ routing' }
  }, token);

  console.log(`\n==================================================`);
  console.log(`🎉 Job submissions complete.`);
  console.log(`==================================================`);
}

runE2ETestSuite();
