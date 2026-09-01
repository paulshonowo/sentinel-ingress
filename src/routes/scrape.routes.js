const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const { publishScrapeJob } = require('../services/pubsub.service');

router.get('/health', (req, res) => {
    res.status(200).json({ status: 'HEALTHY', timestamp: new Date().toISOString() });
});

router.post('/api/v1/scrape', authenticateToken, async (req, res) => {
    try {
        const { targetUrl, expectedFields, webhookUrl, monitorMode } = req.body;

        if (!targetUrl || typeof targetUrl !== 'string') {
            return res.status(400).json({
                error: 'Bad Request',
                message: 'Valid "targetUrl" string is required.'
            });
        }

        const jobPayload = {
            jobId: `job_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
            targetUrl,
            expectedFields: Array.isArray(expectedFields) ? expectedFields : [],
            webhookUrl: webhookUrl || null,
            monitorMode: Boolean(monitorMode),
            requestedBy: req.user.clientId || 'authenticated_client',
            timestamp: new Date().toISOString()
        };

        const pubsubMessageId = await publishScrapeJob(jobPayload);

        return res.status(202).json({
            status: 'ACCEPTED',
            message: 'Scrape job successfully queued.',
            jobId: jobPayload.jobId,
            pubsubMessageId
        });

    } catch (error) {
        console.error('[ROUTE ERROR]', error);
        return res.status(500).json({
            error: 'Internal Server Error',
            message: 'Failed to enqueue scraping job.'
        });
    }
});

module.exports = router;
