# Tools for the backup scripts (civora-org/civora-platform#167): age for
# encryption, rclone for the S3-compatible off-site copy. Built on demand by
# scripts/lib/backup_env.sh when the host has no age/rclone of its own, so the
# only host requirement is Docker. Pinned base; versions come from the Alpine
# release, bump the base deliberately.
FROM alpine:3.22
RUN apk add --no-cache age rclone ca-certificates
# No default entrypoint: the scripts call `age` and `rclone` explicitly.
