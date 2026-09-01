const { PubSub } = require('@google-cloud/pubsub');

const pubSubClient = new PubSub({
    projectId: process.env.GCP_PROJECT_ID
});

module.exports = pubSubClient;
