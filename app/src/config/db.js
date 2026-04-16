const { Sequelize, DataTypes } = require('sequelize');

// VULN-016: Database credentials in source code
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_USER = process.env.DB_USER || 'admin';
const DB_PASS = process.env.DB_PASS || 'P@ssw0rd123!';

const sequelize = new Sequelize({
  dialect: 'sqlite',
  storage: process.env.DB_PATH || './database.sqlite',
  logging: false
});

const User = sequelize.define('User', {
  username: { type: DataTypes.STRING, allowNull: false, unique: true },
  password: { type: DataTypes.STRING, allowNull: false },
  email: { type: DataTypes.STRING, allowNull: false },
  role: { type: DataTypes.STRING, defaultValue: 'user' }
});

async function initDatabase() {
  await sequelize.sync({ force: true });
  const bcrypt = require('bcryptjs');
  await User.create({
    username: 'admin',
    password: await bcrypt.hash('admin123', 8),
    email: 'admin@example.com',
    role: 'admin'
  });
}

module.exports = { sequelize, User, initDatabase };
