const rateLimit = require('express-rate-limit');

const rateLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100,
    message: { error: 'Too many requests', message: 'Rate limit exceeded. Try again later.' }
});

module.exports = { rateLimiter };
