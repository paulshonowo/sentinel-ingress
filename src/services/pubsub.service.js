const pubSubClient = require('../config/pubsub');

const TOPIC_NAME = process.env.PUBSUB_TOPIC || 'sentinel-scrape-jobs';

async function publishScrapeJob(jobData) {
    const dataBuffer = Buffer.from(JSON.stringify(jobData));
    const messageId = await pubSubClient.topic(TOPIC_NAME).publishMessage({ data: dataBuffer });
    return messageId;
}

module.exports = { publishScrapeJob };
