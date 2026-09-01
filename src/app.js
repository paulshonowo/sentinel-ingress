require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const { rateLimiter } = require('./middleware/rateLimiter');
const scrapeRoutes = require('./routes/scrape.routes');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS || '*' }));
app.use(express.json({ limit: '10kb' }));

app.use('/api/', rateLimiter);
app.use('/', scrapeRoutes);

module.exports = app;
