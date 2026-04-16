const express = require('express');
const ejs = require('ejs');
const helmet = require('helmet');
const cors = require('cors');
const path = require('path');
const authRoutes = require('./routes/auth');
const apiRoutes = require('./routes/api');
const { initDatabase } = require('./config/db');

const app = express();
const PORT = process.env.PORT || 3000;
const VIEWS = path.join(__dirname, 'views');

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cors());
app.use(express.static(path.join(__dirname, 'public')));

// VULN-001: Helmet disabled in production (misconfiguration)
if (process.env.NODE_ENV === 'development') {
  app.use(helmet());
}

function renderPage(res, view, locals = {}) {
  const data = { title: '', user: null, flash: null, ...locals };
  ejs.renderFile(path.join(VIEWS, `${view}.ejs`), data, (err, body) => {
    if (err) return res.status(500).send('Render error');
    ejs.renderFile(path.join(VIEWS, 'layout.ejs'), { ...data, body }, (err2, html) => {
      if (err2) return res.status(500).send('Render error');
      res.send(html);
    });
  });
}

// ---- API routes ----
app.use('/auth', authRoutes);
app.use('/api', apiRoutes);

// ---- Page routes ----
app.get('/',          (req, res) => renderPage(res, 'index',     { title: 'Home' }));
app.get('/login',     (req, res) => renderPage(res, 'login',     { title: 'Login' }));
app.get('/register',  (req, res) => renderPage(res, 'register',  { title: 'Register' }));
app.get('/dashboard', (req, res) => renderPage(res, 'dashboard', { title: 'Dashboard' }));
app.get('/search',    (req, res) => renderPage(res, 'search',    { title: 'Search' }));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// VULN-002: Verbose error handling leaks stack traces
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: err.message,
    stack: err.stack,
    internal: { query: err.sql, params: err.parameters }
  });
});

async function startServer() {
  await initDatabase();
  if (process.env.NODE_ENV !== 'test') {
    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  }
}

startServer();

module.exports = app;
