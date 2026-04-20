# Threat Model: E-Commerce Web Application

## System Description
Web App → API Gateway → Backend Services → Database + External Payment Service

## Data Flow Diagram (DFD)

```
                                    ┌─────────────────────────────┐
                                    │      TRUST BOUNDARY:        │
                                    │      External Network       │
                                    │                             │
  ┌──────────┐   HTTPS/TLS         │   ┌──────────────────┐      │
  │  Browser  │────────────────────────▶│   Load Balancer   │      │
  │  (User)   │◀────────────────────────│   / WAF           │      │
  └──────────┘                      │   └────────┬─────────┘      │
                                    │            │                 │
  ┌──────────┐   HTTPS              │   ┌────────▼─────────┐      │
  │  Mobile   │────────────────────────▶│   API Gateway     │      │
  │  App      │◀────────────────────────│   (Rate Limit,    │      │
  └──────────┘                      │   │    Auth Check)    │      │
                                    │   └────────┬─────────┘      │
                                    └────────────┼────────────────┘
                                                 │
                                    ┌────────────┼────────────────┐
                                    │   TRUST BOUNDARY:           │
                                    │   Internal Network (VPC)    │
                                    │            │                 │
                                    │   ┌────────▼─────────┐      │
                                    │   │   Web App         │      │
                                    │   │   (Express.js)    │      │
                                    │   └──┬─────┬────┬────┘      │
                                    │      │     │    │            │
                                    │ ┌────▼──┐  │  ┌─▼────────┐  │
                                    │ │ Auth  │  │  │ Product   │  │
                                    │ │Service│  │  │ Service   │  │
                                    │ └───┬───┘  │  └─────┬────┘  │
                                    │     │      │        │        │
                                    │   ┌─▼──────▼────────▼──┐    │
                                    │   │     Database        │    │
                                    │   │  (PostgreSQL/SQLite)│    │
                                    │   └─────────────────────┘    │
                                    │            │                 │
                                    └────────────┼────────────────┘
                                                 │
                                    ┌────────────┼────────────────┐
                                    │   TRUST BOUNDARY:           │
                                    │   Third-Party Services      │
                                    │            │                 │
                                    │   ┌────────▼─────────┐      │
                                    │   │  Payment Gateway  │      │
                                    │   │  (Stripe/PayPal)  │      │
                                    │   └──────────────────┘      │
                                    └─────────────────────────────┘
```

## Data Flows

| ID | From | To | Data | Protocol |
|----|------|----|------|----------|
| DF-1 | Browser | API Gateway | HTTP Requests, Auth tokens | HTTPS/TLS 1.3 |
| DF-2 | API Gateway | Web App | Validated requests | HTTP (internal) |
| DF-3 | Web App | Auth Service | Credentials, JWT | Internal API |
| DF-4 | Web App | Database | SQL Queries, User data | TCP/5432 |
| DF-5 | Web App | Payment Gateway | Payment tokens, amounts | HTTPS + mTLS |
| DF-6 | Payment Gateway | Web App | Transaction status | Webhook (HTTPS) |

## STRIDE Threat Analysis

### Threat 1: Broken Authentication via JWT Manipulation (API/Auth)
| Attribute | Detail |
|-----------|--------|
| **STRIDE** | Spoofing, Elevation of Privilege |
| **Threat** | Attacker forges/manipulates JWT to impersonate users or escalate to admin |
| **Attack Vector** | Weak secret → brute force; Algorithm confusion (RS256→HS256); No expiry → stolen token valid forever |
| **Impact** | Full account takeover, access to all user data and admin functions |
| **Likelihood** | HIGH |
| **Design Control** | Strong JWT secret (256-bit), Algorithm pinning (RS256 only), Short expiry (1h) + refresh tokens, Token revocation list |
| **CI/CD Check** | SAST rule `jwt-no-expiry`, SAST rule `hardcoded-secret`, SCA scan for JWT library CVEs |

### Threat 2: SQL Injection → Data Breach
| Attribute | Detail |
|-----------|--------|
| **STRIDE** | Tampering, Information Disclosure |
| **Threat** | Attacker injects SQL via search/login to extract or modify database |
| **Attack Vector** | Raw SQL query with string interpolation (e.g., `/api/search?q=' OR 1=1--`) |
| **Impact** | Complete database dump (PII, payment info), data manipulation |
| **Likelihood** | HIGH |
| **Design Control** | Parameterized queries only (ORM), Input validation + sanitization, Database user with minimal privileges, WAF rules for SQL injection patterns |
| **CI/CD Check** | SAST rule `sql-injection-raw-query`, DAST scan for injection endpoints |

### Threat 3: Payment Fraud via SSRF / Man-in-the-Middle
| Attribute | Detail |
|-----------|--------|
| **STRIDE** | Tampering, Repudiation |
| **Threat** | Attacker exploits SSRF to intercept/modify payment requests to payment gateway |
| **Attack Vector** | SSRF endpoint fetches internal payment service URL; or MITM on payment webhook |
| **Impact** | Financial loss, fraudulent transactions, compliance violation (PCI-DSS) |
| **Likelihood** | MEDIUM |
| **Design Control** | URL allowlist for outbound requests, mTLS for payment gateway communication, Webhook signature verification (HMAC), Idempotency keys for transactions |
| **CI/CD Check** | SAST rule `ssrf-vulnerability`, Container scan for network misconfig, IaC scan for missing TLS |

## Threat → Design Control → CI/CD Check Mapping

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│     THREAT          │     │   DESIGN CONTROL     │     │   CI/CD CHECK       │
├─────────────────────┤      ├──────────────────────┤       ├─────────────────────┤
│ JWT Manipulation     │────▶│ Strong secret mgmt    │────▶│ SAST: hardcoded-     │
│                      │      │ Algorithm pinning     │     │   secret             │
│                      │      │ Short token expiry    │     │ SAST: jwt-no-expiry  │
│                      │      │ Token revocation      │     │ SCA: jwt lib CVEs    │
├─────────────────────┤      ├──────────────────────┤      ├─────────────────────┤
│ SQL Injection        │────▶│ Parameterized queries│────▶│ SAST: sql-injection │
│                      │     │ Input validation      │     │ DAST: injection test│
│                      │     │ Least-privilege DB    │     │ IaC: DB config check│
├─────────────────────┤      ├──────────────────────┤     ├─────────────────────┤
│ Payment SSRF/MITM   │────▶│ URL allowlist        │────▶│ SAST: ssrf check    │
│                     │     │ mTLS for payments     │     │ Container: network  │
│                     │     │ Webhook HMAC verify   │     │ IaC: TLS config     │
│                     │     │ Idempotency keys      │     │                     │
└─────────────────────┘     └───────────────────────┘     └─────────────────────┘
```
