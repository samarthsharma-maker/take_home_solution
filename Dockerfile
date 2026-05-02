# Fixed Dockerfile with security best practices

# Use specific version instead of latest
FROM node:20-alpine

WORKDIR /app

# Use .dockerignore to exclude unnecessary files
COPY package*.json ./

# Install dependencies with cache optimization
RUN npm install --omit=dev

# Copy application code
COPY . .

# Do NOT store secrets in ENV variables
# Secrets should be passed at runtime via environment or secrets management

# Do NOT install unnecessary tools (removed curl, vim, wget)
# Remove the extra EXPOSE 22 for SSH

EXPOSE 3000

# Run as non-root user for better security
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001

USER nodejs

CMD ["node", "server.js"]
