# Job Tracker

A full-stack job-application tracker (Next.js + Node/Express + PostgreSQL), built to be deployed on AWS with a custom VPC, ECS Fargate behind an Application Load Balancer, RDS in private subnets, Secrets Manager, and least-privilege IAM — all defined in Terraform.

> Status: local app complete. AWS infrastructure (Terraform) in progress.

## Architecture (target)

```
Internet ──► ALB (public subnets)
              ├── /api/*  ──► backend  (ECS Fargate) ──► RDS PostgreSQL (private subnets, no public access)
              └── /*      ──► frontend (ECS Fargate)
Images: ECR · Secrets: Secrets Manager (injected by ECS) · Logs: CloudWatch
```

## Run locally

Requirements: Docker Desktop (running).

```bash
cp .env.example .env        # then edit DB_PASSWORD
docker compose up --build
```

- App: http://localhost:3000
- API health: http://localhost:4000/api/health · DB check: http://localhost:4000/api/health/db

Stop with `Ctrl+C`; `docker compose down -v` also deletes the local database.

## API

| Method | Path | Description |
|---|---|---|
| GET | `/api/applications?status=` | List (optional status filter) |
| GET | `/api/applications/:id` | Get one |
| POST | `/api/applications` | Create (`company`, `role` required) |
| PATCH | `/api/applications/:id` | Update any fields |
| DELETE | `/api/applications/:id` | Delete |

Statuses: `wishlist`, `applied`, `interviewing`, `offer`, `rejected`.

## Design decisions

- **Secrets are injected, not fetched.** ECS reads the DB credentials from Secrets Manager and passes them as environment variables at container start, so the application's task role needs no Secrets Manager permissions.
- **TLS to RDS is verified** against the Amazon RDS CA bundle baked into the backend image.
- **Liveness vs. readiness:** `/api/health` (ALB health check) doesn't touch the DB, so a DB blip doesn't cause the ALB to cycle healthy containers; `/api/health/db` checks connectivity.
- **Containers run as non-root** and shut down gracefully on `SIGTERM` (what ECS sends during deploys).
