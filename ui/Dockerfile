# Shift Gear UI — built in-cluster (oc start-build shift-gear-ui --from-archive=-)
# Multi-stage build. Stage 1: build Nuxt app. Stage 2: run minimal image.
# Lessons applied:
#   - xattr -rc + COPYFILE_DISABLE=1 in make ui-build before archiving
#   - ._* in .dockerignore
#   - liveness: node -e "fetch('http://localhost:3000/api/health')"
#   - USER 1001 for OpenShift arbitrary UID policy
FROM docker.io/library/node:24-slim@sha256:a5f4366e834695d5f363b920c104953a535d3a9864d1bdf74566a0ebe01daee5 AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# BUILD_DIGEST is injected by the Ansible sg_ux role.
ARG BUILD_DIGEST=dev
ARG BUILD_TIMESTAMP
ENV NUXT_BUILD_DIGEST=${BUILD_DIGEST} NUXT_BUILD_TIMESTAMP=${BUILD_TIMESTAMP}
# nuxt prepare generates .nuxt/ type stubs required for the TypeScript build.
RUN npx nuxt prepare && npx nuxt build

FROM docker.io/library/node:24-slim@sha256:a5f4366e834695d5f363b920c104953a535d3a9864d1bdf74566a0ebe01daee5
WORKDIR /app
COPY --from=build /src/.output ./.output
USER 1001
ENV NODE_ENV=production PORT=3000 HOST=0.0.0.0
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s \
  CMD node -e "fetch('http://localhost:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", ".output/server/index.mjs"]
