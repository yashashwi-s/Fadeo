# Security Policy

## Supported Versions

Fadeo is actively maintained. Security updates and patches are provided for the latest
major version as outlined below.

| Version | Supported          |
| ------- | ------------------ |
| 0.x.x   | :white_check_mark: |

## Reporting a Vulnerability

We take the security of Fadeo seriously. If you discover a security vulnerability,
please report it privately to ensure it can be addressed safely before public
disclosure.

**How to Report:**
1. Please use the [Private Vulnerability Reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) feature on this GitHub repository, OR
2. Send a direct message/email to the maintainer with a clear description of the issue and steps to reproduce.

**What to Expect:**
- **Acknowledgement:** You can expect an initial response acknowledging your report within 48 hours.
- **Triage:** We will investigate the issue and confirm whether it is a valid vulnerability.
- **Resolution:** If accepted, we will work promptly to develop and release a patch. You will be credited in the release notes for your responsible disclosure. If declined, we will provide a clear technical explanation as to why.

*Please do not open public issues for security vulnerabilities.*

## Notes specific to Fadeo

Fadeo is a non-sandboxed, direct-distribution macOS app that uses several private
system APIs (see `PLAN.md` and `CLAUDE.md` for the full list: MediaRemote transport
commands, private CGS/SkyLight Space APIs, AppleScript automation). If you find a way
these interfaces could be abused (e.g. to escalate privileges, exfiltrate data, or
bypass macOS's permission model), that is exactly the kind of report we want, please
use the private reporting channel above rather than a public issue.
