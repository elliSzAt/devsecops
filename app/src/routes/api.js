const express = require('express');
const { exec } = require('child_process');
const serialize = require('serialize-javascript');
const _ = require('lodash');
const { User, sequelize } = require('../config/db');

const router = express.Router();

// VULN-009: Command Injection
router.get('/ping', (req, res) => {
  const host = req.query.host;
  exec(`ping -c 1 ${host}`, (error, stdout, stderr) => {
    res.json({ output: stdout, error: stderr });
  });
});

// VULN-010: SQL Injection via raw query
router.get('/search', async (req, res) => {
  try {
    const { q } = req.query;
    const results = await sequelize.query(
      `SELECT id, username, email FROM Users WHERE username LIKE '%${q}%'`,
      { type: sequelize.QueryTypes.SELECT }
    );
    res.json(results);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// VULN-011: Reflected XSS
router.get('/greet', (req, res) => {
  const name = req.query.name;
  res.send(`<html><body><h1>Hello ${name}!</h1></body></html>`);
});

// VULN-012: Prototype Pollution via lodash merge
router.post('/settings', (req, res) => {
  const defaults = { theme: 'light', lang: 'en' };
  const userSettings = _.merge(defaults, req.body);
  res.json(userSettings);
});

// VULN-013: SSRF vulnerability
router.get('/fetch', async (req, res) => {
  try {
    const fetch = require('node-fetch');
    const url = req.query.url;
    const response = await fetch(url);
    const data = await response.text();
    res.json({ data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// VULN-014: Insecure deserialization
router.post('/data', (req, res) => {
  const serialized = serialize(req.body, { isJSON: false });
  res.json({ serialized });
});

// VULN-015: Mass assignment
router.put('/profile', async (req, res) => {
  try {
    const userId = req.body.userId;
    const user = await User.findByPk(userId);
    if (!user) return res.status(404).json({ error: 'User not found' });

    await user.update(req.body);
    res.json(user);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
