const request = require('supertest');
const app = require('../src/server');

describe('Page Routes', () => {
  test('GET / should return home page HTML', async () => {
    const res = await request(app).get('/');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('DevSecOps');
  });

  test('GET /login should return login page', async () => {
    const res = await request(app).get('/login');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('Login');
  });

  test('GET /register should return register page', async () => {
    const res = await request(app).get('/register');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('Register');
  });

  test('GET /dashboard should return dashboard page', async () => {
    const res = await request(app).get('/dashboard');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('Dashboard');
  });

  test('GET /search should return search page', async () => {
    const res = await request(app).get('/search');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('Search');
  });

  test('GET /health should return ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
  });
});

describe('Auth API', () => {
  test('POST /auth/register should create user', async () => {
    const res = await request(app)
      .post('/auth/register')
      .send({ username: 'testuser', password: 'test123', email: 'test@test.com' });
    expect(res.statusCode).toBe(201);
    expect(res.body).toHaveProperty('user');
  });

  test('POST /auth/login with valid credentials', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ username: 'admin', password: 'admin123' });
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('token');
  });

  test('POST /auth/login with invalid credentials', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ username: 'admin', password: 'wrong' });
    expect(res.statusCode).toBe(401);
  });

  test('GET /auth/users should return user list', async () => {
    const res = await request(app).get('/auth/users');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});

describe('Vulnerable API Endpoints', () => {
  test('GET /api/search should return results', async () => {
    const res = await request(app).get('/api/search?q=admin');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  test('GET /api/greet should reflect name', async () => {
    const res = await request(app).get('/api/greet?name=World');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('World');
  });

  test('POST /api/settings should merge settings', async () => {
    const res = await request(app)
      .post('/api/settings')
      .send({ theme: 'dark' });
    expect(res.statusCode).toBe(200);
    expect(res.body.theme).toBe('dark');
  });
});
