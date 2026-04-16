const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { User } = require('../config/db');

const router = express.Router();

// VULN-003: Hardcoded JWT secret
const JWT_SECRET = 'super-secret-key-12345';

// VULN-004: No rate limiting on login endpoint
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;

    // VULN-005: SQL Injection via raw query
    const user = await User.findOne({
      where: { username: username }
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // VULN-006: Token never expires
    const token = jwt.sign(
      { id: user.id, username: user.username, role: user.role },
      JWT_SECRET
    );

    res.json({ token, user: { id: user.id, username: user.username } });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/register', async (req, res) => {
  try {
    const { username, password, email } = req.body;

    // VULN-007: Weak password policy - no validation
    const hashedPassword = await bcrypt.hash(password, 8);

    const user = await User.create({
      username,
      password: hashedPassword,
      email,
      role: 'user'
    });

    res.status(201).json({
      message: 'User created',
      user: { id: user.id, username: user.username }
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// VULN-008: No authentication middleware on sensitive endpoint
router.get('/users', async (req, res) => {
  try {
    const users = await User.findAll({
      attributes: ['id', 'username', 'email', 'role', 'password']
    });
    res.json(users);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
