# Contributing

Thanks for considering a contribution to this project.

## Getting started

1. Fork the repo and create a branch from `main`.
2. Follow the [Quick Start](README.md#quick-start) to run the stack locally.
3. Make your change, and add/update tests where relevant:
   - Python: `api/`
   - Java / Rest Assured: `rest-assured/src/test/java`
4. Run the full test suite before opening a PR:
   ```bash
   ./scripts/bootstrap_keycloak.sh
   cd rest-assured && mvn test
   ```
5. Open a pull request describing what changed and why.

## Code style

- Python: keep functions small, use type hints, prefer explicit errors over silent failures.
- Java: keep test methods focused on one scenario each (see `OAuthApiTest.java` for the pattern).

## Reporting issues

Please open a GitHub issue with steps to reproduce, expected behavior, and actual behavior.
