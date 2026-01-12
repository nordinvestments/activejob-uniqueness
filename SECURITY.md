# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.5.x   | :white_check_mark: |
| < 0.5   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in this gem, please report it responsibly.

**Do not open a public GitHub issue.**

Instead, please email security concerns to the maintainers privately. You can reach us by:

1. Opening a [private security advisory](https://github.com/nordinvestments/activejob-uniqueness/security/advisories/new) on GitHub
2. Contacting the repository maintainers directly

We will acknowledge receipt within 48 hours and aim to provide a fix within 7 days for critical vulnerabilities.

## Security Best Practices

When using this gem:

- Keep your Redis instance secured and not publicly accessible
- Use TLS for Redis connections in production
- Regularly update to the latest gem version
- Monitor your Redis memory usage as locks consume memory
