# Takehome Solution - Scaler DevSecOps Assignment

This folder contains the **ideal solution** for the DevSecOps take-home assignment. Use this as a reference while grading or if you need to understand the expected approach.

## Files Included

### Dockerfile
The fixed, production-ready Dockerfile with all security best practices:
- Uses specific Node.js version (20-alpine)
- Runs as non-root user
- Removes hardcoded secrets
- Removes unnecessary packages
- Optimized layer caching

Key improvements documented in SECURITY_AUDIT.md

### .github/workflows/deploy.yml
Hardened CI/CD pipeline with:
- OIDC authentication to AWS ECR (no stored credentials)
- Trivy vulnerability scanning with SARIF output
- Cosign image signing (keyless with OIDC)
- SBOM generation with Anchore
- Explicit permissions declaration
- Multi-stage scanning (fail on CRITICAL CVEs)

### SECURITY_AUDIT.md
Comprehensive documentation of:
- Every issue found in the original code
- Why each is a security problem
- How the fix addresses it
- Answers to all 4 decision questions with reasoning
- Architecture decisions and trade-offs
- Summary table of improvements

This is the most important deliverable - shows deep understanding, not just code fixes.

### REFLECTION.md
Example reflection on AI usage including:
- How AI was used (research, validation, syntax)
- Where human judgment was needed
- Where AI got it wrong
- Key learnings

### Supporting Files
- `server.js`: Simple Node.js web server
- `package.json`: Minimal dependencies
- `.dockerignore`: Excludes unnecessary files from image
- `.gitignore`: Excludes runtime artifacts

## How to Use This Reference

### For Grading
- Compare student solutions against this reference
- Use SECURITY_AUDIT.md to identify missing explanations
- Check if student decisions are reasonable (not just copying)

### For Teaching
- Show students the before/after comparison
- Highlight the reasoning behind each fix
- Discuss trade-offs in the decision questions
- Use as inspiration for your own assignments

## Key Differences from Broken Version

| Area | Broken | Fixed |
|------|--------|-------|
| Base image | `node:latest` | `node:20-alpine` |
| Secrets | Hardcoded in ENV | OIDC + GitHub Secrets |
| User | root | nodejs (non-root) |
| Vulnerability scan | None | Trivy (CRITICAL fail) |
| Image signing | None | Cosign (keyless) |
| Registry | Docker Hub | ECR |
| Artifacts | None | SBOM + scan results |

## Testing This Solution

```bash
# Build the Docker image
docker build -t scaler-devsecops:latest .

# Test the application
docker run -p 3000:3000 scaler-devsecops:latest

# Scan with Trivy
trivy image scaler-devsecops:latest

# Verify image runs as non-root
docker run -it scaler-devsecops:latest id
# Output should show: uid=1001(nodejs) gid=1001(nodejs) groups=1001(nodejs)
```

## Important Notes

- **This is a reference solution**, not a template to copy. Students should understand why each change was made.
- **The decision questions** require reasoning and trade-off analysis - copying these answers without understanding will be caught in the follow-up call.
- **Customization is expected**: Different environments may require different choices (e.g., different base images, security tools, deployment strategies).
- **The workflow requires secrets to be configured**: AWS_ACCOUNT_ID secret and OIDC role setup are prerequisites.
