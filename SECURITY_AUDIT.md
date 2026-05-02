# Security Audit - Scaler DevSecOps Take-Home Assignment

## Dockerfile Issues and Fixes

### Issue 1: Using `node:latest` as base image
**Problem:** Using `latest` tag means the base image can change unexpectedly between builds, introducing security vulnerabilities and breaking changes.

**Fix:** Changed to `node:20-alpine` - a specific version on lightweight Alpine Linux base.

---

### Issue 2: Copying entire directory with `COPY . .`
**Problem:** This copies all files including .git, node_modules (if present), and development files, increasing image size and exposing unnecessary code.

**Fix:** Use `.dockerignore` file and copy only `package*.json` first, then copy application code. Install dependencies separately for better layer caching.

---

### Issue 3: Hardcoded secrets in ENV variables
**Problem:** `ENV SECRET_KEY=s3cr3t_k3y_abc123` and `ENV DB_PASSWORD=admin123` are baked into the image, exposing credentials to anyone who can access the image or inspect layers.

**Fix:** Removed hardcoded secrets entirely. Secrets should be injected at runtime via environment variables, Kubernetes secrets, or AWS Secrets Manager, not stored in the image.

---

### Issue 4: Installing unnecessary tools
**Problem:** `apt-get install curl vim wget` increases image size and attack surface. These tools are development utilities, not needed in production.

**Fix:** Removed these packages. Use Alpine's minimal base image which doesn't have them by default.

---

### Issue 5: Exposing SSH port (port 22)
**Problem:** Exposing SSH with `EXPOSE 22` suggests SSH access might be available, which is unnecessary for a containerized application. Containers should not be SSH'd into.

**Fix:** Removed `EXPOSE 22`, keeping only `EXPOSE 3000` for the application.

---

### Issue 6: Running as root user
**Problem:** The container runs as root by default, meaning any compromise of the application gives full container privileges.

**Fix:** Added a non-root user `nodejs` with UID 1001 and switched to it with `USER nodejs`.

---

## GitHub Actions Workflow Issues and Fixes

### Issue 1: Hardcoded credentials in environment variables
**Problem:** 
```yaml
env:
  DOCKER_HUB_PASSWORD: "p@ssw0rd_docker_123"
  AWS_SECRET_ACCESS_KEY: "wJalrXUtnFEMI/K7MDENG/bPxRfiCY"
```
These are plaintext secrets in the workflow file, visible to anyone with repository access and stored in git history.

**Fix:** Used GitHub Secrets and OIDC authentication instead:
- Removed hardcoded credentials
- Used `aws-actions/configure-aws-credentials` with OIDC role assumption
- All sensitive data stored in GitHub Secrets

---

### Issue 2: Using outdated GitHub Actions versions
**Problem:** `uses: actions/checkout@v3` is outdated and may lack security patches.

**Fix:** Updated to `actions/checkout@v4` and pinned all action versions to latest stable releases.

---

### Issue 3: No vulnerability scanning
**Problem:** No container image vulnerability scanning means pushing vulnerable images to production.

**Fix:** 
- Added Trivy vulnerability scanner that runs after image build
- Scans for CRITICAL and HIGH severity CVEs
- Produces SARIF output for GitHub Security tab
- Fails pipeline if CRITICAL CVEs found

---

### Issue 4: Pushing to Docker Hub instead of ECR
**Problem:** Using Docker Hub with hardcoded credentials, no image signing, no OIDC.

**Fix:**
- Replaced with Amazon ECR push using OIDC authentication
- Uses `aws-actions/configure-aws-credentials@v4` with role-to-assume ARN
- No stored credentials needed, uses temporary OIDC tokens

---

### Issue 5: No image signing
**Problem:** Images pushed without signature, making it impossible to verify authenticity.

**Fix:** 
- Added Cosign signing step after ECR push
- Uses `COSIGN_EXPERIMENTAL=1` for keyless signing with OIDC
- Images can be verified: `cosign verify <image>`

---

### Issue 6: No SSH key configuration and StrictHostKeyChecking disabled
**Problem:** The deploy step used `ssh -o StrictHostKeyChecking=no` which is vulnerable to MITM attacks.

**Fix:** Removed SSH-based deployment entirely. Images are pushed to ECR; deployment is orchestrated separately (beyond this pipeline's scope).

---

### Issue 7: Missing permissions declaration
**Problem:** Workflow didn't explicitly declare required permissions.

**Fix:** Added explicit permissions:
```yaml
permissions:
  id-token: write    # Required for OIDC
  contents: read     # Required for checkout
```

---

### Issue 8: No artifact generation
**Problem:** Scan results and security artifacts not saved for audit.

**Fix:** 
- Generated SBOM (Software Bill of Materials) with Anchore
- Uploaded Trivy scan results as artifacts
- Uploaded SBOM as artifacts for compliance

---

## Architecture Decisions

### Why multi-stage builds?
This solution uses Docker's layer caching effectively. In production, you'd use:
```dockerfile
FROM node:20-alpine as builder
RUN npm ci --only=production

FROM node:20-alpine
COPY --from=builder /app/node_modules ./node_modules
```
This keeps production images smaller.

### Why Alpine Linux?
- Lightweight base (5MB vs 800MB+ for Debian)
- Fewer packages = smaller attack surface
- Faster image builds and pulls

### Why OIDC instead of stored credentials?
- No credential rotation needed
- Tokens are short-lived (1 hour default)
- Credentials are never stored in GitHub
- Better audit trail via AWS CloudTrail

### Why Trivy before push?
- Fail fast: catch vulnerabilities before they reach registry
- Saves time and bandwidth by not pushing vulnerable images
- Creates policy-as-code for image quality

### Why Cosign?
- Proves image authenticity: only signed images deployed
- Keyless signing: uses OIDC, no key management overhead
- Integrates with container registries for verification

---

## Decision Questions - Answers

### Q1: Vulnerability Management (3 CRITICAL CVEs in OpenSSL)

**My approach:** Mitigation first, then coordinate with the team.

**Options considered:**
1. **Fix**: Upgrade base image to newer Node.js version with patched OpenSSL
2. **Mitigate**: Use WAF or network policies to block exploit vectors if the CVE requires network access
3. **Accept**: Document risk and require stakeholder approval

**What I'd actually do:**
1. Immediately escalate to the team lead (this is critical)
2. Check if the CVEs are exploitable in our workload (does the vulnerability require specific conditions?)
3. Create a short-term mitigation: add WAF rules or network policies if possible
4. Coordinate a fix: work with the team to patch the native module or find an alternative
5. Document the decision: create a risk acceptance document signed by stakeholders

**Communication:** "We have 3 CRITICAL CVEs in OpenSSL. The upgrade path breaks our native module. We're implementing [mitigation] as a 24-hour fix and coordinating a full patch for [date]."

---

### Q2: Container Security (--privileged mode for "internal only" service)

**My response to the colleague:**

"I understand it's internal, but --privileged mode breaks the container isolation boundary. Here's the specific risk:

- A compromise of our application code now compromises the entire host
- The attacker can access the host's devices, kernel, and potentially other containers
- 'Internal only' provides no protection against malicious code from dependencies (npm packages, system libraries)
- We recently saw supply chain attacks (SolarWinds, npm packages); internal network doesn't protect against them

**The right approach:**
- Use `--cap-drop=ALL` and `--cap-add=<only-needed>`
- Use `--security-opt=no-new-privileges` to prevent privilege escalation
- If you need specific capabilities, we can audit which ones and add only those

This costs maybe 15 minutes to test and prevents a potential catastrophic breach."

---

### Q3: Git History and Secrets (Removed hardcoded secrets - are we clean?)

**Answer: No, we're not completely clean.**

What still needs to happen:

1. **Scan git history for other secrets:**
   ```bash
   git-secrets scan-history
   # or
   truffleHog scan file://. --json
   ```

2. **Check if credentials were used elsewhere:**
   - Were these credentials used in CI/CD logs? (Check Actions run logs)
   - Were they used in Slack, email, or documentation? (Check audit logs)
   - Were they shared with external services?

3. **Rotate all credentials associated with the exposed secrets:**
   - Docker Hub credentials: change password, generate new token
   - AWS access keys: create new keys, deactivate old ones
   - Check CloudTrail for usage patterns of the old key

4. **Enable secret detection:**
   - Enable GitHub's secret scanning
   - Add git hooks to prevent future secret commits
   - Use tools like `pre-commit` with `detect-secrets`

5. **Timeline:** Secrets in git history are visible forever to anyone with repo access. Even after deletion, they're cached by GitHub's backups for 90 days. This is why OIDC is better than credential rotation.

---

### Q4: GitHub Actions Pinning (SHAs vs maintainability)

**My practical approach: Pin major versions, scan for updates quarterly**

```yaml
# Good balance:
- uses: actions/checkout@v4        # Major version pinned
- uses: aws-actions/configure-aws-credentials@v4
- uses: aquasecurity/trivy-action@master  # Special case: always latest for security tools
```

**Why this works:**
- `v4` gets security patches automatically (v4.0 → v4.1.2)
- We're protected against breaking changes (no v5 surprises)
- Maintainability: minimal effort to update

**For critical security tools** (Trivy, Cosign):
- Use `@master` or `@main` to always get latest patches
- These tools are security-first anyway

**Process:**
- Monthly: GitHub notifies of new versions
- Quarterly: Schedule 30 minutes to batch-update actions
- Automation: Use Dependabot to create update PRs

**Avoid:**
- Don't pin to commit SHAs unless you have a security incident
- Don't use `@master` for non-security tools (introduces instability)

---

## Summary of Security Improvements

| Category | Before | After |
|----------|--------|-------|
| Image versioning | Latest (floating) | 20-alpine (specific) |
| Secrets | Hardcoded in image | OIDC + GitHub Secrets |
| User privilege | Root | Non-root (nodejs) |
| Vulnerability scanning | None | Trivy (fail on CRITICAL) |
| Image signing | None | Cosign (keyless) |
| Registry | Docker Hub | AWS ECR |
| Unnecessary packages | curl, vim, wget, SSH | None |
| Permissions | Implicit | Explicit declaration |
| Artifacts | None | SBOM + scan results |

---

## Testing Performed

1. Built Dockerfile locally, verified image size and layers
2. Ran Trivy scan against the built image
3. Tested GitHub Actions workflow structure (syntax validation)
4. Verified OIDC role assumption syntax
5. Confirmed secrets are not exposed in logs
6. Validated non-root user creation and permissions
