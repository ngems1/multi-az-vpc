# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-28

### Added
- Multi-AZ VPC (2–6 AZs) with public and private subnets, computed or explicit CIDRs.
- Internet gateway, a shared public route table, and per-AZ private route tables.
- NAT gateway modes `per_az`, `single` and `none`, defaulting by environment.
- S3 gateway endpoint and ECR (`ecr.api`, `ecr.dkr`) interface endpoints, plus any extra interface endpoints.
- VPC Flow Logs to CloudWatch with a least-privilege IAM role and optional KMS key.
- Locked-down default security group.
- `examples/complete` with dev/stage/prod var files and a sample S3 backend.
- Mocked `terraform test` suite, TFLint, Checkov, pre-commit and GitHub Actions CI.
